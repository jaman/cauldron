dir = Path.join(System.tmp_dir!(), "easel_web_test")
File.rm_rf!(dir)
File.mkdir_p!(dir)
File.write!(Path.join(dir, "gem.pic"), "G #00ff00\nB #0000ff\n\n....\n....\n....\n....\n")

Application.put_env(:cauldron_2d_easel_web, Cauldron2D.Easel.Web.TestEndpoint,
  secret_key_base: String.duplicate("easel", 16),
  live_view: [signing_salt: "easel-live-salt"],
  server: false,
  render_errors: [formats: [html: Cauldron2D.Easel.Web.TestErrors]]
)

{:ok, _} = Cauldron2D.Easel.Web.TestEndpoint.start_link()
Logger.configure(level: :warning)
ExUnit.start()
