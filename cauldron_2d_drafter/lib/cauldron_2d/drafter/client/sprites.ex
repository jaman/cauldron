if Code.ensure_loaded?(CauldronGPU.Target) do
  defmodule Cauldron2D.Drafter.Client.Sprites do
    @moduledoc """
    Draw lists (`Cauldron2D.DrawList`) drawn by the graphics card, for a scene's `:gpu`
    function: each item becomes a `CauldronGPU.Sprite`, each picture a texture uploaded
    the first time it is drawn, and canvases are kept by name at the size last asked.

        {sprites, cache} = Sprites.sprites(cache, target, items, &MyGame.source/1)

        changes = [
          {:layers,
           [%CauldronGPU.SpriteLayer{clear: {0.0, 0.0, 0.0, 1.0}, view: {0, 0, 320, 200}, sprites: sprites}]}
        ]

    `source` is a function from an item's `:picture` to `{key, raster}` or `{key,
    raster, {left, top, width, height}}`, the part of `raster` drawn, or `nil` to skip the
    item. Pictures with the same `key` share a texture; when `key`'s raster differs from
    the one uploaded, it is uploaded again and the old texture released. Textures are
    nearest-sampled, clamped, and hold the raster's bytes as display values, so the card
    blends them as `Cauldron2D.Blend` does.

    Items are drawn in `Cauldron2D.DrawList.in_depth_order/1`. An item's `:blend`,
    `:alpha` and `:mode` become the sprite's `colour`, `alpha` and `mode`; a mode
    `{:gamemaker, mode}` is drawn as `mode`.
    """

    alias Cauldron2D.DrawList
    alias CauldronGPU.{Canvas, Handle, Sprite, Target, Texture}
    alias FrenchCurve.Raster

    @type key :: term()
    @type source ::
            (term() ->
               {key(), Raster.t()}
               | {key(), Raster.t(), {number(), number(), number(), number()}}
               | nil)
    @type t :: %__MODULE__{
            textures: %{key() => {Raster.t(), Handle.t()}},
            canvases: %{term() => {{pos_integer(), pos_integer()}, Handle.t()}}
          }

    defstruct textures: %{}, canvases: %{}

    @doc "An empty cache."
    @spec new() :: t()
    def new, do: %__MODULE__{}

    @doc "The sprites for `items`, uploading the pictures `target` does not have yet."
    @spec sprites(t(), Target.t(), [DrawList.item()], source()) :: {[Sprite.t()], t()}
    def sprites(%__MODULE__{} = cache, target, items, source) do
      items
      |> DrawList.in_depth_order()
      |> Enum.flat_map_reduce(cache, fn item, cache -> sprite(item, source, target, cache) end)
    end

    @doc """
    The canvas `name` at `size` `{width, height}`: the one kept when its size matches, else
    a new one, the old one released.
    """
    @spec canvas(t(), Target.t(), term(), {pos_integer(), pos_integer()}) :: {Handle.t(), t()}
    def canvas(%__MODULE__{} = cache, target, name, size) do
      case Map.get(cache.canvases, name) do
        {^size, handle} ->
          {handle, cache}

        kept ->
          release(target, kept)
          {width, height} = size
          handle = Target.canvas(target, %Canvas{width: width, height: height})
          {handle, %{cache | canvases: Map.put(cache.canvases, name, {size, handle})}}
      end
    end

    @doc "`{r, g, b, a}` bytes as the 0 to 1 colour a layer's `clear` takes."
    @spec colour({byte(), byte(), byte(), byte()}) :: {float(), float(), float(), float()}
    def colour({red, green, blue, alpha}), do: {red / 255, green / 255, blue / 255, alpha / 255}

    defp sprite(item, source, target, cache) do
      case source.(item.picture) do
        nil -> {[], cache}
        {key, raster} -> placed(item, key, raster, nil, target, cache)
        {key, raster, rect} -> placed(item, key, raster, rect, target, cache)
      end
    end

    defp placed(_item, _key, nil, _rect, _target, cache), do: {[], cache}

    defp placed(item, key, raster, rect, target, cache) do
      {texture, cache} = texture(cache, target, key, raster)
      {red, green, blue} = Map.get(item, :blend, {255, 255, 255})

      sprite = %Sprite{
        texture: texture,
        source: rect,
        position: item.position,
        origin: Map.get(item, :origin, {0, 0}),
        scale: Map.get(item, :scale, {1, 1}),
        angle: Map.get(item, :angle, 0),
        colour: {red / 255, green / 255, blue / 255},
        alpha: item |> Map.get(:alpha, 1.0) |> max(0.0) |> min(1.0),
        mode: mode(Map.get(item, :mode, :over))
      }

      {[sprite], cache}
    end

    defp texture(cache, target, key, raster) do
      case Map.get(cache.textures, key) do
        {^raster, handle} ->
          {handle, cache}

        kept ->
          release(target, kept)
          handle = Target.texture(target, uploaded(raster))
          {handle, %{cache | textures: Map.put(cache.textures, key, {raster, handle})}}
      end
    end

    defp uploaded(%Raster{width: width, height: height} = raster) do
      %Texture{
        width: width,
        height: height,
        pixels: Raster.to_rgba_binary(raster),
        format: :linear,
        filter: :nearest,
        wrap: :clamp,
        mipmaps: false
      }
    end

    defp release(_target, nil), do: :ok
    defp release(target, {_kept, handle}), do: Target.release(target, handle)

    defp mode({:gamemaker, mode}), do: mode
    defp mode(mode), do: mode
  end
end
