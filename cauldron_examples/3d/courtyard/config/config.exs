import Config

if config_target() in [:ios, :android] do
  config :cauldron_2d_native, game: Courtyard.Client
end
