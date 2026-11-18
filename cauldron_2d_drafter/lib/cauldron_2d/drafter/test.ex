defmodule Cauldron2D.Drafter.Test do
  @moduledoc """
  A game's terminal client (`Cauldron2D.Drafter.Client`) run in a test with no terminal:
  start it with `start/2`, press keys, wait for what shows, and read the screen and the
  client's state.

      ctx =
        Cauldron2D.Drafter.Test.start(
          %{game: MyGame.Client, username: "alice", sink: Cauldron.Audio.Sink.silent()},
          size: {120, 40}
        )

      on_exit(fn -> Cauldron2D.Drafter.Test.stop(ctx) end)
      Cauldron2D.Drafter.Test.send_key(ctx, :enter)
      :ok = Cauldron2D.Drafter.Test.wait_for(ctx, &(Cauldron2D.Drafter.Test.screen_text(&1) =~ "SCORE"))

  Only one client runs at a time, so a test using this is `async: false`, and `stop/1`
  runs before the next test starts one.
  """

  @type ctx :: map()

  @doc """
  The client started with `props`, as `Cauldron2D.Drafter.Client` takes them (`:game`,
  `:username`, `:sink`, `:settings` and the rest), on an in-memory terminal of
  `opts`'s `:size` (`{columns, rows}`, default `{80, 24}`). Returns once the client has
  drawn its first screen; raises when it cannot start.
  """
  @spec start(map(), keyword()) :: ctx()
  def start(props, opts \\ []) do
    Code.ensure_loaded!(Cauldron2D.Drafter.Surface)
    Drafter.Widget.Registry.register(Cauldron2D.Drafter.Surface)
    Drafter.Test.start_headless(Cauldron2D.Drafter.Client, props, opts)
  end

  @doc """
  Stops the client and everything `start/2` started. Safe on a client that has already
  exited; call it from `on_exit/1` so a failing test still frees them for the next one.
  """
  @spec stop(ctx()) :: :ok
  def stop(ctx), do: Drafter.Test.stop(ctx)

  @doc """
  A key pressed, returning once the client has handled it. `key` is a key as the terminal
  names it: `:enter`, `:up`, `:escape`, `:f1`, or a printable character as an atom (`:q`,
  `:" "`); `modifiers` are drawn from `:ctrl`, `:alt` and `:shift`.

      send_key(ctx, :enter)
      send_key(ctx, :s, [:ctrl])
  """
  @spec send_key(ctx(), atom(), [atom()]) :: :ok
  def send_key(ctx, key, modifiers \\ []), do: Drafter.Test.send_key(ctx, key, modifiers)

  @doc """
  A character typed that is not plain ASCII, as a codepoint, returning once the client
  has handled it; a plain letter is `send_key/3`.

      send_char(ctx, ?é)
  """
  @spec send_char(ctx(), integer() | binary()) :: :ok
  def send_char(ctx, char), do: Drafter.Test.send_char(ctx, char)

  @doc """
  A mouse event, returning once the client has handled it: `%{type: :mouse_down |
  :mouse_up | :drag, button: button, x: x, y: y}`, `%{type: :move, x: x, y: y}` or
  `%{type: :scroll, direction: :up | :down | :left | :right, x: x, y: y}`, in cells.

      send_mouse(ctx, %{type: :scroll, direction: :down, x: 10, y: 5})
  """
  @spec send_mouse(ctx(), map()) :: :ok
  def send_mouse(ctx, event), do: Drafter.Test.send_mouse(ctx, event)

  @doc "The client's state: its screen, look, view of the world and the rest. Raises when the client does not answer within a second."
  @spec get_state(ctx()) :: term()
  def get_state(ctx), do: Drafter.Test.get_state(ctx)

  @doc """
  What is on screen, as plain text, one screen row per line.

      assert screen_text(ctx) =~ "SCORE 3"
  """
  @spec screen_text(ctx()) :: String.t()
  def screen_text(ctx), do: Drafter.Test.screen_text(ctx)

  @doc "The characters of each screen row, trailing blanks removed."
  @spec screen_lines(ctx()) :: [String.t()]
  def screen_lines(ctx), do: Drafter.Test.screen_lines(ctx)

  @doc """
  Calls `condition` with `ctx` until it answers truthy: `:ok` then, or `:timeout` after
  `opts`'s `:timeout` milliseconds (default 1000), trying every `:interval` (default 50).

      wait_for(ctx, fn ctx -> get_state(ctx).screen == :play end, timeout: 2_000)
  """
  @spec wait_for(ctx(), (ctx() -> as_boolean(term())), keyword()) :: :ok | :timeout
  def wait_for(ctx, condition, opts \\ []), do: Drafter.Test.wait_for(ctx, condition, opts)

  @doc "Returns once every event sent before it has been handled and its screen drawn; call it between sending input and asserting on state or screen."
  @spec sync(ctx()) :: :ok
  def sync(ctx), do: Drafter.Test.sync(ctx)
end
