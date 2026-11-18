defmodule CauldronNative.MixProject do
  use Mix.Project

  @version "0.3.4"
  @source_url "https://github.com/jaman/cauldron"
  @description "An Elixir release as an iOS or Android app: the embedded runtime, the screen, touch, and the build."

  def project do
    [
      app: :cauldron_native,
      version: @version,
      description: @description,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_options: [warnings_as_errors: true],
      deps: deps(),
      name: "CauldronNative",
      source_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key], mod: {CauldronNative.Application, []}]
  end

  defp deps do
    [
      {:castore, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib c_src native guides Makefile mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url_pattern: "#{@source_url}/blob/v#{@version}/cauldron_native/%{path}#L%{line}",
      extras: ["README.md", "guides/building_apps.md", "guides/publishing.md", "CHANGELOG.md"],
      groups_for_extras: [Guides: ["guides/building_apps.md", "guides/publishing.md"]],
      groups_for_modules: [
        "On the device": [CauldronNative, CauldronNative.Native],
        Building: ~r/CauldronNative.Build/
      ]
    ]
  end
end
