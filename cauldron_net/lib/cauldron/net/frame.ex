defmodule Cauldron.Net.Frame do
  @moduledoc """
  A frame's status as it goes over the wire beside its picture or scene: the hud rows,
  the outcome when the round is over for this player, the subject the view follows and
  the focus.

      Cauldron.Net.Frame.status(scene, hud_rows, outcome, &MyPalette.rgb/1)

  Hud rows are as `Cauldron.Client.Hud` describes them and go out as
  `[text, "#rrggbb" | nil]` runs, a colour named by an atom looked up with `named`
  (`c:Cauldron.Net.Drawer.colour/1`); a row's tag goes in `tags` at the same position
  (`nil` for a row without one) — `tags` is there only when some row has a tag.
  """

  alias Cauldron.Client.Hud

  @type row :: Hud.row()

  @doc "The status of a frame whose scene is `scene` (`nil` before the scene has a focus)."
  @spec status(map() | nil, [row()], map() | nil, (atom() -> Hud.rgb() | nil)) :: map()
  def status(scene, hud, outcome, named) do
    tags = Enum.map(hud, &Hud.tag/1)

    %{
      hud:
        for(
          row <- hud,
          do:
            for(
              run <- Hud.runs(row),
              do: [elem(run, 0), hex(Hud.colour(run, named))]
            )
        ),
      over: outcome && Map.take(outcome, [:title, :lines])
    }
    |> with_focus(scene)
    |> with_subject(scene)
    |> with_tags(tags)
  end

  defp with_focus(status, %{focus: {fx, fy}}), do: Map.put(status, :focus, [fx / 1, fy / 1])
  defp with_focus(status, _scene), do: status

  defp with_subject(status, %{subject: subject}), do: Map.put(status, :subject, subject)
  defp with_subject(status, _scene), do: status

  defp with_tags(status, tags) do
    if Enum.any?(tags),
      do: Map.put(status, :tags, Enum.map(tags, &(&1 && Atom.to_string(&1)))),
      else: status
  end

  defp hex(nil), do: nil
  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
end
