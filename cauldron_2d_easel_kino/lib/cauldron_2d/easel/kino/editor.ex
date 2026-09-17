defmodule Cauldron2D.Easel.Kino.Editor do
  @moduledoc """
  The atlas editor as a Livebook cell: a canvas to paint on, the palette, the tools and
  the frames, holding a `Cauldron2D.Easel` in the cell's process.

      editor = Cauldron2D.Easel.Kino.Editor.new("priv/art/ship.pic")
      editor = Cauldron2D.Easel.Kino.Editor.new(easel, save: "priv/art/ship.pic", tile: 16)

      Cauldron2D.Easel.Kino.Editor.easel(editor)

  The pointer paints with the tool chosen; a colour is added from the colour input,
  changed by choosing it and using the input again; the frames are added, copied and
  dropped from their row; undo and redo walk the history. **save** writes the `.pic`
  the cell was opened from, or `:save`; with `:atlas` and `:tile` it then installs the
  file's directory as that atlas, as the other editors do. `easel/1` is the document
  as it stands, so a later cell can render or install it.

  ## Options

    * `:save` — the `.pic` path **save** writes. Default: the path given, else none
    * `:atlas` — the atlas name a save installs the directory into. Default: none
    * `:tile` — the tile size, needed with `:atlas`. Default: the picture's width
    * `:zoom` — pixels a picture pixel. Default `16`
  """

  use Kino.JS
  use Kino.JS.Live

  alias Cauldron2D.Easel
  alias Cauldron2D.Easel.{Project, View}
  alias Kino.JS.Live

  @tools ~w(brush line rect filled_rect fill eraser eyedropper)a
  @free_keys String.graphemes("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")

  @doc "The editor on an easel or on a `.pic`/`.png` path; see the module documentation for the options."
  @spec new(Easel.t() | Path.t(), keyword()) :: Live.t()
  def new(source, opts \\ [])

  def new(%Easel{} = easel, opts), do: Live.new(__MODULE__, {easel, opts})

  def new(path, opts) when is_binary(path) do
    case Easel.load(path, Keyword.take(opts, [:frame])) do
      {:ok, easel} -> Live.new(__MODULE__, {easel, Keyword.put_new(opts, :save, path)})
      {:error, reason} -> raise ArgumentError, "cannot open #{path}: #{inspect(reason)}"
    end
  end

  @doc "The document as it stands."
  @spec easel(Live.t()) :: Easel.t()
  def easel(editor), do: Live.call(editor, :easel)

  @impl true
  def init({easel, opts}, ctx) do
    state = %{
      easel: easel,
      tool: :brush,
      key: List.first(Easel.keys(easel)),
      anchor: nil,
      preview: nil,
      onion: false,
      zoom: Keyword.get(opts, :zoom, 16),
      save: Keyword.get(opts, :save),
      atlas: Keyword.get(opts, :atlas),
      tile: Keyword.get(opts, :tile, easel.width),
      status: ""
    }

    {:ok, assign(ctx, state)}
  end

  @impl true
  def handle_connect(ctx), do: {:ok, payload(ctx), ctx}

  @impl true
  def handle_call(:easel, _from, ctx), do: {:reply, ctx.assigns.easel, ctx}

  @impl true
  def handle_event("paint", %{"x" => x, "y" => y, "phase" => phase}, ctx) do
    {:noreply, ctx |> painted({x, y}, String.to_existing_atom(phase)) |> broadcast()}
  end

  def handle_event("tool", %{"tool" => tool}, ctx) do
    tool = String.to_existing_atom(tool)

    if tool in @tools,
      do: {:noreply, ctx |> assign(tool: tool, anchor: nil, preview: nil) |> broadcast()},
      else: {:noreply, ctx}
  end

  def handle_event("pick", %{"key" => key}, ctx),
    do: {:noreply, ctx |> assign(key: key) |> broadcast()}

  def handle_event("frame", %{"index" => index}, ctx),
    do: {:noreply, change(ctx, &Easel.select_frame(&1, index))}

  def handle_event("add_colour", %{"colour" => colour}, ctx),
    do: {:noreply, add_colour(ctx, colour)}

  def handle_event("set_colour", %{"colour" => colour}, %{assigns: %{key: key}} = ctx)
      when key != nil, do: {:noreply, change(ctx, &Easel.set_colour(&1, key, colour))}

  def handle_event("remove_colour", _payload, %{assigns: %{key: key}} = ctx) when key != nil,
    do: {:noreply, change(ctx, &Easel.remove_colour(&1, key))}

  def handle_event("fps", %{"fps" => fps}, ctx) when is_integer(fps) and fps > 0,
    do: {:noreply, change(ctx, &Easel.set_fps(&1, fps))}

  def handle_event("onion", _payload, ctx),
    do: {:noreply, ctx |> assign(onion: not ctx.assigns.onion) |> broadcast()}

  def handle_event("undo", _payload, ctx), do: {:noreply, change(ctx, &Easel.undo/1)}
  def handle_event("redo", _payload, ctx), do: {:noreply, change(ctx, &Easel.redo/1)}
  def handle_event("add_frame", _payload, ctx), do: {:noreply, change(ctx, &Easel.add_frame/1)}

  def handle_event("duplicate_frame", _payload, ctx),
    do: {:noreply, change(ctx, &Easel.duplicate_frame/1)}

  def handle_event("delete_frame", _payload, ctx),
    do: {:noreply, change(ctx, &Easel.delete_frame/1)}

  def handle_event("flip_h", _payload, ctx),
    do: {:noreply, change(ctx, &Easel.flip(&1, :horizontal))}

  def handle_event("flip_v", _payload, ctx),
    do: {:noreply, change(ctx, &Easel.flip(&1, :vertical))}

  def handle_event("rotate", _payload, ctx), do: {:noreply, change(ctx, &Easel.rotate(&1, 90))}
  def handle_event("save", _payload, ctx), do: {:noreply, save(ctx)}
  def handle_event(_event, _payload, ctx), do: {:noreply, ctx}

  defp payload(%{assigns: a}) do
    a.easel
    |> View.payload(zoom: a.zoom, onion: a.onion)
    |> Map.merge(%{
      tool: a.tool,
      key: a.key,
      tools: @tools,
      onion: a.onion,
      status: a.status,
      can_save: a.save != nil
    })
  end

  defp broadcast(ctx) do
    broadcast_event(ctx, "frame", payload(ctx))
    ctx
  end

  defp change(ctx, fun) do
    easel = fun.(ctx.assigns.easel)
    keys = Easel.keys(easel)

    ctx
    |> assign(
      easel: easel,
      key: if(ctx.assigns.key in keys, do: ctx.assigns.key, else: List.first(keys))
    )
    |> broadcast()
  end

  defp painted(%{assigns: %{tool: :eyedropper}} = ctx, point, :start) do
    case Easel.key_at(ctx.assigns.easel, point, ctx.assigns.easel.frame) do
      key when key in [nil, "."] -> ctx
      key -> assign(ctx, key: key, tool: :brush)
    end
  end

  defp painted(%{assigns: %{tool: :eyedropper}} = ctx, _point, _phase), do: ctx

  defp painted(ctx, point, :start),
    do: stroke(assign(ctx, anchor: point, preview: ctx.assigns.easel), point)

  defp painted(ctx, point, :drag), do: stroke(ctx, point)
  defp painted(ctx, point, :end), do: ctx |> stroke(point) |> assign(anchor: nil, preview: nil)

  defp stroke(%{assigns: %{key: nil, tool: tool}} = ctx, _point) when tool != :eraser,
    do: assign(ctx, status: "no colour chosen")

  defp stroke(%{assigns: %{tool: :brush} = a} = ctx, point),
    do: assign(ctx, easel: Easel.paint(a.easel, point, a.key))

  defp stroke(%{assigns: %{tool: :eraser} = a} = ctx, point),
    do: assign(ctx, easel: Easel.erase(a.easel, point))

  defp stroke(%{assigns: %{tool: :fill, anchor: anchor} = a} = ctx, point) when anchor == point,
    do: assign(ctx, easel: Easel.fill(a.easel, point, a.key))

  defp stroke(%{assigns: %{tool: :fill}} = ctx, _point), do: ctx
  defp stroke(%{assigns: %{anchor: nil}} = ctx, _point), do: ctx

  defp stroke(%{assigns: %{tool: :line} = a} = ctx, point),
    do: assign(ctx, easel: Easel.line(a.preview, a.anchor, point, a.key))

  defp stroke(%{assigns: %{tool: :rect} = a} = ctx, point),
    do: assign(ctx, easel: Easel.rect(a.preview, a.anchor, point, a.key))

  defp stroke(%{assigns: %{tool: :filled_rect} = a} = ctx, point),
    do: assign(ctx, easel: Easel.rect(a.preview, a.anchor, point, a.key, fill: true))

  defp stroke(ctx, _point), do: ctx

  defp add_colour(ctx, colour) do
    case Enum.find(@free_keys, &(&1 not in Easel.keys(ctx.assigns.easel))) do
      nil ->
        ctx |> assign(status: "no key left for another colour") |> broadcast()

      key ->
        ctx
        |> assign(key: key, status: "added #{key}")
        |> change(&Easel.add_colour(&1, key, colour))
    end
  end

  defp save(%{assigns: %{save: nil}} = ctx),
    do: ctx |> assign(status: "nowhere to save: give :save") |> broadcast()

  defp save(%{assigns: a} = ctx) do
    case Easel.save(a.easel, a.save) do
      :ok ->
        ctx |> assign(status: "saved #{Path.basename(a.save)}" <> installed(a)) |> broadcast()

      {:error, reason} ->
        ctx |> assign(status: "could not save: #{inspect(reason)}") |> broadcast()
    end
  end

  defp installed(%{atlas: nil}), do: ""

  defp installed(%{atlas: atlas, save: path, tile: tile}) do
    case path |> Path.dirname() |> Project.open(tile: tile) |> Project.install(atlas) do
      {:ok, name} -> ", installed as #{inspect(name)}"
      {:error, reason} -> ", not installed: #{inspect(reason)}"
    end
  end

  asset "main.css" do
    """
    .easel{font:14px system-ui,sans-serif;color:#e8e8f0;background:#181826;padding:.6rem;border-radius:.4rem}
    .easel .row{display:flex;gap:.4rem;align-items:center;flex-wrap:wrap;margin:.3rem 0}
    .easel button{background:#26263a;color:#e8e8f0;border:0;border-radius:.3rem;padding:.25rem .55rem;cursor:pointer}
    .easel button.on{background:#3b5bdb}
    .easel canvas{image-rendering:pixelated;touch-action:none;cursor:crosshair;display:block;margin:.4rem 0}
    .easel .swatch{display:inline-block;width:.9rem;height:.9rem;vertical-align:middle;border:1px solid #000;margin-right:.3rem}
    .easel .status{color:#ffd060}.easel .dim{color:#a0a0b8}
    .easel input[type=number]{width:4rem;background:#101018;color:#e8e8f0;border:1px solid #26263a;border-radius:.3rem}
    """
  end

  asset "main.js" do
    """
    export function init(ctx, data) {
      ctx.importCSS("main.css");
      const checker = ["#282830", "#383842"];
      const names = {brush: "brush", line: "line", rect: "rect", filled_rect: "box", fill: "fill", eraser: "eraser", eyedropper: "pick"};
      const root = ctx.root;
      root.innerHTML = `
        <div class="easel">
          <div class="row tools"></div>
          <canvas></canvas>
          <div class="row palette"></div>
          <div class="row">
            <label>colour <input type="color" class="colour" value="#ffffff"></label>
            <button class="add">add colour</button>
            <button class="set">set chosen</button>
            <button class="remove">remove chosen</button>
          </div>
          <div class="row frames"></div>
          <div class="row">
            <button data-event="add_frame">add frame</button>
            <button data-event="duplicate_frame">duplicate</button>
            <button data-event="delete_frame">drop</button>
            <button class="onion" data-event="onion">onion</button>
            <label>fps <input type="number" class="fps" min="1" max="60"></label>
            <button class="play">play</button>
          </div>
          <div class="row">
            <button class="undo" data-event="undo">undo</button>
            <button class="redo" data-event="redo">redo</button>
            <button data-event="flip_h">flip ↔</button>
            <button data-event="flip_v">flip ↕</button>
            <button data-event="rotate">turn ↺</button>
            <button class="save" data-event="save">save</button>
            <span class="status"></span>
          </div>
        </div>`;

      const canvas = root.querySelector("canvas");
      const context = canvas.getContext("2d");
      let frame = data;
      let down = false;
      let last = null;
      let playing = null;
      let shown = 0;

      const pixel = (event) => {
        const rect = canvas.getBoundingClientRect();
        return {
          x: Math.floor((event.clientX - rect.left) * (canvas.width / rect.width) / frame.zoom),
          y: Math.floor((event.clientY - rect.top) * (canvas.height / rect.height) / frame.zoom)
        };
      };
      const send = (event, phase) => {
        const p = pixel(event);
        if (phase === "drag" && last && last.x === p.x && last.y === p.y) return;
        last = phase === "end" ? null : p;
        ctx.pushEvent("paint", {x: p.x, y: p.y, phase});
      };
      canvas.addEventListener("pointerdown", (e) => { if (playing) return; down = true; canvas.setPointerCapture(e.pointerId); send(e, "start"); });
      canvas.addEventListener("pointermove", (e) => { if (down) send(e, "drag"); });
      const up = (e) => { if (!down) return; down = false; send(e, "end"); };
      canvas.addEventListener("pointerup", up);
      canvas.addEventListener("pointercancel", up);
      canvas.addEventListener("contextmenu", (e) => e.preventDefault());

      root.querySelectorAll("button[data-event]").forEach((b) => b.addEventListener("click", () => ctx.pushEvent(b.dataset.event, {})));
      root.querySelector(".add").addEventListener("click", () => ctx.pushEvent("add_colour", {colour: root.querySelector(".colour").value}));
      root.querySelector(".set").addEventListener("click", () => ctx.pushEvent("set_colour", {colour: root.querySelector(".colour").value}));
      root.querySelector(".remove").addEventListener("click", () => ctx.pushEvent("remove_colour", {}));
      root.querySelector(".fps").addEventListener("change", (e) => ctx.pushEvent("fps", {fps: parseInt(e.target.value, 10) || 8}));
      root.querySelector(".play").addEventListener("click", () => {
        if (playing) { clearInterval(playing); playing = null; shown = 0; root.querySelector(".play").classList.remove("on"); ctx.pushEvent("frame", {index: frame.frame}); draw(); return; }
        if (frame.frames < 2) return;
        shown = frame.frame;
        root.querySelector(".play").classList.add("on");
        playing = setInterval(() => { shown = (shown + 1) % frame.frames; ctx.pushEvent("frame", {index: shown}); }, 1000 / frame.fps);
      });

      const draw = () => {
        const zoom = frame.zoom;
        canvas.width = frame.width * zoom;
        canvas.height = frame.height * zoom;
        context.imageSmoothingEnabled = false;
        for (let y = 0; y < frame.height; y++) for (let x = 0; x < frame.width; x++) {
          context.fillStyle = checker[(x + y) % 2];
          context.fillRect(x * zoom, y * zoom, zoom, zoom);
          const ghost = frame.ghost && frame.ghost[y][x];
          if (ghost) { context.globalAlpha = 0.35; context.fillStyle = ghost; context.fillRect(x * zoom, y * zoom, zoom, zoom); context.globalAlpha = 1; }
          const colour = frame.pixels[y][x];
          if (colour) { context.fillStyle = colour; context.fillRect(x * zoom, y * zoom, zoom, zoom); }
        }
        if (zoom >= 8) {
          context.strokeStyle = "rgba(0,0,0,0.25)";
          for (let gx = 0; gx <= frame.width; gx++) { context.beginPath(); context.moveTo(gx * zoom + 0.5, 0); context.lineTo(gx * zoom + 0.5, canvas.height); context.stroke(); }
          for (let gy = 0; gy <= frame.height; gy++) { context.beginPath(); context.moveTo(0, gy * zoom + 0.5); context.lineTo(canvas.width, gy * zoom + 0.5); context.stroke(); }
        }
      };

      const render = () => {
        const tools = root.querySelector(".tools");
        tools.innerHTML = "";
        frame.tools.forEach((tool) => {
          const b = document.createElement("button");
          b.textContent = names[tool] || tool;
          if (tool === frame.tool) b.classList.add("on");
          b.addEventListener("click", () => ctx.pushEvent("tool", {tool}));
          tools.appendChild(b);
        });
        const palette = root.querySelector(".palette");
        palette.innerHTML = frame.palette.length ? "" : '<span class="dim">no colours yet: pick one below and add it</span>';
        frame.palette.forEach((entry) => {
          const b = document.createElement("button");
          b.innerHTML = `<i class="swatch" style="background:${entry.css}"></i>${entry.key}`;
          if (entry.key === frame.key) b.classList.add("on");
          b.addEventListener("click", () => ctx.pushEvent("pick", {key: entry.key}));
          palette.appendChild(b);
        });
        const frames = root.querySelector(".frames");
        frames.innerHTML = '<span class="dim">frames</span>';
        for (let i = 0; i < frame.frames; i++) {
          const b = document.createElement("button");
          b.textContent = i + 1;
          if (i === frame.frame) b.classList.add("on");
          b.addEventListener("click", () => ctx.pushEvent("frame", {index: i}));
          frames.appendChild(b);
        }
        root.querySelector(".fps").value = frame.fps;
        root.querySelector(".onion").classList.toggle("on", frame.onion);
        root.querySelector(".undo").disabled = !frame.undo;
        root.querySelector(".redo").disabled = !frame.redo;
        root.querySelector(".save").disabled = !frame.can_save;
        root.querySelector(".status").textContent = frame.status || "";
        draw();
      };

      ctx.handleEvent("frame", (payload) => { frame = payload; render(); });
      render();
    }
    """
  end
end
