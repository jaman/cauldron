defmodule Cauldron3D.Net.Events do
  @moduledoc """
  Browser input as `CauldronGPU` window events. The client (`cauldron3d.js`) sends maps
  with a `"type"`; `decode/1` turns each into the event tuple a native window would send,
  or `:error`. Key names are those `cauldron3d.js` reports (`"w"`, `"space"`,
  `"left_shift"`, `"up"`, …); names outside that set arrive as strings.
  """

  @keys ~w(a b c d e f g h i j k l m n o p q r s t u v w x y z
           0 1 2 3 4 5 6 7 8 9 space return escape tab backspace delete
           up down left right left_shift right_shift left_ctrl right_ctrl left_alt right_alt
           f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12)

  @key_atoms Map.new(@keys, &{&1, String.to_atom(&1)})

  @doc "The event a browser message describes."
  @spec decode(map()) :: {:ok, term()} | :error
  def decode(%{"type" => "key", "action" => action, "key" => key} = message)
      when action in ["down", "up"],
      do: {:ok, {:key, String.to_existing_atom(action), key(key), message["repeat"] == true}}

  def decode(%{"type" => "mouse_motion", "x" => x, "y" => y, "dx" => dx, "dy" => dy}),
    do: {:ok, {:mouse_motion, x / 1, y / 1, dx / 1, dy / 1}}

  def decode(%{
        "type" => "mouse_button",
        "action" => action,
        "button" => button,
        "x" => x,
        "y" => y
      })
      when action in ["down", "up"] and is_integer(button),
      do: {:ok, {:mouse_button, String.to_existing_atom(action), button, x / 1, y / 1}}

  def decode(%{"type" => "mouse_wheel", "dx" => dx, "dy" => dy}),
    do: {:ok, {:mouse_wheel, dx / 1, dy / 1}}

  def decode(%{"type" => "resized", "width" => width, "height" => height})
      when is_integer(width) and is_integer(height),
      do: {:ok, {:resized, width, height}}

  def decode(%{"type" => "focus", "focused" => focused}) when is_boolean(focused),
    do: {:ok, {:focus, focused}}

  def decode(_message), do: :error

  defp key(name), do: Map.get(@key_atoms, name, name)
end
