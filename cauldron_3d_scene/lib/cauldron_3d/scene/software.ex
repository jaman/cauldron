if Code.ensure_loaded?(Cauldron3D.Render) do
  defmodule Cauldron3D.Scene.Software do
    @moduledoc """
    A `Cauldron3D.Scene.Target` drawn on the CPU by `cauldron_3d`, for a machine whose
    graphics card will not draw a scene: the same scene a game sends `cauldron_gpu`,
    drawn more plainly (`Cauldron3D.Scene.Software.Picture` lists what is drawn) and
    handed, frame by frame, to a function of the caller's.

        {:ok, software} =
          Cauldron3D.Scene.Software.open(
            width: 480,
            height: 270,
            present: fn rgba, width, height -> show(rgba, width, height) end
          )

        cube = Cauldron3D.Scene.Target.mesh(software, Cauldron3D.Scene.Mesh.cube(1.0))
        Cauldron3D.Scene.Target.submit(software, [{:instance, 1, %Cauldron3D.Scene.Instance{mesh: cube}}, %Cauldron3D.Scene.Camera{position: {0.0, 0.0, 4.0}}])

    The renderer is a process linked to the caller. Uploads and changes are sent to it
    without waiting; it draws a frame once the changes sent so far are applied, so while
    drawing takes longer than the game's tick the frames shown skip ahead to the latest
    scene. `present` is called in the renderer's process with the frame's RGBA pixels,
    rows from the top, `width * height * 4` bytes.

    Its capabilities (`Cauldron3D.Scene.Target.capabilities/1`) are none of the effects.

    ## Options

      * `:width`, `:height` — the size frames are drawn at, in pixels; required
      * `:present` — `fn rgba, width, height -> any end`; required
      * `:decode` — `fn texture -> {:ok, texture} | {:error, reason} end`, turning a
        texture holding a PNG or JPEG file into RGBA (`CauldronGPU.decode/1` where
        `cauldron_gpu` is loaded); without it such textures are not drawn
    """

    use GenServer

    alias Cauldron3D.Scene.{
      Canvas,
      Capabilities,
      Handle,
      Material,
      Mesh,
      Scatter,
      Stream,
      Texture
    }

    alias Cauldron3D.Scene.Host.Record
    alias Cauldron3D.Scene.Software.{Picture, Resources}

    @type t :: %__MODULE__{server: pid(), ids: :atomics.atomics_ref()}

    @enforce_keys [:server, :ids]
    defstruct [:server, :ids]

    @doc "Starts a renderer linked to the caller."
    @spec open(keyword()) :: {:ok, t()} | {:error, term()}
    def open(opts) do
      with {:ok, server} <- GenServer.start_link(__MODULE__, opts),
           do: {:ok, %__MODULE__{server: server, ids: :atomics.new(1, signed: false)}}
    end

    @doc "Sends one tick of changes (`Cauldron3D.Scene.Stream`)."
    @spec submit(t(), [Stream.change()]) :: :ok
    def submit(%__MODULE__{server: server}, changes),
      do: GenServer.cast(server, {:changes, changes})

    @doc "Uploads a mesh and returns its handle."
    @spec mesh(t(), Mesh.t()) :: Handle.t()
    def mesh(software, %Mesh{} = mesh), do: upload(software, :mesh, mesh, [])

    @doc "Uploads a texture and returns its handle."
    @spec texture(t(), Texture.t()) :: Handle.t()
    def texture(software, %Texture{} = texture), do: upload(software, :texture, texture, [])

    @doc "Makes a canvas, which this renderer leaves transparent, and returns its handle."
    @spec canvas(t(), Canvas.t()) :: Handle.t()
    def canvas(software, %Canvas{} = canvas), do: upload(software, :texture, canvas, [], :canvas)

    @doc "Defines a material and returns its handle."
    @spec material(t(), Material.t()) :: Handle.t()
    def material(software, %Material{} = material),
      do: upload(software, :material, material, Material.textures(material))

    @doc "Keeps a scatter and returns its handle. This renderer draws a scattered instance once, at its own place."
    @spec scatter(t(), Scatter.t()) :: Handle.t()
    def scatter(software, %Scatter{} = scatter), do: upload(software, :scatter, scatter, [])

    @doc "Lets the renderer drop a mesh, texture or material once no scene entry uses it."
    @spec release(t(), Handle.t()) :: :ok
    def release(%__MODULE__{server: server}, %Handle{kind: kind, id: id}),
      do: GenServer.cast(server, {:release, kind, id})

    @doc "Draws frames at `{width, height}` from now on."
    @spec resize(t(), pos_integer(), pos_integer()) :: :ok
    def resize(%__MODULE__{server: server}, width, height),
      do: GenServer.cast(server, {:resize, width, height})

    @doc "Stops the renderer."
    @spec close(t()) :: :ok
    def close(%__MODULE__{server: server}), do: GenServer.stop(server)

    defp upload(software, kind, value, keeps, change \\ nil) do
      id = :atomics.add_get(software.ids, 1, 1)
      GenServer.cast(software.server, {:changes, [{change || kind, id, value}]})
      %Handle{kind: kind, id: id, ref: make_ref(), keeps: keeps}
    end

    @impl GenServer
    def init(opts) do
      {:ok,
       %{
         record: Record.new(),
         resources: Resources.new(Keyword.get(opts, :decode)),
         size: {Keyword.fetch!(opts, :width), Keyword.fetch!(opts, :height)},
         present: Keyword.fetch!(opts, :present),
         due?: false
       }}
    end

    @impl GenServer
    def handle_cast({:changes, changes}, state) do
      record = Record.apply_changes(state.record, changes)

      resources =
        changes
        |> Enum.reduce(state.resources, &Resources.change(&2, &1))
        |> Resources.kept(record)

      {:noreply, due(%{state | record: record, resources: resources})}
    end

    def handle_cast({:release, kind, id}, state) do
      record = Record.release(state.record, kind, id)
      {:noreply, %{state | record: record, resources: Resources.kept(state.resources, record)}}
    end

    def handle_cast({:resize, width, height}, state),
      do: {:noreply, due(%{state | size: {width, height}})}

    @impl GenServer
    def handle_info(:draw, state) do
      {width, height} = state.size

      state.present.(Picture.draw(state.record, state.resources, state.size), width, height)

      {:noreply, %{state | due?: false}}
    end

    defp due(%{due?: true} = state), do: state

    defp due(state) do
      send(self(), :draw)
      %{state | due?: true}
    end

    defimpl Cauldron3D.Scene.Target do
      def submit(software, changes), do: @for.submit(software, changes)
      def mesh(software, mesh), do: @for.mesh(software, mesh)
      def texture(software, texture), do: @for.texture(software, texture)
      def canvas(software, canvas), do: @for.canvas(software, canvas)
      def material(software, material), do: @for.material(software, material)
      def scatter(software, scatter), do: @for.scatter(software, scatter)
      def release(software, handle), do: @for.release(software, handle)
      def capabilities(_software), do: %Capabilities{}
    end
  end
end
