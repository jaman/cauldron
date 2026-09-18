(function (global) {
  "use strict";

  function escapeHtml(text) {
    return String(text).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function Sound(rate, channels) {
    this.rate = rate;
    this.channels = channels || 2;
    this.context = null;
    this.next = 0;
    this.lead = 0.05;
  }

  Sound.prototype.format = function (rate, channels) {
    if (this.context && this.rate !== rate) {
      this.context.close();
      this.context = null;
    }
    this.rate = rate;
    this.channels = channels;
  };

  Sound.prototype.unlock = function () {
    if (this.off) return;
    if (!this.context) {
      this.context = new (global.AudioContext || global.webkitAudioContext)({ sampleRate: this.rate });
    }
    if (this.context.state === "suspended") this.context.resume();
  };

  Sound.prototype.play = function (bytes) {
    if (!this.context || this.context.state !== "running") return;
    var samples = new Int16Array(bytes);
    var channels = this.channels;
    var frames = Math.floor(samples.length / channels);
    if (frames === 0) return;
    var buffer = this.context.createBuffer(channels, frames, this.rate);
    for (var channel = 0; channel < channels; channel++) {
      var data = buffer.getChannelData(channel);
      for (var i = 0; i < frames; i++) data[i] = samples[channels * i + channel] / 32768;
    }
    var source = this.context.createBufferSource();
    source.buffer = buffer;
    source.connect(this.context.destination);
    var now = this.context.currentTime;
    if (this.next < now + 0.005) this.next = now + this.lead;
    source.start(this.next);
    this.next += buffer.duration;
  };

  function Renderer(canvas, scale) {
    this.canvas = canvas;
    this.context = canvas.getContext("2d");
    this.context.imageSmoothingEnabled = false;
    this.scale = scale;
    this.ratio = 1;
    this.cssTile = scale;
    this.void = "#000000";
    this.sheet = null;
    this.image = null;
    this.map = null;
    this.frame = null;
    this.origin = [0, 0];
    this.pan = [0, 0];
    this.chunks = {};
    this.chunkKey = null;
    this.chunkTiles = 1;
    this.chunkUse = 0;
    this.animated = [];
  }

  Renderer.prototype.at = function (index) {
    var anim = this.sheet && this.sheet.anim && this.sheet.anim[index];
    if (!anim) return index;
    var now = (global.performance && global.performance.now) ? global.performance.now() : Date.now();
    return anim.indices[Math.floor(now * anim.fps / 1000) % anim.indices.length];
  };

  Renderer.prototype.setTile = function (cssTile) {
    this.cssTile = cssTile;
    this.scale = cssTile * this.ratio;
  };

  var CHUNK_PIXELS = 1024;
  var CHUNKS_KEPT = 16;

  Renderer.prototype.refreshChunks = function () {
    var key = this.scale + "/" + this.map.width + "x" + this.map.height;
    if (this.chunkKey === key && this.chunkImage === this.image && this.chunkMap === this.map) return;
    this.chunks = {};
    this.chunkKey = key;
    this.chunkImage = this.image;
    this.chunkMap = this.map;
    this.chunkTiles = Math.max(1, Math.ceil(CHUNK_PIXELS / this.scale));
    var anim = this.sheet.anim || {};
    var animated = [];
    for (var y = 0; y < this.map.height; y++) {
      var row = this.map.rows[y];
      for (var x = 0; x < this.map.width; x++) {
        if (row[x] && anim[row[x]]) animated.push([x, y, row[x]]);
      }
    }
    this.animated = animated;
  };

  Renderer.prototype.chunk = function (cx, cy) {
    var key = cx + "," + cy;
    var kept = this.chunks[key];
    if (kept) { kept.used = ++this.chunkUse; return kept.canvas; }
    var map = this.map;
    var scale = this.scale;
    var tiles = this.chunkTiles;
    var anim = this.sheet.anim || {};
    var tile = this.sheet.tile;
    var left = Math.round(cx * tiles * scale);
    var top = Math.round(cy * tiles * scale);
    var canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round((cx + 1) * tiles * scale) - left + 1);
    canvas.height = Math.max(1, Math.round((cy + 1) * tiles * scale) - top + 1);
    var context = canvas.getContext("2d");
    context.imageSmoothingEnabled = false;
    for (var y = 0; y < tiles && cy * tiles + y < map.height; y++) {
      var row = map.rows[cy * tiles + y];
      for (var x = 0; x < tiles && cx * tiles + x < map.width; x++) {
        var index = row[cx * tiles + x];
        if (!index || anim[index]) continue;
        var frame = this.sheet.frames[index];
        if (!frame) continue;
        context.drawImage(this.image, frame[0], frame[1], tile, tile, Math.round((cx * tiles + x) * scale) - left, Math.round((cy * tiles + y) * scale) - top, Math.ceil(scale), Math.ceil(scale));
      }
    }
    var keys = Object.keys(this.chunks);
    if (keys.length >= CHUNKS_KEPT) {
      var oldest = keys.reduce(function (a, b) { return this.chunks[a].used < this.chunks[b].used ? a : b; }.bind(this));
      delete this.chunks[oldest];
    }
    this.chunks[key] = { canvas: canvas, used: ++this.chunkUse };
    return canvas;
  };

  Renderer.prototype.drawStatic = function (context, lx, ly) {
    var tiles = this.chunkTiles;
    var span = tiles * this.scale;
    var columns = Math.ceil(this.map.width / tiles);
    var rows = Math.ceil(this.map.height / tiles);
    var firstX = Math.max(0, Math.floor(-lx / span));
    var lastX = Math.min(columns - 1, Math.floor((this.canvas.width - lx) / span));
    var firstY = Math.max(0, Math.floor(-ly / span));
    var lastY = Math.min(rows - 1, Math.floor((this.canvas.height - ly) / span));
    for (var cy = firstY; cy <= lastY; cy++) {
      for (var cx = firstX; cx <= lastX; cx++) {
        context.drawImage(this.chunk(cx, cy), Math.round(lx) + Math.round(cx * span), Math.round(ly) + Math.round(cy * span));
      }
    }
  };

  Renderer.prototype.setSheet = function (sheet) {
    var self = this;
    this.sheet = sheet;
    if (sheet.void) this.void = sheet.void;
    if (!this.scale) this.scale = sheet.tile;
    var image = new Image();
    image.onload = function () { self.image = image; };
    image.src = sheet.url;
  };

  Renderer.prototype.fit = function (cssTile, ratio) {
    var box = this.canvas.parentElement.getBoundingClientRect();
    var width = Math.max(1, Math.floor(box.width * ratio));
    var height = Math.max(1, Math.floor(box.height * ratio));
    if (this.canvas.width !== width) this.canvas.width = width;
    if (this.canvas.height !== height) this.canvas.height = height;
    this.canvas.style.width = box.width + "px";
    this.canvas.style.height = box.height + "px";
    this.ratio = ratio;
    this.cssTile = cssTile || this.cssTile || (this.sheet && this.sheet.tile) || 16;
    this.scale = this.cssTile * ratio;
    this.context.imageSmoothingEnabled = false;
  };

  Renderer.prototype.viewport = function () {
    return [this.canvas.width / this.scale, this.canvas.height / this.scale];
  };

  Renderer.prototype.sprite = function (index, x, y) {
    if (index <= 0 || !this.image) return;
    var frame = this.sheet.frames[this.at(index)];
    if (!frame) return;
    var tile = this.sheet.tile;
    this.context.drawImage(this.image, frame[0], frame[1], tile, tile, Math.round(x), Math.round(y), this.scale, this.scale);
  };

  Renderer.prototype.draw = function () {
    var context = this.context;
    context.fillStyle = this.void;
    context.fillRect(0, 0, this.canvas.width, this.canvas.height);
    if (!this.frame || !this.map || !this.sheet) return;

    var view = this.viewport();
    var focus = this.frame.focus;
    var originX = focus[0] + this.pan[0] - view[0] / 2;
    var originY = focus[1] + this.pan[1] - view[1] / 2;
    var map = this.map;
    this.origin = [originX, originY];

    if (this.image) {
      this.refreshChunks();
      var layerWidth = map.width * this.scale;
      var layerHeight = map.height * this.scale;
      var copies = map.wrap ? [[0, 0], [map.width, 0], [-map.width, 0], [0, map.height], [0, -map.height], [map.width, map.height], [-map.width, -map.height], [map.width, -map.height], [-map.width, map.height]] : [[0, 0]];
      for (var c = 0; c < copies.length; c++) {
        var lx = (copies[c][0] - originX) * this.scale;
        var ly = (copies[c][1] - originY) * this.scale;
        if (lx > this.canvas.width || ly > this.canvas.height || lx + layerWidth < 0 || ly + layerHeight < 0) continue;
        this.drawStatic(context, lx, ly);
        for (var a = 0; a < this.animated.length; a++) {
          var cell = this.animated[a];
          this.sprite(cell[2], lx + cell[0] * this.scale, ly + cell[1] * this.scale);
        }
      }
    }

    var movers = this.frame.movers;
    for (var i = 0; i < movers.length; i++) {
      var mover = movers[i];
      this.mover(mover[0], mover[1], mover[2], originX, originY, view, map);
    }

    var labels = this.frame.labels || [];
    for (var l = 0; l < labels.length; l++) {
      var label = labels[l];
      this.label(label[0], label[1], label[2], label[3], label[4], originX, originY, view, map);
    }
  };

  Renderer.prototype.label = function (text, x, y, colour, scale, originX, originY, view, map) {
    var offsets = map.wrap ? [[0, 0], [map.width, 0], [-map.width, 0], [0, map.height], [0, -map.height]] : [[0, 0]];
    var context = this.context;
    var size = Math.max(6, Math.round(this.scale * 0.45 * (scale || 1)));
    context.font = size + "px monospace";
    context.textBaseline = "top";
    context.fillStyle = colour || "#ffffff";
    for (var i = 0; i < offsets.length; i++) {
      var px = x + offsets[i][0] - originX;
      var py = y + offsets[i][1] - originY;
      if (px > -4 && py > -2 && px < view[0] + 1 && py < view[1] + 1) {
        context.fillText(text, Math.round(px * this.scale), Math.round(py * this.scale));
      }
    }
  };

  Renderer.prototype.mover = function (index, x, y, originX, originY, view, map) {
    var offsets = map.wrap ? [[0, 0], [map.width, 0], [-map.width, 0], [0, map.height], [0, -map.height], [map.width, map.height], [-map.width, -map.height], [map.width, -map.height], [-map.width, map.height]] : [[0, 0]];
    for (var i = 0; i < offsets.length; i++) {
      var px = x + offsets[i][0] - originX;
      var py = y + offsets[i][1] - originY;
      if (px > -1 && py > -1 && px < view[0] && py < view[1]) {
        this.sprite(index, px * this.scale, py * this.scale);
      }
    }
  };

  Renderer.prototype.pixelAt = function (clientX, clientY) {
    var rect = this.canvas.getBoundingClientRect();
    return [(clientX - rect.left) * (this.canvas.width / rect.width), (clientY - rect.top) * (this.canvas.height / rect.height)];
  };

  Renderer.prototype.worldAt = function (clientX, clientY) {
    if (!this.scale) return null;
    var pixel = this.pixelAt(clientX, clientY);
    return [this.origin[0] + pixel[0] / this.scale, this.origin[1] + pixel[1] / this.scale];
  };

  Renderer.prototype.panBy = function (dx, dy) {
    this.pan = [this.pan[0] + dx, this.pan[1] + dy];
  };

  Renderer.prototype.keepUnder = function (world, clientX, clientY) {
    if (!this.frame || !world) return;
    var pixel = this.pixelAt(clientX, clientY);
    var view = this.viewport();
    var focus = this.frame.focus;
    this.pan = [world[0] - pixel[0] / this.scale + view[0] / 2 - focus[0], world[1] - pixel[1] / this.scale + view[1] / 2 - focus[1]];
  };

  function Input(keymap, steering, onChange) {
    this.keymap = keymap;
    this.steering = steering;
    this.onChange = onChange;
    this.held = {};
    this.strength = {};
    this.aim = null;
    this.buttons = keymap.mouse || {};
  }

  Input.prototype.press = function (code) {
    var action = this.keymap[code];
    if (!action) return false;
    if (this.steering.indexOf(action) >= 0) this.aim = null;
    if (!this.held[action]) {
      this.held[action] = true;
      this.onChange();
    }
    return true;
  };

  Input.prototype.release = function (code) {
    var action = this.keymap[code];
    if (!action) return false;
    if (this.held[action]) {
      delete this.held[action];
      this.onChange();
    }
    return true;
  };

  Input.prototype.button = function (which, down) {
    var action = this.buttons[which];
    if (!action) return;
    if (down) this.held[action] = true; else delete this.held[action];
    this.onChange();
  };

  Input.prototype.hold = function (action, down, strength) {
    if (!action) return;
    if (down && !this.held[action]) {
      this.held[action] = true;
      if (strength !== undefined) this.strength[action] = strength;
      this.onChange();
    } else if (!down && this.held[action]) {
      delete this.held[action];
      delete this.strength[action];
      this.onChange();
    } else if (down && strength !== undefined && this.strength[action] !== strength) {
      this.strength[action] = strength;
    }
  };

  Input.prototype.state = function () {
    var state = { held: Object.keys(this.held), aim: this.aim };
    if (Object.keys(this.strength).length) state.strength = this.strength;
    return state;
  };

  function capture(element, pointerId) {
    try { element.setPointerCapture(pointerId); } catch (error) {}
  }

  function Touch(input, renderer, zones, onAim, onDown) {
    this.input = input;
    this.renderer = renderer;
    this.onAim = onAim;
    this.onDown = onDown;
    this.pointers = {};
    this.buttons = [];
    this.stick = null;
    this.listeners = [];
    var self = this;
    zones.forEach(function (zone) {
      if (zone.stick) self.addStick(zone);
      else if (zone.action && zone.element) self.addButton(zone);
    });
  }

  Touch.prototype.listen = function (element, type, handler) {
    element.addEventListener(type, handler, { passive: false });
    this.listeners.push([element, type, handler]);
  };

  Touch.prototype.addButton = function (zone) {
    var self = this;
    this.buttons.push(zone);
    zone.element.style.touchAction = "none";
    this.listen(zone.element, "pointerdown", function (event) {
      event.preventDefault();
      self.onDown();
      capture(zone.element, event.pointerId);
      self.pointers[event.pointerId] = { button: zone };
      zone.element.classList.add("held");
      self.input.hold(zone.action, true);
    });
    this.listen(zone.element, "pointermove", function (event) {
      var pointer = self.pointers[event.pointerId];
      if (!pointer || !pointer.button) return;
      var over = self.buttonAt(event.clientX, event.clientY);
      if (over && over !== pointer.button) {
        pointer.button.element.classList.remove("held");
        self.input.hold(pointer.button.action, false);
        pointer.button = over;
        over.element.classList.add("held");
        self.input.hold(over.action, true);
      }
    });
    var release = function (event) {
      var pointer = self.pointers[event.pointerId];
      if (!pointer || !pointer.button) return;
      pointer.button.element.classList.remove("held");
      self.input.hold(pointer.button.action, false);
      delete self.pointers[event.pointerId];
    };
    this.listen(zone.element, "pointerup", release);
    this.listen(zone.element, "pointercancel", release);
  };

  Touch.prototype.buttonAt = function (x, y) {
    for (var i = 0; i < this.buttons.length; i++) {
      var rect = this.buttons[i].element.getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) return this.buttons[i];
    }
    return null;
  };

  Touch.prototype.addStick = function (zone) {
    var self = this;
    var element = zone.stick;
    var distance = zone.distance || 8;
    var deadzone = zone.deadzone || 0.2;
    var push = zone.push || null;
    this.stick = zone;
    element.style.touchAction = "none";
    function centre() {
      var rect = element.getBoundingClientRect();
      return [rect.left + rect.width / 2, rect.top + rect.height / 2, Math.min(rect.width, rect.height) / 2];
    }
    function move(event) {
      var c = centre();
      var dx = (event.clientX - c[0]) / c[2];
      var dy = (event.clientY - c[1]) / c[2];
      var length = Math.sqrt(dx * dx + dy * dy);
      if (length > 1) { dx /= length; dy /= length; length = 1; }
      if (zone.knob) zone.knob.style.transform = "translate(" + Math.round(dx * c[2] * 0.6) + "px, " + Math.round(dy * c[2] * 0.6) + "px)";
      var focus = self.renderer.frame && self.renderer.frame.focus;
      if (length < deadzone || !focus) {
        self.input.aim = null;
      } else {
        self.input.aim = [focus[0] + (dx / length) * distance, focus[1] + (dy / length) * distance];
      }
      if (push) {
        var beyond = push.beyond || 0.5;
        var strength = length >= beyond ? Math.min(1, (length - beyond) / (1 - beyond) * (push.gain || 1.6)) : 0;
        self.input.hold(push.action, length >= beyond, Math.max(push.least || 0.25, strength));
      }
      self.onAim();
    }
    this.listen(element, "pointerdown", function (event) {
      event.preventDefault();
      self.onDown();
      capture(element, event.pointerId);
      self.pointers[event.pointerId] = { stick: true };
      element.classList.add("held");
      move(event);
    });
    this.listen(element, "pointermove", function (event) {
      var pointer = self.pointers[event.pointerId];
      if (pointer && pointer.stick) move(event);
    });
    var release = function (event) {
      var pointer = self.pointers[event.pointerId];
      if (!pointer || !pointer.stick) return;
      delete self.pointers[event.pointerId];
      element.classList.remove("held");
      if (zone.knob) zone.knob.style.transform = "";
      self.input.aim = null;
      if (push) self.input.hold(push.action, false);
      self.onAim();
    };
    this.listen(element, "pointerup", release);
    this.listen(element, "pointercancel", release);
  };

  Touch.prototype.stop = function () {
    this.listeners.forEach(function (entry) { entry[0].removeEventListener(entry[1], entry[2]); });
    this.listeners = [];
  };

  function mount(canvas, options) {
    var scale = options.scale || null;
    var renderer = new Renderer(canvas, scale);
    var sound = new Sound((options.audio && options.audio.rate) || options.rate || 44100, (options.audio && options.audio.channels) || 2);
    var hud = options.hud || null;
    var socket = new global.Phoenix.Socket(options.socketUrl || "/socket", { params: options.socketParams || {} });
    socket.connect();
    var joinParams = Object.assign({}, options.params || {});
    if (options.audio === false) joinParams.audio = false;
    else if (options.audio) joinParams.audio = { rate: options.audio.rate, channels: options.audio.channels };
    var channel = socket.channel(options.topic, joinParams);
    var input = new Input(options.keymap || {}, options.steering || [], function () { send(); });
    var sendTimer = null;
    var statsTimer = null;
    var aimTimer = null;
    var stopped = false;
    var counts = { frames: 0, draws: 0 };
    var stats = { frames: 0, draws: 0 };
    var ratio = options.fit ? (global.devicePixelRatio || 1) : 1;

    function send() {
      if (stopped) return;
      channel.push("input", input.state());
    }

    function aimed() {
      if (aimTimer) return;
      aimTimer = setTimeout(function () { aimTimer = null; send(); }, options.aimEvery || 33);
    }

    function aimAt(clientX, clientY) {
      if (touch) return;
      pointer = [clientX, clientY];
      input.aim = renderer.worldAt(clientX, clientY);
    }

    function reaim() {
      if (!pointer || !input.aim || watching || drag) return;
      var aim = renderer.worldAt(pointer[0], pointer[1]);
      if (!aim || (aim[0] === input.aim[0] && aim[1] === input.aim[1])) return;
      input.aim = aim;
      aimed();
    }

    function refit() {
      if (options.fit) renderer.fit(renderer.cssTile || options.scale, ratio);
    }

    var zoom = options.zoom || null;
    var baseTile = options.scale || null;
    var watching = options.watching === true || !!joinParams.spectate;
    var drag = null;
    var pointer = null;
    var subject = null;

    function zoomTo(cssTile, anchor) {
      if (!zoom) return;
      var map = renderer.map;
      var whole = map ? Math.min(canvas.width / map.width, canvas.height / map.height) / (renderer.ratio || 1) : 0;
      var least = Math.max(zoom.min || 2, whole);
      var most = zoom.max || 64;
      var tile = Math.max(least, Math.min(most, cssTile));
      var under = anchor && watching ? renderer.worldAt(anchor[0], anchor[1]) : null;
      renderer.setTile(tile);
      if (under) renderer.keepUnder(under, anchor[0], anchor[1]);
      if (options.onZoom) options.onZoom(tile);
    }

    function zoomBy(factor, anchor) {
      zoomTo((renderer.cssTile || baseTile || 16) * factor, anchor);
    }

    function panByPixels(dx, dy) {
      if (!watching || !renderer.scale) return;
      renderer.panBy(dx / renderer.scale, dy / renderer.scale);
    }

    function recentre() {
      renderer.pan = [0, 0];
    }

    channel.on("sheet", function (sheet) {
      renderer.setSheet(sheet);
      if (!baseTile) baseTile = sheet.tile;
      if (!renderer.cssTile) renderer.cssTile = baseTile;
      refit();
    });
    channel.on("audio", function (format) {
      if (format.off) { sound.off = true; if (sound.context) { sound.context.close(); sound.context = null; } return; }
      sound.off = false;
      sound.format(format.rate, format.channels);
    });
    channel.on("map", function (map) { renderer.map = map; });
    channel.on("frame", function (frame) {
      if (frame.subject !== undefined && frame.subject !== subject) {
        subject = frame.subject;
        renderer.pan = [0, 0];
      }
      renderer.frame = frame;
      counts.frames += 1;
      if (hud) hud.innerHTML = frame.hud.map(function (row, i) {
        var tag = frame.tags && frame.tags[i];
        return "<div" + (tag ? ' class="hud-' + escapeHtml(tag) + '"' : "") + ">" + row.map(function (run) {
          return run[1] ? '<span style="color:' + run[1] + '">' + escapeHtml(run[0]) + "</span>" : escapeHtml(run[0]);
        }).join(" ") + "</div>";
      }).join("");
      if (frame.over && options.onOver) {
        stopped = true;
        options.onOver(frame.over);
      }
    });
    channel.on("pcm", function (payload) { sound.play(payload instanceof ArrayBuffer ? payload : payload.buffer); });

    channel.join()
      .receive("ok", function () { if (options.onJoin) options.onJoin(); })
      .receive("error", function (reply) { if (options.onError) options.onError(reply.reason || "refused"); });

    function onKeyDown(event) {
      sound.unlock();
      if (event.repeat) return;
      if (zoom && zoom.keys !== false) {
        if (event.code === "Equal" || event.code === "NumpadAdd") { zoomBy(1.25); event.preventDefault(); return; }
        if (event.code === "Minus" || event.code === "NumpadSubtract") { zoomBy(0.8); event.preventDefault(); return; }
        if (event.code === "Digit0" || event.code === "Numpad0") { zoomTo(baseTile || 16); recentre(); event.preventDefault(); return; }
      }
      if (watching) {
        var step = Math.max(canvas.width, canvas.height) / 8;
        if (event.code === "ArrowLeft") { panByPixels(-step, 0); event.preventDefault(); return; }
        if (event.code === "ArrowRight") { panByPixels(step, 0); event.preventDefault(); return; }
        if (event.code === "ArrowUp") { panByPixels(0, -step); event.preventDefault(); return; }
        if (event.code === "ArrowDown") { panByPixels(0, step); event.preventDefault(); return; }
      }
      if (options.pause && event.code === options.pause) { channel.push("pause", {}); event.preventDefault(); return; }
      if (input.press(event.code)) event.preventDefault();
    }
    function onWheel(event) {
      if (!zoom || zoom.wheel === false) return;
      event.preventDefault();
      zoomBy(Math.pow(1.1, -event.deltaY / 100), [event.clientX, event.clientY]);
    }
    var pinch = {};
    function pinchPoints() {
      return Object.keys(pinch).filter(function (key) { return key !== "start"; }).map(function (key) { return pinch[key]; });
    }
    function pinchDistance() {
      var points = pinchPoints();
      if (points.length < 2) return 0;
      var dx = points[0][0] - points[1][0];
      var dy = points[0][1] - points[1][1];
      return Math.sqrt(dx * dx + dy * dy);
    }
    function pinchCentre() {
      var points = pinchPoints();
      if (points.length < 2) return null;
      return [(points[0][0] + points[1][0]) / 2, (points[0][1] + points[1][1]) / 2];
    }
    function onPinchDown(event) {
      if (event.pointerType !== "touch") return;
      pinch[event.pointerId] = [event.clientX, event.clientY];
      var ids = pinchPoints();
      if (ids.length === 2 && zoom && zoom.pinch !== false) pinch.start = { distance: pinchDistance(), tile: renderer.cssTile || baseTile || 16 };
      if (ids.length === 1 && watching) drag = { x: event.clientX, y: event.clientY, touch: true };
    }
    function onPinchMove(event) {
      if (!pinch[event.pointerId]) return;
      pinch[event.pointerId] = [event.clientX, event.clientY];
      if (pinch.start) {
        var distance = pinchDistance();
        if (distance > 0 && pinch.start.distance > 0) zoomTo(pinch.start.tile * distance / pinch.start.distance, pinchCentre());
        return;
      }
      if (drag && drag.touch) {
        var ratio = renderer.canvas.width / renderer.canvas.getBoundingClientRect().width;
        panByPixels((drag.x - event.clientX) * ratio, (drag.y - event.clientY) * ratio);
        drag = { x: event.clientX, y: event.clientY, touch: true };
      }
    }
    function onPinchUp(event) {
      delete pinch[event.pointerId];
      delete pinch.start;
      if (drag && drag.touch) drag = null;
    }
    function onKeyUp(event) {
      if (input.release(event.code)) event.preventDefault();
    }
    function onMouseMove(event) {
      if (drag && !drag.touch) {
        var ratio = renderer.canvas.width / renderer.canvas.getBoundingClientRect().width;
        panByPixels((drag.x - event.clientX) * ratio, (drag.y - event.clientY) * ratio);
        drag = { x: event.clientX, y: event.clientY };
        return;
      }
      aimAt(event.clientX, event.clientY);
      aimed();
    }
    function onCanvasPointerDown(event) {
      sound.unlock();
      if (event.pointerType === "touch") event.preventDefault();
    }
    function onVisibility() {
      if (global.document.visibilityState === "hidden") onBlur();
    }
    function onMouseDown(event) {
      sound.unlock();
      if (watching && event.button === 0) {
        drag = { x: event.clientX, y: event.clientY };
        event.preventDefault();
        return;
      }
      aimAt(event.clientX, event.clientY);
      input.button(event.button, true);
      event.preventDefault();
    }
    function onMouseUp(event) {
      if (drag && !drag.touch) { drag = null; event.preventDefault(); return; }
      input.button(event.button, false);
      event.preventDefault();
    }
    function onBlur() {
      input.held = {};
      drag = null;
      send();
    }
    function onDragEnd() {
      if (drag && !drag.touch) drag = null;
    }

    global.addEventListener("keydown", onKeyDown);
    global.addEventListener("keyup", onKeyUp);
    global.addEventListener("blur", onBlur);
    global.addEventListener("mouseup", onDragEnd);
    global.document.addEventListener("visibilitychange", onVisibility);
    canvas.addEventListener("mousemove", onMouseMove);
    canvas.addEventListener("mousedown", onMouseDown);
    canvas.addEventListener("mouseup", onMouseUp);
    canvas.addEventListener("pointerdown", onCanvasPointerDown);
    canvas.addEventListener("wheel", onWheel, { passive: false });
    canvas.addEventListener("pointerdown", onPinchDown);
    canvas.addEventListener("pointermove", onPinchMove);
    canvas.addEventListener("pointerup", onPinchUp);
    canvas.addEventListener("pointercancel", onPinchUp);
    canvas.addEventListener("contextmenu", function (event) { event.preventDefault(); });

    var touch = options.touch ? new Touch(input, renderer, options.touch.zones || [], aimed, function () { sound.unlock(); }) : null;
    var observer = null;
    if (options.fit && global.ResizeObserver) {
      observer = new global.ResizeObserver(function () { refit(); });
      observer.observe(canvas.parentElement);
      refit();
    }

    sendTimer = setInterval(send, options.inputEvery || 100);
    statsTimer = setInterval(function () {
      stats = { frames: counts.frames, draws: counts.draws };
      counts = { frames: 0, draws: 0 };
      if (options.onStats) options.onStats(stats);
    }, 1000);

    var running = true;
    function loop() {
      if (!running) return;
      renderer.draw();
      counts.draws += 1;
      reaim();
      global.requestAnimationFrame(loop);
    }
    global.requestAnimationFrame(loop);

    return {
      levels: function (sfx, music) { channel.push("levels", { sfx: sfx, music: music }); },
      music: function (on) { channel.push("music", { on: !!on }); },
      stats: function () { return stats; },
      zoom: function (cssTile) { zoomTo(cssTile); },
      zoomBy: function (factor) { zoomBy(factor); },
      panBy: function (dx, dy) { if (watching) renderer.panBy(dx, dy); },
      recentre: recentre,
      unlockSound: function () { sound.unlock(); },
      stop: function () {
        running = false;
        stopped = true;
        clearInterval(sendTimer);
        clearInterval(statsTimer);
        if (aimTimer) clearTimeout(aimTimer);
        if (touch) touch.stop();
        if (observer) observer.disconnect();
        global.removeEventListener("keydown", onKeyDown);
        global.removeEventListener("keyup", onKeyUp);
        global.removeEventListener("blur", onBlur);
        global.removeEventListener("mouseup", onDragEnd);
        global.document.removeEventListener("visibilitychange", onVisibility);
        channel.leave();
        socket.disconnect();
      }
    };
  }

  global.Cauldron = { mount: mount };
})(window);
