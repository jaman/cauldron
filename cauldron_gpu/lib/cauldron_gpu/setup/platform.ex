defmodule CauldronGPU.Setup.Platform do
  @moduledoc """
  What a platform module of `CauldronGPU.Setup` provides.

    * `c:probe/0`: each thing the build needs, found or not, looked for in the
      platform's usual places
    * `c:install/1`: installs one item: `:ok` when done, `{:wait, text}` when a person
      must finish it (an installer the platform opened), `{:error, text}` otherwise
    * `c:config/1`: the configuration (`CauldronGPU.Setup`) for the items found
  """

  @callback probe() :: [CauldronGPU.Setup.item()]
  @callback install(CauldronGPU.Setup.item()) :: :ok | {:wait, String.t()} | {:error, String.t()}
  @callback config([CauldronGPU.Setup.item()]) :: map()
end
