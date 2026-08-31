defmodule Keepling.Accounts do
  @moduledoc """
  Application seam for the closed personal account and its canonical settings.

  Operator tasks and transports call this module instead of mutating Ecto
  schemas directly. Raw bearer capabilities exist only in the caller and are
  represented by SHA-256 hashes in PostgreSQL.
  """

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.Account
  alias Keepling.Accounts.SecurityAudit
  alias Keepling.Repo

  @default_setup_ttl_seconds 900
  @minimum_setup_ttl_seconds 60
  @maximum_setup_ttl_seconds 3_600
  @minimum_password_bytes 12
  @maximum_password_bytes 1_024
  @default_idle_ttl_seconds 30 * 24 * 60 * 60
  @default_absolute_ttl_seconds 180 * 24 * 60 * 60
  @default_recent_auth_ttl_seconds 15 * 60
  @default_recovery_ttl_seconds 15 * 60
  @minimum_recovery_ttl_seconds 60
  @maximum_recovery_ttl_seconds 3_600
  @session_activity_write_interval_seconds 60 * 60
  @client_kinds ["web", "electron", "iphone", "mcp"]

  @spec issue_setup_token(keyword()) ::
          {:ok, %{token: String.t(), expires_at: DateTime.t()}}
          | {:error,
             :invalid_ttl | :setup_disabled | :setup_token_active | :infrastructure_failure}
  def issue_setup_token(opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_setup_ttl_seconds)

    with true <-
           is_integer(ttl_seconds) and
             ttl_seconds >= @minimum_setup_ttl_seconds and
             ttl_seconds <= @maximum_setup_ttl_seconds,
         token <- random_token(),
         token_hash <- hash_token(token),
         expires_at <- DateTime.add(now, ttl_seconds, :second),
         {:ok, result} <-
           Repo.transact(fn repo ->
             ensure_setup_row(repo, now)
             {:ok, issue_setup_token_locked(repo, token_hash, now, expires_at)}
           end) do
      case result do
        :issued -> {:ok, %{token: token, expires_at: expires_at}}
        {:error, reason} -> {:error, reason}
      end
    else
      false -> {:error, :invalid_ttl}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @spec consume_setup(map()) ::
          {:ok, %{timezone: String.t()}}
          | {:error,
             :invalid_password | :invalid_timezone | :setup_unavailable | :infrastructure_failure}
  def consume_setup(params) when is_map(params) do
    with {:ok, token} <- required_binary(params, :token),
         {:ok, password} <- valid_password(params),
         {:ok, timezone} <- valid_timezone(params),
         {:ok, accepted_at} <- valid_accepted_at(params),
         password_hash <- Argon2.hash_pwd_salt(password),
         token_hash <- hash_token(token),
         {:ok, result} <-
           Repo.transact(fn repo ->
             {:ok, consume_setup_locked(repo, token_hash, password_hash, timezone, accepted_at)}
           end) do
      result
    else
      {:error, reason}
      when reason in [:invalid_password, :invalid_timezone, :setup_unavailable] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def consume_setup(_params), do: {:error, :setup_unavailable}

  @doc """
  Authenticates the closed account and issues one opaque, hash-stored session.

  Failure is deliberately generic: callers cannot distinguish a missing account
  from a wrong password.
  """
  @spec login(String.t(), keyword()) ::
          {:ok, map()} | {:error, :authentication_failed | :infrastructure_failure}
  def login(password, opts \\ [])

  def login(password, opts) when is_binary(password) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    case SQL.query(
           Repo,
           "SELECT id, password_hash FROM accounts WHERE singleton_key = TRUE",
           []
         ) do
      {:ok, %{rows: [[account_id, password_hash]]}} ->
        cond do
          not login_password_valid?(password) ->
            Argon2.no_user_verify()
            record_security_audit(account_id, "login_failed", now)
            {:error, :authentication_failed}

          Argon2.verify_pass(password, password_hash) ->
            case create_login_session(account_id, Keyword.put(opts, :now, now), now) do
              {:ok, _session} = result ->
                result

              {:error, _reason} ->
                {:error, :infrastructure_failure}
            end

          true ->
            record_security_audit(account_id, "login_failed", now)
            {:error, :authentication_failed}
        end

      {:ok, %{rows: []}} ->
        Argon2.no_user_verify()
        {:error, :authentication_failed}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def login(_password, _opts) do
    Argon2.no_user_verify()
    {:error, :authentication_failed}
  end

  @doc "Creates a tracked session for an already authenticated account."
  @spec create_session(binary(), keyword()) :: {:ok, map()} | {:error, atom()}
  def create_session(account_id, opts \\ []) when is_binary(account_id) do
    with {:ok, session_params} <- session_params(opts),
         {:ok, session} <-
           Repo.transact(fn repo ->
             {:ok, insert_session(repo, account_id, session_params)}
           end) do
      {:ok, session}
    else
      {:error, reason} when reason in [:invalid_label, :invalid_client_kind, :invalid_expiry] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  defp create_login_session(account_id, opts, accepted_at) do
    with {:ok, session_params} <- session_params(opts),
         {:ok, session} <-
           Repo.transact(fn repo ->
             session = insert_session(repo, account_id, session_params)
             SecurityAudit.record_required!(repo, "login_succeeded", accepted_at)
             {:ok, session}
           end) do
      {:ok, session}
    else
      {:error, reason} when reason in [:invalid_label, :invalid_client_kind, :invalid_expiry] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @doc "Resolves and coarsely refreshes one active opaque session credential."
  @spec authenticate_session(String.t(), keyword()) ::
          {:ok, map()} | {:error, :authentication_required | :infrastructure_failure}
  def authenticate_session(credential, opts \\ [])

  def authenticate_session(credential, opts) when is_binary(credential) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()
    credential_hash = hash_token(credential)

    case Repo.transact(fn repo ->
           case SQL.query!(
                  repo,
                  """
                  SELECT id, account_id, label, client_kind, created_at, last_seen_at,
                         idle_ttl_seconds, expires_at, absolute_expires_at,
                         recent_auth_expires_at
                  FROM sessions
                  WHERE credential_hash = $1
                    AND revoked_at IS NULL
                    AND expires_at > $2
                    AND absolute_expires_at > $2
                  FOR UPDATE
                  """,
                  [credential_hash, now]
                ).rows do
             [row] -> {:ok, refresh_session(repo, row, now)}
             [] -> {:error, :authentication_required}
           end
         end) do
      {:ok, session} -> {:ok, session}
      {:error, :authentication_required} -> {:error, :authentication_required}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def authenticate_session(_credential, _opts), do: {:error, :authentication_required}

  @doc "Verifies the account password without claiming a completed reauthentication."
  @spec reauthenticate(binary(), String.t(), keyword()) ::
          :ok | {:error, :authentication_failed | :infrastructure_failure}
  def reauthenticate(account_id, password, opts \\ [])

  def reauthenticate(account_id, password, opts)
      when is_binary(account_id) and is_binary(password) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    case SQL.query(Repo, "SELECT password_hash FROM accounts WHERE id = $1", [account_id]) do
      {:ok, %{rows: [[password_hash]]}} ->
        cond do
          not login_password_valid?(password) ->
            Argon2.no_user_verify()
            record_security_audit(account_id, "login_failed", now)
            {:error, :authentication_failed}

          Argon2.verify_pass(password, password_hash) ->
            :ok

          true ->
            record_security_audit(account_id, "login_failed", now)
            {:error, :authentication_failed}
        end

      {:ok, %{rows: []}} ->
        Argon2.no_user_verify()
        {:error, :authentication_failed}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def reauthenticate(_account_id, _password, _opts), do: {:error, :authentication_failed}

  @doc "Verifies a password, rotates the locked session, and audits one atomic reauthentication."
  @spec reauthenticate_session(binary(), binary(), String.t(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def reauthenticate_session(account_id, session_id, password, opts \\ [])

  def reauthenticate_session(account_id, session_id, password, opts)
      when is_binary(account_id) and is_binary(session_id) and is_binary(password) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()
    policy = session_policy(opts)
    credential = random_token()
    credential_hash = hash_token(credential)
    idle_expires_at = DateTime.add(now, policy.idle_ttl_seconds, :second)
    recent_auth_expires_at = DateTime.add(now, policy.recent_auth_ttl_seconds, :second)

    case Repo.transact(fn repo ->
           case SQL.query!(
                  repo,
                  "SELECT password_hash FROM accounts WHERE id = $1 FOR UPDATE",
                  [account_id]
                ).rows do
             [[password_hash]] ->
               cond do
                 not login_password_valid?(password) ->
                   Argon2.no_user_verify()
                   repo.rollback(:authentication_failed)

                 Argon2.verify_pass(password, password_hash) ->
                   session =
                     rotate_session_locked(
                       repo,
                       account_id,
                       session_id,
                       credential,
                       credential_hash,
                       policy,
                       now,
                       idle_expires_at,
                       recent_auth_expires_at
                     )

                   SecurityAudit.record_required!(repo, "reauthenticated", now)
                   {:ok, session}

                 true ->
                   repo.rollback(:authentication_failed)
               end

             [] ->
               Argon2.no_user_verify()
               repo.rollback(:authentication_failed)
           end
         end) do
      {:ok, session} ->
        {:ok, session}

      {:error, :authentication_failed} ->
        record_security_audit(account_id, "login_failed", now)
        {:error, :authentication_failed}

      {:error, :session_unavailable} ->
        {:error, :session_unavailable}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def reauthenticate_session(_account_id, _session_id, _password, _opts),
    do: {:error, :authentication_failed}

  @doc "Returns the latched persistence health of the security audit trail."
  @spec security_audit_health() :: SecurityAudit.health()
  def security_audit_health, do: SecurityAudit.health()

  @doc "Rotates the raw credential and recent-auth state without changing session identity."
  @spec rotate_session(binary(), binary(), keyword()) :: {:ok, map()} | {:error, atom()}
  def rotate_session(account_id, session_id, opts \\ [])
      when is_binary(account_id) and is_binary(session_id) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()
    policy = session_policy(opts)
    credential = random_token()
    credential_hash = hash_token(credential)
    idle_expires_at = DateTime.add(now, policy.idle_ttl_seconds, :second)
    recent_auth_expires_at = DateTime.add(now, policy.recent_auth_ttl_seconds, :second)

    case SQL.query(
           Repo,
           """
           UPDATE sessions
           SET credential_hash = $3,
               idle_ttl_seconds = $4,
               expires_at = LEAST($5, absolute_expires_at),
               last_seen_at = $6,
               recent_authenticated_at = $6,
               recent_auth_expires_at = $7,
               updated_at = $6
           WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
           RETURNING label, client_kind, created_at, absolute_expires_at
           """,
           [
             session_id,
             account_id,
             credential_hash,
             policy.idle_ttl_seconds,
             idle_expires_at,
             now,
             recent_auth_expires_at
           ]
         ) do
      {:ok, %{rows: [[label, client_kind, created_at, absolute_expires_at]]}} ->
        {:ok,
         session_result(
           session_id,
           account_id,
           credential,
           label,
           client_kind,
           as_utc(created_at),
           now,
           min_datetime(idle_expires_at, as_utc(absolute_expires_at)),
           as_utc(absolute_expires_at),
           recent_auth_expires_at
         )}

      {:ok, %{rows: []}} ->
        {:error, :session_unavailable}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  defp rotate_session_locked(
         repo,
         account_id,
         session_id,
         credential,
         credential_hash,
         policy,
         now,
         idle_expires_at,
         recent_auth_expires_at
       ) do
    case SQL.query!(
           repo,
           """
           UPDATE sessions
           SET credential_hash = $3,
               idle_ttl_seconds = $4,
               expires_at = LEAST($5, absolute_expires_at),
               last_seen_at = $6,
               recent_authenticated_at = $6,
               recent_auth_expires_at = $7,
               updated_at = $6
           WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
           RETURNING label, client_kind, created_at, absolute_expires_at
           """,
           [
             session_id,
             account_id,
             credential_hash,
             policy.idle_ttl_seconds,
             idle_expires_at,
             now,
             recent_auth_expires_at
           ]
         ).rows do
      [[label, client_kind, created_at, absolute_expires_at]] ->
        session_result(
          session_id,
          account_id,
          credential,
          label,
          client_kind,
          as_utc(created_at),
          now,
          min_datetime(idle_expires_at, as_utc(absolute_expires_at)),
          as_utc(absolute_expires_at),
          recent_auth_expires_at
        )

      [] ->
        repo.rollback(:session_unavailable)
    end
  end

  @doc "Lists active sessions with only user-visible, coarsened metadata."
  @spec list_sessions(binary(), binary(), keyword()) :: {:ok, [map()]} | {:error, atom()}
  def list_sessions(account_id, current_session_id, opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    case SQL.query(
           Repo,
           """
           SELECT id, label, client_kind, created_at, COALESCE(last_seen_at, created_at)
           FROM sessions
           WHERE account_id = $1 AND revoked_at IS NULL
             AND expires_at > $2 AND absolute_expires_at > $2
           ORDER BY created_at DESC, id DESC
           """,
           [account_id, now]
         ) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [id, label, client_kind, created_at, last_seen_at] ->
           %{
             id: uuid_string(id),
             label: label,
             client_kind: client_kind,
             created_at: created_at |> as_utc() |> DateTime.to_iso8601(),
             coarse_activity: coarse_activity(as_utc(last_seen_at), now),
             current: id == current_session_id
           }
         end)}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @doc "Changes one session label through the account-scoped application seam."
  def rename_session(account_id, session_id, label, opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    with {:ok, session_id} <- dump_uuid(session_id),
         {:ok, label} <- valid_session_label(label),
         {:ok, %{num_rows: 1}} <-
           SQL.query(
             Repo,
             """
             UPDATE sessions SET label = $3, updated_at = $4
             WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
             """,
             [session_id, account_id, label, now]
           ) do
      {:ok, %{status: "session_updated", label: label}}
    else
      :error -> {:error, :session_unavailable}
      {:error, :invalid_label} -> {:error, :invalid_label}
      {:ok, %{num_rows: 0}} -> {:error, :session_unavailable}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  end

  @doc "Revokes one account-scoped session. Recent-auth is enforced by the caller boundary."
  def revoke_session(account_id, session_id, opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    with {:ok, session_id} <- dump_uuid(session_id),
         {:ok, result} <-
           Repo.transact(fn repo ->
             case SQL.query!(
                    repo,
                    """
                    UPDATE sessions SET revoked_at = $3, updated_at = $3
                    WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
                    """,
                    [session_id, account_id, now]
                  ).num_rows do
               1 ->
                 SecurityAudit.record_required!(repo, "session_revoked", now)
                 {:ok, %{status: "session_revoked"}}

               0 ->
                 {:error, :session_unavailable}
             end
           end) do
      {:ok, result}
    else
      :error -> {:error, :session_unavailable}
      {:error, :session_unavailable} -> {:error, :session_unavailable}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @doc "Revokes the current session for logout."
  def logout(account_id, session_id, opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    case Repo.transact(fn repo ->
           SQL.query!(
             repo,
             """
             UPDATE sessions SET revoked_at = $3, updated_at = $3
             WHERE id = $1 AND account_id = $2 AND revoked_at IS NULL
             """,
             [session_id, account_id, now]
           )

           SecurityAudit.record_required!(repo, "logout", now)
           {:ok, :logged_out}
         end) do
      {:ok, :logged_out} ->
        :ok

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @doc "Issues one short-lived recovery capability and persists only its hash."
  @spec issue_recovery_token(keyword()) ::
          {:ok, %{token: String.t(), expires_at: DateTime.t()}}
          | {:error, :invalid_ttl | :account_unavailable | :infrastructure_failure}
  def issue_recovery_token(opts \\ []) do
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()
    ttl_seconds = Keyword.get(opts, :ttl_seconds, @default_recovery_ttl_seconds)

    with true <-
           is_integer(ttl_seconds) and ttl_seconds >= @minimum_recovery_ttl_seconds and
             ttl_seconds <= @maximum_recovery_ttl_seconds,
         token <- random_token(),
         token_hash <- hash_token(token),
         expires_at <- DateTime.add(now, ttl_seconds, :second),
         {:ok, _account_id} <-
           Repo.transact(fn repo ->
             case SQL.query!(
                    repo,
                    "SELECT id FROM accounts WHERE singleton_key = TRUE FOR UPDATE",
                    []
                  ).rows do
               [[account_id]] ->
                 SQL.query!(
                   repo,
                   """
                   INSERT INTO account_recovery (
                     account_id, token_hash, issued_at, expires_at, consumed_at,
                     inserted_at, updated_at
                   )
                   VALUES ($1, $2, $3, $4, NULL, $3, $3)
                   ON CONFLICT (account_id) DO UPDATE
                   SET token_hash = EXCLUDED.token_hash,
                       issued_at = EXCLUDED.issued_at,
                       expires_at = EXCLUDED.expires_at,
                       consumed_at = NULL,
                       updated_at = EXCLUDED.updated_at
                   """,
                   [account_id, token_hash, now, expires_at]
                 )

                 SecurityAudit.record_required!(repo, "recovery_issued", now)
                 {:ok, account_id}

               [] ->
                 {:error, :account_unavailable}
             end
           end) do
      {:ok, %{token: token, expires_at: expires_at}}
    else
      false -> {:error, :invalid_ttl}
      {:error, :account_unavailable} -> {:error, :account_unavailable}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @doc "Consumes a recovery capability once, replaces the password, and rotates all sessions."
  @spec consume_recovery(map()) :: {:ok, map()} | {:error, atom()}
  def consume_recovery(params) when is_map(params) do
    with {:ok, token} <- required_binary(params, :token),
         {:ok, password} <- valid_password(params),
         {:ok, accepted_at} <- recovery_accepted_at(params),
         {:ok, label} <- valid_session_label(Map.get(params, :label, "Browser")),
         {:ok, client_kind} <- valid_client_kind(Map.get(params, :client_kind, "web")),
         password_hash <- Argon2.hash_pwd_salt(password),
         token_hash <- hash_token(token),
         {:ok, result} <-
           Repo.transact(fn repo ->
             {:ok,
              consume_recovery_locked(
                repo,
                token_hash,
                password_hash,
                accepted_at,
                label,
                client_kind
              )}
           end) do
      result
    else
      {:error, reason}
      when reason in [
             :invalid_password,
             :invalid_label,
             :invalid_client_kind,
             :recovery_unavailable
           ] ->
        {:error, reason}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  def consume_recovery(_params), do: {:error, :recovery_unavailable}

  @spec change_timezone(String.t(), keyword()) ::
          {:ok,
           %{
             timezone: String.t(),
             today_view_revision: pos_integer(),
             upcoming_view_revision: pos_integer(),
             activity_view_revision: pos_integer()
           }}
          | {:error, :invalid_timezone | :account_unavailable | :infrastructure_failure}
  def change_timezone(timezone, opts \\ []) do
    accepted_at = opts |> Keyword.get(:accepted_at, utc_now()) |> truncate_utc!()

    with true <- valid_timezone?(timezone),
         {:ok, result} <-
           Repo.transact(fn repo ->
             {:ok, change_timezone_locked(repo, timezone, accepted_at)}
           end) do
      result
    else
      false -> {:error, :invalid_timezone}
      {:error, _reason} -> {:error, :infrastructure_failure}
    end
  rescue
    _error in [ArgumentError, DBConnection.ConnectionError, Postgrex.Error] ->
      {:error, :infrastructure_failure}
  end

  @spec account_date_at(DateTime.t()) ::
          {:ok, Date.t()} | {:error, :account_unavailable | :infrastructure_failure}
  def account_date_at(%DateTime{} = instant) do
    case SQL.query(
           Repo,
           "SELECT timezone FROM accounts WHERE singleton_key = TRUE",
           []
         ) do
      {:ok, %{rows: [[timezone]]}} when is_binary(timezone) ->
        case DateTime.shift_zone(instant, timezone) do
          {:ok, zoned} -> {:ok, DateTime.to_date(zoned)}
          {:error, _reason} -> {:error, :infrastructure_failure}
        end

      {:ok, %{rows: []}} ->
        {:error, :account_unavailable}

      {:error, _reason} ->
        {:error, :infrastructure_failure}
    end
  end

  @spec valid_timezone?(term()) :: boolean()
  def valid_timezone?(timezone) when is_binary(timezone) do
    timezone == String.trim(timezone) and
      not fixed_offset?(timezone) and
      Tzdata.zone_exists?(timezone)
  end

  def valid_timezone?(_timezone), do: false

  defp session_params(opts) do
    policy = session_policy(opts)
    now = opts |> Keyword.get(:now, utc_now()) |> truncate_utc!()

    with {:ok, label} <- valid_session_label(Keyword.get(opts, :label, "Browser")),
         {:ok, client_kind} <- valid_client_kind(Keyword.get(opts, :client_kind, "web")),
         true <-
           Enum.all?(
             [
               policy.idle_ttl_seconds,
               policy.absolute_ttl_seconds,
               policy.recent_auth_ttl_seconds
             ],
             &(is_integer(&1) and &1 > 0)
           ),
         true <- policy.absolute_ttl_seconds > 0 do
      {:ok,
       %{
         absolute_expires_at: DateTime.add(now, policy.absolute_ttl_seconds, :second),
         client_kind: client_kind,
         created_at: now,
         idle_expires_at: DateTime.add(now, policy.idle_ttl_seconds, :second),
         idle_ttl_seconds: policy.idle_ttl_seconds,
         label: label,
         recent_auth_expires_at: DateTime.add(now, policy.recent_auth_ttl_seconds, :second)
       }}
    else
      false -> {:error, :invalid_expiry}
      {:error, reason} -> {:error, reason}
    end
  end

  defp session_policy(opts) do
    configured = Application.get_env(:keepling, :authentication, [])

    %{
      idle_ttl_seconds:
        Keyword.get(
          opts,
          :idle_ttl_seconds,
          Keyword.get(configured, :idle_ttl_seconds, @default_idle_ttl_seconds)
        ),
      absolute_ttl_seconds:
        Keyword.get(
          opts,
          :absolute_ttl_seconds,
          Keyword.get(configured, :absolute_ttl_seconds, @default_absolute_ttl_seconds)
        ),
      recent_auth_ttl_seconds:
        Keyword.get(
          opts,
          :recent_auth_ttl_seconds,
          Keyword.get(
            configured,
            :recent_auth_ttl_seconds,
            @default_recent_auth_ttl_seconds
          )
        )
    }
  end

  defp insert_session(repo, account_id, params) do
    credential = random_token()
    credential_hash = hash_token(credential)
    session_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()

    SQL.query!(
      repo,
      """
      INSERT INTO sessions (
        id, account_id, credential_hash, label, client_kind,
        created_at, last_seen_at, idle_ttl_seconds, expires_at,
        absolute_expires_at, recent_authenticated_at, recent_auth_expires_at,
        inserted_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $6, $7, $8, $9, $6, $10, $6, $6)
      """,
      [
        session_id,
        account_id,
        credential_hash,
        params.label,
        params.client_kind,
        params.created_at,
        params.idle_ttl_seconds,
        params.idle_expires_at,
        params.absolute_expires_at,
        params.recent_auth_expires_at
      ]
    )

    session_result(
      session_id,
      account_id,
      credential,
      params.label,
      params.client_kind,
      params.created_at,
      params.created_at,
      params.idle_expires_at,
      params.absolute_expires_at,
      params.recent_auth_expires_at
    )
  end

  defp session_result(
         session_id,
         account_id,
         credential,
         label,
         client_kind,
         created_at,
         last_seen_at,
         expires_at,
         absolute_expires_at,
         recent_auth_expires_at
       ) do
    %{
      absolute_expires_at: absolute_expires_at,
      account_id: account_id,
      client_kind: client_kind,
      created_at: created_at,
      credential: credential,
      expires_at: expires_at,
      id: uuid_string(session_id),
      label: label,
      last_seen_at: last_seen_at,
      recent_auth_expires_at: recent_auth_expires_at,
      session_id: session_id
    }
  end

  defp refresh_session(
         repo,
         [
           session_id,
           account_id,
           label,
           client_kind,
           created_at,
           last_seen_at,
           idle_ttl_seconds,
           _expires_at,
           absolute_expires_at,
           recent_auth_expires_at
         ],
         now
       ) do
    absolute_expires_at = as_utc(absolute_expires_at)
    idle_expires_at = DateTime.add(now, idle_ttl_seconds, :second)
    next_expires_at = min_datetime(idle_expires_at, absolute_expires_at)
    last_seen_at = as_utc(last_seen_at || created_at)

    coarsened_last_seen_at =
      if DateTime.diff(now, last_seen_at, :second) >= @session_activity_write_interval_seconds,
        do: now,
        else: last_seen_at

    SQL.query!(
      repo,
      """
      UPDATE sessions
      SET expires_at = $2, last_seen_at = $3, updated_at = $4
      WHERE id = $1
      """,
      [session_id, next_expires_at, coarsened_last_seen_at, now]
    )

    %{
      account_id: account_id,
      client_kind: client_kind,
      created_at: as_utc(created_at),
      id: uuid_string(session_id),
      label: label,
      recently_authenticated?: DateTime.compare(as_utc(recent_auth_expires_at), now) == :gt,
      session_id: session_id
    }
  end

  defp consume_recovery_locked(
         repo,
         presented_hash,
         password_hash,
         accepted_at,
         label,
         client_kind
       ) do
    case SQL.query!(
           repo,
           """
           SELECT account_id, token_hash, expires_at, consumed_at
           FROM account_recovery
           FOR UPDATE
           """,
           []
         ).rows do
      [[account_id, stored_hash, expires_at, nil]] ->
        if usable_token?(stored_hash, presented_hash, expires_at, accepted_at) do
          SQL.query!(
            repo,
            "UPDATE accounts SET password_hash = $2, updated_at = $3 WHERE id = $1",
            [account_id, password_hash, accepted_at]
          )

          SQL.query!(
            repo,
            """
            UPDATE account_recovery
            SET consumed_at = $2, updated_at = $2
            WHERE account_id = $1
            """,
            [account_id, accepted_at]
          )

          SQL.query!(
            repo,
            """
            UPDATE sessions
            SET revoked_at = $2, updated_at = $2
            WHERE account_id = $1 AND revoked_at IS NULL
            """,
            [account_id, accepted_at]
          )

          {:ok, params} =
            session_params(
              now: accepted_at,
              label: label,
              client_kind: client_kind
            )

          session = insert_session(repo, account_id, params)
          SecurityAudit.record_required!(repo, "recovery_succeeded", accepted_at)
          {:ok, session}
        else
          {:error, :recovery_unavailable}
        end

      _ ->
        {:error, :recovery_unavailable}
    end
  end

  defp valid_session_label(label) when is_binary(label) do
    trimmed = String.trim(label)
    length = String.length(trimmed)

    if length >= 1 and length <= 200, do: {:ok, trimmed}, else: {:error, :invalid_label}
  end

  defp valid_session_label(_label), do: {:error, :invalid_label}

  defp valid_client_kind(client_kind) when client_kind in @client_kinds,
    do: {:ok, client_kind}

  defp valid_client_kind(_client_kind), do: {:error, :invalid_client_kind}

  defp login_password_valid?(password) do
    size = byte_size(password)
    size > 0 and size <= @maximum_password_bytes
  end

  defp recovery_accepted_at(params) do
    case Map.fetch(params, :accepted_at) do
      {:ok, %DateTime{} = accepted_at} -> {:ok, truncate_utc!(accepted_at)}
      _ -> {:error, :recovery_unavailable}
    end
  end

  defp coarse_activity(last_seen_at, now) do
    seconds = max(DateTime.diff(now, last_seen_at, :second), 0)

    cond do
      seconds < 15 * 60 -> "active_now"
      Date.compare(DateTime.to_date(last_seen_at), DateTime.to_date(now)) == :eq -> "today"
      true -> "earlier"
    end
  end

  defp record_security_audit(_account_id, event_type, accepted_at) do
    SecurityAudit.record_best_effort(Repo, event_type, accepted_at)
  end

  defp dump_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, Ecto.UUID.dump!(uuid)}
      :error -> :error
    end
  end

  defp dump_uuid(_value), do: :error

  defp uuid_string(value) when is_binary(value) do
    case Ecto.UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> value
    end
  end

  defp min_datetime(left, right) do
    case DateTime.compare(left, right) do
      :gt -> right
      _ -> left
    end
  end

  defp change_timezone_locked(repo, timezone, accepted_at) do
    case SQL.query!(
           repo,
           """
           SELECT id, timezone, today_view_revision, upcoming_view_revision,
                  completed_view_revision, activity_view_revision
           FROM accounts
           WHERE singleton_key = TRUE
           FOR UPDATE
           """,
           []
         ).rows do
      [[_account_id, ^timezone, today, upcoming, completed, activity]] ->
        {:ok, setting_result(timezone, today, upcoming, completed, activity)}

      [[account_id, _previous_timezone, _today, _upcoming, _completed, _activity]] ->
        %{rows: [[today, upcoming, completed, activity]]} =
          SQL.query!(
            repo,
            """
            UPDATE accounts
            SET timezone = $2,
                today_view_revision = today_view_revision + 1,
                upcoming_view_revision = upcoming_view_revision + 1,
                completed_view_revision = completed_view_revision + 1,
                activity_view_revision = activity_view_revision + 1,
                updated_at = $3
            WHERE id = $1
            RETURNING today_view_revision, upcoming_view_revision,
                      completed_view_revision, activity_view_revision
            """,
            [account_id, timezone, accepted_at]
          )

        SQL.query!(
          repo,
          """
          INSERT INTO account_security_audits (
            event_type, event_version, accepted_at, inserted_at
          )
          VALUES ('timezone_changed', 1, $1, $1)
          """,
          [accepted_at]
        )

        {:ok, setting_result(timezone, today, upcoming, completed, activity)}

      [] ->
        {:error, :account_unavailable}
    end
  end

  defp setting_result(timezone, today, upcoming, completed, activity) do
    %{
      activity_view_revision: activity,
      completed_view_revision: completed,
      timezone: timezone,
      today_view_revision: today,
      upcoming_view_revision: upcoming
    }
  end

  defp issue_setup_token_locked(repo, token_hash, now, expires_at) do
    %{rows: [[stored_hash, stored_expires_at, consumed_at, disabled_at]]} =
      SQL.query!(
        repo,
        """
        SELECT token_hash, expires_at, consumed_at, disabled_at
        FROM account_setup
        WHERE singleton_key = TRUE
        FOR UPDATE
        """,
        []
      )

    account_exists? = account_exists?(repo)
    active? = active_setup_token?(stored_hash, stored_expires_at, consumed_at, now)

    cond do
      disabled_at != nil ->
        {:error, :setup_disabled}

      account_exists? ->
        disable_setup(repo, now)
        {:error, :setup_disabled}

      active? ->
        {:error, :setup_token_active}

      true ->
        SQL.query!(
          repo,
          """
          UPDATE account_setup
          SET token_hash = $1, issued_at = $2, expires_at = $3,
              consumed_at = NULL, updated_at = $2
          WHERE singleton_key = TRUE
          """,
          [token_hash, now, expires_at]
        )

        :issued
    end
  end

  defp consume_setup_locked(repo, presented_hash, password_hash, timezone, accepted_at) do
    case SQL.query!(
           repo,
           """
           SELECT token_hash, expires_at, consumed_at, disabled_at
           FROM account_setup
           WHERE singleton_key = TRUE
           FOR UPDATE
           """,
           []
         ).rows do
      [[stored_hash, expires_at, nil, nil]] ->
        if usable_token?(stored_hash, presented_hash, expires_at, accepted_at) and
             not account_exists?(repo) do
          create_account_and_disable_setup(
            repo,
            password_hash,
            timezone,
            accepted_at
          )
        else
          {:error, :setup_unavailable}
        end

      _ ->
        {:error, :setup_unavailable}
    end
  end

  defp create_account_and_disable_setup(repo, password_hash, timezone, accepted_at) do
    changeset = Account.creation_changeset(%{password_hash: password_hash, timezone: timezone})

    case repo.insert(changeset) do
      {:ok, _account} ->
        SQL.query!(
          repo,
          """
          UPDATE account_setup
          SET consumed_at = $1, disabled_at = $1, updated_at = $1
          WHERE singleton_key = TRUE
          """,
          [accepted_at]
        )

        {:ok, %{timezone: timezone}}

      {:error, _changeset} ->
        {:error, :setup_unavailable}
    end
  end

  defp ensure_setup_row(repo, now) do
    SQL.query!(
      repo,
      """
      INSERT INTO account_setup (singleton_key, inserted_at, updated_at)
      VALUES (TRUE, $1, $1)
      ON CONFLICT (singleton_key) DO NOTHING
      """,
      [now]
    )
  end

  defp disable_setup(repo, now) do
    SQL.query!(
      repo,
      """
      UPDATE account_setup
      SET consumed_at = COALESCE(consumed_at, $1),
          disabled_at = COALESCE(disabled_at, $1),
          updated_at = $1
      WHERE singleton_key = TRUE
      """,
      [now]
    )
  end

  defp account_exists?(repo) do
    %{rows: [[exists?]]} =
      SQL.query!(repo, "SELECT EXISTS(SELECT 1 FROM accounts WHERE singleton_key = TRUE)", [])

    exists?
  end

  defp active_setup_token?(nil, _expires_at, _consumed_at, _now), do: false

  defp active_setup_token?(_hash, _expires_at, consumed_at, _now) when consumed_at != nil,
    do: false

  defp active_setup_token?(_hash, expires_at, nil, now) do
    DateTime.compare(as_utc(expires_at), now) == :gt
  end

  defp usable_token?(stored_hash, presented_hash, expires_at, accepted_at)
       when is_binary(stored_hash) and is_binary(presented_hash) do
    DateTime.compare(as_utc(expires_at), accepted_at) == :gt and
      byte_size(stored_hash) == byte_size(presented_hash) and
      Plug.Crypto.secure_compare(stored_hash, presented_hash)
  end

  defp usable_token?(_stored_hash, _presented_hash, _expires_at, _accepted_at), do: false

  defp valid_password(params) do
    with {:ok, password} <- required_binary(params, :password),
         size <- byte_size(password),
         true <- size >= @minimum_password_bytes and size <= @maximum_password_bytes do
      {:ok, password}
    else
      _ -> {:error, :invalid_password}
    end
  end

  defp valid_timezone(params) do
    with {:ok, timezone} <- required_binary(params, :timezone),
         true <- valid_timezone?(timezone) do
      {:ok, timezone}
    else
      _ -> {:error, :invalid_timezone}
    end
  end

  defp valid_accepted_at(params) do
    case Map.fetch(params, :accepted_at) do
      {:ok, %DateTime{} = accepted_at} -> {:ok, truncate_utc!(accepted_at)}
      _ -> {:error, :setup_unavailable}
    end
  end

  defp required_binary(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, :setup_unavailable}
    end
  end

  defp fixed_offset?(timezone) do
    timezone in ["UTC", "GMT"] or
      String.starts_with?(timezone, ["UTC+", "UTC-", "GMT+", "GMT-", "+", "-"])
  end

  defp random_token do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)
  defp utc_now, do: DateTime.utc_now()

  defp truncate_utc!(%DateTime{time_zone: "Etc/UTC"} = value),
    do: DateTime.truncate(value, :microsecond)

  defp truncate_utc!(%DateTime{} = value),
    do: value |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:microsecond)

  defp as_utc(%DateTime{} = value), do: value
  defp as_utc(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
end
