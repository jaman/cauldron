import Config

config :now_in_android_server,
  port: String.to_integer(System.get_env("PORT", "4180")),
  publish_every: String.to_integer(System.get_env("PUBLISH_EVERY", "120")),
  data: System.get_env("NIA_DATA", Path.expand("../../now_in_android/priv/data", __DIR__))
