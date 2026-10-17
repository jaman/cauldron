defmodule CauldronGPU.Setup.Command do
  @moduledoc """
  Programs run by `CauldronGPU.Setup`'s platforms.

  `output/2` runs a program and keeps what it printed. `interactive/2` runs one on this
  terminal, so a password prompt (`sudo`) or an installer's questions reach the person
  running the setup.
  """

  @doc "What `program` with `args` printed, or `:error` when it is missing or failed."
  @spec output(String.t(), [String.t()]) :: {:ok, String.t()} | :error
  def output(program, args) do
    with path when is_binary(path) <- System.find_executable(program),
         {text, 0} <- System.cmd(path, args, stderr_to_stdout: true) do
      {:ok, text}
    else
      _failed -> :error
    end
  end

  @doc "Whether `program` with `args` runs and succeeds."
  @spec succeeds?(String.t(), [String.t()]) :: boolean()
  def succeeds?(program, args), do: output(program, args) != :error

  @doc """
  Runs `program` with `args` on this terminal and waits for it: `:ok`, or `{:error, text}`
  when it is missing or exits with a failure.
  """
  @spec interactive(String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def interactive(program, args) do
    case System.find_executable(program) do
      nil ->
        {:error, "#{program} is not installed"}

      path ->
        IO.puts(IO.ANSI.format([:faint, "$ ", Enum.join([program | args], " ")]))
        port = Port.open({:spawn_executable, path}, [:nouse_stdio, :exit_status, args: args])

        receive do
          {^port, {:exit_status, 0}} -> :ok
          {^port, {:exit_status, status}} -> {:error, "#{program} exited with status #{status}"}
        end
    end
  end
end
