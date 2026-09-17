defmodule Cauldron2D.Net.Audio do
  @moduledoc """
  The server's sound policy: what every session's sound costs it.

      Cauldron2D.Net.Audio.set(music: :arena, sfx: :personal)
      Cauldron2D.Net.Audio.set(music: :dynamic)
      Cauldron2D.Net.Audio.policy()

  ## Music

    * `:personal` — every session synthesises its own music, cued by its own view.
      Default
    * `:arena` — one stage a world (`Cauldron2D.Net.Audio.Shared`), cued by the world's
      state, its music mixed under each session's own effects
    * `:static` — every session plays the first section it is cued and no other,
      rendered once a node and looped (`Cauldron2D.Audio` with `static_music: true`):
      the music is a resource, not a performance, and costs a copy a chunk
    * `:dynamic` — personal, at a rate the node's load sets: 44 100 Hz while the
      schedulers are under 30% busy, 22 050 Hz once they pass 60%, each held for
      thirty seconds at least. A session whose rate changes restarts its audio and
      tells its browser
    * `:off` — no music

  ## Effects

    * `:personal` — each session's own, placed against its listener. Default
    * `:off` — none

  A session that asks for no sound (join param `audio: false`) gets none whatever the
  policy. `:rate` (default 44 100) caps the rate any session gets; a session asking
  for less gets what it asked. `format/1` answers what a session gets for what it
  asked; `subscribe/0` has the calling process told `{:cauldron_audio_rate, rate}`
  when the rate changes.
  """

  alias Cauldron2D.Net.Audio.Governor

  @type music :: :personal | :arena | :dynamic | :static | :off
  @type sfx :: :personal | :off
  @type policy :: %{music: music(), sfx: sfx(), rate: pos_integer()}
  @type format :: %{rate: pos_integer(), channels: 1 | 2} | :off

  @key {__MODULE__, :policy}
  @rate_key {__MODULE__, :rate}
  @registry Cauldron2D.Net.Audio.Registry
  @supervisor Cauldron2D.Net.Audio.Supervisor

  @doc false
  def child_specs do
    [
      {Registry, keys: :duplicate, name: @registry},
      {DynamicSupervisor, strategy: :one_for_one, name: @supervisor},
      Governor
    ]
  end

  @doc "Set the policy: `:music`, `:sfx` and `:rate`; what is not given goes back to its default."
  @spec set(keyword()) :: :ok
  def set(opts) do
    music = Keyword.get(opts, :music, :personal)
    sfx = Keyword.get(opts, :sfx, :personal)
    rate = Keyword.get(opts, :rate, 44_100)

    unless music in [:personal, :arena, :dynamic, :static, :off],
      do: raise(ArgumentError, "music is one of :personal, :arena, :dynamic, :static, :off")

    unless sfx in [:personal, :off], do: raise(ArgumentError, "sfx is :personal or :off")
    :persistent_term.put(@key, %{music: music, sfx: sfx, rate: rate})
    :persistent_term.put(@rate_key, rate)
    Governor.policy_changed()
    :ok
  end

  @doc "The policy in force."
  @spec policy() :: policy()
  def policy, do: :persistent_term.get(@key, %{music: :personal, sfx: :personal, rate: 44_100})

  @doc "The rate sessions get now: the policy's, lowered by the governor under `:dynamic` music."
  @spec rate() :: pos_integer()
  def rate, do: :persistent_term.get(@rate_key, 44_100)

  @doc false
  def lower_rate(rate) do
    :persistent_term.put(@rate_key, rate)

    Registry.dispatch(@registry, :rate, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:cauldron_audio_rate, rate})
    end)

    :ok
  end

  @doc "What a session gets for the format it asked, `:off` for no sound asked."
  @spec format(%{rate: pos_integer(), channels: 1 | 2} | :off | nil) :: format()
  def format(:off), do: :off
  def format(nil), do: %{rate: rate(), channels: 2}

  def format(%{rate: asked, channels: channels}),
    do: %{rate: min(asked, rate()), channels: channels}

  @doc "Have the calling process told `{:cauldron_audio_rate, rate}` whenever the rate changes."
  @spec subscribe() :: :ok
  def subscribe do
    Registry.register(@registry, :rate, nil)
    :ok
  end

  @doc false
  def registry, do: @registry

  @doc false
  def supervisor, do: @supervisor
end
