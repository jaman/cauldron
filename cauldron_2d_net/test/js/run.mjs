import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const drawDir = path.join(here, "../../priv/static/draw");
const fixtures = path.join(here, "fixtures");
const only = process.argv[2] || "";

const order = ["core.js", "volume.js", "surface.js", "parallax.js", "screen.js", "iso.js", "oblique.js", "mode7.js", "first_person.js", "draw.js"];
const context = vm.createContext({ console, Math, Uint8ClampedArray, Uint8Array, Float64Array, Int32Array, Array, Object, JSON, Error, Infinity, NaN, parseInt, parseFloat, isFinite });
context.globalThis = context;
for (const file of order) {
  const full = path.join(drawDir, file);
  if (fs.existsSync(full)) vm.runInContext(fs.readFileSync(full, "utf8"), context, { filename: full });
}
const D = context.CauldronDraw;

function png(width, height, rgba) {
  const raw = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (width * 4 + 1)] = 0;
    Buffer.from(rgba.buffer, rgba.byteOffset + y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1);
  }
  const chunk = (type, data) => {
    const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32(body) >>> 0);
    return Buffer.concat([length, body, crc]);
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

let failures = 0, total = 0;
for (const game of fs.readdirSync(fixtures).sort()) {
  const gameDir = path.join(fixtures, game);
  if (!fs.statSync(gameDir).isDirectory()) continue;
  const index = JSON.parse(fs.readFileSync(path.join(gameDir, "atlas.json"), "utf8"));
  const sheet = new Uint8ClampedArray(fs.readFileSync(path.join(gameDir, "atlas.rgba")));
  for (const scene of fs.readdirSync(gameDir).sort()) {
    const sceneDir = path.join(gameDir, scene);
    if (!fs.statSync(sceneDir).isDirectory()) continue;
    const label = `${game}/${scene}`;
    if (only && !label.includes(only)) continue;
    total++;
    const atlas = D.atlas(index, sheet, index.width, index.height);
    for (const file of fs.readdirSync(sceneDir).filter((f) => f.startsWith("tinted-") && f.endsWith(".json"))) {
      const tinted = JSON.parse(fs.readFileSync(path.join(sceneDir, file), "utf8"));
      const data = new Uint8ClampedArray(fs.readFileSync(path.join(sceneDir, file.replace(/\.json$/, ".rgba"))));
      atlas.addTinted(tinted.art, tinted.tint, tinted.index, data, tinted.width, tinted.height);
    }
    for (const file of fs.readdirSync(sceneDir).filter((f) => f.startsWith("tintedcell-") && f.endsWith(".json"))) {
      const cell = JSON.parse(fs.readFileSync(path.join(sceneDir, file), "utf8"));
      const data = new Uint8ClampedArray(fs.readFileSync(path.join(sceneDir, file.replace(/\.json$/, ".rgba"))));
      atlas.addTintedCell(cell.base, cell.overlays, cell.tint, cell.index, data, cell.width, cell.height);
    }
    const fixture = JSON.parse(fs.readFileSync(path.join(sceneDir, "scene.json"), "utf8"));
    const expected = new Uint8ClampedArray(fs.readFileSync(path.join(sceneDir, "expected.rgba")));
    let picture;
    try {
      const view = D.reader(atlas).read(fixture.payload);
      picture = D.picturePane(view, fixture.pane, fixture.at);
    } catch (error) {
      failures++;
      console.log(`FAIL ${label}: ${error.stack.split("\n").slice(0, 4).join(" | ")}`);
      continue;
    }
    if (picture.width !== fixture.width || picture.height !== fixture.height) {
      failures++;
      console.log(`FAIL ${label}: size ${picture.width}x${picture.height}, expected ${fixture.width}x${fixture.height}`);
      continue;
    }
    let differing = 0, worst = 0, first = null;
    const diff = new Uint8ClampedArray(expected.length);
    for (let i = 0; i < expected.length; i += 4) {
      let d = 0;
      for (let k = 0; k < 4; k++) d = Math.max(d, Math.abs(expected[i + k] - picture.data[i + k]));
      if (d > 0) {
        differing++;
        worst = Math.max(worst, d);
        if (!first) first = `(${(i / 4) % fixture.width}, ${Math.floor(i / 4 / fixture.width)}) got ${Array.from(picture.data.slice(i, i + 4))} want ${Array.from(expected.slice(i, i + 4))}`;
        diff[i] = 255; diff[i + 3] = 255;
      } else {
        diff[i] = expected[i] >> 2; diff[i + 1] = expected[i + 1] >> 2; diff[i + 2] = expected[i + 2] >> 2; diff[i + 3] = 255;
      }
    }
    const out = path.join(sceneDir, "out");
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, "actual.png"), png(fixture.width, fixture.height, picture.data));
    fs.writeFileSync(path.join(out, "expected.png"), png(fixture.width, fixture.height, expected));
    fs.writeFileSync(path.join(out, "diff.png"), png(fixture.width, fixture.height, diff));
    if (differing === 0) console.log(`ok   ${label}`);
    else {
      failures++;
      console.log(`FAIL ${label}: ${differing} of ${expected.length / 4} pixels differ, worst by ${worst}; first ${first}`);
    }
  }
}
console.log(`${total - failures} of ${total} scenes match`);
process.exit(failures ? 1 : 0);
