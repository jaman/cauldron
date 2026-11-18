defmodule Greenware.Fonts do
  @moduledoc """
  The two bitmap faces of Greenware: a typewriter for the world and a Baskerville for
  names and titles. Both are placeholder sheets cut from system faces, drawn white so
  the renderer can tint them; the final faces replace the PNGs without touching code.
  """

  alias Linocut.BitmapFont

  @chars for code <- 32..126, into: "", do: <<code>>

  @body_key {__MODULE__, :body}
  @display_key {__MODULE__, :display}

  @doc "The body face: 24 by 40 pixel cells."
  def body, do: fetch(@body_key, "body.png", {24, 40}, line: 40)

  @doc "The display face: 60 by 92 pixel cells."
  def display, do: fetch(@display_key, "display.png", {60, 92}, line: 92)

  @doc "How wide `text` is in the body face."
  def body_width(text), do: div(BitmapFont.width(body(), text), 2)

  @doc "How wide `text` is in the display face."
  def display_width(text), do: div(BitmapFont.width(display(), text), 2)

  @doc "The body face wrapped to `width` pixels, as placements."
  def wrap(text, width), do: BitmapFont.layout(body(), text, wrap: width)

  defp fetch(key, file, cell, opts) do
    case :persistent_term.get(key, nil) do
      nil ->
        path = Path.join([:code.priv_dir(:greenware), "fonts", file])
        {:ok, sheet} = path |> File.read!() |> Linocut.Png.decode()

        font =
          BitmapFont.from_sheet(sheet, cell, @chars,
            fixed: true,
            upcase: false,
            line: Keyword.fetch!(opts, :line),
            spacing: 0
          )

        :persistent_term.put(key, font)
        font

      font ->
        font
    end
  end
end
