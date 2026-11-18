import Config

if config_target() in [:ios, :android, :macos] do
  config :cauldron_2d_native, game: Greenware.Client
end

import_config "#{config_env()}.exs"
