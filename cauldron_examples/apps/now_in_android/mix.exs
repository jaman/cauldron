defmodule NowInAndroid.MixProject do
  use Mix.Project

  def project do
    [
      app: :now_in_android,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [now_in_android: [include_erts: false, strip_beams: true]],
      cauldron_native: [
        name: "Now in Android",
        id: "io.github.jaman.nowinandroid",
        orientation: :any,
        icon: "assets/icon.png",
        icon_background: "#1B6B3A",
        launch: [background: "#1B6B3A"],
        permissions: [notifications: "Tells you about new articles in the topics you follow"],
        url_schemes: ["nowinandroid"],
        background_refresh: true,
        env: %{"NIA_SERVER" => System.get_env("NIA_SERVER", "")},
        privacy: [tracking: false, collects: []],
        encryption: :exempt
      ]
    ]
  end

  def application,
    do: [extra_applications: [:logger, :inets, :ssl], mod: {NowInAndroid.Application, []}]

  defp deps do
    [
      {:cauldron_native, path: "../../../cauldron_native"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
