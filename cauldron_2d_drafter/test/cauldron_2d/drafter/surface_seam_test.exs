defmodule Cauldron2D.Drafter.SurfaceSeamTest do
  @moduledoc """
  The pixels a patched isometric frame actually sends: a patch has to carry the same
  pixels the stored pane carries under it, or the scenery steps at the patch's edge as
  the camera roams.
  """

  use ExUnit.Case, async: false

  alias Cauldron2D.Atlas
  alias Cauldron2D.Drafter.Surface
  alias Drafter.Session.Context
  alias FrenchCurve.Raster

  setup_all do
    Atlas.new(:seam_widget, tile: 8, void: {6, 7, 11})
    |> Atlas.put(:grass, Raster.new(8, 8, background: {40, 160, 40, 255}))
    |> Atlas.put(:pillar, Raster.new(8, 8, background: {160, 120, 80, 255}),
      height: 2,
      faces: %{top: Raster.new(8, 8, background: {200, 40, 40, 255})}
    )
    |> Atlas.put(:hero, Raster.new(8, 8, background: {245, 232, 200, 255}))
    |> Atlas.install()

    :ok
  end

  setup do
    Context.put_terminal_env(%{"TERM" => "xterm-kitty"})
    Context.put_terminal_protocol(:kitty)
    Context.put_cell_size({10, 20})

    on_exit(fn ->
      Process.delete(:drafter_terminal_env)
      Process.delete(:drafter_terminal_protocol)
      Process.delete(:drafter_cell_size)
    end)

    :ok
  end

  defp rect, do: %{x: 0, y: 0, width: 40, height: 12}

  defp mount(id, focus) do
    Surface.mount(%{
      atlas: :seam_widget,
      projection: :iso,
      focus: focus,
      cell: fn {x, y} ->
        if rem(x + y, 3) == 0, do: {:grass, [:pillar], nil}, else: {:grass, [], nil}
      end,
      movers: [{:hero, focus, 0.0}],
      placements: true,
      compress: false,
      id: id
    })
  end

  defp images(bytes) do
    ~r/\e_G([^;\e]*);([^\e]*)\e\\/
    |> Regex.scan(bytes)
    |> Enum.reduce({%{}, nil}, fn [_whole, control, payload], {held, open} ->
      keys = control |> String.split(",") |> Map.new(&control_pair/1)

      case {keys["a"], keys["i"]} do
        {"t", id} ->
          {Map.put(held, id, %{
             width: String.to_integer(keys["s"]),
             height: String.to_integer(keys["v"]),
             payload: payload
           }), if(keys["m"] == "1", do: id, else: nil)}

        {nil, nil} when open != nil ->
          {Map.update!(held, open, &%{&1 | payload: &1.payload <> payload}),
           if(keys["m"] == "1", do: open, else: nil)}

        _other ->
          {held, open}
      end
    end)
    |> elem(0)
    |> Map.new(fn {id, image} ->
      {id, %{image | payload: Base.decode64!(image.payload)}}
    end)
  end

  defp control_pair(pair) do
    case String.split(pair, "=") do
      [key, value] -> {key, value}
      [key] -> {key, ""}
    end
  end

  defp source(bytes, id) do
    [[_whole, x, y]] = Regex.scan(~r/a=p,i=#{id},[^;]*?,x=(\d+),y=(\d+)/, bytes)
    {String.to_integer(x), String.to_integer(y)}
  end

  defp patch_cell(bytes, id) do
    [[_whole, column, row]] =
      Regex.scan(~r/\e\[(\d+);(\d+)H\e_Ga=p,i=#{id},/, bytes)

    {String.to_integer(row) - 1, String.to_integer(column) - 1}
  end

  defp crop(%{width: width, payload: payload}, {x, y}, {w, h}) do
    for row <- y..(y + h - 1), into: <<>> do
      binary_part(payload, (row * width + x) * 4, w * 4)
    end
  end

  @roaming [{0.13, 0.07}, {0.37, 0.21}, {0.5, 0.5}, {0.62, 0.44}, {0.87, 0.31}, {1.31, 0.87}]

  test "a patch drawn while roaming carries the pixels the stored pane carries beneath it" do
    id = :seam_roaming
    scene = Integer.to_string(FrenchCurve.image_id({id, :scene}))
    patch = Integer.to_string(FrenchCurve.image_id({id, :patch, 20_000}))
    start = {5.0, 5.0}

    first = mount(id, start) |> Surface.image(rect(), id) |> elem(0) |> IO.iodata_to_binary()
    assert %{^scene => stored} = images(first), "the first frame should store the pane"

    for {dx, dy} <- @roaming do
      focus = {elem(start, 0) + dx, elem(start, 1) + dy}
      state = mount(id, focus)
      bytes = state |> Surface.image(rect(), id) |> elem(0) |> IO.iodata_to_binary()
      sent = images(bytes)

      refute Map.has_key?(sent, scene),
             "roaming to #{inspect(focus)} sent the pane again, so this proves nothing"

      assert %{^patch => drawn} = sent, "no patch was sent at #{inspect(focus)}"

      {sx, sy} = source(bytes, scene)
      {column, row} = patch_cell(bytes, patch)
      {_size, {across, down}, _aspect} = Surface.picture(state, rect())

      assert crop(drawn, {0, 0}, {drawn.width, drawn.height}) ==
               crop(
                 stored,
                 {sx + round(column * across), sy + round(row * down)},
                 {drawn.width, drawn.height}
               ),
             "at #{inspect(focus)} the patch and the pane beneath it disagree, " <>
               "so scenery steps at the patch edge"
    end
  end
end
