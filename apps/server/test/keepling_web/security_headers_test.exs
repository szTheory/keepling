defmodule KeeplingWeb.SecurityHeadersTest do
  use KeeplingWeb.ConnCase, async: true

  @required_directives ~w(
    default-src
    base-uri
    frame-ancestors
    object-src
    form-action
    script-src
    style-src
    img-src
    connect-src
  )

  test "endpoint applies one browser execution policy to a successful static response", %{
    conn: conn
  } do
    response = get(conn, "/robots.txt")

    assert response.status == 200
    assert [_policy] = get_resp_header(response, "content-security-policy")
  end

  test "endpoint applies one browser execution policy to not-found and API responses", %{
    conn: conn
  } do
    not_found = get(conn, "/missing-browser-shell")
    api = post(build_conn(), "/api/v1/setup", %{"version" => 1})

    for response <- [not_found, api] do
      assert [policy] = get_resp_header(response, "content-security-policy")

      for directive <- @required_directives do
        assert policy =~ "#{directive} "
      end
    end
  end

  test "production policy is same-origin, explicit, and contains no executable escape hatch" do
    policy = KeeplingWeb.SecurityHeaders.content_security_policy()

    assert policy =~ "default-src 'self'"
    assert policy =~ "base-uri 'none'"
    assert policy =~ "frame-ancestors 'none'"
    assert policy =~ "object-src 'none'"
    assert policy =~ "form-action 'self'"
    assert policy =~ "script-src 'self'"
    assert policy =~ "style-src 'self'"
    assert policy =~ "img-src 'self' data:"
    assert policy =~ "connect-src 'self'"

    refute policy =~ "unsafe-eval"
    refute policy =~ "unsafe-inline"
    refute policy =~ "*"
    refute policy =~ "http://"
    refute policy =~ "https://"
  end
end
