defmodule Keepling.OperatorBaseURL do
  @moduledoc """
  Validates the origin used for one-time operator capability links.

  Cleartext HTTP is restricted to loopback development addresses. Remote
  capability links require HTTPS, and embedded URI credentials are never
  accepted.
  """

  @spec validate(String.t() | nil) :: {:ok, URI.t()} | {:error, :invalid_base_url}
  def validate(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{host: host, scheme: "https", userinfo: nil} = uri
      when is_binary(host) and host != "" ->
        {:ok, normalize(uri)}

      %URI{host: host, scheme: "http", userinfo: nil} = uri
      when is_binary(host) and host != "" ->
        if loopback_host?(host), do: {:ok, normalize(uri)}, else: {:error, :invalid_base_url}

      _invalid ->
        {:error, :invalid_base_url}
    end
  end

  def validate(_value), do: {:error, :invalid_base_url}

  @spec capability_link(URI.t(), String.t(), String.t()) :: String.t()
  def capability_link(%URI{} = base_uri, path, token) do
    %{base_uri | path: path, query: URI.encode_query(%{"token" => token}), fragment: nil}
    |> URI.to_string()
  end

  defp normalize(uri), do: %{uri | query: nil, fragment: nil}

  defp loopback_host?(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, {127, _second, _third, _fourth}} -> true
      {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} -> true
      _other -> String.downcase(host) == "localhost"
    end
  end
end
