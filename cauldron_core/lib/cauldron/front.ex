defmodule Cauldron.Front do
  @moduledoc """
  A screen outside the world that the game draws and runs itself — its title, the
  summary when play is over — while the client keeps the moves between screens.

  A game names its fronts in `Cauldron.Client.Game`'s `fronts/1`:

      def fronts(_props), do: %{title: MyGame.Title, summary: MyGame.GameOver}

  A screen with no front is the client's own. A front is a module with this behaviour.
  The client calls `init/2` when the screen opens, `tick/2` as time passes, `event/3`
  for every key, mouse button and controller press (a controller's d-pad as the keys
  `:up`, `:down`, `:left` and `:right`, `A` as `:enter`, `B` and `Start` as `:escape`,
  each as `{:key, key, [:pad]}`), and draws `scene/1` as it draws a world's scene:
  atlas, layers, `:screen`, or a `:picture`.

  `Cauldron.Menu` gives a front its menu behaviour: keep a menu in the front's state,
  hand it the events, and turn its requests into moves.

  ## Moves

  `event/3` returns `%{state: state, settings: settings}`, with `:sounds` (sound events
  as the game's `sounds/0` table knows them) and `:go`, where the client goes next:

    * `:play` — what the title's Enter does: the world of a `{:play, id}` flow, else the lobby
    * `{:play, id}` — world `id` of `worlds/1`
    * `:again` — on the summary, what its Enter does: the next world or the same one
      again, as the outcome's `next` says
    * `:lobby`, `:title`, `:settings`, `:guide` — that screen
    * `:back` — where the screen's `Esc` goes: out of the program from the title, the
      lobby or title from the summary
    * `:quit` — end the client

  Settings changed in `event/3` are saved and take effect at once, as a game menu's are.

  ## Context

  `init/2` is given the screen (`:title` or `:summary`) and a map of `:settings` (the
  player's), `:username`, `:worlds` (the game's `worlds/1`), and on the summary
  `:outcome` (what `outcome/1` returned) and `:view` (the world's last view).
  """

  @type screen :: :title | :summary
  @type go ::
          :play
          | {:play, term()}
          | :again
          | :lobby
          | :title
          | :settings
          | :guide
          | :back
          | :quit
  @type reply :: %{
          required(:state) => term(),
          required(:settings) => map(),
          optional(:sounds) => [term()],
          optional(:go) => go()
        }

  @doc "The front's state as `screen` opens."
  @callback init(screen(), map()) :: term()

  @doc "The state after one input event, and what follows from it."
  @callback event(term(), term(), map()) :: reply()

  @doc "The state `ms` milliseconds later."
  @callback tick(term(), non_neg_integer()) :: term()

  @doc "What to draw, as `c:Cauldron.Client.Game.scene/1` returns it."
  @callback scene(term()) :: Cauldron.Client.Game.scene()

  @doc "The music to play, as `c:Cauldron.Client.Game.cue/2` returns it; `nil` for none."
  @callback cue(term()) :: Cauldron.Audio.Music.cue() | nil

  @optional_callbacks tick: 2, cue: 1

  @doc "`module`'s state after `ms` milliseconds, unchanged when it has no `tick/2`."
  @spec tick(module(), term(), non_neg_integer()) :: term()
  def tick(module, state, ms) do
    if function_exported?(module, :tick, 2), do: module.tick(state, ms), else: state
  end

  @doc "`module`'s music for `state`, `nil` when it has no `cue/1`."
  @spec cue(module(), term()) :: Cauldron.Audio.Music.cue() | nil
  def cue(module, state) do
    if function_exported?(module, :cue, 1), do: module.cue(state), else: nil
  end
end
