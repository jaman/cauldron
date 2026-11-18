defmodule Vale.Picture do
  @moduledoc """
  The vale's `:gpu` (`Cauldron.Client.Game`): what the graphics card draws for a view
  (`Vale.Game.view/2`).

      gpu = Vale.Picture.gpu(view)
      {changes, cache} = gpu.(target, nil, {960, 540}, 1.0)

  The first frame uploads the looks (`Vale.Looks`), stands the land's backdrop panels and
  uploads the walker (`Vale.Figure`). Every frame after keeps the cells round the walker
  drawn (`Cauldron3D.Scene.OpenWorld.Shown`), two cells a frame at most; sends the light
  of the hour when it has changed; places and poses the walker; tells the grass where it
  stands; and sends the camera. The walker and the camera are both placed without easing
  from the tick before, so the walker holds still against the camera.
  """

  alias Cauldron3D.Scene.{Camera, Instance, OpenWorld, Pose, Target, Transform}
  alias Cauldron3D.Scene.OpenWorld.Shown
  alias Vale.{Figure, Land, Looks}

  @panel_id 800_000
  @cells_a_frame 2

  @doc "The scene's `:gpu` function for `view`."
  @spec gpu(map()) :: (Target.t(), map() | nil, {pos_integer(), pos_integer()}, number() ->
                         {list(), map()})
  def gpu(view) do
    fn target, cache, size, aspect ->
      {first, cache} = started(target, cache)
      {land, cache} = land(target, cache, view)
      {light, cache} = light(cache, view.hour)
      {camera, cache} = camera(cache, view, size, aspect)
      {first ++ land ++ light ++ walker(cache, view) ++ camera, cache}
    end
  end

  defp started(_target, %{} = cache), do: {[], cache}

  defp started(target, nil) do
    looks = Looks.upload(target)
    map = Land.map()

    panels =
      for {panel, index} <- Enum.with_index(map.panels) do
        mesh = Target.mesh(target, OpenWorld.panel(panel))
        {:instance, @panel_id + index, %Instance{mesh: mesh, materials: [looks.range], shadows: false}}
      end

    figure =
      case Figure.upload(target) do
        {:ok, placed} -> placed
        {:error, _reason} -> nil
      end

    cache = %{
      looks: looks,
      map: map,
      shown: Shown.new(Looks.shown(looks)),
      figure: figure,
      hour: nil,
      camera: nil
    }

    {panels, cache}
  end

  defp land(target, cache, view) do
    eye = if view.walker, do: view.walker.point, else: Land.start()
    {changes, shown} = Shown.frame(cache.shown, target, cache.map, [eye], @cells_a_frame)
    {changes, %{cache | shown: shown}}
  end

  defp light(%{hour: shown} = cache, hour) when is_number(shown) and abs(shown - hour) < 0.02,
    do: {[], cache}

  defp light(cache, hour) do
    {environment, sun} = Looks.sky(hour)
    {[environment, {:light, 1, sun}], %{cache | hour: hour}}
  end

  defp walker(%{figure: %{skins: skins, instances: instances}}, %{posed: %{} = posed, walker: walker}) do
    transform = %Transform{
      position: posed.position,
      rotation: posed.rotation,
      scale: {posed.scale, posed.scale, posed.scale}
    }

    {x, y} = walker.point

    figure =
      Enum.flat_map(skins, fn {id, skin} ->
        [
          {:instance, id, %{Map.fetch!(instances, id) | transform: transform, snap: true}},
          {:pose, id, %Pose{bones: Map.fetch!(posed.skins, skin)}}
        ]
      end)

    figure ++ [{:pushers, [{x, walker.height, y, 0.7}]}]
  end

  defp walker(_cache, _view), do: []

  defp camera(cache, %{camera: %{} = camera}, {width, height}, aspect) do
    shot = %Camera{
      position: camera.position,
      rotation: camera.rotation,
      fov_y: 1.05,
      far: 1400.0,
      aspect: width * aspect / height,
      snap: true
    }

    {[shot], %{cache | camera: shot}}
  end

  defp camera(%{camera: nil} = cache, _view, _size, _aspect), do: {[], cache}
  defp camera(cache, _view, _size, _aspect), do: {[cache.camera], cache}
end
