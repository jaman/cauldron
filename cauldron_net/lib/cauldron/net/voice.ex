defmodule Cauldron.Net.Voice do
  @moduledoc """
  Voice calls between a game's browser players. It is off until the game calls `open/1`.

      Cauldron.Net.Voice.open(relay: true, turn: {:cloudflare, key_id, api_token})

  ## Agreeing to talk

  A call needs both players: one asks (`call/2`), the other agrees (`accept/2`) or refuses
  (`decline/2`). Until then nothing of either player's sound or address reaches the other.
  Either ends the call with `hang_up/2`, and a player who leaves ends all of theirs. Asking
  someone who has already asked you agrees to their call. `mute/2` turns a player's microphone
  off and on. These work from Elixir, such as from a game's own menu, and from the browser
  (`voice.js`); `state/1` is what a player's calls stand at, for showing them.

  ## How the sound goes

  The browsers send their sound to each other directly (WebRTC), choosing the shortest route that
  works:

    1. their own network, always tried
    2. across the internet, when `:stun` names STUN servers
    3. through a TURN server, when `:turn` names one (`Cauldron.Net.Voice.Ice`)
    4. through this server's channel, when `:relay` is `true` and no route above has connected
       within `:wait` milliseconds, or the connection fails. The browser then encodes its
       microphone as Opus (WebCodecs) and sends it over the channel it already has open

  The browser switches back to a direct route if one connects later.

  ## Options

    * `:relay` — whether calls may go through this server. Default `false`
    * `:stun` — STUN URLs. Default `[]`
    * `:turn` — a TURN server, as `Cauldron.Net.Voice.Ice` describes. Default `nil`
    * `:wait` — milliseconds a call waits for a direct route before using the server. Default `5000`

  ## In the browser

  A page whose socket routes `"voice"` to `Cauldron.Net.Voice.Channel` (`Cauldron.Net.Socket`'s
  `voice: true`) and loads `voice.js` gets `window.cauldronVoice`, as `voice.js` describes.
  """

  alias Cauldron.Net.Voice.{Calls, Ice}

  @type name :: String.t()
  @type option :: {:relay, boolean()} | {:stun, [String.t()]} | {:turn, Ice.turn()} | {:wait, pos_integer()}
  @type settings :: %{relay: boolean(), stun: [String.t()], turn: Ice.turn(), wait: pos_integer()}

  @doc "Turns voice on with `options`, or changes its options."
  @spec open([option()]) :: :ok
  def open(options \\ []) do
    :persistent_term.put(__MODULE__, %{
      relay: Keyword.get(options, :relay, false),
      stun: Keyword.get(options, :stun, []),
      turn: Keyword.get(options, :turn),
      wait: Keyword.get(options, :wait, 5_000)
    })
  end

  @doc "Turns voice off: browsers can no longer join the voice channel. Calls already set up carry on."
  @spec close() :: :ok
  def close do
    :persistent_term.erase(__MODULE__)
    :ok
  end

  @doc "Whether voice is on."
  @spec open?() :: boolean()
  def open?, do: settings() != nil

  @doc "The options voice is on with, or `nil` when it is off."
  @spec settings() :: settings() | nil
  def settings, do: :persistent_term.get(__MODULE__, nil)

  @doc "What `name`'s browser is told when it joins: the STUN and TURN servers, whether the server relays, and the wait."
  @spec browser(name()) :: %{ice: [Ice.server()], relay: boolean(), wait: pos_integer()}
  def browser(name) do
    settings = settings()
    %{ice: Ice.servers(settings, name), relay: settings.relay, wait: settings.wait}
  end

  @doc "`from` asks to talk to `to`. `{:error, :unavailable}` when `to` has no browser on the voice channel."
  @spec call(name(), name()) :: :ok | {:error, :unavailable | :self}
  defdelegate call(from, to), to: Calls

  @doc "`name` agrees to talk to `caller`, who asked first."
  @spec accept(name(), name()) :: :ok | {:error, :not_asked}
  defdelegate accept(name, caller), to: Calls

  @doc "`name` refuses `caller`'s call."
  @spec decline(name(), name()) :: :ok
  defdelegate decline(name, caller), to: Calls

  @doc "Ends `name`'s call with `other`, or withdraws or refuses an unanswered one between them."
  @spec hang_up(name(), name()) :: :ok
  defdelegate hang_up(name, other), to: Calls

  @doc "Turns `name`'s microphone off (`true`) or on (`false`)."
  @spec mute(name(), boolean()) :: :ok
  defdelegate mute(name, muted), to: Calls

  @doc "`name`'s calls: `%{incoming: [name], outgoing: [name], talking: [name], muted: boolean, present: boolean}`."
  @spec state(name()) :: Calls.state()
  defdelegate state(name), to: Calls
end
