defmodule Cauldron2D.Assets.Manifest do
  @moduledoc """
  A game's `assets.exs`: what art to ask the image model for, in what style, and how to
  finish each picture as pixel art.

      %{
        project: "cistern",
        model: "flux2_klein_4b",
        style: "16-bit pixel art game sprite, chunky pixels, clean dark outline",
        background: {255, 0, 255},
        palette: 24,
        assets: [
          jar: [prompt: "a round terracotta clay water jar", fit: {16, 16}, count: 4],
          squall: [prompt: "a grumpy storm cloud with a face", fit: {48, 32}, palette: 10],
          dusk: [prompt: "a dusk sky over desert rooftops", size: {1024, 512}, background: nil,
                 finish: [size: {256, 128}, dither: :bayer4]]
        ]
      }

  ## Top level

    * `:project` — the Studio project the pictures are kept in. Required
    * `:model` — the image model, as the Studio's `list_models` names it. Default
      `"flux2_klein_4b"`
    * `:style` — words put before every prompt. Default `""`
    * `:negative` — what to keep out of every picture and clip, for models that take it. Default none
    * `:background` — `{r, g, b}`: every prompt asks for a flat background of this colour,
      and finishing makes it clear. `nil` asks for none. Default magenta
    * `:palette` — the colours every picture is held to: `{r, g, b}` tuples or `#rrggbb`
      strings, or a count chosen from each picture. Default none
    * `:outline` — `{r, g, b}` drawn round every finished sprite. Default none

  ## Each asset

  `name: options`, the name the finished picture is written under (`<name>.png`), with
  `:prompt` (required), `:count` (candidates to choose between, default 1), `:size`
  (`{width, height}` asked of the model, default `{512, 512}`), `:seed`, `:model`,
  `:background`, `:palette`, `:outline` and `:style` over the top level's, `:fit` (the
  most the finished picture may be, `{width, height}`), and `:finish`, more
  `Linocut.Pixelate.finish/2` options.

  An asset with `from: other` is an edit of the picture chosen for asset `other`, listed
  before it: its `:prompt` is the instruction (`"the same cloud, now grinning"`), given
  as it is, and the picture keeps `other`'s background.

  With `video: [frames: 33, keep: 8, from: 0.2, to: 0.7]` as well it is an animation:
  the chosen picture of `other` set moving as `:prompt` says (`"he runs on the spot"`),
  `frames` long (one more than a multiple of four, at 16 a second), and `keep` frames of
  it kept between those shares of the clip, finished together as one strip
  `<name>.png`. `:size` is the clip's, `{480, 720}` say; `:model` in `video` chooses the
  model (default `"wan21_vace_1_3b"`).

  An asset with `rig: id` is an animation of a character rigged in the Studio
  (`make_rig`; `id` is the rig's library id). `:motion` describes the movement and how
  it is shown, and the frames, rendered on a transparent background, are finished as
  one strip `<name>.png` as a clip's are. `:motion` takes `:prompt` (the movement,
  required: `"a man runs forward at a steady pace"`), `:seconds` (default `4`), `:model`
  (a motion model; the Studio's first by default), `:yaw` (the angle it is seen from:
  `0` faces the viewer, `90` faces right; default `90`), `:loop` (a seamless loop of
  that many cycles, rendered exactly `:keep` frames long), `:keep` (the frames kept:
  for a loop its length, otherwise that many spread between the `:from` and `:to`
  shares of the movement; every frame when left out) and `:arm_swing`
  (`[forward: degrees, back: degrees, elbow: degrees]`: arm action added to a walk or
  run). `:count` makes that many movements to choose between, from seeds counting up
  from `:seed`.
  """

  alias Cauldron2D.Assets.Spec

  @magenta {255, 0, 255}

  @type t :: %{project: String.t(), specs: [Spec.t()]}

  @doc "The manifest in `path`, its assets as `Cauldron2D.Assets.Spec`s."
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(path) do
    with {:ok, text} <- File.read(path),
         {%{} = manifest, _binding} <- Code.eval_string(text, [], file: path) do
      read(manifest)
    else
      {:error, reason} -> {:error, {:manifest, path, reason}}
      {other, _binding} -> {:error, {:manifest, path, {:not_a_map, other}}}
    end
  end

  @doc "A manifest read from its map."
  @spec read(map()) :: {:ok, t()} | {:error, term()}
  def read(%{project: project, assets: assets} = manifest) when is_binary(project) do
    defaults = %{
      model: Map.get(manifest, :model, "flux2_klein_4b"),
      style: Map.get(manifest, :style, ""),
      negative: Map.get(manifest, :negative),
      background: Map.get(manifest, :background, @magenta),
      palette: manifest |> Map.get(:palette) |> colours(),
      outline: Map.get(manifest, :outline)
    }

    {:ok,
     %{
       project: project,
       specs: Enum.map(assets, fn {name, opts} -> spec(name, opts, defaults) end)
     }}
  end

  def read(_manifest), do: {:error, {:manifest, :needs_project_and_assets}}

  defp spec(name, opts, defaults) do
    rig = Keyword.get(opts, :rig)
    motion = Keyword.get(opts, :motion)
    background = if rig, do: nil, else: Keyword.get(opts, :background, defaults.background)

    from = Keyword.get(opts, :from)

    %Spec{
      name: name,
      from: from,
      video: Keyword.get(opts, :video),
      rig: rig,
      motion: motion,
      prompt:
        if(rig,
          do: Keyword.fetch!(motion, :prompt),
          else: words(from, opts, defaults, background)
        ),
      negative: Keyword.get(opts, :negative, defaults.negative),
      model: Keyword.get(opts, :model, defaults.model),
      size: Keyword.get(opts, :size, {512, 512}),
      count: Keyword.get(opts, :count, 1),
      seed: Keyword.get(opts, :seed),
      finish: finish(opts, defaults, background)
    }
  end

  defp words(nil, opts, defaults, background),
    do:
      prompt(Keyword.get(opts, :style, defaults.style), Keyword.fetch!(opts, :prompt), background)

  defp words(_from, opts, _defaults, _background), do: Keyword.fetch!(opts, :prompt)

  defp prompt(style, prompt, background) do
    [style, prompt, backdrop(background)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(", ")
  end

  defp backdrop(nil), do: nil

  defp backdrop({r, g, b}),
    do:
      "centred, alone on a flat solid background of colour #" <>
        hex(r) <> hex(g) <> hex(b) <> ", no shadow, no text"

  defp hex(byte), do: byte |> Integer.to_string(16) |> String.pad_leading(2, "0")

  defp finish(opts, defaults, background) do
    [
      key: if(background, do: :border),
      palette: opts |> Keyword.get(:palette) |> colours() || defaults.palette,
      outline: Keyword.get(opts, :outline, defaults.outline),
      fit: Keyword.get(opts, :fit)
    ]
    |> Keyword.merge(Keyword.get(opts, :finish, []))
    |> Enum.reject(fn {_key, value} -> value == nil end)
  end

  defp colours(nil), do: nil
  defp colours(count) when is_integer(count), do: count
  defp colours(list) when is_list(list), do: Enum.map(list, &colour/1)

  defp colour({_r, _g, _b} = rgb), do: rgb

  defp colour("#" <> hex) do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end
end
