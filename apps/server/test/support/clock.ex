defmodule Keepling.TestClock do
  @moduledoc """
  Immutable deterministic time and identity source for semantic command tests.

  Callers thread the returned clock through a scenario, making every consumed
  identity and time movement explicit in the test.
  """

  @enforce_keys [:instant]
  defstruct [:instant, ids: []]

  @type t :: %__MODULE__{instant: DateTime.t(), ids: [term()]}

  @spec new(DateTime.t(), [term()]) :: t()
  def new(%DateTime{} = instant, ids \\ []) when is_list(ids) do
    %__MODULE__{instant: instant, ids: ids}
  end

  @spec now(t()) :: DateTime.t()
  def now(%__MODULE__{instant: instant}), do: instant

  @spec next_id(t()) :: {term(), t()}
  def next_id(%__MODULE__{ids: [id | ids]} = clock) do
    {id, %{clock | ids: ids}}
  end

  def next_id(%__MODULE__{ids: []}) do
    raise ArgumentError, "deterministic identity source is exhausted"
  end

  @spec advance(t(), integer(), System.time_unit()) :: t()
  def advance(%__MODULE__{} = clock, amount, unit) when is_integer(amount) do
    %{clock | instant: DateTime.add(clock.instant, amount, unit)}
  end
end
