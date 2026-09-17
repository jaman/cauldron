defmodule Cauldron2D.Easel.Web.TestErrors do
  @moduledoc false
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
