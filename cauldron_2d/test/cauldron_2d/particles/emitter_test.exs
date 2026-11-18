defmodule Cauldron2D.Particles.EmitterTest do
  use ExUnit.Case, async: true

  alias Cauldron.Rng
  alias Cauldron2D.Particles
  alias Cauldron2D.Particles.Emitter

  test "a stream makes its rate a second, carrying fractions between steps" do
    emitter = %Emitter{rate: 15.0, art: :spark}

    {counts, _emitter, _rng} =
      Enum.reduce(1..10, {[], emitter, Rng.new(1)}, fn _, {counts, e, rng} ->
        {made, e, rng} = Emitter.emit(e, 0.1, rng)
        {[length(made) | counts], e, rng}
      end)

    assert Enum.sum(counts) == 15
  end

  test "particles leave within the spread and range, and the same seed makes the same ones" do
    emitter = %Emitter{angle: 0.0, spread: 0.5, speed: {2.0, 3.0}, ttl: 0.4, art: :spark}
    {made, _rng} = Emitter.burst(emitter, 50, Rng.new(7))

    for %{vel: {vx, vy}, ttl: 0.4} <- made do
      speed = :math.sqrt(vx * vx + vy * vy)
      assert speed >= 2.0 and speed <= 3.0
      assert abs(:math.atan2(vy, vx)) <= 0.25 + 1.0e-9
    end

    assert {^made, _rng} = Emitter.burst(emitter, 50, Rng.new(7))
  end

  test "a particle shows the art of how much of its life is gone" do
    {[spark], _rng} = Emitter.burst(%Emitter{ttl: 1.0, arts: [:bright, :dim]}, 1, Rng.new(1))
    particles = Particles.spawn(Particles.new(10), [spark])

    assert [{:bright, _at}] = Particles.movers(particles)
    assert [{:dim, _at}] = particles |> Particles.step(0.6) |> Particles.movers()
  end
end
