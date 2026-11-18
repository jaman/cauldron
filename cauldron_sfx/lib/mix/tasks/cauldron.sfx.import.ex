defmodule Mix.Tasks.Cauldron.Sfx.Import do
  @shortdoc "Turns recordings into a bank's sound effects"

  @moduledoc """
  Adds the sounds of a recording to a sound-effect bank: cuts it at silence
  (or into equal parts), normalises each cut, writes them beside the bank
  and lists them as the variants of one event.

      mix cauldron.sfx.import woodpecker.wav --bank priv/sfx/sfx.json
      mix cauldron.sfx.import thunder.wav --bank priv/sfx/thunder --event boom --slices 3

  The bank is created when it does not exist, so a game can start from
  recordings and then open the bank with `mix cauldron.sfx`.

  ## Options

    * `--bank PATH` — the bank, a directory or a `sfx.json` file. Default
      `priv/sfx/sfx.json`
    * `--event NAME` — the event the variants go on. Default the WAV's file
      name
    * `--slices N` — cut into `N` equal parts instead of at silence
    * `--silence-db DB` — what counts as silence. Default `-50`
    * `--gap-ms MS` — how long a silence cuts. Default `120`
    * `--pad-ms MS` — how much of the silence either side of a cut to keep.
      Default `10`
    * `--peak-db DB` — the level each cut is normalised to. Default `-1`
    * `--gain GAIN` — the variants' gain in the bank. Default `0.8`
  """

  use Mix.Task

  alias Cauldron.SFX
  alias Cauldron.SFX.Import

  @switches [
    bank: :string,
    event: :string,
    slices: :integer,
    silence_db: :float,
    gap_ms: :integer,
    pad_ms: :integer,
    peak_db: :float,
    gain: :float
  ]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, argv} = OptionParser.parse!(argv, strict: @switches)
    wav = List.first(argv) || Mix.raise("Give the WAV to import: mix cauldron.sfx.import RECORDING.wav")
    bank_path = opts[:bank] || "priv/sfx/sfx.json"
    import = Keyword.drop(opts, [:bank])

    case Import.add(wav, bank_path, import) do
      {:ok, bank} ->
        name = import[:event] || wav |> Path.basename(Path.extname(wav)) |> String.downcase()
        variants = bank |> SFX.event(name) |> Map.fetch!(:variants) |> length()

        Mix.shell().info(
          "#{variants} variants of #{name} added to #{SFX.manifest(bank_path)}"
        )

      {:error, reason} ->
        Mix.raise("cannot import #{wav}: #{inspect(reason)}")
    end
  end
end
