defmodule CauldronNative.UI.Node do
  @moduledoc """
  One control of an app's screen (`CauldronNative.UI`): its type, its key among its
  siblings, its properties, its children, and how a value from the platform becomes the
  app's (`CauldronNative.UI.Value`).
  """

  @enforce_keys [:type]
  defstruct type: nil, key: nil, props: %{}, children: [], decode: nil

  @type t :: %__MODULE__{
          type: atom(),
          key: term(),
          props: map(),
          children: [t()],
          decode: CauldronNative.UI.Value.decode()
        }
end
