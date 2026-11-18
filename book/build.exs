# Builds the book: one HTML document with a cover, a colophon, contents and the
# chapters, then a PDF printed from it.
#
#     elixir book/build.exs
#
# Writes book/build/cauldron.html and book/build/cauldron.pdf. The PDF's contents carry
# the page each chapter starts on: the book is printed once, the outline the browser
# writes is read for the page numbers, and the contents are built again and reprinted.
#
# Nothing here runs at application time: the book is documentation, built by hand.

root = Path.expand("..", __DIR__)
out = Path.join(__DIR__, "build")

[preface: preface, parts: parts] =
  Path.join(__DIR__, "contents.exs") |> Code.eval_file() |> elem(0)

pandoc =
  System.find_executable("pandoc") ||
    raise "Pandoc is needed to build the book: https://pandoc.org"

slug = fn path -> Path.basename(path, ".md") end

# A chapter's figures live beside the guide that uses them: `pkg/guides/assets`, or
# `book/assets` for the chapters written here. They are copied under the chapter's own
# name so two packages may use the same file name.
package_of = fn path ->
  case Path.split(path) do
    ["book" | _rest] -> "book"
    [pkg | _rest] -> pkg
  end
end

figure_dir = fn pkg ->
  if pkg == "book",
    do: Path.join(__DIR__, "assets"),
    else: Path.join([root, pkg, "guides", "assets"])
end

copy_figures = fn pkg ->
  source = figure_dir.(pkg)
  target = Path.join([out, "assets", pkg])

  if File.dir?(source) do
    File.mkdir_p!(Path.dirname(target))
    File.cp_r!(source, target)
  end
end

# Figures are written `assets/name` in a guide; in the book they live under the chapter's
# own directory.
rewrite_figures = fn text, pkg ->
  text
  |> then(fn text ->
    Regex.replace(~r/\]\(assets\/([^)]+)\)/, text, fn _whole, file ->
      "](assets/#{pkg}/#{file})"
    end)
  end)
  |> then(fn text ->
    Regex.replace(~r/src="assets\/([^"]+)"/, text, fn _whole, file ->
      ~s(src="assets/#{pkg}/#{file}")
    end)
  end)
end

# --- the chapters, in order -----------------------------------------------------

chapters =
  [%{path: elem(hd(preface), 1), number: nil, part: nil}] ++
    (parts
     |> Enum.with_index(1)
     |> Enum.flat_map(fn {{_part, entries}, part_number} ->
       Enum.map(entries, fn {_title, path} -> %{path: path, part: part_number} end)
     end)
     |> Enum.with_index(1)
     |> Enum.map(fn {chapter, number} -> Map.put(chapter, :number, number) end))

chapter_slugs = MapSet.new(chapters, &slug.(&1.path))

