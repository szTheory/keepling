defmodule Keepling.Accounts do
  @moduledoc """
  Application seam for the closed personal account and its canonical settings.

  Operator tasks and transports call this module instead of mutating Ecto
  schemas directly. Raw bearer capabilities exist only in the caller and are
  represented by SHA-256 hashes in PostgreSQL.
  """

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts.Account
  alias Keepling.Repo

  @default_setup_ttl_seconds 900
  @minimum_setup_ttl_seconds 60
  @maximum_setup_ttl_seconds 3_600
  @minimum_password_bytes 12
  @maximum_password_bytes 1_024

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

  defp change_timezone_locked(repo, timezone, accepted_at) do
    case SQL.query!(
           repo,
           """
           SELECT id, timezone, today_view_revision, upcoming_view_revision,
                  activity_view_revision
           FROM accounts
           WHERE singleton_key = TRUE
           FOR UPDATE
           """,
           []
         ).rows do
      [[_account_id, ^timezone, today, upcoming, activity]] ->
        {:ok, setting_result(timezone, today, upcoming, activity)}

      [[account_id, _previous_timezone, _today, _upcoming, _activity]] ->
        %{rows: [[today, upcoming, activity]]} =
          SQL.query!(
            repo,
            """
            UPDATE accounts
            SET timezone = $2,
                today_view_revision = today_view_revision + 1,
                upcoming_view_revision = upcoming_view_revision + 1,
                activity_view_revision = activity_view_revision + 1,
                updated_at = $3
            WHERE id = $1
            RETURNING today_view_revision, upcoming_view_revision, activity_view_revision
            """,
            [account_id, timezone, accepted_at]
          )

        SQL.query!(
          repo,
          """
          INSERT INTO account_security_audits (
            account_id, event_type, event_version, accepted_at, inserted_at
          )
          VALUES ($1, 'timezone_changed', 1, $2, $2)
          """,
          [account_id, accepted_at]
        )

        {:ok, setting_result(timezone, today, upcoming, activity)}

      [] ->
        {:error, :account_unavailable}
    end
  end

  defp setting_result(timezone, today, upcoming, activity) do
    %{
      activity_view_revision: activity,
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
