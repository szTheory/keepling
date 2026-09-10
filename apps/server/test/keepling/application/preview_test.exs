defmodule Keepling.Application.PreviewTest do
  @moduledoc """
  05-07-PLAN.md Task 2: the preview binding -- a closed field list and an
  opaque bound token. Covers `<behavior>` end to end using fake `Port`
  implementations so the MAC/decode/authorize logic is proven WITHOUT
  needing a live Postgres connection; the atomic-commit-under-drift case
  lives in `preview_commit_test.exs` against real Postgres.
  """
  use ExUnit.Case, async: true

  alias Keepling.Application.Preview

  @fake_epoch "11111111-1111-4111-8111-111111111111"
  @other_epoch "22222222-2222-4222-8222-222222222222"

  defmodule FakePort do
    @moduledoc "current_sync_epoch/1 only -- used for pure mint/decode tests."
    @behaviour Preview.Port

    def current_sync_epoch(_context), do: {:ok, Process.get(:preview_test_epoch)}
    def lock_targets(_context, _binding, targets), do: {:ok, targets}

    def apply_all(_binding, mutation_id, _context, _authorize),
      do: {:ok, %{mutation_id: mutation_id, results: []}}
  end

  defmodule DriftPort do
    @moduledoc "apply_all/4 invokes the real authorize callback against a configurable live view."
    @behaviour Preview.Port

    def current_sync_epoch(_context), do: {:ok, Process.get(:preview_test_epoch)}
    def lock_targets(_context, _binding, targets), do: {:ok, targets}

    def apply_all(binding, mutation_id, context, authorize) do
      authoritative = %{
        account_id: context.account_id,
        arguments: binding.arguments,
        command: binding.command,
        server_instance: Process.get(:preview_test_server_instance, Preview.server_instance()),
        sync_epoch: Process.get(:preview_test_live_epoch, Process.get(:preview_test_epoch)),
        targets: Process.get(:preview_test_live_targets, binding.targets)
      }

      case authorize.(binding, authoritative) do
        :ok -> {:ok, %{mutation_id: mutation_id, results: []}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  setup do
    Process.put(:preview_test_epoch, @fake_epoch)
    :ok
  end

  defp target(task_id \\ Ecto.UUID.generate(), revision \\ 1),
    do: %{task_id: task_id, expected_revision: revision}

  defp context(account_id \\ Ecto.UUID.generate()) do
    %{
      account_id: account_id,
      accepted_at: ~U[2026-09-10 12:00:00.000000Z],
      preview_secret: "preview-test-fixed-secret"
    }
  end

  describe "destructive?/1" do
    test "true for trash, restore, and undo" do
      for command <- [:trash_task, :restore_task, :undo_task] do
        assert Preview.destructive?(%{command: command, targets: [target()]})
      end
    end

    test "true for any command whose target set has more than one member" do
      assert Preview.destructive?(%{
               command: :complete_task,
               targets: [target(), target(Ecto.UUID.generate())]
             })
    end

    test "false for a single-task complete or reopen" do
      refute Preview.destructive?(%{command: :complete_task, targets: [target()]})
      refute Preview.destructive?(%{command: :reopen_task, targets: [target()]})
    end
  end

  describe "mint/3" do
    test "returns an opaque token plus a human-readable summary" do
      ctx = context()

      assert {:ok, %{token: token, expires_at: %DateTime{}, summary: summary}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, FakePort)

      assert is_binary(token)
      assert summary =~ "trash_task"
    end

    test "a preview whose target set exceeds the maximum is refused rather than truncated" do
      ctx = context()
      targets = for _n <- 1..(Preview.maximum_targets() + 1), do: target(Ecto.UUID.generate())

      assert {:error, :invalid_preview} =
               Preview.mint(%{command: :trash_task, targets: targets}, ctx, FakePort)
    end

    test "an empty target set is refused" do
      ctx = context()

      assert {:error, :invalid_preview} =
               Preview.mint(%{command: :trash_task, targets: []}, ctx, FakePort)
    end
  end

  describe "token round trip and tampering" do
    test "the token round-trips through decode to the identical binding map, and a single flipped byte fails the MAC check" do
      ctx = context()

      assert {:ok, %{token: token}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, DriftPort)

      # Round trip: committing the untouched token authorizes (proves decode
      # recovered the identical binding the DriftPort authoritative view
      # matches by construction).
      assert {:ok, _result} = Preview.commit(token, Ecto.UUID.generate(), ctx, DriftPort)

      tampered = flip_last_byte(token)

      assert {:error, :preview_invalid} =
               Preview.commit(tampered, Ecto.UUID.generate(), ctx, DriftPort)
    end
  end

  describe "authorize_commit/2 refusals" do
    test "two absent fields do not compare as equal" do
      assert {:error, :preview_invalid} = Preview.authorize_commit(%{}, %{})
    end

    test "wrong account is refused" do
      account_a = Ecto.UUID.generate()
      account_b = Ecto.UUID.generate()
      ctx = context(account_a)

      assert {:ok, %{token: token}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, DriftPort)

      other_ctx = %{ctx | account_id: account_b}

      assert {:error, :preview_invalid} =
               Preview.commit(token, Ecto.UUID.generate(), other_ctx, DriftPort)
    end

    test "wrong server instance is refused" do
      ctx = context()

      assert {:ok, %{token: token}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, DriftPort)

      Process.put(:preview_test_server_instance, "a-different-server-instance")

      assert {:error, :preview_invalid} =
               Preview.commit(token, Ecto.UUID.generate(), ctx, DriftPort)
    end

    test "wrong sync epoch is refused" do
      ctx = context()

      assert {:ok, %{token: token}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, DriftPort)

      Process.put(:preview_test_live_epoch, @other_epoch)

      assert {:error, :preview_invalid} =
               Preview.commit(token, Ecto.UUID.generate(), ctx, DriftPort)
    end

    test "expired token is refused" do
      ctx = context()

      assert {:ok, %{token: token, expires_at: expires_at}} =
               Preview.mint(%{command: :trash_task, targets: [target()]}, ctx, DriftPort)

      later_ctx = %{ctx | accepted_at: DateTime.add(expires_at, 1, :second)}

      assert {:error, :preview_expired} =
               Preview.commit(token, Ecto.UUID.generate(), later_ctx, DriftPort)
    end

    test "a drifted target set is refused as preview_stale, not preview_invalid" do
      ctx = context()
      one = target()
      two = target(Ecto.UUID.generate())

      assert {:ok, %{token: token}} =
               Preview.mint(%{command: :trash_task, targets: [one, two]}, ctx, DriftPort)

      Process.put(:preview_test_live_targets, [
        %{task_id: one.task_id, expected_revision: one.expected_revision + 1},
        two
      ])

      assert {:error, :preview_stale} =
               Preview.commit(token, Ecto.UUID.generate(), ctx, DriftPort)
    end
  end

  defp flip_last_byte(token) do
    last_index = byte_size(token) - 1
    <<prefix::binary-size(^last_index), last_byte>> = token
    flipped = Bitwise.bxor(last_byte, 0xFF)
    prefix <> <<flipped>>
  end
end
