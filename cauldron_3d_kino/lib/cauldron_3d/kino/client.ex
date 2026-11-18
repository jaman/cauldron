defmodule Cauldron3D.Kino.Client do
  @moduledoc """
  `cauldron_3d_net`'s browser client (`cauldron3d.js`) as a module a Kino cell imports
  without an import map: three.js and its add-ons come from jsDelivr's `+esm` builds
  of the version `Cauldron3D.Net.Page.three_version/0` names.
  """

  alias Cauldron3D.Net.Page

  @doc "The path of `cauldron3d.js` in `cauldron_3d_net`."
  @spec path() :: Path.t()
  def path, do: Application.app_dir(:cauldron_3d_net, "priv/static/cauldron3d.js")

  @doc "The client's source with every three.js import pointed at jsDelivr."
  @spec source() :: String.t()
  def source, do: path() |> File.read!() |> rewrite(Page.three_version())

  @doc ~s|`source` with `"three"` and `"three/addons/…"` imports replaced by jsDelivr URLs of `version`.|
  @spec rewrite(String.t(), String.t()) :: String.t()
  def rewrite(source, version) do
    base = "https://cdn.jsdelivr.net/npm/three@#{version}"

    source
    |> String.replace(~r/from "three\/addons\/([^"]+)"/, ~s(from "#{base}/examples/jsm/\\1/+esm"))
    |> String.replace(~s(from "three"), ~s(from "#{base}/+esm"))
  end
end
