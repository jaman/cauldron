defmodule Cauldron2D.Easel.Web.Router do
  @moduledoc """
  Mounts the editor in a game's Phoenix router.

      import Cauldron2D.Easel.Web.Router

      scope "/" do
        pipe_through :browser
        easel "/easel", dir: "priv/art", tile: 16, atlas: :my_game
      end

  The pages are `<path>` (the arts) and `<path>/<art>` (the editor), with their own root
  layout and scripts under `<path>/assets`. The scope must fetch the session, as a
  `:browser` pipeline does. `:atlas` is the name saves install into; leave it out and
  saves only write the files.
  """

  @doc "The routes of an editor on `dir` at `path`; options `:dir`, `:tile` (required) and `:atlas`."
  defmacro easel(path, opts) do
    quote bind_quoted: [path: path, opts: opts] do
      session = %{
        "dir" => Keyword.fetch!(opts, :dir),
        "tile" => Keyword.fetch!(opts, :tile),
        "atlas" => Keyword.get(opts, :atlas),
        "base" => path
      }

      name = String.to_atom("easel" <> String.replace(path, "/", "_"))

      pipeline name do
        plug(Cauldron2D.Easel.Web.Base, base: path)
      end

      scope path do
        pipe_through(name)
        get("/assets/:file", Cauldron2D.Easel.Web.Assets, :file)

        live_session name, root_layout: {Cauldron2D.Easel.Web.Layout, :root}, session: session do
          live("/", Cauldron2D.Easel.Web.EditorLive, :arts)
          live("/:art", Cauldron2D.Easel.Web.EditorLive, :edit)
        end
      end
    end
  end
end
