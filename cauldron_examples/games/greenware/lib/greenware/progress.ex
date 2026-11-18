defmodule Greenware.Progress do
  @moduledoc "What the Bake remembers between sessions."

  @app :greenware
  @slot "progress"
  @version 1

  def new do
    %{
      version: @version,
      act: 1,
      completed: [],
      seen: [],
      flags: %{},
      ending: nil,
      started_at: nil
    }
  end

  def load do
    case Cauldron.Save.read(@app, @slot) do
      {:ok, %{version: @version} = progress} -> Map.merge(new(), progress)
      _ -> new()
    end
  end

  def save(progress), do: Cauldron.Save.write(@app, @slot, progress)

  def delete, do: Cauldron.Save.delete(@app, @slot)

  def exists? do
    case Cauldron.Save.read(@app, @slot) do
      {:ok, %{version: @version}} -> true
      _ -> false
    end
  end

  def summary do
    case Cauldron.Save.read(@app, @slot) do
      {:ok, %{version: @version} = progress} ->
        %{
          act: Map.get(progress, :act, 1),
          completed: Map.get(progress, :completed, []),
          ending: Map.get(progress, :ending)
        }

      _ ->
        nil
    end
  end
end
