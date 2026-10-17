import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";

const VERTEX_FLOATS = 12;
const SNAP = 4;
const MATERIAL_SKY = 8;
const MATERIAL_WARP = 16;
const IN_FRONT = 8;
const STANDING = 32;
const DYNAMIC_GLSL = `
vec3 cauldronDynamic(vec3 position, vec3 n) {
  vec3 sum = vec3(0.0);
  #if NUM_POINT_LIGHTS > 0
  for (int i = 0; i < NUM_POINT_LIGHTS; i++) {
    vec3 to = pointLights[i].position - position;
    float range = pointLights[i].distance;
    float fall = range > 0.0 ? max(1.0 - dot(to, to) / (range * range), 0.0) : 1.0;
    sum += pointLights[i].color * max(dot(n, normalize(to)), 0.0) * fall;
  }
  #endif
  #if NUM_SPOT_LIGHTS > 0
  for (int i = 0; i < NUM_SPOT_LIGHTS; i++) {
    vec3 to = spotLights[i].position - position;
    float range = spotLights[i].distance;
    float fall = range > 0.0 ? max(1.0 - dot(to, to) / (range * range), 0.0) : 1.0;
    vec3 axis = -spotLights[i].direction;
    float along = dot(-to, axis);
    float cosine = spotLights[i].coneCos;
    float across = length(-to - axis * along) / max(along * sqrt(max(1.0 - cosine * cosine, 0.0)) / max(cosine, 1e-6), 1e-6);
    float cone = along > 0.0 ? max(1.0 - across * across, 0.0) : 0.0;
    sum += spotLights[i].color * max(dot(n, normalize(to)), 0.0) * fall * cone;
  }
  #endif
  #if NUM_DIR_LIGHTS > 0
  for (int i = 0; i < NUM_DIR_LIGHTS; i++) sum += directionalLights[i].color * max(dot(n, directionalLights[i].direction), 0.0);
  #endif
  return sum;
}
`;

const MATERIAL_ADD = 64;
const MATERIAL_MULTIPLY = 128;
const MATERIAL_REFLECTION = 65536;
const NO_DEPTH_TEST = 16;
const LAYER_SMEAR = 1;
const LAYER_STANDING = 2;
const LAYER_FRONT = 3;
const LAYER_DOME = 4;

const LIGHT_GLSL = `
uniform float cauldronDisplay;
uniform float cauldronHasTable;
uniform float cauldronReach;
uniform sampler2D cauldronTable;
vec3 cauldronEncode(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
vec3 cauldronDecode(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 cauldronTabled(vec3 light, float distance) {
  if (cauldronHasTable < 0.5) return light;
  float row = clamp(distance / cauldronReach, 0.0, 1.0);
  return vec3(texture2D(cauldronTable, vec2(clamp(light.r, 0.0, 1.0), row)).r,
              texture2D(cauldronTable, vec2(clamp(light.g, 0.0, 1.0), row)).g,
              texture2D(cauldronTable, vec2(clamp(light.b, 0.0, 1.0), row)).b);
}
vec3 cauldronDisplayLit(vec3 albedo, vec3 light, vec3 emissive) {
  return any(greaterThan(emissive, vec3(0.0))) ? emissive : cauldronDecode(cauldronEncode(albedo) * light);
}
`;

const SMEAR_FRAGMENT = `
uniform sampler2D behind;
uniform vec2 resolution;
uniform float frameIndex;
uniform float smear;
uniform vec3 tint;
uniform sampler2D map;
uniform float hasMap;
uniform float cutoff;
varying vec2 vUv;
void main() {
  float alpha = hasMap > 0.5 ? texture2D(map, vUv).a : 1.0;
  if (alpha < cutoff) discard;
  vec2 screen = gl_FragCoord.xy / resolution;
  vec2 block = floor(vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y) / (smear * resolution.y));
  float choice = fract(sin(dot(block, vec2(12.9898, 4.1414)) + frameIndex * 78.233) * 43758.5453);
  gl_FragColor = vec4(texture2D(behind, screen + vec2(0.0, choice < 0.5 ? smear : -smear)).rgb * tint, 1.0);
}
`;

const FINISH_SHADER = {
  uniforms: {
    tDiffuse: { value: null },
    viewport: { value: new THREE.Vector4(0, 0, 1, 1) },
    gamma: { value: 1 },
    contrast: { value: 1 },
    brightness: { value: 0 },
    blocks: { value: new THREE.Vector2(0, 0) }
  },
  vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
  fragmentShader: `uniform sampler2D tDiffuse; uniform vec4 viewport; uniform float gamma; uniform float contrast; uniform float brightness; uniform vec2 blocks; varying vec2 vUv;
    void main() {
      vec2 top = vec2(vUv.x, 1.0 - vUv.y);
      bool outside = any(lessThan(top, viewport.xy)) || any(greaterThan(top, viewport.xy + viewport.zw));
      if (blocks.x > 0.0 && blocks.y > 0.0) {
        vec2 local = (floor((top - viewport.xy) / viewport.zw * blocks) + 0.5) / blocks;
        top = viewport.xy + local * viewport.zw;
      }
      vec4 color = texture2D(tDiffuse, vec2(top.x, 1.0 - top.y));
      gl_FragColor = outside ? vec4(0.0, 0.0, 0.0, 1.0) : vec4(clamp(pow(color.rgb, vec3(gamma)) * contrast + brightness, 0.0, 1.0), color.a);
    }`
};

const SKY_GLSL = `
uniform int skyKind;
uniform sampler2D skyFaces[6];
uniform vec2 skyScroll;
uniform float skyTime;
uniform vec3 skyTop;
uniform vec3 skyHorizon;
uniform vec3 skyGround;
vec3 skyLayers(vec3 d) {
  float reach = max(length(vec3(d.x, d.z, 3.0 * d.y)), 1e-6);
  vec2 point = vec2(d.x, -d.z) * (378.0 / 128.0) / reach;
  vec3 back = texture2D(skyFaces[0], point + skyTime * skyScroll.x).rgb;
  vec4 front = texture2D(skyFaces[1], point + skyTime * skyScroll.y);
  return mix(back, front.rgb, front.a);
}
vec3 skyBox(vec3 d) {
  vec3 size = abs(d);
  if (size.x >= size.y && size.x >= size.z) {
    vec2 uv = vec2(-d.z * sign(d.x), -d.y) / size.x * 0.5 + 0.5;
    return d.x > 0.0 ? texture2D(skyFaces[0], uv).rgb : texture2D(skyFaces[1], uv).rgb;
  }
  if (size.y >= size.z) {
    vec2 uv = vec2(d.x, d.z * sign(d.y)) / size.y * 0.5 + 0.5;
    return d.y > 0.0 ? texture2D(skyFaces[2], uv).rgb : texture2D(skyFaces[3], uv).rgb;
  }
  vec2 uv = vec2(d.x * sign(d.z), -d.y) / size.z * 0.5 + 0.5;
  return d.z > 0.0 ? texture2D(skyFaces[4], uv).rgb : texture2D(skyFaces[5], uv).rgb;
}
vec3 skyColor(vec3 d) {
  if (skyKind == 1) return skyLayers(d);
  if (skyKind == 2) return skyBox(d);
  vec3 above = mix(skyHorizon, skyTop, pow(clamp(d.y, 0.0, 1.0), 0.6));
  vec3 below = mix(skyHorizon, skyGround, pow(clamp(-d.y, 0.0, 1.0), 0.4));
  return d.y >= 0.0 ? above : below;
}
`;

const SKY_VERTEX = "varying vec3 vSkyWorld; void main() { vec4 world = modelMatrix * vec4(position, 1.0); vSkyWorld = world.xyz; gl_Position = projectionMatrix * viewMatrix * world; }";
const SKY_FRAGMENT = SKY_GLSL + `
varying vec3 vSkyWorld;
void main() {
  gl_FragColor = vec4(skyColor(normalize(vSkyWorld - cameraPosition)), 1.0);
  #include <tonemapping_fragment>
  #include <colorspace_fragment>
}`;

const WARP_GLSL = `
uniform float warpTime;
vec2 warpedUv(sampler2D picture, vec2 uv) {
  vec2 size = vec2(textureSize(picture, 0));
  vec2 texels = uv * size;
  return (texels + 8.0 * sin(texels.yx / 8.0 + warpTime)) / size;
}
`;