# A link to another chapter of this book becomes a link inside the book, whether the
# guide writes it as `chapter.html` or as its HexDocs address.
rewrite_links = fn text ->
  Regex.replace(
    ~r/\]\((?:https:\/\/hexdocs\.pm\/[a-z0-9_]+\/)?([a-z0-9-]+)\.html(?:#[^)]*)?\)/,
    text,
    fn whole, page ->
      if MapSet.member?(chapter_slugs, page), do: "](##{page})", else: whole
    end
  )
end

markdown_to_html = fn markdown ->
  file = Path.join(System.tmp_dir!(), "cauldron-book-#{System.unique_integer([:positive])}.md")
  File.write!(file, markdown)

  try do
    {html, status} =
      System.cmd(
        pandoc,
        ["--from=gfm", "--to=html5", "--syntax-highlighting=none", "--wrap=none", file],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("Pandoc could not read a chapter:\n\n#{html}")
    html
  after
    File.rm(file)
  end
end

# --- heading anchors and the sections they name ----------------------------------

strip_ids = fn html -> Regex.replace(~r/<h([1-6])\s+id="[^"]*">/, html, "<h\\1>") end

text_of = fn html ->
  html
  |> String.replace(~r/<[^>]*>/, "")
  |> String.replace("&amp;", "&")
  |> String.replace("&quot;", "\"")
  |> String.replace("&#39;", "'")
  |> String.replace("&lt;", "<")
  |> String.replace("&gt;", ">")
  |> String.trim()
end

anchor_of = fn html ->
  html
  |> text_of.()
  |> String.downcase()
  |> String.replace("&", " and ")
  |> String.replace(~r/[^a-z0-9]+/, "-")
  |> String.trim("-")
end

# Each heading is given the chapter's name in front of its own, so two chapters may carry
# a heading with the same words. The second-level ones are collected for the contents.
headings = fn html, chapter ->
  matches = Regex.scan(~r/<h([23])>(.*?)<\/h\1>/s, html)

  {html, sections, _used} =
    Enum.reduce(matches, {html, [], %{}}, fn [whole, level, inner], {html, sections, used} ->
      base = anchor_of.(inner)
      count = Map.get(used, base, 0)
      anchor = if count == 0, do: base, else: "#{base}-#{count + 1}"
      id = "#{chapter}--#{anchor}"

      html =
        String.replace(
          html,
          whole,
          ~s(<h#{level} id="#{id}">#{inner}</h#{level}>),
          global: false
        )

      sections =
        if level == "2", do: sections ++ [%{id: id, title: text_of.(inner)}], else: sections

      {html, sections, Map.put(used, base, count + 1)}
    end)

  {html, sections}
end

# A picture on its own line becomes a figure with a visible caption, from its alt text.
figures = fn html ->
  Regex.replace(
    ~r/<p>\s*<img([^>]*?)alt="([^"]*)"([^>]*?)\/?>\s*<\/p>/s,
    html,
    fn _whole, before, alt, rest ->
      ~s(<figure><img#{before}alt="#{alt}"#{rest}/><figcaption>#{alt}</figcaption></figure>)
    end
  )
end

split_title = fn markdown, path ->
  case String.split(markdown, ~r/^# /, parts: 2) do
    [_, rest] ->
      [first | body] = String.split(rest, "\n", parts: 2)
      {String.trim(first), Enum.join(body, "\n")}

    _none ->
      raise "#{path} has no title (a line starting with `# `)."
  end
end

built =
  Enum.map(chapters, fn chapter ->
    pkg = package_of.(chapter.path)
    copy_figures.(pkg)

    markdown =
      File.read!(Path.join(root, chapter.path))
      |> rewrite_figures.(pkg)
      |> rewrite_links.()

    {title, body} = split_title.(markdown, chapter.path)
    chapter_slug = slug.(chapter.path)

    {html, sections} =
      body
      |> markdown_to_html.()
      |> strip_ids.()
      |> headings.(chapter_slug)

    Map.merge(chapter, %{
      title: title,
      slug: chapter_slug,
      html: figures.(html),
      sections: sections
    })
  end)

# --- front matter ----------------------------------------------------------------

cover = Path.join(__DIR__, "cover.md") |> File.read!() |> rewrite_figures.("book")
colophon = Path.join(__DIR__, "colophon.md") |> File.read!() |> rewrite_figures.("book")

# --- contents --------------------------------------------------------------------

escape = fn text ->
  text
  |> String.replace("&", "&amp;")
  |> String.replace("<", "&lt;")
  |> String.replace(">", "&gt;")
end

# The browser's outline names a chapter with its number and often repeats its words
# ("11IntroductionIntroduction"), and a section of another chapter may carry the same
# words. Chapters run in book order, so each one starts at or after the one before it;
# the first page that names it and does not precede its predecessor is where it starts.
chapter_pages = fn pages ->
  built
  |> Enum.reduce({%{}, 0}, fn chapter, {found, previous} ->
    case pages
         |> Enum.filter(fn {entry, _page} -> String.contains?(entry, chapter.title) end)
         |> Enum.map(fn {_entry, page} -> page end)
         |> Enum.filter(&(&1 >= previous))
         |> Enum.min(fn -> nil end) do
      nil -> {found, previous}
      page -> {Map.put(found, chapter.slug, page), page}
    end
  end)
  |> elem(0)
end

toc_chapter = fn chapter, pages ->
  page =
    case Map.get(pages, chapter.slug) do
      nil -> ""
      number -> ~s(<span class="toc-page">#{number}</span>)
    end

  number =
    case chapter.number do
      nil -> ""
      n -> ~s(<span class="toc-number">#{n}</span>)
    end

  """
  <li class="toc-chapter">
    <a href="##{chapter.slug}">#{number}<span class="toc-title">#{escape.(chapter.title)}</span><span class="toc-fill"></span>#{page}</a>
  </li>
  """
end

toc = fn pages ->
  pages = chapter_pages.(pages)

  preface_entry =
    built
    |> Enum.find(&is_nil(&1.number))
    |> then(&toc_chapter.(&1, pages))

  parts_html =
    parts
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{part, _entries}, part_number} ->
      entries =
        built
        |> Enum.filter(&(&1.part == part_number))
        |> Enum.map_join("\n", &toc_chapter.(&1, pages))

      """
      <li class="toc-part"><span>#{escape.(part)}</span></li>
      #{entries}
      """
    end)

  """
  <nav class="contents" id="contents">
  <h1>Contents</h1>
  <ol class="toc-chapters">
  #{preface_entry}
  #{parts_html}
  </ol>
  </nav>
  """
end

# --- the document ----------------------------------------------------------------

chapter_html = fn chapter ->
  number =
    case chapter.number do
      nil -> ""
      n -> ~s(<span class="chapter-number">#{n}</span>)
    end

  """
  <section class="chapter" id="#{chapter.slug}">
  <h1 class="chapter-title">#{number}#{escape.(chapter.title)}</h1>
  #{chapter.html}
  </section>
  """
end

part_html = fn title -> ~s(<section class="part"><h1>#{escape.(title)}</h1></section>) end

document = fn pages ->
  body =
    [
      cover,
      colophon,
      toc.(pages),
      chapter_html.(Enum.find(built, &is_nil(&1.number))),
      parts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {{part, _entries}, part_number} ->
        part_html.(part) <>
          (built
           |> Enum.filter(&(&1.part == part_number))
           |> Enum.map_join("\n", &chapter_html.(&1)))
      end)
    ]
    |> Enum.join("\n")

  """
  <!DOCTYPE html>
  <html lang="en">
  <head>
  <meta charset="utf-8"/>
  <title>Cauldron</title>
  <style>
  #{File.read!(Path.join(__DIR__, "book.css"))}
  </style>
  </head>
  <body>
  #{body}
  </body>
  </html>
  """
end

# --- printing --------------------------------------------------------------------

File.mkdir_p!(out)
html_path = Path.join(out, "cauldron.html")
pdf_path = Path.join(out, "cauldron.pdf")

# The browser's outline names each heading and the page it is on; the page tree says
# which page a destination points at. Read back, the outline gives the contents numbers
# that match the printed pages.
pages_of = fn pdf ->
  binary = File.read!(pdf)

  objects =
    ~r{(\d+) 0 obj\n(.*?)\nendobj}s
    |> Regex.scan(binary)
    |> Map.new(fn [_, id, body] -> {String.to_integer(id), body} end)

  kids = fn id ->
    case Regex.run(~r{/Kids \[([^\]]*)\]}, Map.get(objects, id, "")) do
      [_, list] ->
        Regex.scan(~r{(\d+) 0 R}, list) |> Enum.map(fn [_, n] -> String.to_integer(n) end)

      _none ->
        []
    end
  end

  root =
    Enum.find_value(objects, fn {id, body} ->
      if String.contains?(body, "/Type /Pages") and not String.contains?(body, "/Parent"),
        do: id
    end)

  walk = fn walk, id, pages ->
    body = Map.get(objects, id, "")

    cond do
      Regex.match?(~r{/Type /Page[^s]}, body) ->
        pages ++ [id]

      String.contains?(body, "/Type /Pages") ->
        Enum.reduce(kids.(id), pages, fn kid, acc -> walk.(walk, kid, acc) end)

      true ->
        pages
    end
  end

  order =
    (if root, do: walk.(walk, root, []), else: [])
    |> Enum.with_index(1)
    |> Map.new(fn {object, page} -> {object, page} end)

  ~r{<</Title \((.*?)\)\s*/Dest \[(\d+) 0 R}
  |> Regex.scan(binary)
  |> Enum.flat_map(fn [_, title, object] ->
    case Map.fetch(order, String.to_integer(object)) do
      {:ok, page} -> [{title, page}]
      :error -> []
    end
  end)
end

print = fn pages ->
  File.write!(html_path, document.(pages))

  case System.find_executable("node") do
    nil ->
      IO.puts("Node.js is not on PATH: wrote the HTML only")
      {:no_pdf, []}

    node ->
      {output, status} =
        System.cmd(node, [Path.join(__DIR__, "print.mjs"), html_path, pdf_path],
          stderr_to_stdout: true
        )

      if status == 0 do
        {:ok, pages_of.(pdf_path)}
      else
        IO.puts("the PDF was not written:\n#{output}")
        {:failed, []}
      end
  end
end

case print.([]) do
  {:ok, pages} when pages != [] -> print.(pages)
  _other -> :ok
end

IO.puts("wrote #{html_path}")
IO.puts("wrote #{pdf_path}")
