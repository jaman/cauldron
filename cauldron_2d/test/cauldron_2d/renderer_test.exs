defmodule Cauldron2D.RendererTest do
  @moduledoc """
  Which way a surface gets drawn, and who decides.

  The tests that pin the resolution order use modes that name a protocol outright, so they
  never reach `FrenchCurve.Capability.detect/0` and never depend on the terminal the suite
  happens to run in. The two that do reach it assert only what holds on any terminal.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Renderer

  setup do
    previous = System.get_env("CAULDRON_MODE")
    configured = Application.get_env(:cauldron_2d, :mode)

    on_exit(fn ->
      if previous,
        do: System.put_env("CAULDRON_MODE", previous),
        else: System.delete_env("CAULDRON_MODE")

      if configured,
        do: Application.put_env(:cauldron_2d, :mode, configured),
        else: Application.delete_env(:cauldron_2d, :mode)
    end)

    System.delete_env("CAULDRON_MODE")
    Application.delete_env(:cauldron_2d, :mode)

    :ok
  end

  describe "the modes it knows" do
  end

  describe "reading a mode name" do
    test "a name it knows comes back as an atom" do
      for mode <- Renderer.modes() do
        assert Renderer.parse(Atom.to_string(mode)) == mode
      end
    end

    test "surrounding space and case are ignored" do
      assert Renderer.parse("  KiTtY  ") == :kitty
    end

    test "a name it does not know is nil, and so is nil" do
      assert Renderer.parse("quartz") == nil
      assert Renderer.parse("") == nil
      assert Renderer.parse(nil) == nil
    end
  end

  describe "resolving which protocol to draw with" do
    test "a mode that names a protocol is used as given" do
      assert Renderer.protocol(:kitty) == :kitty
      assert Renderer.protocol(:iterm2) == :iterm2
      assert Renderer.protocol(:sixel) == :sixel
    end

    test "text means no protocol" do
      assert Renderer.protocol(:text) == nil
      assert Renderer.mode(:text) == :text
    end

    test "an override beats the environment" do
      System.put_env("CAULDRON_MODE", "sixel")

      assert Renderer.protocol(:kitty) == :kitty
    end

    test "the environment beats configuration" do
      Application.put_env(:cauldron_2d, :mode, :kitty)
      System.put_env("CAULDRON_MODE", "sixel")

      assert Renderer.protocol() == :sixel
    end

    test "configuration beats the default" do
      Application.put_env(:cauldron_2d, :mode, :iterm2)

      assert Renderer.protocol() == :iterm2
    end

    test "an override that names no mode is ignored, leaving it to the environment" do
      System.put_env("CAULDRON_MODE", "kitty")

      assert Renderer.protocol(:quartz) == :kitty
      assert Renderer.protocol("kitty") == :kitty, "a string is not a mode name"
    end

    test "a CAULDRON_MODE that names no mode is ignored, leaving it to configuration" do
      Application.put_env(:cauldron_2d, :mode, :sixel)
      System.put_env("CAULDRON_MODE", "quartz")

      assert Renderer.protocol() == :sixel
    end

    test "a configured value that names no mode is ignored, leaving the default" do
      Application.put_env(:cauldron_2d, :mode, :quartz)

      assert Renderer.protocol(:text) == nil
    end
  end

  describe "falling through to the terminal" do
    test "mode and describe always agree with protocol, whatever the terminal turns out to be" do
      case Renderer.protocol() do
        nil ->
          assert Renderer.mode() == :text
          assert Renderer.describe() == "text"

        protocol ->
          assert Renderer.mode() == :pixel
          assert Renderer.describe() == Atom.to_string(protocol)
      end
    end
  end
end
