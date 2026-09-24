defmodule Cauldron2D.Net.Pages do
  @moduledoc """
  The pages around a game's worlds in a browser: a title, a lobby of worlds, the
  world, settings and the guide, from a `Cauldron2D.Client.Game`, as a plug a game
  forwards a path to.

      forward "/play", Cauldron2D.Net.Pages, game: MyGame.Client, username: &MyGame.Web.Auth.username/1, token: &MyGame.Web.Auth.token/1, login: "/login"

  The pages also serve the atlas as `atlas.png`, `cauldron.js`, `gamepad.js` (the
  `gamepad` package's browser reader) and `phoenix.min.js`, and `worlds.json` for the
  lobby to refresh from. Links follow the path the pages are mounted at. The world page
  mounts `cauldron.js` on the game's channel with the player's settings — the preset
  and the levels, kept in the browser by the settings page — and the game's `padmap/1`
  (`Cauldron2D.Input.Pad.default_map/1` of its actions without one), and shows the
  round's end over the canvas with a way back to the lobby.

  ## Options

    * `:game` — the module. Required
    * `:username` — a function from the conn to the player's name, or `nil` when
      nobody is signed in. Default: the conn's `:username` assign
    * `:token` — a function from the conn to the token the socket connects with, sent as
      the `token` socket param. Default: none
    * `:login` — where to send a visitor with no name. Default: none, the page says so
    * `:socket` — the socket's path. Default `"/socket"`
    * `:topic` — the channel topic prefix, as `Cauldron2D.Net.Channel` takes it.
      Default `"world"`
    * `:scale` — pixels a tile on the canvas. Default `32`
  """

  use Plug.Router

  alias Cauldron2D.Client.Game
  alias Cauldron2D.Input.Pad
  alias Cauldron2D.Net.{Keys, Sheet}

  plug(:match)
  plug(:dispatch)

  @impl Plug
  def init(opts) do
    %{
      game: Keyword.fetch!(opts, :game),
      username: Keyword.get(opts, :username, &__MODULE__.assigned_username/1),
      token: Keyword.get(opts, :token, &__MODULE__.no_token/1),
      login: Keyword.get(opts, :login),
      socket: Keyword.get(opts, :socket, "/socket"),
      topic: Keyword.get(opts, :topic, "world"),
      scale: Keyword.get(opts, :scale, 32)
    }
  end

  @doc "The default `:username`: the conn's `:username` assign."
  @spec assigned_username(Plug.Conn.t()) :: String.t() | nil
  def assigned_username(conn), do: conn.assigns[:username]

  @doc "The default `:token`: none."
  @spec no_token(Plug.Conn.t()) :: nil
  def no_token(_conn), do: nil

  @impl Plug
  def call(conn, opts),
    do:
      conn
      |> fetch_query_params()
      |> put_private(:cauldron_pages, Map.put(opts, :base, base(conn)))
      |> super([])

  defp settings(conn), do: conn.private.cauldron_pages

  get "/" do
    opts = settings(conn)
    name = opts.username.(conn)
    html(conn, page(opts, "", title_page(opts, name)))
  end

  get "/lobby" do
    opts = settings(conn)

    with_player(conn, opts, fn name ->
      html(conn, page(opts, "Worlds", lobby_page(opts, name), lobby_script(opts)))
    end)
  end

  get "/worlds.json" do
    opts = settings(conn)

    with_player(conn, opts, fn name ->
      worlds =
        for world <- opts.game.worlds(%{username: name}),
            do: %{
              id: to_string(world.id),
              name: world.name,
              players: Map.get(world, :players, 0),
              map: Map.get(world, :map),
              note: Map.get(world, :note),
              kind: kind_text(world),
              teams: Map.get(world, :teams, [])
            }

      conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(worlds))
    end)
  end

  get "/world/:id" do
    opts = settings(conn)

    with_player(conn, opts, fn name ->
      case Game.world(opts.game, %{username: name}, id) do
        nil ->
          send_resp(conn, 404, "no such world")

        world ->
          html(
            conn,
            page(opts, world.name, world_page(opts, world), world_script(opts, conn, world, name))
          )
      end
    end)
  end

  get "/settings" do
    opts = settings(conn)

    with_player(conn, opts, fn _name ->
      html(conn, page(opts, "Settings", settings_page(opts), settings_script(opts)))
    end)
  end

  get "/guide" do
    opts = settings(conn)
    html(conn, page(opts, "Guide", guide_page(opts)))
  end

  get "/atlas.png" do
    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, Sheet.cached(settings(conn).game.atlas()).png)
  end

  get "/cauldron.js" do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(
      200,
      File.read!(Application.app_dir(:cauldron_2d_net, "priv/static/cauldron.js"))
    )
  end

  get "/gamepad.js" do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, File.read!(Gamepad.browser_script()))
  end

  get "/phoenix.min.js" do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.min.js")))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp base(%{script_name: []}), do: ""
  defp base(%{script_name: parts}), do: "/" <> Enum.join(parts, "/")

  defp with_player(conn, opts, fun) do
    case opts.username.(conn) do
      nil when is_binary(opts.login) ->
        conn |> put_resp_header("location", opts.login) |> send_resp(302, "")

      nil ->
        html(conn, page(opts, "Sign in", [~s|<p class="note">Sign in to play.</p>|]), 401)

      name ->
        fun.(name)
    end
  end

  defp html(conn, body, status \\ 200),
    do: conn |> put_resp_content_type("text/html") |> send_resp(status, body)

  defp e(text), do: text |> to_string() |> Plug.HTML.html_escape()
  defp link(opts, path), do: opts.base <> path

  defp page(opts, heading, body, script \\ "") do
    name = opts.game.title().name

    [
      ~s|<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">|,
      "<title>",
      e(if heading == "", do: name, else: "#{heading} · #{name}"),
      "</title><style>",
      css(),
      "</style></head><body>",
      ~s|<header><a class="brand" href="#{link(opts, "/")}">#{e(name)}</a><nav>|,
      ~s|<a href="#{link(opts, "/lobby")}">worlds</a> <a href="#{link(opts, "/settings")}">settings</a> <a href="#{link(opts, "/guide")}">guide</a></nav></header>|,
      "<main>",
      if(heading == "", do: "", else: "<h1>#{e(heading)}</h1>"),
      body,
      "</main>",
      script,
      "</body></html>"
    ]
  end

  defp title_page(opts, name) do
    title = opts.game.title()

    [
      ~s|<section class="title"><h1 class="big">#{e(title.name)}</h1>|,
      if(Map.get(title, :tagline), do: "<p class=\"tagline\">#{e(title.tagline)}</p>", else: ""),
      if(name,
        do: ~s|<p><a class="button" href="#{link(opts, "/lobby")}">Play as #{e(name)}</a></p>|,
        else:
          if(opts.login,
            do: ~s|<p><a class="button" href="#{e(opts.login)}">Sign in</a></p>|,
            else: ~s|<p class="note">Sign in to play.</p>|
          )
      ),
      ~s|<p class="links"><a href="#{link(opts, "/guide")}">guide</a> · <a href="#{link(opts, "/settings")}">settings</a></p></section>|
    ]
  end

  defp lobby_page(opts, name) do
    worlds = opts.game.worlds(%{username: name})
    [~s|<ul class="worlds" id="worlds">|, Enum.map(worlds, &world_row(opts, &1)), "</ul>"]
  end

  defp world_row(opts, world) do
    id = to_string(world.id)
    teams = Map.get(world, :teams, [])

    [
      ~s|<li class="world" data-id="#{e(id)}"><a class="name" href="#{link(opts, "/world/#{id}")}">#{e(world.name)}</a>|,
      if(kind_text(world), do: ~s| <span class="kind">#{e(kind_text(world))}</span>|, else: ""),
      ~s| <span class="players">#{Map.get(world, :players, 0)} playing</span>|,
      if(Map.get(world, :map), do: ~s| <span class="map">#{e(world.map)}</span>|, else: ""),
      if(Map.get(world, :note), do: ~s|<p class="note">#{e(world.note)}</p>|, else: ""),
      ~s|<p class="joins">|,
      Enum.map(teams, fn team ->
        ~s|<a href="#{link(opts, "/world/#{id}?team=#{e(team)}")}">team #{e(team)}</a> |
      end),
      ~s|<a href="#{link(opts, "/world/#{id}?spectate=1")}">watch</a></p></li>|
    ]
  end

  defp kind_text(world) do
    case Map.get(world, :kind) do
      {text, _rgb} -> text
      text when is_binary(text) -> text
      _none -> nil
    end
  end

  defp lobby_script(opts) do
    """
    <script>
    (function () {
      var list = document.getElementById("worlds");
      setInterval(function () {
        fetch("#{link(opts, "/worlds.json")}").then(function (r) { return r.json(); }).then(function (worlds) {
          worlds.forEach(function (world) {
            var row = list.querySelector('[data-id="' + world.id + '"] .players');
            if (row) row.textContent = world.players + " playing";
          });
        });
      }, 3000);
    })();
    </script>
    """
  end

  defp world_page(_opts, world) do
    [
      ~s|<div class="world-page" id="world"><div class="stage"><canvas></canvas><div class="over" id="over" hidden><h2 id="over-title"></h2><div id="over-lines"></div><p><a class="button" id="over-again" href="">again</a> <a class="button" id="over-lobby" href="">lobby</a></p></div></div>|,
      ~s|<aside class="hud" id="hud"></aside></div>|,
      ~s|<p class="note" id="status">joining #{e(world.name)}…  <kbd>p</kbd> pauses a world of your own, <kbd>+</kbd><kbd>−</kbd> zoom</p>|
    ]
  end

  defp world_script(opts, conn, world, name) do
    presets =
      for {preset, keymap} <- opts.game.keymaps(),
          into: %{},
          do: {Atom.to_string(preset), Keys.browser_keymap(keymap)}

    steering = opts.game |> Game.optional(:steering, [], []) |> Enum.map(&Atom.to_string/1)

    padmap =
      Keys.browser_padmap(
        Game.optional(
          opts.game,
          :padmap,
          [%{username: name}],
          Pad.default_map(opts.game.actions())
        )
      )

    params = conn.query_params |> Map.take(["team", "spectate"])
    token = opts.token.(conn)

    """
    <script src="#{link(opts, "/phoenix.min.js")}"></script>
    <script src="#{link(opts, "/gamepad.js")}"></script>
    <script src="#{link(opts, "/cauldron.js")}"></script>
    <script>
    (function () {
      var presets = #{Jason.encode!(presets)};
      var settings = {};
      try { settings = JSON.parse(localStorage.getItem(#{Jason.encode!(settings_key(opts))}) || "{}"); } catch (e) {}
      var preset = presets[settings.preset] ? settings.preset : Object.keys(presets)[0];
      var status = document.getElementById("status");
      var over = document.getElementById("over");
      document.getElementById("over-lobby").href = #{Jason.encode!(link(opts, "/lobby"))};
      document.getElementById("over-again").href = location.href;
      var game = Cauldron.mount(document.querySelector("#world canvas"), {
        socketUrl: #{Jason.encode!(opts.socket)},
        socketParams: #{Jason.encode!(if(token, do: %{token: token, username: name}, else: %{username: name}))},
        topic: #{Jason.encode!("#{opts.topic}:#{world.id}")},
        params: #{Jason.encode!(params)},
        hud: document.getElementById("hud"),
        scale: #{opts.scale},
        keymap: presets[preset] || {},
        padmap: #{Jason.encode!(padmap)},
        steering: #{Jason.encode!(steering)},
        pause: "KeyP",
        zoom: { min: 2, max: 64 },
        onJoin: function () { status.textContent = "in #{e(world.name)} as #{e(name)}"; game.levels(settings.sfx == null ? 0.85 : settings.sfx, settings.music == null ? 0.35 : settings.music); },
        onError: function (reason) { status.textContent = "could not join: " + reason; },
        onOver: function (outcome) {
          document.getElementById("over-title").textContent = outcome.title;
          document.getElementById("over-lines").innerHTML = outcome.lines.map(function (line) { return "<p>" + line.replace(/[&<>]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]; }) + "</p>"; }).join("");
          over.hidden = false;
        }
      });
      window.addEventListener("beforeunload", function () { game.stop(); });
    })();
    </script>
    """
  end

  defp settings_key(opts), do: "cauldron:#{opts.game.atlas()}:settings"

  defp settings_page(opts) do
    presets = for {preset, keymap} <- opts.game.keymaps(), do: {Atom.to_string(preset), keymap}

    [
      ~s|<form class="settings" id="settings"><label>Keys <select name="preset">|,
      Enum.map(presets, fn {preset, _} ->
        ~s|<option value="#{e(preset)}">#{e(preset)}</option>|
      end),
      ~s|</select></label>|,
      Enum.map(presets, fn {preset, keymap} ->
        [
          ~s|<dl class="preset" data-preset="#{e(preset)}">|,
          Enum.map(keymap, fn {action, keys} ->
            ~s|<dt>#{e(action)}</dt><dd>#{e(Enum.map_join(keys, ", ", &key_text/1))}</dd>|
          end),
          "</dl>"
        ]
      end),
      ~s|<label>Effects <input type="range" name="sfx" min="0" max="1" step="0.05" value="0.85"></label>|,
      ~s|<label>Music <input type="range" name="music" min="0" max="1" step="0.05" value="0.35"></label>|,
      ~s|<p class="note">Kept in this browser.</p></form>|
    ]
  end

  defp key_text({:mouse, button}), do: "mouse #{button}"
  defp key_text({key, mods}), do: Enum.map_join(mods, "+", &to_string/1) <> "+" <> to_string(key)
  defp key_text(key), do: to_string(key)

  defp settings_script(opts) do
    """
    <script>
    (function () {
      var key = #{Jason.encode!(settings_key(opts))};
      var form = document.getElementById("settings");
      var saved = {};
      try { saved = JSON.parse(localStorage.getItem(key) || "{}"); } catch (e) {}
      if (saved.preset) form.preset.value = saved.preset;
      if (saved.sfx != null) form.sfx.value = saved.sfx;
      if (saved.music != null) form.music.value = saved.music;
      function show() {
        document.querySelectorAll(".preset").forEach(function (dl) { dl.hidden = dl.dataset.preset !== form.preset.value; });
      }
      function save() {
        localStorage.setItem(key, JSON.stringify({ preset: form.preset.value, sfx: parseFloat(form.sfx.value), music: parseFloat(form.music.value) }));
        show();
      }
      form.addEventListener("input", save);
      form.addEventListener("change", save);
      show();
    })();
    </script>
    """
  end

  defp guide_page(opts) do
    sheet = Sheet.cached(opts.game.atlas())
    sections = Game.optional(opts.game, :guide, [], [])
    url = link(opts, "/atlas.png")

    if sections == [] do
      [~s|<p class="note">This game has no guide.</p>|]
    else
      Enum.map(sections, fn {heading, entries} ->
        [
          "<h2>#{e(heading)}</h2><dl class=\"guide\">",
          Enum.map(entries, fn entry ->
            [
              ~s|<dt>|,
              art_span(sheet, url, entry.art),
              ~s| #{e(entry.name)}</dt><dd>#{e(entry.text)}</dd>|
            ]
          end),
          "</dl>"
        ]
      end)
    end
  end

  defp art_span(sheet, url, art) do
    case Map.get(sheet.arts, art) do
      nil ->
        ""

      index ->
        [x, y] = Enum.at(sheet.frames, index)

        ~s|<span class="art" style="background-image:url(#{url});background-position:-#{x}px -#{y}px;width:#{sheet.tile}px;height:#{sheet.tile}px"></span>|
    end
  end

  defp css do
    """
    body{margin:0;background:#101018;color:#e8e8f0;font:16px/1.4 system-ui,sans-serif}
    header{display:flex;justify-content:space-between;padding:.6rem 1rem;background:#181826}
    header a{color:#e8e8f0;text-decoration:none;margin-left:1rem}header .brand{font-weight:bold;margin:0}
    main{padding:1rem;max-width:64rem;margin:0 auto}
    .title{text-align:center;padding:4rem 0}.big{font-size:3rem;margin:0}.tagline{color:#a0a0b8}
    .button{display:inline-block;padding:.5rem 1rem;background:#3b5bdb;color:#fff;border-radius:.3rem;text-decoration:none}
    .note{color:#a0a0b8}.worlds{list-style:none;padding:0}.world{padding:.6rem 0;border-bottom:1px solid #26263a}
    .world .name{font-weight:bold;color:#fff}.kind{color:#7fe07f}.players{color:#a0a0b8;margin-left:.6rem}.map{color:#a0a0b8;margin-left:.6rem}
    .joins a{margin-right:.6rem;color:#8fb2ff}
    .world-page{display:flex;gap:1rem}.stage{position:relative;flex:1;min-height:60vh;background:#000}.stage canvas{display:block;width:100%;height:100%;image-rendering:pixelated}
    .hud{width:18rem;font-family:ui-monospace,monospace;white-space:pre;font-size:14px}.hud div{margin:0}
    .over{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,.7)}
    .settings label{display:block;margin:.6rem 0}.preset dt{font-weight:bold;display:inline-block;width:10rem}.preset dd{display:inline;margin:0}.preset dd::after{content:"";display:block}
    .guide dt{margin-top:.6rem;font-weight:bold}.art{display:inline-block;background-repeat:no-repeat;image-rendering:pixelated;transform:scale(2);transform-origin:left center;margin-right:1rem;vertical-align:middle}
    kbd{background:#26263a;padding:0 .3rem;border-radius:.2rem}
    """
  end
end
