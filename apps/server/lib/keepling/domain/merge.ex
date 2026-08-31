defmodule Keepling.Domain.Merge do
  @moduledoc """
  Pure, closed three-way merge decisions for semantic task commands.

  A requested field may rebase only while the canonical value still equals
  the submitted base or already equals the requested value. The caller owns
  normalization and invariant checks before and after this decision.
  """

  @spec three_way(map(), map(), map(), [atom()]) ::
          {:ok, map(), map()} | {:conflict, [String.t()]} | {:error, :invalid_merge_fields}
  def three_way(current, base_values, requested_values, allowed_fields)
      when is_map(current) and is_map(base_values) and is_map(requested_values) and
             is_list(allowed_fields) do
    requested_keys = Map.keys(requested_values)

    if requested_keys != [] and
         MapSet.new(requested_keys) == MapSet.new(Map.keys(base_values)) and
         Enum.all?(requested_keys, &(&1 in allowed_fields and Map.has_key?(current, &1))) do
      conflicts =
        requested_values
        |> Enum.reject(fn {field, requested} ->
          canonical = Map.fetch!(current, field)
          canonical == Map.fetch!(base_values, field) or canonical == requested
        end)
        |> Enum.map(fn {field, _requested} -> Atom.to_string(field) end)
        |> Enum.sort()

      if conflicts == [] do
        {merged, changes} =
          Enum.reduce(requested_values, {current, %{}}, fn
            {field, requested}, {merged, changes} ->
              canonical = Map.fetch!(merged, field)

              if canonical == requested do
                {merged, changes}
              else
                {
                  Map.put(merged, field, requested),
                  Map.put(changes, Atom.to_string(field), %{
                    "from" => canonical,
                    "to" => requested
                  })
                }
              end
          end)

        {:ok, merged, changes}
      else
        {:conflict, conflicts}
      end
    else
      {:error, :invalid_merge_fields}
    end
  end

  def three_way(_current, _base_values, _requested_values, _allowed_fields),
    do: {:error, :invalid_merge_fields}
end
