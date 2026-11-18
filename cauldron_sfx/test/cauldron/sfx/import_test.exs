defmodule Cauldron.SFX.ImportTest do
  use ExUnit.Case, async: true

  alias Cauldron.Audio.Recording
  alias Cauldron.SFX
  alias Cauldron.SFX.Import

  @moduletag :tmp_dir
  @rate 22_050
  @peak -1.0
  @full_scale 32_767

  defp burst(amplitude, frames) do
    for _ <- 1..frames, into: <<>>, do: <<amplitude::little-signed-16>>
  end

  defp silence(frames) do
    for _ <- 1..frames, into: <<>>, do: <<0::little-signed-16>>
  end

  defp peak(pcm) do
    pcm |> samples() |> Enum.map(&abs/1) |> Enum.max()
  end

  defp samples(pcm), do: for(<<sample::little-signed-16 <- pcm>>, do: sample)

  defp target_peak, do: round(@full_scale * :math.pow(10, @peak / 20))

  test "cuts at silence, normalises each cut and writes one event with a variant per cut",
       %{tmp_dir: dir} do
    wav = Path.join(dir, "Woodpecker.wav")

    File.write!(
      wav,
      Import.wave(
        @rate,
        1,
        IO.iodata_to_binary([
          burst(3000, 2000),
          silence(4410),
          burst(1200, 1500),
          silence(4410),
          burst(900, 2500)
        ])
      )
    )

    bank_path = Path.join(dir, "sfx.json")
    assert {:ok, bank} = Import.add(wav, bank_path)

    assert SFX.events(bank) == ["woodpecker"]
    assert [_, _, _] = SFX.event(bank, "woodpecker").variants
    assert {:ok, read} = SFX.read(bank_path)
    assert SFX.events(read) == ["woodpecker"]

    for index <- 1..3 do
      file = Path.join(dir, "woodpecker-#{index}.wav")
      assert File.exists?(file)
      assert {:ok, %{rate: @rate, channels: 1, pcm: pcm}} = Recording.read(file)
      assert_in_delta peak(pcm), target_peak(), 200
    end

    assert %{sample: %TuningFork.Sample{}} = SFX.voice(read, "woodpecker")
  end

  test "cuts into equal parts and keeps the events already in the bank", %{tmp_dir: dir} do
    wav = Path.join(dir, "thunder.wav")
    File.write!(wav, Import.wave(@rate, 1, burst(4000, 8000)))

    bank_path = Path.join(dir, "sfx.json")

    assert :ok =
             SFX.new()
             |> SFX.put_event("click", %{variants: [%{kind: "tone", freq: 880.0}]})
             |> SFX.write(bank_path)

    assert {:ok, bank} = Import.add(wav, bank_path, slices: 4, event: "boom", gain: 0.5)

    assert SFX.events(bank) == ["boom", "click"]
    variants = SFX.event(bank, "boom").variants
    assert length(variants) == 4
    assert Enum.all?(variants, &(&1["kind"] == "sample" and &1["gain"] == 0.5))

    for index <- 1..4 do
      file = Path.join(dir, "boom-#{index}.wav")
      assert File.exists?(file)
      assert {:ok, %{pcm: pcm}} = Recording.read(file)
      assert_in_delta peak(pcm), target_peak(), 200
    end
  end

  test "the level each cut is normalised to is the option's", %{tmp_dir: dir} do
    wav = Path.join(dir, "quiet.wav")
    File.write!(wav, Import.wave(@rate, 1, burst(100, 2000)))

    assert {:ok, bank} = Import.add(wav, Path.join(dir, "sfx.json"), peak_db: -6.0)
    assert [variant] = SFX.event(bank, "quiet").variants

    assert {:ok, %{pcm: pcm}} = Recording.read(Path.join(dir, variant["file"]))
    assert_in_delta peak(pcm), round(@full_scale * :math.pow(10, -6.0 / 20)), 200
  end
end
