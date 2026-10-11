defmodule Cauldron3D.Native do
  @moduledoc """
  Where cauldron_3d's compiled native code is: `priv/native/<system architecture>`, the
  architecture as `:erlang.system_info(:system_architecture)` gives it, so builds for
  different machines sit side by side in one checkout. The Makefile writes to the same
  folder, which `mix.exs` passes it as `PRIV_DIR`.
  """

  @doc "The file `name` of this machine's native code, as a charlist for `:erlang.load_nif/2`."
  @spec path(String.t()) :: charlist()
  def path(name) do
    architecture = to_string(:erlang.system_info(:system_architecture))
    Path.join([:code.priv_dir(:cauldron_3d), "native", architecture, name]) |> to_charlist()
  end
end
