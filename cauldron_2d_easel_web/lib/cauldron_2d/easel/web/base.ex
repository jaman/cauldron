defmodule Cauldron2D.Easel.Web.Base do
  @moduledoc """
  Remembers the path the editor is mounted at, for its layout to find its assets.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :base)

  @impl Plug
  def call(conn, base), do: Plug.Conn.put_private(conn, :easel_base, base)
end
