# Assembles the book from the chapters listed in book/contents.exs.
#
#     elixir book/build.exs
#
# Writes book/build/cauldron.md, and book/build/cauldron.html when Pandoc is on PATH.
# Nothing here is used at run time: the book is documentation, built by hand.

root = Path.expand("..", __DIR__)
parts = Code.eval_file(Path.join(__DIR__, "contents.exs")) |> elem(0)
out = Path.join(__DIR__, "build")

slug = fn path -> Path.basename(path, ".md") end

# A chapter's figures live beside the guide that uses them: `pkg/guides/assets`, or
# `book/assets` for the chapters written here. They are copied under the chapter's own
# name so two packages may use the same file name.
chapter_package = fn path ->
  case Path.split(path) do
    ["book" | _rest] -> "book"
    [pkg | _rest] -> pkg
  end
end

figure_dir = fn pkg ->
  if pkg == "book", do: Path.join(__DIR__, "assets"), else: Path.join([root, pkg, "guides", "assets"])
end

copy_figures = fn pkg ->
  source = figure_dir.(pkg)
  target = Path.join([out, "assets", pkg])
  if File.dir?(source) do
    File.mkdir_p!(Path.dirname(target))
    File.cp_r!(source, target)
  end
end

rewrite_figures = fn text, pkg ->
  Regex.replace(~r/\]\(assets\/([^)]+)\)/, text, fn _whole, file ->
    "](assets/#{pkg}/#{file})"
  end)
end

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

front = File.read!(Path.join(__DIR__, "index.md")) |> rewrite_links.() |> rewrite_figures.("book")

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
        pkg = chapter_package.(path)
        copy_figures.(pkg)

        text =
          File.read!(Path.join(root, path))
          |> rewrite_links.()
          |> rewrite_figures.(pkg)
          |> demote.()

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
          "cauldron.md",
          "--standalone",
          "--embed-resources",
          "--toc",
          "--toc-depth=2",
          "--metadata",
          "title=Cauldron",
          "--metadata",
          "lang=en",
          "--css",
          css,
          "-o",
          "cauldron.html"
        ],
        cd: out,
        stderr_to_stdout: true
      )

    if status == 0 do
      IO.puts("wrote book/build/cauldron.html")
    else
      IO.puts("pandoc failed:\n#{output}")
      System.halt(1)
    end
end

# A PDF needs a browser to print the HTML: Chrome, Chromium or Edge. `CHROME` names one
# that is somewhere else.
chrome =
  System.get_env("CHROME") ||
    Enum.find(
      [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser",
        "/usr/bin/microsoft-edge"
      ],
      &File.exists?/1
    )

if File.exists?(Path.join(out, "cauldron.html")) and chrome do
  profile = Path.join(System.tmp_dir!(), "cauldron-book-#{System.unique_integer([:positive])}")
  pdf = Path.join(out, "cauldron.pdf")

  {output, status} =
    System.cmd(
      chrome,
      [
        "--headless=new",
        "--no-sandbox",
        "--disable-gpu",
        "--user-data-dir=#{profile}",
        "--no-pdf-header-footer",
        "--virtual-time-budget=30000",
        "--print-to-pdf=#{pdf}",
        "file://#{Path.join(out, "cauldron.html")}"
      ],
      stderr_to_stdout: true
    )

  File.rm_rf(profile)

  if status == 0 and File.exists?(pdf) do
    IO.puts("wrote book/build/cauldron.pdf (#{div(File.stat!(pdf).size, 1024)} KB)")
  else
    IO.puts("the PDF was not written:\n#{output}")
  end
end
