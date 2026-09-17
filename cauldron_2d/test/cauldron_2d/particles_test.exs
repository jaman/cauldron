defmodule Cauldron2D.ParticlesTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Particles

  defp spark(x, ttl \\ 1.0), do: %{art: :spark, pos: {x, 0.0}, vel: {1.0, 0.0}, ttl: ttl}

  test "particles move and die" do
    particles =
      Particles.new(10)
      |> Particles.spawn([spark(0.0, 0.3)])
      |> Particles.step(0.2)

    assert [{:spark, {x, _}}] = Particles.movers(particles)
    assert_in_delta x, 0.2, 1.0e-9

    assert Particles.movers(Particles.step(particles, 0.2)) == []
  end

  test "the cap drops the oldest" do
    particles =
      Particles.new(2)
      |> Particles.spawn([spark(1.0), spark(2.0)])
      |> Particles.spawn([spark(3.0)])

    assert Enum.map(Particles.movers(particles), fn {_, {x, _}} -> x end) == [2.0, 3.0]
    assert Particles.count(particles) == 2
  end

  test "movers can be offset for sprites drawn from their top-left corner" do
    particles = Particles.new(4) |> Particles.spawn([spark(1.0)])
    assert [{:spark, {0.5, -0.5}}] = Particles.movers(particles, {-0.5, -0.5})
  end

  test "gravity fields and drag apply when given" do
    field = %{strength: 2.0, kind: {:uniform, {0.0, 1.0}}}

    particles =
      Particles.new(4)
      |> Particles.spawn([spark(0.0)])
      |> Particles.step(0.5, fields: [field], drag: 0.0)

    [{_, {_, y}}] = Particles.movers(particles)
    assert y > 0.0
  end
end
