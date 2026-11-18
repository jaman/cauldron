defmodule Cauldron.Launch do
  @moduledoc """
  How a run's settings are found: one order, the same for every setting.

    1. `:given` — the value given explicitly: a function option, a mount prop, a
       command-line flag
    2. `:saved` — the game's saved launch values, a map read by `:key` (the launcher's
       file, as the terminal client of `cauldron_2d_drafter` loads it)
    3. `:env` — an environment variable
    4. `:config` — application config
    5. `:default`

  The first layer with a value gives it. `nil` is "not given" at every layer, so `false`
  given explicitly wins over everything after it.

  `:env` is `{name, parse}`: the variable's text goes through `parse`, which answers the
  value or `nil` for text it does not accept, so a mistyped variable falls through to
  the next layer. `{name}` takes the text as it is. `:config` is `{app, key}`, or
  `{app, key, check}` with `check` answering the value or `nil` likewise.

      Cauldron.Launch.value(
        given: Keyword.get(opts, :mode),
        env: {"CAULDRON_AUDIO", &MyGame.parse_mode/1},
        config: {:my_game, :audio},
        default: :live
      )
  """

  @type option ::
          {:given, term()}
          | {:saved, map() | nil}
          | {:key, term()}
          | {:env, {String.t(), (String.t() -> term())} | {String.t()}}
          | {:config, {atom(), atom()} | {atom(), atom(), (term() -> term())}}
          | {:default, term()}

  @doc "The setting's value: the first of the layers in the module documentation that has one."
  @spec value([option()]) :: term()
  def value(opts) do
    layers = [
      fn -> Keyword.get(opts, :given) end,
      fn -> saved(Keyword.get(opts, :saved), Keyword.get(opts, :key)) end,
      fn -> env(Keyword.get(opts, :env)) end,
      fn -> config(Keyword.get(opts, :config)) end
    ]

    Enum.reduce_while(layers, Keyword.get(opts, :default), fn layer, default ->
      case layer.() do
        nil -> {:cont, default}
        found -> {:halt, found}
      end
    end)
  end

  defp saved(nil, _key), do: nil
  defp saved(_saved, nil), do: nil
  defp saved(saved, key), do: Map.get(saved, key)

  defp env(nil), do: nil
  defp env({name}), do: System.get_env(name)

  defp env({name, parse}) do
    case System.get_env(name) do
      nil -> nil
      text -> parse.(text)
    end
  end

  defp config(nil), do: nil
  defp config({app, key}), do: Application.get_env(app, key)
  defp config({app, key, check}), do: app |> Application.get_env(key) |> checked(check)

  defp checked(nil, _check), do: nil
  defp checked(value, check), do: check.(value)
end
