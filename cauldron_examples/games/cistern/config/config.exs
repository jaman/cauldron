import Config

config :cistern, Cistern.Web.Endpoint,
  http: [port: 4300],
  secret_key_base: String.duplicate("cistern", 10),
  server: false,
  pubsub_server: Cistern.PubSub
