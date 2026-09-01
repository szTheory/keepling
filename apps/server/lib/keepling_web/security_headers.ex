defmodule KeeplingWeb.SecurityHeaders do
  @moduledoc """
  Applies the browser execution policy at the endpoint boundary.

  Keeping this plug ahead of static serving ensures the application shell and
  API responses receive the same defense-in-depth policy.
  """

  @behaviour Plug

  import Plug.Conn, only: [put_resp_header: 3]

  @content_security_policy [
                             "default-src 'self'",
                             "base-uri 'none'",
                             "frame-ancestors 'none'",
                             "object-src 'none'",
                             "form-action 'self'",
                             "script-src 'self'",
                             "style-src 'self'",
                             "img-src 'self' data:",
                             "connect-src 'self'"
                           ]
                           |> Enum.join("; ")

  @impl Plug
  def init(options), do: options

  @impl Plug
  def call(conn, _options) do
    put_resp_header(conn, "content-security-policy", @content_security_policy)
  end

  @spec content_security_policy() :: String.t()
  def content_security_policy, do: @content_security_policy
end
