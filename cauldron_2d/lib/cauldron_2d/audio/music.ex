defmodule Cauldron2D.Audio.Music do
  @moduledoc """
  Music in sections and layers, switched on bar boundaries and mixed per listener.

  A game declares a piece — its tempo, its layer names, and for each section what every
  layer plays — and then cues it from its own state. The names are the game's; nothing
  here knows what a section or a layer is for.

      Cauldron2D.Audio.Music.piece(audio, "orbit", %{
        bpm: 112,
        beats_per_bar: 4,
        layers: [:drums, :bass, :pad],
        sections: %{
          calm: %{drums: calm_drums, bass: calm_bass, pad: pad},
          tense: %{drums: tense_drums, bass: tense_bass, pad: pad}
        },
        fingerprint: "3"
      })

      Cauldron2D.Audio.Music.cue(audio, %{piece: "orbit", section: :tense, layers: %{drums: 1.0, bass: 1.0, pad: 0.4}})

  What a layer plays is either performed live or rendered once:

    * a Strudel chain as a string — `~s|s("bd*4").bank("RolandTR909")|` — is performed
      live on the listener's stage. A section's chains play as one `stack`, each layer's
      level applied to its chain as its `velocity` — multiplying whatever `gain` the
      chain sets, never replacing it — and the music level to the whole, sounding notes
      included, at the piece's `bpm / beats_per_bar / 60` cycles per second. Nothing is rendered ahead, so a cue takes effect at once:
      a new section at the next cycle line, new gains on the next block. Every layer of
      a section must be a chain for the section to play this way
    * a `TuningFork.Score`, a zero-arity function returning PCM, or PCM as `{:pcm, binary}` is rendered once,
      two stems at a time in tasks, and kept through `TuningFork.Cache` in the game's
      music directory under
      `piece/section/layer` and a fingerprint of the piece's own, what was written, the
      tempo, the rate and channels — so a changed layer is rendered again. A cue moves its section to the front of
      what is still to render and takes effect when the section is ready — at the next
      bar boundary of the playing section, with a cross-fade; new gains at once

  A piece of long recordings — whole tracks rather than loops — sets `render: :on_cue`:
  then a section is rendered only when it is first cued, and once another section of the
  piece plays, the one before leaves memory (its render stays in the cache, so cueing it
  again reads it back).

  The music level from `Cauldron2D.Audio.levels/3` scales either.

  A director made static (`Cauldron2D.Audio` started with `static_music: true`) plays
  the first section it is cued and no other: the section's chains are rendered once,
  as one pattern, over the piece's `:loop` cycles (default 8) — whatever still sounds at
  the end folded back over the start, so it loops without a seam — kept through
  `TuningFork.Cache` under `piece/section/static` and the fingerprint, and looped as a
  bed. Every later cue is ignored until `stop/1`. Rendering costs once a section and
  rate on a node; playing it back costs a copy a chunk.
  """

  alias TuningFork.{Cache, Stage}
  alias TuningFork.Pattern.Player

  @type renderable :: String.t() | TuningFork.Score.t() | (-> binary()) | {:pcm, binary()}
  @type spec :: %{
          required(:bpm) => number(),
          required(:beats_per_bar) => pos_integer(),
          required(:layers) => [atom()],
          required(:sections) => %{atom() => %{atom() => renderable()}},
          optional(:fingerprint) => String.t(),
          optional(:render) => :ahead | :on_cue
        }
  @type cue :: %{
          required(:piece) => String.t(),
          required(:section) => atom(),
          optional(:layers) => %{atom() => number()}
        }
  @type t :: %{
          pieces: map(),
          rendered: map(),
          wanted: cue() | nil,
          playing: {String.t(), atom()} | nil
        }

  @fade_ms 250
  @prefetch_cycles 64

  @doc """
  Fetch every recording and soundfont `pieces` play, in the background, so that their
  first bars are not synthesised while the files arrive. Walks the first 64
  cycles of every chain; a chain that does not read is skipped. Returns at once.
  """
  @spec prefetch([{String.t(), spec()}]) :: :ok
  def prefetch(pieces) when is_list(pieces) do
    chains =
      for {_name, spec} <- pieces,
          {_section, layers} <- spec.sections,
          {_layer, chain} <- layers,
          do: chain

    Task.start(fn -> Enum.each(chains, &prefetch_chain/1) end)
    :ok
  end

  defp prefetch_chain(chain) do
    case TuningFork.Strudel.pattern(chain) do
      {:ok, pattern} ->
        TuningFork.Strudel.defaults(wait: true)

        pattern
        |> TuningFork.Pattern.query({0, @prefetch_cycles})
        |> Enum.map(& &1.value)
        |> TuningFork.Kit.prefetch()

      {:error, _unreadable} ->
        :ok
    end
  end

  @doc "Declare a piece and start rendering every section of it."
  @spec piece(Cauldron2D.Audio.instance(), String.t(), spec()) :: :ok
  def piece(audio \\ Cauldron2D.Audio, name, spec) when is_binary(name) and is_map(spec) do
    call(audio, {:piece, name, spec})
  end

  @doc "Ask for a section of a piece with the given layer gains; see the module rules."
  @spec cue(Cauldron2D.Audio.instance(), cue()) :: :ok
  def cue(audio \\ Cauldron2D.Audio, %{piece: _, section: _} = cue), do: call(audio, {:cue, cue})

  @doc "Stop the music."
  @spec stop(Cauldron2D.Audio.instance()) :: :ok
  def stop(audio \\ Cauldron2D.Audio), do: call(audio, :stop)

  @doc "The piece and section playing, as `{piece, section}`, or `nil`."
  @spec current(Cauldron2D.Audio.instance()) :: {String.t(), atom()} | nil
  def current(audio \\ Cauldron2D.Audio), do: call(audio, :current)

  defp call(audio, request) do
    case GenServer.whereis(audio) do
      nil -> if request == :current, do: nil, else: :ok
      pid -> GenServer.call(pid, {:music, request})
    end
  end

  @workers 2

  @loop_cycles 8

  @doc false
  def new(opts \\ []),
    do: %{
      pieces: %{},
      rendered: %{},
      wanted: nil,
      playing: nil,
      queue: [],
      requested: MapSet.new(),
      rendering: 0,
      live: false,
      static: Keyword.get(opts, :static, false)
    }

  @doc false
  def handle({:piece, name, spec}, director, owner, state) do
    stems = if on_cue?(spec), do: [], else: stems(name, spec, Map.keys(spec.sections))

    director = %{
      director
      | pieces: Map.put(director.pieces, name, spec),
        queue: director.queue ++ stems
    }

    {:ok, director |> prioritise() |> start_renders(owner, state)}
  end

  def handle({:cue, _cue}, %{static: true, playing: playing} = director, _owner, _state)
      when playing != nil,
      do: {:ok, director}

  def handle({:cue, cue}, %{static: true} = director, owner, state) do
    director = %{director | wanted: cue}

    case Map.fetch(director.rendered, {cue.piece, cue.section}) do
      {:ok, %{static: _}} -> {:ok, apply_cue(director, state)}
      _not_yet -> {:ok, render_static(director, cue, owner, state)}
    end
  end

  def handle({:cue, cue}, director, owner, state) do
    director =
      %{director | wanted: cue} |> request(cue) |> prioritise() |> start_renders(owner, state)

    {:ok, apply_cue(director, state)}
  end

  def handle({:level, _music}, %{live: false} = director, _owner, _state), do: {:ok, director}

  def handle({:level, music}, director, _owner, state) do
    if state.stage, do: Stage.pattern_gain(state.stage, music)
    {:ok, director}
  end

  def handle(:stop, director, _owner, state) do
    if state.stage do
      Stage.clear_bed(state.stage)
      if director.live, do: Stage.stop_pattern(state.stage)
    end

    {:ok, %{director | wanted: nil, playing: nil, live: false}}
  end

  def handle(:current, director, _owner, _state), do: {director.playing, director}

  @doc false
  def handle_info({:stem, piece, section, layer, pcm}, director, owner, state) do
    key = {piece, section}
    stems = director.rendered |> Map.get(key, %{}) |> Map.put(layer, pcm)

    %{
      director
      | rendered: Map.put(director.rendered, key, stems),
        rendering: director.rendering - 1
    }
    |> start_renders(owner, state)
    |> apply_cue(state)
  end

  defp stems(name, spec, sections) do
    for section <- sections,
        layers = Map.fetch!(spec.sections, section),
        not live?(layers),
        {layer, renderable} <- layers,
        do: {name, section, layer, renderable, spec}
  end

  defp on_cue?(spec), do: Map.get(spec, :render, :ahead) == :on_cue

  defp request(director, %{piece: piece, section: section}) do
    key = {piece, section}

    with {:ok, spec} <- Map.fetch(director.pieces, piece),
         true <- on_cue?(spec) and is_map_key(spec.sections, section),
         false <- MapSet.member?(director.requested, key) do
      %{
        director
        | queue: director.queue ++ stems(piece, spec, [section]),
          requested: MapSet.put(director.requested, key)
      }
    else
      _ahead_or_requested -> director
    end
  end

  defp forget_others(director, {piece, _section} = key) do
    case Map.fetch(director.pieces, piece) do
      {:ok, spec} -> if on_cue?(spec), do: drop_others(director, key), else: director
      :error -> director
    end
  end

  defp drop_others(director, {piece, _section} = key) do
    others = for {{^piece, _} = other, _stems} <- director.rendered, other != key, do: other

    %{
      director
      | rendered: Map.drop(director.rendered, others),
        requested: Enum.reduce(others, director.requested, &MapSet.delete(&2, &1))
    }
  end

  defp prioritise(%{wanted: nil} = director), do: director

  defp prioritise(%{wanted: %{piece: piece, section: section}, queue: queue} = director) do
    {first, rest} = Enum.split_with(queue, fn {p, s, _, _, _} -> p == piece and s == section end)
    %{director | queue: first ++ rest}
  end

  defp start_renders(%{queue: []} = director, _owner, _state), do: director

  defp start_renders(%{rendering: busy} = director, _owner, _state) when busy >= @workers,
    do: director

  defp start_renders(
         %{queue: [{piece, section, layer, renderable, spec} | rest]} = director,
         owner,
         state
       ) do
    render(owner, piece, section, layer, renderable, spec, state)
    start_renders(%{director | queue: rest, rendering: director.rendering + 1}, owner, state)
  end

  defp render(owner, piece, section, layer, renderable, spec, state) do
    key = "#{piece}/#{section}/#{layer}"
    {rate, channels} = {state.rate, state.channels}
    fingerprint = fingerprint(spec, renderable, rate, channels)

    Task.start(fn ->
      pcm =
        Cache.fetch(key, fingerprint, fn -> to_pcm(renderable, rate, channels) end,
          dir: state.music_dir
        )

      send(owner, {:music, {:stem, piece, section, layer, pcm}})
    end)
  end

  defp render_static(%{rendering: busy} = director, _cue, _owner, _state) when busy > 0,
    do: director

  defp render_static(director, cue, owner, state) do
    with {:ok, spec} <- Map.fetch(director.pieces, cue.piece),
         {:ok, layers} <- Map.fetch(spec.sections, cue.section),
         true <- live?(layers) do
      {rate, channels} = {state.rate, state.channels}

      dir = state.music_dir

      Task.start(fn ->
        pcm = render_static(cue.piece, spec, cue.section, rate, channels, dir: dir)
        send(owner, {:music, {:stem, cue.piece, cue.section, :static, pcm}})
      end)

      %{director | rendering: 1}
    else
      _not_chains -> director
    end
  end

  @doc """
  The section of `spec` a static director loops for `piece`, as PCM at `rate` and
  `channels`: rendered now and kept if it was not before, read back if it was, in
  `:dir` (default `TuningFork.Cache.dir/0`; a game's is
  `Cauldron2D.Client.Game.music_dir/1`). A server that will play static music calls
  this for its pieces as it starts, so the first listener does not wait for the
  rendering.
  """
  @spec render_static(String.t(), spec(), atom(), pos_integer(), 1 | 2, keyword()) :: binary()
  def render_static(piece, spec, section, rate, channels, opts \\ []) do
    cue = %{piece: piece, section: section, layers: %{}}
    key = "#{piece}/#{section}/static"
    cycles = Map.get(spec, :loop, @loop_cycles)
    cps = spec.bpm / spec.beats_per_bar / 60
    pattern = live_pattern(%{pieces: %{piece => spec}}, cue)

    Cache.fetch(
      key,
      fingerprint(spec, Map.fetch!(spec.sections, section), rate, channels),
      fn ->
        Player.render(pattern, rate,
          cycles: cycles,
          cps: cps,
          channels: channels
        )
      end,
      dir: Keyword.get(opts, :dir, Cache.dir())
    )
  end

  defp fingerprint(spec, written, rate, channels),
    do:
      "#{Map.get(spec, :fingerprint, "0")}-#{:erlang.phash2({written, spec.bpm, spec.beats_per_bar, Map.get(spec, :loop)})}-#{rate}x#{channels}"

  defp to_pcm(%TuningFork.Score{} = score, rate, channels),
    do: TuningFork.Score.render(score, rate, channels: channels)

  defp to_pcm(render, _rate, _channels) when is_function(render, 0), do: render.()
  defp to_pcm({:pcm, pcm}, _rate, _channels) when is_binary(pcm), do: pcm

  defp apply_cue(%{wanted: nil} = director, _state), do: director
  defp apply_cue(director, %{stage: nil}), do: director

  defp apply_cue(%{static: true, wanted: cue} = director, state) do
    key = {cue.piece, cue.section}

    case Map.get(director.rendered, key) do
      %{static: _} = stems ->
        play(director, Map.get(director.pieces, cue.piece), key, stems, %{}, state)

      _not_ready ->
        director
    end
  end

  defp apply_cue(%{wanted: cue} = director, state) do
    key = {cue.piece, cue.section}

    with {:ok, spec} <- Map.fetch(director.pieces, cue.piece),
         {:ok, wanted} <- Map.fetch(spec.sections, cue.section) do
      if live?(wanted),
        do: perform(director, spec, key, cue, state),
        else: play_rendered(director, spec, key, wanted, cue, state)
    else
      _unknown -> director
    end
  end

  defp play_rendered(director, spec, key, wanted, cue, state) do
    case Map.get(director.rendered, key) do
      stems when is_map(stems) and map_size(stems) == map_size(wanted) ->
        play(director, spec, key, stems, Map.get(cue, :layers, %{}), state)

      _not_ready ->
        director
    end
  end

  defp live?(layers),
    do: layers != %{} and Enum.all?(layers, fn {_layer, what} -> is_binary(what) end)

  defp perform(%{playing: key} = director, _spec, key, cue, state) do
    Stage.update_pattern(state.stage, live_pattern(director, cue), at: :now)
    director
  end

  defp perform(director, spec, key, cue, state) do
    pattern = live_pattern(director, cue)
    cps = spec.bpm / spec.beats_per_bar / 60

    if director.live and director.playing != nil do
      Stage.pattern_cps(state.stage, cps)
      Stage.update_pattern(state.stage, pattern, at: :cycle)
    else
      Stage.clear_bed(state.stage)
      Stage.pattern_gain(state.stage, state.music)
      Stage.start_pattern(state.stage, pattern, cps: cps, parallel: state.parallel)
    end

    %{director | playing: key, live: true}
  end

  defp live_pattern(director, cue) do
    spec = Map.fetch!(director.pieces, cue.piece)
    layers = Map.fetch!(spec.sections, cue.section)
    gains = Map.get(cue, :layers, %{})

    chains =
      for {layer, chain} <- layers do
        gain = Map.get(gains, layer, 1.0)
        "(" <> chain <> ").velocity(" <> Float.to_string(gain / 1) <> ")"
      end

    {:ok, pattern} = TuningFork.Strudel.pattern("stack(" <> Enum.join(chains, ",\n") <> ")")
    pattern
  end

  defp play(%{playing: key} = director, _spec, key, _stems, gains, state) do
    Stage.layer_gains(state.stage, gains)
    director
  end

  defp play(director, _spec, key, stems, gains, state) do
    if director.live, do: Stage.stop_pattern(state.stage)
    opts = [gains: gains, fade_ms: @fade_ms] ++ bar_opt(director, state.rate)
    Stage.layers(state.stage, stems, opts)
    forget_others(%{director | playing: key, live: false}, key)
  end

  defp bar_opt(%{playing: nil}, _rate), do: []

  defp bar_opt(%{playing: {piece, _section}, pieces: pieces}, rate) do
    case Map.fetch(pieces, piece) do
      {:ok, playing_spec} -> [at: {:bar, bar_frames(playing_spec, rate)}]
      :error -> []
    end
  end

  defp bar_frames(spec, rate), do: max(1, round(rate * 60 / spec.bpm * spec.beats_per_bar))
end
