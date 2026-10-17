defmodule CauldronGPU.Setup.Fetch do
  @moduledoc """
  Downloads for `CauldronGPU.Setup`: an archive fetched over HTTPS, with the server's
  certificate checked against the operating system's certificate store, and unpacked into
  a folder.

      :ok = Fetch.unpack("https://example.com/thing.zip", :zip, "/tmp/thing")
  """

  @doc """
  Downloads `url` and unpacks it, a `:zip` or `:tar_gz` archive, into `dir`, replacing
  what `dir` held.
  """
  @spec unpack(String.t(), :zip | :tar_gz, Path.t()) :: :ok | {:error, String.t()}
  def unpack(url, kind, dir) do
    IO.puts("Downloading #{url}")

    with {:ok, body} <- download(url) do
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
      extract(kind, body, dir)
    end
  end

  @doc "The body of `url`, following redirects."
  @spec download(String.t()) :: {:ok, binary()} | {:error, String.t()}
  def download(url) do
    {:ok, _apps} = Application.ensure_all_started([:inets, :ssl, :public_key])

    ssl = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 4,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    request = {String.to_charlist(url), [{~c"user-agent", ~c"cauldron_gpu setup"}]}

    case :httpc.request(:get, request, [ssl: ssl, autoredirect: true, timeout: 300_000],
           body_format: :binary
         ) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, "#{url} answered #{status}"}

      {:error, reason} ->
        {:error, "#{url} could not be downloaded: #{inspect(reason)}"}
    end
  end

  defp extract(:zip, body, dir) do
    case :zip.extract(body, cwd: String.to_charlist(dir)) do
      {:ok, _files} -> :ok
      {:error, reason} -> {:error, "the download could not be unpacked: #{inspect(reason)}"}
    end
  end

  defp extract(:tar_gz, body, dir) do
    case :erl_tar.extract({:binary, body}, [:compressed, cwd: String.to_charlist(dir)]) do
      :ok -> :ok
      {:error, reason} -> {:error, "the download could not be unpacked: #{inspect(reason)}"}
    end
  end
end
