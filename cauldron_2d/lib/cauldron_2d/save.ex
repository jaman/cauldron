defmodule Cauldron2D.Save do
  @moduledoc """
  Saved games: a game state kept on disk under a slot name, and read back to start a
  `Cauldron2D.World` from with its `:state` option.

      :ok = Cauldron2D.Save.write(:my_game, "quick", Cauldron2D.World.snapshot(world))
      {:ok, state} = Cauldron2D.Save.read(:my_game, "quick")
      {:ok, world} = Cauldron2D.World.start_link(game: MyGame, state: state)

  Slots live at `Cauldron2D.Paths.data(game, ["saves", slot <> ".save"])`. A slot name is
  one path segment; anything with a separator or `..` is `{:error, :bad_slot}`. The
  state is any term.
  """

  alias Cauldron2D.Paths

  @type slot :: String.t()

  @doc "The file a slot is kept in."
  @spec path(Paths.game(), slot()) :: Path.t()
  def path(game, slot), do: Paths.data(game, ["saves", slot <> ".save"])

  @doc "Keep `state` under `slot`, replacing what was there."
  @spec write(Paths.game(), slot(), term()) :: :ok | {:error, term()}
  def write(game, slot, state) do
    with :ok <- valid(slot),
         path = path(game, slot),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, :erlang.term_to_binary(%{saved_at: DateTime.utc_now(), state: state}))
    end
  end

  @doc "The state kept under `slot`."
  @spec read(Paths.game(), slot()) :: {:ok, term()} | {:error, term()}
  def read(game, slot) do
    with :ok <- valid(slot),
         {:ok, bytes} <- File.read(path(game, slot)),
         {:ok, %{state: state}} <- decode(bytes) do
      {:ok, state}
    end
  end

  @doc "Every slot, oldest first, with when it was written."
  @spec list(Paths.game()) :: [%{slot: slot(), at: DateTime.t()}]
  def list(game) do
    dir = Paths.data(game, "saves")

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".save"))
        |> Enum.flat_map(&slot_entry(dir, &1))
        |> Enum.sort_by(&{DateTime.to_unix(&1.at, :microsecond), &1.slot})

      {:error, :enoent} ->
        []
    end
  end

  @doc "Forget `slot`."
  @spec delete(Paths.game(), slot()) :: :ok | {:error, term()}
  def delete(game, slot) do
    with :ok <- valid(slot), do: File.rm(path(game, slot))
  end

  defp slot_entry(dir, file) do
    with {:ok, bytes} <- dir |> Path.join(file) |> File.read(),
         {:ok, %{saved_at: at}} <- decode(bytes) do
      [%{slot: Path.rootname(file), at: at}]
    else
      _unreadable -> []
    end
  end

  defp valid(slot) when is_binary(slot) do
    if slot != "" and slot not in [".", ".."] and not String.contains?(slot, ["/", "\\"]),
      do: :ok,
      else: {:error, :bad_slot}
  end

  defp valid(_slot), do: {:error, :bad_slot}

  defp decode(bytes) do
    case :erlang.binary_to_term(bytes, [:safe]) do
      %{saved_at: %DateTime{}, state: _} = saved -> {:ok, saved}
      _other -> {:error, :corrupt}
    end
  rescue
    ArgumentError -> {:error, :corrupt}
  end
end
