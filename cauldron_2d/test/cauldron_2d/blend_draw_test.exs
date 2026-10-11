defmodule Cauldron2D.BlendDrawTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Blend

  @canvas_size {16, 12}

  defp canvas do
    {width, height} = @canvas_size
    for index <- 0..(width * height - 1), into: <<>>, do: <<index, 40, 200 - index, 128>>
  end

  defp picture do
    for row <- 0..2,
        column <- 0..4,
        into: <<>>,
        do: <<column * 60, row * 100, 90, 255 - column * 40>>
  end

  test "a picture scaled by two across lands on exactly the pixels it covers" do
    blank = :binary.copy(<<0, 0, 0, 255>>, 64)
    red = :binary.copy(<<255, 0, 0, 255>>, 4)
    drawn = Blend.draw(blank, {8, 8}, red, {2, 2}, %{position: {3, 3}, scale: {2, 1}})

    red_pixels =
      for {<<255, 0, 0, 255>>, index} <- Enum.with_index(for <<p::binary-4 <- drawn>>, do: p),
          do: {rem(index, 8), div(index, 8)}

    assert red_pixels == for(row <- 3..4, column <- 3..6, do: {column, row})
  end

  test "the C library and Elixir draw the same pixels" do
    placements = [
      %{position: {2, 3}},
      %{position: {7.5, 6.25}, origin: {2, 1}, scale: {2, 3}},
      %{position: {8, 6}, origin: {2.5, 1.5}, scale: {-1.5, 1}, angle: 30},
      %{position: {8, 6}, origin: {2.5, 1.5}, angle: 90, blend: {255, 128, 0}},
      %{position: {5, 5}, origin: {1, 1}, scale: {1, -2}, angle: 200, alpha: 0.5},
      %{position: {-2, 10}, scale: {3, 3}, angle: 45},
      %{position: {15, 0}, scale: {0.5, 0.5}, angle: 12.5, alpha: 0.25}
    ]

    assert Blend.available?()

    for placement <- placements do
      native = Blend.draw(canvas(), @canvas_size, picture(), {5, 3}, placement)
      elixir = Blend.draw(canvas(), @canvas_size, picture(), {5, 3}, placement, native: false)

      assert native == elixir, "placement #{inspect(placement)} differs"
      refute native == canvas(), "placement #{inspect(placement)} drew nothing"
    end
  end
end
