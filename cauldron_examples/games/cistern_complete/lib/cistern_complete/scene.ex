defmodule CisternComplete.Scene do
  @moduledoc """
  A keeper's square drawn from their view: the dusk backdrop, the cobbles and the grate,
  the Squall in its mood, the rings where rain will land, the keeper with the yoke and
  jars (a full one brimming), the rain and hail, splashes, lightning's warning column
  and its bolt, and over it all the hud (`CisternComplete.Hud`).

  `pixel/2` places a point of the square on the pane, for anything drawn fixed to the
  pane that belongs at a place in the square: the `+12` of a pour rises from the
  keeper.
  """

  alias Cauldron2D.Parallax
  alias CisternComplete.{Hud, Yoke}

  @tile 16
  @focus {8.0, 6.0}
  @ground 11
  @row 10
  @squall_row 1
  @head 8.25
  @yoke_row 9.0625

  @doc "The scene for `view`, as `Cauldron.Client.Game.scene/1` returns it."
  @spec build(map(), map()) :: map()
  def build(%{me: nil, size: size}, _look) do
    %{focus: @focus, bounds: size, cell: &cell/1, movers: [], layers: layers()}
  end

  def build(%{me: me, size: size} = view, look) do
    %{
      focus: @focus,
      bounds: size,
      cell: &cell/1,
      layers: layers(),
      movers:
        [grate()] ++
          rings(me) ++
          squall(me) ++
          keeper(me, view.capacity) ++ rain(me) ++ splashes(me) ++ bolts(me),
      volumes: flicker(me),
      screen: Hud.items(view, look)
    }
  end

  @doc "The pane pixel, from the pane's centre, of point `{x, y}` of the square."
  @spec pixel({number(), number()}) :: {number(), number()}
  def pixel({x, y}) do
    {fx, fy} = @focus
    {(x - fx) * @tile, (y - fy) * @tile}
  end

  @doc "The square's tiles: cobbles along the bottom, nothing above them but the backdrop."
  @spec cell({integer(), integer()}) :: {atom(), [], nil} | :void
  def cell({_x, y}) when y >= @ground, do: {:ground, [], nil}
  def cell(_at), do: :void

  defp layers do
    [
      Parallax.panorama(
        name: :backdrop,
        art: :backdrop,
        size: {16, 11},
        at: {0, 0},
        wrap: :none,
        factor: {1.0, 1.0},
        void: :opaque
      )
    ]
  end

  defp grate, do: {:grate, {7.5, @ground}}

  defp rings(me) do
    for drop <- me.drops, do: {ring(drop.y), {drop.x - 0.5, @ground}}
  end

  defp ring(y) when y < 5, do: :shadow_far
  defp ring(y) when y < 8, do: :shadow_mid
  defp ring(_y), do: :shadow_near

  defp squall(%{squall: squall, clock: clock}) do
    art =
      case squall.mood do
        :grin -> :squall_grin
        :sulk -> :squall_sulk
        :gust -> :squall_gust
        :drizzle -> :squall
      end

    bob = :math.sin(clock * 2.4) * 0.12
    [{art, {squall.x - 0.5, @squall_row + bob}}]
  end

  defp keeper(me, capacity) do
    tint = if me.robot?, do: %{tint: :robot}, else: %{}
    jars = Yoke.jars(me.yoke)
    centre = me.yoke.centre

    [{:keeper, {centre - 0.5, @row}, nil, tint}] ++
      yoke(jars, centre, tint) ++ Enum.flat_map(jars, &jar(&1, me, capacity, tint))
  end

  defp yoke(jars, centre, tint) do
    if Enum.any?(jars, &(&1.slot != :head)),
      do: [{:yoke, {centre - 0.5, @yoke_row}, nil, tint}],
      else: []
  end

  defp jar(jar, me, capacity, tint) do
    y = if jar.slot == :head, do: @head, else: @row
    tilted = if me.pouring > 0, do: y + 0.15, else: y
    brim = if jar.fill >= capacity, do: [{:brim, {jar.x, tilted}}], else: []
    [{:jar, {jar.x, tilted}, nil, tint} | brim]
  end

  defp rain(me) do
    for drop <- me.drops do
      art = if drop.kind == :hail, do: :hail, else: :drop
      {art, {drop.x - 0.5, drop.y}}
    end
  end

  defp splashes(me) do
    for splash <- me.splashes do
      frame = Enum.at([:splash_1, :splash_2, :splash_3], Cauldron.Effects.frame(splash, 3, 7.5))
      {frame, {splash.x - 0.5, @row}}
    end
  end

  defp bolts(me) do
    for bolt <- me.bolts, y <- 2..@row, do: {:bolt, {bolt.x - 0.5, y / 1}, nil, %{tint: :flash}}
  end

  defp flicker(%{strike: nil}), do: []

  defp flicker(%{strike: %{x: x}, clock: clock}) do
    strength = if rem(trunc(clock * 12), 2) == 0, do: 0.35, else: 0.15

    [
      %{
        at: {x, 0.0},
        shape: {:beam, 12.0, 1.0, :math.pi() / 2, 3.0},
        colour: {255, 248, 200},
        strength: strength,
        falloff: :flat
      }
    ]
  end
end
