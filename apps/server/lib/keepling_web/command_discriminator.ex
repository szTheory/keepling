defmodule KeeplingWeb.CommandDiscriminator do
  @moduledoc """
  Accepts, and VERIFIES, the optional `type` discriminator an offline client
  carries inside its durable command bytes (D-49, found by O-34).

  ## Why the field exists at all

  An offline-first client commits the serialized command to a durable outbox
  BEFORE reporting success, and retries those exact bytes -- never
  re-serialized -- until the server acknowledges them. After a relaunch the
  bytes are all that survives, so they must say what command they are or the
  queue cannot route them. The browser has no outbox: it posts to a typed
  endpoint and forgets, so it neither sends nor needs this field.

  That is the whole asymmetry. The field is OPTIONAL for exactly that
  reason, and the request is otherwise byte-identical across adapters, which
  is what SRV-02 means by one set of semantic invariants.

  ## Why the server verifies it rather than trusting it

  Routing is derived from the URL and ONLY from the URL. This plug never
  dispatches on `type`; it checks that the client's own description agrees
  with the endpoint it was posted to, and refuses the request when it does
  not. A body claiming `complete_task` posted to `/commands/capture-task` is
  a client bug or an attack, and either way must be a loud 400 rather than a
  silently-honoured guess about which one the caller meant.

  Once verified, the key is REMOVED before the controller decodes the body,
  so every command decoder keeps its exact-key discipline unchanged and no
  decoder had to learn about this field.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(%{params: %{"type" => declared}} = conn, _options) when is_binary(declared) do
    if String.replace(declared, "_", "-") == List.last(conn.path_info) do
      %{conn | params: Map.delete(conn.params, "type")}
    else
      refuse(conn)
    end
  end

  def call(%{params: %{"type" => _not_a_string}} = conn, _options), do: refuse(conn)

  def call(conn, _options), do: conn

  defp refuse(conn) do
    conn
    |> put_resp_content_type("application/problem+json")
    |> send_resp(
      400,
      Jason.encode!(%{
        code: "invalid_command",
        recovery_action: "correct_request",
        retryable: false,
        status: 400,
        title: "Invalid command",
        type: "/problems/invalid_command"
      })
    )
    |> halt()
  end
end
