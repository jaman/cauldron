defmodule CauldronNative.Build.DriverTab do
  @moduledoc """
  The emulator's table of static NIFs for one app: OTP's own `driver_tab.c` with the
  app's NIFs added, compiled for the platform. The emulator finds a static NIF by the
  module that calls `:erlang.load_nif/2`, so each NIF here loads whatever path its
  module asks for.
  """

  alias CauldronNative.Build.{Otp, Platform, Shell}

  @doc "The object file of the table naming OTP's NIFs and `names`, written under `folder`."
  @spec compile!([String.t()], Platform.t(), Otp.t(), String.t()) :: String.t()
  def compile!(names, platform, otp, folder) do
    File.mkdir_p!(folder)
    source = Path.join(folder, "driver_tab.c")
    object = Path.join(folder, "driver_tab.o")
    File.write!(source, with_nifs(File.read!(otp.driver_tab), names))
    [cc | cc_arguments] = String.split(platform.cc)

    Shell.run!(
      cc,
      cc_arguments ++
        String.split(platform.cflags) ++
        otp.driver_tab_flags ++ ["-c", source, "-o", object],
      log: Path.join(folder, "driver_tab.log")
    )

    object
  end

  @doc "OTP's `driver_tab.c` text with the NIFs `names` declared and listed."
  @spec with_nifs(String.t(), [String.t()]) :: String.t()
  def with_nifs(text, names) do
    declarations = Enum.map_join(names, &"void *#{&1}_nif_init(void);\n")
    entries = Enum.map_join(names, &"    {&#{&1}_nif_init, 1, THE_NON_VALUE, NULL},\n")
    [head, table] = String.split(text, "ErtsStaticNif erts_static_nif_tab[] =", parts: 2)
    [listed, tail] = String.split(table, "    {NULL}\n};", parts: 2)

    head <>
      declarations <>
      "ErtsStaticNif erts_static_nif_tab[] =" <> listed <> entries <> "    {NULL}\n};" <> tail
  end
end
