defmodule Linocut.Derive do
  @moduledoc """
  A picture made from another by a short line of operations, so one drawing gives many
  views: a recoloured costume, a mirrored heading, a hat laid on.

      from knight; colour C #c02020; flip h
      from walk; frame 2; over hat 0 -2

  The operations, separated by `;`, in the order they run:

    * `from NAME` — the picture to start from; always first
    * `colour KEY COLOUR` (or `color`) — what `KEY` means, as a palette line takes it
    * `swap KEY KEY` — exchange what two keys mean
    * `flip h` / `flip v` — mirror left to right, or top to bottom
    * `turn 90` / `180` / `270` — clockwise, a quarter turn at a time
    * `shift DX DY` — move the picture, what leaves the edge lost, what enters transparent
    * `frame N` — keep the `N`th frame alone, counting from 1
    * `reverse` — the frames in the other order
    * `over NAME [DX DY]` — lay `NAME`'s first frame on every frame, its transparent
      keys letting the picture through, moved by `DX DY`; the palettes are merged, and a
      key the two pictures use for different colours is refused

  Everything works on the text of a `.pic` — keys, not pixels — so a derived picture is
  a picture like any other, edited in the same editors and rendered the same way.
  `derive/2` takes the line and a function from a name to the text it names — `{:ok,
  text}`, `:error` for a name it does not know, or `{:error, message}` with a reason of
  its own.
  """

  alias Linocut.Pic

  @type op ::
          {:from, String.t()}
          | {:colour, String.t(), String.t()}
          | {:swap, String.t(), String.t()}
          | {:flip, :h | :v}
          | {:turn, 90 | 180 | 270}
          | {:shift, integer(), integer()}
          | {:frame, pos_integer()}
          | :reverse
          | {:over, String.t(), integer(), integer()}
  @type lookup :: (String.t() -> {:ok, String.t()} | :error | {:error, String.t()})

  @transparent "."

  @doc "The picture `line` describes, with `lookup` giving the text behind each name it uses."
  @spec derive(String.t(), lookup()) :: {:ok, String.t()} | {:error, String.t()}
  def derive(line, lookup) do
    with {:ok, ops} <- parse(line), do: run(ops, lookup)
  end

  @doc """
  The operations in `line`, or why it could not be read.

  ## Examples

      iex> Linocut.Derive.parse("from ship; flip h; colour H #fff")
      {:ok, [{:from, "ship"}, {:flip, :h}, {:colour, "H", "#fff"}]}

  """
  @spec parse(String.t()) :: {:ok, [op()]} | {:error, String.t()}
  def parse(line) do
    words =
      line
      |> String.split(";")
      |> Enum.map(&String.split(&1, ~r/\s+/, trim: true))
      |> Enum.reject(&(&1 == []))

    with [["from", _name] | _] <- words,
         {:ok, ops} <- Enum.reduce_while(words, {:ok, []}, &collect/2) do
      {:ok, Enum.reverse(ops)}
    else
      {:error, _} = error -> error
      _other -> {:error, "a derivation starts with `from NAME`"}
    end
  end

  defp collect(words, {:ok, ops}) do
    case op(words) do
      {:ok, op} -> {:cont, {:ok, [op | ops]}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp op(["from", name]), do: {:ok, {:from, name}}
  defp op(["colour", key, spec]), do: {:ok, {:colour, key, spec}}
  defp op(["color", key, spec]), do: {:ok, {:colour, key, spec}}
  defp op(["swap", a, b]), do: {:ok, {:swap, a, b}}
  defp op(["flip", "h"]), do: {:ok, {:flip, :h}}
  defp op(["flip", "v"]), do: {:ok, {:flip, :v}}

  defp op(["turn", degrees]) when degrees in ~w(90 180 270),
    do: {:ok, {:turn, String.to_integer(degrees)}}

  defp op(["shift", dx, dy]), do: with({:ok, x, y} <- integers(dx, dy), do: {:ok, {:shift, x, y}})
  defp op(["frame", n]), do: with({:ok, index, _} <- integers(n, "0"), do: {:ok, {:frame, index}})
  defp op(["reverse"]), do: {:ok, :reverse}
  defp op(["over", name]), do: {:ok, {:over, name, 0, 0}}

  defp op(["over", name, dx, dy]),
    do: with({:ok, x, y} <- integers(dx, dy), do: {:ok, {:over, name, x, y}})

  defp op(words), do: {:error, "cannot read `#{Enum.join(words, " ")}`"}

  defp integers(a, b) do
    case {Integer.parse(a), Integer.parse(b)} do
      {{x, ""}, {y, ""}} -> {:ok, x, y}
      _other -> {:error, "`#{a} #{b}` are not whole numbers"}
    end
  end

  @doc "The picture the operations make, as text."
  @spec run([op()], lookup()) :: {:ok, String.t()} | {:error, String.t()}
  def run([{:from, name} | ops], lookup) do
    with {:ok, pic} <- fetch(name, lookup),
         {:ok, made} <- Enum.reduce_while(ops, {:ok, pic}, &step(&1, &2, lookup)) do
      {:ok, Pic.write(made)}
    end
  end

  def run(_ops, _lookup), do: {:error, "a derivation starts with `from NAME`"}

  defp step(op, {:ok, pic}, lookup) do
    case apply_op(op, pic, lookup) do
      {:ok, next} -> {:cont, {:ok, next}}
      {:error, message} -> {:halt, {:error, message}}
    end
  end

  defp fetch(name, lookup) do
    with {:ok, text} <- lookup.(name) |> named(name) do
      Pic.read(text) |> readable(name)
    end
  end

  defp named({:ok, text}, _name), do: {:ok, text}
  defp named({:error, message}, _name), do: {:error, message}
  defp named(:error, name), do: {:error, "no picture is called #{name}"}

  defp readable({:ok, pic}, _name), do: {:ok, pic}

  defp readable({:error, reason}, name),
    do: {:error, "#{name} cannot be read: #{inspect(reason)}"}

  defp apply_op({:colour, key, spec}, pic, _lookup),
    do: {:ok, %{pic | palette: List.keystore(pic.palette, key, 0, {key, spec})}}

  defp apply_op({:swap, a, b}, pic, _lookup) do
    palette =
      Enum.map(pic.palette, fn
        {^a, spec} -> {b, spec}
        {^b, spec} -> {a, spec}
        other -> other
      end)

    {:ok, %{pic | palette: palette}}
  end

  defp apply_op({:flip, :h}, pic, _lookup),
    do: {:ok, frames(pic, &Enum.map(&1, fn row -> String.reverse(row) end))}

  defp apply_op({:flip, :v}, pic, _lookup), do: {:ok, frames(pic, &Enum.reverse/1)}
  defp apply_op({:turn, 90}, pic, _lookup), do: {:ok, frames(pic, &clockwise/1)}

  defp apply_op({:turn, 180}, pic, _lookup),
    do: {:ok, frames(pic, &(&1 |> clockwise() |> clockwise()))}

  defp apply_op({:turn, 270}, pic, _lookup),
    do: {:ok, frames(pic, &(&1 |> clockwise() |> clockwise() |> clockwise()))}

  defp apply_op({:shift, dx, dy}, pic, _lookup), do: {:ok, frames(pic, &shift(&1, dx, dy))}
  defp apply_op(:reverse, pic, _lookup), do: {:ok, %{pic | frames: Enum.reverse(pic.frames)}}

  defp apply_op({:frame, n}, pic, _lookup) do
    case Enum.at(pic.frames, n - 1) do
      nil -> {:error, "there is no frame #{n}; the picture has #{length(pic.frames)}"}
      frame -> {:ok, %{pic | frames: [frame]}}
    end
  end

  defp apply_op({:over, name, dx, dy}, pic, lookup) do
    with {:ok, top} <- fetch(name, lookup),
         {:ok, palette} <- merge(pic.palette, top.palette) do
      layer = top.frames |> hd() |> shift(dx, dy)
      {:ok, %{pic | palette: palette, frames: Enum.map(pic.frames, &lay(&1, layer))}}
    end
  end

  defp frames(pic, fun), do: %{pic | frames: Enum.map(pic.frames, fun)}

  defp clockwise(rows) do
    rows
    |> Enum.map(&String.graphemes/1)
    |> Enum.reverse()
    |> Enum.zip_with(&Enum.join/1)
  end

  defp shift(rows, dx, dy) do
    width = rows |> Enum.map(&String.length/1) |> Enum.max(fn -> 0 end)
    height = length(rows)
    blank = String.duplicate(@transparent, width)

    for y <- 0..(height - 1)//1 do
      source = y - dy

      if source >= 0 and source < height,
        do: rows |> Enum.at(source) |> shift_row(dx, width),
        else: blank
    end
  end

  defp shift_row(row, dx, width) when dx >= 0,
    do: String.duplicate(@transparent, dx) <> String.slice(row, 0, max(width - dx, 0))

  defp shift_row(row, dx, width),
    do: String.slice(row, -dx, width) <> String.duplicate(@transparent, min(-dx, width))

  defp lay(rows, layer), do: Enum.zip_with(rows, layer, &lay_row/2)

  defp lay_row(under, over) do
    Enum.zip_with(String.graphemes(under), String.graphemes(over), &above/2) |> Enum.join()
  end

  defp above(below, above) when above in [@transparent, " "], do: below
  defp above(_below, above), do: above

  defp merge(palette, added) do
    Enum.reduce_while(added, {:ok, palette}, fn {key, spec}, {:ok, acc} ->
      case List.keyfind(acc, key, 0) do
        nil ->
          {:cont, {:ok, acc ++ [{key, spec}]}}

        {_key, ^spec} ->
          {:cont, {:ok, acc}}

        {_key, other} ->
          {:halt, {:error, "#{key} is #{other} in one picture and #{spec} in the other"}}
      end
    end)
  end
end
