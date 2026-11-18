import Config

if config_target() in [:ios, :tvos, :macos, :android] do
  config :cauldron_2d_native, game: Beast.Client
end

import_config "#{config_env()}.exs"
