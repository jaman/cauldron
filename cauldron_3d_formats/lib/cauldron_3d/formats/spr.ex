defmodule Cauldron3D.Formats.Spr do
  @moduledoc """
  A sprite, `.spr`: flat pictures that face the viewer, Quake's (version 1) or
  Half-Life's (version 2, with its own palette and a `format` for how it is drawn).

      {:ok, sprite} = Cauldron3D.Formats.Spr.parse(bytes)

  `frames` is a tuple of `{:single, picture}` or `{:group, [{picture, until}]}`, each
  picture `%{texture: Cauldron3D.Texture.t(), origin: {x, y}}`, the origin being the
  pixel that sits on the entity. Colour 255 is see-through.
  """

  alias Cauldron3D.Texture

  @enforce_keys [:kind, :frames, :mins, :maxs]
  defstruct [:kind, :frames, :mins, :maxs, format: :normal]

  @type t :: %__MODULE__{}

  @kinds {:parallel_upright, :facing_upright, :parallel, :oriented, :parallel_oriented}

  @doc "The sprite in `data`."
  @spec parse(binary()) :: {:ok, t()} | {:error, :not_a_sprite}
  def parse(
        <<"IDSP", 1::little-32, kind::little-32, _radius::little-float-32, width::little-32,
          height::little-32, count::little-32, _beam::little-float-32, _sync::little-32,
          rest::binary>>
      ) do
    {frames, _rest} = Enum.map_reduce(1..max(count, 1)//1, rest, fn _, acc -> frame(acc) end)
    half = max(width, height) / 2

    {:ok,
     %__MODULE__{
       kind: elem(@kinds, min(kind, 4)),
       frames: List.to_tuple(frames),
       mins: {-half, -half, -half},
       maxs: {half, half, half}
     }}
  end

  def parse(
        <<"IDSP", 2::little-32, kind::little-32, format::little-32, _radius::little-float-32,
          width::little-32, height::little-32, count::little-32, _beam::little-float-32,
          _sync::little-32, colours::little-16, rest::binary>>
      )
      when colours <= 256 do
    <<palette::binary-size(^colours * 3), rest::binary>> = rest
    palette = palette <> :binary.copy(<<0>>, 768 - colours * 3)

    {frames, _rest} =
      Enum.map_reduce(1..max(count, 1)//1, rest, fn _, acc -> frame(acc, palette) end)

    half = max(width, height) / 2

    {:ok,
     %__MODULE__{
       kind: elem(@kinds, min(kind, 4)),
       frames: List.to_tuple(frames),
       mins: {-half, -half, -half},
       maxs: {half, half, half},
       format: elem({:normal, :additive, :index_alpha, :alpha_test}, min(format, 3))
     }}
  end

  def parse(_data), do: {:error, :not_a_sprite}

  @doc """
  A frame's picture as an RGBA texture by the sprite's format: `:normal` and `:additive`
  opaque, `:alpha_test` see-through at colour 255, `:index_alpha` the palette's last
  colour with each pixel's index as its alpha.
  """
  @spec rgba(t(), Texture.t(), binary() | nil) :: Texture.t()
  def rgba(%__MODULE__{format: format}, %Texture{} = texture, palette \\ nil) do
    palette = texture.palette || palette
    colours = Texture.colours(palette)
    <<_::binary-765, lr, lg, lb>> = palette

    pixels =
      for <<index <- texture.pixels>>, into: <<>> do
        case format do
          :index_alpha -> <<lr, lg, lb, index>>
          :alpha_test when index == 255 -> <<0, 0, 0, 0>>
          _ -> Texture.colour(colours, index)
        end
      end

    Texture.rgba(texture.width, texture.height, pixels)
  end

  @doc "Every frame's picture, groups opened up, in order."
  @spec pictures(t()) :: [map()]
  def pictures(%__MODULE__{frames: frames}) do
    frames
    |> Tuple.to_list()
    |> Enum.flat_map(fn
      {:single, picture} -> [picture]
      {:group, pictures} -> Enum.map(pictures, &elem(&1, 0))
    end)
  end

  @doc "The picture of frame number `frame` at `time` seconds."
  @spec picture(t(), integer(), number()) :: map()
  def picture(%__MODULE__{frames: frames}, frame, time) do
    case frame >= 0 and frame < tuple_size(frames) and elem(frames, frame) do
      {:single, picture} -> picture
      {:group, pictures} -> grouped(pictures, time)
      _ -> first(elem(frames, 0))
    end
  end

  defp first({:single, picture}), do: picture
  defp first({:group, [{picture, _} | _]}), do: picture

  defp grouped(pictures, time) do
    {_, cycle} = List.last(pictures)
    at = if cycle > 0, do: :math.fmod(time, cycle), else: 0.0

    Enum.find_value(pictures, elem(hd(pictures), 0), fn {picture, until} ->
      if at < until, do: picture
    end)
  end

  defp frame(data, palette \\ nil)

  defp frame(<<0::little-32, rest::binary>>, palette) do
    picture(rest, palette)
    |> then(fn {picture, rest} -> {{:single, picture}, rest} end)
  end

  defp frame(<<1::little-32, count::little-32, rest::binary>>, palette) do
    <<intervals::binary-size(^count * 4), rest::binary>> = rest
    untils = for <<until::little-float-32 <- intervals>>, do: until
    {pictures, rest} = Enum.map_reduce(1..count, rest, fn _, acc -> picture(acc, palette) end)
    {{:group, Enum.zip(pictures, untils)}, rest}
  end

  defp picture(
         <<x::little-signed-32, y::little-signed-32, width::little-32, height::little-32,
           rest::binary>>,
         palette
       ) do
    <<pixels::binary-size(^width * ^height), rest::binary>> = rest

    texture =
      if palette,
        do: Texture.new(width, height, pixels, palette),
        else: Texture.new(width, height, pixels)

    {%{texture: texture, origin: {-x, y}}, rest}
  end
end
