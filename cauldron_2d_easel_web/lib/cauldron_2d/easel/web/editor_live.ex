defmodule Cauldron2D.Easel.Web.EditorLive do
  @moduledoc """
  The atlas editor in a browser: the arts of a directory, and one of them on a canvas
  with the palette, the tools and the frames beside it. The document is a
  `Cauldron2D.Easel` held here; the browser draws it and sends back where the pointer
  paints.

  Mounted by `Cauldron2D.Easel.Web.Router.easel/2`; the session carries `"dir"`,
  `"tile"` and, when saves should install the directory as an atlas, `"atlas"`.

  ## Keys

  The pointer paints with the tool in hand. `b` brush, `l` line, `r` rectangle, `R`
  filled rectangle, `f` fill, `e` eraser; `1`–`9` pick a colour; `h`/`v` flip, `t`/`T`
  turn, arrows shift; `,`/`.` frame before or after, `a` adds one, `d` duplicates, `x`
  drops; `o` onion skin, `p` plays; `u` undoes, `U` redoes; `s` saves, `w` saves and
  installs. Every one of them is also a button.
  """

  use Phoenix.LiveView

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.{Project, View}

  @tools [brush: "b", line: "l", rect: "r", filled_rect: "R", fill: "f", eraser: "e"]

  @impl true
  def mount(_params, session, socket) do
    project = Project.open(session["dir"], tile: session["tile"])

    {:ok,
     assign(socket,
       project: project,
       base: session["base"],
       atlas: session["atlas"],
       arts: Project.arts(project),
       name: nil,
       easel: nil,
       tool: :brush,
       key: nil,
       anchor: nil,
       preview: nil,
       onion: false,
       playing: false,
       shown: 0,
       zoom: 16,
       status: ""
     )}
  end

  @impl true
  def handle_params(%{"art" => art}, _uri, socket),
    do: {:noreply, open(socket, String.to_atom(art))}

  def handle_params(_params, _uri, socket),
    do:
      {:noreply,
       assign(socket, name: nil, easel: nil, arts: Project.arts(socket.assigns.project))}

  defp open(socket, name) do
    case Project.load(socket.assigns.project, name) do
      {:ok, easel} ->
        socket
        |> assign(
          name: name,
          easel: easel,
          key: List.first(Easel.keys(easel)),
          anchor: nil,
          preview: nil,
          playing: false,
          shown: 0,
          status: ""
        )
        |> push_frame()

      {:error, reason} ->
        assign(socket, status: "could not open #{name}: #{inspect(reason)}")
    end
  end

  defp push_frame(%{assigns: %{easel: nil}} = socket), do: socket

  defp push_frame(socket) do
    push_event(socket, "frame", frame_payload(socket.assigns))
  end

  @doc "What the canvas hook draws: `Cauldron2D.Easel.View.payload/2` for the frame shown, the ghost under it when onion skin is on and playback off."
  @spec frame_payload(map()) :: map()
  def frame_payload(%{easel: easel, playing: true} = assigns),
    do: View.payload(easel, zoom: assigns.zoom, shown: assigns.shown)

  def frame_payload(%{easel: easel} = assigns),
    do: View.payload(easel, zoom: assigns.zoom, onion: assigns.onion)

  @impl true
  def handle_event(
        "paint",
        %{"x" => x, "y" => y, "phase" => phase},
        %{assigns: %{easel: easel, playing: false}} = socket
      )
      when easel != nil do
    {:noreply, socket |> painted({x, y}, String.to_existing_atom(phase)) |> push_frame()}
  end

  def handle_event("paint", _pixel, socket), do: {:noreply, socket}

  def handle_event("tool", %{"tool" => tool}, socket) do
    {:noreply, assign(socket, tool: String.to_existing_atom(tool), anchor: nil, preview: nil)}
  end

  def handle_event("pick", %{"key" => key}, socket), do: {:noreply, assign(socket, key: key)}

  def handle_event("frame", %{"index" => index}, socket),
    do: {:noreply, change(socket, &Easel.select_frame(&1, String.to_integer(index)))}

  def handle_event("add_colour", %{"key" => key, "colour" => colour}, socket),
    do: {:noreply, add_colour(socket, key, colour)}

  def handle_event("set_colour", %{"colour" => colour}, %{assigns: %{key: key}} = socket)
      when key != nil, do: {:noreply, set_colour(socket, colour)}

  def handle_event("remove_colour", _params, %{assigns: %{key: key}} = socket) when key != nil,
    do: {:noreply, change(socket, &Easel.remove_colour(&1, key))}

  def handle_event("glyph", %{"glyph" => glyph} = params, socket),
    do: {:noreply, glyph(socket, glyph, params["colour"])}

  def handle_event("fps", %{"fps" => fps}, socket),
    do: {:noreply, change(socket, &Easel.set_fps(&1, max(String.to_integer(fps), 1)))}

  def handle_event("zoom", %{"zoom" => zoom}, socket),
    do: {:noreply, socket |> assign(zoom: String.to_integer(zoom)) |> push_frame()}

  def handle_event("new_art", %{"name" => name}, socket) when name != "",
    do: {:noreply, new_art(socket, String.to_atom(name))}

  def handle_event("new_art", _params, socket), do: {:noreply, socket}

  def handle_event("derive", %{"name" => name, "line" => line}, socket) when name != "",
    do: {:noreply, derive(socket, String.to_atom(String.trim(name)), String.trim(line))}

  def handle_event("derive", _params, socket), do: {:noreply, socket}

  def handle_event("clone", %{"from" => from, "name" => name}, socket) when name != "",
    do: {:noreply, clone(socket, String.to_atom(from), String.to_atom(String.trim(name)))}

  def handle_event("clone", _params, socket), do: {:noreply, socket}
  def handle_event("key", %{"key" => key}, socket), do: {:noreply, key(key, socket)}
  def handle_event(action, _params, socket), do: {:noreply, key(action, socket)}

  @impl true
  def handle_info(:play, %{assigns: %{playing: true, easel: easel}} = socket) do
    Process.send_after(self(), :play, div(1000, easel.fps))

    {:noreply,
     socket |> assign(shown: rem(socket.assigns.shown + 1, length(easel.frames))) |> push_frame()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp key(_key, %{assigns: %{easel: nil}} = socket), do: socket

  defp key("u", socket), do: change(socket, &Easel.undo/1)
  defp key("U", socket), do: change(socket, &Easel.redo/1)
  defp key("h", socket), do: change(socket, &Easel.flip(&1, :horizontal))
  defp key("v", socket), do: change(socket, &Easel.flip(&1, :vertical))
  defp key("t", socket), do: change(socket, &Easel.rotate(&1, 90))
  defp key("T", socket), do: change(socket, &Easel.rotate(&1, -90))
  defp key("ArrowLeft", socket), do: change(socket, &Easel.shift(&1, -1, 0))
  defp key("ArrowRight", socket), do: change(socket, &Easel.shift(&1, 1, 0))
  defp key("ArrowUp", socket), do: change(socket, &Easel.shift(&1, 0, -1))
  defp key("ArrowDown", socket), do: change(socket, &Easel.shift(&1, 0, 1))
  defp key(",", socket), do: change(socket, &Easel.select_frame(&1, &1.frame - 1))
  defp key(".", socket), do: change(socket, &Easel.select_frame(&1, &1.frame + 1))
  defp key("a", socket), do: change(socket, &Easel.add_frame/1)
  defp key("d", socket), do: change(socket, &Easel.duplicate_frame/1)
  defp key("x", socket), do: change(socket, &Easel.delete_frame/1)
  defp key("<", socket), do: change(socket, &Easel.move_frame(&1, &1.frame, &1.frame - 1))
  defp key(">", socket), do: change(socket, &Easel.move_frame(&1, &1.frame, &1.frame + 1))
  defp key("o", socket), do: socket |> assign(onion: not socket.assigns.onion) |> push_frame()
  defp key("p", socket), do: toggle_play(socket)
  defp key("s", socket), do: save(socket)
  defp key("w", socket), do: socket |> save() |> install()
  defp key(other, socket), do: tool_or_pick(other, socket)

  defp tool_or_pick(key, socket) do
    cond do
      tool = Enum.find_value(@tools, fn {tool, shortcut} -> if shortcut == key, do: tool end) ->
        assign(socket, tool: tool, anchor: nil, preview: nil)

      key in ~w(1 2 3 4 5 6 7 8 9) ->
        pick(socket, String.to_integer(key) - 1)

      true ->
        socket
    end
  end

  defp pick(socket, index) do
    case Enum.at(Easel.keys(socket.assigns.easel), index) do
      nil -> socket
      key -> assign(socket, key: key)
    end
  end

  defp change(socket, fun) do
    easel = fun.(socket.assigns.easel)
    keys = Easel.keys(easel)

    socket
    |> assign(
      easel: easel,
      key: if(socket.assigns.key in keys, do: socket.assigns.key, else: List.first(keys)),
      shown: min(socket.assigns.shown, length(easel.frames) - 1)
    )
    |> push_frame()
  end

  defp painted(socket, point, :start),
    do: stroke(assign(socket, anchor: point, preview: socket.assigns.easel), point)

  defp painted(socket, point, :drag), do: stroke(socket, point)

  defp painted(socket, point, :end),
    do: socket |> stroke(point) |> assign(anchor: nil, preview: nil)

  defp stroke(%{assigns: %{key: nil, tool: tool}} = socket, _point) when tool != :eraser,
    do: socket

  defp stroke(%{assigns: %{tool: :brush} = a} = socket, point),
    do: assign(socket, easel: Easel.paint(a.easel, point, a.key))

  defp stroke(%{assigns: %{tool: :eraser} = a} = socket, point),
    do: assign(socket, easel: Easel.erase(a.easel, point))

  defp stroke(%{assigns: %{tool: :fill, anchor: anchor} = a} = socket, point)
       when anchor == point, do: assign(socket, easel: Easel.fill(a.easel, point, a.key))

  defp stroke(%{assigns: %{tool: :fill}} = socket, _point), do: socket
  defp stroke(%{assigns: %{anchor: nil}} = socket, _point), do: socket

  defp stroke(%{assigns: %{tool: :line} = a} = socket, point),
    do: assign(socket, easel: Easel.line(a.preview, a.anchor, point, a.key))

  defp stroke(%{assigns: %{tool: :rect} = a} = socket, point),
    do: assign(socket, easel: Easel.rect(a.preview, a.anchor, point, a.key))

  defp stroke(%{assigns: %{tool: :filled_rect} = a} = socket, point),
    do: assign(socket, easel: Easel.rect(a.preview, a.anchor, point, a.key, fill: true))

  defp toggle_play(%{assigns: %{playing: true}} = socket),
    do: socket |> assign(playing: false, shown: 0) |> push_frame()

  defp toggle_play(socket) do
    Process.send_after(self(), :play, div(1000, socket.assigns.easel.fps))
    socket |> assign(playing: true, shown: socket.assigns.easel.frame) |> push_frame()
  end

  defp add_colour(socket, key, colour) do
    changed = change(socket, &Easel.add_colour(&1, key, colour))

    if key in Easel.keys(changed.assigns.easel),
      do: assign(changed, key: key),
      else: assign(changed, status: "could not add #{inspect(key)}")
  rescue
    ArgumentError -> assign(socket, status: "not a colour: #{colour}")
  end

  defp set_colour(socket, colour) do
    change(socket, &Easel.set_colour(&1, socket.assigns.key, colour))
  rescue
    ArgumentError -> assign(socket, status: "not a colour: #{colour}")
  end

  defp glyph(socket, glyph, colour) do
    fields =
      [glyph: glyph |> String.pad_trailing(2) |> String.slice(0, 2)] ++
        if(colour in [nil, ""],
          do: [],
          else: [
            color: colour |> Linocut.Palette.color() |> then(fn {r, g, b, _} -> {r, g, b} end)
          ]
        )

    case Project.put_entry(socket.assigns.project, socket.assigns.name, fields) do
      {:ok, project} ->
        assign(socket, project: project, status: "glyph set")

      {:error, reason} ->
        assign(socket, status: "could not write the manifest: #{inspect(reason)}")
    end
  rescue
    ArgumentError -> assign(socket, status: "not a colour: #{colour}")
  end

  defp new_art(socket, name) do
    socket
    |> assign(
      name: name,
      easel: Project.new_art(socket.assigns.project),
      key: nil,
      anchor: nil,
      preview: nil,
      playing: false,
      shown: 0,
      status: "new art #{name}, unsaved"
    )
    |> push_frame()
  end

  defp derive(socket, name, line) do
    case Project.derive(socket.assigns.project, name, line) do
      {:ok, project} ->
        assign(socket, project: project, arts: Project.arts(project), status: "#{name}: #{line}")

      {:error, message} when is_binary(message) ->
        assign(socket, status: "not derived: #{message}")

      {:error, reason} ->
        assign(socket, status: "not derived: #{inspect(reason)}")
    end
  end

  defp clone(socket, from, name) do
    case Project.clone(socket.assigns.project, from, name) do
      {:ok, project} ->
        assign(socket,
          project: project,
          arts: Project.arts(project),
          status: "cloned #{from} as #{name}.pic"
        )

      {:error, reason} ->
        assign(socket, status: "could not clone: #{inspect(reason)}")
    end
  end

  defp save(%{assigns: %{name: name}} = socket) do
    if Map.has_key?(Project.entry(socket.assigns.project, name), :derive),
      do:
        assign(socket,
          status: "#{name} is derived: change its line on the arts page, or clone it"
        ),
      else: write(socket)
  end

  defp write(socket) do
    case Project.save(socket.assigns.project, socket.assigns.name, socket.assigns.easel) do
      {:ok, project} ->
        assign(socket,
          project: project,
          arts: Project.arts(project),
          status: "saved #{socket.assigns.name}.pic"
        )

      {:error, reason} ->
        assign(socket, status: "could not save: #{inspect(reason)}")
    end
  end

  defp install(%{assigns: %{atlas: nil}} = socket),
    do: assign(socket, status: socket.assigns.status <> " (no atlas to install into)")

  defp install(socket) do
    case Project.install(socket.assigns.project, socket.assigns.atlas) do
      {:ok, name} ->
        assign(socket, status: socket.assigns.status <> "  installed as #{inspect(name)}")

      {:error, reason} ->
        assign(socket, status: "could not install: #{inspect(reason)}")
    end
  end

  defp source(%{derived: line}), do: line
  defp source(%{file: file}), do: file

  @doc "The tools with their keys, in order."
  @spec tools() :: keyword()
  def tools, do: @tools

  @impl true
  def render(%{easel: nil} = assigns) do
    ~H"""
    <main class="easel">
      <h1>Easel · {@project.dir} · {@project.tile}px tiles</h1>
      <ul class="arts">
        <li :for={art <- @arts}>
          <.link patch={"#{@base}/#{art.name}"}>{art.name}</.link>
          <span class="dim">{art.frames} {if art.frames == 1, do: "frame", else: "frames"} · {source(
            art
          )}</span>
          <form id={"clone-#{art.name}"} phx-submit="clone" class="inline">
            <input type="hidden" name="from" value={art.name} />
            <input name="name" placeholder="clone as" autocomplete="off" size="10" />
            <button>clone</button>
          </form>
        </li>
      </ul>
      <form phx-submit="new_art" class="row">
        <input name="name" placeholder="new art" autocomplete="off" />
        <button>new</button>
      </form>
      <form phx-submit="derive" class="row">
        <input name="name" placeholder="derived art" autocomplete="off" />
        <input
          name="line"
          placeholder="from ART; colour K #rrggbb; flip h; over HAT 0 -2"
          autocomplete="off"
          size="48"
        />
        <button>derive</button>
      </form>
      <p class="status">{@status}</p>
    </main>
    """
  end

  def render(assigns) do
    ~H"""
    <main class="easel editing">
      <header>
        <.link patch={@base}>← arts</.link>
        <strong>{@name}</strong>
        <span class="dim">{@easel.width}×{@easel.height} · frame {@easel.frame + 1}/{length(
          @easel.frames
        )} · {@easel.fps} fps{if @playing, do: " · playing"}</span>
        <span class="status">{@status}</span>
      </header>
      <div class="row">
        <div
          id="canvas"
          phx-hook="EaselCanvas"
          phx-update="ignore"
          data-frame={Jason.encode!(frame_payload(assigns))}
        >
          <canvas></canvas>
        </div>
        <aside>
          <section>
            <h2>tool</h2>
            <button
              :for={{tool, shortcut} <- tools()}
              phx-click="tool"
              phx-value-tool={tool}
              class={if @tool == tool, do: "on"}
            >{tool} <kbd>{shortcut}</kbd></button>
          </section>
          <section>
            <h2>colours</h2>
            <button
              :for={{{key, {r, g, b, _a}}, index} <- Enum.with_index(@easel.palette)}
              phx-click="pick"
              phx-value-key={key}
              class={if @key == key, do: "on"}
            >
              <i class="swatch" style={"background:rgb(#{r},#{g},#{b})"}></i> {key}
              <kbd>{index + 1}</kbd>
            </button>
            <form phx-submit="add_colour" class="row">
              <input name="key" size="1" maxlength="1" placeholder="k" autocomplete="off" />
              <input name="colour" type="color" value="#ffffff" />
              <button>add</button>
            </form>
            <form :if={@key} phx-submit="set_colour" class="row">
              <input name="colour" type="color" value={css_hex(Easel.colour(@easel, @key))} />
              <button>set {@key}</button>
              <button type="button" phx-click="remove_colour">remove {@key}</button>
            </form>
          </section>
          <section>
            <h2>frames</h2>
            <button
              :for={index <- 0..(length(@easel.frames) - 1)}
              phx-click="frame"
              phx-value-index={index}
              class={if @easel.frame == index, do: "on"}
            >{index + 1}</button>
            <div class="row">
              <button phx-click="a" title="add">a</button><button phx-click="d" title="duplicate">d</button><button
                phx-click="x"
                title="drop"
              >x</button>
              <button phx-click="<">‹</button><button phx-click=">">›</button>
              <button phx-click="o" class={if @onion, do: "on"}>onion</button>
              <button phx-click="p" class={if @playing, do: "on"}>play</button>
            </div>
            <form id="fps" phx-change="fps" class="row">
              <label>fps <input name="fps" type="number" min="1" max="60" value={@easel.fps} /></label>
            </form>
          </section>
          <section>
            <h2>frame</h2>
            <button phx-click="u">undo</button><button phx-click="U">redo</button>
            <button phx-click="h">flip ↔</button><button phx-click="v">flip ↕</button>
            <button phx-click="t">turn ↺</button><button phx-click="T">turn ↻</button>
            <form id="zoom" phx-change="zoom" class="row">
              <label>zoom <input name="zoom" type="range" min="4" max="40" step="2" value={@zoom} /></label>
            </form>
          </section>
          <section>
            <h2>text renderer</h2>
            <form phx-submit="glyph" class="row">
              <input
                name="glyph"
                size="2"
                maxlength="2"
                placeholder="··"
                value={Map.get(Project.entry(@project, @name), :glyph, "")}
                autocomplete="off"
              />
              <input
                name="colour"
                type="color"
                value={css_hex(Map.get(Project.entry(@project, @name), :color))}
              />
              <button>glyph</button>
            </form>
          </section>
          <section>
            <button phx-click="s">save <kbd>s</kbd></button>
            <button phx-click="w">save + install <kbd>w</kbd></button>
          </section>
        </aside>
      </div>
    </main>
    """
  end

  defp css_hex({r, g, b, _a}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
  defp css_hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
  defp css_hex(nil), do: "#ffffff"
end
