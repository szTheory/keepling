defmodule KeeplingWeb.Auth do
  @moduledoc false

  import Plug.Conn

  alias Ecto.Adapters.SQL
  alias Keepling.Accounts
  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.AgentScope
  alias Keepling.Repo

  @session_key :session_credential

  def init(action), do: action

  def call(conn, :load_session), do: load_session(conn)
  def call(conn, :require_authenticated), do: require_authenticated(conn)
  def call(conn, :require_recent_auth), do: require_recent_auth(conn)
  def call(conn, :require_trusted_origin), do: require_trusted_origin(conn)
  def call(conn, :require_test_fixture), do: require_test_fixture(conn)
  def call(conn, :authenticate_device_grant), do: authenticate_first_party_device_grant(conn)

  def call(conn, :authenticate_client),
    do: conn |> authenticate_client(false) |> authorize_agent()

  def call(conn, :authenticate_client_mutation),
    do: conn |> authenticate_client(true) |> authorize_agent()

  def establish_session(conn, session) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> put_session(@session_key, session.credential)
    |> assign_session(session)
  end

  def initialize_csrf(conn) do
    conn
    |> put_private(:plug_skip_csrf_protection, true)
    |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))
  end

  def clear_session(conn) do
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> delete_session(@session_key)
    |> configure_session(drop: true)
  end

  def sign_in_test_account(conn) do
    with %{rows: [[account_id]]} <-
           SQL.query!(Repo, "SELECT id FROM accounts WHERE singleton_key = TRUE", []),
         {:ok, session} <-
           Accounts.create_session(account_id,
             label: "Test browser",
             client_kind: "web"
           ) do
      signed_in_conn = establish_session(conn, session)
      {:ok, signed_in_conn, Plug.CSRFProtection.get_csrf_token()}
    else
      _ -> {:error, :fixture_unavailable}
    end
  end

  defp load_session(conn) do
    with credential when is_binary(credential) <- get_session(conn, @session_key),
         {:ok, session} <- Accounts.authenticate_session(credential) do
      assign_session(conn, session)
    else
      _ -> conn
    end
  end

  defp assign_session(conn, session) do
    conn
    |> assign(:current_account_id, session.account_id)
    |> assign(:current_session_id, session.session_id)
    |> assign(:recently_authenticated?, Map.get(session, :recently_authenticated?, true))
  end

  # D-49. ONE credential decision for the shared command surface.
  #
  # A request presenting `Authorization: Bearer` is a NATIVE client (Mac
  # today, iPhone and MCP later). It is authenticated by its device grant,
  # and no Origin is required, because `require_trusted_origin` and
  # `protect_from_forgery` defend against CSRF -- an attack that rides
  # AMBIENT COOKIE authentication a browser attaches automatically. A bearer
  # client has no ambient credential to ride: the token is attached only by
  # code that already holds it. Not demanding an Origin here is therefore
  # standard practice, not a relaxation.
  #
  # EVERY OTHER REQUEST IS A BROWSER and takes exactly the path it took
  # before D-49 -- `load_session`, `require_authenticated`,
  # `protect_from_forgery`, then `require_trusted_origin` for mutations --
  # in that order, with nothing removed and nothing made conditional. That
  # is pinned by test/keepling_web/device_grant_command_test.exs rather than
  # asserted here in prose.
  defp authenticate_client(conn, mutation?) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> credential] when credential != "" ->
        conn
        # No session is involved, so there is no CSRF token to verify and
        # nothing for `protect_from_forgery` to protect.
        |> put_private(:plug_skip_csrf_protection, true)
        |> authenticate_device_grant()

      _no_bearer_credential ->
        conn
        |> load_session()
        |> require_authenticated()
        |> browser_guards(mutation?)
    end
  end

  defp browser_guards(%{halted: true} = conn, _mutation?), do: conn

  defp browser_guards(conn, mutation?) do
    conn = Phoenix.Controller.protect_from_forgery(conn, [])
    if mutation?, do: require_trusted_origin(conn), else: conn
  end

  # T-05-14 / WINDOWS #72. The SCOPE half of the agent boundary. 05-13 made
  # `client_kind` default-deny on `:device_grant_authenticated`; this makes
  # `scope` default-deny on the shared surface. A credential's authority is
  # `client_kind` x `scope`, and half a product is not a boundary.
  #
  # `Keepling.Application.AgentScope` calls itself "the authoritative,
  # application-boundary scope gate", so that "a bug in the adapter alone
  # cannot widen what an agent grant may do". Every one of its call sites was
  # inside `lib/keepling_web/mcp/`, which made it adapter-local -- the exact
  # property its own moduledoc denies. This is its first call site outside
  # that adapter, so the claim is now true of the application rather than
  # only of `/mcp/v1`.
  #
  # It applies ONLY to agent client kinds. A browser session has no
  # `current_client_kind` at all, and an `electron`/`iphone` grant is not an
  # agent, so both leave here as exactly the conn they arrived as: the owner
  # keeps every shared command and query it had before, unchanged. That is
  # pinned by tests rather than asserted here in prose.
  @agent_client_kinds ~w(mcp)

  defp authorize_agent(%{halted: true} = conn), do: conn

  defp authorize_agent(conn) do
    if conn.assigns[:current_client_kind] in @agent_client_kinds,
      do: require_agent_authority(conn),
      else: conn
  end

  defp require_agent_authority(conn) do
    with {:ok, scope} <- agent_authority(conn.method, conn.path_info),
         :ok <- AgentScope.require(%{scope: conn.assigns[:current_scope]}, scope),
         :ok <- authorize_receipt_read(conn) do
      conn
    else
      _refused -> conn |> insufficient_scope() |> halt()
    end
  end

  # T-06-07-01/D-39. Closes the receipt-scope inversion the comment above
  # `agent_authority/2`'s mutations clause already names: that clause grants
  # the ROUTE to any `tasks.write`-scoped agent, but the receipt itself
  # belongs to whichever grant issued the mutation. Extends the existing
  # match-and-dispatch shape (no new middleware layer, `agent_authority/2`
  # itself unchanged) by checking, for this one route only, whether the
  # stored mutation's issuing grant -- `CommandStore.receipt_issuer/2`, a
  # narrow companion to `Commands.lookup_result/3` that answers only "who
  # issued this" -- differs from the CURRENT grant.
  #
  # A stored issuing grant of `nil` (a receipt written by a browser session,
  # by a first-party grant, or before this column existed) refuses nothing:
  # only a proven MISMATCH does. A malformed or genuinely nonexistent
  # mutation id is also let through here unrefused, so the controller's own
  # `Ecto.UUID.cast/1` and `Commands.lookup_result/3` calls produce their
  # ordinary 400/404 -- this plug exists to add a 403 for a mismatched
  # OWNER, not to duplicate that handling.
  defp authorize_receipt_read(%{path_info: ["api", "v1", "mutations", mutation_id]} = conn) do
    current_grant_id = conn.assigns[:current_device_grant_id]

    with {:ok, _uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, issuing_grant_id} <-
           CommandStore.receipt_issuer(conn.assigns[:current_account_id], mutation_id) do
      if is_binary(issuing_grant_id) and issuing_grant_id != current_grant_id,
        do: :error,
        else: :ok
    else
      _otherwise -> :ok
    end
  end

  defp authorize_receipt_read(_conn), do: :ok

  # DEFAULT-DENY, by the same reasoning 05-13 used for the client-kind
  # allow-list: anything not named here is refused, so a route added to
  # `:client_authenticated` or to the command surface later does not silently
  # inherit agent reach.
  #
  # The named set is EXACTLY what the closed MCP tool set (`mcp/tools.ex`,
  # D-11) already reaches, under the scope that tool requires:
  # `keepling.search_tasks` and the resource reads require `tasks.read`;
  # `keepling.capture_task`, `keepling.update_task` (which decodes into
  # `:edit_task`, `:edit_task_dates` or `:assign_task_organizations`),
  # `keepling.complete_task` and `keepling.reopen_task` require `tasks.write`.
  #
  # The thirteen command routes left out are NOT an oversight, and they are
  # not merely "unexposed". `trash-task`, `restore-task` and `undo-task` are
  # the closed D-19 destructive vocabulary, which an agent may reach only
  # through `preview_bulk_change` + `commit_bulk_change` -- a two-step gated
  # by `tasks.bulk` AND by a signed token binding exact targets and their
  # expected revisions (D-17, D-18). Admitting them here would hand a
  # `tasks.bulk` grant a ONE-STEP, unpreviewed, drift-unchecked trash: a
  # route around the safeguard the bulk path exists to impose. The remaining
  # ten (clarify, return-to-inbox, resolve-conflict, plan-for-today, unplan,
  # move-today and the four organization commands) are outside the tool set
  # the phase deliberately published, and an authority an agent cannot
  # express through its own surface is not one its credential should carry.
  #
  # `GET /api/v1/mutations/:id` requires `tasks.write`, not `tasks.read`,
  # because D-49 moves the receipt WITH the write: it is the stored result of
  # a mutation, readable by the authority that could have issued it.
  @agent_writable_commands ~w(
    capture-task
    edit-task
    edit-task-dates
    assign-task-organizations
    complete-task
    reopen-task
  )

  defp agent_authority("GET", ["api", "v1", "search"]), do: {:ok, "tasks.read"}
  defp agent_authority("GET", ["api", "v1", "projects"]), do: {:ok, "tasks.read"}
  defp agent_authority("GET", ["api", "v1", "projects", _id, "tasks"]), do: {:ok, "tasks.read"}
  defp agent_authority("GET", ["api", "v1", "mutations", _id]), do: {:ok, "tasks.write"}

  defp agent_authority("POST", ["api", "v1", "commands", command])
       when command in @agent_writable_commands,
       do: {:ok, "tasks.write"}

  defp agent_authority(_method, _path_info), do: :no_agent_authority

  # 403, not 401: the credential authenticated. What it lacks is authority,
  # and telling an agent to reauthenticate for a scope its grant was never
  # issued would send it round a loop it cannot exit. The body is constant --
  # it names neither the scope required nor whether the route exists for some
  # other authority, so it discloses nothing an agent could enumerate with.
  # `insufficient_scope` is the same code `KeeplingWeb.MCP.Errors` returns for
  # the same refusal on `/mcp/v1`: one refusal, one name, on both surfaces.
  defp insufficient_scope(conn) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      403,
      Jason.encode!(%{
        code: "insufficient_scope",
        recovery_action: "reauthorize_device",
        retryable: false,
        status: 403,
        title: "Insufficient scope",
        type: "/problems/insufficient_scope"
      })
    )
  end

  # T-05-13. The MIRROR IMAGE of `KeeplingWeb.MCP.Pipeline`'s
  # `client_kind == "mcp"` requirement (mcp/pipeline.ex). That pipeline
  # refuses a native grant on the agent surface; this one refuses an agent
  # grant on the native surface. Without both halves the refusal is not a
  # boundary, it is a one-way door: an `mcp` grant scoped `tasks.read`
  # authenticated here and reached `/api/v1/sync/bootstrap` (the whole
  # account, unbounded and unredacted, around the paginated MCP read
  # surface), enumerated every device grant, and revoked another
  # installation -- in production, an agent switching off the owner's
  # iPhone. Recorded as WINDOWS #70, found by live probe in
  # KPL-05's VERIFICATION.md.
  #
  # The check lives on the PIPELINE, not per route, for two reasons. First,
  # `:device_grant_authenticated` fronts only first-party native client
  # surfaces (router.ex: `/api/v1/sync`, `/api/v1/sync/bootstrap`, and both
  # `/api/v1/device-grants` routes), so there is no route behind it that an
  # agent should reach and therefore no per-route judgement to make.
  # Second, a per-route check defaults to ALLOW for any route added later,
  # which is exactly the failure mode being closed here; an allow-list on
  # the pipeline defaults to DENY.
  #
  # It is an ALLOW-LIST of first-party kinds rather than a `!= "mcp"`
  # denial for the same reason: a future agent-ish `client_kind` added to
  # `Keepling.Accounts.DeviceGrant`'s `@client_kinds` is refused here until
  # someone deliberately admits it.
  #
  # This deliberately does NOT apply to `:client_authenticated`
  # (`authenticate_client/2` above), which calls `authenticate_device_grant/1`
  # directly. D-09 admits `mcp` grants to the SHARED read/command surface on
  # purpose: it is the one query, not a parallel one. The asymmetry between
  # the two entry points is the point -- one fronts the raw device feed and
  # grant administration, the other fronts a surface an agent reaches only
  # within the authority its own grant carries, which `authorize_agent/1`
  # above enforces.
  #
  # T-05-14 CORRECTION. Until `authorize_agent/1` existed, this paragraph
  # read "that surface is scope-checked and bounded". Bounded was true.
  # SCOPE-CHECKED WAS NOT, and could not be: `authenticate_device_grant/1`
  # did not assign `current_scope` at all outside `KeeplingWeb.MCP.Pipeline`,
  # so no route behind `:client_authenticated` or `:client_mutation` could
  # have checked a scope if it had tried, and none did. A `tasks.read` grant
  # captured and trashed tasks through `/api/v1/commands/*` while the same
  # token was refused `insufficient_scope` at `/mcp/v1` (WINDOWS #72). The
  # sentence is recorded here rather than quietly deleted, because an
  # inherited, plausible, unverified claim is exactly how the next reader
  # concludes a boundary is already covered.
  @first_party_client_kinds ~w(electron iphone)

  defp authenticate_first_party_device_grant(conn) do
    conn = authenticate_device_grant(conn)

    cond do
      conn.halted ->
        conn

      conn.assigns[:current_client_kind] in @first_party_client_kinds ->
        conn

      true ->
        # The same problem shape `KeeplingWeb.MCP.Pipeline` returns for the
        # opposite refusal: an authenticated-but-wrong-kind credential is
        # told only that this surface requires a different device
        # authorization. Nothing here discloses which kinds are admitted.
        conn
        |> authentication_problem(
          "device_authentication_required",
          "Device authentication required",
          "reauthorize_device"
        )
        |> halt()
    end
  end

  defp authenticate_device_grant(conn) do
    with ["Bearer " <> credential] when credential != "" <-
           get_req_header(conn, "authorization"),
         {:ok, authenticated} <- Accounts.authenticate_device_access(credential) do
      conn
      |> assign(:current_device_grant_id, authenticated.grant_id)
      |> assign(:device_grant_namespace, authenticated.namespace)
      # D-49: the account and the client kind are derived from the GRANT and
      # from nowhere else. No request input reaches either, so a native
      # client can never write outside the namespace its credential is
      # bound to.
      |> assign(:current_account_id, authenticated.account_id)
      |> assign(:current_client_kind, authenticated.client_kind)
      # T-05-14. The scope travels with the credential on EVERY surface it
      # authenticates, not only under `KeeplingWeb.MCP.Pipeline`. A
      # credential's authority is `client_kind` x `scope`; while the scope
      # was assigned only inside the MCP pipeline, no route outside
      # `/mcp/v1` could check it even if it tried, and none did.
      |> assign(:current_scope, authenticated.scope)
    else
      {:error, :infrastructure_failure} ->
        conn
        |> authentication_problem(
          "device_authentication_unavailable",
          "Device authentication unavailable",
          "retry"
        )
        |> halt()

      _reason ->
        conn
        |> authentication_problem(
          "device_authentication_required",
          "Device authentication required",
          "reauthorize_device"
        )
        |> halt()
    end
  end

  defp require_authenticated(%{assigns: %{current_account_id: _account_id}} = conn), do: conn

  defp require_authenticated(conn) do
    conn
    |> authentication_problem(
      "authentication_required",
      "Authentication required",
      "sign_in"
    )
    |> halt()
  end

  defp require_recent_auth(%{assigns: %{recently_authenticated?: true}} = conn), do: conn

  defp require_recent_auth(conn) do
    conn
    |> authentication_problem(
      "recent_authentication_required",
      "Recent authentication required",
      "reauthenticate"
    )
    |> halt()
  end

  defp authentication_problem(conn, code, title, recovery_action) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      401,
      Jason.encode!(%{
        code: code,
        recovery_action: recovery_action,
        retryable: false,
        status: 401,
        title: title,
        type: "/problems/#{code}"
      })
    )
  end

  defp require_trusted_origin(conn) do
    expected = "#{conn.scheme}://#{List.first(get_req_header(conn, "host"))}"

    case get_req_header(conn, "origin") do
      [^expected] -> conn
      _ -> forbidden(conn)
    end
  end

  defp require_test_fixture(conn) do
    if Mix.env() == :test and System.get_env("KEEPLING_E2E_SEED") == "phase-1" do
      conn
      |> require_trusted_origin()
      |> put_private(:plug_skip_csrf_protection, true)
    else
      conn |> send_resp(404, "") |> halt()
    end
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      403,
      Jason.encode!(%{
        code: "origin_not_allowed",
        recovery_action: "reload_same_origin",
        retryable: false,
        status: 403,
        title: "Origin not allowed",
        type: "/problems/origin_not_allowed"
      })
    )
    |> halt()
  end
end
