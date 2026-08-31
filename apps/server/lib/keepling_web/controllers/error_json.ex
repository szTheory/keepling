defmodule KeeplingWeb.ErrorJSON do
  @moduledoc """
  Renders Phoenix transport errors as a closed JSON object.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
