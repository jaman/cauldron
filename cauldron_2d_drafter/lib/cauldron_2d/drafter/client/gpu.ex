defmodule Cauldron2D.Drafter.Client.Gpu do
  @moduledoc """
  A client's graphics card: where its scenes are drawn, the
  `Cauldron2D.Drafter.Client.Stage` that draws them, and what it does to the game's scenes.

  Where comes from the picture options (`gpu`, `window` or `software`,
  `Cauldron2D.Drafter.Client.Picture`) when they say, else from the player's `drawing`
  setting (`Cauldron2D.Drafter.Client.Settings`), whose `:auto` draws on the card in the
  pane. The stage starts the first time a scene with a `:gpu` arrives, so a game that
  never describes one never starts a renderer.

  The client keeps it under `:gpu` in its state:

    * `new/1` and `configure/1` work out where to draw; `configure/1` again after the
      drawing setting changes stops a stage that no longer fits
    * `tick/2`, with each scene, starts the stage when it is wanted and sends the scene
      to a window
    * `scene/2` gives the scene the client draws: in the pane, a scene with a `:gpu` has
      its `:picture` drawn by the stage once it is ready; in a window, the pane's picture
      is empty from the moment the window starts opening; otherwise, and for scenes with
      no `:gpu`, the game's own `:picture` with the `:gpu` key taken out
    * `message/2` takes the stage's messages: window keys go to the app as terminal
      events, and a stage that fails or a window that closes leaves the game's own
      picture in its place
    * `note/1` is a note about the card for the few seconds after it is made; notes are
      made when the card was asked for by name (`gpu`, `window`, or the setting `:pane`
      or `:window`), not for `:auto`
    * `stop/1` stops the stage

  While a window is open the client is told keys are released (`{:key_release_support,
  true}`); when it closes the terminal's own answer is restored.
  """

  alias Cauldron2D.Drafter.Client.{Picture, Stage}
  alias Drafter.Event.Manager
  alias Drafter.Session.Context

  @type mode :: :pane | :window | nil
  @type t :: %{
          asked: :pane | :window | :software | nil,
          mode: mode(),
          named?: boolean(),
          tried?: boolean(),
          stage: Stage.t() | nil,
          ready?: boolean(),
          note: {String.t(), integer()} | nil,
          key_release: boolean() | nil
        }

  @note_ms 6_000

  @doc "The state of a client whose picture options are `options`, before `configure/1`."
  @spec new([Picture.option()]) :: t()
  def new(options) do
    %{
      asked: Picture.gpu(options),
      mode: nil,
      named?: false,
      tried?: false,
      stage: nil,
      ready?: false,
      note: nil,
      key_release: nil
    }
  end

  @doc """
  The client state with where to draw worked out from its picture options and its
  settings' `drawing`; a stage that no longer fits is stopped, and the next scene with a
  `:gpu` starts one that does.
  """
  @spec configure(map()) :: map()
  def configure(%{gpu: gpu, settings: settings} = state) do
    drawing = Map.get(settings, :drawing, :auto)
    mode = mode(gpu.asked, drawing)
    named? = gpu.asked in [:pane, :window] or (gpu.asked == nil and drawing in [:pane, :window])

    if mode == gpu.mode and gpu.tried? do
      put(state, %{named?: named?})
    else
      stop(state)

      state
      |> restore_key_release()
      |> put(%{mode: mode, named?: named?, tried?: false, stage: nil, ready?: false})
    end
  end

  @doc "Starts the stage when the scene wants one, and sends the scene to an open window."
  @spec tick(map(), map()) :: map()
  def tick(%{gpu: %{mode: mode, tried?: false}} = state, %{gpu: _gpu}) when mode != nil,
    do: start(state)

  def tick(%{gpu: %{mode: :window, ready?: true, stage: stage}} = state, %{gpu: gpu}) do
    Stage.draw(stage, gpu)
    state
  end

  def tick(state, _scene), do: state

  @doc "The scene the client draws for the game's `scene`."
  @spec scene(map(), map()) :: map()
  def scene(%{gpu: %{mode: :pane, ready?: true, stage: stage}}, %{gpu: gpu} = scene) do
    own = Map.get(scene, :picture)

    Map.put(scene, :picture, fn size, aspect ->
      case Stage.picture(stage, gpu, size, aspect) do
        {:ok, raster} -> raster
        {:error, _reason} -> own.(size, aspect)
      end
    end)
  end

  def scene(%{gpu: %{mode: :window, stage: stage}}, %{gpu: _gpu} = scene) when stage != nil,
    do: scene |> Map.delete(:gpu) |> Map.put(:picture, nil)

  def scene(_state, scene), do: Map.delete(scene, :gpu)

  @doc "The client state after a message from its stage."
  @spec message({module(), pid(), term()}, map()) :: map()
  def message({Stage, stage, message}, %{gpu: %{stage: stage}} = state),
    do: staged(message, state)

  def message(_message, state), do: state

  @doc "The note about the graphics card to show now, if any."
  @spec note(map()) :: String.t() | nil
  def note(%{gpu: %{note: {text, at}}}) do
    if System.monotonic_time(:millisecond) - at < @note_ms, do: text
  end

  def note(_state), do: nil

  @doc "Stops the client's stage, if it has one."
  @spec stop(map()) :: :ok
  def stop(%{gpu: %{stage: nil}}), do: :ok
  def stop(%{gpu: %{stage: stage}}), do: Stage.stop(stage)
  def stop(_state), do: :ok

  defp mode(:software, _drawing), do: nil
  defp mode(asked, _drawing) when asked in [:pane, :window], do: asked
  defp mode(nil, :software), do: nil
  defp mode(nil, :auto), do: :pane
  defp mode(nil, drawing) when drawing in [:pane, :window], do: drawing

  defp start(%{gpu: gpu, game: game} = state) do
    case Stage.start(gpu.mode, title: game.title().name) do
      {:ok, stage} ->
        put(state, %{tried?: true, stage: stage, note: named(gpu, opening(gpu.mode))})

      {:error, reason} ->
        fall_back(put(state, %{tried?: true}), reason)
    end
  end

  defp staged(:ready, %{gpu: %{mode: :window} = gpu} = state) do
    terminal_release = Context.key_release?()
    Manager.send_event({:key_release_support, true})

    put(state, %{
      ready?: true,
      key_release: terminal_release,
      note: named(gpu, "drawn in its own window")
    })
  end

  defp staged(:ready, %{gpu: gpu} = state),
    do: put(state, %{ready?: true, note: named(gpu, "drawn by the graphics card")})

  defp staged({:input, event}, state) do
    Manager.send_event(event)
    state
  end

  defp staged(:closed, state) do
    state
    |> restore_key_release()
    |> put(%{
      stage: nil,
      ready?: false,
      mode: nil,
      note: noted("window closed: drawn in the terminal")
    })
  end

  defp staged({:failed, reason}, state), do: state |> restore_key_release() |> fall_back(reason)

  defp fall_back(%{gpu: gpu} = state, reason) do
    put(state, %{
      stage: nil,
      ready?: false,
      mode: nil,
      note: named(gpu, "no graphics card (#{describe(reason)}): drawn in software")
    })
  end

  defp restore_key_release(%{gpu: %{key_release: nil}} = state), do: state

  defp restore_key_release(%{gpu: %{key_release: supported?}} = state) do
    Manager.send_event({:key_release_support, supported?})
    put(state, %{key_release: nil})
  end

  defp put(%{gpu: gpu} = state, changes), do: %{state | gpu: Map.merge(gpu, changes)}

  defp named(%{named?: true}, {_text, _at} = note), do: note
  defp named(%{named?: true}, text), do: noted(text)
  defp named(_gpu, _note), do: nil

  defp noted(text), do: {text, System.monotonic_time(:millisecond)}

  defp opening(:window), do: noted("opening a window")
  defp opening(:pane), do: noted("starting the graphics card")

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
