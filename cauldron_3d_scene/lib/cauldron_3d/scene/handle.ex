defmodule Cauldron3D.Scene.Handle do
  @moduledoc """
  A mesh, texture, material or scatter held by the renderer. Once the handle is garbage collected
  the renderer frees the object as soon as no scene entry uses it: a mesh, material or
  scatter when no instance names it, a texture when no material does. A material's handle keeps
  the texture handles it uses.
  """

  @type kind :: :mesh | :texture | :material | :scatter
  @type t :: %__MODULE__{kind: kind(), id: pos_integer(), ref: reference(), keeps: [t()]}

  @enforce_keys [:kind, :id, :ref]
  defstruct [:kind, :id, :ref, keeps: []]
end
