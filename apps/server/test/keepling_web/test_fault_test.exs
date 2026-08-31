defmodule KeeplingWeb.TestFaultTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias KeeplingWeb.TestFaultController

  @credential "plan-01-17-random-test-credential"

  setup do
    previous = System.get_env("KEEPLING_TEST_FAULT_TOKEN")
    System.put_env("KEEPLING_TEST_FAULT_TOKEN", @credential)

    on_exit(fn ->
      if previous do
        System.put_env("KEEPLING_TEST_FAULT_TOKEN", previous)
      else
        System.delete_env("KEEPLING_TEST_FAULT_TOKEN")
      end
    end)
  end

  test "before-acceptance fault drops the request before downstream work" do
    conn = TestFaultController.call(fault_conn("before_acceptance"), [])

    assert conn.halted
    assert conn.status == 503
    assert conn.resp_body =~ ~s("code":"test_transport_unavailable")
    refute conn.resp_body =~ @credential
  end

  test "after-commit fault drops only when the downstream response is sent" do
    conn = TestFaultController.call(fault_conn("after_commit"), [])

    assert conn.state == :unset

    assert_raise TestFaultController.ConnectionDropped, "test connection dropped", fn ->
      send_resp(conn, 200, ~s({"outcome":"accepted"}))
    end
  end

  test "fault controls are credentialed, closed, and privacy-safe" do
    conn =
      conn(:post, "/api/v1/commands/complete-task")
      |> put_req_header("x-keepling-test-fault", "after_commit")
      |> put_req_header("x-keepling-test-fault-token", "wrong")
      |> TestFaultController.call([])

    assert conn.halted
    assert conn.status == 404
    refute conn.resp_body =~ @credential
  end

  test "authentication interruption can occur before acceptance without downstream work" do
    conn = TestFaultController.call(fault_conn("authentication_before_acceptance"), [])

    assert conn.halted
    assert conn.status == 401
    assert conn.resp_body =~ ~s("code":"authentication_required")
    refute conn.resp_body =~ @credential
  end

  test "authentication interruption can replace only the downstream response" do
    conn = TestFaultController.call(fault_conn("authentication_after_commit"), [])
    response = send_resp(conn, 200, ~s({"outcome":"accepted"}))

    assert response.status == 401
    assert response.resp_body =~ ~s("code":"authentication_required")
    refute response.resp_body =~ @credential
  end

  test "router references the fault plug only inside the test compile gate" do
    source = File.read!(Path.expand("../../lib/keepling_web/router.ex", __DIR__))

    assert source =~ "if Mix.env() == :test do"
    assert source =~ "plug KeeplingWeb.TestFaultController"
    assert source =~ "else: [:api, :authenticated, :mutation]"
  end

  defp fault_conn(mode) do
    conn(:post, "/api/v1/commands/complete-task")
    |> put_req_header("x-keepling-test-fault", mode)
    |> put_req_header("x-keepling-test-fault-token", @credential)
  end
end
