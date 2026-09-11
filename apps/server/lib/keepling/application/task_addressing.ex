defmodule Keepling.Application.TaskAddressing do
  @moduledoc """
  MCP-03 (D-15, D-16). The ONLY path any MCP write tool resolves its
  target task through.

  `resolve/3` accepts exactly one addressing key -- the opaque task
  identity -- and performs a read-only lookup; any other shape (a title,
  any other free-text key, more than one key) is a closed argument error
  before any query runs. A well-formed but non-UUID-shaped identity is
  `:not_found` -- never a crash, never a probe -- mirroring 05-04's
  established precedent of collapsing a malformed identity into the same
  stable not-found outcome a genuinely absent one produces.

  `candidates/4` is a SEPARATE bounded read reused only for
  disambiguation, when a caller supplies a phrase where an identity
  belongs. It never mutates. The decision of which of the three closed
  outcomes (`no_match`/`ambiguous_match`/`too_many_matches`) to report is
  made by `classify_match_count/2`, which takes only an integer COUNT --
  never the candidate list, never any task content -- so this
  authorization-adjacent decision is structurally incapable of depending
  on what a task's title or notes say (D-24/T-05-28).
  """

  alias Keepling.Application.{Commands, Search}

  @candidate_limit 5

  # Format-only shape check, matching Keepling.Application.Preview's own
  # `@uuid_shape` idiom -- this module has no outward adapter dependency
  # (architecture_test.exs forbids `Ecto` anywhere under
  # lib/keepling/application/), so identity SHAPE is checked with a plain
  # regex rather than `Ecto.UUID.cast/1`. The caller's own decode already
  # casts a genuine identity through `Ecto.UUID.cast/1` before dispatch;
  # this check exists only to decide "does this look like an identity at
  # all" without ever touching the database for a value that plainly
  # is not one.
  @uuid_shape ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  @doc "The closed bound on a single disambiguation candidate set."
  @spec candidate_limit() :: pos_integer()
  def candidate_limit, do: @candidate_limit

  @doc """
  Structural shape check: does `value` look like a stable opaque task
  identity? Used by callers to decide whether to call `resolve/3` (an
  identity) or `candidates/4` (a phrase) -- never by `resolve/3` or
  `candidates/4` themselves to make an authorization decision.
  """
  @spec uuid_shaped?(term()) :: boolean()
  def uuid_shaped?(value) when is_binary(value), do: Regex.match?(@uuid_shape, value)
  def uuid_shaped?(_value), do: false

  @doc """
  Identity-only resolution. `params` must be EXACTLY `%{task_id: id}` --
  any other key, or any additional key alongside `task_id`, falls through
  to a closed argument error before any query runs.
  """
  @spec resolve(map(), map(), module()) ::
          {:ok, map()} | {:error, :not_found | :invalid_command | :infrastructure_failure}
  def resolve(context, %{task_id: task_id} = params, port)
      when map_size(params) == 1 and is_binary(task_id) and is_map(context) do
    if uuid_shaped?(task_id) do
      Commands.get_task(context, task_id, port)
    else
      {:error, :not_found}
    end
  end

  def resolve(_context, _params, _port), do: {:error, :invalid_command}

  @doc """
  Bounded candidate read for disambiguation, reusing
  `Keepling.Application.Search`. Queries `limit + 1` items so the caller
  can distinguish "exactly at the limit" from "over the limit" without a
  second round trip. Performs no write.
  """
  @spec candidates(map(), String.t(), pos_integer(), module()) ::
          {:ok, [map()]} | {:error, atom()}
  def candidates(context, term, limit, port)
      when is_binary(term) and is_integer(limit) and limit > 0 and is_map(context) do
    case Search.query(context, term, %{limit: limit + 1}, port) do
      {:ok, %{items: items}} -> {:ok, items}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Classifies a candidate COUNT into one of the three closed outcomes.
  Takes only an integer -- never the candidate list, never any task
  content -- so the decision is structurally incapable of depending on
  what a task's title or notes say.
  """
  @spec classify_match_count(non_neg_integer(), pos_integer()) ::
          :no_match | :ambiguous_match | :too_many_matches
  def classify_match_count(0, limit) when is_integer(limit) and limit > 0, do: :no_match

  def classify_match_count(count, limit)
      when is_integer(count) and count > limit and is_integer(limit) and limit > 0,
      do: :too_many_matches

  def classify_match_count(count, limit)
      when is_integer(count) and count > 0 and count <= limit and is_integer(limit) and
             limit > 0,
      do: :ambiguous_match
end
