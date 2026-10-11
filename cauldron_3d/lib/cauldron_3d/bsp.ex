defmodule Cauldron3D.Bsp do
  @moduledoc """
  A world cut into convex leaves by a binary space partition, with its faces, textures,
  lightmaps, what each leaf can see, and its brush models.

  A loader fills the struct from its own file format; the engine draws it
  (`Cauldron3D.Bsp.Draw`), lights its faces (`Cauldron3D.Bsp.Surfaces`) and moves things
  through it (`Cauldron3D.Hull`).

    * `planes` — a tuple of `{normal, distance}`; a point `p` is in front when
      `Vec.dot(p, normal) - distance >= 0`
    * `nodes` — a tuple of `%{plane: index, front: child, back: child, mins: Vec, maxs: Vec}`;
      a child at or above zero is a node, below zero the leaf `-child - 1`
    * `leaves` — a tuple of `%{contents: integer, faces: [face index], mins: Vec, maxs: Vec}`
    * `faces` — a tuple of `Cauldron3D.Bsp.Face`
    * `textures` — a tuple of `%{name: String.t(), kind: kind, mips: [Texture.t()]}`, the
      mips halving in size, `kind` one of `:solid`, `:masked` (solid but see-through
      where it is colour 255), `:sky`, `:liquid` or `:hidden`
    * `lightmaps` — the lightmap bytes faces point into
    * `light_channels` — bytes per lightmap sample: 1 for a grey level, 3 for red, green
      and blue
    * `world_leaves` — how many leaves after leaf 0 belong to the world itself (model 0);
      the leaves after them belong to the brush models. `nil` when every leaf is the
      world's
    * `game` — the game the map was made for, `:quake` or `:half_life`
    * `visibility` — a tuple holding for each leaf a bitset of the leaves it can see
      (bit `i` of byte `div(i, 8)`, least significant first), or `nil` where it can see
      every world leaf; `nil` for a world that keeps none. A brush model's leaves are
      never among those seen
    * `models` — a tuple of `%{mins:, maxs:, origin:, heads: [node per hull], first_face:,
      face_count:}`; model 0 is the world itself
    * `hulls` — the collision hulls, as `Cauldron3D.Hull`s with the head of model 0

  Contents follow one convention: -1 empty, -2 solid, -3 water, -4 slime, -5 lava,
  -6 sky.
  """

  alias Cauldron3D.Vec

  @type kind :: :solid | :masked | :sky | :liquid | :hidden
  @type t :: %__MODULE__{
          planes: tuple(),
          nodes: tuple(),
          leaves: tuple(),
          faces: tuple(),
          textures: tuple(),
          lightmaps: binary(),
          light_channels: 1 | 3,
          visibility: tuple() | nil,
          world_leaves: non_neg_integer() | nil,
          game: :quake | :half_life,
          models: tuple(),
          hulls: [Cauldron3D.Hull.t()]
        }

  defstruct planes: {},
            nodes: {},
            leaves: {},
            faces: {},
            textures: {},
            lightmaps: <<>>,
            light_channels: 1,
            visibility: nil,
            world_leaves: nil,
            game: :quake,
            models: {},
            hulls: []

  @empty -1
  @solid -2

  @doc "The contents value for open space."
  @spec empty() :: integer()
  def empty, do: @empty

  @doc "The contents value for solid."
  @spec solid() :: integer()
  def solid, do: @solid

  @doc "The leaf `point` is in, walking from model `model`'s first node (default the world)."
  @spec leaf_at(t(), Vec.t(), non_neg_integer()) :: non_neg_integer()
  def leaf_at(%__MODULE__{} = bsp, point, model \\ 0) do
    %{heads: [head | _]} = elem(bsp.models, model)
    descend(bsp, head, point)
  end

  @doc "What `point` is inside: the contents of its leaf."
  @spec contents(t(), Vec.t()) :: integer()
  def contents(%__MODULE__{} = bsp, point), do: elem(bsp.leaves, leaf_at(bsp, point)).contents

  @doc "The leaves `leaf` can see, itself included, in ascending order."
  @spec visible_leaves(t(), non_neg_integer()) :: [non_neg_integer()]
  def visible_leaves(%__MODULE__{visibility: nil} = bsp, _leaf), do: all_world_leaves(bsp)

  def visible_leaves(%__MODULE__{} = bsp, leaf) do
    case elem(bsp.visibility, leaf) do
      nil -> all_world_leaves(bsp)
      bits -> [leaf | set_bits(bits, last_world_leaf(bsp) + 1)] |> Enum.uniq() |> Enum.sort()
    end
  end

  defp all_world_leaves(bsp), do: Enum.to_list(0..last_world_leaf(bsp))

  defp last_world_leaf(%__MODULE__{world_leaves: nil} = bsp), do: tuple_size(bsp.leaves) - 1
  defp last_world_leaf(%__MODULE__{world_leaves: count}), do: count

  @doc "Whether leaf `to` is among those leaf `from` can see."
  @spec sees?(t(), non_neg_integer(), non_neg_integer()) :: boolean()
  def sees?(%__MODULE__{visibility: nil}, _from, _to), do: true

  def sees?(%__MODULE__{} = bsp, from, to) do
    case elem(bsp.visibility, from) do
      nil -> true
      _bits when from == to -> true
      bits -> bit?(bits, to)
    end
  end

  @doc "The leaves whose boxes overlap the box `mins`..`maxs`."
  @spec leaves_touching(t(), Vec.t(), Vec.t()) :: [non_neg_integer()]
  def leaves_touching(%__MODULE__{} = bsp, mins, maxs) do
    %{heads: [head | _]} = elem(bsp.models, 0)
    gather(bsp, head, mins, maxs, [])
  end

  @doc "The plane of `index`: `{normal, distance}`."
  @spec plane(t(), non_neg_integer()) :: {Vec.t(), float()}
  def plane(%__MODULE__{planes: planes}, index), do: elem(planes, index)

  defp descend(_bsp, child, _point) when child < 0, do: -child - 1

  defp descend(bsp, node_index, point) do
    node = elem(bsp.nodes, node_index)
    {normal, distance} = elem(bsp.planes, node.plane)

    if Vec.dot(point, normal) - distance >= 0,
      do: descend(bsp, node.front, point),
      else: descend(bsp, node.back, point)
  end

  defp gather(_bsp, child, _mins, _maxs, acc) when child < 0, do: [-child - 1 | acc]

  defp gather(bsp, node_index, mins, maxs, acc) do
    node = elem(bsp.nodes, node_index)
    {normal, distance} = elem(bsp.planes, node.plane)
    {near, far} = box_extremes(normal, mins, maxs)
    front? = Vec.dot(far, normal) - distance >= 0
    back? = Vec.dot(near, normal) - distance < 0
    acc = if front?, do: gather(bsp, node.front, mins, maxs, acc), else: acc
    if back?, do: gather(bsp, node.back, mins, maxs, acc), else: acc
  end

  defp box_extremes({nx, ny, nz}, {x0, y0, z0}, {x1, y1, z1}) do
    near =
      {if(nx >= 0, do: x0, else: x1), if(ny >= 0, do: y0, else: y1),
       if(nz >= 0, do: z0, else: z1)}

    far =
      {if(nx >= 0, do: x1, else: x0), if(ny >= 0, do: y1, else: y0),
       if(nz >= 0, do: z1, else: z0)}

    {near, far}
  end

  defp set_bits(bits, count) do
    for {byte, index} <- Enum.with_index(:binary.bin_to_list(bits)),
        byte != 0,
        bit <- 0..7,
        Bitwise.band(byte, Bitwise.bsl(1, bit)) != 0,
        leaf = index * 8 + bit,
        leaf < count,
        do: leaf
  end

  defp bit?(bits, leaf) do
    byte_index = div(leaf, 8)

    byte_index < byte_size(bits) and
      Bitwise.band(:binary.at(bits, byte_index), Bitwise.bsl(1, rem(leaf, 8))) != 0
  end
end
