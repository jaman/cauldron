defmodule CauldronNative.Build.Shell do
  @moduledoc """
  Runs the build's commands. Each command's output goes to a log file; a command that
  fails raises `Mix.Error` with the log's last lines and its path.

  The compiler variables of the calling shell (`CC`, `CFLAGS`, `CPPFLAGS`, `LDFLAGS`,
  …) are removed from every command's environment, so a cross build sees only the
  flags the build gives it.
  """

  @scrubbed ~w(CC CXX CPP LD AR RANLIB CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBS OBJCFLAGS
               ERL_TOP ERL_LIBS MAKEFLAGS MFLAGS SDKROOT IPHONEOS_DEPLOYMENT_TARGET
               MACOSX_DEPLOYMENT_TARGET)

  @doc """
  Run `command` with `arguments` in `:cd`, logging to `:log`, with `:env` added to the
  scrubbed environment. Returns `:ok` or raises, the error ending with `:explain`, text
  saying what the failure usually means, when given: the text, or a function given the
  log's last lines that returns the text or `nil` when it does not apply.
  """
  @spec run!(String.t(), [String.t()], keyword()) :: :ok
  def run!(command, arguments, opts) do
    log = Keyword.fetch!(opts, :log)
    File.mkdir_p!(Path.dirname(log))
    env = Enum.map(@scrubbed, &{&1, nil}) ++ Keyword.get(opts, :env, [])
    cd = Keyword.get(opts, :cd, File.cwd!())
    executable = executable(command, cd)

    {_, status} =
      File.open!(log, [:append, :binary], fn file ->
        IO.binwrite(file, "\n$ #{Enum.join([command | arguments], " ")}\n")

        System.cmd(executable, arguments,
          cd: cd,
          env: env,
          stderr_to_stdout: true,
          into: IO.binstream(file, :line)
        )
      end)

    if status == 0, do: :ok, else: failed!(command, status, log, Keyword.get(opts, :explain))
  end

  @doc "The output of `command`, trimmed, or raises when it fails."
  @spec output!(String.t(), [String.t()], keyword()) :: String.t()
  def output!(command, arguments, opts \\ []) do
    env = Enum.map(@scrubbed, &{&1, nil}) ++ Keyword.get(opts, :env, [])

    case System.cmd(System.find_executable(command) || command, arguments,
           env: env,
           stderr_to_stdout: true,
           cd: Keyword.get(opts, :cd, File.cwd!())
         ) do
      {output, 0} -> String.trim(output)
      {output, status} -> Mix.raise("#{command} exited with #{status}:\n#{output}")
    end
  end

  @doc "The number of jobs a parallel make runs."
  @spec jobs() :: String.t()
  def jobs, do: Integer.to_string(System.schedulers_online())

  defp executable("./" <> _relative = command, cd), do: Path.expand(command, cd)
  defp executable(command, _cd), do: System.find_executable(command) || command

  defp failed!(command, status, log, explain) do
    tail = log |> File.read!() |> String.split("\n") |> Enum.take(-40) |> Enum.join("\n")
    message = "#{command} exited with #{status}. The last lines of #{log}:\n\n#{tail}"

    case explanation(explain, tail) do
      nil -> Mix.raise(message)
      text -> Mix.raise(message <> "\n\n" <> text)
    end
  end

  defp explanation(explain, tail) when is_function(explain, 1), do: explain.(tail)
  defp explanation(explain, _tail), do: explain
end
