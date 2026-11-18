defmodule CauldronNative.Certificates do
  @moduledoc """
  The certificates the app trusts for TLS, loaded into `:public_key` at start so
  `:ssl`, `:httpc` and the libraries built on them can verify servers on the device:
  Android's own store (the updatable one in `/apex/com.android.conscrypt/cacerts`, else
  `/system/etc/security/cacerts`); on iOS and tvOS, which do not expose theirs, the
  Mozilla CA bundle `castore` ships; on macOS the system's, which `:public_key` reads
  itself.
  """

  @android_stores ["/apex/com.android.conscrypt/cacerts", "/system/etc/security/cacerts"]

  @doc "Load the certificates for `system` (`CauldronNative.Device.system/0`)."
  @spec load(CauldronNative.Device.system() | nil) :: :ok | {:error, term()}
  def load(:android) do
    case Enum.find(@android_stores, &File.dir?/1) do
      nil -> {:error, :no_store}
      store -> store |> bundle!() |> loaded()
    end
  end

  def load(system) when system in [:ios, :tvos], do: loaded(CAStore.file_path())
  def load(_system), do: :ok

  defp bundle!(store) do
    pem =
      store
      |> File.ls!()
      |> Enum.map_join("\n", &File.read!(Path.join(store, &1)))

    path = Path.join(System.tmp_dir!(), "cauldron_cacerts.pem")
    File.write!(path, pem)
    path
  end

  defp loaded(path) do
    case :public_key.cacerts_load(String.to_charlist(path)) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
