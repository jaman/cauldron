defmodule Mix.Tasks.Cauldron.Sfx do
  @shortdoc "Edit a game's sound effects in a terminal"

  @moduledoc """
  Opens `Cauldron.SFX.Editor.Drafter` on a sound-effect bank.

      mix cauldron.sfx priv/sfx/sfx.json
      mix cauldron.sfx --starter --out priv/sfx/sfx.json

  With no file, and no `--starter`, the editor opens on `Cauldron.SFX.starter/0`. `w` in the
  editor writes the bank back, so a first run can be a bank created from the starter.

  ## Options

    * `--out PATH` — where `w` writes, default the file given, or `sfx.json`
    * `--starter` — open the starter bank even when a file is given
  """

  use Mix.Task

  alias Cauldron.SFX

  @switches [out: :string, starter: :boolean]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(argv, strict: @switches)

    Drafter.run(Cauldron.SFX.Editor.Drafter, props: props(argv, opts))
  end

  @doc """
  The props `Cauldron.SFX.Editor.mount/1` is handed for `argv` and `opts`.

      props(["sfx.json"], out: "priv/sfx/sfx.json")
  """
  @spec props([String.t()], keyword()) :: map()
  def props(argv, opts \\ []) do
    path = List.first(argv)

    bank =
      cond do
        opts[:starter] -> SFX.starter()
        is_binary(path) -> SFX.read!(path)
        true -> SFX.starter()
      end

    %{bank: bank, out: opts[:out] || path || "sfx.json"}
  end
end
