import Config

start =
  cond do
    config_target() in [:ios, :android] -> {:child, GpuShowcase.Mobile}
    config_env() == :prod -> :desktop
    true -> nil
  end

config :gpu_showcase, start: start
