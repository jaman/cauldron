defmodule Cauldron2D.Drafter.Client.Picture do
  @moduledoc """
  How a game's picture (a scene's `:picture`) reaches a terminal that keeps images: the
  size it is drawn at, how each frame is encoded, and whether frames are double
  buffered. Options are a list, or a comma-separated string:

    * `native` — drawn at the game's own size times the largest whole number that fits
      the pane, the terminal scaling it to the pane
    * `native:N` — at the game's own size times `N`
    * `size:WxH` — the game's own size is `W` by `H` pixels, over what the game declares
      (a scene's `:native`, else the look's `:native`)
    * `png` — each frame is sent as a PNG, palette when it has at most 256 colours, in
      place of deflated raw pixels
    * `swap` — each frame is stored before the last is let go, so the pane never blanks
      between frames
    * `gpu` — a scene that describes itself for the graphics card (a scene's `:gpu`) is
      drawn by `CauldronGPU` at the pane's size in pixels and shown in the pane; other
      scenes, and every scene when no graphics card opens, are drawn as without it
    * `window` — as `gpu`, but in a window of its own: keys pressed in the window reach
      the client as the terminal's do, and the pane is left empty while the window opens and is open
    * `software` — never the graphics card

  Without `gpu`, `window` or `software` the player's drawing setting decides
  (`Cauldron2D.Drafter.Client.Settings`), which by default uses the graphics card in the
  pane when there is one.
    * `none` — none of these

  Without `native`, or with it when neither the game nor `size` gives a size, the picture
  is drawn at the pane's cells times the surface's density and sent as raw pixels.

  `options/2` reads a client's options from its mount props (`:picture`), else the
  application env `config :cauldron_2d_drafter, picture: ...`, else the environment
  variable `CAULDRON_PICTURE`, else the game's look (`:picture`), else `default/0`. `surface_props/3` turns them into
  `Cauldron2D.Drafter.Surface` props.

      iex> Cauldron2D.Drafter.Client.Picture.parse("native:2,png,swap")
      {:ok, [{:native, 2}, :png, :swap]}
  """

  @type option ::
          :native
          | {:native, pos_integer()}
          | {:size, {pos_integer(), pos_integer()}}
          | :png
          | :swap
          | :gpu
          | :window
          | :software

  @default [{:native, 2}, :swap]

  @doc "The options used when none are given."
  @spec default() :: [option()]
  def default, do: @default

  @doc """
  The options a string names, or the list given back, with the first that is not an
  option as the error.
  """
  @spec parse(String.t() | [option()]) :: {:ok, [option()]} | {:error, String.t()}
  def parse(options) when is_list(options) do
    case Enum.reject(options, &option?/1) do
      [] -> {:ok, options}
      [other | _rest] -> {:error, not_an_option(other)}
    end
  end

  def parse("none"), do: {:ok, []}

  def parse(string) when is_binary(string) do
    string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, options} ->
      case option(name) do
        {:ok, option} -> {:cont, {:ok, options ++ [option]}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  The options for a client of a game whose look is `look`, mounted with `props`: the
  `:picture` prop, else the application env, else `CAULDRON_PICTURE`, else the look's
  `:picture`, else `default/0`. Raises `ArgumentError` when the one found does not parse.
  """
  @spec options(map(), map()) :: [option()]
  def options(props, look) do
    case Map.get(props, :picture) || Application.get_env(:cauldron_2d_drafter, :picture) ||
           System.get_env("CAULDRON_PICTURE") || Map.get(look, :picture) do
      nil -> @default
      given -> parse!(given)
    end
  end

  @doc """
  Where `options` ask for scenes to be drawn: on the graphics card in the pane (`:pane`)
  or a window (`:window`), never on it (`:software`), or `nil` when they do not say.
  """
  @spec gpu([option()]) :: :pane | :window | :software | nil
  def gpu(options) do
    cond do
      :software in options -> :software
      :window in options -> :window
      :gpu in options -> :pane
      true -> nil
    end
  end

  @doc """
  The `:native`, `:native_scale`, `:picture_format` and `:swap` props of a
  `Cauldron2D.Drafter.Surface` showing `scene` under `look` with `options`. A scene with a
  `:gpu` is drawn at the pane's own pixels.
  """
  @spec surface_props([option()], map(), map()) :: keyword()
  def surface_props(options, scene, look) do
    [
      native: if(Map.has_key?(scene, :gpu), do: :pane, else: native_size(options, scene, look)),
      native_scale: Enum.find_value(options, :fit, &scale/1),
      picture_format: if(:png in options, do: :png, else: :rgba),
      swap: :swap in options
    ]
  end

  defp parse!(given) do
    case parse(given) do
      {:ok, options} -> options
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp native_size(options, scene, look) do
    if Enum.any?(options, &native?/1),
      do:
        Enum.find_value(options, &declared_size/1) || Map.get(scene, :native) ||
          Map.get(look, :native)
  end

  defp native?(:native), do: true
  defp native?({:native, _scale}), do: true
  defp native?(_option), do: false

  defp declared_size({:size, size}), do: size
  defp declared_size(_option), do: nil

  defp scale({:native, scale}), do: scale
  defp scale(_option), do: nil

  defp option?(option) when option in [:native, :png, :swap, :gpu, :window, :software], do: true
  defp option?({:native, scale}), do: is_integer(scale) and scale > 0

  defp option?({:size, {width, height}}),
    do: is_integer(width) and is_integer(height) and width > 0 and height > 0

  defp option?(_other), do: false

  defp option("native"), do: {:ok, :native}
  defp option("png"), do: {:ok, :png}
  defp option("swap"), do: {:ok, :swap}
  defp option("gpu"), do: {:ok, :gpu}
  defp option("window"), do: {:ok, :window}
  defp option("software"), do: {:ok, :software}

  defp option("native:" <> scale) do
    case Integer.parse(scale) do
      {times, ""} when times > 0 -> {:ok, {:native, times}}
      _other -> {:error, "native:N takes a whole number above 0: not #{inspect(scale)}"}
    end
  end

  defp option("size:" <> size) do
    with [width, height] <- String.split(size, "x"),
         {width, ""} when width > 0 <- Integer.parse(width),
         {height, ""} when height > 0 <- Integer.parse(height) do
      {:ok, {:size, {width, height}}}
    else
      _other -> {:error, "size:WxH takes two whole numbers above 0: not #{inspect(size)}"}
    end
  end

  defp option(other), do: {:error, not_an_option(other)}

  defp not_an_option(other),
    do:
      "#{inspect(other)} is not a picture option: native, native:N, size:WxH, png, swap, or none"
end
