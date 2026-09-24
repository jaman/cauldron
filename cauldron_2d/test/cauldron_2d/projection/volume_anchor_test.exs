defmodule Cauldron2D.Projection.VolumeAnchorTest do
  use ExUnit.Case, async: true

  alias Cauldron2D.Projection.Volume

  defp dome(fields), do: Enum.into(fields, %{at: {0.0, 0.0}, shape: {:sphere, 2.0, 0.0}})

  defp cone(fields),
    do: Enum.into(fields, %{at: {0.0, 0.0}, shape: {:cone, 4.0, 1.0, 0.0, 2.0}})

  describe "anchored/2" do
    test "a volume that follows nothing stays where it stands" do
      fixed = dome(at: {3.0, 4.0})

      assert Volume.anchored([fixed], %{knight: {9.0, 9.0}}) == [fixed]
    end

    test "a volume that follows a subject moves to it" do
      assert [%{at: {9.0, 9.0}}] =
               Volume.anchored([dome(follows: :knight)], %{knight: {9.0, 9.0}})
    end

    test "a subject that is gone takes its volume with it" do
      assert Volume.anchored([dome(follows: :knight)], %{}) == []
    end

    test "a cone turns to face the way its subject faces" do
      subjects = %{knight: {{9.0, 9.0}, 1.5}}

      assert [%{at: {9.0, 9.0}, shape: {:cone, 4.0, 1.0, 1.5, 2.0}}] =
               Volume.anchored([cone(follows: :knight)], subjects)
    end

    test "a beam turns as well" do
      volume = %{at: {0.0, 0.0}, shape: {:beam, 8.0, 1.0, 0.0, 2.0}, follows: :knight}

      assert [%{shape: {:beam, 8.0, 1.0, 0.5, 2.0}}] =
               Volume.anchored([volume], %{knight: {{1.0, 2.0}, 0.5}})
    end

    test "a shape with no heading of its own is only moved" do
      subjects = %{knight: {{9.0, 9.0}, 1.5}}

      assert [moved] = Volume.anchored([dome(follows: :knight)], subjects)
      assert moved.at == {9.0, 9.0}
      assert moved.shape == {:sphere, 2.0, 0.0}
    end

    test "each volume follows its own subject" do
      volumes = [dome(follows: :a), dome(follows: :b), dome(at: {5.0, 5.0})]
      subjects = %{a: {1.0, 1.0}, b: {2.0, 2.0}}

      assert [%{at: {1.0, 1.0}}, %{at: {2.0, 2.0}}, %{at: {5.0, 5.0}}] =
               Volume.anchored(volumes, subjects)
    end
  end

  describe "new/1" do
    test "keeps `:follows`, so a volume may be normalised before or after it is anchored" do
      built = Volume.new(dome(follows: :knight))

      assert built.follows == :knight
      assert [%{at: {7.0, 7.0}}] = Volume.anchored([built], %{knight: {7.0, 7.0}})
    end

    test "leaves `:follows` out of a volume that does not follow anything" do
      refute Map.has_key?(Volume.new(dome([])), :follows)
    end
  end
end