class Reader {
  constructor(buffer) {
    this.view = new DataView(buffer);
    this.bytes = new Uint8Array(buffer);
    this.at = 0;
  }
  done() { return this.at >= this.view.byteLength; }
  u8() { return this.view.getUint8(this.at++); }
  u16() { const value = this.view.getUint16(this.at, true); this.at += 2; return value; }
  u32() { const value = this.view.getUint32(this.at, true); this.at += 4; return value; }
  f32() { const value = this.view.getFloat32(this.at, true); this.at += 4; return value; }
  floats(count) { const out = []; for (let i = 0; i < count; i++) out.push(this.f32()); return out; }
  vec3() { return new THREE.Vector3(this.f32(), this.f32(), this.f32()); }
  quat() { return new THREE.Quaternion(this.f32(), this.f32(), this.f32(), this.f32()).normalize(); }
  transform() { return { position: this.vec3(), rotation: this.quat(), scale: this.vec3() }; }
  slice(length) {
    const out = this.bytes.slice(this.at, this.at + length);
    this.at += length;
    return out;
  }
}

function vertexColours(bytes) {
  const decode = (byte) => {
    const c = byte / 255;
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  };
  const out = new Float32Array(bytes.length);
  for (let i = 0; i < bytes.length; i += 4) out.set([decode(bytes[i]), decode(bytes[i + 1]), decode(bytes[i + 2]), bytes[i + 3] / 255], i);
  return out;
}

function linearColor(rgb) {
  return new THREE.Color().setRGB(rgb[0], rgb[1], rgb[2], THREE.LinearSRGBColorSpace);
}

function copyTransform(t) {
  return { position: t.position.clone(), rotation: t.rotation.clone(), scale: t.scale.clone() };
}

function styleBytes(first, last) {
  return [first & 255, first >> 8, last & 255, last >> 8];
}

const SPRITE_FLOATS = 9;
const QUAD = [[0, 0], [1, 0], [0, 1], [0, 1], [1, 0], [1, 1]];
const SPRITE_BLENDS = [
  { blendSrc: THREE.SrcAlphaFactor, blendDst: THREE.OneMinusSrcAlphaFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor },
  { blendSrc: THREE.OneFactor, blendDst: THREE.OneFactor, blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneFactor },
  { blendSrc: THREE.DstColorFactor, blendDst: THREE.ZeroFactor, blendSrcAlpha: THREE.ZeroFactor, blendDstAlpha: THREE.OneFactor }
];

function readLayer(reader) {
  const kind = reader.u8();
  const layer = { kind, target: reader.u32(), clear: reader.u8() !== 0, clearColour: reader.floats(4), port: reader.floats(4) };
  if (kind === 0) {
    layer.view = reader.floats(4);
    const count = reader.u32();
    layer.sprites = [];
    for (let i = 0; i < count; i++) {
      layer.sprites.push({
        texture: reader.u32(), mode: reader.u32(), source: reader.floats(4), position: reader.floats(2), origin: reader.floats(2),
        scale: reader.floats(2), turn: reader.floats(2), colour: reader.floats(4)
      });
    }
  } else {
    layer.source = reader.u32();
    const count = reader.u32();
    layer.columns = new Float32Array(count * 4);
    for (let i = 0; i < count; i++) layer.columns.set(reader.floats(3), i * 4);
  }
  return layer;
}

