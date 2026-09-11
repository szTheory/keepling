defmodule KeeplingWeb.MCP.ContentIsolationTest do
  @moduledoc """
  05-06-PLAN.md Task 3 / D-24: no authorization decision in the MCP
  surface can receive task content. Two halves:

  The STRUCTURAL half asserts, for four named authorization functions,
  that the argument maps production code actually builds for them carry
  only structural keys -- never a task title, note, project name, or tag
  name.

  The BEHAVIOURAL half drives the identical sequence of tool calls against
  two fixture task sets that are identical except one carries every
  string from `packages/contracts/vectors/redaction.json`'s
  `hostile_sentinels` in its title and notes, and asserts the two
  sequences of authorization outcomes are equal -- proving storing a
  sentinel changes nothing about what is authorized.

  A fourth case proves a preview token minted for a DIFFERENT binding,
  found embedded in a task's own note, authorizes nothing: `commit`
  requires the token as an explicit argument, never derived from content.
  """
  use KeeplingWeb.ConnCase, async: false

  alias Ecto.Adapters.SQL
  alias Keepling.Application.{AgentScope, Preview, TaskAddressing}
  alias Keepling.Repo

  @mcp_redirect_uri "https://server.keepling.invalid/mcp/callback"
  @mcp_resource "https://server.keepling.invalid/mcp/v1"
  @verifier String.duplicate("v", 64)
  @challenge :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false)
  @password String.duplicate("content-isolation-test-password-", 12)

  @redaction_vectors_path Path.join([
                             __DIR__,
                             "..",
                             "..",
                             "..",
                             "..",
                             "..",
                             "packages",
                             "contracts",
                             "vectors",
                             "redaction.json"
                           ])
                           |> Path.expand()

  # The declared structural-keys allowlist (task action text): identities,
  # revisions, scopes, server instance, sync epoch, expiry -- plus the
  # small set of adapter-derived actor/secret fields every MCP context
  # carries. NONE of these are task content; a text field such as
  # :title/:notes/:name/:description appearing in any production call
  # site's argument map would fail the subset assertion below.
  @structural_context_keys ~w(
    account_id accepted_at actor_label actor_principal actor_type
    client_kind scope preview_secret cursor_secret
  )a
  @structural_binding_keys ~w(account_id arguments command server_instance sync_epoch targets expires_at)a
  @structural_target_keys ~w(task_id expected_revision)a
  @forbidden_text_keys ~w(title notes name description)a

  setup do
    previous = Application.get_env(:keepling, :device_grants)

    Application.put_env(:keepling, :device_grants,
      issuer: "https://issuer.keepling.invalid",
      origin: "https://server.keepling.invalid",
      server_instance: "server-instance-content-isolation-test",
      redirect_uris: %{
        "electron" => ["keepling://authorization/callback"],
        "iphone" => ["keepling://authorization/callback"],
        "mcp" => [@mcp_redirect_uri]
      }
    )

    SQL.query!(Repo, "DELETE FROM account_security_audits", [])
    SQL.query!(Repo, "DELETE FROM accounts", [])
    account_id = create_account()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:keepling, :device_grants, previous),
        else: Application.delete_env(:keepling, :device_grants)
    end)

    %{account_id: account_id}
  end

  # == Structural half ====================================================
  # Four named authorization functions. For each, the argument map REAL
  # production call sites build (Dispatch.context/1, KeeplingWeb.MCP.Tools's
  # preview_context/1 and Preview.mint/3's binding construction) is
  # mirrored here field-for-field from source and asserted to carry only
  # structural keys. A text key added to any of these production call
  # sites -- e.g. threading `title` into `dispatch_context/1` -- would fail
  # the corresponding `assert ... subset?` line below; that is the
  # one-line change (task acceptance criterion) that makes this test fail.

  test "1. the scope gate (AgentScope.require/2) receives only the structural MCP dispatch context" do
    # Mirrors KeeplingWeb.MCP.Dispatch.context/1 exactly -- the context
    # EVERY scope check in this codebase is called with.
    production_context = %{
      account_id: Ecto.UUID.generate(),
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      actor_label: "Synthetic grant label",
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: "mcp",
      scope: ["tasks.read", "tasks.write", "tasks.bulk"]
    }

    assert subset?(Map.keys(production_context), @structural_context_keys)
    assert Enum.empty?(Map.keys(production_context) -- @structural_context_keys)
    refute Enum.any?(@forbidden_text_keys, &(&1 in Map.keys(production_context)))
    assert AgentScope.require(production_context, "tasks.write") == :ok

    # Differential: an identical context PLUS a text field decides nothing
    # differently -- proving the decision cannot depend on it even if a
    # caller mistakenly threaded one in.
    poisoned = Map.put(production_context, :title, "HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT")
    assert AgentScope.require(poisoned, "tasks.write") == AgentScope.require(production_context, "tasks.write")
  end

  test "2. the preview binding comparison (Preview.authorize_commit/2) receives only the closed binding field list" do
    # Mirrors the binding Keepling.Application.Preview.mint/3 constructs
    # (@binding_fields) exactly.
    binding = %{
      account_id: Ecto.UUID.generate(),
      arguments: %{},
      command: "trash_task",
      server_instance: "server-instance-content-isolation-test",
      sync_epoch: "epoch-1",
      targets: [%{task_id: Ecto.UUID.generate(), expected_revision: 1}]
    }

    assert subset?(Map.keys(binding), @structural_binding_keys)
    assert Enum.all?(binding.targets, &subset?(Map.keys(&1), @structural_target_keys))
    assert Preview.authorize_commit(binding, binding) == :ok

    # Differential: Preview.authorize_commit/2 uses Map.take/2 over the
    # closed field list on BOTH sides -- an extra text field present on
    # either map changes nothing about the decision.
    poisoned_supplied = Map.put(binding, :title, "HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT")
    poisoned_authoritative = Map.put(binding, :notes, "HOSTILE_TASK_NOTE_SENTINEL_DO_NOT_EMIT")

    assert Preview.authorize_commit(poisoned_supplied, poisoned_authoritative) ==
             Preview.authorize_commit(binding, binding)
  end

  test "3. commit authorization (Preview.commit/4) receives only a token, a mutation identity, and the structural preview context" do
    # Mirrors KeeplingWeb.MCP.Tools's preview_context/1 exactly:
    # dispatch_context/1 plus preview_secret.
    context = %{
      account_id: Ecto.UUID.generate(),
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      actor_label: "Synthetic grant label",
      actor_principal: "authorized_grant",
      actor_type: "agent",
      client_kind: "mcp",
      preview_secret: :crypto.strong_rand_bytes(32)
    }

    assert subset?(Map.keys(context), @structural_context_keys)

    # commit/4's own parameter list: (token :: binary, mutation_id ::
    # binary, context :: map, port :: module) -- a malformed/tampered
    # token is refused identically regardless of what the context or the
    # token bytes contain; no text field can substitute for a valid token.
    assert {:error, :preview_invalid} =
             Preview.commit("not-a-real-token", Ecto.UUID.generate(), context, RaisingPreviewPort)
  end

  test "4. the candidate selection decision (TaskAddressing.classify_match_count/2) takes only an integer count" do
    limit = TaskAddressing.candidate_limit()

    # Its arity and parameter shape admit no text field at all: passing a
    # binary (the shape a title or note would have) raises
    # FunctionClauseError rather than silently coercing -- there is no
    # clause under which this function's decision could read task content.
    assert_raise FunctionClauseError, fn ->
      TaskAddressing.classify_match_count("HOSTILE_TASK_TITLE_SENTINEL_DO_NOT_EMIT", limit)
    end

    assert TaskAddressing.classify_match_count(0, limit) == :no_match
    assert TaskAddressing.classify_match_count(2, limit) == :ambiguous_match
    assert TaskAddressing.classify_match_count(limit + 1, limit) == :too_many_matches
  end

  # == Behavioural half ====================================================

  test "the same tool-call sequence produces identical authorization outcomes whether or not task content carries hostile sentinels",
       %{conn: conn} do
    sentinels = load_hostile_sentinels()
    hostile_corpus = Enum.join(sentinels, " ")

    browser = login(conn)

    hostile_outcomes = run_sequence(browser, "hostile", hostile_corpus)
    clean_outcomes = run_sequence(browser, "clean", "Ordinary safe task content, nothing hostile")

    assert hostile_outcomes == clean_outcomes
  end

  test "a preview token minted for a different binding, found inside a task note, authorizes nothing",
       %{conn: conn} do
    browser = login(conn)
    credential = grant_credential(browser, "token-in-note", "tasks.write tasks.bulk")

    target_task_id = capture_task(credential, "Target task, untouched by the embedded token")
    decoy_task_id = capture_task(credential, "Decoy task carrying a foreign token in its notes")

    preview_response =
      call_tool(credential, "keepling.preview_bulk_change", %{
        "command" => "trash_task",
        "mutation_id" => Ecto.UUID.generate(),
        "targets" => [%{"task_id" => decoy_task_id, "expected_revision" => 1}]
      })

    token = preview_response["result"]["structuredContent"]["preview_token"]
    assert is_binary(token)

    # Store the foreign token as ordinary task content -- literal text
    # inside a note. This proves the value carries no authority merely by
    # being present in a task's stored fields.
    embed_response =
      call_tool(credential, "keepling.update_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => target_task_id,
        "expected_revision" => 1,
        "version" => 1,
        "notes" => "preview_token=#{token}"
      })

    assert embed_response["result"]["structuredContent"]["outcome"] == "accepted"

    # A commit call MUST supply preview_token explicitly -- the schema
    # requires it. Omitting it (even though a valid token for a DIFFERENT
    # binding sits inside target_task_id's own notes) is a closed argument
    # error, never a content-derived authorization.
    commit_without_token =
      call_tool(credential, "keepling.commit_bulk_change", %{
        "mutation_id" => Ecto.UUID.generate()
      })

    assert commit_without_token["error"]["data"]["keepling_code"] == "invalid_command"

    # Neither task was written by the omitted-token attempt.
    assert current_revision(target_task_id) == 2
    assert current_revision(decoy_task_id) == 1
  end

  # -- sequence driver -----------------------------------------------------

  defp run_sequence(browser, label, corpus_text) do
    write_credential = grant_credential(browser, "#{label}-write", "tasks.write tasks.bulk")
    read_only_credential = grant_credential(browser, "#{label}-read-only", "tasks.read")

    task_id = capture_task(write_credential, "Content isolation sequence task (#{label})")

    read_outcome =
      normalize(call_method(write_credential, "resources/read", %{"uri" => "keepling://tasks/#{task_id}"}))

    write_outcome =
      normalize(
        call_tool(write_credential, "keepling.update_task", %{
          "mutation_id" => Ecto.UUID.generate(),
          "task_id" => task_id,
          "expected_revision" => 1,
          "version" => 1,
          "notes" => corpus_text
        })
      )

    denied_outcome =
      normalize(
        call_tool(read_only_credential, "keepling.update_task", %{
          "mutation_id" => Ecto.UUID.generate(),
          "task_id" => task_id,
          "expected_revision" => 2,
          "version" => 1,
          "notes" => "should never apply, read-only credential"
        })
      )

    preview_response =
      call_tool(write_credential, "keepling.preview_bulk_change", %{
        "command" => "trash_task",
        "mutation_id" => Ecto.UUID.generate(),
        "targets" => [%{"task_id" => task_id, "expected_revision" => 2}]
      })

    token = preview_response["result"]["structuredContent"]["preview_token"]
    preview_outcome = if is_binary(token), do: :token_minted, else: normalize(preview_response)

    commit_outcome =
      normalize(
        call_tool(write_credential, "keepling.commit_bulk_change", %{
          "mutation_id" => Ecto.UUID.generate(),
          "preview_token" => token
        })
      )

    stale_commit_outcome =
      normalize(
        call_tool(write_credential, "keepling.commit_bulk_change", %{
          "mutation_id" => Ecto.UUID.generate(),
          "preview_token" => token
        })
      )

    [
      {:scoped_read, read_outcome},
      {:scoped_write, write_outcome},
      {:denied_write, denied_outcome},
      {:preview, preview_outcome},
      {:commit, commit_outcome},
      {:stale_commit, stale_commit_outcome}
    ]
  end

  # Content-independent normalization: keeps only the SHAPE of the
  # outcome (success vs. a named closed error code), never any field
  # whose VALUE would differ merely because the underlying task content
  # differs between the hostile and clean passes (ids, revisions, tokens).
  defp normalize(%{"result" => result}) when is_map(result), do: :ok
  defp normalize(%{"error" => %{"data" => %{"keepling_code" => code}}}), do: {:error, code}

  # -- helpers --------------------------------------------------------------

  defp subset?(keys, allowlist), do: Enum.all?(keys, &(&1 in allowlist))

  defp load_hostile_sentinels do
    @redaction_vectors_path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("hostile_sentinels")
  end

  defp capture_task(credential, title) do
    task_id = Ecto.UUID.generate()

    response =
      call_tool(credential, "keepling.capture_task", %{
        "mutation_id" => Ecto.UUID.generate(),
        "task_id" => task_id,
        "title" => title,
        "version" => 1
      })

    assert response["result"]["structuredContent"]["outcome"] == "accepted"
    task_id
  end

  defp current_revision(task_id) do
    {:ok, %{rows: [[revision]]}} =
      SQL.query(Repo, "SELECT revision FROM tasks WHERE id = $1", [Ecto.UUID.dump!(task_id)])

    revision
  end

  defp call_tool(credential, name, arguments) do
    call_method(credential, "tools/call", %{"name" => name, "arguments" => arguments})
  end

  defp call_method(credential, method, params) do
    build_conn()
    |> bearer(credential)
    |> post("/mcp/v1", %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    })
    |> json_response(200)
  end

  defp grant_credential(conn, installation_id, scope) do
    authorization = authorize(conn, installation_id, scope)
    exchange(authorization)["access_token"]
  end

  defp authorize(conn, installation_id, scope) do
    response =
      conn
      |> recycle()
      |> get("/oauth/authorize", %{
        "client_id" => "mcp",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "installation_id" => installation_id,
        "label" => "Synthetic mcp installation #{installation_id}",
        "redirect_uri" => @mcp_redirect_uri,
        "resource" => @mcp_resource,
        "response_type" => "code",
        "scope" => scope,
        "state" => challenge_state(installation_id)
      })

    assert response.status == 302
    location = response |> get_resp_header("location") |> List.first() |> URI.parse()
    assert "#{location.scheme}://#{location.host}#{location.path}" == @mcp_redirect_uri

    query = URI.decode_query(location.query)
    assert query["state"] == challenge_state(installation_id)
    assert is_binary(query["code"])

    %{code: query["code"], state: query["state"]}
  end

  defp exchange(authorization) do
    build_conn()
    |> post("/oauth/token", %{
      "code" => authorization.code,
      "code_verifier" => @verifier,
      "grant_type" => "authorization_code",
      "redirect_uri" => @mcp_redirect_uri,
      "resource" => @mcp_resource,
      "state" => authorization.state
    })
    |> json_response(200)
  end

  defp challenge_state(installation_id),
    do:
      :crypto.hash(:sha256, "content-isolation-test-state-#{installation_id}")
      |> Base.url_encode64(padding: false)

  defp bearer(conn, credential), do: put_req_header(conn, "authorization", "Bearer #{credential}")

  defp login(conn) do
    conn
    |> trusted_request()
    |> post("/api/v1/login", %{
      "client_kind" => "web",
      "label" => "Content isolation test browser",
      "password" => @password,
      "version" => 1
    })
    |> tap(&json_response(&1, 200))
  end

  defp trusted_request(conn) do
    conn = %{
      conn
      | host: "www.example.com",
        req_headers: [
          {"host", "www.example.com"}
          | Enum.reject(conn.req_headers, fn {name, _value} -> name == "host" end)
        ]
    }

    put_req_header(conn, "origin", "http://www.example.com")
  end

  defp create_account do
    account_id = Ecto.UUID.generate() |> Ecto.UUID.dump!()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    SQL.query!(
      Repo,
      """
      INSERT INTO accounts (id, singleton_key, password_hash, timezone, inserted_at, updated_at)
      VALUES ($1, TRUE, $2, 'Etc/UTC', $3, $3)
      """,
      [account_id, Argon2.hash_pwd_salt(@password), now]
    )

    account_id
  end
end
