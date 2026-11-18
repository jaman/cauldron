defmodule Cauldron.Paths do
  @moduledoc """
  Where a game keeps its files: one directory per game under each of the XDG base
  directories.

      Cauldron.Paths.config(:my_game, "alice.settings")
      #=> "~/.config/my_game/alice.settings"
      Cauldron.Paths.data(:my_game, ["saves", "one.save"])
      Cauldron.Paths.cache(:my_game)

  `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME` and `$XDG_CACHE_HOME` are honoured; without them
  the directories are `~/.config`, `~/.local/share` and `~/.cache`. Nothing here creates a
  directory.
  """

  @type game :: atom() | String.t()
  @type parts :: Path.t() | [Path.t()]

  @doc "A path under the game's configuration directory."
  @spec config(game(), parts()) :: Path.t()
  def config(game, parts \\ []), do: under("XDG_CONFIG_HOME", ".config", game, parts)

  @doc "A path under the game's data directory."
  @spec data(game(), parts()) :: Path.t()
  def data(game, parts \\ []), do: under("XDG_DATA_HOME", ".local/share", game, parts)

  @doc "A path under the game's cache directory."
  @spec cache(game(), parts()) :: Path.t()
  def cache(game, parts \\ []), do: under("XDG_CACHE_HOME", ".cache", game, parts)

  @doc """
  `path`, unless nothing is there and something is at `other`: then `other`. For a file
  that may still be kept under another name than the one a game uses now.
  """
  @spec existing(Path.t(), Path.t()) :: Path.t()
  def existing(path, other) do
    if File.exists?(path) or not File.exists?(other), do: path, else: other
  end

  defp under(variable, default, game, parts) do
    base = System.get_env(variable) || Path.join(System.user_home!(), default)
    Path.join([base, to_string(game) | List.wrap(parts)])
  end
end
