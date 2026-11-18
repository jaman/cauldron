defmodule Cauldron.SFX.Web.EditorLive do
  @moduledoc """
  The sound-effect editor in a browser: `Cauldron.SFX.Editor`'s state, drawn as a list and a
  row of buttons, with the keyboard doing the same as the buttons.

  A `{:play, sound}` is rendered to a WAV and pushed to the page, which plays it.
  """

  use Phoenix.LiveView

  alias Cauldron.SFX
  alias Cauldron.SFX.{Audio, Editor}

  @keys %{
    "up" => :up,
    "down" => :down,
    "left" => :left,
    "right" => :right,
    "ArrowUp" => :up,
    "ArrowDown" => :down,
    "ArrowLeft" => :left,
    "ArrowRight" => :right,
    "p" => :p,
    "s" => :s,
    "+" => :+,
    "-" => :-,
    ">" => :>,
    "<" => :<,
    "]" => :"]",
    "[" => :"[",
    "a" => :a,
    "d" => :d,
    "x" => :x,
    "1" => :"1",
    "2" => :"2",
    "3" => :"3",
    "4" => :"4",
    "5" => :"5",
    "6" => :"6",
    "7" => :"7",
    "8" => :"8",
    "9" => :"9",
    "0" => :"0",
    "k" => :k,
    "l" => :l,
    "t" => :t,
    "w" => :w,
    "q" => :q
  }

  @buttons [
    {"↑", "up"},
    {"↓", "down"},
    {"←", "left"},
    {"→", "right"},
    {"play", "p"},
    {"shape", "s"},
    {"+", "+"},
    {"-", "-"},
    {"pan >", ">"},
    {"pan <", "<"},
    {"pitch ]", "]"},
    {"pitch [", "["},
    {"variant +", "a"},
    {"variant -", "d"},
    {"decay -", "1"},
    {"decay +", "2"},
    {"sweep -", "3"},
    {"sweep +", "4"},
    {"cutoff -", "5"},
    {"cutoff +", "6"},
    {"attack -", "7"},
    {"attack +", "8"},
    {"release -", "9"},
    {"release +", "0"},
    {"space -", "k"},
    {"space +", "l"},
    {"preset", "t"},
    {"delete event", "x"},
    {"write", "w"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, editor: Editor.mount(%{bank: bank(), out: out()}))}
  end

  @impl true
  def handle_event("key", %{"key" => key}, socket) do
    case Map.fetch(@keys, key) do
      {:ok, key} -> {:noreply, press(socket, key)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("select", %{"index" => index}, socket) do
    {:noreply, apply_command(socket, {:selected, String.to_integer(index)})}
  end

  def handle_event("new_event", %{"name" => name}, socket) do
    {:noreply, apply_command(socket, {:new_event, name})}
  end

  @impl true
  def render(assigns) do
    view = Editor.view(assigns.editor)
    assigns = assign(assigns, :view, view)

    ~H"""
    <div class="sfx">
      <h1><%= @view.title %></h1>
      <p class="summary"><%= @view.summary %></p>

      <ul class="events">
        <li :for={{row, index} <- Enum.with_index(@view.rows)} class={["row", row.selected && "on"]}>
          <button phx-click="select" phx-value-index={index}>
            <span class="marker"><%= if row.selected, do: "▸", else: " " %></span>
            <span class="label"><%= row.label %></span>
          </button>
        </li>
      </ul>

      <form class="new" phx-submit="new_event">
        <input name="name" placeholder="new event name" autocomplete="off" />
        <button type="submit">add event</button>
      </form>

      <p class="detail"><%= @view.detail %></p>
      <p class="said"><%= @view.said %></p>

      <div class="buttons">
        <button :for={{label, key} <- buttons()} phx-click="key" phx-value-key={key}><%= label %></button>
      </div>

      <audio id="sfx-player" class="player" controls></audio>

      <p class="keys"><%= Enum.map_join(@view.keys, " · ", fn {key, what} -> "#{key} #{what}" end) %></p>
    </div>
    """
  end

  defp buttons, do: @buttons

  defp press(socket, key) do
    {editor, effects} = Editor.key(socket.assigns.editor, key)
    run(assign(socket, :editor, editor), effects)
  end

  defp apply_command(socket, command) do
    {editor, effects} = Editor.command(socket.assigns.editor, command)
    run(assign(socket, :editor, editor), effects)
  end

  defp run(socket, effects) do
    Enum.reduce(effects, socket, fn
      {:play, sound}, socket -> push_event(socket, "sfx", %{wav: Base.encode64(Audio.wav(sound))})
      :quit, socket -> socket
    end)
  end

  defp bank do
    case Application.get_env(:cauldron_sfx_web, :bank) do
      nil -> SFX.starter()
      path -> SFX.read!(path)
    end
  end

  defp out, do: Application.get_env(:cauldron_sfx_web, :out, "sfx.json")
end
