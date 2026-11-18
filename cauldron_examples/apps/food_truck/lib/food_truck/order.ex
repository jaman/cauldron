defmodule FoodTruck.Order do
  @moduledoc """
  A customer's order: its number, the donuts in it and how many of each, when it was
  placed and completed, and its status. The truck moves an order on with `next_step/2`:
  placed orders start being prepared, prepared ones are completed; `complete/2` completes
  one from any status.
  """

  @enforce_keys [:number, :status, :sales, :created_at]
  defstruct [:number, :status, :sales, :created_at, completed_at: nil]

  @type status :: :placed | :preparing | :ready | :completed
  @type t :: %__MODULE__{
          number: pos_integer(),
          status: status(),
          sales: [{FoodTruck.Donut.id(), pos_integer()}],
          created_at: NaiveDateTime.t(),
          completed_at: NaiveDateTime.t() | nil
        }

  @statuses [:placed, :preparing, :ready, :completed]

  @doc "The statuses, in order."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "The order as the truck names it, such as `\"Order#1203\"`."
  @spec title(t()) :: String.t()
  def title(%__MODULE__{number: number}), do: "Order##{number}"

  @doc "The donut ids in the order, in the order they were added."
  @spec donut_ids(t()) :: [FoodTruck.Donut.id()]
  def donut_ids(%__MODULE__{sales: sales}), do: Enum.map(sales, &elem(&1, 0))

  @doc "How many donuts the order holds."
  @spec total(t()) :: non_neg_integer()
  def total(%__MODULE__{sales: sales}), do: Enum.sum_by(sales, &elem(&1, 1))

  @doc "The order after its next step, done `at`: placed to preparing, preparing to completed."
  @spec next_step(t(), NaiveDateTime.t()) :: t()
  def next_step(%__MODULE__{status: :placed} = order, _at), do: %{order | status: :preparing}
  def next_step(%__MODULE__{status: :preparing} = order, at), do: complete(order, at)
  def next_step(%__MODULE__{} = order, _at), do: order

  @doc "The order completed `at`; a completed order keeps its time."
  @spec complete(t(), NaiveDateTime.t()) :: t()
  def complete(%__MODULE__{status: :completed} = order, _at), do: order
  def complete(%__MODULE__{} = order, at), do: %{order | status: :completed, completed_at: at}

  @doc "Whether the order is completed."
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{status: status}), do: status == :completed

  @doc "Whether `search` is in the order's title."
  @spec matches?(t(), String.t()) :: boolean()
  def matches?(%__MODULE__{} = order, search),
    do: String.contains?(String.downcase(title(order)), String.downcase(search))

  @doc "The status's name."
  @spec status_title(status()) :: String.t()
  def status_title(:placed), do: "Placed"
  def status_title(:preparing), do: "Preparing"
  def status_title(:ready), do: "Ready"
  def status_title(:completed), do: "Completed"

  @doc "What the button that takes an order of `status` on says."
  @spec button_title(status()) :: String.t()
  def button_title(:placed), do: "Prepare"
  def button_title(:preparing), do: "Ready"
  def button_title(_status), do: "Complete"

  @doc "The status's icon, as `CauldronNative.UI.icon/2` options: an SF Symbol and a Material icon."
  @spec status_icon(status()) :: keyword()
  def status_icon(:placed), do: [ios: "paperplane", android: "Send"]
  def status_icon(:preparing), do: [ios: "timer", android: "Timer"]
  def status_icon(:ready), do: [ios: "checkmark.circle", android: "CheckCircle"]
  def status_icon(:completed), do: [ios: "shippingbox", android: "Inventory2"]
end
