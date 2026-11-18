defmodule Cauldron3D.Scene.SpriteLayer do
  @moduledoc """
  Sprites drawn in order into a target, one layer of a `{:layers, [layer]}` change.

    * `target` — `:frame` (the default), the window's picture, or a canvas handle
    * `clear` — `{r, g, b, a}` from 0 to 1 the target is filled with first; `nil` (the
      default) draws over what the target holds
    * `port` — `{x, y, width, height}` in the target's pixels; the sprites are drawn
      only inside it. `nil` (the default) is the whole target
    * `view` — `{x, y, width, height}`, the part of the sprites' space shown in the
      port, stretched to fill it. `nil` (the default) places sprites in pixels from the
      port's top-left corner
    * `sprites` — `Cauldron3D.Scene.Sprite`s, drawn first to last

  The frame's layers are drawn over the 3D scene, a transparent picture laid over its
  display colours. A renderer that has never been sent a `Cauldron3D.Scene.Camera` draws its
  layers alone, on black, and skips the 3D passes.

      %Cauldron3D.Scene.SpriteLayer{
        clear: {0.0, 0.0, 0.0, 1.0},
        view: {0, 0, 320, 200},
        sprites: [%Cauldron3D.Scene.Sprite{texture: ship, position: {160, 100}, origin: {8, 8}}]
      }
  """

  alias Cauldron3D.Scene.{Handle, Sprite}

  @type rect :: {number(), number(), number(), number()}
  @type t :: %__MODULE__{
          target: :frame | Handle.t(),
          clear: {number(), number(), number(), number()} | nil,
          port: rect() | nil,
          view: rect() | nil,
          sprites: [Sprite.t()]
        }

  defstruct target: :frame, clear: nil, port: nil, view: nil, sprites: []
end