class Layers2D {
  constructor(renderer) {
    this.renderer = renderer;
    this.layers = [];
    this.canvases = new Map();
    this.flat = new THREE.WebGLRenderTarget(1, 1, { depthBuffer: false });
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.capacity = 0;
    this.geometry = new THREE.BufferGeometry();
    this.spriteMaterials = SPRITE_BLENDS.map((factors) => new THREE.ShaderMaterial({
      uniforms: { picture: { value: null }, texelSize: { value: new THREE.Vector2(1, 1) }, nearest: { value: 1 }, mode: { value: 0 } },
      vertexShader: "attribute vec2 texels; attribute vec4 tint; varying vec2 vTexels; varying vec4 vTint; void main() { vTexels = texels; vTint = tint; gl_Position = vec4(position.xy, 0.0, 1.0); }",
      fragmentShader: `uniform sampler2D picture; uniform vec2 texelSize; uniform float nearest; uniform float mode; varying vec2 vTexels; varying vec4 vTint;
        void main() {
          vec2 at = nearest > 0.5 ? floor(vTexels + 1.0 / 256.0) + 0.5 : vTexels;
          vec4 texel = texture2D(picture, at * texelSize);
          vec3 colour = texel.rgb * vTint.rgb;
          float alpha = texel.a * vTint.a;
          if (mode > 1.5) gl_FragColor = vec4(1.0 - colour * alpha, 1.0);
          else if (mode > 0.5) gl_FragColor = vec4(colour * alpha, alpha);
          else gl_FragColor = vec4(colour, alpha);
        }`,
      transparent: true, blending: THREE.CustomBlending, ...factors, side: THREE.DoubleSide, depthTest: false, depthWrite: false
    }));
    this.sprites = new THREE.Mesh(this.geometry, this.spriteMaterials[0]);
    this.sprites.frustumCulled = false;
    this.spriteScene = new THREE.Scene();
    this.spriteScene.add(this.sprites);
    this.columnsMaterial = new THREE.ShaderMaterial({
      uniforms: { source: { value: null }, sourceSize: { value: new THREE.Vector2(1, 1) }, table: { value: null }, count: { value: 1 } },
      vertexShader: "attribute vec2 local; varying vec2 vLocal; void main() { vLocal = local; gl_Position = vec4(position.xy, 0.0, 1.0); }",
      fragmentShader: `uniform sampler2D source; uniform vec2 sourceSize; uniform sampler2D table; uniform float count; varying vec2 vLocal;
        vec4 at(vec2 texel) { return texture2D(source, (clamp(texel, vec2(0.0), sourceSize - 1.0) + 0.5) / sourceSize); }
        void main() {
          float column = min(floor(vLocal.x * count), count - 1.0);
          vec4 entry = texture2D(table, vec2((column + 0.5) / count, 0.5));
          vec2 uv = vec2(entry.x, 0.5 + (vLocal.y - 0.5) * entry.y);
          if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
          vec2 point = uv * sourceSize - 0.5;
          vec2 base = floor(point);
          vec2 part = point - base;
          vec4 picture = mix(mix(at(base), at(base + vec2(1.0, 0.0)), part.x), mix(at(base + vec2(0.0, 1.0)), at(base + vec2(1.0, 1.0)), part.x), part.y);
          gl_FragColor = vec4(picture.rgb * entry.z, picture.a);
        }`,
      side: THREE.DoubleSide, depthTest: false, depthWrite: false
    });
    this.columnsGeometry = new THREE.BufferGeometry();
    this.columnsGeometry.setAttribute("position", new THREE.BufferAttribute(new Float32Array(18), 3));
    this.columnsGeometry.setAttribute("local", new THREE.BufferAttribute(new Float32Array(QUAD.flat()), 2));
    this.columnsScene = new THREE.Scene();
    const columns = new THREE.Mesh(this.columnsGeometry, this.columnsMaterial);
    columns.frustumCulled = false;
    this.columnsScene.add(columns);
    this.presentMaterial = new THREE.ShaderMaterial({
      uniforms: { layers: { value: this.flat.texture }, over: { value: 1 } },
      vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
      fragmentShader: "uniform sampler2D layers; uniform float over; varying vec2 vUv; void main() { vec4 shown = texture2D(layers, vec2(vUv.x, 1.0 - vUv.y)); gl_FragColor = over > 0.5 ? shown : vec4(shown.rgb, 1.0); }",
      transparent: true, blending: THREE.CustomBlending, blendSrc: THREE.OneFactor, blendDst: THREE.OneMinusSrcAlphaFactor,
      blendSrcAlpha: THREE.OneFactor, blendDstAlpha: THREE.OneMinusSrcAlphaFactor, depthTest: false, depthWrite: false
    });
    this.presentScene = new THREE.Scene();
    this.presentScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.presentMaterial));
  }

  readCanvas(reader, textures) {
    const id = reader.u32();
    const linear = reader.u8() !== 0;
    const width = reader.u32();
    const height = reader.u32();
    const filter = linear ? THREE.LinearFilter : THREE.NearestFilter;
    const target = new THREE.WebGLRenderTarget(width, height, { depthBuffer: false, magFilter: filter, minFilter: filter });
    target.texture.userData.canvas = { width, height, linear };
    this.drop(id);
    textures.get(id)?.dispose();
    this.canvases.set(id, target);
    textures.set(id, target.texture);
    this.renderer.setRenderTarget(target);
    this.renderer.setClearColor(0x000000, 0);
    this.renderer.clear(true, false, false);
    this.renderer.setRenderTarget(null);
  }

  readLayers(reader) {
    const count = reader.u32();
    const layers = [];
    for (let i = 0; i < count; i++) layers.push(readLayer(reader));
    this.layers = layers;
  }

  drop(id) {
    this.canvases.get(id)?.dispose();
    this.canvases.delete(id);
  }

  resize(width, height) {
    this.flat.setSize(width, height);
  }

  draw(textures, flatOnly) {
    const clear = this.renderer.getClearColor(new THREE.Color());
    const clearAlpha = this.renderer.getClearAlpha();
    let flatStarted = false;
    for (const layer of this.layers) {
      const target = layer.target ? this.canvases.get(layer.target) : this.flat;
      if (!target) continue;
      let clearColour = layer.clear ? layer.clearColour : null;
      if (!layer.target && !flatStarted) {
        clearColour = clearColour || [0, 0, 0, 0];
        flatStarted = true;
      }
      this.renderer.setRenderTarget(target);
      if (clearColour) {
        target.scissorTest = false;
        this.renderer.setClearColor(new THREE.Color().setRGB(clearColour[0], clearColour[1], clearColour[2], THREE.NoColorSpace), clearColour[3]);
        this.renderer.clear(true, false, false);
      }
      const port = this.port(layer, target);
      target.scissor.set(port[0], port[1], port[2], port[3]);
      target.scissorTest = true;
      this.renderer.setRenderTarget(target);
      if (layer.kind === 0) this.drawSprites(layer, target, port, textures);
      else this.drawColumns(layer, target, port, textures);
      target.scissorTest = false;
    }
    if (flatOnly && !flatStarted) {
      this.renderer.setRenderTarget(this.flat);
      this.renderer.setClearColor(0x000000, 0);
      this.renderer.clear(true, false, false);
      flatStarted = true;
    }
    this.renderer.setRenderTarget(null);
    this.renderer.setClearColor(clear, clearAlpha);
    return flatStarted;
  }

  port(layer, target) {
    const whole = layer.port[2] <= 0 || layer.port[3] <= 0;
    return whole ? [0, 0, target.width, target.height] : layer.port;
  }

  drawSprites(layer, target, port, textures) {
    const viewWhole = layer.view[2] === 0 || layer.view[3] === 0;
    const view = viewWhole ? [0, 0, port[2], port[3]] : layer.view;
    const runs = [];
    const vertices = [];
    for (const sprite of layer.sprites) {
      const texture = textures.get(sprite.texture);
      if (!texture || sprite.texture === layer.target) continue;
      const size = this.textureSize(texture);
      const whole = sprite.source[2] <= 0 || sprite.source[3] <= 0;
      const source = whole ? [0, 0, size[0], size[1]] : sprite.source;
      for (const [u, v] of QUAD) {
        const tx = u * source[2], ty = v * source[3];
        const dx = (tx - sprite.origin[0]) * sprite.scale[0], dy = (ty - sprite.origin[1]) * sprite.scale[1];
        const x = sprite.position[0] + dx * sprite.turn[0] + dy * sprite.turn[1];
        const y = sprite.position[1] - dx * sprite.turn[1] + dy * sprite.turn[0];
        const px = port[0] + (x - view[0]) * port[2] / view[2], py = port[1] + (y - view[1]) * port[3] / view[3];
        vertices.push(px / target.width * 2 - 1, py / target.height * 2 - 1, 0, source[0] + tx, source[1] + ty, ...sprite.colour);
      }
      const last = runs[runs.length - 1];
      if (last && last.texture === texture && last.mode === sprite.mode) last.count += 6;
      else runs.push({ texture, mode: sprite.mode, first: vertices.length / SPRITE_FLOATS - 6, count: 6, size, nearest: !this.linear(texture) });
    }
    if (!runs.length) return;
    this.fill(vertices);
    for (const run of runs) {
      const material = this.spriteMaterials[run.mode];
      material.uniforms.picture.value = run.texture;
      material.uniforms.texelSize.value.set(1 / run.size[0], 1 / run.size[1]);
      material.uniforms.nearest.value = run.nearest ? 1 : 0;
      material.uniforms.mode.value = run.mode;
      this.sprites.material = material;
      this.geometry.setDrawRange(run.first, run.count);
      this.renderer.render(this.spriteScene, this.camera);
    }
  }

  fill(vertices) {
    const count = vertices.length / SPRITE_FLOATS;
    if (count > this.capacity) {
      this.capacity = Math.max(count, this.capacity * 2, 600);
      this.buffer = new Float32Array(this.capacity * SPRITE_FLOATS);
      const interleaved = new THREE.InterleavedBuffer(this.buffer, SPRITE_FLOATS);
      interleaved.setUsage(THREE.DynamicDrawUsage);
      this.interleaved = interleaved;
      this.geometry.setAttribute("position", new THREE.InterleavedBufferAttribute(interleaved, 3, 0));
      this.geometry.setAttribute("texels", new THREE.InterleavedBufferAttribute(interleaved, 2, 3));
      this.geometry.setAttribute("tint", new THREE.InterleavedBufferAttribute(interleaved, 4, 5));
    }
    this.buffer.set(vertices);
    this.interleaved.needsUpdate = true;
  }

  drawColumns(layer, target, port, textures) {
    const source = textures.get(layer.source);
    const count = layer.columns.length / 4;
    if (!source || layer.source === layer.target || count === 0) return;
    const positions = this.columnsGeometry.attributes.position;
    QUAD.forEach(([u, v], i) => positions.setXYZ(i, (port[0] + u * port[2]) / target.width * 2 - 1, (port[1] + v * port[3]) / target.height * 2 - 1, 0));
    positions.needsUpdate = true;
    this.columnTable?.dispose();
    this.columnTable = new THREE.DataTexture(layer.columns, count, 1, THREE.RGBAFormat, THREE.FloatType);
    this.columnTable.needsUpdate = true;
    const size = this.textureSize(source);
    this.columnsMaterial.uniforms.source.value = source;
    this.columnsMaterial.uniforms.sourceSize.value.set(size[0], size[1]);
    this.columnsMaterial.uniforms.table.value = this.columnTable;
    this.columnsMaterial.uniforms.count.value = count;
    this.renderer.render(this.columnsScene, this.camera);
  }

  textureSize(texture) {
    const canvas = texture.userData.canvas;
    if (canvas) return [canvas.width, canvas.height];
    return [texture.image.width, texture.image.height];
  }

  linear(texture) {
    return texture.magFilter === THREE.LinearFilter;
  }

  present(over) {
    this.presentMaterial.uniforms.over.value = over ? 1 : 0;
    this.presentMaterial.blending = over ? THREE.CustomBlending : THREE.NoBlending;
    this.renderer.render(this.presentScene, this.camera);
  }
}

