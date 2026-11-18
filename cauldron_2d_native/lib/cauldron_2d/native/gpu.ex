defmodule Cauldron2D.Native.Gpu do
  @moduledoc """
  A game's `:gpu` scene on a phone: drawn by `cauldron_gpu` into the app's graphics
  surface (`CauldronNative.gpu_surface/0`: Metal on iOS, Vulkan on Android) at the
  screen's full size, or, where the graphics card will not open, drawn on the CPU by
  `Cauldron3D.Scene.Software` at up to 480 pixels across and shown as the app's
  picture (`CauldronNative.present/3`).

  `cauldron_gpu` is an optional dependency of this package; without it `usable?/1` is
  `false` and the game's scenes are drawn as pictures. While the app has no surface (before
  its view exists, or in the background on Android) `draw/3` leaves the renderer unopened
  and tries again with the next scene. When the card will not open, `draw/3` hides the
  surface and uses the software renderer from then on; where that is not in the app
  either (`cauldron_3d` is needed), `failed?/1` turns `true` for good and the caller draws
  the game's pictures instead (`Cauldron.Net.Link.Local.without_gpu/1`).

      gpu = Gpu.new()
      gpu = Gpu.draw(gpu, %{gpu: scene_gpu, size: nil}, screen)
      gpu = Gpu.close(gpu)

  `draw/3` opens a renderer on the first scene it is given, follows the screen when it
  changes size, calls the scene's `:gpu` function with the renderer as its target
  (`Cauldron3D.Scene.Target`), the size it draws at and square pixels, keeps what it
  answers as the next call's cache, and submits its changes. A game reads the renderer's
  `Cauldron3D.Scene.Target.capabilities/1` to offer only the effects it draws. `close/1`
  closes the renderer and hides the surface.
  """

  @software_width 480

  @type renderer :: {:card, term()} | {:software, term()}
  @type t :: %{
          renderer: renderer() | nil,
          cache: term(),
          size: {pos_integer(), pos_integer()} | nil,
          card_failed?: boolean(),
          failed?: boolean()
        }

  @doc "Nothing open yet."
  @spec new() :: t()
  def new, do: %{renderer: nil, cache: nil, size: nil, card_failed?: false, failed?: false}

  @doc "Whether neither renderer would open on this device, so scenes are drawn as pictures."
  @spec failed?(t()) :: boolean()
  def failed?(%{failed?: failed?}), do: failed?

  @doc "The size the software renderer draws a screen of `{width, height}` pixels at."
  @spec software_size({pos_integer(), pos_integer()}) :: {pos_integer(), pos_integer()}
  def software_size({width, height}) do
    across = min(width, @software_width)
    {across, max(round(across * height / width), 1)}
  end

  if Code.ensure_loaded?(CauldronGPU) do
    alias Cauldron3D.Scene.{Software, Target}

    @doc "`scene`'s `:gpu` drawn on `screen` (`%{width, height}` in pixels)."
    @spec draw(t(), %{gpu: function()}, map()) :: t()
    def draw(state, %{gpu: gpu}, %{width: width, height: height}) do
      state = state |> opened({width, height}) |> sized({width, height})

      case state.renderer do
        nil ->
          state

        renderer ->
          target = target(renderer)
          {changes, cache} = gpu.(target, state.cache, drawn_size(renderer, state.size), 1.0)
          Target.submit(target, changes)
          %{state | cache: cache}
      end
    end

    @doc "Close the renderer, if one is open, and hide the surface."
    @spec close(t()) :: t()
    def close(%{renderer: nil} = state), do: state

    def close(%{renderer: renderer} = state) do
      closed(renderer)
      %{new() | card_failed?: state.card_failed?, failed?: state.failed?}
    end

    defp closed({:card, gpu}) do
      CauldronGPU.close(gpu)
      CauldronNative.hide_gpu_surface()
    end

    defp closed({:software, software}), do: software_close(software)

    defp opened(%{renderer: nil, failed?: false, card_failed?: false} = state, size) do
      case CauldronNative.gpu_surface() do
        {:ok, surface} -> on_card(state, surface, size)
        {:error, :unavailable} -> state
      end
    end

    defp opened(%{renderer: nil, failed?: false, card_failed?: true} = state, size),
      do: on_software(state, size)

    defp opened(state, _size), do: state

    defp on_card(state, surface, {width, height}) do
      case CauldronGPU.open(surface: surface, width: width, height: height) do
        {:ok, gpu} ->
          %{state | renderer: {:card, gpu}, size: {width, height}, cache: nil}

        {:error, _reason} ->
          CauldronNative.hide_gpu_surface()
          on_software(%{state | card_failed?: true}, {width, height})
      end
    end

    defp sized(%{renderer: nil} = state, _size), do: state
    defp sized(%{size: size} = state, size), do: state

    defp sized(%{renderer: {:card, gpu}} = state, {width, height} = size) do
      CauldronGPU.resize(gpu, width, height)
      %{state | size: size}
    end

    defp sized(%{renderer: {:software, software}} = state, size) do
      {width, height} = software_size(size)
      software_resize(software, width, height)
      %{state | size: size}
    end

    if Code.ensure_loaded?(Software) do
      @doc "Whether a world should send this app its `:gpu` scenes: unless no renderer opened here (`failed?/1`)."
      @spec usable?(t()) :: boolean()
      def usable?(state), do: not failed?(state)

      defp on_software(state, size) do
        {width, height} = software_size(size)

        {:ok, software} =
          Software.open(
            width: width,
            height: height,
            present: fn rgba, across, down -> CauldronNative.present(across, down, rgba) end,
            decode: &CauldronGPU.decode/1
          )

        %{state | renderer: {:software, software}, size: size, cache: nil}
      end

      defp software_resize(software, width, height),
        do: Software.resize(software, width, height)

      defp software_close(software), do: Software.close(software)
    else
      @doc "Whether a world should send this app its `:gpu` scenes: where the card has a backend, unless it failed to open here (`failed?/1`)."
      @spec usable?(t()) :: boolean()
      def usable?(state), do: CauldronGPU.backends() != [] and not failed?(state)

      defp on_software(state, _size), do: %{state | failed?: true}
      defp software_resize(_software, _width, _height), do: :ok
      defp software_close(_software), do: :ok
    end

    defp target({_kind, target}), do: target

    defp drawn_size({:card, _gpu}, size), do: size
    defp drawn_size({:software, _software}, size), do: software_size(size)
  else
    @doc "Whether a world should send this app its `:gpu` scenes: never, without `cauldron_gpu`."
    @spec usable?(t()) :: boolean()
    def usable?(_state), do: false

    @doc "Nothing to draw with: `state` as it is."
    @spec draw(t(), map(), map()) :: t()
    def draw(state, _scene, _screen), do: state

    @doc "Nothing to close: `state` as it is."
    @spec close(t()) :: t()
    def close(state), do: state
  end
end
