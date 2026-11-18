defmodule Cauldron.LaunchTest do
  use ExUnit.Case, async: false

  alias Cauldron.Launch

  @var "CAULDRON_LAUNCH_TEST"

  setup do
    Application.put_env(:cauldron_core, :launch_test, :config)

    on_exit(fn ->
      System.delete_env(@var)
      Application.delete_env(:cauldron_core, :launch_test)
    end)
  end

  defp layers(given, saved) do
    [
      given: given,
      saved: saved,
      key: :setting,
      env: {@var, &parse/1},
      config: {:cauldron_core, :launch_test},
      default: :default
    ]
  end

  defp parse("env"), do: :env
  defp parse(_text), do: nil

  test "the explicit value, then saved, then the environment, then config, then the default" do
    System.put_env(@var, "env")
    assert Launch.value(layers(:given, %{setting: :saved})) == :given
    assert Launch.value(layers(false, %{setting: :saved})) == false
    assert Launch.value(layers(nil, %{setting: :saved})) == :saved
    assert Launch.value(layers(nil, %{})) == :env

    System.put_env(@var, "mistyped")
    assert Launch.value(layers(nil, %{})) == :config

    Application.delete_env(:cauldron_core, :launch_test)
    assert Launch.value(layers(nil, nil)) == :default
  end
end
