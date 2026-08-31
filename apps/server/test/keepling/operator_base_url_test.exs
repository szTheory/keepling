defmodule Keepling.OperatorBaseURLTest do
  use ExUnit.Case, async: true

  alias Keepling.OperatorBaseURL

  test "rejects remote cleartext and URI userinfo" do
    assert {:error, :invalid_base_url} = OperatorBaseURL.validate("http://keepling.example")

    assert {:error, :invalid_base_url} =
             OperatorBaseURL.validate("https://operator:secret@keepling.example")

    assert {:error, :invalid_base_url} =
             OperatorBaseURL.validate("http://operator:secret@localhost:4000")
  end

  test "accepts HTTPS and loopback HTTP without leaking a prior query or fragment" do
    for accepted <- [
          "https://keepling.example",
          "http://localhost:4000",
          "http://127.12.34.56:4000",
          "http://[::1]:4000"
        ] do
      assert {:ok, uri} = OperatorBaseURL.validate(accepted)
      assert is_binary(uri.host)
    end

    assert {:ok, base_uri} =
             OperatorBaseURL.validate("https://keepling.example/old?unsafe=value#fragment")

    assert OperatorBaseURL.capability_link(base_uri, "/recover", "secret token") ==
             "https://keepling.example/recover?token=secret+token"
  end
end
