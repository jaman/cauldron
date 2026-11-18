defmodule CauldronGPUWindows.MixProject do
  use Mix.Project

  # The smallest project that can draw with cauldron_gpu: one path dependency, so a
  # machine with a card can build and test the renderer without the rest of the family.
  def project do
    [
      app: :cauldron_gpu_windows,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: false,
      deps: [{:cauldron_gpu, path: "../../cauldron_gpu"}]
    ]
  end

  def application do
    [extra_applications: [:crypto]]
  end
end
