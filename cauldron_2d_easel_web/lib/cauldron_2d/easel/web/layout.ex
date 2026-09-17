defmodule Cauldron2D.Easel.Web.Layout do
  @moduledoc """
  The root layout of the editor's pages: the stylesheet, the Phoenix and LiveView
  scripts and the canvas hook, from the editor's own assets.
  """

  use Phoenix.Component

  @doc false
  def root(assigns) do
    assigns = assign(assigns, :base, assigns.conn.private[:easel_base] || "")

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Easel</title>
        <link rel="stylesheet" href={"#{@base}/assets/easel.css"} />
      </head>
      <body>
        {@inner_content}
        <script src={"#{@base}/assets/phoenix.min.js"}>
        </script>
        <script src={"#{@base}/assets/phoenix_live_view.min.js"}>
        </script>
        <script src={"#{@base}/assets/easel.js"}>
        </script>
      </body>
    </html>
    """
  end
end
