defmodule Cauldron2D.AudioTest do
  use ExUnit.Case, async: false

  alias Cauldron2D.Audio
  alias Cauldron2D.Audio.{Music, Rendered}
  alias TuningFork.{Envelope, Pattern, Voice}
  alias TuningFork.Sink.Buffer

  setup do
    home = Path.join(System.tmp_dir!(), "cauldron_audio_#{System.unique_integer([:positive])}")
    previous = System.get_env("XDG_STATE_HOME")
    System.put_env("XDG_STATE_HOME", home)

    listener = self()
    stand_in = spawn(fn -> forward(listener) end)

    on_exit(fn ->
      Process.exit(stand_in, :kill)
      File.rm_rf(home)
      for key <- ~w(a b c), do: :persistent_term.erase({{Cauldron2D.Audio, :bed}, key})

      if previous,
        do: System.put_env("XDG_STATE_HOME", previous),
        else: System.delete_env("XDG_STATE_HOME")
    end)

    {:ok, stage: stand_in}
  end

  defp forward(listener) do
    receive do
      message ->
        send(listener, {:stage, message})
        forward(listener)
    end
  end

  defp start(stage, opts) do
    {:ok, audio} = Audio.start_link([name: nil, stage: stage] ++ opts)
    audio
  end

  defp beep(gain \\ 0.5) do
    Voice.new(shape: :sine, freq: 440.0, envelope: Envelope.hit(0.05), gain: gain)
  end

  defp tone(frames), do: :binary.copy(<<1000::16-signed-little>>, frames)

  defp sides(pcm) do
    for <<left::16-signed-little, right::16-signed-little <- pcm>>, reduce: {0, 0} do
      {l, r} -> {max(l, abs(left)), max(r, abs(right))}
    end
  end

  describe "events becoming sounds" do
    test "an event the table knows reaches the stage, rendered once for every stage on the node",
         %{stage: stage} do
      audio =
        start(stage,
          sounds: fn :ping ->
            Voice.new(shape: :sine, freq: 441.5, envelope: Envelope.hit(0.05), gain: 0.5)
          end
        )

      before = Rendered.count()
      Audio.play(audio, [:ping])
      assert_receive {:stage, {:"$gen_cast", {:play_pcm, pcm}}}, 500
      assert byte_size(pcm) > 44_100 * 0.05 * 4 and byte_size(pcm) < 44_100 * 0.06 * 4
      Audio.play(audio, [:ping])
      assert_receive {:stage, {:"$gen_cast", {:play_pcm, ^pcm}}}, 500
      assert Rendered.count() == before + 1
    end

    test "an event the table has no sound for is silent, not an error", %{stage: stage} do
      audio = start(stage, sounds: fn _event -> nil end)

      assert Audio.play(audio, [:whatever]) == :ok
      refute_receive {:stage, {:"$gen_cast", {:play_pcm, _pcm}}}, 200
    end

    test "an event that is not a sound, a result or a message a game emits beside its sounds, is passed over",
         %{stage: stage} do
      audio = start(stage, sounds: fn :ping -> beep(1.0) end)

      assert Audio.play(audio, [
               {:result, %{name: "alice"}},
               {:told, "alice", "hit a wall"},
               :ping
             ]) == :ok

      assert_receive {:stage, {:"$gen_cast", {:play_pcm, _pcm}}}, 500
      assert Process.alive?(audio)
    end

    test "the effects level scales what is sent", %{stage: stage} do
      audio = start(stage, sounds: fn :ping -> beep(1.0) end)
      Audio.levels(audio, 0.5, 0.3)
      Audio.play(audio, [:ping])

      assert_receive {:stage, {:"$gen_cast", {:play_pcm, half}}}, 500
      Audio.levels(audio, 1.0, 0.3)
      Audio.play(audio, [:ping])
      assert_receive {:stage, {:"$gen_cast", {:play_pcm, full}}}, 500
      assert_in_delta TuningFork.Mixer.peak(half) / TuningFork.Mixer.peak(full), 0.5, 0.01
    end

    test "a run arrives as several sounds rather than one chord", %{stage: stage} do
      run = [{0, beep()}, {10, beep()}, {20, beep()}]
      audio = start(stage, sounds: fn :chime -> run end)
      Audio.play(audio, [:chime])

      for _ <- 1..3, do: assert_receive({:stage, {:"$gen_cast", {:play_pcm, _}}}, 1_000)
    end

    test "several events in a frame all sound", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> beep() end)
      Audio.play(audio, [:one, :two, :three])

      for _ <- 1..3, do: assert_receive({:stage, {:"$gen_cast", {:play_pcm, _}}}, 500)
    end
  end

  describe "placed events" do
    test "with no listener a placed event plays at full level, centred", %{stage: stage} do
      audio = start(stage, sounds: fn :bang -> beep(1.0) end, sfx: 1.0)
      Audio.play(audio, [{:bang, {50.0, 50.0}}])

      assert_receive {:stage, {:"$gen_cast", {:play_pcm, pcm}}}, 500
      {left, right} = sides(pcm)
      assert_in_delta left, right, 2
      assert left > 20_000
    end

    test "a distant event is quieter and panned to its side", %{stage: stage} do
      audio = start(stage, sounds: fn :bang -> beep(1.0) end, sfx: 1.0, earshot: 20.0)
      Audio.listener(audio, {10.0, 10.0})
      Audio.play(audio, [{:bang, {20.0, 10.0}}])

      assert_receive {:stage, {:"$gen_cast", {:play_pcm, pcm}}}, 500
      {left, right} = sides(pcm)
      assert right > left * 1.5
      assert right < 20_000 and right > 8_000
    end

    test "an event beyond earshot is not heard", %{stage: stage} do
      audio = start(stage, sounds: fn :bang -> beep(1.0) end, earshot: 20.0)
      Audio.listener(audio, {10.0, 10.0})
      Audio.play(audio, [{:bang, {50.0, 10.0}}])

      refute_receive {:stage, {:"$gen_cast", {:play_pcm, _}}}, 200
    end

    test "an event within a tile is at full level", %{stage: stage} do
      audio = start(stage, sounds: fn :bang -> beep(1.0) end, sfx: 1.0, earshot: 20.0)
      Audio.listener(audio, {10.0, 10.0})
      Audio.play(audio, [{:bang, {10.5, 10.0}}])

      assert_receive {:stage, {:"$gen_cast", {:play_pcm, pcm}}}, 500
      {left, _right} = sides(pcm)
      assert left > 20_000
    end
  end

  describe "the bed" do
    test "is rendered, kept, and handed to the stage", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Audio.bed(audio, "a", fn -> tone(2_000) end)

      assert_receive {:stage, {:"$gen_cast", {:bed, pcm}}}, 5_000
      assert byte_size(pcm) == 4_000
    end

    test "asking for one already made does not render it again", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Audio.bed(audio, "b", fn -> tone(1_000) end)
      assert_receive {:stage, {:"$gen_cast", {:bed, _}}}, 5_000

      Audio.bed(audio, "b", fn -> flunk("rendered a second time") end)
      assert_receive {:stage, {:"$gen_cast", {:bed, _}}}, 500
    end

    test "a bed finishing after the game moved on is dropped rather than played late", %{
      stage: stage
    } do
      audio = start(stage, sounds: fn _ -> nil end)

      Audio.bed(audio, "a", fn ->
        Process.sleep(300)
        tone(500)
      end)

      Audio.bed(audio, "b", fn -> tone(700) end)

      assert_receive {:stage, {:"$gen_cast", {:bed, pcm}}}, 5_000
      assert byte_size(pcm) == 1_400, "the stratum left behind arrived anyway"
      refute_receive {:stage, {:"$gen_cast", {:bed, _}}}, 600
    end

    test "the music level reaches the stage rather than re-rendering", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      assert_receive {:stage, {:"$gen_cast", {:bed_gain, initial}}}, 500
      assert_in_delta initial, 0.35, 0.001

      Audio.levels(audio, 0.8, 0.25)

      assert_receive {:stage, {:"$gen_cast", {:bed_gain, gain}}}, 500
      assert_in_delta gain, 0.25, 0.001
    end

    test "playing reports what was last asked for", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Audio.bed(audio, "c", fn -> tone(100) end)

      assert Audio.playing(audio) == "c"
    end
  end

  describe "stopping" do
    defp silent_audio do
      {:ok, tape} = Buffer.start_link()

      Audio.start_link(
        name: nil,
        sink: {Buffer, into: tape},
        sounds: fn _ -> nil end
      )
    end

    test "stopping the audio stops the stage it started, so nothing keeps sounding" do
      {:ok, audio} = silent_audio()
      stage = Audio.stage(audio)
      assert is_pid(stage) and Process.alive?(stage)

      :ok = GenServer.stop(audio)
      refute Process.alive?(stage)
    end

    test "the audio and its stage go when the process that started them exits, normally or not" do
      owner = self()

      for reason <- [:normal, :shutdown] do
        pid =
          spawn(fn ->
            {:ok, audio} = silent_audio()
            send(owner, {:started, audio, Audio.stage(audio)})
            receive do: (:go -> exit(reason))
          end)

        assert_receive {:started, audio, stage}, 1_000
        send(pid, :go)

        assert :ok ==
                 wait_until(fn -> not Process.alive?(audio) and not Process.alive?(stage) end)
      end
    end

    test "a stage handed in is left running", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      :ok = GenServer.stop(audio)
      assert Process.alive?(stage)
    end

    defp wait_until(check, tries \\ 50) do
      cond do
        check.() -> :ok
        tries == 0 -> :timeout
        true -> Process.sleep(20) && wait_until(check, tries - 1)
      end
    end
  end

  describe "muting" do
    test "silences the bed and restores it", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Audio.bed(audio, "a", fn -> tone(500) end)
      assert_receive {:stage, {:"$gen_cast", {:bed, _}}}, 5_000

      Audio.mute(audio, true)
      assert_receive {:stage, {:"$gen_cast", {:mute, true}}}, 500
      assert_receive {:stage, {:"$gen_cast", {:bed, <<>>}}}, 500

      Audio.mute(audio, false)
      assert_receive {:stage, {:"$gen_cast", {:mute, false}}}, 500
      assert_receive {:stage, {:"$gen_cast", {:bed, pcm}}}, 500
      assert byte_size(pcm) == 1_000
    end
  end

  describe "a piece played live" do
    defp score, do: TuningFork.Score.new(bpm: 120, beats: 4)

    defp play_live(stage) do
      audio = start(stage, sounds: fn _ -> nil end, mode: :live)
      Audio.play_piece(audio, "a", score(), mode: :live)
      assert_receive {:stage, {:"$gen_cast", {:start_score, _score, _opts}}}, 500
      audio
    end

    test "reaches the stage as a score rather than as a render", %{stage: stage} do
      play_live(stage)

      refute_receive {:stage, {:"$gen_cast", {:bed, _pcm}}}, 200
    end

    test "clearing stops the score, not only the bed", %{stage: stage} do
      audio = play_live(stage)
      Audio.clear_bed(audio)

      assert_receive {:stage, {:"$gen_cast", {:bed, <<>>}}}, 500
      assert_receive {:stage, {:"$gen_cast", :stop_score}}, 500
    end

    test "resuming performs it again rather than finding no render and staying silent", %{
      stage: stage
    } do
      audio = play_live(stage)
      Audio.clear_bed(audio)
      Audio.resume_bed(audio)

      assert_receive {:stage, {:"$gen_cast", {:start_score, _score, _opts}}}, 500
    end

    test "muting and unmuting leaves it playing where it reached", %{stage: stage} do
      audio = play_live(stage)

      Audio.mute(audio, true)
      assert_receive {:stage, {:"$gen_cast", {:mute, true}}}, 500

      Audio.mute(audio, false)
      assert_receive {:stage, {:"$gen_cast", {:mute, false}}}, 500

      refute_receive {:stage, {:"$gen_cast", {:bed, <<>>}}}, 200
      refute_receive {:stage, {:"$gen_cast", {:start_score, _score, _opts}}}, 200
    end
  end

  describe "a render that fails" do
    test "is logged rather than vanishing, and nothing else fails with it", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)

      logged =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Audio.bed(audio, "a", fn -> raise "no such instrument" end) == :ok
          Process.sleep(300)
        end)

      assert logged =~ "no such instrument"
      assert logged =~ "will never play"
      refute_receive {:stage, {:"$gen_cast", {:bed, _pcm}}}, 200
      assert Audio.play(audio, [:anything]) == :ok
    end
  end

  describe "music in sections and layers" do
    defp piece do
      %{
        bpm: 120,
        beats_per_bar: 4,
        layers: [:drums, :pad],
        sections: %{
          calm: %{drums: {:pcm, tone(100)}, pad: fn -> tone(200) end},
          tense: %{drums: {:pcm, tone(300)}, pad: {:pcm, tone(400)}}
        }
      }
    end

    defp layers_cast do
      receive do
        {:stage, {:"$gen_cast", {:layers, layers, opts}}} -> {layers, opts}
      after
        10_000 -> flunk("no layer set reached the stage")
      end
    end

    test "a cue starts the section once its layers are rendered", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "p", piece())
      Music.cue(audio, %{piece: "p", section: :calm, layers: %{drums: 1.0, pad: 0.5}})

      {layers, opts} = layers_cast()
      assert byte_size(layers.drums) == 200
      assert byte_size(layers.pad) == 400
      assert opts[:gains] == %{drums: 1.0, pad: 0.5}
      refute Keyword.has_key?(opts, :at)
      assert Music.current(audio) == {"p", :calm}
    end

    test "the cued section is rendered first, a few stems at a time", %{stage: stage} do
      {:ok, order} = Agent.start_link(fn -> [] end)

      slow = fn name ->
        fn ->
          Agent.update(order, &[name | &1])
          Process.sleep(30)
          tone(100)
        end
      end

      sections =
        for section <- [:a, :b, :c, :d], into: %{} do
          {section, %{drums: slow.({section, :drums}), pad: slow.({section, :pad})}}
        end

      audio = start(stage, sounds: fn _ -> nil end)

      Music.piece(audio, "p", %{
        bpm: 120,
        beats_per_bar: 4,
        layers: [:drums, :pad],
        sections: sections
      })

      Music.cue(audio, %{piece: "p", section: :d})
      {_layers, _opts} = layers_cast()

      started = order |> Agent.get(& &1) |> Enum.reverse()

      assert Enum.sort(Enum.take(started, 4)) |> Enum.filter(&match?({:d, _}, &1)) == [
               {:d, :drums},
               {:d, :pad}
             ],
             inspect(started)

      assert length(started) <= 6, "stems were not rendered a few at a time: #{inspect(started)}"
    end

    test "changing the section waits for a bar and cross-fades", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "p", piece())
      Music.cue(audio, %{piece: "p", section: :calm})
      layers_cast()

      Music.cue(audio, %{piece: "p", section: :tense})
      {layers, opts} = layers_cast()
      assert byte_size(layers.drums) == 600
      assert opts[:at] == {:bar, 88_200}
      assert opts[:fade_ms] > 0
    end

    test "changing only the gains changes them at once", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "p", piece())
      Music.cue(audio, %{piece: "p", section: :calm})
      layers_cast()

      Music.cue(audio, %{piece: "p", section: :calm, layers: %{pad: 0.1}})
      assert_receive {:stage, {:"$gen_cast", {:layer_gains, %{pad: 0.1}}}}, 500
      refute_receive {:stage, {:"$gen_cast", {:layers, _, _}}}, 200
    end

    test "stopping clears the bed", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "p", piece())
      Music.cue(audio, %{piece: "p", section: :calm})
      layers_cast()
      Music.stop(audio)
      assert_receive {:stage, {:"$gen_cast", {:bed, <<>>}}}, 500
      assert Music.current(audio) == nil
    end
  end

  describe "music played live from Strudel" do
    test "prefetching a piece's sounds walks every chain and returns at once" do
      assert :ok == Music.prefetch([{"one", strudel_piece()}])

      assert :ok ==
               Music.prefetch([
                 {"broken", %{strudel_piece() | sections: %{calm: %{drums: ~s|s(|}}}}
               ])
    end

    defp strudel_piece do
      %{
        bpm: 120,
        beats_per_bar: 4,
        layers: [:drums, :pad],
        sections: %{
          calm: %{drums: ~s|s("bd ~ ~ ~")|, pad: ~s|note("<c3 e3>").s("triangle")|},
          tense: %{drums: ~s|s("bd*4")|, pad: ~s|note("<c3 e3>*2").s("square")|}
        }
      }
    end

    defp pattern_cast do
      receive do
        {:stage, {:"$gen_cast", {:start_pattern, pattern, opts}}} -> {:start, pattern, opts}
        {:stage, {:"$gen_cast", {:update_pattern, pattern, opts}}} -> {:update, pattern, opts}
        {:stage, {:"$gen_cast", {:pattern_gain, gain}}} -> {:gain, gain}
        {:stage, {:"$gen_cast", :stop_pattern}} -> :stop
      after
        2_000 -> flunk("no pattern reached the stage")
      end
    end

    defp gains_of(pattern) do
      pattern
      |> Pattern.query({0, 1})
      |> Enum.map(fn %{value: value} -> if(is_map(value), do: Map.get(value, :velocity)) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()
    end

    test "static music renders the first cued section once, loops it as a bed, and ignores every cue after",
         %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end, static_music: true)
      Music.piece(audio, "s", Map.put(strudel_piece(), :loop, 2))
      Music.cue(audio, %{piece: "s", section: :calm, layers: %{drums: 1.0, pad: 0.5}})

      assert_receive {:stage, {:"$gen_cast", {:layers, %{static: pcm}, opts}}}, 30_000
      assert byte_size(pcm) == 2 * 2 * 44_100 * 4
      assert opts[:gains] == %{}
      assert Music.current(audio) == {"s", :calm}

      Music.cue(audio, %{piece: "s", section: :tense, layers: %{drums: 1.0, pad: 1.0}})
      refute_receive {:stage, {:"$gen_cast", {:layers, _, _}}}, 300
      refute_receive {:stage, {:"$gen_cast", {:start_pattern, _, _}}}, 100
      assert Music.current(audio) == {"s", :calm}

      again = start(stage, sounds: fn _ -> nil end, static_music: true)
      Music.piece(again, "s", Map.put(strudel_piece(), :loop, 2))
      Music.cue(again, %{piece: "s", section: :calm})
      assert_receive {:stage, {:"$gen_cast", {:layers, %{static: ^pcm}, _}}}, 2_000
    end

    test "a cue starts the section's chains as one pattern at the piece's speed", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "s", strudel_piece())
      Music.cue(audio, %{piece: "s", section: :calm, layers: %{drums: 1.0, pad: 0.5}})

      assert {:gain, _} = pattern_cast()
      assert {:start, %TuningFork.Pattern{} = pattern, opts} = pattern_cast()
      assert opts[:cps] == 0.5
      assert Music.current(audio) == {"s", :calm}
      assert Pattern.query(pattern, {0, 1}) != []
    end

    test "a chain of any length is a chain, a score of many bars included", %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end)
      bars = Enum.map_join(1..400, " ", fn _ -> "[c3 e3 g3 c4 e4 g4 c5 e5]" end)
      long = ~s|note("<#{bars}>").s("triangle")|
      assert byte_size(long) > 8_192

      Music.piece(audio, "s", %{
        strudel_piece()
        | sections: %{calm: %{drums: ~s|s("bd*4")|, pad: long}}
      })

      Music.cue(audio, %{piece: "s", section: :calm, layers: %{drums: 1.0, pad: 0.5}})

      assert {:gain, _} = pattern_cast()
      assert {:start, %TuningFork.Pattern{} = pattern, _opts} = pattern_cast()
      assert length(Pattern.query(pattern, {0, 1})) == 12
    end

    test "changing the section swaps the pattern at the cycle line; changing gains at once", %{
      stage: stage
    } do
      audio = start(stage, sounds: fn _ -> nil end)
      Music.piece(audio, "s", strudel_piece())
      Music.cue(audio, %{piece: "s", section: :calm, layers: %{drums: 1.0, pad: 1.0}})
      assert {:gain, _} = pattern_cast()
      assert {:start, first, _} = pattern_cast()

      Music.cue(audio, %{piece: "s", section: :tense, layers: %{drums: 1.0, pad: 1.0}})
      assert {:update, second, opts} = pattern_cast()
      assert opts[:at] == :cycle
      assert Music.current(audio) == {"s", :tense}
      refute gains_of(first) == [] and gains_of(second) == []

      Music.cue(audio, %{piece: "s", section: :tense, layers: %{drums: 0.2, pad: 1.0}})
      assert {:update, quieter, opts} = pattern_cast()
      assert opts[:at] == :now
      assert gains_of(quieter) != gains_of(second)
    end

    test "the music level is the pattern's master gain, set at the start and on every change, and stop silences it",
         %{stage: stage} do
      audio = start(stage, sounds: fn _ -> nil end, music: 0.6)
      Music.piece(audio, "s", strudel_piece())
      Music.cue(audio, %{piece: "s", section: :calm, layers: %{drums: 1.0, pad: 1.0}})
      assert {:gain, 0.6} = pattern_cast()
      assert {:start, _pattern, _} = pattern_cast()

      Audio.levels(audio, 1.0, 0.0)
      assert {:gain, +0.0} = pattern_cast()

      Music.stop(audio)
      assert :stop = pattern_cast()
      assert Music.current(audio) == nil
    end
  end

  describe "a machine that cannot make sound" do
    test "every call is a no-op rather than a crash" do
      {:ok, audio} = Audio.start_link(name: nil, sink: TuningFork.Sink.Silent)
      refute Audio.on?(audio)
      assert Audio.play(audio, [:anything]) == :ok
      assert Audio.levels(audio, 0.5, 0.5) == :ok
      assert Audio.mute(audio, true) == :ok
      assert Audio.clear_bed(audio) == :ok
      assert Audio.resume_bed(audio) == :ok
      assert Audio.bed(audio, "a", fn -> flunk("rendered with nowhere to play it") end) == :ok
      assert Music.cue(audio, %{piece: "p", section: :calm}) == :ok
    end

    test "the default instance answers when nothing was started" do
      refute Audio.on?()
      assert Audio.play([:anything]) == :ok
      assert Audio.playing() == nil
      assert Music.current() == nil
    end
  end
end
