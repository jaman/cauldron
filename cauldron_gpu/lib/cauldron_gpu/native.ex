defmodule CauldronGPU.Native do
  @moduledoc """
  The compiled renderer: `priv/native/<system architecture>/cauldron_gpu.so`, loaded when
  the module loads. Call through `CauldronGPU`; these functions take and return the raw
  values the C++ side uses.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    architecture = to_string(:erlang.system_info(:system_architecture))
    path = Path.join([:code.priv_dir(:cauldron_gpu), "native", architecture, "cauldron_gpu"])

    with {:error, {_reason, text}} <- :erlang.load_nif(to_charlist(path), 0) do
      :persistent_term.put({__MODULE__, :error}, text)
    end

    :ok
  end

  @doc "Why the library did not load, or `nil` when it did."
  @spec load_error() :: charlist() | nil
  def load_error, do: :persistent_term.get({__MODULE__, :error}, nil)

  @doc false
  def open(_backend, _title, _width, _height, _shader_directory, _owner, _windowed),
    do: :erlang.nif_error(:not_loaded)

  @doc false
  def submit(_window, _binary), do: :erlang.nif_error(:not_loaded)
  @doc false
  def handle(_window, _drop_op, _id), do: :erlang.nif_error(:not_loaded)
  @doc false
  def close(_window), do: :erlang.nif_error(:not_loaded)
  @doc false
  def relative_mouse(_window, _enabled), do: :erlang.nif_error(:not_loaded)
  @doc false
  def capture(_window, _generated, _shared_memory), do: :erlang.nif_error(:not_loaded)
  @doc false
  def remove_shared_memory(_name), do: :erlang.nif_error(:not_loaded)
  @doc false
  def write_shared_memory(_name, _data), do: :erlang.nif_error(:not_loaded)
  @doc false
  def terminal_size, do: :erlang.nif_error(:not_loaded)
  @doc false
  def resize(_window, _width, _height), do: :erlang.nif_error(:not_loaded)
  @doc false
  def stats(_window), do: :erlang.nif_error(:not_loaded)
  @doc false
  def frames(_window), do: :erlang.nif_error(:not_loaded)
  @doc false
  def backends, do: :erlang.nif_error(:not_loaded)
end