class Scene3D {
  constructor(canvas) {
    this.canvas = canvas;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
    this.renderer.setPixelRatio(window.devicePixelRatio);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.layers2d = new Layers2D(this.renderer);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(68, 1, 0.05, 1000);
    this.cameraState = null;
    this.meshes = new Map();
    this.textures = new Map();
    this.materials = new Map();
    this.materialData = new Map();
    this.instances = new Map();
    this.lights = new Map();
    this.styles = new Float32Array(64 * 3).fill(1);
    this.previousTick = 0;
    this.currentTick = 0;
    this.ambient = new THREE.HemisphereLight(0xffffff, 0x444444, 0.3);
    this.scene.add(this.ambient);
    this.environment = null;
    this.started = performance.now();
    this.skyIds = [0, 0, 0, 0, 0, 0];
    this.skyUniforms = {
      skyKind: { value: 0 },
      skyFaces: { value: [null, null, null, null, null, null] },
      skyScroll: { value: new THREE.Vector2(0.0625, 0.125) },
      skyTime: { value: 0 },
      skyTop: { value: new THREE.Color(0.25, 0.45, 0.85) },
      skyHorizon: { value: new THREE.Color(0.75, 0.85, 0.95) },
      skyGround: { value: new THREE.Color(0.25, 0.22, 0.2) }
    };
    this.warpTime = { value: 0 };
    this.lightUniforms = {
      cauldronDisplay: { value: 0 },
      cauldronHasTable: { value: 0 },
      cauldronReach: { value: 1 },
      cauldronTable: { value: null }
    };
    this.lightTableId = 0;
    this.viewport = [0, 0, 1, 1];
    this.viewAspect = 0;
    this.behindTarget = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType });
    this.behindTexture = { value: this.behindTarget.texture };
    this.resolution = { value: new THREE.Vector2(1, 1) };
    this.frameIndex = { value: 0 };
    for (const layer of [LAYER_SMEAR, LAYER_STANDING, LAYER_FRONT, LAYER_DOME]) this.camera.layers.enable(layer);
    this.nearestTarget = new THREE.WebGLRenderTarget(1, 1, { type: THREE.FloatType });
    this.nearestTexture = { value: this.nearestTarget.texture };
    this.nearestMaterial = new THREE.ShaderMaterial({
      vertexShader:
        "varying vec3 vWorldNormal; varying float vHeight; void main() { vWorldNormal = (vec4(normalMatrix * normal, 0.0) * viewMatrix).xyz; vec4 world = modelMatrix * vec4(position, 1.0); vHeight = world.y; gl_Position = projectionMatrix * viewMatrix * world; }",
      fragmentShader:
        "varying vec3 vWorldNormal; varying float vHeight; void main() { gl_FragColor = vec4(gl_FragCoord.z, normalize(vWorldNormal).y * (gl_FrontFacing ? 1.0 : -1.0), vHeight, 1.0); }",
      side: THREE.DoubleSide
    });
    this.blank = new THREE.DataTexture(new Uint8Array([0, 0, 0, 255]), 1, 1);
    this.blank.needsUpdate = true;
    this.dome = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), this.skyMaterial({ side: THREE.BackSide, depthTest: false, depthWrite: false }));
    this.dome.frustumCulled = false;
    this.dome.renderOrder = -1e9;
    this.dome.layers.set(LAYER_DOME);
    this.scene.add(this.dome);
    this.bloomStrength = 0.05;
    this.composer = new EffectComposer(this.renderer);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.05, 0.4, 1.0);
    this.composer.addPass(this.bloom);
    this.composer.addPass(new OutputPass());
    this.finish = new ShaderPass(FINISH_SHADER);
    this.composer.addPass(this.finish);
    this.screenScene = new THREE.Scene();
    this.screenCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.screenMaterial = new THREE.ShaderMaterial({
      uniforms: { overlay: { value: null }, hasOverlay: { value: 0 }, premultiplied: { value: 0 }, tint: { value: new THREE.Vector4(0, 0, 0, 0) } },
      vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
      fragmentShader: LIGHT_GLSL + `uniform sampler2D overlay; uniform float hasOverlay; uniform float premultiplied; uniform vec4 tint; varying vec2 vUv;
        void main() {
          vec4 picture = hasOverlay > 0.5 ? texture2D(overlay, vec2(vUv.x, 1.0 - vUv.y)) : vec4(0.0);
          vec3 shown = cauldronEncode(picture.rgb) * (premultiplied > 0.5 ? 1.0 : picture.a);
          gl_FragColor = vec4(tint.rgb * tint.a * (1.0 - picture.a) + shown, 1.0 - (1.0 - tint.a) * (1.0 - picture.a));
        }`,
      transparent: true,
      blending: THREE.CustomBlending,
      blendSrc: THREE.OneFactor,
      blendDst: THREE.OneMinusSrcAlphaFactor,
      depthTest: false,
      depthWrite: false
    });
    this.screenScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.screenMaterial));
    this.renderer.autoClear = false;
    this.resize();
    window.addEventListener("resize", () => this.resize());
  }

  readOverlay(reader) {
    this.overlayId = reader.u32();
    this.screenMaterial.uniforms.premultiplied.value = reader.u8();
  }

  readScreenTint(reader) {
    const [r, g, b, a] = reader.floats(4);
    this.screenMaterial.uniforms.tint.value.set(r, g, b, a);
  }

  drawScreen() {
    const overlay = this.overlayId ? this.textures.get(this.overlayId) : null;
    const tint = this.screenMaterial.uniforms.tint.value;
    if (!overlay && tint.w <= 0) return;
    this.screenMaterial.uniforms.overlay.value = overlay || null;
    this.screenMaterial.uniforms.hasOverlay.value = overlay ? 1 : 0;
    this.renderer.render(this.screenScene, this.screenCamera);
  }

  resize() {
    const width = this.canvas.clientWidth || window.innerWidth;
    const height = this.canvas.clientHeight || window.innerHeight;
    this.renderer.setSize(width, height, false);
    this.composer.setSize(width, height);
    const buffer = this.renderer.getDrawingBufferSize(new THREE.Vector2());
    this.behindTarget.setSize(buffer.x, buffer.y);
    this.nearestTarget.setSize(buffer.x, buffer.y);
    this.layers2d.resize(buffer.x, buffer.y);
    this.resolution.value.copy(buffer);
    this.project();
    return { width, height };
  }

  apply(buffer) {
    const reader = new Reader(buffer);
    while (!reader.done()) {
      const op = reader.u8();
      const handler = this.ops[op];
      if (!handler) throw new Error("cauldron3d: unknown operation " + op);
      handler.call(this, reader);
    }
  }

  tick() {
    this.previousTick = this.currentTick;
    this.currentTick = performance.now();
    for (const instance of this.instances.values()) instance.previous = copyTransform(instance.current);
    if (this.cameraState) this.cameraState.previous = copyTransform(this.cameraState.current);
  }

  readMesh(reader, skinned) {
    const id = reader.u32();
    const vertexCount = reader.u32();
    const indexCount = reader.u32();
    const partCount = reader.u32();
    const parts = [];
    for (let i = 0; i < partCount; i++) parts.push({ first: reader.u32(), count: reader.u32() });
    const raw = new Float32Array(reader.slice(vertexCount * 48).buffer);
    const indices = new Uint32Array(reader.slice(indexCount * 4).buffer);
    const skin = skinned ? reader.slice(vertexCount * 8) : null;
    const colorBytes = reader.u32() !== 0 ? reader.slice(vertexCount * 4) : null;
    const position = new Float32Array(vertexCount * 3);
    const normal = new Float32Array(vertexCount * 3);
    const uv = new Float32Array(vertexCount * 2);
    const uv1 = new Float32Array(vertexCount * 2);
    const styles = new Float32Array(vertexCount * 4);
    for (let v = 0; v < vertexCount; v++) {
      const at = v * VERTEX_FLOATS;
      position.set([raw[at], raw[at + 1], raw[at + 2]], v * 3);
      normal.set([raw[at + 4], raw[at + 5], raw[at + 6]], v * 3);
      uv.set([raw[at + 3], raw[at + 7]], v * 2);
      uv1.set([raw[at + 8], raw[at + 9]], v * 2);
      styles.set(styleBytes(raw[at + 10], raw[at + 11]), v * 4);
    }
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(position, 3));
    geometry.setAttribute("normal", new THREE.BufferAttribute(normal, 3));
    geometry.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
    geometry.setAttribute("uv1", new THREE.BufferAttribute(uv1, 2));
    geometry.setAttribute("lightStyles", new THREE.BufferAttribute(styles, 4));
    if (colorBytes) geometry.setAttribute("color", new THREE.BufferAttribute(vertexColours(colorBytes), 4));
    geometry.setIndex(new THREE.BufferAttribute(indices, 1));
    const groups = parts.length ? parts : [{ first: 0, count: indexCount }];
    groups.forEach((part, index) => geometry.addGroup(part.first, part.count, index));
    geometry.computeBoundingSphere();
    this.meshes.set(id, { geometry, position, normal, skin, vertexCount, colored: colorBytes !== null });
  }

  readTexture(reader) {
    const id = reader.u32();
    const format = reader.u8();
    const linear = reader.u8() !== 0;
    const clamp = reader.u8() !== 0;
    const mipmaps = reader.u8() !== 0;
    const width = reader.u32();
    const height = reader.u32();
    const half = format === 2;
    const bytes = reader.slice(width * height * (half ? 8 : 4));
    const data = half ? new Uint16Array(bytes.buffer) : bytes;
    const texture = new THREE.DataTexture(data, width, height, THREE.RGBAFormat, half ? THREE.HalfFloatType : THREE.UnsignedByteType);
    texture.colorSpace = format === 0 ? THREE.SRGBColorSpace : THREE.NoColorSpace;
    texture.magFilter = linear ? THREE.LinearFilter : THREE.NearestFilter;
    texture.minFilter = mipmaps ? THREE.LinearMipmapLinearFilter : texture.magFilter;
    texture.generateMipmaps = mipmaps;
    texture.wrapS = texture.wrapT = clamp ? THREE.ClampToEdgeWrapping : THREE.RepeatWrapping;
    texture.flipY = false;
    texture.needsUpdate = true;
    this.textures.get(id)?.dispose();
    this.textures.set(id, texture);
  }

  readMaterial(reader) {
    const id = reader.u32();
    const base = reader.floats(4);
    const emissive = reader.floats(3);
    const [emissiveStrength, metallic, roughness, alphaCutoff] = reader.floats(4);
    const flags = reader.u32();
    const [baseTexture, metallicRoughness, emissiveTexture, lightmap] = [reader.u32(), reader.u32(), reader.u32(), reader.u32()];
    const lightmapScale = reader.f32();
    const [normalTexture, occlusionTexture] = [reader.u32(), reader.u32()];
    const normalScale = reader.f32();
    const smear = reader.f32();
    const uvScroll = reader.floats(2);
    const data = {
      base, emissive, emissiveStrength, metallic, roughness, alphaCutoff, flags, baseTexture, metallicRoughness,
      emissiveTexture, lightmap, lightmapScale, normalTexture, occlusionTexture, normalScale, smear, uvScroll
    };
    this.materialData.set(id, data);
    this.materials.get(id)?.dispose();
    this.materials.set(id, this.buildMaterial(data));
  }

  texture(id) { return id ? this.textures.get(id) || null : null; }

  skyMaterial(options) {
    return new THREE.ShaderMaterial({ uniforms: this.skyUniforms, vertexShader: SKY_VERTEX, fragmentShader: SKY_FRAGMENT, ...options });
  }

  buildMaterial(data, variant = { inFront: false, shading: null }) {
    if ((data.flags & MATERIAL_SKY) !== 0) return this.skyMaterial({ side: (data.flags & 2) !== 0 ? THREE.DoubleSide : THREE.FrontSide });
    if (data.smear > 0) return this.smearMaterial(data);
    const material = this.surfaceMaterial(data);
    this.patch(material, data, variant);
    return material;
  }

  smearMaterial(data) {
    const map = this.texture(data.baseTexture);
    return new THREE.ShaderMaterial({
      uniforms: {
        behind: this.behindTexture,
        resolution: this.resolution,
        frameIndex: this.frameIndex,
        smear: { value: data.smear },
        tint: { value: linearColor(data.base) },
        map: { value: map || this.blank },
        hasMap: { value: map ? 1 : 0 },
        cutoff: { value: data.alphaCutoff }
      },
      vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
      fragmentShader: SMEAR_FRAGMENT,
      side: (data.flags & 2) !== 0 ? THREE.DoubleSide : THREE.FrontSide,
      depthWrite: false
    });
  }

  surfaceMaterial(data) {
    const unlit = (data.flags & 1) !== 0;
    const doubleSided = (data.flags & 2) !== 0;
    const blend = (data.flags & 4) !== 0;
    const common = {
      color: new THREE.Color().setRGB(data.base[0], data.base[1], data.base[2], THREE.LinearSRGBColorSpace),
      map: this.texture(data.baseTexture),
      transparent: blend,
      opacity: blend ? data.base[3] : 1,
      alphaTest: data.alphaCutoff,
      side: doubleSided ? THREE.DoubleSide : THREE.FrontSide,
      depthWrite: !blend
    };
    if (unlit) return new THREE.MeshBasicMaterial(common);
    return new THREE.MeshStandardMaterial({
      ...common,
      metalness: data.metallic,
      roughness: data.roughness,
      metalnessMap: this.texture(data.metallicRoughness),
      roughnessMap: this.texture(data.metallicRoughness),
      emissive: new THREE.Color().setRGB(data.emissive[0], data.emissive[1], data.emissive[2], THREE.LinearSRGBColorSpace),
      emissiveIntensity: data.emissiveStrength,
      emissiveMap: this.texture(data.emissiveTexture),
      normalMap: this.texture(data.normalTexture),
      normalScale: new THREE.Vector2(data.normalScale, data.normalScale),
      aoMap: this.texture(data.occlusionTexture),
      lightMap: this.texture(data.lightmap),
      lightMapIntensity: data.lightmapScale * Math.PI
    });
  }

  patch(material, data, variant) {
    const slots = material.lightMap ? Math.max(1, (data.flags >> 8) & 255) : 0;
    const warp = (data.flags & MATERIAL_WARP) !== 0 && material.map !== null;
    const reflection = (data.flags & MATERIAL_REFLECTION) !== 0 && material.map !== null;
    const scroll = (data.uvScroll[0] !== 0 || data.uvScroll[1] !== 0) && material.map !== null;
    const add = (data.flags & MATERIAL_ADD) !== 0;
    const multiply = (data.flags & MATERIAL_MULTIPLY) !== 0;
    const shading = variant.shading;
    const swell = variant.swell;
    if (slots) material.lightMap.channel = 1;
    const shadeUniforms = shading && {
      shadeAmbient: { value: new THREE.Vector3(...shading.slice(0, 3)) },
      shadeDirectional: { value: new THREE.Vector3(...shading.slice(3, 6)) },
      shadeDirection: { value: new THREE.Vector3(...shading.slice(6, 9)) }
    };
    const standing = variant.standing;
    if (standing || variant.noDepth) Object.assign(material, { depthTest: false, depthWrite: false, transparent: true });
    if (variant.inFront) Object.assign(material, { transparent: true });
    if (add) Object.assign(material, { blending: THREE.AdditiveBlending, transparent: true, depthWrite: false });
    if (multiply) Object.assign(material, { blending: THREE.CustomBlending, blendSrc: THREE.DstColorFactor, blendDst: THREE.ZeroFactor, transparent: true, depthWrite: false });
    if (variant.colors) material.vertexColors = true;
    material.customProgramCacheKey = () =>
      ["cauldron", slots, warp, variant.inFront, !!shading, reflection, scroll, multiply, !!swell, !!variant.colors, !!standing].join("-");
    material.onBeforeCompile = (shader) => {
      Object.assign(shader.uniforms, this.lightUniforms, { lightStyleScales: { value: this.styles }, warpTime: this.warpTime, cauldronTime: this.warpTime }, shadeUniforms || {});
      shader.uniforms.uvScroll = { value: new THREE.Vector2(data.uvScroll[0], data.uvScroll[1]) };
      shader.uniforms.cauldronSwell = { value: new THREE.Vector3(...(swell || [0, 0, 0])) };
      let vertex = shader.vertexShader
        .replace("#include <common>", "#include <common>\nuniform float cauldronTime;\nuniform vec3 cauldronSwell;\nvarying vec3 vCauldronWorld;\nvarying vec3 vCauldronNormal;")
        .replace(
          "#include <begin_vertex>",
          `#include <begin_vertex>
          ${swell ? "transformed += normal * cauldronSwell.y * sin(uv.x * cauldronSwell.x + cauldronTime * cauldronSwell.z);" : ""}
          vCauldronWorld = (modelMatrix * vec4(transformed, 1.0)).xyz;
          vCauldronNormal = normalize(mat3(modelMatrix) * normal);`
        );
      let fragment = shader.fragmentShader
        .replace(
          "#include <common>",
          "#include <common>\n" + LIGHT_GLSL + (warp ? WARP_GLSL : "") +
            "\nuniform float cauldronTime;\nuniform vec2 uvScroll;\nvarying vec3 vCauldronWorld;\nvarying vec3 vCauldronNormal;\n" +
            "vec2 cauldronReflectionUv() { vec3 r = reflect(normalize(vCauldronWorld - cameraPosition), normalize(vCauldronNormal)); return vec2(0.5 - r.z * 0.5, 0.5 - r.y * 0.5); }"
        );
      if (slots) {
        vertex = vertex
          .replace("#include <common>", "#include <common>\nattribute vec4 lightStyles;\nvarying vec4 vLightStyles;")
          .replace("#include <uv_vertex>", "#include <uv_vertex>\nvLightStyles = lightStyles;");
        fragment = fragment
          .replace("#include <common>", "#include <common>\nuniform vec3 lightStyleScales[64];\nvarying vec4 vLightStyles;")
          .replace("#include <lights_fragment_maps>", THREE.ShaderChunk.lights_fragment_maps.replace(
            "vec3 lightMapIrradiance = lightMapTexel.rgb * lightMapIntensity;",
            `vec3 styled = vec3(0.0);
            for (int slot = 0; slot < ${slots}; slot++) {
              int style = int(vLightStyles[slot] + 0.5);
              if (style >= 64) continue;
              vec2 slotUv = vec2(vLightMapUv.x + float(slot) / ${slots}.0, vLightMapUv.y);
              styled += texture2D(lightMap, slotUv).rgb * lightStyleScales[style];
            }
            cauldronLight = cauldronTabled(styled * lightMapIntensity * RECIPROCAL_PI, vViewPosition.z);
            vec3 lightMapIrradiance = cauldronLight * PI;`
          ));
      }
      if (shading) {
        fragment = fragment
          .replace("#include <common>", "#include <common>\nuniform vec3 shadeAmbient;\nuniform vec3 shadeDirectional;\nuniform vec3 shadeDirection;")
          .replace("#include <lights_fragment_maps>", "#include <lights_fragment_maps>\ncauldronLight = cauldronTabled(max(shadeAmbient + shadeDirectional * dot(normal, normalize((viewMatrix * vec4(shadeDirection, 0.0)).xyz)), vec3(0.0)), vViewPosition.z);");
      }
      fragment = fragment
        .replace("void main() {", fragment.includes("#include <lights_fragment_begin>") ? DYNAMIC_GLSL + "\nvoid main() {" : "void main() {")
        .replace("#include <lights_fragment_begin>", "vec3 cauldronLight = vec3(-1.0);\n#include <lights_fragment_begin>")
        .replace(
          "vec3 outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;",
          `vec3 outgoingLight = totalDiffuse + totalSpecular + totalEmissiveRadiance;
          if (cauldronLight.x >= 0.0 && cauldronDisplay > 0.5) outgoingLight = cauldronDisplayLit(diffuseColor.rgb, cauldronLight + cauldronDynamic(-vViewPosition, normal), totalEmissiveRadiance);
          else if (${shading ? "true" : "false"}) outgoingLight = diffuseColor.rgb * cauldronLight + totalEmissiveRadiance;`
        );
      const base = reflection ? "cauldronReflectionUv()" : "vMapUv";
      const moved = scroll ? `(${base} + uvScroll * cauldronTime)` : base;
      const sampled = warp ? `warpedUv( map, ${moved} )` : moved;
      if (sampled !== "vMapUv") fragment = fragment.replace("#include <map_fragment>", THREE.ShaderChunk.map_fragment.replace("texture2D( map, vMapUv )", `texture2D( map, ${sampled} )`));
      if (multiply) fragment = fragment.replace("#include <dithering_fragment>", "#include <dithering_fragment>\ngl_FragColor = vec4(mix(vec3(1.0), gl_FragColor.rgb, gl_FragColor.a), 1.0);");
      if (standing) {
        shader.uniforms.cauldronNearest = this.nearestTexture;
        shader.uniforms.cauldronScreen = this.resolution;
        shader.uniforms.cauldronStanding = { value: new THREE.Vector2(standing[0], standing[1]) };
        fragment = fragment
          .replace("#include <common>", "#include <common>\nuniform sampler2D cauldronNearest;\nuniform vec2 cauldronScreen;\nuniform vec2 cauldronStanding;")
          .replace(
            "void main() {",
            "void main() {\n  vec4 near = texture2D(cauldronNearest, gl_FragCoord.xy / cauldronScreen);\n  if (near.r < gl_FragCoord.z && !((near.g > 0.7071 && near.b <= cauldronStanding.x + 1e-3) || (near.g < -0.7071 && near.b >= cauldronStanding.y - 1e-3))) discard;"
          );
      }
      if (variant.inFront) vertex = vertex.replace("#include <project_vertex>", "#include <project_vertex>\ngl_Position.z = -0.9 * gl_Position.w + 0.1 * gl_Position.z;");
      shader.vertexShader = vertex;
      shader.fragmentShader = fragment;
    };
  }

  readInstance(reader) {
    const id = reader.u32();
    const meshId = reader.u32();
    const flags = reader.u32();
    const transform = reader.transform();
    const count = reader.u32();
    const materialIds = [];
    for (let i = 0; i < count; i++) materialIds.push(reader.u32());
    const shaded = reader.u32() !== 0;
    const shading = reader.floats(9);
    const swell = reader.floats(3);
    const standing = reader.floats(2);
    const mesh = this.meshes.get(meshId);
    if (!mesh) return;
    const existing = this.instances.get(id);
    const snap = !existing || (flags & SNAP) !== 0;
    if (existing) this.forget(existing);
    const geometry = existing && existing.mesh === mesh && existing.geometry !== mesh.geometry ? existing.geometry : mesh.geometry;
    const variant = {
      inFront: (flags & IN_FRONT) !== 0,
      shading: shaded ? shading : null,
      noDepth: (flags & NO_DEPTH_TEST) !== 0,
      swell: swell[1] !== 0 ? swell : null,
      colors: mesh.colored,
      standing: (flags & STANDING) !== 0 ? standing : null
    };
    const own = variant.inFront || shaded || variant.noDepth || variant.swell !== null || variant.colors || variant.standing !== null;
    const materialFor = (materialId) => {
      const data = this.materialData.get(materialId);
      if (!data) return new THREE.MeshStandardMaterial();
      return own ? this.buildMaterial(data, variant) : this.materials.get(materialId);
    };
    const materials = mesh.geometry.groups.map((group, index) => materialFor(materialIds[Math.min(index, materialIds.length - 1)]));
    const object = new THREE.Mesh(geometry, materials);
    const smeared = materials.some((material) => material.uniforms && material.uniforms.behind);
    if (smeared) object.layers.set(LAYER_SMEAR);
    if (variant.standing && smeared) object.layers.enable(LAYER_STANDING);
    else if (variant.standing) object.layers.set(LAYER_STANDING);
    if (variant.inFront) {
      object.layers.set(LAYER_FRONT);
      object.renderOrder = 1e9;
    }
    object.castShadow = (flags & 2) === 0 && !variant.inFront;
    object.receiveShadow = true;
    object.visible = (flags & 1) === 0;
    this.scene.add(object);
    this.instances.set(id, {
      object, mesh, geometry, own: own ? materials : [], current: transform, previous: snap ? copyTransform(transform) : existing.current
    });
  }

  forget(instance) {
    this.scene.remove(instance.object);
    for (const material of instance.own) material.dispose();
  }

  readMove(reader) {
    const id = reader.u32();
    const flags = reader.u32();
    const transform = reader.transform();
    const instance = this.instances.get(id);
    if (!instance) return;
    instance.previous = (flags & SNAP) !== 0 ? copyTransform(transform) : instance.current;
    instance.current = transform;
  }

  removeInstance(reader) {
    const id = reader.u32();
    const instance = this.instances.get(id);
    if (!instance) return;
    this.forget(instance);
    if (instance.geometry !== instance.mesh.geometry) instance.geometry.dispose();
    this.instances.delete(id);
  }

  readPose(reader) {
    const id = reader.u32();
    const blendId = reader.u32();
    const blend = reader.f32();
    const boneCount = reader.u32();
    const bones = reader.floats(boneCount * 12);
    const instance = this.instances.get(id);
    if (!instance) return;
    if (instance.geometry === instance.mesh.geometry) {
      instance.geometry = instance.mesh.geometry.clone();
      instance.object.geometry = instance.geometry;
    }
    this.deform(instance, this.meshes.get(blendId), blend, bones);
  }

  deform(instance, target, blend, bones) {
    const source = instance.mesh;
    const position = instance.geometry.getAttribute("position");
    const normal = instance.geometry.getAttribute("normal");
    const blends = target && target.vertexCount === source.vertexCount && blend > 0;
    const skins = source.skin && bones.length > 0;
    const p = [0, 0, 0], n = [0, 0, 0];
    for (let v = 0; v < source.vertexCount; v++) {
      for (let k = 0; k < 3; k++) {
        p[k] = source.position[v * 3 + k];
        n[k] = source.normal[v * 3 + k];
        if (blends) {
          p[k] += (target.position[v * 3 + k] - p[k]) * blend;
          n[k] += (target.normal[v * 3 + k] - n[k]) * blend;
        }
      }
      if (skins) this.skinVertex(source.skin, v, bones, p, n);
      position.setXYZ(v, p[0], p[1], p[2]);
      normal.setXYZ(v, n[0], n[1], n[2]);
    }
    position.needsUpdate = true;
    normal.needsUpdate = true;
    instance.geometry.computeBoundingSphere();
  }

  skinVertex(skin, v, bones, p, n) {
    const boneCount = bones.length / 12;
    const sp = [0, 0, 0], sn = [0, 0, 0];
    for (let slot = 0; slot < 4; slot++) {
      const weight = skin[v * 8 + 4 + slot] / 255;
      if (weight <= 0) continue;
      const b = Math.min(skin[v * 8 + slot], boneCount - 1) * 12;
      for (let row = 0; row < 3; row++) {
        const m = b + row * 4;
        sp[row] += (bones[m] * p[0] + bones[m + 1] * p[1] + bones[m + 2] * p[2] + bones[m + 3]) * weight;
        sn[row] += (bones[m] * n[0] + bones[m + 1] * n[1] + bones[m + 2] * n[2]) * weight;
      }
    }
    for (let k = 0; k < 3; k++) { p[k] = sp[k]; n[k] = sn[k]; }
  }

  readLight(reader) {
    const id = reader.u32();
    const kind = reader.u8();
    const shadows = reader.u8() !== 0;
    reader.u16();
    const color = reader.floats(3);
    const intensity = reader.f32();
    const position = reader.vec3();
    const direction = reader.vec3().normalize();
    const [range, inner, outer] = reader.floats(3);
    const existing = this.lights.get(id);
    if (existing) this.scene.remove(existing);
    const tint = new THREE.Color().setRGB(color[0], color[1], color[2], THREE.LinearSRGBColorSpace);
    let light;
    if (kind === 0) {
      light = new THREE.DirectionalLight(tint, intensity);
      light.userData.direction = direction;
      light.castShadow = shadows;
      light.shadow.mapSize.set(2048, 2048);
      light.shadow.bias = -0.0005;
      this.scene.add(light.target);
    } else if (kind === 1) {
      light = new THREE.PointLight(tint, intensity, range, 2);
      light.position.copy(position);
    } else {
      light = new THREE.SpotLight(tint, intensity, range, outer, 1 - inner / Math.max(outer, 1e-4), 2);
      light.position.copy(position);
      light.target.position.copy(position.clone().add(direction));
      this.scene.add(light.target);
    }
    this.scene.add(light);
    this.lights.set(id, light);
  }

  removeLight(reader) {
    const id = reader.u32();
    const light = this.lights.get(id);
    if (light) this.scene.remove(light);
    this.lights.delete(id);
  }

  readCamera(reader) {
    const transform = { position: reader.vec3(), rotation: reader.quat(), scale: new THREE.Vector3(1, 1, 1) };
    const [fov, near, far] = reader.floats(3);
    const flags = reader.u32();
    this.viewport = reader.floats(4);
    this.viewAspect = reader.f32();
    this.finish.uniforms.blocks.value.set(reader.f32(), reader.f32());
    const previous = !this.cameraState || (flags & SNAP) !== 0 ? copyTransform(transform) : this.cameraState.current;
    this.cameraState = { current: transform, previous };
    this.camera.fov = THREE.MathUtils.radToDeg(fov);
    this.camera.near = near;
    this.camera.far = far;
    this.project();
  }

  project() {
    const size = this.renderer.getSize(new THREE.Vector2());
    const [x, y, width, height] = this.viewport;
    this.camera.aspect = this.viewAspect > 0 ? this.viewAspect : (size.x * width) / Math.max(size.y * height, 1);
    this.camera.updateProjectionMatrix();
    const e = this.camera.projectionMatrix.elements;
    const shiftX = 2 * x + width - 1;
    const shiftY = 1 - 2 * y - height;
    for (let column = 0; column < 4; column++) {
      e[column * 4] = width * e[column * 4] + shiftX * e[column * 4 + 3];
      e[column * 4 + 1] = height * e[column * 4 + 1] + shiftY * e[column * 4 + 3];
    }
    this.camera.projectionMatrixInverse.copy(this.camera.projectionMatrix).invert();
    this.finish.uniforms.viewport.value.set(x, y, width, height);
  }

  readEnvironment(reader) {
    const [top, horizon, ground, ambient] = [reader.floats(3), reader.floats(3), reader.floats(3), reader.floats(3)];
    const ambientIntensity = reader.f32();
    const fog = reader.floats(3);
    const [fogDensity, exposure, shadowDistance, reflections, , , , bloomStrength, bloomThreshold] = reader.floats(9);
    const toneMap = reader.u32();
    this.skyUniforms.skyKind.value = reader.u32();
    for (let face = 0; face < 6; face++) this.skyIds[face] = reader.u32();
    this.skyUniforms.skyScroll.value.set(reader.f32(), reader.f32());
    this.lightUniforms.cauldronDisplay.value = reader.u32();
    this.finish.uniforms.gamma.value = reader.f32();
    this.finish.uniforms.contrast.value = reader.f32();
    this.finish.uniforms.brightness.value = reader.f32();
    this.lightTableId = reader.u32();
    this.lightUniforms.cauldronReach.value = Math.max(reader.f32(), 1e-6);
    this.skyUniforms.skyTop.value = linearColor(top);
    this.skyUniforms.skyHorizon.value = linearColor(horizon);
    this.skyUniforms.skyGround.value = linearColor(ground);
    this.renderer.toneMappingExposure = exposure;
    this.renderer.toneMapping = [THREE.ACESFilmicToneMapping, THREE.NeutralToneMapping, THREE.NoToneMapping][toneMap] || THREE.ACESFilmicToneMapping;
    const linear = (rgb) => new THREE.Color().setRGB(rgb[0], rgb[1], rgb[2], THREE.LinearSRGBColorSpace);
    this.ambient.color = linear(ambient).lerp(linear(top), 0.5);
    this.ambient.groundColor = linear(ground);
    this.ambient.intensity = ambientIntensity * Math.PI;
    this.scene.fog = fogDensity > 0 ? new THREE.FogExp2(linear(fog), fogDensity) : null;
    this.scene.environment?.dispose?.();
    this.scene.environment = reflections > 0 ? this.skyTexture(top, horizon, ground) : null;
    this.scene.environmentIntensity = reflections;
    this.shadowDistance = shadowDistance;
    this.bloom.strength = bloomStrength * 10;
    this.bloom.threshold = bloomThreshold;
  }

  skyTexture(top, horizon, ground) {
    const canvas = document.createElement("canvas");
    canvas.width = 4;
    canvas.height = 256;
    const context = canvas.getContext("2d");
    const css = (rgb) => "#" + new THREE.Color().setRGB(rgb[0], rgb[1], rgb[2], THREE.LinearSRGBColorSpace).getHexString();
    const gradient = context.createLinearGradient(0, 0, 0, 256);
    gradient.addColorStop(0, css(top));
    gradient.addColorStop(0.5, css(horizon));
    gradient.addColorStop(1, css(ground));
    context.fillStyle = gradient;
    context.fillRect(0, 0, 4, 256);
    const texture = new THREE.CanvasTexture(canvas);
    texture.mapping = THREE.EquirectangularReflectionMapping;
    texture.colorSpace = THREE.SRGBColorSpace;
    return texture;
  }

  readLightStyles(reader) {
    const count = reader.u32();
    for (let i = 0; i < count; i++) {
      const [r, g, b] = reader.floats(3);
      if (i < 64) this.styles.set([r, g, b], i * 3);
    }
  }

  readEffects(reader) {
    this.effects = reader.u32();
  }

  dropMesh(reader) {
    const id = reader.u32();
    this.meshes.get(id)?.geometry.dispose();
    this.meshes.delete(id);
  }

  dropTexture(reader) {
    const id = reader.u32();
    this.textures.get(id)?.dispose();
    this.textures.delete(id);
    this.layers2d.drop(id);
  }

  dropMaterial(reader) {
    const id = reader.u32();
    this.materials.get(id)?.dispose();
    this.materials.delete(id);
  }

  progress(now) {
    const span = this.currentTick - this.previousTick;
    if (!this.previousTick || span <= 0) return 1;
    return Math.min(Math.max((now - this.currentTick) / span, 0), 1);
  }

  place(object, state, t) {
    object.position.lerpVectors(state.previous.position, state.current.position, t);
    object.quaternion.slerpQuaternions(state.previous.rotation, state.current.rotation, t);
    object.scale.lerpVectors(state.previous.scale, state.current.scale, t);
  }

  smearing() {
    return this.anyOn(LAYER_SMEAR);
  }

  anyOn(layer) {
    for (const instance of this.instances.values()) if (instance.object.visible && instance.object.layers.isEnabled(layer)) return true;
    return false;
  }

  renderNearest() {
    const clear = this.renderer.getClearColor(new THREE.Color());
    const alpha = this.renderer.getClearAlpha();
    this.camera.layers.set(0);
    this.scene.overrideMaterial = this.nearestMaterial;
    this.renderer.setRenderTarget(this.nearestTarget);
    this.renderer.setClearColor(0xffffff, 1);
    this.renderer.clear();
    this.renderer.render(this.scene, this.camera);
    this.renderer.setClearColor(clear, alpha);
    this.renderer.setRenderTarget(null);
    this.scene.overrideMaterial = null;
    for (const layer of [LAYER_SMEAR, LAYER_STANDING, LAYER_FRONT, LAYER_DOME]) this.camera.layers.enable(layer);
  }

  renderBehind() {
    this.camera.layers.set(0);
    this.camera.layers.enable(LAYER_FRONT);
    this.camera.layers.enable(LAYER_DOME);
    this.renderer.setRenderTarget(this.behindTarget);
    this.renderer.clear();
    this.renderer.render(this.scene, this.camera);
    this.renderer.setRenderTarget(null);
    for (const layer of [LAYER_SMEAR, LAYER_STANDING, LAYER_FRONT, LAYER_DOME]) this.camera.layers.enable(layer);
  }

  frame(now) {
    const flatOnly = !this.cameraState && this.layers2d.layers.length > 0;
    const flat = this.layers2d.draw(this.textures, flatOnly);
    if (flatOnly) {
      this.renderer.clear();
      this.layers2d.present(false);
      return;
    }
    const t = this.progress(now);
    const seconds = (now - this.started) / 1000;
    this.skyUniforms.skyTime.value = seconds;
    this.warpTime.value = seconds;
    this.skyUniforms.skyFaces.value = this.skyIds.map((id) => this.texture(id) || this.blank);
    const table = this.texture(this.lightTableId);
    this.lightUniforms.cauldronTable.value = table || this.blank;
    this.lightUniforms.cauldronHasTable.value = table ? 1 : 0;
    this.frameIndex.value = (this.frameIndex.value + 1) % 65536;
    for (const instance of this.instances.values()) this.place(instance.object, instance, t);
    if (this.cameraState) this.place(this.camera, this.cameraState, t);
    for (const light of this.lights.values()) {
      if (!light.isDirectionalLight) continue;
      const extent = this.shadowDistance || 60;
      const centre = this.camera.position;
      light.target.position.copy(centre);
      light.position.copy(centre).addScaledVector(light.userData.direction, -extent * 2);
      Object.assign(light.shadow.camera, { left: -extent, right: extent, top: extent, bottom: -extent, near: 0.1, far: extent * 4 });
      light.shadow.camera.updateProjectionMatrix();
    }
    this.dome.position.copy(this.camera.position);
    this.dome.scale.setScalar(this.camera.near * 4);
    this.renderer.clear();
    if (this.anyOn(LAYER_STANDING)) this.renderNearest();
    if (this.smearing()) this.renderBehind();
    this.bloom.enabled = this.bloom.strength > 0;
    this.composer.render();
    this.drawScreen();
    if (flat) this.layers2d.present(true);
  }
}

