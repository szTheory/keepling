defmodule Keepling.Accounts.DeviceGrantTest do
  use ExUnit.Case, async: true

  @vectors_path Path.expand(
                  "../../../../../packages/contracts/vectors/account-lifecycle.json",
                  __DIR__
                )

  @tag :vectors
  test "account lifecycle vectors fence every namespace and preserve recoverable intent" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    assert vectors["version"] == 1
    assert vectors["namespace_fields"] == [
             "issuer",
             "origin",
             "server_instance",
             "subject",
             "generation"
           ]

    assert Enum.sort(vectors["covered_decisions"]) ==
             Enum.map(16..21, &"D-#{&1}")

    assert Enum.any?(vectors["cases"], &(&1["name"] == "account A to B to A"))
    assert Enum.any?(vectors["cases"], &(&1["name"] == "duplicate subject across servers"))
    assert Enum.any?(vectors["cases"], &(&1["name"] == "late acknowledgement after fencing"))
    assert Enum.any?(vectors["cases"], &(&1["name"] == "confirmed local removal"))

    for vector <- vectors["cases"] do
      actual = Enum.reduce(vector["actions"], initial_state(vector), &apply_action/2)

      assert project(actual) == vector["expect"], vector["name"]
    end
  end

  @tag :vectors
  test "account lifecycle runner rejects unknown actions" do
    assert_raise ArgumentError, ~r/unknown account lifecycle action/, fn ->
      apply_action(%{"type" => "cross_drain"}, initial_state(%{}))
    end
  end

  defp initial_state(vector) do
    %{
      active_namespace: vector["initial_namespace"],
      drafts: vector["initial_drafts"] || 0,
      namespaces: vector["initial_namespaces"] || %{},
      recovery_actions: [],
      removal_prompt: nil,
      status: "ready"
    }
  end

  defp apply_action(%{"type" => "local_accept", "namespace" => key, "mutation" => mutation}, state) do
    update_namespace(state, key, fn namespace ->
      Map.update(namespace, "outbox", [mutation], &(&1 ++ [mutation]))
    end)
  end

  defp apply_action(%{"type" => "begin_logout"}, state) do
    state
    |> Map.put(:status, "fenced")
    |> quarantine_active()
  end

  defp apply_action(%{"type" => "revocation_uncertain"}, state) do
    state
    |> Map.put(:status, "sign_out_pending")
    |> Map.put(:recovery_actions, ["retry_revocation"])
  end

  defp apply_action(%{"type" => "revocation_confirmed"}, state) do
    state
    |> Map.put(:active_namespace, nil)
    |> Map.put(:status, "signed_out")
    |> Map.put(:recovery_actions, [])
  end

  defp apply_action(%{"type" => "relaunch"}, state), do: state

  defp apply_action(%{"type" => "authenticate", "namespace" => key}, state) do
    namespace = Map.fetch!(state.namespaces, key)

    state
    |> Map.put(:active_namespace, key)
    |> Map.put(:status, if(namespace["quarantined"], do: "quarantined", else: "ready"))
    |> Map.put(:recovery_actions, [])
  end

  defp apply_action(%{"type" => "resume_same_namespace", "namespace" => key}, state) do
    if state.active_namespace == key do
      state
      |> update_namespace(key, &Map.put(&1, "quarantined", false))
      |> Map.put(:status, "ready")
    else
      quarantine_active(state)
    end
  end

  defp apply_action(%{"type" => "ready_pushes", "namespace" => key}, state) do
    namespace = Map.fetch!(state.namespaces, key)

    ready =
      if state.active_namespace == key and state.status == "ready" and
           not namespace["quarantined"] do
        namespace["outbox"] || []
      else
        []
      end

    Map.put(state, :ready_pushes, ready)
  end

  defp apply_action(%{"type" => "late_acknowledgement", "namespace" => key}, state) do
    if state.status == "ready" and state.active_namespace == key do
      update_namespace(state, key, &Map.put(&1, "outbox", []))
    else
      quarantine_active(state)
    end
  end

  defp apply_action(%{"type" => "access_expired"}, state) do
    state
    |> Map.put(:status, "authentication_required")
    |> quarantine_active()
    |> Map.put(:recovery_actions, ["sign_in"])
  end

  defp apply_action(%{"type" => event}, state)
       when event in ["grant_revoked", "device_loss_revoked"] do
    state
    |> Map.put(:status, "permanent_authorization_loss")
    |> quarantine_active()
    |> Map.put(:recovery_actions, ["inspect", "export", "remove"])
  end

  defp apply_action(%{"type" => "request_local_removal"}, state) do
    namespace = Map.fetch!(state.namespaces, state.active_namespace)

    Map.put(state, :removal_prompt, %{
      "default" => "cancel",
      "unsynced_count" => length(namespace["outbox"] || []),
      "conflict_count" => length(namespace["conflicts"] || [])
    })
  end

  defp apply_action(%{"type" => "cancel_local_removal"}, state) do
    Map.put(state, :removal_prompt, nil)
  end

  defp apply_action(%{"type" => "confirm_local_removal"}, state) do
    state
    |> Map.put(:active_namespace, nil)
    |> Map.put(:namespaces, %{})
    |> Map.put(:recovery_actions, [])
    |> Map.put(:removal_prompt, nil)
    |> Map.put(:status, "local_data_removed")
  end

  defp apply_action(%{"type" => "dirty_draft", "count" => count}, state) do
    Map.put(state, :drafts, count)
  end

  defp apply_action(%{"type" => "begin_logout_with_draft"}, state) do
    state
    |> Map.put(:status, "draft_decision_required")
    |> Map.put(:recovery_actions, ["save", "discard", "keep_working"])
  end

  defp apply_action(%{"type" => unknown}, _state) do
    raise ArgumentError, "unknown account lifecycle action: #{inspect(unknown)}"
  end

  defp quarantine_active(%{active_namespace: nil} = state), do: state

  defp quarantine_active(state) do
    update_namespace(state, state.active_namespace, &Map.put(&1, "quarantined", true))
  end

  defp update_namespace(state, key, fun) do
    update_in(state, [:namespaces, key], fn namespace -> fun.(namespace || %{}) end)
  end

  defp project(state) do
    %{
      "active_namespace" => state.active_namespace,
      "drafts" => state.drafts,
      "namespaces" => state.namespaces,
      "ready_pushes" => Map.get(state, :ready_pushes, []),
      "recovery_actions" => state.recovery_actions,
      "removal_prompt" => state.removal_prompt,
      "status" => state.status
    }
  end
end
