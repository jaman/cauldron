defmodule Cauldron2D.GameMaker.Script do
  @moduledoc """
  A script (a `SCPT` entry): a name and the code entry it runs, `nil` for none.
  `constructor` marks a GameMaker 2.3 function declared as a constructor. A game
  compiled to native code keeps a script's code in its executable as the function
  `gml_Script_<name>`.
  """

  alias Cauldron2D.GameMaker.Bytes

  @enforce_keys [:name, :code]
  defstruct [:name, :code, constructor: false]

  @type t :: %__MODULE__{name: String.t(), code: non_neg_integer() | nil, constructor: boolean()}

  @constructor 0x80000000

  @doc "The script at `at`."
  @spec read(binary(), non_neg_integer()) :: t()
  def read(data, at) do
    name = Bytes.string_at(data, at)

    case Bytes.u32(data, at + 4) do
      0xFFFFFFFF ->
        %__MODULE__{name: name, code: nil}

      code ->
        %__MODULE__{
          name: name,
          code: Bitwise.band(code, Bitwise.bnot(@constructor)),
          constructor: Bitwise.band(code, @constructor) != 0
        }
    end
  end
end
