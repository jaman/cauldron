// Joins the PDFs a book is printed in into one, page for page.
//
//     osascript -l JavaScript book/merge.js out.pdf part-1.pdf part-2.pdf ...
//
// The book is printed in parts because one print job of more than about sixty pages of
// it stalls the browser's printer; each part carries the page numbers of the whole, so
// the join needs no renumbering. macOS's PDFKit does the joining.

function run(argv) {
  const out = argv[0];
  const inputs = argv.slice(1);

  ObjC.import("PDFKit");

  const merged = $.PDFDocument.alloc.init;

  for (const path of inputs) {
    const document = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath(path));

    if (!document) {
      throw new Error("could not read " + path);
    }

    for (let page = 0; page < document.pageCount; page++) {
      merged.insertPageAtIndex(document.pageAtIndex(page), merged.pageCount);
    }
  }

  if (!merged.writeToFile(out)) {
    throw new Error("could not write " + out);
  }
}
