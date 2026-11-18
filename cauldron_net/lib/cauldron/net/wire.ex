defmodule Cauldron.Net.Wire do
  @moduledoc """
  The Phoenix channel protocol (serializer 2.0.0) as an Elixir client speaks it, and
  a session's own pushes read into plain shapes: a frame's status (hud rows of
  `{text, colour}` runs, the outcome, the subject, the focus) and where the client goes.
  What a desktop view, a terminal or any other program joining a served world over its
  WebSocket reads; a drawer's pushes are its own to read (`c:Cauldron.Net.Drawer.read/4`).

      Cauldron.Net.Wire.encode(join_ref, ref, topic, "phx_join", params)
      Cauldron.Net.Wire.decode(text)
      Cauldron.Net.Wire.decode_binary(bytes)
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

  @doc "A `\"status\"` payload: the hud rows of `{text, colour}` runs, the outcome, the subject and the focus."
  @spec status(map()) :: %{
          hud: [[{String.t(), String.t() | nil}]],
          over: map() | nil,
          subject: term(),
          focus: {float(), float()} | nil
        }
  def status(payload) do
    %{
      hud: for(row <- field(payload, :hud), do: for([text, colour] <- row, do: {text, colour})),
      over: field(payload, :over),
      subject: field(payload, :subject),
      focus:
        case field(payload, :focus) do
          [fx, fy] -> {fx / 1, fy / 1}
          nil -> nil
        end
    }
  end

  @doc "A `\"go\"` payload: where the client goes, `:lobby`, `:settings` or `:title`."
  @spec go(map()) :: :lobby | :settings | :title
  def go(payload) do
    case field(payload, :to) do
      to when to in [:lobby, "lobby"] -> :lobby
      to when to in [:settings, "settings"] -> :settings
      _title -> :title
    end
  end

  @doc "A payload's field by its atom key, or by the key's text for a payload decoded from JSON."
  @spec field(map(), atom()) :: term()
  def field(payload, key),
    do: Map.get_lazy(payload, key, fn -> Map.get(payload, Atom.to_string(key)) end)
end
