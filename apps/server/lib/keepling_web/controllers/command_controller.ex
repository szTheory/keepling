defmodule KeeplingWeb.CommandController do
  use KeeplingWeb, :controller

  alias Keepling.Adapters.Postgres.CommandStore
  alias Keepling.Application.Commands
  alias KeeplingWeb.Auth

  def test_session(conn, _params) do
    case Auth.sign_in_test_account(conn) do
      {:ok, signed_in_conn, csrf_token} -> json(signed_in_conn, %{csrf_token: csrf_token})
      {:error, :fixture_unavailable} -> infrastructure_problem(conn)
    end
  end

  def session(conn, _params) do
    json(conn, %{csrf_token: Plug.CSRFProtection.get_csrf_token()})
  end

  def inbox(conn, _params) do
    case Commands.list_inbox(context(conn), CommandStore) do
      {:ok, tasks} -> json(conn, %{tasks: tasks})
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def organizations(conn, _params) do
    case Commands.list_organizations(context(conn), CommandStore) do
      {:ok, organizations} -> json(conn, %{organizations: organizations})
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def capture_task(conn, params) do
    with {:ok, command} <- decode_capture(params),
         {:ok, result} <- Commands.dispatch(command, context(conn), CommandStore) do
      respond(conn, result)
    else
      {:error, :invalid_command} -> invalid_command(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  def edit_task(conn, params),
    do: dispatch_task_command(conn, decode_edit(params, :edit_task, false))

  def clarify_task(conn, params),
    do: dispatch_task_command(conn, decode_edit(params, :clarify_task, true))

  def return_to_inbox(conn, params),
    do: dispatch_task_command(conn, decode_return_to_inbox(params))

  def create_organization(conn, params),
    do: dispatch_task_command(conn, decode_create_organization(params))

  def rename_organization(conn, params),
    do: dispatch_task_command(conn, decode_rename_organization(params))

  def archive_organization(conn, params),
    do: dispatch_task_command(conn, decode_organization_lifecycle(params, :archive_organization))

  def unarchive_organization(conn, params),
    do:
      dispatch_task_command(conn, decode_organization_lifecycle(params, :unarchive_organization))

  def assign_task_organizations(conn, params),
    do: dispatch_task_command(conn, decode_task_organizations(params))

  def mutation(conn, %{"mutation_id" => mutation_id}) do
    with {:ok, _uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, result} <- Commands.lookup_result(context(conn), mutation_id, CommandStore) do
      respond(conn, result)
    else
      :error -> invalid_command(conn)
      {:error, :not_found} -> not_found_problem(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp decode_capture(params) do
    allowed_keys = ["mutation_id", "task_id", "title", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "title" => title,
           "version" => 1
         }
         when is_binary(title) <- params,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         mutation_id: mutation_id,
         task_id: task_id,
         title: title,
         type: :capture_task,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp dispatch_task_command(conn, decoded) do
    with {:ok, command} <- decoded,
         {:ok, result} <- Commands.dispatch(command, context(conn), CommandStore) do
      respond(conn, result)
    else
      {:error, :invalid_command} -> invalid_command(conn)
      {:error, :infrastructure_failure} -> infrastructure_problem(conn)
    end
  end

  defp decode_edit(params, type, allow_empty) do
    allowed_keys = [
      "base_values",
      "expected_revision",
      "fields",
      "mutation_id",
      "task_id",
      "version"
    ]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "base_values" => base_values,
           "expected_revision" => expected_revision,
           "fields" => fields,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, decoded_fields} <- decode_detail_fields(fields, allow_empty),
         {:ok, decoded_base_values} <- decode_detail_fields(base_values, true),
         true <-
           Map.keys(decoded_fields) |> Enum.sort() == Map.keys(decoded_base_values) |> Enum.sort(),
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         base_values: decoded_base_values,
         expected_revision: expected_revision,
         fields: decoded_fields,
         mutation_id: mutation_id,
         task_id: task_id,
         type: type,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_detail_fields(fields, allow_empty) when is_map(fields) do
    allowed = ["notes", "title"]

    if (allow_empty or map_size(fields) > 0) and
         Enum.all?(fields, fn {key, value} -> key in allowed and is_binary(value) end) do
      {:ok,
       Map.new(fields, fn
         {"notes", value} -> {:notes, value}
         {"title", value} -> {:title, value}
       end)}
    else
      {:error, :invalid_command}
    end
  end

  defp decode_detail_fields(_fields, _allow_empty), do: {:error, :invalid_command}

  defp decode_return_to_inbox(params) do
    allowed_keys = ["expected_revision", "mutation_id", "task_id", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "expected_revision" => expected_revision,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         expected_revision: expected_revision,
         mutation_id: mutation_id,
         task_id: task_id,
         type: :return_to_inbox,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_create_organization(params) do
    allowed_keys = ["kind", "mutation_id", "name", "organization_id", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "kind" => kind,
           "mutation_id" => mutation_id,
           "name" => name,
           "organization_id" => organization_id,
           "version" => 1
         }
         when kind in ["project", "tag"] and is_binary(name) <- params,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _organization_uuid} <- Ecto.UUID.cast(organization_id) do
      {:ok,
       %{
         kind: String.to_existing_atom(kind),
         mutation_id: mutation_id,
         name: name,
         organization_id: organization_id,
         type: :create_organization,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_rename_organization(params) do
    allowed_keys = ["expected_revision", "mutation_id", "name", "organization_id", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "expected_revision" => expected_revision,
           "mutation_id" => mutation_id,
           "name" => name,
           "organization_id" => organization_id,
           "version" => 1
         }
         when is_binary(name) <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _organization_uuid} <- Ecto.UUID.cast(organization_id) do
      {:ok,
       %{
         expected_revision: expected_revision,
         mutation_id: mutation_id,
         name: name,
         organization_id: organization_id,
         type: :rename_organization,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_organization_lifecycle(params, type) do
    allowed_keys = ["expected_revision", "mutation_id", "organization_id", "version"]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "expected_revision" => expected_revision,
           "mutation_id" => mutation_id,
           "organization_id" => organization_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _organization_uuid} <- Ecto.UUID.cast(organization_id) do
      {:ok,
       %{
         expected_revision: expected_revision,
         mutation_id: mutation_id,
         organization_id: organization_id,
         type: type,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_task_organizations(params) do
    allowed_keys = [
      "base_values",
      "expected_revision",
      "fields",
      "mutation_id",
      "task_id",
      "version"
    ]

    with true <- Enum.sort(Map.keys(params)) == allowed_keys,
         %{
           "base_values" => base_values,
           "expected_revision" => expected_revision,
           "fields" => fields,
           "mutation_id" => mutation_id,
           "task_id" => task_id,
           "version" => 1
         } <- params,
         true <- is_integer(expected_revision) and expected_revision >= 1,
         {:ok, decoded_base_values} <- decode_assignment_values(base_values),
         {:ok, decoded_fields} <- decode_assignment_values(fields),
         {:ok, _mutation_uuid} <- Ecto.UUID.cast(mutation_id),
         {:ok, _task_uuid} <- Ecto.UUID.cast(task_id) do
      {:ok,
       %{
         base_values: decoded_base_values,
         expected_revision: expected_revision,
         fields: decoded_fields,
         mutation_id: mutation_id,
         task_id: task_id,
         type: :assign_task_organizations,
         version: 1
       }}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_assignment_values(%{"project_id" => project_id, "tag_ids" => tag_ids} = values)
       when map_size(values) == 2 and (is_nil(project_id) or is_binary(project_id)) and
              is_list(tag_ids) do
    with :ok <- cast_optional_uuid(project_id),
         true <- Enum.all?(tag_ids, &match?({:ok, _uuid}, Ecto.UUID.cast(&1))),
         true <- length(tag_ids) == MapSet.size(MapSet.new(tag_ids)) do
      {:ok, %{project_id: project_id, tag_ids: Enum.sort(tag_ids)}}
    else
      _ -> {:error, :invalid_command}
    end
  end

  defp decode_assignment_values(_values), do: {:error, :invalid_command}

  defp cast_optional_uuid(nil), do: :ok

  defp cast_optional_uuid(value),
    do: if(match?({:ok, _uuid}, Ecto.UUID.cast(value)), do: :ok, else: :error)

  defp context(conn) do
    %{
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      account_id: conn.assigns.current_account_id,
      actor_type: "user",
      client_kind: "web"
    }
  end

  defp respond(conn, %{status: status, body: body}) do
    conn
    |> put_status(status)
    |> maybe_problem_content_type(status)
    |> json(body)
  end

  defp maybe_problem_content_type(conn, status) when status >= 400,
    do: put_resp_content_type(conn, "application/problem+json")

  defp maybe_problem_content_type(conn, _status), do: conn

  defp invalid_command(conn) do
    problem(
      conn,
      400,
      "invalid_command",
      "Invalid command",
      "Send a closed version 1 semantic command shape.",
      false,
      "correct_request"
    )
  end

  defp not_found_problem(conn) do
    problem(
      conn,
      404,
      "mutation_not_found",
      "Mutation not found",
      nil,
      true,
      "retry_original_mutation"
    )
  end

  defp infrastructure_problem(conn) do
    problem(
      conn,
      503,
      "service_unavailable",
      "Keepling is temporarily unavailable",
      "Your request was not confirmed. Check again with the same mutation identity.",
      true,
      "check_mutation_result"
    )
  end

  defp problem(conn, status, code, title, detail, retryable, recovery_action) do
    body = %{
      code: code,
      recovery_action: recovery_action,
      retryable: retryable,
      status: status,
      title: title,
      type: "/problems/#{code}"
    }

    body = if detail, do: Map.put(body, :detail, detail), else: body

    conn
    |> put_status(status)
    |> put_resp_content_type("application/problem+json")
    |> json(body)
  end
end
