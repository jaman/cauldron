defmodule Cauldron.SFX.Presets do
  @moduledoc """
  Recipes to start an event from, so **add event** lands on something finished.

      Cauldron.SFX.Presets.names()
      {name, %{recipe: recipe, space: space}} = Cauldron.SFX.Presets.get(0)

  Each is a whole event recipe — layers, FM, detune, a room where it helps — not a bare
  tone. `space` is how much of the early-reflection field the event is given.
  """

  @presets [
    {"laser",
     %{
       space: 0.0,
       recipe: %{
         kind: "tone",
         shape: "saw",
         freq: 1400.0,
         sweep: 0.18,
         decay: 0.14,
         attack: 0.003,
         detune: 6.0,
         cutoff: 0.7,
         gain: 0.6
       }
     }},
    {"zap",
     %{
       space: 0.0,
       recipe: %{
         kind: "tone",
         shape: "square",
         freq: 900.0,
         sweep: 0.12,
         decay: 0.09,
         fm: 0.6,
         fmh: 2.01,
         fmattack: 0.01,
         cutoff: 0.8,
         gain: 0.55
       }
     }},
    {"coin",
     %{
       space: 0.15,
       recipe: %{
         kind: "layers",
         parts: [
           %{
             at_ms: 0,
             recipe: %{kind: "tone", shape: "sine", freq: 988.0, decay: 0.09, gain: 0.5}
           },
           %{
             at_ms: 70,
             recipe: %{kind: "tone", shape: "sine", freq: 1319.0, decay: 0.18, gain: 0.5}
           }
         ]
       }
     }},
    {"jump",
     %{
       space: 0.0,
       recipe: %{
         kind: "tone",
         shape: "square",
         freq: 320.0,
         sweep: 2.2,
         decay: 0.16,
         attack: 0.004,
         cutoff: 0.6,
         gain: 0.45
       }
     }},
    {"explosion",
     %{
       space: 0.7,
       recipe: %{
         kind: "layers",
         parts: [
           %{at_ms: 0, recipe: %{kind: "noise", decay: 0.6, cutoff: 0.35, gain: 0.7}},
           %{
             at_ms: 0,
             recipe: %{
               kind: "tone",
               shape: "sine",
               freq: 55.0,
               sweep: 0.4,
               decay: 0.55,
               gain: 0.5
             }
           }
         ]
       }
     }},
    {"whoosh",
     %{
       space: 0.3,
       recipe: %{
         kind: "noise",
         attack: 0.06,
         decay: 0.3,
         cutoff: 0.4,
         gain: 0.5
       }
     }},
    {"hit",
     %{
       space: 0.2,
       recipe: %{
         kind: "layers",
         parts: [
           %{at_ms: 0, recipe: %{kind: "noise", decay: 0.05, cutoff: 0.9, gain: 0.8}},
           %{
             at_ms: 0,
             recipe: %{kind: "tone", shape: "sine", freq: 170.0, decay: 0.12, gain: 0.7}
           }
         ]
       }
     }},
    {"bell",
     %{
       space: 0.4,
       recipe: %{
         kind: "tone",
         shape: "sine",
         freq: 880.0,
         decay: 0.7,
         release: 0.2,
         fm: 0.5,
         fmh: 3.01,
         gain: 0.5
       }
     }},
    {"clang",
     %{
       space: 0.25,
       recipe: %{kind: "sample", sound: "hh", gain: 0.6}
     }}
  ]

  @doc "Every preset, as `{name, %{recipe: recipe, space: space}}`, in the order an editor cycles them."
  @spec all() :: [{String.t(), %{recipe: map(), space: float()}}]
  def all, do: @presets

  @doc "The presets' names, in order."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@presets, &elem(&1, 0))

  @doc "The preset at `index`, wrapping at either end, or `nil` when there are none."
  @spec get(integer()) :: {String.t(), %{recipe: map(), space: float()}} | nil
  def get(index) when is_integer(index) and index >= 0 do
    Enum.at(@presets, rem(index, length(@presets)))
  end

  def get(_index), do: nil

  @doc "The preset called `name`, or `nil`."
  @spec named(String.t()) :: %{recipe: map(), space: float()} | nil
  def named(name) do
    case Enum.find(@presets, fn {preset, _} -> preset == name end) do
      nil -> nil
      {_name, preset} -> preset
    end
  end
end
