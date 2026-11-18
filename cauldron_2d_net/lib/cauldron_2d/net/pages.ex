defmodule Cauldron2D.Net.Pages do
  @moduledoc """
  The pages around a game's worlds in a browser: a title, a lobby of worlds, the
  world, settings and the guide, from a `Cauldron.Client.Game`, as a plug a game
  forwards a path to.

      forward "/play", Cauldron2D.Net.Pages, game: MyGame.Client, username: &MyGame.Web.Auth.username/1, token: &MyGame.Web.Auth.token/1, login: "/login"

  The game's own pages (`c:Cauldron.Client.Game.pages/1`, given `%{username: name}`)
  are linked from every page's header and shown at `page/<key>`. The pages also serve
  the atlas as `atlas.png`, `cauldron.js`, the scene drawing it
  uses where the client draws (`draw/*.js`, `CauldronDraw`), `gamepad.js` (the
  `gamepad` package's browser reader), `phoenix.min.js`, `voice.js` (`Cauldron.Net.Voice`), and `worlds.json` for the
  lobby to refresh from. Links follow the path the pages are mounted at. The world page
  mounts `cauldron.js` on the game's channel with the player's settings — the preset
  and the levels, kept in the browser by the settings page — and the game's `padmap/1`
  (`Cauldron.Client.Game.padmap/3`), and shows the
  round's end over the canvas with a way back to the lobby. While `Cauldron.Net.Voice` is on, the
  world page also loads `voice.js` and starts it on the game's socket as `window.cauldronVoice`.

  ## Options

    * `:game` — the module. Required
    * `:nav` — the links every page's header offers, `{label, path}` pairs; default
      worlds, settings and guide. Pass `[]` for an app whose pages are its own.
    * `:username` — a function from the conn to the player's name, or `nil` when
      nobody is signed in. Default: the conn's `:username` assign
    * `:token` — a function from the conn to the token the socket connects with, sent as
      the `token` socket param. Default: none
    * `:login` — where to send a visitor with no name. Default: none, the page says so
    * `:socket` — the socket's path. Default `"/socket"`
    * `:topic` — the channel topic prefix, as `Cauldron.Net.Channel` takes it.
      Default `"world"`
    * `:scale` — pixels a tile on the canvas. Default `32`
    * `:drawer` — the drawer the game's channel uses (`Cauldron.Net.Drawer`), whose
      browser scripts and join params (`c:Cauldron.Net.Drawer.browser/0`) the world
      page loads, served at `drawer/<name>`. Default `Cauldron2D.Net.Drawer`
  """

  use Plug.Router

  alias Cauldron.Client.{Fronts, Game, Hud, Stage, Start}
  alias Cauldron.Client.Keys, as: ClientKeys
  alias Cauldron.Net.{Drawer, Voice}
  alias Cauldron2D.Net.Atlas
  alias Cauldron2D.Net.Scene.Items

  @draw_files ~w(core.js volume.js surface.js parallax.js screen.js iso.js oblique.js mode7.js first_person.js draw.js)

  plug(:match)
  plug(:dispatch)

  @nav [{"worlds", "/lobby"}, {"settings", "/settings"}, {"guide", "/guide"}]

  @impl Plug
  def init(opts) do
    %{
      game: Keyword.fetch!(opts, :game),
      username: Keyword.get(opts, :username, &__MODULE__.assigned_username/1),
      token: Keyword.get(opts, :token, &__MODULE__.no_token/1),
      login: Keyword.get(opts, :login),
      socket: Keyword.get(opts, :socket, "/socket"),
      topic: Keyword.get(opts, :topic, "world"),
      scale: Keyword.get(opts, :scale, 32),
      drawer: opts |> Keyword.get(:drawer, Cauldron2D.Net.Drawer) |> Drawer.spec() |> elem(0),
      nav: Keyword.get(opts, :nav, @nav)
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
    flow = Start.flow(opts.game, %{username: name})

    case {Start.first_screen(flow), name} do
      {:play, name} when name != nil ->
        redirect(conn, link(opts, "/world/" <> first_world(opts, flow, name)))

      {:lobby, name} when name != nil ->
        redirect(conn, link(opts, "/lobby"))

      _title ->
        title(conn, opts, name, flow)
    end
  end

  get "/lobby" do
    opts = settings(conn)

    with_player(conn, opts, fn name ->
      html(
        conn,
        page(opts, "Worlds", [lobby_page(opts, name), chat_panel(opts)], [
          lobby_script(opts),
          lobby_chat_script(opts, conn, name)
        ])
      )
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

  get "/page/:key" do
    opts = settings(conn)
    name = opts.username.(conn)

    case Enum.find(game_pages(opts, name), &(to_string(&1.key) == key)) do
      nil ->
        send_resp(conn, 404, "no such page")

      found ->
        rows = for row <- found.render.(), do: ~s|<p>#{e(Hud.text(row))}</p>|
        html(conn, page(opts, found.title, [~s|<div class="game-page">|, rows, "</div>"]))
    end
  end

  get "/guide" do
    opts = settings(conn)
    html(conn, page(opts, "Guide", guide_page(opts)))
  end

  get "/atlas.png" do
    conn
    |> put_resp_content_type("image/png")
    |> send_resp(200, Atlas.cached(settings(conn).game.atlas()).png)
  end

  get "/cauldron.js" do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(
      200,
      File.read!(Application.app_dir(:cauldron_2d_net, "priv/static/cauldron.js"))
    )
  end

  get "/voice.js" do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, File.read!(Application.app_dir(:cauldron_2d_net, "priv/static/voice.js")))
  end

  get "/draw/:file" do
    if file in @draw_files do
      conn
      |> put_resp_content_type("application/javascript")
      |> send_resp(
        200,
        File.read!(Application.app_dir(:cauldron_2d_net, "priv/static/draw/" <> file))
      )
    else
      send_resp(conn, 404, "not found")
    end
  end

  get "/drawer/:file" do
    case List.keyfind(browser(settings(conn)).scripts, file, 0) do
      {_name, path} ->
        conn
        |> put_resp_content_type("application/javascript")
        |> send_resp(200, File.read!(path))

      nil ->
        send_resp(conn, 404, "not found")
    end
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

  defp title(conn, opts, name, flow) do
    if name != nil and Map.has_key?(Fronts.of(opts.game, %{username: name}), :title),
      do:
        html(
          conn,
          page(opts, "", front_page(), mount_script(opts, conn, name, "front:title", %{}, flow))
        ),
      else: html(conn, page(opts, "", title_page(opts, name)))
  end

  defp first_world(opts, {:play, :first, _flow_opts}, name),
    do:
      opts.game.worlds(%{username: name})
      |> List.first(%{id: ""})
      |> Map.fetch!(:id)
      |> to_string()

  defp first_world(_opts, {:play, id, _flow_opts}, _name), do: to_string(id)

  defp redirect(conn, to), do: conn |> put_resp_header("location", to) |> send_resp(302, "")

  defp front_page do
    ~s|<div class="world-page front" id="world"><div class="stage"><canvas></canvas></div></div>|
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
      Enum.map(opts.nav, fn {label, path} ->
        ~s|<a href="#{link(opts, path)}">#{e(label)}</a> |
      end),
      Enum.map(game_pages(opts, nil), fn found ->
        ~s| <a href="#{link(opts, "/page/" <> to_string(found.key))}">#{e(found.title)}</a>|
      end),
      "</nav></header>",
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
      ~s| <span class="players">#{e(players_text(opts.game, world))}</span>|,
      if(Map.get(world, :map), do: ~s| <span class="map">#{e(world.map)}</span>|, else: ""),
      if(Map.get(world, :note), do: ~s|<p class="note">#{e(world.note)}</p>|, else: ""),
      ~s|<p class="joins">|,
      Enum.map(teams, fn team ->
        ~s|<a href="#{link(opts, "/world/#{id}?team=#{e(team)}")}">team #{e(team)}</a> |
      end),
      ~s|<a href="#{link(opts, "/world/#{id}?spectate=1")}">watch</a></p></li>|
    ]
  end

  defp players_text(game, %{humans: [_ | _] = humans}),
    do: humans |> Enum.map(&Game.player_label(game, &1)) |> Enum.sort() |> Enum.join(", ")

  defp players_text(_game, world), do: "#{Map.get(world, :players, 0)} playing"

  defp game_pages(opts, name), do: Game.optional(opts.game, :pages, [%{username: name}], [])

  defp kind_text(world) do
    case Map.get(world, :kind) do
      {text, _rgb} -> text
      text when is_binary(text) -> text
      _none -> nil
    end
  end

  defp chat_panel(opts) do
    if Stage.chat?(opts.game),
      do:
        ~s|<div class="chat" id="chat"><div class="chat-lines" id="chat-lines"></div><input id="chat-input" maxlength="500" placeholder="say something, Enter sends" autocomplete="off"></div>|,
      else: ""
  end

  defp chat_script do
    """
    function Chat(send) {
      var lines = document.getElementById("chat-lines");
      var input = document.getElementById("chat-input");
      if (!lines || !input) return { add: function () {}, focus: function () {} };
      input.addEventListener("keydown", function (event) {
        if (event.key === "Enter") { if (input.value.trim()) send(input.value); input.value = ""; input.blur(); event.preventDefault(); }
        else if (event.key === "Escape") { input.value = ""; input.blur(); event.preventDefault(); }
      });
      return {
        add: function (message) {
          var line = document.createElement("p");
          var who = document.createElement("b");
          who.textContent = message.from + " ";
          line.appendChild(who);
          line.appendChild(document.createTextNode(message.text));
          lines.appendChild(line);
          while (lines.childNodes.length > 100) lines.removeChild(lines.firstChild);
          lines.scrollTop = lines.scrollHeight;
        },
        focus: function () { input.focus(); }
      };
    }
    """
  end

  defp lobby_chat_script(opts, conn, name) do
    if Stage.chat?(opts.game) do
      token = opts.token.(conn)

      """
      <script src="#{link(opts, "/phoenix.min.js")}"></script>
      <script>#{chat_script()}</script>
      <script>
      (function () {
        var socket = new Phoenix.Socket(#{Jason.encode!(opts.socket)}, { params: #{Jason.encode!(if(token, do: %{token: token, username: name}, else: %{username: name}))} });
        socket.connect();
        var channel = socket.channel(#{Jason.encode!("#{opts.topic}:chat:lobby")}, {});
        var chat = Chat(function (text) { channel.push("say", { text: text }); });
        channel.on("chat", chat.add);
        channel.on("chat_history", function (history) { history.messages.forEach(chat.add); });
        channel.join();
      })();
      </script>
      """
    else
      ""
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

  defp world_page(opts, world) do
    [
      ~s|<div class="world-page" id="world"><div class="stage"><canvas></canvas><div class="opening" id="opening">#{opening_lines(opts, world)}</div><div class="over" id="over" hidden><h2 id="over-title"></h2><div id="over-lines"></div><p><a class="button" id="over-again" href="">again</a> <a class="button" id="over-lobby" href="">lobby</a></p></div></div>|,
      ~s|<aside class="side"><div class="hud" id="hud"></div>#{chat_panel(opts)}</aside></div>|,
      ~s|<p class="note" id="status">#{key_hints(opts.game)}</p>|
    ]
  end

  defp key_hints(game) do
    keys = ClientKeys.of(game)

    [
      pause: "pauses a world of your own",
      zoom_in: "zooms in",
      zoom_out: "zooms out",
      menu: "opens the menu",
      talk: "talks"
    ]
    |> Enum.flat_map(fn {action, text} ->
      case keys |> Map.get(action) |> List.wrap() do
        [key | _] -> [~s|<kbd>#{e(key_name(key))}</kbd> #{text}|]
        [] -> []
      end
    end)
    |> Enum.join(", ")
  end

  defp key_name(:escape), do: "Esc"
  defp key_name(:" "), do: "Space"
  defp key_name(key), do: to_string(key)

  defp opening_lines(opts, world) do
    for row <- Game.optional(opts.game, :opening, [world], []),
        into: "",
        do: ~s|<p>#{e(Hud.text(row))}</p>|
  end

  defp world_script(opts, conn, world, name) do
    params = conn.query_params |> Map.take(["team", "spectate"])
    mount_script(opts, conn, name, to_string(world.id), params, world)
  end

  defp mount_script(opts, conn, name, id, params, place) do
    presets = for {preset, _keymap} <- opts.game.keymaps(), do: Atom.to_string(preset)

    token = opts.token.(conn)
    world_name = if is_map(place), do: place.name, else: opts.game.title().name
    browser = browser(opts)
    module = if browser.scripts == [], do: "", else: ~s| type="module"|

    """
    <script src="#{link(opts, "/phoenix.min.js")}"></script>
    <script src="#{link(opts, "/gamepad.js")}"></script>
    #{Enum.map_join(@draw_files, "\n", &~s|<script src="#{link(opts, "/draw/" <> &1)}"></script>|)}
    <script src="#{link(opts, "/cauldron.js")}"></script>
    #{voice_tag(opts)}
    #{browser.head}
    #{Enum.map_join(browser.scripts, "\n", fn {name, _path} -> ~s|<script type="module" src="#{link(opts, "/drawer/" <> name)}"></script>| end)}
    <script>#{chat_script()}</script>
    <script#{module}>
    (function () {
      var presets = #{Jason.encode!(presets)};
      var settings = {};
      try { settings = JSON.parse(localStorage.getItem(#{Jason.encode!(settings_key(opts))}) || localStorage.getItem(#{Jason.encode!(atlas_settings_key(opts))}) || "{}"); } catch (e) {}
      var preset = presets.indexOf(settings.preset) >= 0 ? settings.preset : presets[0];
      var status = document.getElementById("status") || { textContent: "" };
      var over = document.getElementById("over") || { hidden: true };
      var hud = document.getElementById("hud");
      var chat = Chat(function (text) { game.say(text); });
      var fronted = false;
      if (document.getElementById("over-lobby")) document.getElementById("over-lobby").href = #{Jason.encode!(link(opts, "/lobby"))};
      if (document.getElementById("over-again")) document.getElementById("over-again").href = location.href;
      var settingsKey = #{Jason.encode!(settings_key(opts))};
      var joinParams = Object.assign(#{Jason.encode!(params)}, #{Jason.encode!(browser.params)});
      if (settings.saved) joinParams.saved = settings.saved;
      if (preset) joinParams.preset = preset;
      if (typeof settings.fps === "number") joinParams.fps = settings.fps;
      if (typeof settings.pointer === "boolean") joinParams.pointer = settings.pointer;
      var places = { lobby: #{Jason.encode!(link(opts, "/lobby"))}, settings: #{Jason.encode!(link(opts, "/settings"))}, guide: #{Jason.encode!(link(opts, "/guide"))}, title: #{Jason.encode!(link(opts, "/"))} };
      var worldBase = #{Jason.encode!(link(opts, "/world/"))};
      var game = Cauldron.mount(document.querySelector("#world canvas"), {
        socketUrl: #{Jason.encode!(opts.socket)},
        socketParams: #{Jason.encode!(if(token, do: %{token: token, username: name}, else: %{username: name}))},
        topic: #{Jason.encode!("#{opts.topic}:#{id}")},
        params: joinParams,
        hud: hud,
        scale: #{opts.scale},
        fit: true,
        onGo: function (to, go) {
          if (to === "world") { location.href = worldBase + encodeURIComponent(go.id); return; }
          if (to === "quit") { try { window.close(); } catch (e) {} return; }
          if (places[to]) location.href = places[to];
        },
        onFront: function () { fronted = true; over.hidden = true; if (hud) hud.hidden = true; },
        onWorld: function (id) { history.replaceState(null, "", worldBase + encodeURIComponent(id)); },
        onChat: function (message) { chat.add(message); },
        onChatHistory: function (messages) { messages.forEach(chat.add); },
        onTalk: function () { chat.focus(); },
        onSettings: function (changed) {
          settings.sfx = changed.sfx; settings.music = changed.music; settings.saved = changed.saved;
          try { localStorage.setItem(settingsKey, JSON.stringify(settings)); } catch (e) {}
        },
        onJoin: function () { var opening = document.getElementById("opening"); if (opening) opening.hidden = true; status.textContent = "in #{e(world_name)} as #{e(name)}"; game.levels(settings.sfx == null ? 0.85 : settings.sfx, settings.music == null ? 0.35 : settings.music); },
        onError: function (reason) { status.textContent = "could not join: " + reason; },
        onOver: function (outcome) {
          if (fronted) return;
          document.getElementById("over-title").textContent = outcome.title;
          document.getElementById("over-lines").innerHTML = outcome.lines.map(function (line) { return "<p>" + line.replace(/[&<>]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]; }) + "</p>"; }).join("");
          over.hidden = false;
        }
      });
      #{voice_start()}
      window.addEventListener("beforeunload", function () { if (window.cauldronVoice) window.cauldronVoice.stop(); game.stop(); });
    })();
    </script>
    """
  end

  defp browser(opts) do
    Code.ensure_loaded(opts.drawer)

    if function_exported?(opts.drawer, :browser, 0),
      do: opts.drawer.browser(),
      else: %{scripts: [], head: "", params: %{}}
  end

  defp settings_key(opts), do: "cauldron:#{Game.home(opts.game)}:settings"
  defp atlas_settings_key(opts), do: "cauldron:#{opts.game.atlas()}:settings"

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
      ~s|<label>Frame rate <select name="fps">|,
      Enum.map(Game.frame_rates(opts.game), fn rate ->
        ~s|<option value="#{rate}">#{if rate == :auto, do: "auto", else: "#{rate} a second"}</option>|
      end),
      ~s|</select></label>|,
      ~s|<label><input type="checkbox" name="pointer" checked> The pointer aims</label>|,
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
      try { saved = JSON.parse(localStorage.getItem(key) || localStorage.getItem(#{Jason.encode!(atlas_settings_key(opts))}) || "{}"); } catch (e) {}
      if (saved.preset) form.preset.value = saved.preset;
      if (saved.sfx != null) form.sfx.value = saved.sfx;
      if (saved.music != null) form.music.value = saved.music;
      if (saved.fps != null) form.fps.value = String(saved.fps);
      if (saved.pointer != null) form.pointer.checked = saved.pointer;
      function show() {
        document.querySelectorAll(".preset").forEach(function (dl) { dl.hidden = dl.dataset.preset !== form.preset.value; });
      }
      function save() {
        localStorage.setItem(key, JSON.stringify({ preset: form.preset.value, sfx: parseFloat(form.sfx.value), music: parseFloat(form.music.value), fps: form.fps.value === "auto" ? "auto" : parseInt(form.fps.value, 10), pointer: form.pointer.checked, saved: saved.saved }));
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
    sheet = Atlas.cached(opts.game.atlas()).index
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
    case Map.get(sheet.arts, Items.art_name(art)) do
      nil ->
        ""

      %{frames: [[x, y, width, height] | _]} ->
        ~s|<span class="art" style="background-image:url(#{url});background-position:-#{x}px -#{y}px;width:#{width}px;height:#{height}px"></span>|
    end
  end

  defp voice_tag(opts) do
    if Voice.open?(),
      do: ~s|<script src="#{link(opts, "/voice.js")}"></script>|,
      else: ""
  end

  defp voice_start do
    if Voice.open?(),
      do: "window.cauldronVoice = CauldronVoice.start(game.socket());",
      else: ""
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
    main:has(.world-page){max-width:none}.world-page{display:flex;gap:1rem;height:calc(100dvh - 15rem);min-height:20rem}.stage{position:relative;flex:1;min-width:0;min-height:0;background:#000;overflow:hidden}.stage canvas{display:block;width:100%;height:100%;image-rendering:pixelated}
    .side{width:18rem;display:flex;flex-direction:column;gap:1rem}.side:not(:has(:not([hidden]))){display:none}.hud{font-family:ui-monospace,monospace;white-space:pre-wrap;font-size:14px}.hud div{margin:0}
    .chat{display:flex;flex-direction:column;gap:.4rem;min-height:12rem}.chat-lines{flex:1;overflow-y:auto;max-height:24rem;font-size:14px}.chat-lines p{margin:.1rem 0}
    .chat input{background:#181826;color:#e8e8f0;border:1px solid #26263a;border-radius:.3rem;padding:.4rem}
    .opening{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}.opening p{margin:0}
    .over{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;background:rgba(0,0,0,.7)}
    .settings label{display:block;margin:.6rem 0}.preset dt{font-weight:bold;display:inline-block;width:10rem}.preset dd{display:inline;margin:0}.preset dd::after{content:"";display:block}
    .guide dt{margin-top:.6rem;font-weight:bold}.art{display:inline-block;background-repeat:no-repeat;image-rendering:pixelated;transform:scale(2);transform-origin:left center;margin-right:1rem;vertical-align:middle}
    kbd{background:#26263a;padding:0 .3rem;border-radius:.2rem}
    .over[hidden],.opening[hidden],.hud[hidden]{display:none}
    """
  end
end
