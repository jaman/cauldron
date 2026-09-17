defmodule Cauldron2D.Wx.Input do
  @moduledoc """
  The keys and buttons a desktop player holds, as the input message the server takes.

      input = Cauldron2D.Wx.Input.new(%{?A => :left, 315 => :jump, {:mouse, :left} => :act}, steering: [:left, :right])
      {input, handled?} = Cauldron2D.Wx.Input.press(input, ?A)
      Cauldron2D.Wx.Input.state(input)

  Keys are wx key codes (`?A`, `32`, `315` for the up arrow); buttons `{:mouse, :left | :right | :middle}`.
  A held key of a steering action clears the aim, so the keys take over from the pointer
  until it moves again, as the other clients do.
  """

  @type t :: %__MODULE__{
          keymap: map(),
          steering: [atom()],
          held: MapSet.t(atom()),
          aim: {number(), number()} | nil
        }

  defstruct keymap: %{}, steering: [], held: MapSet.new(), aim: nil

  @doc "An input reading `keymap`; `:steering` names the actions the pointer also drives."
  @spec new(map(), keyword()) :: t()
  def new(keymap, opts \\ []),
    do: %__MODULE__{keymap: keymap, steering: Keyword.get(opts, :steering, [])}

  @doc "A key went down; `{input, whether the key meant anything}`."
  @spec press(t(), integer()) :: {t(), boolean()}
  def press(%__MODULE__{} = input, key) do
    case Map.get(input.keymap, key) do
      nil ->
        {input, false}

      action ->
        {%{
           input
           | held: MapSet.put(input.held, action),
             aim: if(action in input.steering, do: nil, else: input.aim)
         }, true}
    end
  end

  @doc "A key came up; `{input, whether the key meant anything}`."
  @spec release(t(), integer()) :: {t(), boolean()}
  def release(%__MODULE__{} = input, key) do
    case Map.get(input.keymap, key) do
      nil -> {input, false}
      action -> {%{input | held: MapSet.delete(input.held, action)}, true}
    end
  end

  @doc "A mouse button went down or up."
  @spec button(t(), :left | :right | :middle, boolean()) :: t()
  def button(%__MODULE__{} = input, button, down?) do
    case Map.get(input.keymap, {:mouse, button}) do
      nil ->
        input

      action ->
        %{
          input
          | held:
              if(down?,
                do: MapSet.put(input.held, action),
                else: MapSet.delete(input.held, action)
              )
        }
    end
  end

  @doc "The pointer moved to a world position."
  @spec aim(t(), {number(), number()} | nil) :: t()
  def aim(%__MODULE__{} = input, aim), do: %{input | aim: aim}

  @doc "Every key let go, as when the window loses focus."
  @spec drop(t()) :: t()
  def drop(%__MODULE__{} = input), do: %{input | held: MapSet.new()}

  @doc "What to send: the actions held, by name, and the aim as a pair."
  @spec state(t()) :: %{held: [String.t()], aim: [number()] | nil}
  def state(%__MODULE__{held: held, aim: aim}) do
    %{held: held |> Enum.map(&Atom.to_string/1) |> Enum.sort(), aim: aim && Tuple.to_list(aim)}
  end
end
