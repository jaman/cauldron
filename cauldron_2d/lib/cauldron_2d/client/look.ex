defmodule Cauldron2D.Client.Look do
  @moduledoc """
  The client's view of a world — projection, facing, tilt, heading, pitch — as a game's
  `c:Cauldron.Client.Game.look/0` starts it and the player's keys change it, the same
  in every front end.

      look = Cauldron2D.Client.Look.of(MyGame.Client)
      look = Cauldron2D.Client.Look.cycle(look)
      scene = MyGame.Client.scene(view, Cauldron.Client.View.given(look, menu, frame, options))

  A look is a map with `:projection`, `:projections`, `:facings`, `:facing`, `:tilt`,
  `:heading`, `:pitch` and `:mouse_look?`, and any key of the game's own.
  """

  alias Cauldron.Client.Game
  alias Cauldron2D.Projection.Iso

  @directions %{left: {-1, 0}, right: {1, 0}, up: {0, -1}, down: {0, 1}}
  @defaults %{
    projection: :top,
    projections: [:top, :iso, :first_person],
    facings: 4,
    facing: 0,
    tilt: 1.0,
    heading: 0.0,
    pitch: 0.0,
    mouse_look?: false
  }
  @turn :math.pi() / 12
  @tilt_step 0.125
  @pitch_step 0.1
  @turn_per_width 4.0
  @pitch_per_height 2.5
  @tilt_per_height 0.5

  @doc "The look before a game's `look/0` is applied."
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc "The look `game` starts in: the defaults with its `look/0` over them."
  @spec of(module()) :: map()
  def of(game), do: Map.merge(@defaults, Game.optional(game, :look, [], %{}))

  @doc "The zoom a world opens at for `game`: its look's `:zoom`, default `1`."
  @spec zoom(module()) :: number()
  def zoom(game), do: game |> Game.optional(:look, [], %{}) |> Map.get(:zoom, 1)

  @doc "The look at the next of its `:projections`."
  @spec cycle(map()) :: map()
  def cycle(%{projections: projections} = look) do
    index = Enum.find_index(projections, &(&1 == look.projection)) || 0
    %{look | projection: Enum.at(projections, rem(index + 1, length(projections)))}
  end

  @doc "The look turned: isometric and oblique by `amount` facings, mode 7 and first person by `amount` times 15°."
  @spec turn(map(), number()) :: map()
  def turn(%{projection: projection} = look, steps) when projection in [:iso, :oblique] do
    facings = facings(look)
    turned = look.facing + steps

    wrapped =
      if is_integer(turned),
        do: Integer.mod(turned, facings),
        else: :math.fmod(:math.fmod(turned, facings) + facings, facings)

    %{look | facing: wrapped}
  end

  def turn(%{projection: projection} = look, amount) when projection in [:mode7, :first_person],
    do: %{look | heading: look.heading + amount * @turn}

  def turn(look, _amount), do: look

  @doc "The look tilted by `amount` steps: the isometric diamond, or the eye's pitch in mode 7 and first person."
  @spec tilt(map(), number()) :: map()
  def tilt(%{projection: :iso} = look, amount),
    do: %{look | tilt: (look.tilt + amount * @tilt_step) |> min(1.5) |> max(0.5)}

  def tilt(%{projection: :mode7} = look, amount),
    do: %{look | pitch: (look.pitch + amount * @pitch_step) |> min(0.8) |> max(-0.8)}

  def tilt(%{projection: :first_person} = look, amount),
    do: %{look | pitch: (look.pitch + amount * @pitch_step) |> min(1.0) |> max(-1.0)}

  def tilt(look, _amount), do: look

  @doc """
  A direction on screen as a direction in the world: turned back by the isometric
  facing where the look is isometric with four facings, as it is everywhere else.
  """
  @spec world_direction(map(), {number(), number()}) :: {number(), number()}
  def world_direction(%{projection: :iso, facing: facing} = look, direction)
      when is_integer(facing),
      do: if(facings(look) == 4, do: turned(direction, rem(4 - facing, 4)), else: direction)

  def world_direction(_look, direction), do: direction

  defp turned(direction, 0), do: direction
  defp turned({x, y}, times), do: turned({y, -x}, times - 1)

  @doc """
  Whether a drag with the left button turns the view the look describes: it does in first
  person and mode 7, and in the isometric view when the game offers more than four
  facings. At four facings the view steps in quarters and there is nothing to drag to.

  Only the left button turns: a drag with any other belongs to the game, whose aim must
  stay where the player put it.
  """
  @spec turns_with_pointer?(map()) :: boolean()
  def turns_with_pointer?(%{projection: projection}) when projection in [:first_person, :mode7],
    do: true

  def turns_with_pointer?(%{projection: :iso} = look), do: facings(look) > 4
  def turns_with_pointer?(_look), do: false

  @doc """
  The look after the pointer moved `{dx, dy}` while turning it, in fractions of the
  picture's width and height: across the width turns the view by #{@turn_per_width}
  radians, and down the height pitches the eye by #{@pitch_per_height} (first person and
  mode 7) or flattens the isometric diamond by #{@tilt_per_height}.
  """
  @spec dragged(map(), {number(), number()}) :: map()
  def dragged(%{projection: :iso} = look, {dx, dy}) do
    count = facings(look)
    steps = dx * @turn_per_width * count / (2 * :math.pi())

    %{
      look
      | facing: :math.fmod(:math.fmod(look.facing + steps, count) + count, count),
        tilt: (look.tilt - dy * @tilt_per_height) |> min(1.5) |> max(0.5)
    }
  end

  def dragged(%{projection: :mode7} = look, {dx, dy}),
    do: %{
      look
      | heading: look.heading + dx * @turn_per_width,
        pitch: (look.pitch - dy * @pitch_per_height) |> min(0.8) |> max(-0.8)
    }

  def dragged(look, {dx, dy}),
    do: %{
      look
      | heading: look.heading + dx * @turn_per_width,
        pitch: (look.pitch - dy * @pitch_per_height) |> min(1.0) |> max(-1.0)
    }

  @doc """
  The player's input as the world should see it for the look in view. A view that does
  not turn sends it as held: top-down always, and the oblique view at its default single
  facing. A view at one of four facings turns the four direction actions with it, and of
  the directions a stick holds keeps only the one pushed hardest.

  On a finer `facings` a quarter turn is no longer the step, so the directions go as held
  and the input carries `:heading` instead, as it does in first person and mode 7: a
  heading in radians with `0` along `+x`, along which the game walks `:up`, against which
  it walks `:down`, and across which it walks `:left` and `:right`. A game offering more
  than four facings must read `:heading`; pressing up then moves the same way across the
  picture however far the view has turned.
  """
  @spec steered(map(), map()) :: map()
  def steered(read, %{projection: :top}), do: read

  def steered(read, %{projection: projection, heading: heading})
      when projection in [:first_person, :mode7],
      do: Map.put(read, :heading, heading)

  def steered(read, %{projection: projection} = look) when projection in [:iso, :oblique] do
    case facings(look) do
      1 -> read
      4 -> quartered(read, look.facing)
      count -> Map.put(read, :heading, Iso.up(facing: look.facing, facings: count))
    end
  end

  def steered(read, _look), do: read

  defp quartered(read, facing) do
    held =
      MapSet.new(snapped(read), fn action ->
        case Map.fetch(@directions, action) do
          {:ok, screen} -> screen |> turned(rem(4 - facing, 4)) |> direction_action()
          :error -> action
        end
      end)

    %{read | held: held}
  end

  defp snapped(%{held: held, strength: strength}) do
    pushed = Map.take(strength, Map.keys(@directions))

    case Enum.max_by(pushed, &elem(&1, 1), fn -> nil end) do
      nil ->
        held

      {hardest, _} ->
        held |> MapSet.difference(MapSet.new(Map.keys(pushed))) |> MapSet.put(hardest)
    end
  end

  defp snapped(%{held: held}), do: held

  defp direction_action(direction) do
    {action, _} = Enum.find(@directions, fn {_, screen} -> screen == direction end)
    action
  end

  @doc "How many facings make a full turn in the look's projection."
  @spec facings(map()) :: pos_integer()
  def facings(%{projection: projection} = look) do
    case Map.get(look, :facings) do
      counts when is_map(counts) -> Map.get(counts, projection, fixed(projection))
      nil -> fixed(projection)
      count -> if projection == :oblique, do: fixed(projection), else: count
    end
  end

  defp fixed(:oblique), do: 1
  defp fixed(_projection), do: 4
end
