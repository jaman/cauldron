defmodule Cauldron.SFX.Web.Layout do
  @moduledoc """
  The page the editor is drawn in: its stylesheet, the Phoenix and LiveView scripts, and the
  one that plays what the server sends.
  """

  use Phoenix.Component

  @doc false
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>SFX</title>
        <link rel="stylesheet" href="/assets/sfx.css" />
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix.min.js">
        </script>
        <script src="/assets/phoenix_live_view.min.js">
        </script>
        <script src="/assets/sfx.js">
        </script>
      </body>
    </html>
    """
  end
end
