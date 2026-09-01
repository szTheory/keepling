defmodule Keepling.Accounts.DeviceGrantTest do
  use Keepling.DataCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Repo

  @now ~U[2026-09-01 12:00:00.000000Z]
  @redirect_uri "keepling://authorization/callback"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @state :crypto.hash(:sha256, "synthetic-state") |> Base.url_encode64(padding: false)

  @vectors_path Path.expand(
                  "../../../../../packages/contracts/vectors/account-lifecycle.json",
                  __DIR__
                )

  setup tags do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-fixed",
      redirect_uris: %{"electron" => [@redirect_uri], "iphone" => [@redirect_uri]}
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    unless tags[:vectors] do
      SQL.query!(Repo, "DELETE FROM account_security_audits", [])
      SQL.query!(Repo, "DELETE FROM accounts", [])
    end

    :ok
  end

  @tag :vectors
  test "account lifecycle vectors fence every namespace and preserve recoverable intent" do
    vectors = @vectors_path |> File.read!() |> Jason.decode!()

    schema =
      @vectors_path
      |> Path.join("../../schemas/account-lifecycle.schema.json")
      |> Path.expand()
      |> File.read!()
      |> Jason.decode!()

    assert vectors["version"] == 1
    assert vectors["$schema"] == "../schemas/account-lifecycle.schema.json"
    assert schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
    assert schema["additionalProperties"] == false
    assert schema["$defs"]["action"]["oneOf"] |> length() == 18

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
      actual = Enum.reduce(vector["actions"], initial_state(vector), &apply_lifecycle_action/2)

      assert project(actual) == vector["expect"], vector["name"]
    end
  end

  @tag :vectors
  test "account lifecycle runner rejects unknown actions" do
    assert_raise ArgumentError, ~r/unknown account lifecycle action/, fn ->
      apply_lifecycle_action(%{"type" => "cross_drain"}, initial_state(%{}))
    end
  end

  test "authorization exchange validates exact redirect, state, and S256 PKCE and stores only hashes" do
    account_id = create_account()

    assert {:error, :invalid_authorization_request} =
             Accounts.issue_device_authorization(
               account_id,
               authorization_request("installation-a", "electron")
               |> Map.put(:client_secret, "must-not-be-accepted"),
               now: @now
             )

    assert {:error, :invalid_authorization_request} =
             Accounts.issue_device_authorization(
               account_id,
               authorization_request("installation-a", "electron")
               |> Map.put(:issuer, "https://client-asserted.invalid"),
               now: @now
             )

    assert {:ok, authorization} =
             Accounts.issue_device_authorization(
               account_id,
               authorization_request("installation-a", "electron"),
               now: @now
             )

    assert is_binary(authorization.code)
    assert authorization.state == @state
    assert authorization.expires_at == DateTime.add(@now, 600, :second)

    assert {:error, :invalid_authorization_code} =
             Accounts.exchange_device_authorization(
               exchange_request(authorization.code, redirect_uri: "keepling://wrong/callback"),
               now: DateTime.add(@now, 1, :second)
             )

    assert {:error, :invalid_authorization_code} =
             Accounts.exchange_device_authorization(
               exchange_request(authorization.code, state: @state <> "changed"),
               now: DateTime.add(@now, 1, :second)
             )

    assert {:error, :invalid_authorization_code} =
             Accounts.exchange_device_authorization(
               exchange_request(authorization.code, code_verifier: String.duplicate("x", 64)),
               now: DateTime.add(@now, 1, :second)
             )

    assert {:ok, grant} =
             Accounts.exchange_device_authorization(
               exchange_request(authorization.code),
               now: DateTime.add(@now, 1, :second)
             )

    assert grant.access_expires_at == DateTime.add(@now, 901, :second)
    assert grant.refresh_inactivity_expires_at == DateTime.add(@now, 2_592_001, :second)
    assert grant.family_absolute_expires_at == DateTime.add(@now, 7_776_000, :second)
    assert byte_size(Base.url_decode64!(grant.access_token, padding: false)) == 32
    assert byte_size(Base.url_decode64!(grant.refresh_token, padding: false)) == 32

    assert grant.namespace == %{
             generation: 1,
             issuer: "https://issuer.keepling.invalid",
             origin: "https://server.keepling.invalid",
             server_instance: "server-instance-fixed",
             subject: Ecto.UUID.load!(account_id)
           }

    assert %{rows: [[code_hash, state_hash, access_hash, refresh_hash, stored_json]]} =
             SQL.query!(
               Repo,
               """
               SELECT g.authorization_code_hash, g.state_hash, g.access_token_hash,
                      r.token_hash, row_to_json(g)::text || row_to_json(r)::text
               FROM device_grants g
               JOIN device_grant_refresh_tokens r ON r.grant_id = g.id
               WHERE g.id = $1
               """,
               [Ecto.UUID.dump!(grant.id)]
             )

    assert code_hash == :crypto.hash(:sha256, authorization.code)
    assert state_hash == :crypto.hash(:sha256, @state)
    assert access_hash == :crypto.hash(:sha256, grant.access_token)
    assert refresh_hash == :crypto.hash(:sha256, grant.refresh_token)
    refute stored_json =~ authorization.code
    refute stored_json =~ @state
    refute stored_json =~ @verifier
    refute stored_json =~ grant.access_token
    refute stored_json =~ grant.refresh_token
  end

  test "refresh rotation detects replay and atomically fences only that installation" do
    account_id = create_account()
    grant_a = authorize_and_exchange(account_id, "installation-a", "electron")
    grant_b = authorize_and_exchange(account_id, "installation-b", "iphone")

    assert {:ok, rotated} =
             Accounts.refresh_device_grant(grant_a.refresh_token,
               now: DateTime.add(@now, 60, :second)
             )

    refute rotated.refresh_token == grant_a.refresh_token
    assert rotated.namespace.generation == 1

    assert {:error, :refresh_replay_detected} =
             Accounts.refresh_device_grant(grant_a.refresh_token,
               now: DateTime.add(@now, 61, :second)
             )

    assert {:error, :refresh_replay_detected} =
             Accounts.refresh_device_grant(grant_a.refresh_token,
               now: DateTime.add(@now, 62, :second)
             )

    assert {:error, :authentication_required} =
             Accounts.authenticate_device_access(rotated.access_token,
               now: DateTime.add(@now, 63, :second)
             )

    assert {:ok, authenticated_b} =
             Accounts.authenticate_device_access(grant_b.access_token,
               now: DateTime.add(@now, 63, :second)
             )

    assert authenticated_b.grant_id == grant_b.id
    assert authenticated_b.namespace.generation == 1

    assert %{rows: [[revoked_a, generation_a, revoked_b, generation_b]]} =
             SQL.query!(
               Repo,
               """
               SELECT a.revoked_at, a.generation, b.revoked_at, b.generation
               FROM device_grants a, device_grants b
               WHERE a.id = $1 AND b.id = $2
               """,
               [Ecto.UUID.dump!(grant_a.id), Ecto.UUID.dump!(grant_b.id)]
             )

    assert revoked_a != nil
    assert generation_a == 2
    assert revoked_b == nil
    assert generation_b == 1
  end

  test "access expiry and explicit revocation use stable bounded outcomes" do
    account_id = create_account()
    grant_a = authorize_and_exchange(account_id, "installation-a", "electron")
    grant_b = authorize_and_exchange(account_id, "installation-b", "iphone")

    assert {:error, :authentication_required} =
             Accounts.authenticate_device_access(grant_a.access_token,
               now: DateTime.add(@now, 902, :second)
             )

    assert {:ok, %{status: "device_grant_revoked"}} =
             Accounts.revoke_device_grant(account_id, grant_a.id,
               now: DateTime.add(@now, 120, :second)
             )

    assert {:error, :authentication_required} =
             Accounts.authenticate_device_access(grant_a.access_token,
               now: DateTime.add(@now, 121, :second)
             )

    assert {:ok, _authenticated} =
             Accounts.authenticate_device_access(grant_b.access_token,
               now: DateTime.add(@now, 121, :second)
             )

    assert [%{id: id, installation_id: "installation-a", revoked?: true}, %{revoked?: false}] =
             Accounts.list_device_grants(account_id)

    assert id == grant_a.id

    assert %{rows: [[events]]} =
             SQL.query!(
               Repo,
               "SELECT array_agg(event_type ORDER BY id) FROM account_security_audits",
               []
             )

    assert Enum.all?(
             events,
             &(&1 in ~w(device_grant_issued device_grant_refreshed device_grant_replay_revoked device_grant_revoked))
           )
  end

  defp authorize_and_exchange(account_id, installation_id, client_kind) do
    assert {:ok, authorization} =
             Accounts.issue_device_authorization(
               account_id,
               authorization_request(installation_id, client_kind),
               now: @now
             )

    assert {:ok, grant} =
             Accounts.exchange_device_authorization(exchange_request(authorization.code),
               now: DateTime.add(@now, 1, :second)
             )

    grant
  end

  defp authorization_request(installation_id, client_kind) do
    %{
      client_kind: client_kind,
      code_challenge: @challenge,
      code_challenge_method: "S256",
      installation_id: installation_id,
      label: "Synthetic installation",
      redirect_uri: @redirect_uri,
      state: @state
    }
  end

  defp exchange_request(code, overrides \\ []) do
    %{
      code: code,
      code_verifier: Keyword.get(overrides, :code_verifier, @verifier),
      redirect_uri: Keyword.get(overrides, :redirect_uri, @redirect_uri),
      state: Keyword.get(overrides, :state, @state)
    }
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, '$argon2id$synthetic-fixture', 'Etc/UTC', $2, $2)
      """,
      [account_id, @now]
    )

    account_id
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

  defp apply_lifecycle_action(
         %{"type" => "local_accept", "namespace" => key, "mutation" => mutation},
         state
       ) do
    update_namespace(state, key, fn namespace ->
      Map.update(namespace, "outbox", [mutation], &(&1 ++ [mutation]))
    end)
  end

  defp apply_lifecycle_action(%{"type" => "begin_logout"}, state) do
    state
    |> Map.put(:status, "fenced")
    |> quarantine_active()
  end

  defp apply_lifecycle_action(%{"type" => "revocation_uncertain"}, state) do
    state
    |> Map.put(:status, "sign_out_pending")
    |> Map.put(:recovery_actions, ["retry_revocation"])
  end

  defp apply_lifecycle_action(%{"type" => "revocation_confirmed"}, state) do
    state
    |> Map.put(:active_namespace, nil)
    |> Map.put(:status, "signed_out")
    |> Map.put(:recovery_actions, [])
  end

  defp apply_lifecycle_action(%{"type" => "relaunch"}, state), do: state

  defp apply_lifecycle_action(%{"type" => "authenticate", "namespace" => key}, state) do
    state =
      if state.active_namespace && state.active_namespace != key,
        do: quarantine_active(state),
        else: state

    namespace = Map.fetch!(state.namespaces, key)

    state
    |> Map.put(:active_namespace, key)
    |> Map.put(:status, if(namespace["quarantined"], do: "quarantined", else: "ready"))
    |> Map.put(:recovery_actions, [])
  end

  defp apply_lifecycle_action(%{"type" => "resume_same_namespace", "namespace" => key}, state) do
    if state.active_namespace == key do
      state
      |> update_namespace(key, &Map.put(&1, "quarantined", false))
      |> Map.put(:status, "ready")
    else
      quarantine_active(state)
    end
  end

  defp apply_lifecycle_action(%{"type" => "ready_pushes", "namespace" => key}, state) do
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

  defp apply_lifecycle_action(%{"type" => "late_acknowledgement", "namespace" => key}, state) do
    if state.status == "ready" and state.active_namespace == key do
      update_namespace(state, key, &Map.put(&1, "outbox", []))
    else
      quarantine_active(state)
    end
  end

  defp apply_lifecycle_action(%{"type" => "access_expired"}, state) do
    state
    |> Map.put(:status, "authentication_required")
    |> quarantine_active()
    |> Map.put(:recovery_actions, ["sign_in"])
  end

  defp apply_lifecycle_action(%{"type" => event}, state)
       when event in ["grant_revoked", "device_loss_revoked"] do
    state
    |> Map.put(:status, "permanent_authorization_loss")
    |> quarantine_active()
    |> Map.put(:recovery_actions, ["inspect", "export", "remove"])
  end

  defp apply_lifecycle_action(%{"type" => "request_local_removal"}, state) do
    namespace = Map.fetch!(state.namespaces, state.active_namespace)

    Map.put(state, :removal_prompt, %{
      "default" => "cancel",
      "unsynced_count" => length(namespace["outbox"] || []),
      "conflict_count" => length(namespace["conflicts"] || [])
    })
  end

  defp apply_lifecycle_action(%{"type" => "cancel_local_removal"}, state) do
    Map.put(state, :removal_prompt, nil)
  end

  defp apply_lifecycle_action(%{"type" => "confirm_local_removal"}, state) do
    state
    |> Map.put(:active_namespace, nil)
    |> Map.put(:namespaces, %{})
    |> Map.put(:recovery_actions, [])
    |> Map.put(:removal_prompt, nil)
    |> Map.put(:status, "local_data_removed")
  end

  defp apply_lifecycle_action(%{"type" => "dirty_draft", "count" => count}, state) do
    Map.put(state, :drafts, count)
  end

  defp apply_lifecycle_action(%{"type" => "begin_logout_with_draft"}, state) do
    state
    |> Map.put(:status, "draft_decision_required")
    |> Map.put(:recovery_actions, ["save", "discard", "keep_working"])
  end

  defp apply_lifecycle_action(%{"type" => unknown}, _state) do
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
