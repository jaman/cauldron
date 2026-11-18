Application.put_env(:cauldron_sfx_web, Cauldron.SFX.Web.TestEndpoint,
  secret_key_base: String.duplicate("sfx", 32),
  live_view: [signing_salt: "sfx-live-salt"],
  server: false,
  render_errors: [formats: [html: Cauldron.SFX.Web.TestErrors]]
)

{:ok, _} = Cauldron.SFX.Web.TestEndpoint.start_link()
Logger.configure(level: :warning)
ExUnit.start()
