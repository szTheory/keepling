defmodule Keepling.Accounts.DeviceGrant do
  @moduledoc """
  Hash-only authorization-code and rotating refresh lineage for native public clients.

  Namespace authority is constructed exclusively from server configuration and the
  locked grant row. Native clients supply no secret and cannot assert an issuer,
  origin, server instance, account subject, or synchronization generation.
  """

  use Ecto.Schema

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.SecurityAudit
  alias Keepling.Repo

  @primary_key {:id, Ecto.UUID, autogenerate: true}
  @foreign_key_type Ecto.UUID

  @authorization_code_ttl_seconds 10 * 60
  @access_ttl_seconds 15 * 60
  @refresh_inactivity_ttl_seconds 30 * 24 * 60 * 60
  @family_absolute_ttl_seconds 90 * 24 * 60 * 60
  @client_kinds ~w(electron iphone)

  schema "device_grants" do
    field :installation_id, :string
    field :label, :string
    field :client_kind, :string
    field :redirect_uri, :string
    field :authorization_code_hash, :binary, redact: true
    field :authorization_code_expires_at, :utc_datetime_usec
    field :authorization_code_consumed_at, :utc_datetime_usec
    field :state_hash, :binary, redact: true
    field :pkce_challenge, :string, redact: true
    field :access_token_hash, :binary, redact: true
    field :access_expires_at, :utc_datetime_usec
    field :refresh_inactivity_expires_at, :utc_datetime_usec
    field :family_absolute_expires_at, :utc_datetime_usec
    field :generation, :integer
    field :last_refreshed_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :account, Keepling.Accounts.Account

    timestamps(type: :utc_datetime_usec)
  end

  @spec issue(binary(), map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def issue(account_id, params, opts \\ [])

  def issue(account_id, params, opts) when is_binary(account_id) and is_map(params) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> truncate_utc!()

    with {:ok, request} <- validate_authorization_request(params),
         {:ok, _namespace_config} <- namespace_config(),
         code <- random_token(),
         grant_id <- Ecto.UUID.generate() |> Ecto.UUID.dump!(),
         code_hash <- hash_token(code),
         state_hash <- hash_token(request.state),
         code_expires_at <- DateTime.add(now, @authorization_code_ttl_seconds, :second),
         family_expires_at <- DateTime.add(now, @family_absolute_ttl_seconds, :second),
         {:ok, _result} <-
           Repo.transact(fn repo ->
             SQL.query!(
               repo,
               """
               INSERT INTO device_grants (
                 id, account_id, installation_id, label, client_kind, redirect_uri,
                 authorization_code_hash, authorization_code_expires_at, state_hash,
                 pkce_challenge, family_absolute_expires_at, generation,
                 inserted_at, updated_at
               )
               VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 1, $12, $12)
               """,
               [
                 grant_id,
                 account_id,
                 request.installation_id,
                 request.label,
                 request.client_kind,
                 request.redirect_uri,
                 code_hash,
                 code_expires_at,
                 state_hash,
                 request.code_challenge,
                 family_expires_at,
                 now
               ]
             )

             {:ok, :issued}
           end) do
      {:ok, %{code: code, expires_at: code_expires_at, state: request.state}}
    else
      {:error, reason}
      when reason in [
             :invalid_client_kind,
             :invalid_code_challenge,
             :invalid_installation,
             :invalid_authorization_request,
             :invalid_redirect_uri,
             :invalid_state
           ] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def issue(_account_id, _params, _opts), do: {:error, :invalid_installation}

  @spec exchange(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def exchange(params, opts \\ [])

  def exchange(params, opts) when is_map(params) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> truncate_utc!()

    with {:ok, request} <- validate_exchange_request(params),
         {:ok, config} <- namespace_config(),
         access_token <- random_token(),
         refresh_token <- random_token(),
         {:ok, grant} <-
           Repo.transact(fn repo ->
             exchange_locked(repo, request, access_token, refresh_token, config, now)
           end) do
      {:ok, grant}
    else
      {:error, :invalid_authorization_code} -> {:error, :invalid_authorization_code}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def exchange(_params, _opts), do: {:error, :invalid_authorization_code}

  @spec refresh(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def refresh(refresh_token, opts \\ [])

  def refresh(refresh_token, opts) when is_binary(refresh_token) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> truncate_utc!()

    with {:ok, config} <- namespace_config(),
         access_token <- random_token(),
         next_refresh_token <- random_token() do
      case Repo.transact(fn repo ->
             refresh_locked(
               repo,
               hash_token(refresh_token),
               access_token,
               next_refresh_token,
               config,
               now
             )
           end) do
        {:ok, {:error, reason}} -> {:error, reason}
        {:ok, result} -> {:ok, result}
        {:error, reason} when reason in [:invalid_refresh_token] -> {:error, reason}
        {:error, _reason} -> {:error, :infrastructure_failure}
      end
    else
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def refresh(_refresh_token, _opts), do: {:error, :invalid_refresh_token}

  @spec authenticate_access(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def authenticate_access(access_token, opts \\ [])

  def authenticate_access(access_token, opts) when is_binary(access_token) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> truncate_utc!()

    with {:ok, config} <- namespace_config(),
         {:ok, %{rows: [row]}} <-
           SQL.query(
             Repo,
             """
             SELECT id, account_id, generation
             FROM device_grants
             WHERE access_token_hash = $1
               AND access_expires_at > $2
               AND revoked_at IS NULL
             """,
             [hash_token(access_token), now]
           ) do
      [grant_id, account_id, generation] = row

      {:ok,
       %{
         grant_id: uuid_string(grant_id),
         namespace: namespace(config, account_id, generation)
       }}
    else
      {:ok, %{rows: []}} -> {:error, :authentication_required}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def authenticate_access(_access_token, _opts), do: {:error, :authentication_required}

  @spec revoke(binary(), String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def revoke(account_id, grant_id, opts \\ [])

  def revoke(account_id, grant_id, opts)
      when is_binary(account_id) and is_binary(grant_id) do
    now = opts |> Keyword.get(:now, DateTime.utc_now()) |> truncate_utc!()

    with {:ok, dumped_grant_id} <- Ecto.UUID.dump(grant_id),
         {:ok, result} <-
           Repo.transact(fn repo ->
             case SQL.query!(
                    repo,
                    """
                    UPDATE device_grants
                    SET revoked_at = $3, generation = generation + 1,
                        access_token_hash = NULL, access_expires_at = NULL, updated_at = $3
                    WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
                    RETURNING id
                    """,
                    [dumped_grant_id, account_id, now]
                  ).rows do
               [[_id]] ->
                 SecurityAudit.record_required!(repo, "device_grant_revoked", now)
                 {:ok, %{status: "device_grant_revoked"}}

               [] ->
                 {:error, :device_grant_not_found}
             end
           end) do
      {:ok, result}
    else
      :error -> {:error, :device_grant_not_found}
      {:error, :device_grant_not_found} -> {:error, :device_grant_not_found}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def revoke(_account_id, _grant_id, _opts), do: {:error, :device_grant_not_found}

  @spec list(binary()) :: [map()]
  def list(account_id) when is_binary(account_id) do
    %{rows: rows} =
      SQL.query!(
        Repo,
        """
        SELECT id, installation_id, label, client_kind, generation, revoked_at
        FROM device_grants
        WHERE account_id = $1
        ORDER BY installation_id, inserted_at, id
        """,
        [account_id]
      )

    Enum.map(rows, fn [id, installation_id, label, client_kind, generation, revoked_at] ->
      %{
        client_kind: client_kind,
        generation: generation,
        id: uuid_string(id),
        installation_id: installation_id,
        label: label,
        revoked?: revoked_at != nil
      }
    end)
  end

  def list(_account_id), do: []

  defp exchange_locked(repo, request, access_token, refresh_token, config, now) do
    case SQL.query!(
           repo,
           """
           SELECT id, account_id, redirect_uri, state_hash, pkce_challenge,
                  authorization_code_expires_at, family_absolute_expires_at, generation
           FROM device_grants
           WHERE authorization_code_hash = $1
             AND authorization_code_consumed_at IS NULL
             AND revoked_at IS NULL
           FOR UPDATE
           """,
           [hash_token(request.code)]
         ).rows do
      [
        [
          grant_id,
          account_id,
          redirect_uri,
          state_hash,
          pkce_challenge,
          code_expires_at,
          family_expires_at,
          generation
        ]
      ] ->
        valid? =
          DateTime.compare(as_utc(code_expires_at), now) == :gt and
            DateTime.compare(as_utc(family_expires_at), now) == :gt and
            secure_equal?(redirect_uri, request.redirect_uri) and
            secure_equal?(state_hash, hash_token(request.state)) and
            secure_equal?(pkce_challenge, pkce_challenge(request.code_verifier))

        if valid? do
          access_expires_at = DateTime.add(now, @access_ttl_seconds, :second)

          refresh_expires_at =
            min_datetime(
              DateTime.add(now, @refresh_inactivity_ttl_seconds, :second),
              as_utc(family_expires_at)
            )

          SQL.query!(
            repo,
            """
            UPDATE device_grants
            SET authorization_code_consumed_at = $2,
                access_token_hash = $3, access_expires_at = $4,
                refresh_inactivity_expires_at = $5, last_refreshed_at = $2,
                updated_at = $2
            WHERE id = $1
            """,
            [grant_id, now, hash_token(access_token), access_expires_at, refresh_expires_at]
          )

          insert_refresh_token(repo, grant_id, refresh_token, now, refresh_expires_at)
          SecurityAudit.record_required!(repo, "device_grant_issued", now)

          {:ok,
           grant_result(
             grant_id,
             account_id,
             generation,
             access_token,
             refresh_token,
             access_expires_at,
             refresh_expires_at,
             as_utc(family_expires_at),
             config
           )}
        else
          {:error, :invalid_authorization_code}
        end

      [] ->
        {:error, :invalid_authorization_code}
    end
  end

  defp refresh_locked(repo, token_hash, access_token, next_refresh_token, config, now) do
    case SQL.query!(
           repo,
           """
           SELECT r.id, r.grant_id, r.expires_at, r.consumed_at,
                  g.account_id, g.generation, g.refresh_inactivity_expires_at,
                  g.family_absolute_expires_at, g.revoked_at
           FROM device_grant_refresh_tokens r
           JOIN device_grants g ON g.id = r.grant_id
           WHERE r.token_hash = $1
           FOR UPDATE OF r, g
           """,
           [token_hash]
         ).rows do
      [
        [
          _token_id,
          grant_id,
          _expires_at,
          consumed_at,
          _account_id,
          _generation,
          _idle,
          _absolute,
          revoked_at
        ]
      ]
      when consumed_at != nil ->
        if revoked_at == nil, do: revoke_replayed_family(repo, grant_id, now)
        {:ok, {:error, :refresh_replay_detected}}

      [
        [
          _token_id,
          _grant_id,
          _expires_at,
          nil,
          _account_id,
          _generation,
          _idle,
          _absolute,
          revoked_at
        ]
      ]
      when revoked_at != nil ->
        {:error, :invalid_refresh_token}

      [
        [
          token_id,
          grant_id,
          token_expires_at,
          nil,
          account_id,
          generation,
          idle_expires_at,
          family_expires_at,
          nil
        ]
      ] ->
        token_expires_at = as_utc(token_expires_at)
        idle_expires_at = as_utc(idle_expires_at)
        family_expires_at = as_utc(family_expires_at)

        if Enum.all?([token_expires_at, idle_expires_at, family_expires_at], fn expiry ->
             DateTime.compare(expiry, now) == :gt
           end) do
          access_expires_at = DateTime.add(now, @access_ttl_seconds, :second)

          refresh_expires_at =
            min_datetime(
              DateTime.add(now, @refresh_inactivity_ttl_seconds, :second),
              family_expires_at
            )

          SQL.query!(
            repo,
            "UPDATE device_grant_refresh_tokens SET consumed_at = $2 WHERE id = $1",
            [token_id, now]
          )

          SQL.query!(
            repo,
            """
            UPDATE device_grants
            SET access_token_hash = $2, access_expires_at = $3,
                refresh_inactivity_expires_at = $4, last_refreshed_at = $5,
                updated_at = $5
            WHERE id = $1
            """,
            [grant_id, hash_token(access_token), access_expires_at, refresh_expires_at, now]
          )

          insert_refresh_token(repo, grant_id, next_refresh_token, now, refresh_expires_at)
          SecurityAudit.record_required!(repo, "device_grant_refreshed", now)

          {:ok,
           grant_result(
             grant_id,
             account_id,
             generation,
             access_token,
             next_refresh_token,
             access_expires_at,
             refresh_expires_at,
             family_expires_at,
             config
           )}
        else
          revoke_expired_family(repo, grant_id, now)
          {:ok, {:error, :refresh_expired}}
        end

      [] ->
        {:error, :invalid_refresh_token}
    end
  end

  defp insert_refresh_token(repo, grant_id, token, issued_at, expires_at) do
    SQL.query!(
      repo,
      """
      INSERT INTO device_grant_refresh_tokens (
        grant_id, token_hash, issued_at, expires_at, inserted_at
      )
      VALUES ($1, $2, $3, $4, $3)
      """,
      [grant_id, hash_token(token), issued_at, expires_at]
    )
  end

  defp revoke_replayed_family(repo, grant_id, now) do
    SQL.query!(
      repo,
      """
      UPDATE device_grants
      SET revoked_at = COALESCE(revoked_at, $2), generation = generation + 1,
          access_token_hash = NULL, access_expires_at = NULL, updated_at = $2
      WHERE id = $1
      """,
      [grant_id, now]
    )

    SecurityAudit.record_required!(repo, "device_grant_replay_revoked", now)
  end

  defp revoke_expired_family(repo, grant_id, now) do
    SQL.query!(
      repo,
      """
      UPDATE device_grants
      SET revoked_at = COALESCE(revoked_at, $2), generation = generation + 1,
          access_token_hash = NULL, access_expires_at = NULL, updated_at = $2
      WHERE id = $1
      """,
      [grant_id, now]
    )
  end

  defp grant_result(
         grant_id,
         account_id,
         generation,
         access_token,
         refresh_token,
         access_expires_at,
         refresh_expires_at,
         family_expires_at,
         config
       ) do
    %{
      access_expires_at: access_expires_at,
      access_token: access_token,
      family_absolute_expires_at: family_expires_at,
      id: uuid_string(grant_id),
      namespace: namespace(config, account_id, generation),
      refresh_inactivity_expires_at: refresh_expires_at,
      refresh_token: refresh_token
    }
  end

  defp namespace(config, account_id, generation) do
    %{
      generation: generation,
      issuer: config.issuer,
      origin: config.origin,
      server_instance: config.server_instance,
      subject: uuid_string(account_id)
    }
  end

  defp validate_authorization_request(params) do
    allowed_keys = [
      :client_kind,
      :code_challenge,
      :code_challenge_method,
      :installation_id,
      :label,
      :redirect_uri,
      :state
    ]

    with :ok <- validate_exact_keys(params, allowed_keys, :invalid_authorization_request),
         {:ok, client_kind} <- required_binary(params, :client_kind, :invalid_client_kind),
         true <- client_kind in @client_kinds,
         {:ok, installation_id} <- required_bounded_binary(params, :installation_id, 200),
         {:ok, label} <- required_bounded_binary(params, :label, 200),
         {:ok, redirect_uri} <- required_binary(params, :redirect_uri, :invalid_redirect_uri),
         true <- allowed_redirect?(client_kind, redirect_uri),
         {:ok, state} <- required_binary(params, :state, :invalid_state),
         true <- unpredictable_state?(state),
         {:ok, method} <- required_binary(params, :code_challenge_method, :invalid_code_challenge),
         true <- method == "S256",
         {:ok, code_challenge} <-
           required_binary(params, :code_challenge, :invalid_code_challenge),
         true <- valid_code_challenge?(code_challenge) do
      {:ok,
       %{
         client_kind: client_kind,
         code_challenge: code_challenge,
         installation_id: installation_id,
         label: label,
         redirect_uri: redirect_uri,
         state: state
       }}
    else
      {:error, reason} -> {:error, reason}
      false -> authorization_request_error(params)
    end
  end

  defp validate_exchange_request(params) do
    with :ok <-
           validate_exact_keys(
             params,
             [:code, :code_verifier, :redirect_uri, :state],
             :invalid_authorization_code
           ),
         {:ok, code} <- required_binary(params, :code, :invalid_authorization_code),
         {:ok, state} <- required_binary(params, :state, :invalid_authorization_code),
         {:ok, redirect_uri} <-
           required_binary(params, :redirect_uri, :invalid_authorization_code),
         {:ok, verifier} <- required_binary(params, :code_verifier, :invalid_authorization_code),
         true <- valid_code_verifier?(verifier) do
      {:ok, %{code: code, state: state, redirect_uri: redirect_uri, code_verifier: verifier}}
    else
      _ -> {:error, :invalid_authorization_code}
    end
  end

  defp authorization_request_error(params) do
    cond do
      Map.get(params, :client_kind) not in @client_kinds ->
        {:error, :invalid_client_kind}

      not allowed_redirect?(Map.get(params, :client_kind), Map.get(params, :redirect_uri)) ->
        {:error, :invalid_redirect_uri}

      not unpredictable_state?(Map.get(params, :state)) ->
        {:error, :invalid_state}

      true ->
        {:error, :invalid_code_challenge}
    end
  end

  defp required_binary(params, key, reason) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, reason}
    end
  end

  defp validate_exact_keys(params, allowed_keys, reason) do
    if Enum.sort(Map.keys(params)) == Enum.sort(allowed_keys), do: :ok, else: {:error, reason}
  end

  defp required_bounded_binary(params, key, maximum) do
    with {:ok, value} <- required_binary(params, key, :invalid_installation),
         true <- byte_size(value) <= maximum do
      {:ok, value}
    else
      _ -> {:error, :invalid_installation}
    end
  end

  defp namespace_config do
    config = Application.get_env(:keepling, :device_grants, [])

    with issuer when is_binary(issuer) and byte_size(issuer) > 0 <- Keyword.get(config, :issuer),
         origin when is_binary(origin) and byte_size(origin) > 0 <- Keyword.get(config, :origin),
         server when is_binary(server) and byte_size(server) > 0 <-
           Keyword.get(config, :server_instance) do
      {:ok, %{issuer: issuer, origin: origin, server_instance: server}}
    else
      _ -> {:error, :device_grant_configuration_missing}
    end
  end

  defp allowed_redirect?(client_kind, redirect_uri)
       when client_kind in @client_kinds and is_binary(redirect_uri) do
    redirects =
      :keepling
      |> Application.get_env(:device_grants, [])
      |> Keyword.get(:redirect_uris, %{})

    redirect_uri in Map.get(redirects, client_kind, [])
  end

  defp allowed_redirect?(_client_kind, _redirect_uri), do: false

  defp unpredictable_state?(state) when is_binary(state) do
    case Base.url_decode64(state, padding: false) do
      {:ok, decoded} -> byte_size(decoded) >= 32
      :error -> false
    end
  end

  defp unpredictable_state?(_state), do: false

  defp valid_code_challenge?(challenge) when is_binary(challenge) do
    case Base.url_decode64(challenge, padding: false) do
      {:ok, decoded} -> byte_size(decoded) == 32
      :error -> false
    end
  end

  defp valid_code_verifier?(verifier) when is_binary(verifier) do
    byte_size(verifier) in 43..128 and String.match?(verifier, ~r/^[A-Za-z0-9._~-]+$/)
  end

  defp pkce_challenge(verifier) do
    :sha256
    |> :crypto.hash(verifier)
    |> Base.url_encode64(padding: false)
  end

  defp secure_equal?(left, right) when is_binary(left) and is_binary(right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secure_equal?(_left, _right), do: false

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)

  defp min_datetime(left, right) do
    if DateTime.compare(left, right) == :gt, do: right, else: left
  end

  defp uuid_string(value) when is_binary(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp truncate_utc!(%DateTime{} = value),
    do: value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)

  defp as_utc(%DateTime{} = value), do: value
  defp as_utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
