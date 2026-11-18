defmodule Cauldron.SFX.Kino.Editor do
  @moduledoc """
  The sound-effect editor as a Livebook cell.

      Cauldron.SFX.Kino.Editor.new()
      Cauldron.SFX.Kino.Editor.new("priv/sfx/sfx.json")
      Cauldron.SFX.Kino.Editor.new(bank, out: "priv/sfx/sfx.json")

  It is `Cauldron.SFX.Editor`'s state, drawn in the cell: the events, the selected variant,
  a form to name a new one, and the buttons that play and shape it. A play is rendered to a
  WAV in the notebook's process and played by the cell, so what you hear is the game's own
  voice.

  `new/2` takes a `Cauldron.SFX` bank, the path of one, or nothing for
  `Cauldron.SFX.starter/0`. `:out` is where the editor writes, default `"sfx.json"`.

  ## Keys

  The buttons say what they do; the same commands are in `Cauldron.SFX.Editor`.
  """

  use Kino.JS
  use Kino.JS.Live

  alias Cauldron.SFX
  alias Cauldron.SFX.{Audio, Editor}
  alias Kino.JS.Live

  @keys %{
    "up" => :up,
    "down" => :down,
    "left" => :left,
    "right" => :right,
    "p" => :p,
    "s" => :s,
    "+" => :+,
    "-" => :-,
    ">" => :>,
    "<" => :<,
    "]" => :"]",
    "[" => :"[",
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
    "a" => :a,
    "d" => :d,
    "x" => :x,
    "w" => :w
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
    {"variant +", "a"},
    {"variant -", "d"},
    {"delete event", "x"},
    {"write", "w"}
  ]

  @doc """
  An editor in the cell: on `bank`, on the bank file at `path`, or on the starter bank.

  ## Options

    * `:out` — where the editor's `write` writes, default `"sfx.json"`, or the path given
  """
  @spec new(SFX.t() | Path.t() | nil, keyword()) :: Kino.JS.Live.t()
  def new(source \\ nil, opts \\ [])

  def new(nil, opts), do: start(SFX.starter(), opts)
  def new(%SFX{} = bank, opts), do: start(bank, opts)

  def new(path, opts) when is_binary(path) do
    start(SFX.read!(path), Keyword.put_new(opts, :out, path))
  end

  defp start(bank, opts) do
    Live.new(__MODULE__, {bank, Keyword.get(opts, :out, "sfx.json")})
  end

  @impl true
  def init({bank, out}, ctx) do
    {:ok, assign(ctx, editor: Editor.mount(%{bank: bank, out: out}))}
  end

  @impl true
  def handle_connect(ctx), do: {:ok, payload(ctx), ctx}

  @impl true
  def handle_event("key", %{"key" => key}, ctx) do
    case Map.fetch(@keys, key) do
      {:ok, key} -> {:noreply, changed(ctx, Editor.key(ctx.assigns.editor, key))}
      :error -> {:noreply, ctx}
    end
  end

  def handle_event("select", %{"index" => index}, ctx) do
    {:noreply, changed(ctx, Editor.command(ctx.assigns.editor, {:selected, to_integer(index)}))}
  end

  def handle_event("new_event", %{"name" => name}, ctx) do
    {:noreply, changed(ctx, Editor.command(ctx.assigns.editor, {:new_event, name}))}
  end

  def handle_event(_other, _payload, ctx), do: {:noreply, ctx}

  @doc false
  def payload(ctx) do
    editor = ctx.assigns.editor
    view = Editor.view(editor)

    %{
      title: view.title,
      summary: view.summary,
      detail: view.detail,
      said: view.said,
      out: editor.out,
      rows:
        view.rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          %{label: row.label, selected: row.selected, index: index}
        end),
      buttons: Enum.map(@buttons, fn {label, key} -> %{label: label, key: key} end)
    }
  end

  defp changed(ctx, {editor, effects}) do
    Enum.reduce(effects, assign(ctx, editor: editor), &run/2) |> broadcast()
  end

  defp run({:play, sound}, ctx) do
    broadcast_event(ctx, "play", %{wav: Base.encode64(Audio.wav(sound))})
    ctx
  end

  defp run(:quit, ctx), do: ctx

  defp broadcast(ctx) do
    broadcast_event(ctx, "state", payload(ctx))
    ctx
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)

  asset "main.css" do
    """
    .sfx{font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;color:#d7d9e3}
    .sfx h1{margin:0 0 .2rem;font-size:1rem;letter-spacing:.08em;color:#ffd166}
    .sfx .summary,.sfx .detail,.sfx .said{margin:.2rem 0;color:#8a8fa6}
    .sfx ul{list-style:none;margin:.6rem 0;padding:0}
    .sfx li button{display:block;width:100%;padding:.15rem .5rem;border:0;border-radius:3px;background:none;color:inherit;font:inherit;text-align:left;cursor:pointer}
    .sfx li.on button{background:#232634;color:#ffd166}
    .sfx li button:hover{background:#1c1f2b}
    .sfx .new{display:flex;gap:.4rem;margin:.6rem 0}
    .sfx .new input{flex:0 1 16rem;padding:.25rem .5rem;border:1px solid #2d3142;border-radius:4px;background:#1a1d28;color:inherit;font:inherit}
    .sfx .new input:focus{outline:none;border-color:#ffd166}
    .sfx button{border:1px solid #2d3142;border-radius:4px;background:#1a1d28;color:inherit;font:inherit;cursor:pointer}
    .sfx .new button{padding:.25rem .6rem}
    .sfx .buttons{display:flex;flex-wrap:wrap;gap:.3rem;margin-top:.4rem}
    .sfx .buttons button{padding:.2rem .55rem}
    .sfx button:hover{border-color:#ffd166;color:#ffd166}
    .sfx .player{width:100%;margin-top:.5rem;height:2rem}
    """
  end

  asset "main.js" do
    """
    export function init(ctx, payload) {
      ctx.importCSS("main.css")

      const root = ctx.root
      root.innerHTML = `
        <div class="sfx">
          <h1 class="title"></h1>
          <p class="summary"></p>
          <ul class="events"></ul>
          <form class="new">
            <input name="name" placeholder="new event name" autocomplete="off" />
            <button type="submit">add event</button>
          </form>
          <p class="detail"></p>
          <p class="said"></p>
          <div class="buttons"></div>
          <div class="sound"></div>
        </div>`

      const find = (selector) => root.querySelector(selector)

      function render(state) {
        find(".title").textContent = state.title
        find(".summary").textContent = state.summary
        find(".detail").textContent = state.detail
        find(".said").textContent = "written to " + state.out + " — " + state.said

        const list = find(".events")
        list.innerHTML = ""
        for (const row of state.rows) {
          const item = document.createElement("li")
          if (row.selected) item.className = "on"
          const button = document.createElement("button")
          button.textContent = (row.selected ? "▸ " : "  ") + row.label
          button.addEventListener("click", () => ctx.pushEvent("select", {index: row.index}))
          item.appendChild(button)
          list.appendChild(item)
        }

        const buttons = find(".buttons")
        buttons.innerHTML = ""
        for (const {label, key} of state.buttons) {
          const button = document.createElement("button")
          button.textContent = label
          button.addEventListener("click", () => ctx.pushEvent("key", {key}))
          buttons.appendChild(button)
        }
      }

      find(".new").addEventListener("submit", (event) => {
        event.preventDefault()
        const input = event.target.querySelector("input")
        const name = input.value.trim()
        if (name) ctx.pushEvent("new_event", {name})
        input.value = ""
      })

      ctx.handleEvent("state", render)
      let player = null

      // A visible player, not an invisible Audio object: a browser may refuse to start
      // sound that no click asked for, and then the controls are right there.
      ctx.handleEvent("play", ({wav}) => {
        if (!player) {
          player = document.createElement("audio")
          player.controls = true
          player.className = "player"
          find(".sound").appendChild(player)
        }
        player.src = "data:audio/wav;base64," + wav
        player.play().catch(() => {})
      })

      render(payload)
    }
    """
  end
end
