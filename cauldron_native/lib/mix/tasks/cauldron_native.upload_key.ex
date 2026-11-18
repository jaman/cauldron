defmodule Mix.Tasks.CauldronNative.UploadKey do
  @shortdoc "Makes the upload key that signs an app's Google Play builds"

  @moduledoc """
  Makes an upload key with the JDK's `keytool`: the key that signs each App Bundle sent
  to Google Play, while Play App Signing keeps the key that signs what users install.

      CAULDRON_ANDROID_STORE_PASSWORD=… CAULDRON_ANDROID_KEY_PASSWORD=… \\
        mix cauldron_native.upload_key --keystore ~/keys/my_app.jks --name "Example Ltd"

  The passwords come from `CAULDRON_ANDROID_STORE_PASSWORD` and
  `CAULDRON_ANDROID_KEY_PASSWORD`, the same variables a release build reads. Then name
  the keystore in the project's config, `android_signing: [keystore: "~/keys/my_app.jks",
  alias: "upload"]`.

  Keep the keystore and its passwords out of the project's repository and backed up: an
  app's later updates must be signed with the same upload key, or Google Play support
  has to reset it.

  ## Options

    * `--keystore` — where to write the keystore. Required; it must not exist yet
    * `--name` — the organisation or person the key names. Required
    * `--alias` — the key's alias. Default `upload`
  """

  use Mix.Task

  @switches [keystore: :string, name: :string, alias: :string]

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: @switches)
    keystore = Path.expand(opts[:keystore] || Mix.raise("--keystore is required"))
    name = opts[:name] || Mix.raise("--name is required")
    if File.exists?(keystore), do: Mix.raise("#{keystore} already exists")

    for variable <- ["CAULDRON_ANDROID_STORE_PASSWORD", "CAULDRON_ANDROID_KEY_PASSWORD"],
        System.get_env(variable) in [nil, ""],
        do: Mix.raise("#{variable} is not set")

    File.mkdir_p!(Path.dirname(keystore))

    keytool =
      System.find_executable("keytool") || Mix.raise("keytool, from a JDK, is not on the PATH")

    arguments =
      ~w(-genkeypair -noprompt -keyalg RSA -keysize 4096 -validity 10000) ++
        ["-keystore", keystore, "-alias", opts[:alias] || "upload"] ++
        ["-dname", "CN=#{escape(name)}, O=#{escape(name)}"] ++
        ["-storepass:env", "CAULDRON_ANDROID_STORE_PASSWORD"] ++
        ["-keypass:env", "CAULDRON_ANDROID_KEY_PASSWORD"]

    case System.cmd(keytool, arguments, stderr_to_stdout: true) do
      {_output, 0} -> Mix.shell().info("Wrote the upload key to #{keystore}")
      {output, _status} -> Mix.raise("keytool failed:\n" <> output)
    end
  end

  defp escape(text), do: String.replace(text, ~r/([,+"\\<>;=])/, "\\\\\\1")
end
