defmodule Cauldron2D.Easel.View do
  @moduledoc """
  An easel as a browser canvas draws it: the frame in hand as CSS colours, the frame
  before it as a ghost, the palette, and the frames' count and rate. What the LiveView
  editor and the notebook editor both send to their script.

      Cauldron2D.Easel.View.payload(easel, zoom: 16, onion: true)
  """

  alias Cauldron2D.Easel

  @doc """
  The payload for `easel`.

  ## Options

    * `:zoom` — pixels a picture pixel on the canvas. Default `16`
    * `:onion` — show the frame before as a ghost. Default `false`
    * `:shown` — the frame to draw instead of the one in hand, for playback. Default none
  """
  @spec payload(Easel.t(), keyword()) :: map()
  def payload(%Easel{} = easel, opts \\ []) do
    shown = Keyword.get(opts, :shown) || easel.frame
    frame = Enum.at(easel.frames, shown)

    ghost =
      if Keyword.get(opts, :onion, false) and shown > 0, do: Enum.at(easel.frames, shown - 1)

    %{
      width: easel.width,
      height: easel.height,
      zoom: Keyword.get(opts, :zoom, 16),
      frame: easel.frame,
      frames: length(easel.frames),
      fps: easel.fps,
      pixels: rows(easel, frame),
      ghost: ghost && rows(easel, ghost),
      palette: for({key, colour} <- easel.palette, do: %{key: key, css: css(colour)}),
      undo: easel.undo != [],
      redo: easel.redo != []
    }
  end

  defp rows(easel, frame) do
    for row <- Tuple.to_list(frame),
        do: for(key <- Tuple.to_list(row), do: css(Easel.colour(easel, key)))
  end

  @doc "A colour as CSS: `#rrggbb`, `rgba(...)` for a translucent one, `nil` for none."
  @spec css(Easel.rgba() | nil) :: String.t() | nil
  def css(nil), do: nil
  def css({r, g, b, 255}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
  def css({r, g, b, a}), do: "rgba(#{r},#{g},#{b},#{Float.round(a / 255, 3)})"
end
