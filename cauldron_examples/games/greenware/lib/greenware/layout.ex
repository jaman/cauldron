defmodule Greenware.Layout do
  @moduledoc "Where things sit on the 640 by 360 canvas, shared by the world and the painter."

  @width 640
  @height 360

  def width, do: @width
  def height, do: @height

  def px({x, y}), do: {round(x * @width), round(y * @height)}

  def cursor(view), do: px(view.cursor)

  def in_rect?({x, y}, {left, top, width, height}),
    do: x >= left and y >= top and x < left + width and y < top + height

  def hub_slots(3), do: [{82, 138, 140, 122}, {250, 138, 140, 122}, {418, 138, 140, 122}]

  def hub_slots(4),
    do: [{40, 142, 128, 118}, {186, 142, 128, 118}, {332, 142, 128, 118}, {478, 142, 128, 118}]

  def hub_slots(2), do: [{160, 140, 145, 120}, {335, 140, 145, 120}]
  def hub_slots(1), do: [{250, 140, 145, 120}]
  def hub_slots(_), do: [{82, 138, 140, 122}, {250, 138, 140, 122}, {418, 138, 140, 122}]

  def field_rect, do: {120, 88, 288, 216}

  def field_cell({x, y}) do
    {left, top, width, height} = field_rect()

    if x >= left and y >= top and x < left + width and y < top + height do
      {div((x - left) * 96, width), div((y - top) * 72, height)}
    end
  end

  def tool_rect(index), do: {424, 92 + index * 26, 198, 23}

  def test_button, do: {412, 318, 86, 30}
  def reset_button, do: {504, 318, 62, 30}
  def back_button, do: {572, 318, 54, 30}

  def dialogue_rect, do: {28, 232, 584, 112}

  def choice_rect(index), do: {44 + index * 188, 176, 176, 124}

  def title_menu, do: {372, 140, 236, 196}

  def summary_menu, do: {220, 282, 200, 52}

  def card(scene_id) do
    case scene_id do
      :cup -> {300, 238}
      :key -> {420, 200}
      :wing -> {380, 168}
      :bucket -> {360, 220}
      :arm -> {380, 230}
      :dam -> {340, 226}
      :lamp -> {330, 220}
      :plate -> {360, 220}
      :doll -> {340, 218}
      :hub -> {330, 190}
      :face -> {382, 196}
      :music_box -> {360, 226}
      :bridge -> {340, 230}
      :heart -> {340, 218}
      :sky -> {360, 184}
      _ -> {340, 220}
    end
  end
end