Scene3D.prototype.ops = {
  1: Scene3D.prototype.tick,
  2: function (reader) { this.readMesh(reader, false); },
  3: Scene3D.prototype.dropMesh,
  4: Scene3D.prototype.readTexture,
  5: Scene3D.prototype.dropTexture,
  6: Scene3D.prototype.readMaterial,
  7: Scene3D.prototype.dropMaterial,
  8: Scene3D.prototype.readInstance,
  9: Scene3D.prototype.readMove,
  10: Scene3D.prototype.removeInstance,
  11: Scene3D.prototype.readLight,
  12: Scene3D.prototype.removeLight,
  13: Scene3D.prototype.readCamera,
  14: Scene3D.prototype.readEnvironment,
  15: Scene3D.prototype.readEffects,
  16: function (reader) { this.readMesh(reader, true); },
  17: Scene3D.prototype.readPose,
  18: Scene3D.prototype.readLightStyles,
  19: Scene3D.prototype.readOverlay,
  20: Scene3D.prototype.readScreenTint,
  21: function (reader) { this.layers2d.readCanvas(reader, this.textures); },
  22: function (reader) { this.layers2d.readLayers(reader); }
};

const KEY_NAMES = {
  Space: "space", Enter: "return", Escape: "escape", Tab: "tab", Backspace: "backspace", Delete: "delete",
  ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
  ShiftLeft: "left_shift", ShiftRight: "right_shift", ControlLeft: "left_ctrl", ControlRight: "right_ctrl",
  AltLeft: "left_alt", AltRight: "right_alt"
};

