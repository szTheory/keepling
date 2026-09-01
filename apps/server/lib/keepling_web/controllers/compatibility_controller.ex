defmodule KeeplingWeb.CompatibilityController do
  use KeeplingWeb, :controller

  alias Keepling.Application.Compatibility

  @claim_keys ~w(maximum_protocol_train minimum_protocol_train)

  def show(conn, params) do
    with :ok <- exact_keys(params),
         {:ok, minimum} <- protocol_train(params["minimum_protocol_train"]),
         {:ok, maximum} <- protocol_train(params["maximum_protocol_train"]),
         true <- minimum <= maximum do
      policy =
        :keepling
        |> Application.fetch_env!(:compatibility)
        |> Map.put(
          "now",
          DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
        )

      response =
        %{
          "minimum_protocol_train" => minimum,
          "maximum_protocol_train" => maximum
        }
        |> Compatibility.negotiate(policy)
        |> Map.merge(Compatibility.metadata(policy))

      json(conn, response)
    else
      _invalid -> invalid_claims(conn)
    end
  end

  defp exact_keys(params) do
    if Enum.sort(Map.keys(params)) == @claim_keys, do: :ok, else: {:error, :invalid_shape}
  end

  defp protocol_train(value) when is_binary(value) do
    case Integer.parse(value) do
      {train, ""} when train >= 0 -> {:ok, train}
      _invalid -> {:error, :invalid_train}
    end
  end

  defp protocol_train(_value), do: {:error, :invalid_train}

  defp invalid_claims(conn) do
    conn
    |> put_status(400)
    |> put_resp_content_type("application/problem+json")
    |> json(%{
      code: "invalid_compatibility_claims",
      detail: "Provide only an increasing minimum and maximum integer protocol train.",
      recovery_action: "correct_protocol_range",
      retryable: false,
      status: 400,
      title: "Invalid compatibility claims",
      type: "/problems/invalid_compatibility_claims"
    })
  end
end
