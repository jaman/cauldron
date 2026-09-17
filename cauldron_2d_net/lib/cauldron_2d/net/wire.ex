defmodule Cauldron2D.Net.Wire do
  @moduledoc """
  The Phoenix channel protocol (serializer 2.0.0) as an Elixir client speaks it, and
  the `cauldron_2d_net` messages read into plain shapes: a frame's focus, movers as
  `{index, x, y}`, hud rows of `{text, colour}` runs and the outcome; a map's rows of
  indices; a sheet's tile, frames, URL and void colour. What a desktop view, a terminal
  or any other program joining a served world over its WebSocket draws from.

      Cauldron2D.Net.Wire.encode(join_ref, ref, topic, "phx_join", params)
      Cauldron2D.Net.Wire.decode(text)
      Cauldron2D.Net.Wire.decode_binary(bytes)
  """

  @type message ::
          {:reply, String.t(), String.t(), String.t(), String.t(), map()}
          | {:push, String.t() | nil, String.t(), String.t(), term()}
          | :other

  @doc "A message to the server as a text frame."
  @spec encode(String.t() | nil, String.t() | nil, String.t(), String.t(), map()) :: String.t()
  def encode(join_ref, ref, topic, event, payload),
    do: Jason.encode!([join_ref, ref, topic, event, payload])

  @doc "A text frame from the server: a reply to one of ours, or a push."
  @spec decode(String.t()) :: message()
  def decode(text) do
    case Jason.decode(text) do
      {:ok, [join_ref, ref, topic, "phx_reply", %{"status" => status, "response" => response}]} ->
        {:reply, join_ref, ref, topic, status, response}

      {:ok, [join_ref, _ref, topic, event, payload]} ->
        {:push, join_ref, topic, event, payload}

      _ ->
        :other
    end
  end

  @doc "A binary frame from the server: a push or a broadcast with raw bytes."
  @spec decode_binary(binary()) :: message()
  def decode_binary(
        <<0, join_size, topic_size, event_size, join_ref::binary-size(join_size),
          topic::binary-size(topic_size), event::binary-size(event_size), data::binary>>
      ),
      do: {:push, join_ref, topic, event, data}

  def decode_binary(
        <<2, topic_size, event_size, topic::binary-size(topic_size),
          event::binary-size(event_size), data::binary>>
      ),
      do: {:push, nil, topic, event, data}

  def decode_binary(_other), do: :other

  @doc "A `\"frame\"` payload as the painter takes it."
  @spec frame(map()) :: %{
          focus: {float(), float()},
          movers: [{non_neg_integer(), float(), float()}],
          labels: [{String.t(), float(), float(), String.t() | nil, pos_integer()}],
          hud: [[{String.t(), String.t() | nil}]],
          over: map() | nil
        }
  def frame(payload) do
    [fx, fy] = fetch(payload, :focus)

    %{
      focus: {fx / 1, fy / 1},
      movers: for([index, x, y] <- fetch(payload, :movers), do: {index, x / 1, y / 1}),
      labels:
        for(
          [text, x, y, colour, scale] <- fetch(payload, :labels) || [],
          do: {text, x / 1, y / 1, colour, scale}
        ),
      hud: for(row <- fetch(payload, :hud), do: for([text, colour] <- row, do: {text, colour})),
      over: fetch(payload, :over)
    }
  end

  @doc "A `\"map\"` payload as the painter takes it."
  @spec map(map()) :: %{
          width: pos_integer(),
          height: pos_integer(),
          tile: pos_integer(),
          wrap: boolean(),
          rows: [[non_neg_integer()]]
        }
  def map(payload),
    do: %{
      width: fetch(payload, :width),
      height: fetch(payload, :height),
      tile: fetch(payload, :tile),
      wrap: fetch(payload, :wrap),
      rows: fetch(payload, :rows)
    }

  @doc "A `\"sheet\"` payload: the tile size, the columns, where each index sits, the animations by first index, the void colour and the PNG's url."
  @spec sheet(map()) :: %{
          tile: pos_integer(),
          columns: pos_integer(),
          frames: [{non_neg_integer(), non_neg_integer()}],
          anim: %{pos_integer() => %{indices: [pos_integer()], fps: pos_integer()}},
          url: String.t(),
          void: {byte(), byte(), byte()}
        }
  def sheet(payload) do
    %{
      tile: fetch(payload, :tile),
      columns: fetch(payload, :columns),
      frames: for([x, y] <- fetch(payload, :frames), do: {x, y}),
      anim: anim(fetch(payload, :anim) || %{}),
      url: fetch(payload, :url),
      void: rgb(fetch(payload, :void))
    }
  end

  defp anim(payload) do
    Map.new(payload, fn {first, spec} ->
      {to_integer(first), %{indices: fetch(spec, :indices), fps: fetch(spec, :fps)}}
    end)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)

  defp rgb("#" <> hex),
    do: hex |> Base.decode16!(case: :mixed) |> then(fn <<r, g, b>> -> {r, g, b} end)

  defp rgb(_none), do: {0, 0, 0}

  defp fetch(payload, key),
    do: Map.get_lazy(payload, key, fn -> Map.get(payload, Atom.to_string(key)) end)
end
