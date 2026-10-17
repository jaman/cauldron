defmodule CauldronGPU.Host.Record do
  @moduledoc """
  The scene a host renderer holds, rebuilt from the changes sent to it: meshes, textures
  and materials, instances with their latest transform and pose, lights, camera,
  environment, effects, light styles, overlay, screen tint and 2D layers. `replay/1` lists the changes that give a new renderer the same
  scene.

  A released mesh, texture or material stays while a kept instance, pose, material,
  overlay or layer names it, and is replayed followed by its drop.
  """

  alias CauldronGPU.{
    Camera,
    ColumnLayer,
    Environment,
    Handle,
    Instance,
    Material,
    Pose,
    Sprite,
    SpriteLayer,
    Stream
  }

  @type key :: {Handle.kind(), Stream.id()}
  @type t :: %__MODULE__{
          resources: %{key() => Stream.change()},
          released: MapSet.t(key()),
          instances: %{Stream.id() => Instance.t()},
          poses: %{Stream.id() => Pose.t()},
          lights: %{Stream.id() => CauldronGPU.Light.t()},
          camera: Camera.t() | nil,
          environment: Environment.t() | nil,
          effects: [atom()] | nil,
          light_styles: [number() | {number(), number(), number()}] | nil,
          overlay: Stream.change() | nil,
          screen_tint: Stream.change() | nil,
          layers: Stream.change() | nil
        }

  defstruct resources: %{},
            released: MapSet.new(),
            instances: %{},
            poses: %{},
            lights: %{},
            camera: nil,
            environment: nil,
            effects: nil,
            light_styles: nil,
            overlay: nil,
            screen_tint: nil,
            layers: nil

  @kind_order %{texture: 0, material: 1, mesh: 2}

  @doc "An empty record."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "The record after `changes` were sent."
  @spec apply_changes(t(), [Stream.change()]) :: t()
  def apply_changes(record, changes), do: changes |> Enum.reduce(record, &change/2) |> prune()

  @doc "The record after the object `kind`/`id` was released."
  @spec release(t(), Handle.kind(), Stream.id()) :: t()
  def release(record, kind, id),
    do: prune(%{record | released: MapSet.put(record.released, {kind, id})})

  @doc "The changes that rebuild the recorded scene in a renderer that has none of it."
  @spec replay(t()) :: [Stream.change()]
  def replay(%__MODULE__{} = record) do
    resources =
      record.resources
      |> Enum.sort_by(fn {{kind, id}, _change} -> {@kind_order[kind], id} end)
      |> Enum.map(fn {_key, change} -> change end)

    drops = for {kind, id} <- record.released, do: {drop(kind), id}
    instances = for {id, instance} <- record.instances, do: {:instance, id, instance}
    poses = for {id, pose} <- record.poses, do: {:pose, id, pose}
    lights = for {id, light} <- record.lights, do: {:light, id, light}

    settings =
      Enum.reject(
        [
          record.camera,
          record.environment,
          record.effects && {:effects, record.effects},
          record.light_styles && {:light_styles, record.light_styles},
          record.overlay,
          record.screen_tint,
          record.layers
        ],
        &is_nil/1
      )

    resources ++ instances ++ poses ++ lights ++ settings ++ drops
  end

  defp change(:tick, record), do: record
  defp change({:mesh, id, _mesh} = change, record), do: put_resource(record, {:mesh, id}, change)

  defp change({:texture, id, _texture} = change, record),
    do: put_resource(record, {:texture, id}, change)

  defp change({:canvas, id, _canvas} = change, record),
    do: put_resource(record, {:texture, id}, change)

  defp change({:material, id, _material} = change, record),
    do: put_resource(record, {:material, id}, change)

  defp change({:drop_mesh, id}, record), do: mark_released(record, {:mesh, id})
  defp change({:drop_texture, id}, record), do: mark_released(record, {:texture, id})
  defp change({:drop_material, id}, record), do: mark_released(record, {:material, id})

  defp change({:instance, id, instance}, record),
    do: %{record | instances: Map.put(record.instances, id, instance)}

  defp change({:move, id, transform}, record), do: move(record, id, transform)
  defp change({:move, id, transform, _opts}, record), do: move(record, id, transform)

  defp change({:pose, id, pose}, record) when is_map_key(record.instances, id),
    do: %{record | poses: Map.put(record.poses, id, pose)}

  defp change({:pose, _id, _pose}, record), do: record

  defp change({:remove_instance, id}, record) do
    %{record | instances: Map.delete(record.instances, id), poses: Map.delete(record.poses, id)}
  end

  defp change({:light, id, light}, record),
    do: %{record | lights: Map.put(record.lights, id, light)}

  defp change({:remove_light, id}, record), do: %{record | lights: Map.delete(record.lights, id)}
  defp change(%Camera{} = camera, record), do: %{record | camera: camera}
  defp change(%Environment{} = environment, record), do: %{record | environment: environment}
  defp change({:effects, effects}, record), do: %{record | effects: effects}
  defp change({:light_styles, scales}, record), do: %{record | light_styles: scales}
  defp change({:overlay, _texture} = change, record), do: %{record | overlay: change}
  defp change({:overlay, _texture, _mode} = change, record), do: %{record | overlay: change}
  defp change({:screen_tint, _tint} = change, record), do: %{record | screen_tint: change}
  defp change({:layers, _layers} = change, record), do: %{record | layers: change}

  defp put_resource(record, key, change) do
    %{
      record
      | resources: Map.put(record.resources, key, change),
        released: MapSet.delete(record.released, key)
    }
  end

  defp mark_released(record, key) do
    if Map.has_key?(record.resources, key),
      do: %{record | released: MapSet.put(record.released, key)},
      else: record
  end

  defp move(record, id, transform) do
    case record.instances do
      %{^id => instance} ->
        %{record | instances: Map.put(record.instances, id, %{instance | transform: transform})}

      _ ->
        record
    end
  end

  defp prune(%__MODULE__{released: released} = record) do
    if MapSet.size(released) == 0, do: record, else: drop_unused(record)
  end

  defp drop_unused(record) do
    used = used_objects(record)
    unused = Enum.reject(record.released, &MapSet.member?(used, &1))

    %{
      record
      | resources: Map.drop(record.resources, unused),
        released: MapSet.difference(record.released, MapSet.new(unused))
    }
  end

  defp used_objects(record) do
    instance_keys =
      Enum.flat_map(record.instances, fn {_id, %Instance{} = instance} ->
        [handle_key(instance.mesh) | Enum.map(instance.materials, &handle_key/1)]
      end)

    pose_keys =
      for {_id, %Pose{blend_to: %Handle{} = mesh}} <- record.poses, do: handle_key(mesh)

    used = MapSet.new(instance_keys ++ pose_keys)

    texture_keys =
      for {{:material, _id} = key, {:material, _, %Material{} = material}} <- record.resources,
          MapSet.member?(used, key) or not MapSet.member?(record.released, key),
          texture <- Material.textures(material),
          do: handle_key(texture)

    overlay_keys =
      case record.overlay do
        {:overlay, %Handle{} = texture} -> [handle_key(texture)]
        {:overlay, %Handle{} = texture, _mode} -> [handle_key(texture)]
        _ -> []
      end

    MapSet.union(used, MapSet.new(texture_keys ++ overlay_keys ++ layer_keys(record.layers)))
  end

  defp layer_keys({:layers, layers}), do: Enum.flat_map(layers, &layer_handles/1)
  defp layer_keys(nil), do: []

  defp layer_handles(%SpriteLayer{target: target, sprites: sprites}),
    do:
      target_keys(target) ++
        Enum.map(sprites, fn %Sprite{texture: texture} -> handle_key(texture) end)

  defp layer_handles(%ColumnLayer{target: target, source: source}),
    do: [handle_key(source) | target_keys(target)]

  defp target_keys(:frame), do: []
  defp target_keys(%Handle{} = canvas), do: [handle_key(canvas)]

  defp handle_key(%Handle{kind: kind, id: id}), do: {kind, id}
  defp handle_key(nil), do: nil

  defp drop(:mesh), do: :drop_mesh
  defp drop(:texture), do: :drop_texture
  defp drop(:material), do: :drop_material
end
