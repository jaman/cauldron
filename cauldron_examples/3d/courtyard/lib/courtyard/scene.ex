defmodule Courtyard.Scene do
  @moduledoc """
  What a scene the courtyard can show provides (`Courtyard.Scenes` lists them):

    * `name/0` — what the status bar calls it
    * `start/0` — where the character first stands in it, `%{position, yaw, pitch}`: its
      feet, the way it and the camera face, and the camera's pitch
    * `ground/0` — its walk grid (`Cauldron3D.WalkGrid`), or `{:error, reason}` when it has
      not been downloaded
    * `upload/2` — puts it in a `Cauldron3D.Scene.Target`, answering `%{changes, handles, data}`:
      the changes that show it (instances, lights, the environment), every handle
      uploaded (released when the scene is left) and whatever `frame/2` needs; or
      `{:error, {:missing, command}}` when it has not been downloaded
    * `frame/2` — the changes for one frame of `view` (`Courtyard.Game.view/2`): what
      moves; an instance or light it stops giving is removed

  `upload/2` reads files and uploads, so it can take seconds; `Courtyard.Loader` runs it
  away from the drawing. `ground/0` can take seconds the first time and is quick after
  (`Courtyard.Grounds`). Everything else is quick.
  """

  @type placed :: %{
          changes: [Cauldron3D.Scene.Stream.change()],
          handles: [Cauldron3D.Scene.Handle.t()],
          data: term()
        }
  @type pose :: %{position: {float(), float(), float()}, yaw: float(), pitch: float()}

  @callback name() :: String.t()
  @callback start() :: pose()
  @callback ground() :: {:ok, Cauldron3D.WalkGrid.t()} | {:error, term()}
  @callback upload(Cauldron3D.Scene.Target.t(), keyword()) :: {:ok, placed()} | {:error, term()}
  @callback frame(placed(), map()) :: [Cauldron3D.Scene.Stream.change()]
end
