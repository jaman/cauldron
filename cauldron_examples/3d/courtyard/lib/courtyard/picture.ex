defmodule Courtyard.Picture do
  @moduledoc """
  The courtyard's `:gpu` (`Cauldron.Client.Game`): what the graphics card draws for a
  view (`Courtyard.Game.view/2`).

      gpu = Courtyard.Picture.gpu(view)
      {changes, cache} = gpu.(target, nil, {640, 360}, 1.0)

  It draws the scene that is loaded, from where the view stands in that scene. When the
  view asks for another scene, `Courtyard.Loader` uploads it while the shown one stays,
  dimmed; once it is ready the shown scene's instances and lights are removed and its
  handles released, the new scene's changes sent, and the picture fades in from black.
  Each frame sends the scene's `frame/2`, removing any instance or light it gave the frame
  before and no longer gives, the effects the view asks for when they change, the
  character (`Courtyard.Character`, uploaded once by the loader) placed and posed as the
  view's `:character` gives it, and the view's camera. While another scene loads, the
  character is hidden and the camera stays where it was. The atrium loads with
  2048-pixel textures.
  """

  alias Cauldron3D.Scene.{Camera, Pose, Transform}
  alias Cauldron3D.Scene.Target
  alias Courtyard.{Loader, Scenes}

  @traced [:ray_traced_shadows, :ray_traced_reflections, :ray_traced_ambient_occlusion]
  @fade_ms 600
  @dimmed 0.35

  @doc "The scene's `:gpu` function for `view`."
  @spec gpu(map()) :: (Target.t(), map() | nil, {pos_integer(), pos_integer()}, number() ->
                         {list(), map()})
  def gpu(view) do
    fn target, cache, size, aspect ->
      cache =
        cache ||
          %{
            shown: nil,
            placed: nil,
            moving: [],
            effects: nil,
            swapped_at: nil,
            tint: 0.0,
            camera: nil,
            character: false
          }

      {switch, cache} = switched(target, cache, view.scene)
      {moving, cache} = moved(cache, view)
      {effects, cache} = effects(cache, view.effects)
      {tint, cache} = tinted(cache, view.scene)
      {figure, cache} = figure(target, cache, view)
      {camera, cache} = camera(cache, view, size, aspect)
      {switch ++ effects ++ moving ++ figure ++ camera ++ tint, cache}
    end
  end

  @doc "The renderer effects a view's `:effects` ask for."
  @spec effects(map()) :: [atom()]
  def effects(effects) do
    if(effects.ray_tracing, do: @traced, else: []) ++
      if(effects.global_illumination, do: [:ray_traced_global_illumination], else: []) ++
      if effects.upscaling, do: [:upscaling], else: []
  end

  defp switched(_target, %{shown: scene} = cache, scene), do: {[], cache}

  defp switched(target, cache, scene) do
    case Loader.request(target, scene, side: 2048) do
      {:ready, placed} -> swapped(target, cache, scene, placed)
      _not_ready -> {[], cache}
    end
  end

  defp swapped(target, cache, scene, placed) do
    leaving = if cache.placed, do: removals(cache.placed.changes ++ cache.moving), else: []

    if cache.placed do
      Enum.each(cache.placed.handles, &Target.release(target, &1))
      Loader.forget(target, cache.shown)
    end

    cache = %{cache | shown: scene, placed: placed, moving: [], swapped_at: now()}
    {leaving ++ placed.changes, cache}
  end

  defp moved(%{placed: nil} = cache, _view), do: {[], cache}

  defp moved(cache, view) do
    moving = Scenes.module(cache.shown).frame(cache.placed, view)
    gone = removals(cache.moving) -- removals(moving)
    {gone ++ moving, %{cache | moving: moving}}
  end

  defp removals(changes) do
    for change <- changes, removal = removal(change), removal != nil, do: removal
  end

  defp removal({:instance, id, _instance}), do: {:remove_instance, id}
  defp removal({:light, id, _light}), do: {:remove_light, id}
  defp removal(_change), do: nil

  defp effects(%{effects: wanted} = cache, asked) do
    case effects(asked) do
      ^wanted -> {[], cache}
      changed -> {[{:effects, changed}], %{cache | effects: changed}}
    end
  end

  defp tinted(cache, asked) do
    tint = tint(cache, asked)

    if tint == cache.tint,
      do: {[], cache},
      else: {[{:screen_tint, {0.0, 0.0, 0.0, tint}}], %{cache | tint: tint}}
  end

  defp tint(%{placed: nil}, _asked), do: 1.0
  defp tint(%{shown: shown}, asked) when shown != asked, do: @dimmed
  defp tint(%{swapped_at: nil}, _asked), do: 0.0
  defp tint(%{swapped_at: at}, _asked), do: max(1.0 - (now() - at) / @fade_ms, 0.0)

  defp figure(target, cache, %{scene: scene, character: %{} = posed}) when cache.shown == scene do
    case Loader.request(target, :character) do
      {:ready, placed} -> {posed_figure(placed.data, posed), %{cache | character: true}}
      _not_ready -> {[], cache}
    end
  end

  defp figure(target, %{character: true} = cache, _view) do
    {:ready, placed} = Loader.request(target, :character)
    {Enum.map(placed.data.skins, &{:remove_instance, elem(&1, 0)}), %{cache | character: false}}
  end

  defp figure(_target, cache, _view), do: {[], cache}

  defp posed_figure(%{skins: skins, instances: instances}, posed) do
    transform = %Transform{position: posed.position, rotation: posed.rotation}

    Enum.flat_map(skins, fn {id, skin} ->
      [
        {:instance, id, %{Map.fetch!(instances, id) | transform: transform}},
        {:pose, id, %Pose{bones: Map.fetch!(posed.skins, skin)}}
      ]
    end)
  end

  defp camera(
         %{shown: scene} = cache,
         %{scene: scene, camera: %{} = camera},
         {width, height},
         aspect
       ) do
    shot = %Camera{
      position: camera.position,
      rotation: camera.rotation,
      fov_y: 1.1,
      aspect: width * aspect / height,
      snap: true
    }

    {[shot], %{cache | camera: shot}}
  end

  defp camera(%{camera: nil} = cache, _view, _size, _aspect), do: {[], cache}
  defp camera(cache, _view, _size, _aspect), do: {[cache.camera], cache}

  defp now, do: System.monotonic_time(:millisecond)
end
