defmodule Cauldron2D.Drafter.Client.SoftwareStage do
  @moduledoc """
  A client's scenes drawn on the CPU by `Cauldron3D.Scene.Software`, for a terminal client
  without a graphics card to draw on: a scene's `:gpu` function describes the scene to
  the software renderer as it would to the card, and `picture/4` answers the frame it
  draws as a raster for the pane.

      {:ok, stage} = SoftwareStage.start()
      # once {SoftwareStage, ^stage, :ready} has arrived:
      {:ok, raster} = SoftwareStage.picture(stage, scene.gpu, {480, 270}, 1.0)

  The process that starts a stage is its owner and receives `{SoftwareStage, stage,
  message}`: `:ready` once it has started, and `{:drawn, count}` once a second, the
  pictures handed to the pane in the second before. The stage stops when its owner exits.

  The software renderer is in the build when `cauldron_3d` is (`available?/0`).
  """

  use GenServer

  alias Cauldron2D.Raster
  alias Cauldron3D.Scene.{Software, Target}

  @compile {:no_warn_undefined, [Cauldron3D.Scene.Software, Cauldron3D.Scene.Target, CauldronGPU]}

  @type t :: pid()
  @type gpu :: (term(), term(), {pos_integer(), pos_integer()}, number() -> {list(), term()})

  @frame_timeout 5_000
  @count_ms 1_000

  @doc "Whether this build has the software renderer."
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Software)

  @doc "Starts a stage owned by the caller."
  @spec start() :: {:ok, t()} | {:error, term()}
  def start do
    if available?(),
      do: GenServer.start(__MODULE__, self()),
      else: {:error, "no software renderer in this build"}
  end

  @doc """
  Describes the scene `gpu` gives to the software renderer at `size` pixels and answers
  the frame it draws as a raster, or `{:error, reason}` when the function raises or no
  frame comes in time.
  """
  @spec picture(t(), gpu(), {pos_integer(), pos_integer()}, number()) ::
          {:ok, Raster.t()} | {:error, term()}
  def picture(stage, gpu, size, aspect) do
    GenServer.call(stage, {:picture, gpu, size, aspect}, @frame_timeout + 1_000)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc "Stops the stage and its renderer."
  @spec stop(t()) :: :ok
  def stop(stage) do
    GenServer.stop(stage)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init(owner) do
    Process.monitor(owner)
    stage = self()

    {:ok, software} =
      Software.open(
        width: 1,
        height: 1,
        present: fn rgba, width, height -> send(stage, {:frame, rgba, width, height}) end,
        decode: decoder()
      )

    send(owner, {__MODULE__, self(), :ready})
    Process.send_after(self(), :count, @count_ms)
    {:ok, %{owner: owner, software: software, size: nil, cache: nil, drawn: 0}}
  end

  @impl true
  def handle_call({:picture, gpu, size, aspect}, _from, state) do
    state = sized(state, size)
    {changes, cache} = gpu.(state.software, state.cache, size, aspect)
    Target.submit(state.software, changes)
    {:reply, newest_frame(size), %{state | cache: cache, drawn: state.drawn + 1}}
  rescue
    error -> {:reply, {:error, error}, state}
  end

  @impl true
  def handle_info(:count, state) do
    Process.send_after(self(), :count, @count_ms)
    send(state.owner, {__MODULE__, self(), {:drawn, state.drawn}})
    {:noreply, %{state | drawn: 0}}
  end

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: Software.close(state.software)

  defp sized(%{size: size} = state, size), do: state

  defp sized(state, {width, height} = size) do
    Software.resize(state.software, width, height)
    %{state | size: size}
  end

  defp newest_frame({width, height}) do
    receive do
      {:frame, rgba, ^width, ^height} ->
        {:ok, newer_frame(Raster.from_rgba(width, height, rgba), width, height)}

      {:frame, _rgba, _width, _height} ->
        newest_frame({width, height})
    after
      @frame_timeout -> {:error, :no_frame}
    end
  end

  defp newer_frame(raster, width, height) do
    receive do
      {:frame, rgba, ^width, ^height} ->
        newer_frame(Raster.from_rgba(width, height, rgba), width, height)
    after
      0 -> raster
    end
  end

  defp decoder do
    if Code.ensure_loaded?(CauldronGPU) and function_exported?(CauldronGPU, :decode, 1),
      do: &CauldronGPU.decode/1
  end
end
