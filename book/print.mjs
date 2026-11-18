// Prints a print-ready HTML document to PDF with the machine's Chrome.
//
//     node book/print.mjs book/build/cauldron.html book/build/cauldron.pdf
//
// No package is needed: the browser is driven over the DevTools protocol
// with the WebSocket client built into Node. The page does its own
// pagination through CSS (see the book's print stylesheet); this script
// prints it and puts the page number in the footer.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [htmlPath, pdfPath] = process.argv.slice(2);

if (!htmlPath || !pdfPath) {
  console.error("usage: node book/print.mjs <input.html> <output.pdf>");
  process.exit(2);
}

const chrome =
  process.env.CHROME_PATH ||
  [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
  ].find((candidate) => existsSync(candidate));

if (!chrome) {
  console.error("No Chrome, Chromium, Edge or Brave found. Set CHROME_PATH.");
  process.exit(2);
}

// Node's WebSocket does not keep the event loop alive by itself; this
// interval does, so the awaits below can wait for the browser's answers.
const keepalive = setInterval(() => {}, 1000);
const profile = await mkdtemp(join(tmpdir(), "cauldron-book-"));

const browser = spawn(
  chrome,
  [
    "--headless=new",
    "--disable-gpu",
    "--no-sandbox",
    "--disable-dev-shm-usage",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-extensions",
    `--user-data-dir=${profile}`,
    "--remote-debugging-port=0",
    "about:blank",
  ],
  { stdio: "ignore" },
);

let socket;

try {
  const { port, path } = await waitForPort(join(profile, "DevToolsActivePort"));
  socket = new WebSocket(`ws://127.0.0.1:${port}${path}`);
  await once(socket, "open");

  const call = cdp(socket);
  const { targetInfos } = await call("Target.getTargets");
  const page = targetInfos.find((target) => target.type === "page");
  if (!page) throw new Error("Chrome opened no page to print.");

  const { sessionId } = await call("Target.attachToTarget", {
    targetId: page.targetId,
    flatten: true,
  });

  await call("Page.enable", {}, sessionId);

  const loaded = event(socket, "Page.loadEventFired", sessionId);
  await call("Page.navigate", { url: pathToFileURL(resolve(htmlPath)).href }, sessionId);
  await loaded;

  await call(
    "Runtime.evaluate",
    {
      awaitPromise: true,
      expression: `(async () => {
        await document.fonts.ready;
        await Promise.all([...document.images].map((image) =>
          image.complete ? null : new Promise((done) => { image.onload = done; image.onerror = done; })
        ));
      })()`,
    },
    sessionId,
  );

  const { data } = await call(
    "Page.printToPDF",
    {
      printBackground: true,
      preferCSSPageSize: true,
      ...(process.env.PAGE_RANGES ? { pageRanges: process.env.PAGE_RANGES } : {}),
      displayHeaderFooter: true,
      generateDocumentOutline: process.env.OUTLINE !== "false",
      headerTemplate: "<span></span>",
      footerTemplate: `<div style="width:100%;font-family:Georgia,serif;font-size:9px;color:#6b6459;text-align:center;">
        <span class="pageNumber"></span>
      </div>`,
    },
    sessionId,
  );

  await writeFile(resolve(pdfPath), Buffer.from(data, "base64"));
  console.log(`Wrote ${resolve(pdfPath)}`);
} finally {
  if (socket && socket.readyState === WebSocket.OPEN) socket.close();
  browser.kill("SIGTERM");
  clearInterval(keepalive);
  await rm(profile, { recursive: true, force: true }).catch(() => {});
}

async function waitForPort(file) {
  for (let attempt = 0; attempt < 150; attempt += 1) {
    try {
      const text = await readFile(file, "utf8");
      const [port, path] = text.split("\n");
      if (port && path) return { port: port.trim(), path: path.trim() };
    } catch {
      // not written yet
    }
    await new Promise((done) => setTimeout(done, 100));
  }
  throw new Error("Chrome did not open its debugging port.");
}

function once(target, name) {
  return new Promise((done, fail) => {
    target.addEventListener(name, () => done(), { once: true });
    target.addEventListener("error", (error) => fail(error), { once: true });
  });
}

function event(target, method, sessionId) {
  return new Promise((done) => {
    const listener = (message) => {
      const decoded = JSON.parse(message.data);
      if (decoded.method === method && (decoded.sessionId || null) === (sessionId || null)) {
        target.removeEventListener("message", listener);
        done(decoded.params);
      }
    };
    target.addEventListener("message", listener);
  });
}

function cdp(target) {
  let next = 0;
  const pending = new Map();

  target.addEventListener("message", (message) => {
    const decoded = JSON.parse(message.data);
    if (!decoded.id || !pending.has(decoded.id)) return;

    const { done, fail } = pending.get(decoded.id);
    pending.delete(decoded.id);
    if (decoded.error) fail(new Error(decoded.error.message));
    else done(decoded.result);
  });

  return (method, params = {}, sessionId = null) =>
    new Promise((done, fail) => {
      const id = (next += 1);
      pending.set(id, { done, fail });
      target.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    });
}
