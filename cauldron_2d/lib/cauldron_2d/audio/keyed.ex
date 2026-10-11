defmodule Cauldron2D.Audio.Keyed do
  @moduledoc """
  A sound event under a key, as `Cauldron2D.Audio.keyed/4`, `moved/2` and `stopped/2`
  build it for `Cauldron2D.Audio.play/2`.

    * `:play` — sound `name` under `key`, at `at`, replacing whatever sounds under `key`;
      with `loop` `true`, round and round until stopped
    * `:move` — the sound under `key` is now at `at`
    * `:stop` — let the sound under `key` go over `fade` seconds

  `at` is `{x, y}` against the listener, `nil` for full level centred, or
  `{:level, gain, pan}` for a level the game works out itself. With `music` `true` the
  music level scales it instead of the effects level.
  """

  @type position :: {number(), number()} | {:level, number(), number()} | nil
  @type t :: %__MODULE__{
          action: :play | :move | :stop,
          key: term(),
          name: term(),
          at: position(),
          fade: float(),
          loop: boolean(),
          music: boolean()
        }

  @enforce_keys [:action, :key]
  defstruct [:action, :key, :name, :at, fade: 0.05, loop: false, music: false]
end
