import Config

config :beast,
  run: 7.0,
  gravity: 55.0,
  jump: 17.0,
  lives: 3

import_config "#{config_env()}.exs"
