# Assembles the book from the chapters listed in book/contents.exs.
#
#     elixir book/build.exs
#
# Writes book/build/cauldron.md, and book/build/cauldron.html when Pandoc is on PATH.
# Nothing here is used at run time: the book is documentation, built by hand.

root = Path.expand("..", __DIR__)
parts = Code.eval_file(Path.join(__DIR__, "contents.exs")) |> elem(0)

slug = fn path -> Path.basename(path, ".md") end

# A link to another chapter of this book becomes a link to that chapter in the assembled
# file. A link anywhere else is left alone.
chapter_slugs =
  for {_part, chapters} <- parts, {_title, path} <- chapters, into: MapSet.new(), do: slug.(path)

rewrite_links = fn text ->
  Regex.replace(~r/\]\(([a-z0-9-]+)\.html(?:#[^)]*)?\)/, text, fn whole, page ->
    if MapSet.member?(chapter_slugs, page), do: "](##{page})", else: whole
  end)
end

# Chapter headings sit one level below their part heading. Lines inside a fenced code
# block are left alone, since a `#` there is a comment, not a heading.
demote = fn text ->
  {lines, _in_code} =
    text
    |> String.split("\n")
    |> Enum.map_reduce(false, fn line, in_code ->
      cond do
        String.starts_with?(line, "```") -> {line, not in_code}
        in_code -> {line, in_code}
        String.starts_with?(line, "#") -> {"#" <> line, in_code}
        true -> {line, in_code}
      end
    end)

  Enum.join(lines, "\n")
end

front = File.read!(Path.join(__DIR__, "index.md")) |> rewrite_links.()

toc =
  parts
  |> Enum.map(fn {part, chapters} ->
    entries =
      chapters
      |> Enum.map(fn {title, path} -> "  - [#{title}](##{slug.(path)})" end)
      |> Enum.join("\n")

    "- **#{part}**\n#{entries}"
  end)
  |> Enum.join("\n")

chapters =
  parts
  |> Enum.map(fn {part, chapters} ->
    body =
      chapters
      |> Enum.map(fn {_title, path} ->
        text = File.read!(Path.join(root, path)) |> rewrite_links.() |> demote.()
        "<a id=\"#{slug.(path)}\"></a>\n\n" <> text
      end)
      |> Enum.join("\n\n---\n\n")

    "# #{part}\n\n#{body}"
  end)
  |> Enum.join("\n\n")

book = """
#{front}

## Contents

#{toc}

#{chapters}
"""

out = Path.join([__DIR__, "build"])
File.mkdir_p!(out)
File.write!(Path.join(out, "cauldron.md"), book)
IO.puts("wrote book/build/cauldron.md (#{length(String.split(book, "\n"))} lines)")

case System.find_executable("pandoc") do
  nil ->
    IO.puts("pandoc is not on PATH; only the markdown was written")

  pandoc ->
    css = Path.join(__DIR__, "book.css")

    {output, status} =
      System.cmd(
        pandoc,
        [
          Path.join(out, "cauldron.md"),
          "--standalone",
          "--toc",
          "--toc-depth=2",
          "--metadata",
          "title=Cauldron",
          "--metadata",
          "lang=en",
          "--css",
          css,
          "-o",
          Path.join(out, "cauldron.html")
        ],
        stderr_to_stdout: true
      )

    if status == 0 do
      IO.puts("wrote book/build/cauldron.html")
    else
      IO.puts("pandoc failed:\n#{output}")
      System.halt(1)
    end
end
