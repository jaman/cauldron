# Prose

The book is read by someone who wants to build something. Every paragraph is measured
against that reader.

## The voice

Plain, declarative, and specific. The book explains what a thing is and what it does,
in that order. It does not sell, and it does not perform.

- **Say the thing, then stop.** One idea to a sentence, one subject to a paragraph.
- **Lead with the concrete.** "A world is a module with seven callbacks" beats "The
  concept of a world is central to the architecture."
- **Name the thing once.** After that, use the name. Do not circle it with synonyms.
- **Prefer the active voice** and a plain verb: "the session asks the drawer for pushes",
  not "pushes are obtained from the drawer by the session".
- **Second person for instructions, third for description.** "Give the scene a `:gpu`
  function." "The drawer turns a scene into pushes."
- **Cut the scaffolding.** No "in this chapter we will", "as we saw", "it is worth
  noting", "let us", "simply", "just", "basically", "of course".

## Words to leave out

`powerful`, `seamless`, `robust`, `elegant`, `effortless`, `blazing`, `amazing`,
`simply`, `just`, `very`, `really`, `easily`, `obviously`, `clearly`, `somewhat`,
`quite`, `a bit`. Also `utilise` (use), `leverage` (use), `facilitate` (let),
`in order to` (to), `prior to` (before), `whilst` (while).

## Sentences

- Under about 30 words. Split rather than stack clauses.
- One em-dash pair to a paragraph at most.
- No rhetorical questions.
- No exclamation marks.
- A colon introduces a list or an explanation, not a drum roll.

## Paragraphs

Four sentences is a long paragraph. A paragraph that restates the one before it is
deleted. A paragraph that begins "Note that" is rewritten to say the thing noted.

## Structure

- **Headings in sentence case**, except proper names: "How a frame is made".
- **Tables for things that differ by row**: options, callbacks, costs. Prose for
  things that differ by argument.
- **Lists only when the items are parallel.** Three sentences in a row with "also" are
  a paragraph, not a list.
- **A figure earns a sentence in the text.** The text says what to look at.

## Code

- A snippet is the shortest thing that runs, or the smallest thing that shows the shape.
- Name real functions and arities; a made-up function is a lie with a syntax highlight.
- Prose before the snippet says what it does; after it, only what the snippet cannot say.
- Comments in a snippet are for the reader of the book, not decoration.

## Facts

- The book does not narrate its own history and does not record how the code came to be.
- No release numbers in prose, no "previously", no "this changed in".
- No claim a reader cannot check against the source.
