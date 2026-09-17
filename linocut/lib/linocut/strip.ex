defmodule Linocut.Strip do
  @moduledoc """
  An animation: frames shown in turn at a rate, looping.

      strip = Linocut.Strip.new([frame_a, frame_b, frame_c], 12)
      Linocut.Strip.frame_at(strip, elapsed_ms)
  """

  alias FrenchCurve.Raster

  @type t :: %__MODULE__{frames: tuple(), fps: number()}

  defstruct [:frames, :fps]

  @doc "A strip of `frames` at `fps` frames per second."
  @spec new([Raster.t()], number()) :: t()
  def new([_ | _] = frames, fps) when fps > 0,
    do: %__MODULE__{frames: List.to_tuple(frames), fps: fps}

  @doc "The frame showing `ms` milliseconds after the strip started, wrapping round."
  @spec frame_at(t(), non_neg_integer()) :: Raster.t()
  def frame_at(%__MODULE__{frames: frames, fps: fps}, ms) do
    index = trunc(ms * fps / 1000)
    elem(frames, rem(index, tuple_size(frames)))
  end

  @doc "How many frames the strip has."
  @spec count(t()) :: pos_integer()
  def count(%__MODULE__{frames: frames}), do: tuple_size(frames)
end
