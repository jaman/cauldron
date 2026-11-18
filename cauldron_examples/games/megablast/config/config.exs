import Config

config :megablast,
  scroll: 5.0,
  steer: 13.0,
  shields: 3,
  addons: 2,
  lane_width: 26,
  wall_least: 2,
  wall_most: 7,
  wave_spread: 2.2,
  dive_speed: 7.0

import_config "#{config_env()}.exs"
