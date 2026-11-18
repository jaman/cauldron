defmodule Cauldron.Client.Party do
  @moduledoc """
  The players a client plays on one machine: the player's own `Cauldron.Client.Controls`,
  the further seats of the game's `c:Cauldron.Client.Game.local_seats/1`
  (`Cauldron.Client.Seats`), and which of them each controller plays
  (`Cauldron.Client.Controllers`, by the settings' `:pads`).

      party = Cauldron.Client.Party.new(MyGame.Client, settings, props)
      party = Cauldron.Client.Party.seat(party, world, "alice", join_props)
      party = Cauldron.Client.Party.key(party, :left, [], true, now)
      party = Cauldron.Client.Party.event(party, {:mouse, %{type: :move, x: 3, y: 4}}, now)
      {party, routed} = Cauldron.Client.Party.pad(party, event)
      party = Cauldron.Client.Party.send_seats(party, world, look)

  Every key and mouse event reaches the player and every seat, a key press counting
  where each one's keymap binds it (`Cauldron.Client.Seats.keyed?/2`); a
  controller's events reach the one player its slot names, `routed` saying which
  (`:own`, `:seat` or `:none`). The player's own input is `state/1` with the device
  they last played with and their keymap; the seats send theirs themselves
  (`send_seats/3`). The seats read keys with the player's input options, whether keys
  come with their releases among them.
  """

  alias Cauldron.Client.{Controllers, Controls, Game, Seats, View}
  alias Cauldron.Input

  @type t :: %__MODULE__{}

  defstruct [
    :game,
    :controls,
    :settings,
    :props,
    seats: [],
    controllers: nil,
    slots: %{},
    device: :keyboard
  ]

  @doc """
  The player alone, for `game` with their `settings` and the client's `props`; `opts`
  are `Cauldron.Client.Controls.new/4`'s.
  """
  @spec new(module(), map(), map(), keyword()) :: t()
  def new(game, settings, props \\ %{}, opts \\ []),
    do: %__MODULE__{
      game: game,
      settings: settings,
      props: props,
      controls: Controls.new(game, settings, props, opts),
      controllers: Controllers.new()
    }

  @doc """
  The party with the game's local seats joined to `world` as `"<username> 2"` and on,
  each with `join_props`, its own keymap and the player's padmap
  (`Cauldron.Client.Controls.padmap/2`) (`Cauldron.Client.Seats.join/6`).
  """
  @spec seat(t(), GenServer.server(), String.t(), map()) :: t()
  def seat(party, world, username, join_props) do
    keymaps = keymaps(party)

    seats =
      Seats.join(
        world,
        username,
        join_props,
        keymaps,
        Controls.padmap(party.game, party.props),
        party.controls.options
      )

    %{party | seats: seats} |> assigned()
  end

  @doc "Every seat out of `world`, the controllers that played them assigned again."
  @spec unseat(t(), GenServer.server()) :: t()
  def unseat(party, world) do
    Seats.leave(party.seats, world)
    drop_seats(party)
  end

  @doc "Every seat dropped without telling the world, for a world that is gone; the controllers that played them assigned again."
  @spec drop_seats(t()) :: t()
  def drop_seats(party), do: assigned(%{party | seats: []})

  @doc "A key pressed or released, for the player and every seat."
  @spec key(t(), atom(), [atom()], boolean(), integer()) :: t()
  def key(party, key, mods, true, now), do: event(party, {:key_down, key, mods}, now)
  def key(party, key, mods, false, now), do: event(party, {:key_up, key, mods}, now)

  @doc """
  A raw key or mouse event (`Cauldron.Client.Controls.event/3`), for the player and
  every seat; a key press the player's keymap binds makes the keyboard the player's
  device.
  """
  @spec event(t(), term(), integer()) :: t()
  def event(party, event, now) do
    device = if Seats.keyed?(party.controls.input, event), do: :keyboard, else: party.device

    %{
      party
      | controls: Controls.event(party.controls, event, now),
        seats: Seats.key(party.seats, event, now),
        device: device
    }
  end

  @doc """
  A `Gamepad.Wire` event: a controller connecting or going is noted and the controllers
  assigned again; any other event goes to the player its slot names — `:own`, a `:seat`,
  or `:none` for a controller that plays no one.
  """
  @spec pad(t(), map()) :: {t(), :own | :seat | :none}
  def pad(party, %{type: :connected, device: device, name: name}),
    do:
      {assigned(%{party | controllers: Controllers.connect(party.controllers, device, name)}),
       :none}

  def pad(party, %{type: :disconnected, device: device} = event) do
    party = released(party, Map.get(party.slots, device), event)
    {assigned(%{party | controllers: Controllers.disconnect(party.controllers, device)}), :none}
  end

  def pad(party, %{device: device} = event) do
    party =
      if Controllers.known?(party.controllers, device),
        do: party,
        else: assigned(%{party | controllers: Controllers.seen(party.controllers, device)})

    case Map.get(party.slots, device) do
      0 ->
        name = Controllers.name(party.controllers, device)

        {%{
           party
           | controls: Controls.pad(party.controls, event),
             device: Seats.pad_device(party.device, event, name)
         }, :own}

      nil ->
        {party, :none}

      slot ->
        name = Controllers.name(party.controllers, device)
        {%{party | seats: Seats.controller(party.seats, slot - 1, event, name)}, :seat}
    end
  end

  @doc "The party with the player's controls changed by `fun`."
  @spec controls(t(), (Controls.t() -> Controls.t())) :: t()
  def controls(party, fun), do: %{party | controls: fun.(party.controls)}

  @doc """
  The party playing with new settings: the player's keys and input options from them
  (`Cauldron.Client.Controls.settings/3`), each seat's keys from the game's
  `local_seats/1` for them, the controllers assigned by their `:pads`; everything held
  let go.
  """
  @spec settings(t(), map()) :: t()
  def settings(party, settings) do
    party = %{party | settings: settings}
    controls = Controls.settings(party.controls, party.game, settings)

    %{
      party
      | controls: controls,
        seats: Seats.release(party.seats, keymaps(party), controls.options)
    }
    |> assigned()
  end

  @doc "Everyone in the party letting go of everything."
  @spec let_go(t()) :: t()
  def let_go(party),
    do: %{
      party
      | controls: Controls.let_go(party.controls),
        seats: Seats.release(party.seats, keymaps(party), party.controls.options)
    }

  @doc "Taps and gestures whose time is up by `now` let go, the player's and every seat's."
  @spec expire(t(), integer()) :: t()
  def expire(party, now),
    do: %{
      party
      | controls: Controls.expire(party.controls, now),
        seats: Seats.expire(party.seats, now)
    }

  @doc "The player's own input: `Cauldron.Client.Controls.state/1` with `:device` and `:keys`, their keymap."
  @spec state(t()) :: map()
  def state(party),
    do:
      Map.merge(Controls.state(party.controls), %{
        device: party.device,
        keys: Input.keymap(party.controls.input)
      })

  @doc "Each seat's input sent to `world` where it changed, steered for `look` by the game's view (`c:Cauldron.Client.View.steered/2`)."
  @spec send_seats(t(), GenServer.server(), map()) :: t()
  def send_seats(party, world, look),
    do: %{
      party
      | seats: Seats.send_input(party.seats, world, &View.of(party.game).steered(&1, look))
    }

  @doc "The connected controllers, each `%{name, player}`, for a settings screen."
  @spec listed(t()) :: [%{name: String.t(), player: pos_integer() | nil}]
  def listed(party), do: Controllers.listed(party.controllers, party.slots)

  defp keymaps(party),
    do:
      Game.optional(
        party.game,
        :local_seats,
        [Map.put(party.props, :settings, party.settings)],
        []
      )

  defp assigned(party) do
    slots =
      Controllers.slots(
        party.controllers,
        Map.get(party.settings, :pads, %{}),
        1 + length(party.seats)
      )

    party =
      Enum.reduce(party.slots, party, fn {device, slot}, party ->
        if Map.get(slots, device) == slot,
          do: party,
          else: released(party, slot, %{type: :disconnected, device: device})
      end)

    %{party | slots: slots}
  end

  defp released(party, nil, _event), do: party
  defp released(party, 0, event), do: %{party | controls: Controls.pad(party.controls, event)}

  defp released(party, slot, event),
    do: %{party | seats: Seats.controller(party.seats, slot - 1, event)}
end
