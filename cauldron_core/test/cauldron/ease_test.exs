defmodule Cauldron.EaseTest do
  use ExUnit.Case, async: true

  alias Cauldron.{Ease, Tween}

  test "every curve starts at nought and ends at one" do
    for curve <- Ease.curves() do
      assert_in_delta Ease.apply(curve, 0.0), 0.0, 1.0e-9, inspect(curve)
      assert_in_delta Ease.apply(curve, 1.0), 1.0, 1.0e-9, inspect(curve)
    end
  end

  test "in starts slow, out ends slow, in-out is half way at half time" do
    assert Ease.apply(:in_cubic, 0.5) == 0.125
    assert Ease.apply(:out_cubic, 0.5) == 0.875
    assert Ease.apply(:in_out_quad, 0.5) == 0.5
    assert Ease.apply(:out_back, 0.6) > 1.0
  end

  test "a tween moves a point along its curve and stops at its end" do
    tween = Tween.new({0.0, 10.0}, {4.0, 20.0}, 1.0, :in_quad)
    assert Tween.value(Tween.step(tween, 0.5)) == {1.0, 12.5}

    done = Tween.step(tween, 3.0)
    assert Tween.done?(done)
    assert Tween.value(done) == {4.0, 20.0}
  end
end
