defmodule Cauldron2D.JumpTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Jump

  @ground %{vy: 0.0, grounded?: true}
  @air %{vy: 2.0, grounded?: false}

  test "off a ledge a body can still jump for the coyote time, and only once" do
    jump = Jump.step(Jump.new(), @air, 0.06)
    assert Jump.ready?(jump, @air)
    refute Jump.ready?(Jump.step(jump, @air, 0.06), @air)

    {jumped, body} = Jump.launch(jump, @air, 20.0)
    assert body.vy == -20.0
    refute Jump.ready?(jumped, body)
    assert Jump.ready?(Jump.step(jumped, @ground, 0.02), @ground)
  end

  test "rising with the jump let go falls harder, and no fall passes the cap" do
    rising = %{vy: -10.0, grounded?: false}
    assert Jump.fall(rising, true, 50.0, 0.1).vy == -5.0
    assert Jump.fall(rising, false, 50.0, 0.1).vy == 3.0
    assert Jump.fall(%{vy: 29.0, grounded?: false}, false, 50.0, 0.1).vy == 30.0
  end
end
