defmodule Keepling.ArchitectureTest do
  use ExUnit.Case, async: false

  @semantic_roots ["lib/keepling/domain/**/*.ex", "lib/keepling/application/**/*.ex"]
  @forbidden_prefixes [
    "Phoenix",
    "Plug",
    "Ecto",
    "Keepling.Repo",
    "KeeplingWeb",
    "Keepling.Adapters.Postgres",
    "Keepling.Generated",
    "Keepling.MCP",
    "React",
    "Electron",
    "SQLite",
    "SwiftUI"
  ]

  test "domain and semantic application sources have no outward dependencies" do
    violations =
      @semantic_roots
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> forbidden_references()
        |> Enum.map(&{path, &1})
      end)

    assert violations == []
  end

  test "the dependency guard rejects every prohibited boundary family" do
    for forbidden <- @forbidden_prefixes do
      source = "defmodule Keepling.Domain.Invalid do\n  alias #{forbidden}\nend"
      assert forbidden in forbidden_references(source)
    end
  end

  test "independent database connections pause and release at one barrier" do
    barrier = Keepling.ConcurrencyCase.start_barrier(2)
    parent = self()

    left =
      Task.async(fn ->
        Keepling.ConcurrencyCase.with_connection(fn backend_pid ->
          send(parent, {:checked_out, :left, backend_pid})
          :ok = Keepling.ConcurrencyCase.await(barrier)
          send(parent, {:released, :left})
          backend_pid
        end)
      end)

    assert_receive {:checked_out, :left, left_backend}
    refute_receive {:released, :left}, 50

    right =
      Task.async(fn ->
        Keepling.ConcurrencyCase.with_connection(fn backend_pid ->
          send(parent, {:checked_out, :right, backend_pid})
          :ok = Keepling.ConcurrencyCase.await(barrier)
          send(parent, {:released, :right})
          backend_pid
        end)
      end)

    assert_receive {:checked_out, :right, right_backend}
    assert_receive {:released, :left}
    assert_receive {:released, :right}
    assert Task.await(left) == left_backend
    assert Task.await(right) == right_backend
    refute left_backend == right_backend
  end

  test "the test clock deterministically supplies time and identities" do
    now = ~U[2026-08-30 12:00:00.000000Z]
    clock = Keepling.TestClock.new(now, ["task-1", "mutation-1"])

    assert Keepling.TestClock.now(clock) == now
    assert {"task-1", clock} = Keepling.TestClock.next_id(clock)
    assert {"mutation-1", clock} = Keepling.TestClock.next_id(clock)

    assert Keepling.TestClock.now(Keepling.TestClock.advance(clock, 90, :second)) ==
             ~U[2026-08-30 12:01:30.000000Z]
  end

  defp forbidden_references(source) do
    {:ok, quoted} = Code.string_to_quoted(source)

    {_quoted, references} =
      Macro.prewalk(quoted, MapSet.new(), fn
        {:__aliases__, _meta, parts} = node, acc ->
          {node, MapSet.put(acc, Module.concat(parts) |> inspect())}

        node, acc ->
          {node, acc}
      end)

    references
    |> Enum.filter(fn reference ->
      Enum.any?(@forbidden_prefixes, fn prefix ->
        reference == prefix or String.starts_with?(reference, prefix <> ".")
      end)
    end)
    |> Enum.sort()
  end
end
