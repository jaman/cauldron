defmodule Cauldron2D.Renderer do
  @moduledoc """
  Chooses between drawing a surface as pixels or as glyphs.

  Modes are `:text`, `:pixel`, `:kitty`, `:iterm2` and `:sixel`. `:pixel` means "whichever
  protocol this terminal has"; the other three name one outright.

  A mode is resolved most specific first:

    1. an override passed by the caller, when it is one of the modes
    2. `CAULDRON_MODE` in the environment
    3. the `:cauldron_2d` application environment's `:mode` key
    4. `:pixel`

  A resolved `:pixel` is then asked of `FrenchCurve.Capability.detect/0`. Its `:braille`
  answer counts as no pixel protocol, and the text renderer takes over.
  """

  @modes [:text, :pixel, :kitty, :iterm2, :sixel]
  @protocols [:kitty, :iterm2, :sixel]

  @doc "The mode names accepted as an override, in `CAULDRON_MODE`, or in application config."
  @spec modes() :: [atom()]
  def modes, do: @modes

  @doc """
  Whether the surface is drawn as an image or as characters.

  `:pixel` when `protocol/1` finds one, `:text` otherwise. `override` is a mode name, or `nil`
  to leave the choice to the environment and configuration.
  """
  @spec mode(atom() | nil) :: :pixel | :text
  def mode(override \\ nil) do
    if protocol(override), do: :pixel, else: :text
  end

  @doc """
  The pixel protocol to draw with, or `nil` for the text renderer.

  `override` is a mode name, or `nil` to leave the choice to the environment and
  configuration. An override that is not one of `modes/0` is ignored.
  """
  @spec protocol(atom() | nil) :: :kitty | :iterm2 | :sixel | nil
  def protocol(override \\ nil) do
    case resolve(override) do
      :text -> nil
      :pixel -> detect()
      protocol when protocol in @protocols -> protocol
    end
  end

  @doc """
  The mode in force before any terminal is asked: `:text`, `:pixel`, or a protocol named
  outright.

  `override` is a mode name, or `nil` to leave the choice to the environment and
  configuration. A caller that can ask the session's own terminal resolves `:pixel`
  itself; `protocol/1` resolves it from the OS environment.
  """
  @spec resolved(atom() | nil) :: :text | :pixel | :kitty | :iterm2 | :sixel
  def resolved(override \\ nil), do: resolve(override)

  @doc ~S(The resolved protocol's name, or `"text"`, for a status bar.)
  @spec describe(atom() | nil) :: String.t()
  def describe(override \\ nil) do
    case protocol(override) do
      nil -> "text"
      protocol -> Atom.to_string(protocol)
    end
  end

  @doc """
  The mode `value` names, or `nil` when it names none.

  Surrounding whitespace and case are ignored. `nil` in gives `nil` out.
  """
  @spec parse(String.t() | nil) :: atom() | nil
  def parse(nil), do: nil

  def parse(value) when is_binary(value) do
    normalised = value |> String.trim() |> String.downcase()
    Enum.find(@modes, fn mode -> Atom.to_string(mode) == normalised end)
  end

  defp resolve(override) do
    valid(override) || parse(System.get_env("CAULDRON_MODE")) || configured() || :pixel
  end

  defp valid(mode) when mode in @modes, do: mode
  defp valid(_other), do: nil

  defp configured, do: valid(Application.get_env(:cauldron_2d, :mode))

  defp detect do
    case FrenchCurve.Capability.detect() do
      protocol when protocol in @protocols -> protocol
      _braille -> nil
    end
  end
end
