defmodule Catalog.MixProject do
  use Mix.Project

  def project do
    [
      app: :catalog,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [catalog: [include_erts: false, strip_beams: true]],
      cauldron_native: [
        name: "Catalog",
        id: "io.github.jaman.catalog",
        orientation: :any,
        permissions: [
          camera: "Shows the camera's preview and takes photos and videos",
          microphone: "Records sound and the sound of videos",
          photos: "Shows the photo library's permission prompt",
          location: "Shows where you are on the map",
          notifications: "Shows the notifications you schedule"
        ],
        background_audio: true,
        icon: "assets/icon.png",
        icon_background: "#3B2F5C",
        launch: [background: "#3B2F5C"],
        maps: [android_key: {:env, "CATALOG_MAPS_KEY"}],
        privacy: [tracking: false, collects: []],
        encryption: :exempt
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:cauldron_native, path: "../../../cauldron_native"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
