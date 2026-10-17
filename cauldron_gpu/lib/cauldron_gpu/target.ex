defprotocol CauldronGPU.Target do
  @moduledoc """
  Anything a scene can be sent to: a `CauldronGPU` renderer in the VM, a
  `CauldronGPU.Host` in its own process, or a browser scene (`Cauldron3D.Net.Scene`).
  The converters (`CauldronGPU.Bsp`, `CauldronGPU.AliasModel`, `CauldronGPU.StudioModel`,
  `CauldronGPU.Sectors`) upload through it, so they work with every one.
  """

  @doc "Sends one tick of changes (`CauldronGPU.Stream`)."
  @spec submit(t(), [CauldronGPU.Stream.change()]) :: :ok | {:error, term()}
  def submit(target, changes)

  @doc "Uploads a mesh and returns its handle."
  @spec mesh(t(), CauldronGPU.Mesh.t()) :: CauldronGPU.Handle.t()
  def mesh(target, mesh)

  @doc "Uploads a texture and returns its handle."
  @spec texture(t(), CauldronGPU.Texture.t()) :: CauldronGPU.Handle.t()
  def texture(target, texture)

  @doc "Makes a canvas, a texture drawn into by 2D layers, and returns its handle."
  @spec canvas(t(), CauldronGPU.Canvas.t()) :: CauldronGPU.Handle.t()
  def canvas(target, canvas)

  @doc "Defines a material and returns its handle."
  @spec material(t(), CauldronGPU.Material.t()) :: CauldronGPU.Handle.t()
  def material(target, material)

  @doc """
  Lets the target free a mesh, texture or material once no scene entry uses it. A
  `CauldronGPU` renderer frees a handle's object when the handle is no longer
  referenced, and answers `:ok` here.
  """
  @spec release(t(), CauldronGPU.Handle.t()) :: :ok
  def release(target, handle)
end

defimpl CauldronGPU.Target, for: CauldronGPU do
  def submit(gpu, changes), do: CauldronGPU.submit(gpu, changes)
  def mesh(gpu, mesh), do: CauldronGPU.mesh(gpu, mesh)
  def texture(gpu, texture), do: CauldronGPU.texture(gpu, texture)
  def canvas(gpu, canvas), do: CauldronGPU.canvas(gpu, canvas)
  def material(gpu, material), do: CauldronGPU.material(gpu, material)
  def release(_gpu, _handle), do: :ok
end

defimpl CauldronGPU.Target, for: CauldronGPU.Host do
  def submit(host, changes), do: CauldronGPU.Host.submit(host, changes)
  def mesh(host, mesh), do: CauldronGPU.Host.mesh(host, mesh)
  def texture(host, texture), do: CauldronGPU.Host.texture(host, texture)
  def canvas(host, canvas), do: CauldronGPU.Host.canvas(host, canvas)
  def material(host, material), do: CauldronGPU.Host.material(host, material)
  def release(host, handle), do: CauldronGPU.Host.release(host, handle)
end
