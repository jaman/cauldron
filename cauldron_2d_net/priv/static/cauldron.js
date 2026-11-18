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
    this.frame = null;
    this.drawing = { world: "server", screen: "server" };
    this.picture = null;
    this.overlay = null;
    this.atlas = null;
    this.reader = null;
    this.view = null;
    this.pending = 0;
    this.waiting = [];
    this.scratch = global.document.createElement("canvas");
    this.screenCanvas = global.document.createElement("canvas");
    this.drawnAt = 0;
  }

  Renderer.prototype.serverDrawn = function () {
    return this.drawing.world === "server";
  };

  Renderer.prototype.now = function () {
    return global.performance && global.performance.now ? global.performance.now() : Date.now();
  };

  Renderer.prototype.setTile = function (cssTile) {
    this.cssTile = cssTile;
    this.scale = cssTile * this.ratio;
  };

  function pixels(image) {
    var canvas = global.document.createElement("canvas");
    canvas.width = image.width;
    canvas.height = image.height;
    var context = canvas.getContext("2d");
    context.drawImage(image, 0, 0);
    return context.getImageData(0, 0, image.width, image.height).data;
  }

  Renderer.prototype.held = function (done) {
    var self = this;
    this.pending += 1;
    return function () {
      done.apply(null, arguments);
      self.pending -= 1;
      if (self.pending === 0) { var waiting = self.waiting; self.waiting = []; waiting.forEach(function (fn) { fn(); }); }
    };
  };

  Renderer.prototype.whenReady = function (fn) {
    if (this.pending === 0) fn(); else this.waiting.push(fn);
  };

  Renderer.prototype.setSheet = function (sheet) {
    var self = this;
    this.sheet = sheet;
    if (sheet.void) this.void = sheet.void;
    if (!this.scale) this.scale = sheet.tile;
    if (!global.CauldronDraw) return;
    var image = new Image();
    image.onload = this.held(function () {
      self.atlas = global.CauldronDraw.atlas(sheet, pixels(image), image.width, image.height);
      self.reader = global.CauldronDraw.reader(self.atlas);
    });
    image.src = sheet.url;
  };

  Renderer.prototype.addTinted = function (tinted) {
    var self = this;
    var image = new Image();
    image.onload = this.held(function () {
      self.whenAtlas(function () { self.atlas.addTinted(tinted.art, tinted.tint, tinted.index, pixels(image), image.width, image.height); });
    });
    image.src = "data:image/png;base64," + tinted.png;
  };

  Renderer.prototype.addTintedCell = function (cell) {
    var self = this;
    var image = new Image();
    image.onload = this.held(function () {
      self.whenAtlas(function () { self.atlas.addTintedCell(cell.base, cell.overlays, cell.tint, cell.index, pixels(image), image.width, image.height); });
    });
    image.src = "data:image/png;base64," + cell.png;
  };

  Renderer.prototype.whenAtlas = function (fn) {
    var self = this;
    if (this.atlas) fn(); else this.waiting.push(function () { self.whenAtlas(fn); });
  };

  Renderer.prototype.setScene = function (payload) {
    var self = this;
    this.whenReady(function () {
      if (!self.reader) return;
      self.view = self.reader.read(payload);
      self.screenDrawn = null;
    });
  };

  Renderer.prototype.setPicture = function (buffer) {
    this.nextPicture = buffer;
    if (!this.decoding) this.decodeNext();
  };

  Renderer.prototype.decodeNext = function () {
    var self = this;
    var buffer = this.nextPicture;
    if (!buffer) { this.decoding = false; return; }
    this.nextPicture = null;
    this.decoding = true;
    global.createImageBitmap(new Blob([buffer], { type: "image/png" })).then(function (bitmap) {
      if (self.picture && self.picture.close) self.picture.close();
      self.picture = bitmap;
      self.screenDrawn = null;
      self.decodeNext();
    }, function () { self.decodeNext(); });
  };

  Renderer.prototype.setOverlay = function (buffer) {
    var self = this;
    if (!buffer || buffer.byteLength === 0) { this.overlay = null; return; }
    global.createImageBitmap(new Blob([buffer], { type: "image/png" })).then(function (bitmap) {
      if (self.overlay && self.overlay.close) self.overlay.close();
      self.overlay = bitmap;
    });
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

  Renderer.prototype.pane = function () {
    var tile = (this.sheet ? this.sheet.tile : 16) * (this.ratio || 1);
    return [Math.max(1, Math.round(this.canvas.width / tile)), Math.max(1, Math.round(this.canvas.height / tile))];
  };

  Renderer.prototype.pixelAt = function (clientX, clientY) {
    var rect = this.canvas.getBoundingClientRect();
    return [(clientX - rect.left) * (this.canvas.width / rect.width), (clientY - rect.top) * (this.canvas.height / rect.height)];
  };

  Renderer.prototype.fraction = function (clientX, clientY) {
    var pixel = this.pixelAt(clientX, clientY);
    return [pixel[0] / this.canvas.width, pixel[1] / this.canvas.height];
  };

  Renderer.prototype.cover = function (image) {
    this.context.imageSmoothingEnabled = false;
    this.context.drawImage(image, 0, 0, this.canvas.width, this.canvas.height);
  };

  Renderer.prototype.put = function (target, picture) {
    if (target.width !== picture.width) target.width = picture.width;
    if (target.height !== picture.height) target.height = picture.height;
    target.getContext("2d").putImageData(new ImageData(picture.data, picture.width, picture.height), 0, 0);
    return target;
  };

  Renderer.prototype.draw = function () {
    var context = this.context;
    context.fillStyle = this.void;
    context.fillRect(0, 0, this.canvas.width, this.canvas.height);
    var D = global.CauldronDraw;
    if (this.serverDrawn()) {
      if (!this.picture) return;
      this.cover(this.picture);
      if (this.drawing.screen === "client" && this.view && D) this.drawClientScreen(this.picture.width, this.picture.height);
      return;
    }
    if (!this.view || !D) return;
    var now = this.now();
    if (!this.scened || now - this.drawnAt >= 33) {
      this.scened = this.put(this.scratch, D.picturePane(this.view, this.paneDrawn || this.pane(), now));
      this.drawnAt = now;
    }
    this.cover(this.scened);
    if (this.overlay) this.cover(this.overlay);
  };

  Renderer.prototype.drawClientScreen = function (width, height) {
    var D = global.CauldronDraw;
    if (!this.screenDrawn) {
      var items = D.screenItems(this.view);
      this.screenDrawn = items.length ? this.put(this.screenCanvas, D.screen.compose(this.view.atlas, items, width, height, this.now())) : "none";
    }
    if (this.screenDrawn !== "none") this.cover(this.screenDrawn);
  };

  function Input(channel) {
    this.channel = channel;
    this.held = {};
    this.aim = null;
  }

  Input.prototype.hold = function (action, down, strength) {
    if (!action) return;
    var before = this.held[action];
    if (down) {
      var value = strength === undefined ? null : strength;
      if (before === value) return;
      this.held[action] = value;
      this.channel.push("hold", { action: action, down: true, strength: value });
    } else if (before !== undefined) {
      delete this.held[action];
      this.channel.push("hold", { action: action, down: false });
    }
  };

  Input.prototype.letGo = function () {
    for (var action in this.held) this.channel.push("hold", { action: action, down: false });
    this.held = {};
  };

  Input.prototype.state = function () {
    return { held: Object.keys(this.held), aim: this.aim };
  };

  function capture(element, pointerId) {
    try { element.setPointerCapture(pointerId); } catch (error) {}
  }

  function screenAngle() {
    var orientation = global.screen && global.screen.orientation;
    if (orientation && typeof orientation.angle === "number") return orientation.angle;
    if (typeof global.orientation === "number") return (global.orientation + 360) % 360;
    return 0;
  }

  function Tilt(input, renderer, options, onAim) {
    this.input = input;
    this.renderer = renderer;
    this.onAim = onAim;
    this.range = options.range || 22;
    this.deadzone = options.deadzone || 0.12;
    this.distance = options.distance || 8;
    this.smoothing = options.smoothing || 0.4;
    this.invert = !!options.invert;
    this.rest = null;
    this.deflection = [0, 0];
    this.live = false;
    this.listening = false;
    this.refused = false;
    this.yielded = false;
    var self = this;
    this.onOrientation = function (event) { self.read(event); };
    this.onLevel = function () { self.level(); };
    this.onGesture = function () { self.arm(); };
    this.onVisible = function () { if (global.document.visibilityState === "visible") self.level(); };
    global.document.addEventListener("pointerup", this.onGesture);
    global.document.addEventListener("touchend", this.onGesture);
    global.document.addEventListener("click", this.onGesture);
    var Orientation = global.DeviceOrientationEvent;
    if (!Orientation) this.refused = true;
    else if (typeof Orientation.requestPermission !== "function") this.listen();
  }

  Tilt.prototype.arm = function () {
    if (this.listening || this.refused) return;
    var self = this;
    global.DeviceOrientationEvent.requestPermission().then(function (state) {
      if (state === "granted") self.listen(); else if (state === "denied") self.refused = true;
    }, function () {});
  };

  Tilt.prototype.listen = function () {
    if (this.listening) return;
    this.listening = true;
    global.document.removeEventListener("pointerup", this.onGesture);
    global.document.removeEventListener("touchend", this.onGesture);
    global.document.removeEventListener("click", this.onGesture);
    global.addEventListener("deviceorientation", this.onOrientation);
    global.addEventListener("orientationchange", this.onLevel);
    if (global.screen && global.screen.orientation) global.screen.orientation.addEventListener("change", this.onLevel);
    global.document.addEventListener("visibilitychange", this.onVisible);
  };

  Tilt.prototype.level = function () {
    this.rest = null;
    this.deflection = [0, 0];
  };

  Tilt.prototype.pose = function (beta, gamma) {
    var b = beta * Math.PI / 180;
    var g = gamma * Math.PI / 180;
    var gx = Math.sin(g) * Math.cos(b);
    var gy = -Math.sin(b);
    var gz = -Math.cos(g) * Math.cos(b);
    var roll = Math.atan2(gx, Math.sqrt(gy * gy + gz * gz)) * 180 / Math.PI;
    var pitch = Math.atan2(-gy, -gz) * 180 / Math.PI;
    switch (screenAngle()) {
      case 90: return [pitch, roll];
      case 180: return [-roll, -pitch];
      case 270: return [-pitch, -roll];
      default: return [roll, pitch];
    }
  };

  function wrapDegrees(degrees) {
    return degrees - 360 * Math.round(degrees / 360);
  }

  Tilt.prototype.read = function (event) {
    if (typeof event.beta !== "number" || typeof event.gamma !== "number") return;
    var pose = this.pose(event.beta, event.gamma);
    if (!this.rest) this.rest = pose;
    var dx = wrapDegrees(pose[0] - this.rest[0]) / this.range;
    var dy = wrapDegrees(pose[1] - this.rest[1]) / this.range;
    if (this.invert) dy = -dy;
    var length = Math.sqrt(dx * dx + dy * dy);
    if (length > 1) { dx /= length; dy /= length; }
    this.deflection = [
      this.deflection[0] + (dx - this.deflection[0]) * this.smoothing,
      this.deflection[1] + (dy - this.deflection[1]) * this.smoothing
    ];
    this.live = true;
    if (!this.yielded) this.apply();
  };

  Tilt.prototype.apply = function () {
    var dx = this.deflection[0];
    var dy = this.deflection[1];
    var length = Math.sqrt(dx * dx + dy * dy);
    var focus = this.renderer.frame && this.renderer.frame.focus;
    var aim = length < this.deadzone || !focus ? null : [focus[0] + (dx / length) * this.distance, focus[1] + (dy / length) * this.distance];
    var before = this.input.aim;
    if (aim === before || (aim && before && aim[0] === before[0] && aim[1] === before[1])) return;
    this.input.aim = aim;
    this.onAim();
  };

  Tilt.prototype.yield = function (toStick) {
    this.yielded = toStick;
    if (!toStick && this.live) this.apply();
  };

  Tilt.prototype.stop = function () {
    global.document.removeEventListener("pointerup", this.onGesture);
    global.document.removeEventListener("touchend", this.onGesture);
    global.document.removeEventListener("click", this.onGesture);
    global.removeEventListener("deviceorientation", this.onOrientation);
    global.removeEventListener("orientationchange", this.onLevel);
    if (global.screen && global.screen.orientation) global.screen.orientation.removeEventListener("change", this.onLevel);
    global.document.removeEventListener("visibilitychange", this.onVisible);
    this.listening = false;
  };

  function Touch(input, renderer, zones, tilt, onAim, onDown) {
    this.input = input;
    this.renderer = renderer;
    this.tilt = tilt;
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
      var beyond = push ? push.beyond || 0.5 : 1;
      var tilting = self.tilt && self.tilt.live;
      var steers = tilting ? length >= beyond : length >= deadzone;
      if (tilting) self.tilt.yield(length >= beyond);
      if (steers && focus) {
        self.input.aim = [focus[0] + (dx / length) * distance, focus[1] + (dy / length) * distance];
      } else if (!tilting) {
        self.input.aim = null;
      }
      if (push) {
        var strength = length >= beyond ? Math.min(1, (length - beyond) / (1 - beyond) * (push.gain || 1.6)) : 0;
        self.input.hold(push.action, tilting || length >= beyond, Math.max(push.least || 0.25, strength));
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
      if (self.tilt) self.tilt.yield(false);
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
    var drawer = global.CauldronDrawer ? global.CauldronDrawer.mount(canvas) : null;
    var sound = new Sound((options.audio && options.audio.rate) || options.rate || 44100, (options.audio && options.audio.channels) || 2);
    var hud = options.hud || null;
    var socket = new global.Phoenix.Socket(options.socketUrl || "/socket", { params: options.socketParams || {} });
    socket.connect();
    var joinParams = Object.assign({}, options.params || {});
    if (options.audio === false) joinParams.audio = false;
    else if (options.audio) joinParams.audio = { rate: options.audio.rate, channels: options.audio.channels };
    var channel = socket.channel(options.topic, joinParams);
    var input = new Input(channel);
    var statsTimer = null;
    var aimTimer = null;
    var stopped = false;
    var counts = { frames: 0, draws: 0 };
    var stats = { frames: 0, draws: 0 };
    var ratio = options.fit ? (global.devicePixelRatio || 1) : 1;

    var sentAim = null;
    function send() {
      if (stopped) return;
      var aim = input.aim;
      if (aim === sentAim || (aim && sentAim && aim[0] === sentAim[0] && aim[1] === sentAim[1])) return;
      sentAim = aim;
      channel.push("aim", { at: aim });
    }

    var lastMove = 0;
    var down = {};
    function mouse(payload, clientX, clientY) {
      payload.at = renderer.fraction(clientX, clientY);
      channel.push("mouse", payload);
    }

    var lastHud = null;
    var joined = false;

    function sendPane() {
      if (!joined) return;
      var pane = drawer && drawer.pane ? drawer.pane() : renderer.pane();
      channel.push("pane", { columns: pane[0], rows: pane[1] });
    }

    function mods(event) {
      var list = [];
      if (event.ctrlKey) list.push("ctrl");
      if (event.shiftKey) list.push("shift");
      if (event.altKey) list.push("alt");
      if (event.metaKey) list.push("meta");
      return list;
    }

    function aimed() {
      if (aimTimer) return;
      aimTimer = setTimeout(function () { aimTimer = null; send(); }, options.aimEvery || 33);
    }

    function aimAt(clientX, clientY) {
      if (touch) return;
      pointer = [clientX, clientY];
      input.aim = null;
      sentAim = null;
      var now = Date.now();
      if (now - lastMove < (options.aimEvery || 33)) return;
      lastMove = now;
      mouse({ move: true }, clientX, clientY);
    }

    function refit() {
      if (options.fit) renderer.fit(renderer.cssTile || options.scale, ratio);
      sendPane();
    }

    var baseTile = options.scale || null;
    var watching = options.watching === true || !!joinParams.spectate;
    var drag = null;
    var pointer = null;

    function panByPixels(dx, dy) {
      if (!watching) return;
      channel.push("pan", { x: dx / canvas.width, y: dy / canvas.height });
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
    channel.on("drawing", function (drawing) {
      renderer.drawing = drawing;
      sendPane();
    });
    channel.on("picture", function (payload) { renderer.setPicture(payload instanceof ArrayBuffer ? payload : payload.buffer); });
    channel.on("go", function (go) { if (options.onGo) options.onGo(go.to, go); });
    channel.on("front", function (front) { stopped = true; if (options.onFront) options.onFront(front.screen); });
    channel.on("settings", function (settings) { if (options.onSettings) options.onSettings(settings); });
    channel.on("clipboard", function (clip) { if (global.navigator.clipboard) global.navigator.clipboard.writeText(clip.text); });
    channel.on("scene", function (payload) { renderer.setScene(payload); });
    channel.on("world", function (world) { renderer.view = null; renderer.picture = null; stopped = false; if (options.onWorld) options.onWorld(world.id); });
    channel.on("chat", function (message) { if (options.onChat) options.onChat(message); });
    channel.on("chat_history", function (history) { if (options.onChatHistory) options.onChatHistory(history.messages); });
    channel.on("talk", function () { if (options.onTalk) options.onTalk(); });
    channel.on("tinted", function (tinted) { renderer.addTinted(tinted); });
    channel.on("tinted_cell", function (cell) { renderer.addTintedCell(cell); });
    channel.on("overlay", function (payload) { renderer.setOverlay(payload instanceof ArrayBuffer ? payload : payload.buffer); });
    channel.on("status", function (frame) {
      renderer.frame = frame;
      counts.frames += 1;
      var hudKey = hud ? JSON.stringify([frame.hud, frame.tags]) : null;
      if (hud && hudKey !== lastHud) { lastHud = hudKey; hud.hidden = frame.hud.length === 0; hud.innerHTML = frame.hud.map(function (row, i) {
        var tag = frame.tags && frame.tags[i];
        return "<div" + (tag ? ' class="hud-' + escapeHtml(tag) + '"' : "") + ">" + row.map(function (run) {
          return run[1] ? '<span style="color:' + run[1] + '">' + escapeHtml(run[0]) + "</span>" : escapeHtml(run[0]);
        }).join(" ") + "</div>";
      }).join(""); }
      if (frame.over && options.onOver) {
        stopped = true;
        options.onOver(frame.over);
      }
    });
    channel.on("pcm", function (payload) { sound.play(payload instanceof ArrayBuffer ? payload : payload.buffer); });
    if (drawer && drawer.events) Object.keys(drawer.events).forEach(function (name) { channel.on(name, drawer.events[name]); });

    channel.join()
      .receive("ok", function () { joined = true; sendPane(); if (options.onJoin) options.onJoin(); })
      .receive("error", function (reply) { if (options.onError) options.onError(reply.reason || "refused"); });

    function typing(event) {
      var target = event.target;
      return target && (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable);
    }
    function onKeyDown(event) {
      if (typing(event)) return;
      sound.unlock();
      if (event.repeat) return;
      down[event.code || event.key] = { key: event.key, code: event.code };
      channel.push("key", { key: event.key, code: event.code, mods: mods(event), down: true });
      if (!event.metaKey && !event.ctrlKey) event.preventDefault();
      if (watching) {
        var step = Math.max(canvas.width, canvas.height) / 8;
        if (event.code === "ArrowLeft") { panByPixels(-step, 0); event.preventDefault(); return; }
        if (event.code === "ArrowRight") { panByPixels(step, 0); event.preventDefault(); return; }
        if (event.code === "ArrowUp") { panByPixels(0, -step); event.preventDefault(); return; }
        if (event.code === "ArrowDown") { panByPixels(0, step); event.preventDefault(); return; }
      }
    }
    function onWheel(event) {
      event.preventDefault();
      mouse({ wheel: event.deltaY < 0 ? "up" : "down" }, event.clientX, event.clientY);
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
    function onPinchDown(event) {
      if (event.pointerType !== "touch") return;
      pinch[event.pointerId] = [event.clientX, event.clientY];
      var ids = pinchPoints();
      if (ids.length === 2 && options.pinch !== false) pinch.start = { distance: pinchDistance() };
      if (ids.length === 1 && watching) drag = { x: event.clientX, y: event.clientY, touch: true };
    }
    function onPinchMove(event) {
      if (!pinch[event.pointerId]) return;
      pinch[event.pointerId] = [event.clientX, event.clientY];
      if (pinch.start) {
        var distance = pinchDistance();
        if (distance > 0 && pinch.start.distance > 0) {
          var grown = distance / pinch.start.distance;
          if (grown >= 1.25) { channel.push("mouse", { wheel: "up" }); pinch.start.distance = distance; }
          else if (grown <= 0.8) { channel.push("mouse", { wheel: "down" }); pinch.start.distance = distance; }
        }
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
      var held = down[event.code || event.key];
      if (typing(event) || !held) return;
      delete down[event.code || event.key];
      channel.push("key", { key: held.key, code: held.code, mods: mods(event), down: false });
      event.preventDefault();
    }
    function onMouseMove(event) {
      if (drag && !drag.touch) {
        var ratio = renderer.canvas.width / renderer.canvas.getBoundingClientRect().width;
        panByPixels((drag.x - event.clientX) * ratio, (drag.y - event.clientY) * ratio);
        drag = { x: event.clientX, y: event.clientY };
        return;
      }
      aimAt(event.clientX, event.clientY);
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
      mouse({ button: ["left", "middle", "right"][event.button] || "left", down: true }, event.clientX, event.clientY);
      event.preventDefault();
    }
    function onMouseUp(event) {
      if (drag && !drag.touch) { drag = null; event.preventDefault(); return; }
      mouse({ button: ["left", "middle", "right"][event.button] || "left", down: false }, event.clientX, event.clientY);
      event.preventDefault();
    }
    function onBlur() {
      for (var id in down) channel.push("key", { key: down[id].key, code: down[id].code, mods: [], down: false });
      down = {};
      input.letGo();
      drag = null;
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

    var tilt = options.touch && options.touch.tilt ? new Tilt(input, renderer, options.touch.tilt, aimed) : null;
    var touch = options.touch ? new Touch(input, renderer, options.touch.zones || [], tilt, aimed, function () { sound.unlock(); }) : null;
    var pad = global.Gamepad && global.Gamepad.available() ? global.Gamepad.watch(function (line) { channel.push("padline", { line: line }); }, options.pad) : null;

    var observer = null;
    if (options.fit && global.ResizeObserver) {
      observer = new global.ResizeObserver(function () { refit(); });
      observer.observe(canvas.parentElement);
      refit();
    }

    statsTimer = setInterval(function () {
      stats = { frames: counts.frames, draws: counts.draws };
      counts = { frames: 0, draws: 0 };
      if (options.onStats) options.onStats(stats);
    }, 1000);

    var running = true;
    function loop() {
      if (!running) return;
      if (!drawer) renderer.draw();
      counts.draws += 1;
      global.requestAnimationFrame(loop);
    }
    global.requestAnimationFrame(loop);

    return {
      levels: function (sfx, music) { channel.push("levels", { sfx: sfx, music: music }); },
      music: function (on) { channel.push("music", { on: !!on }); },
      stats: function () { return stats; },
      aim: function (point) { pointer = null; input.aim = point ? [point[0], point[1]] : null; send(); },
      hold: function (action, down, strength) { input.hold(action, !!down, down ? strength : undefined); },
      focus: function () { var focus = renderer.frame && renderer.frame.focus; return focus ? [focus[0], focus[1]] : null; },
      input: function () { return input.state(); },
      zoomIn: function () { channel.push("mouse", { wheel: "up" }); },
      zoomOut: function () { channel.push("mouse", { wheel: "down" }); },
      panBy: function (fx, fy) { if (watching) channel.push("pan", { x: fx, y: fy }); },
      recentre: function () { channel.push("recentre", {}); },
      unlockSound: function () { sound.unlock(); },
      say: function (text) { channel.push("say", { text: text }); },
      socket: function () { return socket; },
      stop: function () {
        running = false;
        stopped = true;
        if (drawer && drawer.stop) drawer.stop();
        clearInterval(statsTimer);
        if (aimTimer) clearTimeout(aimTimer);
        if (touch) touch.stop();
        if (tilt) tilt.stop();
        if (pad) pad.stop();
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
