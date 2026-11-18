defmodule CauldronNative.Native do
  @moduledoc """
  The NIF a mobile app links into its BEAM. It exists only inside an app built by
  `mix cauldron_native.build`, linked statically as `cauldron_native`; anywhere else
  `loaded/0` is `false` and the other functions raise.
  """

  @on_load :load_nif

  @doc false
  def load_nif do
    _ = :erlang.load_nif(~c"cauldron_native", 0)
    :ok
  end

  @doc "Whether the app's native side is linked in."
  @spec loaded() :: boolean()
  def loaded, do: false

  @doc "Send the screen's events to `pid`."
  @spec subscribe(pid()) :: :ok
  def subscribe(_pid), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Show `rgba`, `width` by `height` pixels."
  @spec present(pos_integer(), pos_integer(), binary()) :: :ok
  def present(_width, _height, _rgba), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Draw the packed overlay over the picture."
  @spec overlay(binary()) :: :ok
  def overlay(_packed), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "The screen as last reported, or `nil` before the first report."
  @spec screen() :: map() | nil
  def screen, do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "The fold as last reported, or `nil` on a device that has reported none."
  @spec posture() :: map() | nil
  def posture, do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "The handle of the app's graphics surface, or `{:error, :unavailable}`."
  @spec gpu_surface() :: {:ok, non_neg_integer()} | {:error, :unavailable}
  def gpu_surface, do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Hide the graphics surface, so pictures from `present/3` show again."
  @spec hide_gpu_surface() :: :ok
  def hide_gpu_surface, do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Send the native screen a patch of its controls, as `CauldronNative.UI.Tree.encode/1` writes it."
  @spec ui(binary()) :: :ok
  def ui(_patch), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Send the native side a request of `CauldronNative.Device`'s, as JSON."
  @spec request(binary()) :: :ok
  def request(_json), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc """
  Send `pid` the platform's state that the runtime keeps up to date, as
  `{:cauldron_native, :network, json}` with the default network's DNS servers; the last
  one known is sent at once.
  """
  @spec watch_system(pid()) :: :ok
  def watch_system(_pid), do: :erlang.nif_error(:not_in_a_mobile_app)

  @doc "Close the app, where the platform allows it."
  @spec quit() :: :ok
  def quit, do: :erlang.nif_error(:not_in_a_mobile_app)
end
