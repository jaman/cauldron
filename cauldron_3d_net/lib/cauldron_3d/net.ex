defmodule Cauldron3D.Net do
  @moduledoc """
  3D scenes in the browser. A `Cauldron3D.Net.Scene` takes the same changes
  `CauldronGPU.submit/2` does and broadcasts them as `CauldronGPU.Stream` bytes; browsers
  joining a `Cauldron3D.Net.Channel` get the whole scene and then each tick, and draw it
  with three.js (`priv/static/cauldron3d.js`, served by `Cauldron3D.Net.Page`).

      defmodule MyGame.Web.SceneSocket do
        use Cauldron3D.Net.Socket, channel: MyGame.Web.SceneChannel
      end

      defmodule MyGame.Web.SceneChannel do
        use Cauldron3D.Net.Channel
      end

      defmodule MyGame.Web.Endpoint do
        use Phoenix.Endpoint, otp_app: :my_game
        socket "/socket", MyGame.Web.SceneSocket, websocket: true, longpoll: false
        plug Cauldron3D.Net.Page, scene: "courtyard"
      end

  The browser draws what WebGL 2 can: physically based materials, the lights, shadows
  from the directional light, fog, the sky, light styles, bloom, tone mapping, poses
  (blended and skinned on the browser's CPU) and interpolation between ticks. Requested
  ray-traced effects, upscaling and frame generation are ignored there.
  """
end
