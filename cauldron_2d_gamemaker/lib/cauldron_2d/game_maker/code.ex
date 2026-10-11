defmodule Cauldron2D.GameMaker.Code do
  @moduledoc """
  The game's code, as a module that answers for each piece of compiled code by name.

  Names are the ones GameMaker's compiler gives:

    * `gml_Object_<object>_<Event>_<subtype>` — an object's event
      (`Cauldron2D.GameMaker.Event.handler_name/3`)
    * `gml_Room_<room>_Create` — a room's creation code
    * `gml_RoomCC_<room>_<n>_Create` — the creation code of the `n`th instance, counting
      from `0`, among the room's instances that have creation code

  `handler/1` returns a function of the world, the instance running the code (`self`)
  and, for collision events, the other instance's id (`nil` otherwise), returning the
  world. Room creation code runs with `self` `nil`. `nil` from `handler/1` means the game
  has no code there and nothing runs.

      defmodule MyGame.Code do
        @behaviour Cauldron2D.GameMaker.Code

        @impl true
        def handler("gml_Object_Ball_Step_0"), do: &MyGame.Ball.step/3
        def handler(_name), do: nil
      end
  """

  alias Cauldron2D.GameMaker.World

  @type handler :: (World.t(), non_neg_integer() | nil, non_neg_integer() | nil -> World.t())

  @callback handler(name :: String.t()) :: handler() | nil
end
