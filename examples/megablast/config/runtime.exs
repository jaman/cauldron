import Config

if scroll = System.get_env("MEGABLAST_SCROLL"),
  do: config(:megablast, scroll: String.to_float(scroll))

if shields = System.get_env("MEGABLAST_SHIELDS"),
  do: config(:megablast, shields: String.to_integer(shields))
