defmodule Notes.App do
  @moduledoc """
  Notes kept on the phone, in the platform's own controls: a list of notes with a field to
  add one, a screen to edit a note and rate it with stars (`rating`, a view of the app's
  own in `native/ios` and `native/android`), and a settings screen.
  """

  use CauldronNative.App

  @impl true
  def mount(_params),
    do: %{notes: [], next: 1, draft: "", screens: [:notes], newest_first: true}

  @impl true
  def render(state) do
    navigation(Enum.map(state.screens, &screen_for(&1, state)), on_back: :back)
  end

  @impl true
  def handle_event(:draft, text, state), do: %{state | draft: text}
  def handle_event(:add, _value, %{draft: ""} = state), do: state

  def handle_event(:add, _value, state) do
    note = %{id: state.next, text: String.trim(state.draft), stars: 0}
    %{state | notes: state.notes ++ [note], next: state.next + 1, draft: ""}
  end

  def handle_event({:open, id}, _value, state), do: %{state | screens: [:notes, {:note, id}]}
  def handle_event(:settings, _value, state), do: %{state | screens: [:notes, :settings]}
  def handle_event(:back, depth, state), do: %{state | screens: Enum.take(state.screens, depth)}
  def handle_event({:edit, id}, text, state), do: update_note(state, id, &%{&1 | text: text})
  def handle_event({:rate, id}, stars, state), do: update_note(state, id, &%{&1 | stars: stars})

  def handle_event({:delete, id}, _value, state),
    do: %{state | notes: Enum.reject(state.notes, &(&1.id == id)), screens: [:notes]}

  def handle_event(:newest_first, on?, state), do: %{state | newest_first: on?}

  defp screen_for(:notes, state) do
    screen("Notes", [
      list([
        section(nil, [
          text_field("New note", value: state.draft, on_change: :draft, on_submit: :add),
          button("Add", on_tap: :add, disabled: String.trim(state.draft) == "")
        ]),
        section("Notes", note_rows(state), footer: count(state.notes)),
        section(nil, [button("Settings", on_tap: :settings)])
      ])
    ])
  end

  defp screen_for({:note, id}, state) do
    note = Enum.find(state.notes, &(&1.id == id))

    screen("Note", [
      form([
        section("Text", [text_field("Note", value: note.text, on_change: {:edit, id})]),
        section("Rating", [
          native(:rating, value: note.stars, on_change: {:rate, id}, label: "Rating")
        ]),
        section(nil, [button("Delete", role: :destructive, on_tap: {:delete, id})])
      ])
    ])
  end

  defp screen_for(:settings, state) do
    screen("Settings", [
      form([
        section("List", [
          toggle("Newest first", value: state.newest_first, on_change: :newest_first)
        ])
      ])
    ])
  end

  defp note_rows(state) do
    notes = if state.newest_first, do: Enum.reverse(state.notes), else: state.notes

    for note <- notes do
      button(note.text <> stars(note.stars), id: note.id, on_tap: {:open, note.id})
    end
  end

  defp stars(0), do: ""
  defp stars(count), do: " " <> String.duplicate("★", count)

  defp count([]), do: "No notes yet"
  defp count([_one]), do: "1 note"
  defp count(notes), do: "#{length(notes)} notes"

  defp update_note(state, id, change) do
    %{state | notes: Enum.map(state.notes, &if(&1.id == id, do: change.(&1), else: &1))}
  end
end
