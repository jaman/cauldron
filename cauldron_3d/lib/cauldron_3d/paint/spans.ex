defmodule Cauldron3D.Paint.Spans do
  @moduledoc """
  The RGBA pixels of one row's run of a textured polygon, for `Cauldron3D.Paint.Rgba`.

      planes = {w0, wx, uw0, uwx, vw0, vwx}
      Cauldron3D.Paint.Spans.texture({pixels, 64, 64, colours}, nil, nil, planes, {10, 90})

  A texture is `{pixels, width, height, colours}`, and a run `{first, stop}`, the pixels
  from `first` up to `stop`. `planes` is a row's `{w, uw, vw}` planes as `{at_x_zero, per_x}` pairs, flattened; the
  texel at pixel `x` is at `floor(uw / w)`, `floor(vw / w)` taken at `x + 0.5`.
  `colours` is the texture's `Cauldron3D.Texture.colours/1` table for an indexed texture,
  or `nil` for an RGBA one.

  `available?/0` says whether the C library loaded. Where it did not the same bytes are
  made in Elixir.
  """

  alias Cauldron3D.Texture

  @on_load :load_nif

  @type source :: {binary(), pos_integer(), pos_integer(), binary() | nil}
  @type run :: {integer(), integer()}
  @type planes :: {number(), number(), number(), number(), number(), number()}
  @type light :: nil | number() | {number(), number(), number()} | {:plane, number(), number()}

  @clear <<0, 0, 0, 0>>

  @doc false
  def load_nif do
    "span_nif"
    |> Cauldron3D.Native.path()
    |> :erlang.load_nif(0)
    |> then(&:persistent_term.put({__MODULE__, :native}, &1 == :ok))
  end

  @doc "Whether the library is loaded and spans are filled in C."
  @spec available?() :: boolean()
  def available?, do: :persistent_term.get({__MODULE__, :native}, false)

  @doc """
  Pixels `first` up to `stop` of a texture repeated both ways. A texel of index `clear`
  in an indexed texture is `<<0, 0, 0, 0>>`. `light` multiplies red, green and blue: a
  scale, one scale a channel, `{:plane, origin, per_x}` for the scale
  `(origin + per_x * (x + 0.5)) / 128` at pixel `x`, or `nil` for none.
  """
  @spec texture(source(), byte() | nil, light(), planes(), run()) :: binary()
  def texture({pixels, width, height, colours}, clear, light, planes, {first, stop}) do
    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(planes, x)
      at = Integer.mod(v, height) * width + Integer.mod(u, width)
      texel(pixels, colours, at, clear) |> lit(light, x)
    end
  end

  @doc "Pixels `first` up to `stop` of a texture whose edge pixels repeat beyond it."
  @spec surface(source(), planes(), run()) :: binary()
  def surface({pixels, width, height, colours}, planes, {first, stop}) do
    for x <- first..(stop - 1)//1, into: <<>> do
      {u, v} = uv(planes, x)
      column = u |> max(0) |> min(width - 1)
      row = v |> max(0) |> min(height - 1)
      texel(pixels, colours, row * width + column, nil)
    end
  end

  @doc """
  `base`, RGBA pixels from column `first`, each channel multiplied by its tint plane over
  `w`: `planes` is `{w0, wx, r0, rx, g0, gx, b0, bx, a0, ax}`, each taken at `x + 0.5`. A
  pixel whose alpha is below `threshold` is `<<0, 0, 0, 0>>`.
  """
  @spec tint(binary(), integer(), tuple(), number()) :: binary()
  def tint(base, first, {w0, wx, r0, rx, g0, gx, b0, bx, a0, ax}, threshold) do
    for {<<r, g, b, a>>, x} <- Enum.with_index(words(base), first), into: <<>> do
      xc = x + 0.5
      w = w0 + wx * xc

      if a < threshold,
        do: @clear,
        else:
          <<channel(r * (r0 + rx * xc) / w), channel(g * (g0 + gx * xc) / w),
            channel(b * (b0 + bx * xc) / w), channel(a * (a0 + ax * xc) / w)>>
    end
  end

  defp uv({w0, wx, u0, ux, v0, vx}, x) do
    xc = x + 0.5
    w = w0 + wx * xc
    {floor((u0 + ux * xc) / w), floor((v0 + vx * xc) / w)}
  end

  defp texel(pixels, nil, at, _clear), do: binary_part(pixels, at * 4, 4)

  defp texel(pixels, colours, at, clear) do
    case :binary.at(pixels, at) do
      ^clear -> @clear
      index -> Texture.colour(colours, index)
    end
  end

  defp lit(@clear, _light, _x), do: @clear
  defp lit(colour, nil, _x), do: colour

  defp lit(<<r, g, b, a>>, {:plane, origin, per_x}, x) do
    scale = (origin + per_x * (x + 0.5)) / 128
    <<channel(r * scale), channel(g * scale), channel(b * scale), a>>
  end

  defp lit(<<r, g, b, a>>, {sr, sg, sb}, _x),
    do: <<channel(r * sr), channel(g * sg), channel(b * sb), a>>

  defp lit(<<r, g, b, a>>, scale, _x),
    do: <<channel(r * scale), channel(g * scale), channel(b * scale), a>>

  defp channel(value) when value >= 255, do: 255
  defp channel(value) when value <= 0, do: 0
  defp channel(value), do: trunc(value)

  defp words(binary), do: for(<<word::binary-4 <- binary>>, do: word)
end
