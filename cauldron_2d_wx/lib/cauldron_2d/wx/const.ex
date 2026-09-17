defmodule Cauldron2D.Wx.Const do
  @moduledoc """
  The wxWidgets constants this package uses, by the names `wx.hrl` gives them, as
  functions: the fixed ones as numbers, the ones wx decides at runtime through
  wx's `wxe_util:get_const/1` (so `wx:new/0` must have run).

      Cauldron2D.Wx.Const.wants_chars()
      Cauldron2D.Wx.Const.bg_style_paint()
  """

  @fixed %{
    wants_chars: 262_144,
    full_repaint_on_resize: 65_536,
    tab_traversal: 524_288,
    border_none: 2_097_152,
    id_any: -1,
    expand: 8_192,
    all: 240,
    left: 16,
    right: 32,
    top: 64,
    bottom: 128,
    horizontal: 4,
    vertical: 8,
    align_center_vertical: 2_048,
    align_center_horizontal: 256,
    lc_report: 32,
    lc_single_sel: 8_192,
    list_autosize: -1,
    list_next_all: 1,
    list_state_selected: 4,
    te_password: 2_048,
    te_process_enter: 1_024,
    te_multiline: 32,
    te_readonly: 16,
    default_frame_style: 541_072_960,
    teletype: 76,
    normal: 90,
    default_family: 70,
    key_return: 13,
    key_escape: 27,
    key_space: 32,
    key_shift: 306,
    key_left: 314,
    key_up: 315,
    key_right: 316,
    key_down: 317,
    mouse_btn_left: 1,
    mouse_btn_middle: 2,
    mouse_btn_right: 3
  }

  for {name, value} <- @fixed do
    @doc "wx's `#{name}`."
    @spec unquote(name)() :: integer()
    def unquote(name)(), do: unquote(value)
  end

  @doc "`wxBG_STYLE_PAINT`, from a running wx."
  @spec bg_style_paint() :: integer()
  def bg_style_paint, do: :wxe_util.get_const(:wxBG_STYLE_PAINT)

  @doc "`wxIMAGE_QUALITY_NEAREST`, from a running wx."
  @spec image_quality_nearest() :: integer()
  def image_quality_nearest, do: :wxe_util.get_const(:wxIMAGE_QUALITY_NEAREST)

  @doc "`wxFONTWEIGHT_NORMAL`, from a running wx."
  @spec fontweight_normal() :: integer()
  def fontweight_normal, do: :wxe_util.get_const(:wxFONTWEIGHT_NORMAL)

  @doc "`wxFONTWEIGHT_BOLD`, from a running wx."
  @spec fontweight_bold() :: integer()
  def fontweight_bold, do: :wxe_util.get_const(:wxFONTWEIGHT_BOLD)
end
