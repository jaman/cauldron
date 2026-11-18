defmodule Cauldron.SFXTest do
  use ExUnit.Case, async: true

  alias Cauldron.SFX
  alias Cauldron.SFX.Presets

  @moduletag :tmp_dir

  defp forward(listener) do
    receive do
      message ->
        send(listener, {:stage, message})
        forward(listener)
    end
  end

  describe "a bank" do
    test "the starter has events with variants" do
      bank = SFX.starter()

      assert SFX.events(bank) == ["boom", "click", "fire", "hurt", "jump", "pickup"]
      assert %{variants: [_, _, _]} = SFX.event(bank, "fire")
    end

    test "an event's variants are recipes" do
      bank = SFX.starter()

      assert %{"kind" => "tone", "shape" => "square"} = SFX.variant(bank, "fire", 0)

      assert %{"kind" => "layers", "parts" => [%{"at_ms" => 0}, %{"at_ms" => 10}]} =
               SFX.variant(bank, "boom", 0)
    end

    test "an unknown event makes no sound" do
      assert SFX.voice(SFX.starter(), "nothing") == nil
    end

    test "a tone becomes a voice at its own pitch and level" do
      bank =
        SFX.new(
          events: %{
            "blip" => %{
              gain: 0.5,
              pan: 0.25,
              variants: [%{kind: "tone", freq: 880.0, decay: 0.1, gain: 0.8}]
            }
          }
        )

      voice = SFX.voice(bank, "blip", variant: 0)

      assert voice.__struct__ == TuningFork.Voice
      assert_in_delta voice.freq, 880.0, 0.001
      assert_in_delta voice.gain, 0.4, 0.001
      assert_in_delta voice.pan, 0.25, 0.001
      assert TuningFork.Envelope.duration(voice.envelope) > 0.1
    end

    test "a layered event becomes a list of delayed voices" do
      assert [{0, %{shape: :noise}}, {10, tone}] = SFX.voice(SFX.starter(), "boom", variant: 0)
      assert tone.shape == :saw
    end

    test "the variant asked for is the one played" do
      bank = SFX.starter()

      assert SFX.voice(bank, "fire", variant: 0).freq != SFX.voice(bank, "fire", variant: 1).freq
    end

    test "sounds/1 is the function Cauldron.Audio takes" do
      sounds = SFX.sounds(SFX.starter())

      assert is_function(sounds, 1)
      assert %{freq: freq} = sounds.(:fire)
      assert freq in [1180.0, 1320.0, 1480.0]
      assert sounds.(:nothing) == nil
    end
  end

  describe "the file" do
    test "round trips through maps" do
      bank = SFX.starter()
      read = bank |> SFX.to_map() |> SFX.from_map()

      assert SFX.events(read) == SFX.events(bank)
      assert read.events["fire"] == bank.events["fire"]
      assert read.events["boom"] == bank.events["boom"]
    end

    test "writes a file a person can read and diff", %{tmp_dir: dir} do
      bank = SFX.starter()

      assert :ok = SFX.write(bank, dir)

      body = File.read!(Path.join(dir, "sfx.json"))
      assert body =~ ~s("fire")
      assert length(String.split(body, "\n")) > 10
      assert SFX.read!(dir).events == bank.events
      assert SFX.read!(Path.join(dir, "sfx.json")).events == bank.events
    end

    test "a recipe of an unknown kind is a tone, and an empty one is dropped" do
      bank =
        SFX.from_map(%{
          "events" => %{
            "a" => %{"variants" => [%{"kind" => "sorcery"}]},
            "b" => %{"variants" => [%{"kind" => "layers", "parts" => []}]},
            "c" => %{"gain" => "loud"}
          }
        })

      assert [%{"kind" => "tone"}] = SFX.event(bank, "a").variants
      assert SFX.event(bank, "b").variants == []
      assert %{gain: 1.0, variants: []} = SFX.event(bank, "c")
    end

    test "a file that is not a bank is nothing to play" do
      assert SFX.from_map(%{"events" => "none"}).events == %{}
    end
  end

  describe "through Cauldron.Audio" do
    test "a bank is the sounds function the audio takes" do
      listener = self()
      stand_in = spawn_link(fn -> forward(listener) end)
      on_exit(fn -> Process.exit(stand_in, :kill) end)

      {:ok, audio} =
        Cauldron.Audio.start_link(
          name: nil,
          stage: stand_in,
          sounds: Cauldron.SFX.sounds(Cauldron.SFX.starter())
        )

      assert :ok = Cauldron.Audio.play(audio, [:fire])
      assert_receive {:stage, {:"$gen_cast", {:play_pcm, pcm, _opts}}}, 500
      assert byte_size(pcm) > 0

      assert :ok = Cauldron.Audio.play(audio, [:nothing_at_all])
    end
  end

  describe "a sound as a WAV" do
    test "a tone becomes 44.1 kHz stereo audio" do
      wav = Cauldron.SFX.Audio.wav(SFX.voice(SFX.starter(), "fire", variant: 0))

      assert {:ok, pcm, 44_100, 2} = TuningFork.Wav.decode(wav)
      assert byte_size(pcm) > 0
    end

    test "a layered sound runs as long as its last part" do
      wav = Cauldron.SFX.Audio.wav(SFX.voice(SFX.starter(), "boom", variant: 0))

      assert {:ok, pcm, 44_100, 2} = TuningFork.Wav.decode(wav)
      assert TuningFork.Wav.duration(pcm, 44_100, 2) > 0.45
    end
  end

  describe "richer recipes" do
    test "every preset is a recipe a bank accepts" do
      for {name, %{recipe: recipe, space: space}} <- Presets.all() do
        bank = SFX.put_event(SFX.new(), name, %{variants: [recipe], space: space})

        assert [%{"kind" => kind}] = SFX.event(bank, name).variants
        assert kind in ["tone", "noise", "layers", "sample"]
        assert SFX.event(bank, name).space == space
      end
    end

    test "space adds early reflections" do
      bank =
        SFX.put_event(SFX.new(), "blip", %{
          space: 1.0,
          variants: [%{kind: "tone", decay: 0.1}]
        })

      assert [{0, _}, {60, _}, {110, _}, {170, _}] = SFX.voice(bank, "blip")
    end

    test "a detuned tone is two voices" do
      bank =
        SFX.put_event(SFX.new(), "wide", %{
          variants: [%{kind: "tone", freq: 440.0, detune: 12.0}]
        })

      assert [{0, low}, {0, high}] = SFX.voice(bank, "wide")
      assert low.freq < 440.0
      assert high.freq > 440.0
    end

    test "attack and release make a longer voice" do
      short = SFX.put_event(SFX.new(), "a", %{variants: [%{kind: "tone", decay: 0.1}]})

      long =
        SFX.put_event(SFX.new(), "a", %{variants: [%{kind: "tone", decay: 0.1, release: 0.5}]})

      short_duration = TuningFork.Envelope.duration(SFX.voice(short, "a").envelope)
      long_duration = TuningFork.Envelope.duration(SFX.voice(long, "a").envelope)

      assert long_duration > short_duration + 0.4
    end

    test "a sample recipe plays a recording", %{tmp_dir: dir} do
      path = Path.join(dir, "hit.wav")

      File.write!(
        path,
        TuningFork.Wav.encode(:binary.copy(<<0, 0>>, 4_410), rate: 44_100, channels: 1)
      )

      bank =
        SFX.put_event(SFX.new(), "hit", %{
          variants: [%{kind: "sample", file: path, gain: 0.8}]
        })

      voice = SFX.voice(bank, "hit")
      assert voice.sample != nil
    end

    test "a sample's file is found beside the bank it is written in", %{tmp_dir: dir} do
      File.write!(
        Path.join(dir, "hit.wav"),
        TuningFork.Wav.encode(:binary.copy(<<0, 0>>, 4_410), rate: 44_100, channels: 1)
      )

      bank =
        SFX.put_event(SFX.new(), "hit", %{
          variants: [%{kind: "sample", file: "hit.wav"}]
        })

      :ok = SFX.write(bank, dir)

      read = SFX.read!(dir)
      file = SFX.variant(read, "hit", 0)["file"]

      assert Path.type(file) == :absolute
      assert File.exists?(file)
      assert SFX.voice(read, "hit").sample != nil
    end

    test "a sample with neither a file nor a sound makes nothing" do
      bank = SFX.put_event(SFX.new(), "mute", %{variants: [%{kind: "sample"}]})

      assert SFX.event(bank, "mute").variants == []
      assert SFX.voice(bank, "mute") == nil
    end
  end

  describe "changing a bank" do
    test "put, update and remove" do
      bank =
        SFX.new()
        |> SFX.put_event("blip", %{variants: [%{freq: 660.0}]})
        |> SFX.update_event("blip", fn event -> %{event | gain: 0.5} end)

      assert %{gain: 0.5, variants: [%{"freq" => 660.0, "kind" => "tone"}]} =
               SFX.event(bank, "blip")

      assert SFX.events(SFX.remove_event(bank, "blip")) == []
    end

    test "updating an event that is not there changes nothing" do
      bank = SFX.starter()

      assert SFX.update_event(bank, "nothing", & &1) == bank
      assert SFX.variant(bank, "nothing", 0) == nil
    end
  end
end
