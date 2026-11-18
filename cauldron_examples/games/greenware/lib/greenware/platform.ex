defmodule Greenware.Platform do
  @moduledoc "The picture size each front end wants: native phones fill the pane, desktops keep 16:9."

  @native if(Mix.target() in [:ios, :android], do: :pane, else: {1280, 720})

  def native_size, do: @native
end
