defmodule Cauldron.SFX.Editor.Drafter do
  @moduledoc """
  The sound-effect editor in a terminal: `Cauldron.SFX.Editor`'s state, drawn with Drafter
  and played through a `TuningFork.Stage`.

      mix cauldron.sfx priv/sfx/sfx.json

  The keys and what they do are the editor's (`Cauldron.SFX.Editor`); this module only
  turns a key into a command, a `view/1` into labels, and a `{:play, sound}` into a stage
  call.
  """

  use Drafter, runtime: :reducer

  alias Cauldron.SFX.Editor

  @typedoc """
  The front end's state: the editor's `t:Cauldron.SFX.Editor.t/0`, the stage auditions go
  through, and the sink to start it with.
  """
  @type t :: %{
          model: Editor.t(),
          stage: pid() | nil,
          sink: term(),
          naming: String.t() | nil
        }

  @doc """
  The state the editor starts in.

  `props` is a map or a keyword list carrying the editor's own `:bank` and `:out`, and:

    * `:sink` — the sink to start the audition stage with; the speaker when not given
    * `:stage` — a stage already running, to audition through instead of starting one
  """
  @spec mount(map() | keyword()) :: t()
  def mount(props) do
    props = Map.new(props)

    %{
      model: Editor.mount(props),
      stage: Map.get(props, :stage),
      sink: Map.get(props, :sink),
      naming: nil
    }
  end

  @doc false
  def render(state) do
    view = Editor.view(state.model)

    vertical(
      [
        header(view.title),
        label(view.summary, style: %{fg: :cyan}),
        label(""),
        vertical(rows(view), flex: 1),
        label(""),
        label(view.detail, style: %{fg: :bright_black}),
        label(prompt(state), style: %{fg: :yellow}),
        label(view.said, style: %{fg: :bright_black}),
        footer(bindings: view.keys)
      ],
      gap: 0
    )
  end

  @doc """
  Handle a key. `q` stops whatever is playing and returns `{:stop, :normal}`; every other
  key goes to the editor, and anything it asks for is done here.
  """
  @spec update(term(), t()) :: t() | {:stop, :normal}
  def update({:key, key}, %{naming: naming} = state) when is_binary(naming) do
    naming(state, key)
  end

  def update({:key, :q}, state) do
    stop(state)
    {:stop, :normal}
  end

  def update({:key, :n}, state), do: %{state | naming: ""}

  def update({:key, key}, state) do
    {model, effects} = Editor.key(state.model, key)

    Enum.reduce(effects, %{state | model: model}, &run/2)
  end

  def update(_anything_else, state), do: state

  @doc false
  def handle_info(_message, state), do: {:noreply, state}

  # A name typed in the editor itself: enter adds the event, escape drops it.
  defp naming(state, :enter) do
    {model, effects} = Editor.command(state.model, {:new_event, state.naming})
    Enum.reduce(effects, %{state | model: model, naming: nil}, &run/2)
  end

  defp naming(state, :escape), do: %{state | naming: nil}

  defp naming(state, :backspace) do
    case String.slice(state.naming, 0..-2//1) do
      "" -> %{state | naming: ""}
      shorter -> %{state | naming: shorter}
    end
  end

  defp naming(state, key) do
    case printable(key) do
      nil -> state
      text -> %{state | naming: state.naming <> text}
    end
  end

  defp printable(key) when is_atom(key) do
    text = Atom.to_string(key)
    if text =~ ~r/^[a-z0-9_]$/, do: text
  end

  defp printable(_key), do: nil

  defp prompt(%{naming: nil}), do: ""

  defp prompt(%{naming: naming}),
    do: "new event: #{naming}▌  enter adds · escape cancels"

  defp rows(view) do
    Enum.map(view.rows, fn row ->
      if row.selected,
        do: label("▸ " <> row.label, style: %{fg: :yellow, bold: true}),
        else: label("  " <> row.label)
    end)
  end

  defp run({:play, voice}, state) do
    case stage(state) do
      {:ok, stage, state} ->
        audition(stage, voice)
        state

      {:error, state} ->
        state
    end
  end

  defp run(:quit, state), do: state

  defp stage(%{stage: stage} = state) when is_pid(stage), do: {:ok, stage, state}

  defp stage(state) do
    case sink(state) do
      nil ->
        {:error,
         %{state | model: %{state.model | said: "no audio device — w writes the bank instead"}}}

      sink ->
        {:ok, stage} = TuningFork.Stage.start_link(name: nil, sink: sink, chunk: 256, voices: 32)
        {:ok, stage, %{state | stage: stage}}
    end
  end

  defp sink(%{sink: sink}) when not is_nil(sink), do: sink

  defp sink(_state) do
    speaker = TuningFork.Sink.Speaker
    if Code.ensure_loaded?(speaker) and TuningFork.available?(), do: speaker
  end

  defp audition(stage, %{} = voice), do: TuningFork.Stage.play(stage, voice)

  defp audition(stage, voices) when is_list(voices) do
    for {at, voice} <- voices do
      spawn(fn ->
        Process.sleep(at)
        TuningFork.Stage.play(stage, voice)
      end)
    end

    :ok
  end

  defp stop(state) do
    case state.stage do
      stage when is_pid(stage) ->
        if Process.alive?(stage) do
          try do
            GenServer.stop(stage, :normal, 2_000)
          catch
            :exit, _reason -> Process.exit(stage, :kill)
          end
        end

        :ok

      _none ->
        :ok
    end

    %{state | stage: nil}
  end
end
