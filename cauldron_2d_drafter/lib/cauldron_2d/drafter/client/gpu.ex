defmodule Cauldron2D.Drafter.Client.Gpu do
  @moduledoc """
  A client's graphics card: where its scenes are drawn, the
  `Cauldron2D.Drafter.Client.Stage` that draws them, and what it does to the game's scenes.

  Where comes from the picture options (`gpu`, `window` or `software`,
  `Cauldron2D.Drafter.Client.Picture`) when they say, else from the player's `drawing`
  setting (`Cauldron2D.Drafter.Client.Settings`), whose `:auto` draws on the card in the
  pane. The stage starts the first time a scene with a `:gpu` arrives, so a game that
  never describes one never starts a renderer.

  Where the card is not drawn on — the options or the setting say `software`, or the card
  did not open — a scene with a `:gpu` and no `:picture` of the game's own is drawn on
  the CPU by `Cauldron3D.Scene.Software` (`Cauldron2D.Drafter.Client.SoftwareStage`),
  where the build has it; a game's own `:picture` is drawn as it is.

  The client keeps it under `:gpu` in its state:

    * `new/1` and `configure/1` work out where to draw; `configure/1` again after the
      drawing setting changes stops a stage that no longer fits
    * `tick/2`, with each scene, starts the stage when it is wanted and sends the scene
      to a window, telling the stage whether the player's bindings steer with the
      pointer (`Stage.pointer/2`), so a window captures the pointer only then
    * `scene/2` gives the scene the client draws: in the pane, a scene with a `:gpu` has
      its `:picture` drawn by the stage once it is ready, as frames in shared memory when
      the terminal is on this machine and its surface stores pictures
      (`Cauldron2D.Drafter.Surface.stores_pictures?/1`), else as pixels; in a window, the pane's picture
      is empty from the moment the window starts opening; otherwise, and for scenes with
      no `:gpu`, the game's own `:picture` with the `:gpu` key taken out
    * `message/2` takes the stage's messages: window keys go to the app as terminal
      events, and a stage that fails or a window that closes leaves the game's own
      picture in its place
    * `note/1` is a note about the card for the few seconds after it is made; notes are
      made when the card was asked for by name (`gpu`, `window`, or the setting `:pane`
      or `:window`), not for `:auto`
    * `drawn/1` is how many pictures the card gave the pane, or frames it drew in the
      window, in the last second; `nil` while no stage is drawing
    * `rate/2` tells the stage the client's new frame rate
    * `stop/1` stops the stage

  While a window is open the client is told keys are released (`{:key_release_support,
  true}`); when it closes the terminal's own answer is restored.
  """

  alias Cauldron.Input
  alias Cauldron2D.Drafter.Client
  alias Cauldron2D.Drafter.Client.{Picture, Settings, SoftwareStage, Stage}
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Event.Manager
  alias Drafter.Session.Context

  @type mode :: :pane | :window | :software | nil
  @type t :: %{
          asked: :pane | :window | :software | nil,
          mode: mode(),
          named?: boolean(),
          tried?: boolean(),
          stage: Stage.t() | SoftwareStage.t() | nil,
          ready?: boolean(),
          note: {String.t(), integer()} | nil,
          key_release: boolean() | nil,
          pointer?: boolean(),
          drawn: non_neg_integer() | nil
        }

  @note_ms 6_000
  @pointer_moves [:move_left, :move_right, :move_up, :move_down]

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
      key_release: nil,
      pointer?: false,
      drawn: nil
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
      |> put(%{
        mode: mode,
        named?: named?,
        tried?: false,
        stage: nil,
        ready?: false,
        pointer?: false,
        drawn: nil
      })
    end
  end

  @doc "Starts the stage when the scene wants one, and sends the scene to an open window."
  @spec tick(map(), map()) :: map()
  def tick(%{gpu: %{mode: :software}} = state, %{picture: _own}), do: state

  def tick(%{gpu: %{mode: mode, tried?: false}} = state, %{gpu: _gpu}) when mode != nil,
    do: start(state)

  def tick(%{gpu: %{mode: :window, ready?: true, stage: stage}} = state, %{gpu: gpu}) do
    Stage.draw(stage, gpu)
    pointer(state, stage, steers?(state))
  end

  def tick(state, _scene), do: state

  defp pointer(%{gpu: %{pointer?: steers?}} = state, _stage, steers?), do: state

  defp pointer(state, stage, steers?) do
    Stage.pointer(stage, steers?)
    put(state, %{pointer?: steers?})
  end

  defp steers?(%{joined: joined, party: %{controls: %{input: %Input{} = input}}})
       when joined != nil,
       do: Enum.any?(@pointer_moves, &Input.binds?(input, {:mouse, &1}))

  defp steers?(_state), do: false

  @doc "The scene the client draws for the game's `scene`."
  @spec scene(map(), map()) :: map()
  def scene(%{gpu: %{mode: :pane, ready?: true, stage: stage}} = state, %{gpu: gpu} = scene) do
    own = Map.get(scene, :picture)
    shared? = shared_frames?(state)

    Map.put(scene, :picture, fn size, aspect ->
      case Stage.picture(stage, gpu, size, aspect, shared?) do
        {:ok, picture} -> picture
        {:error, _reason} -> own.(size, aspect)
      end
    end)
  end

  def scene(%{gpu: %{mode: :window, stage: stage}}, %{gpu: _gpu} = scene) when stage != nil,
    do: scene |> Map.delete(:gpu) |> Map.put(:picture, nil)

  def scene(%{gpu: %{mode: :software, ready?: true, stage: stage}}, %{gpu: gpu} = scene) do
    scene
    |> Map.delete(:gpu)
    |> Map.put_new(:picture, fn size, aspect ->
      case SoftwareStage.picture(stage, gpu, size, aspect) do
        {:ok, picture} -> picture
        {:error, _reason} -> FrenchCurve.Raster.new(elem(size, 0), elem(size, 1))
      end
    end)
  end

  def scene(_state, scene), do: Map.delete(scene, :gpu)

  @doc "The client state after a message from its stage."
  @spec message({module(), pid(), term()}, map()) :: map()
  def message({Stage, stage, message}, %{gpu: %{stage: stage}} = state),
    do: staged(message, state)

  def message({SoftwareStage, stage, message}, %{gpu: %{stage: stage}} = state),
    do: staged(message, state)

  def message(_message, state), do: state

  @doc "The note about the graphics card to show now, if any."
  @spec note(map()) :: String.t() | nil
  def note(%{gpu: %{note: {text, at}}}) do
    if System.monotonic_time(:millisecond) - at < @note_ms, do: text
  end

  def note(_state), do: nil

  @doc """
  Whether the card's frames reach the pane through shared memory: the pane is drawn on the
  card, the terminal is on this machine, and its surface stores pictures
  (`Cauldron2D.Drafter.Surface.stores_pictures?/1`).
  """
  @spec shared_frames?(map()) :: boolean()
  def shared_frames?(%{gpu: %{mode: :pane}} = state),
    do: local?(state) and Surface.stores_pictures?(surface_props(state, %{gpu: nil}))

  def shared_frames?(_state), do: false

  @doc "The pictures the card drew in the last second, or `nil` while it draws nothing."
  @spec drawn(map()) :: non_neg_integer() | nil
  def drawn(%{gpu: %{stage: stage, drawn: drawn}}) when stage != nil, do: drawn
  def drawn(_state), do: nil

  @doc "Tells the client's stage, if it has one, to draw at `fps` frames a second."
  @spec rate(map(), pos_integer()) :: :ok
  def rate(%{gpu: %{mode: :software}}, _fps), do: :ok
  def rate(%{gpu: %{stage: stage}}, fps) when stage != nil, do: Stage.rate(stage, fps)
  def rate(_state, _fps), do: :ok

  @doc "Stops the client's stage, if it has one."
  @spec stop(map()) :: :ok
  def stop(%{gpu: %{stage: nil}}), do: :ok
  def stop(%{gpu: %{mode: :software, stage: stage}}), do: SoftwareStage.stop(stage)
  def stop(%{gpu: %{stage: stage}}), do: Stage.stop(stage)
  def stop(_state), do: :ok

  defp mode(:software, _drawing), do: software_mode()
  defp mode(asked, _drawing) when asked in [:pane, :window], do: asked
  defp mode(nil, :software), do: software_mode()
  defp mode(nil, :auto), do: :pane
  defp mode(nil, drawing) when drawing in [:pane, :window], do: drawing

  defp surface_props(state, scene) do
    [mode: Settings.surface_mode(state.settings)] ++
      Picture.surface_props(state.picture, scene, Client.look(state))
  end

  defp local?(%{props: %{served_by: _server}}), do: false

  defp local?(_state) do
    env = Context.terminal_env()
    not Map.has_key?(env, "SSH_CONNECTION") and not Map.has_key?(env, "SSH_TTY")
  end

  defp software_mode, do: if(SoftwareStage.available?(), do: :software)

  defp start(%{gpu: %{mode: :software} = gpu} = state) do
    case SoftwareStage.start() do
      {:ok, stage} ->
        put(state, %{
          tried?: true,
          stage: stage,
          note: named(gpu, "starting the software renderer")
        })

      {:error, reason} ->
        fall_back(put(state, %{tried?: true}), reason)
    end
  end

  defp start(%{gpu: gpu, game: game} = state) do
    case Stage.start(gpu.mode, title: game.title().name, fps: Client.frame_rate(state)) do
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

  defp staged(:ready, %{gpu: %{mode: :software} = gpu} = state),
    do: put(state, %{ready?: true, note: named(gpu, "drawn on the CPU")})

  defp staged(:ready, %{gpu: gpu} = state),
    do: put(state, %{ready?: true, note: named(gpu, "drawn by the graphics card")})

  defp staged({:drawn, count}, state), do: put(state, %{drawn: count})

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
      drawn: nil,
      mode: nil,
      note: noted("window closed: drawn in the terminal")
    })
  end

  defp staged({:failed, reason}, state), do: state |> restore_key_release() |> fall_back(reason)

  defp fall_back(%{gpu: %{mode: :software} = gpu} = state, reason) do
    put(state, %{
      stage: nil,
      ready?: false,
      drawn: nil,
      mode: nil,
      note: named(gpu, "no software renderer (#{describe(reason)}): the game's own picture")
    })
  end

  defp fall_back(%{gpu: gpu} = state, reason) do
    mode = software_mode()

    put(state, %{
      stage: nil,
      ready?: false,
      drawn: nil,
      mode: mode,
      tried?: false,
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
