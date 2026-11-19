defmodule Linocut.Cache do
  @moduledoc """
  Rasters rendered once and kept on disk, under `$XDG_CACHE_HOME/linocut` or
  `~/.cache/linocut`.

      headings = Linocut.Cache.fetch("ship/headings", "2", fn -> Linocut.headings(points, 64, size: {16, 16}, fill: :white) end)

  `key` may contain slashes; `fingerprint` is any string that changes when the render
  should. The render function may return one raster or a list of them; either comes back
  the same shape, with dense pixel buffers.
  """

  alias FrenchCurve.Raster

  @doc "The stored rasters for `key` and `fingerprint`, rendering and storing them when absent."
  @spec fetch(String.t(), String.t(), (-> Raster.t() | [Raster.t()])) :: Raster.t() | [Raster.t()]
  def fetch(key, fingerprint, render) when is_function(render, 0) do
    path = path(key, fingerprint)

    case File.read(path) do
      {:ok, binary} ->
        binary |> :erlang.binary_to_term() |> thaw()

      {:error, _} ->
        rendered = render.()
        store(path, rendered)
        rendered
    end
  end

  @doc "Where `key` at `fingerprint` is stored."
  @spec path(String.t(), String.t()) :: Path.t()
  def path(key, fingerprint) do
    Path.join(dir(), "#{String.replace(key, "/", "__")}-#{fingerprint}.lino")
  end

  defp dir do
    base = System.get_env("XDG_CACHE_HOME") || Path.join(System.user_home!(), ".cache")
    Path.join(base, "linocut")
  end

  defp store(path, rendered) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(freeze(rendered)))
  end

  defp freeze(rasters) when is_list(rasters), do: Enum.map(rasters, &freeze/1)

  defp freeze(%Raster{} = raster) do
    {width, height} = Raster.dimensions(raster)
    {:raster, width, height, Raster.to_rgba_binary(raster)}
  end

  defp thaw(frozen) when is_list(frozen), do: Enum.map(frozen, &thaw/1)
  defp thaw({:raster, width, height, rgba}), do: Raster.from_rgba(width, height, rgba)
end
