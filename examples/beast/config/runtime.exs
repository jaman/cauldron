import Config

if run = System.get_env("BEAST_RUN"), do: config(:beast, run: String.to_float(run))
if lives = System.get_env("BEAST_LIVES"), do: config(:beast, lives: String.to_integer(lives))