function keyName(code) {
  if (KEY_NAMES[code]) return KEY_NAMES[code];
  if (/^Key[A-Z]$/.test(code)) return code.slice(3).toLowerCase();
  if (/^Digit[0-9]$/.test(code)) return code.slice(5);
  if (/^F[0-9]{1,2}$/.test(code)) return code.toLowerCase();
  return code;
}

function forwardInput(canvas, channel, scene) {
  const send = (message) => channel.push("event", message);
  window.addEventListener("keydown", (e) => { send({ type: "key", action: "down", key: keyName(e.code), repeat: e.repeat }); e.preventDefault(); });
  window.addEventListener("keyup", (e) => { send({ type: "key", action: "up", key: keyName(e.code), repeat: false }); e.preventDefault(); });
  canvas.addEventListener("mousemove", (e) => send({ type: "mouse_motion", x: e.offsetX, y: e.offsetY, dx: e.movementX, dy: e.movementY }));
  canvas.addEventListener("mousedown", (e) => { canvas.focus(); send({ type: "mouse_button", action: "down", button: e.button + 1, x: e.offsetX, y: e.offsetY }); });
  canvas.addEventListener("mouseup", (e) => send({ type: "mouse_button", action: "up", button: e.button + 1, x: e.offsetX, y: e.offsetY }));
  canvas.addEventListener("wheel", (e) => { send({ type: "mouse_wheel", dx: -e.deltaX / 100, dy: -e.deltaY / 100 }); e.preventDefault(); }, { passive: false });
  canvas.addEventListener("focus", () => send({ type: "focus", focused: true }));
  canvas.addEventListener("blur", () => send({ type: "focus", focused: false }));
  window.addEventListener("resize", () => { const size = scene.resize(); send({ type: "resized", width: size.width, height: size.height }); });
}

export function start(canvas, settings) {
  const scene = new Scene3D(canvas);
  const socket = new window.Phoenix.Socket(settings.socket, {});
  socket.connect();
  const channel = socket.channel(settings.topic + ":" + settings.scene, {});
  channel.on("changes", (payload) => scene.apply(payload));
  channel.join().receive("error", (reply) => console.error("cauldron3d:", reply.reason));
  forwardInput(canvas, channel, scene);
  const loop = (now) => { scene.frame(now); requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
  window.cauldron3d = scene;
  return scene;
}
