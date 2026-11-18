defprotocol Cauldron3D.Scene.Target do
  @moduledoc """
  Anything a scene can be sent to: a `CauldronGPU` renderer in the VM, a
  `CauldronGPU.Host` in its own process, or a browser scene (`Cauldron3D.Net.Scene`).
  The converters (`Cauldron3D.Scene.Bsp`, `Cauldron3D.Scene.AliasModel`, `Cauldron3D.Scene.StudioModel`,
  `Cauldron3D.Scene.Sectors`) upload through it, so they work with every one.
  """

  @doc "Sends one tick of changes (`Cauldron3D.Scene.Stream`)."
  @spec submit(t(), [Cauldron3D.Scene.Stream.change()]) :: :ok | {:error, term()}
  def submit(target, changes)

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), Cauldron3D.Scene.Mesh.t()) :: Cauldron3D.Scene.Handle.t()
  def mesh(target, mesh)

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), Cauldron3D.Scene.Texture.t()) :: Cauldron3D.Scene.Handle.t()
  def texture(target, texture)

  @doc "Makes a canvas, a texture drawn into by 2D layers, and returns its handle."
  @spec canvas(t(), Cauldron3D.Scene.Canvas.t()) :: Cauldron3D.Scene.Handle.t()
  def canvas(target, canvas)

  @doc "Defines a material and returns its handle."
  @spec material(t(), Cauldron3D.Scene.Material.t()) :: Cauldron3D.Scene.Handle.t()
  def material(target, material)

  @doc "Uploads a scatter, the places an instance draws its mesh at, and returns its handle."
  @spec scatter(t(), Cauldron3D.Scene.Scatter.t()) :: Cauldron3D.Scene.Handle.t()
  def scatter(target, scatter)

  @doc """
  Lets the target free a mesh, texture, material or scatter once no scene entry uses it. A
  `CauldronGPU` renderer frees a handle's object when the handle is no longer
  referenced, and answers `:ok` here.
  """
  @spec release(t(), Cauldron3D.Scene.Handle.t()) :: :ok
  def release(target, handle)

  @doc "What the target can do beyond drawing the scene (`Cauldron3D.Scene.Capabilities`)."
  @spec capabilities(t()) :: Cauldron3D.Scene.Capabilities.t()
  def capabilities(target)
end
