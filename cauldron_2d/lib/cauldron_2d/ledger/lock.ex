defmodule Cauldron2D.Ledger.Lock do
  @moduledoc """
  The lock that keeps a ledger file to one operating system process: `<path>.lock`,
  holding the process id of the holder. A lock whose process is gone, or is no longer an
  Erlang VM (its id since reused by another program), counts as free; a file a DETS
  table of this process already has open is held. The process is looked up with `ps` on
  Unix and `tasklist` on Windows.
  """

  @doc "The operating system process holding the file's lock, or nil."
  @spec holder(Path.t()) :: pos_integer() | nil
  def holder(path) do
    with {:ok, contents} <- File.read(lock_path(path)),
         {pid, _rest} <- Integer.parse(String.trim(contents)),
         true <- alive?(pid) do
      pid
    else
      _free -> nil
    end
  end

  @doc "Take the file's lock for this process: `:ok`, or `{:error, {:held, pid}}` when another live process holds it."
  @spec take(Path.t()) :: :ok | {:error, {:held, pos_integer()}}
  def take(path) do
    me = List.to_integer(:os.getpid())

    case holder(path) do
      nil ->
        write(path, me)

      ^me ->
        if open_here?(path), do: {:error, {:held, me}}, else: :ok

      pid ->
        {:error, {:held, pid}}
    end
  end

  @doc "Give the file's lock up, when this process holds it."
  @spec release(Path.t()) :: :ok
  def release(path) do
    if holder(path) == List.to_integer(:os.getpid()), do: File.rm(lock_path(path))
    :ok
  end

  defp write(path, me) do
    lock = lock_path(path)
    File.rm(lock)

    case File.open(lock, [:write, :exclusive]) do
      {:ok, file} ->
        IO.binwrite(file, Integer.to_string(me))
        File.close(file)
        :ok

      {:error, :eexist} ->
        take(path)
    end
  end

  defp lock_path(path), do: path <> ".lock"

  defp open_here?(path) do
    file = String.to_charlist(path)
    Enum.any?(:dets.all(), &(:dets.info(&1, :filename) == file))
  end

  defp alive?(pid), do: pid |> program(:os.type()) |> erlang_vm?()

  defp program(pid, {:win32, _name}) do
    id = Integer.to_string(pid)
    {out, _status} = System.cmd("tasklist", ["/FI", "PID eq #{id}", "/FO", "CSV", "/NH"])

    case String.split(String.trim(out), "\",\"") do
      ["\"" <> image, ^id | _columns] -> image
      _none -> ""
    end
  end

  defp program(pid, {:unix, _name}) do
    case System.cmd("ps", ["-p", Integer.to_string(pid), "-o", "comm="], stderr_to_stdout: true) do
      {out, 0} -> String.trim(out)
      {_out, _status} -> ""
    end
  end

  defp erlang_vm?(program) do
    program
    |> Path.basename()
    |> String.downcase()
    |> String.starts_with?(["beam", "erl", "werl"])
  end
end
