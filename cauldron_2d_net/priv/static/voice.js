/**
 * Voice calls between players of a Cauldron game, on the game's own socket (`Cauldron.Net.Voice`).
 *
 * `CauldronVoice.start(socket)` joins the `"voice"` channel and answers a voice object. The page
 * Cauldron serves starts one as `window.cauldronVoice` when the game has voice on.
 *
 *   voice.call(name), voice.accept(name), voice.decline(name), voice.hangUp(name), voice.mute(bool)
 *     ask the server; each answers a promise.
 *   voice.state()
 *     `{ incoming, outgoing, talking, muted, routes, ready }`: who asks, whom you ask, whom you talk
 *     to, whether the microphone is off, and each call's route, one of `"connecting"`, `"local"`,
 *     `"direct"`, `"turn"`, `"server"` or `"failed"`.
 *   voice.on(listener)
 *     calls `listener(state, notice)` on every change and answers a function that stops it. A
 *     notice is `null` or `{ kind, name }`, kind being `"declined"`, `"unavailable"` or `"error"`.
 *     Every change is also sent to `window` as the `"cauldron-voice"` event, `detail` being
 *     `{ state, notice }`.
 *   voice.place(name, x, y, z), voice.place(name, null)
 *     where a player's voice comes from, or that it comes from nowhere in particular.
 *   voice.listen(x, y, z, forwardX, forwardY, forwardZ, upX, upY, upZ)
 *     where the listener is and which way they face.
 *   voice.volume(level), voice.supported, voice.stop()
 *
 * Calls go directly between browsers. When no direct route connects within the server's wait, or
 * the connection fails, and the server relays, the microphone is encoded as Opus and sent over the
 * channel; it switches back when a direct route connects.
 */
(function (global) {
  "use strict";

  var TAP = "class CauldronVoiceTap extends AudioWorkletProcessor { process(inputs) { var channel = inputs[0] && inputs[0][0]; if (channel) this.port.postMessage(channel.slice(0)); return true; } } registerProcessor('cauldron-voice-tap', CauldronVoiceTap);";
  var encoder = new TextEncoder();
  var decoder = new TextDecoder();

  function supported() {
    return {
      direct: typeof global.RTCPeerConnection === "function",
      relay: typeof global.AudioEncoder === "function" && typeof global.AudioDecoder === "function" && typeof global.AudioWorkletNode === "function"
    };
  }

  function Voice(socket) {
    var self = this;
    this.supported = supported();
    this.ice = [];
    this.relay = false;
    this.wait = 5000;
    this.calls = { incoming: [], outgoing: [], talking: [], muted: false };
    this.ready = false;
    this.peers = {};
    this.placed = {};
    this.listeners = [];
    this.audio = null;
    this.master = null;
    this.microphone = null;
    this.sending = null;
    this.level = 1;
    this.channel = socket.channel("voice", {});
    this.channel.on("state", function (state) { self.calls = state; self.emit(null); });
    this.channel.on("connect", function (payload) { self.connect(payload.with, payload.offer); });
    this.channel.on("ended", function (payload) { self.drop(payload.with); });
    this.channel.on("declined", function (payload) { self.emit({ kind: "declined", name: payload.by }); });
    this.channel.on("unavailable", function (payload) { self.emit({ kind: "unavailable", name: payload.name }); });
    this.channel.on("mute", function (payload) { self.applyMute(payload.muted); });
    this.channel.on("signal", function (payload) { var peer = self.peers[payload.from]; if (peer) peer.signal(payload.data); });
    this.channel.on("audio", function (payload) { self.heard(payload); });
    this.channel.join()
      .receive("ok", function (reply) {
        self.ice = reply.ice || [];
        self.relay = !!reply.relay;
        self.wait = reply.wait || 5000;
        self.calls = reply.state || self.calls;
        self.ready = true;
        self.emit(null);
      })
      .receive("error", function (reply) { self.emit({ kind: "error", name: (reply && reply.reason) || "voice is off" }); });
    this.wake = function () { if (self.audio && self.audio.state !== "running") self.audio.resume(); };
    ["pointerdown", "keydown", "touchend"].forEach(function (kind) { global.addEventListener(kind, self.wake, true); });
  }

  Voice.prototype.ask = function (event, payload) {
    var channel = this.channel;
    this.wake();
    return new Promise(function (resolve, reject) {
      channel.push(event, payload)
        .receive("ok", function () { resolve(); })
        .receive("error", function (reply) { reject(new Error((reply && reply.reason) || event)); })
        .receive("timeout", function () { reject(new Error("timeout")); });
    });
  };

  Voice.prototype.call = function (name) { this.context(); return this.ask("call", { to: name }); };
  Voice.prototype.accept = function (name) { this.context(); return this.ask("accept", { from: name }); };
  Voice.prototype.decline = function (name) { return this.ask("decline", { from: name }); };
  Voice.prototype.hangUp = function (name) { return this.ask("hang_up", { with: name }); };
  Voice.prototype.mute = function (muted) { return this.ask("mute", { muted: !!muted }); };

  Voice.prototype.state = function () {
    var routes = {};
    var peers = this.peers;
    Object.keys(peers).forEach(function (name) { routes[name] = peers[name].route; });
    return {
      incoming: this.calls.incoming.slice(),
      outgoing: this.calls.outgoing.slice(),
      talking: this.calls.talking.slice(),
      muted: !!this.calls.muted,
      routes: routes,
      ready: this.ready
    };
  };

  Voice.prototype.on = function (listener) {
    var listeners = this.listeners;
    listeners.push(listener);
    return function () { var at = listeners.indexOf(listener); if (at >= 0) listeners.splice(at, 1); };
  };

  Voice.prototype.emit = function (notice) {
    var state = this.state();
    this.listeners.slice().forEach(function (listener) { listener(state, notice); });
    global.dispatchEvent(new CustomEvent("cauldron-voice", { detail: { state: state, notice: notice } }));
  };

  Voice.prototype.context = function () {
    if (!this.audio) {
      var Context = global.AudioContext || global.webkitAudioContext;
      try { this.audio = new Context({ sampleRate: 48000 }); } catch (e) { this.audio = new Context(); }
      this.master = this.audio.createGain();
      this.master.gain.value = this.level;
      this.master.connect(this.audio.destination);
    }
    this.wake();
    return this.audio;
  };

  Voice.prototype.volume = function (level) {
    this.level = level;
    if (this.master) this.master.gain.value = level;
  };

  Voice.prototype.listen = function (x, y, z, fx, fy, fz, ux, uy, uz) {
    if (!this.audio) return;
    var listener = this.audio.listener;
    if (listener.positionX) {
      listener.positionX.value = x; listener.positionY.value = y; listener.positionZ.value = z;
      listener.forwardX.value = fx; listener.forwardY.value = fy; listener.forwardZ.value = fz;
      listener.upX.value = ux; listener.upY.value = uy; listener.upZ.value = uz;
    } else {
      listener.setPosition(x, y, z);
      listener.setOrientation(fx, fy, fz, ux, uy, uz);
    }
  };

  Voice.prototype.place = function (name, x, y, z) {
    if (x === null || x === undefined) delete this.placed[name];
    else this.placed[name] = [x, y, z];
    if (this.peers[name]) this.peers[name].at(this.placed[name] || null);
  };

  Voice.prototype.openMicrophone = function () {
    var self = this;
    if (!this.microphone) {
      if (!global.navigator.mediaDevices || !global.navigator.mediaDevices.getUserMedia) {
        this.microphone = Promise.resolve(null);
        this.emit({ kind: "error", name: "the microphone needs a secure (https) page" });
      } else {
        this.microphone = global.navigator.mediaDevices
          .getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } })
          .then(function (stream) {
            stream.getAudioTracks().forEach(function (track) { track.enabled = !self.calls.muted; });
            return stream;
          })
          .catch(function (error) {
            self.emit({ kind: "error", name: "microphone: " + error.message });
            return null;
          });
      }
    }
    return this.microphone;
  };

  Voice.prototype.closeMicrophone = function () {
    if (!this.microphone) return;
    this.microphone.then(function (stream) { if (stream) stream.getTracks().forEach(function (track) { track.stop(); }); });
    this.microphone = null;
  };

  Voice.prototype.applyMute = function (muted) {
    this.calls.muted = muted;
    if (this.microphone) {
      this.microphone.then(function (stream) {
        if (stream) stream.getAudioTracks().forEach(function (track) { track.enabled = !muted; });
      });
    }
  };

  Voice.prototype.signal = function (name, data) {
    this.channel.push("signal", { to: name, data: data });
  };

  Voice.prototype.connect = function (name, offer) {
    if (this.peers[name]) this.peers[name].close();
    this.peers[name] = new Peer(this, name, offer);
    this.peers[name].at(this.placed[name] || null);
    this.emit(null);
  };

  Voice.prototype.drop = function (name) {
    var peer = this.peers[name];
    if (peer) {
      peer.close();
      delete this.peers[name];
    }
    this.updateSending();
    if (Object.keys(this.peers).length === 0) this.closeMicrophone();
    this.emit(null);
  };

  Voice.prototype.updateSending = function () {
    var peers = this.peers;
    var relaying = Object.keys(peers).some(function (name) { return peers[name].relaying; });
    if (relaying && !this.sending) this.startSending();
    if (!relaying && this.sending) this.stopSending();
  };

  Voice.prototype.startSending = function () {
    var self = this;
    var audio = this.context();
    var sending = { encoder: null, nodes: [], frames: 0, buffer: null, filled: 0, stopped: false };
    this.sending = sending;
    var module = URL.createObjectURL(new Blob([TAP], { type: "application/javascript" }));
    Promise.all([this.openMicrophone(), audio.audioWorklet.addModule(module)]).then(function (results) {
      var stream = results[0];
      if (sending.stopped || !stream) return;
      var rate = audio.sampleRate;
      var size = Math.round(rate / 50);
      var config = { codec: "opus", sampleRate: rate, numberOfChannels: 1, bitrate: 32000 };
      return global.AudioEncoder.isConfigSupported(config).then(function (support) {
        if (sending.stopped) return;
        if (!support.supported) { self.emit({ kind: "error", name: "this browser cannot encode Opus at " + rate + " Hz" }); return; }
        sending.encoder = new global.AudioEncoder({
          output: function (chunk) { self.sendPacket(chunk); },
          error: function (error) { self.emit({ kind: "error", name: "encoder: " + error.message }); }
        });
        sending.encoder.configure(config);
        sending.buffer = new Float32Array(size);
        var source = audio.createMediaStreamSource(stream);
        var tap = new global.AudioWorkletNode(audio, "cauldron-voice-tap");
        var sink = audio.createGain();
        sink.gain.value = 0;
        source.connect(tap);
        tap.connect(sink);
        sink.connect(audio.destination);
        sending.nodes = [source, tap, sink];
        tap.port.onmessage = function (event) { self.collect(sending, event.data, rate); };
      });
    }).finally(function () { URL.revokeObjectURL(module); });
  };

  Voice.prototype.collect = function (sending, samples, rate) {
    var at = 0;
    while (at < samples.length) {
      var take = Math.min(samples.length - at, sending.buffer.length - sending.filled);
      sending.buffer.set(samples.subarray(at, at + take), sending.filled);
      sending.filled += take;
      at += take;
      if (sending.filled === sending.buffer.length) {
        if (!this.calls.muted && sending.encoder && sending.encoder.state === "configured") {
          sending.encoder.encode(new global.AudioData({
            format: "f32-planar",
            sampleRate: rate,
            numberOfFrames: sending.buffer.length,
            numberOfChannels: 1,
            timestamp: Math.round(sending.frames * 1e6 * sending.buffer.length / rate),
            data: sending.buffer.slice(0)
          }));
        }
        sending.frames += 1;
        sending.filled = 0;
      }
    }
  };

  Voice.prototype.stopSending = function () {
    var sending = this.sending;
    this.sending = null;
    if (!sending) return;
    sending.stopped = true;
    sending.nodes.forEach(function (node) { node.disconnect(); });
    if (sending.encoder && sending.encoder.state !== "closed") sending.encoder.close();
  };

  Voice.prototype.sendPacket = function (chunk) {
    var packet = new Uint8Array(chunk.byteLength);
    chunk.copyTo(packet);
    var peers = this.peers;
    var channel = this.channel;
    Object.keys(peers).forEach(function (name) {
      if (!peers[name].relaying) return;
      var label = encoder.encode(name);
      if (label.length > 255) return;
      var frame = new Uint8Array(1 + label.length + packet.length);
      frame[0] = label.length;
      frame.set(label, 1);
      frame.set(packet, 1 + label.length);
      channel.push("audio", frame.buffer);
    });
  };

  Voice.prototype.heard = function (payload) {
    var bytes = new Uint8Array(payload);
    var length = bytes[0];
    var name = decoder.decode(bytes.subarray(1, 1 + length));
    var peer = this.peers[name];
    if (!peer) return;
    if (peer.connection && peer.connection.connectionState === "connected") return;
    if (!peer.relaying) peer.fallBack();
    peer.decode(bytes.subarray(1 + length));
  };

  Voice.prototype.stop = function () {
    var self = this;
    Object.keys(this.peers).forEach(function (name) { self.peers[name].close(); });
    this.peers = {};
    this.stopSending();
    this.closeMicrophone();
    ["pointerdown", "keydown", "touchend"].forEach(function (kind) { global.removeEventListener(kind, self.wake, true); });
    this.channel.leave();
    if (this.audio) this.audio.close();
  };

  function Peer(voice, name, offer) {
    var self = this;
    var audio = voice.context();
    this.voice = voice;
    this.name = name;
    this.route = "connecting";
    this.relaying = false;
    this.closed = false;
    this.candidates = [];
    this.element = null;
    this.playback = null;
    this.next = 0;
    this.clock = 0;
    this.gain = audio.createGain();
    this.panner = audio.createPanner();
    this.panner.panningModel = "HRTF";
    this.panner.distanceModel = "inverse";
    this.panner.refDistance = 1;
    this.panner.maxDistance = 40;
    this.panner.rolloffFactor = 1;
    this.panner.connect(voice.master);
    this.gain.connect(voice.master);
    this.placed = false;
    this.connection = voice.supported.direct ? new global.RTCPeerConnection({ iceServers: voice.ice }) : null;
    this.timer = setTimeout(function () { self.fallBack(); }, voice.wait);
    if (!this.connection) { this.fallBack(); return; }
    var connection = this.connection;
    connection.onicecandidate = function (event) { if (event.candidate) voice.signal(name, { candidate: event.candidate.toJSON() }); };
    connection.ontrack = function (event) { self.hear(event.streams[0] || new MediaStream([event.track])); };
    connection.onconnectionstatechange = function () { self.changed(); };
    this.tracks = voice.openMicrophone().then(function (stream) {
      if (stream && !self.closed) stream.getAudioTracks().forEach(function (track) { connection.addTrack(track, stream); });
    });
    if (offer) {
      this.tracks
        .then(function () { return connection.createOffer({ offerToReceiveAudio: true }); })
        .then(function (description) { return connection.setLocalDescription(description); })
        .then(function () { voice.signal(name, { description: connection.localDescription.toJSON() }); })
        .catch(function (error) { voice.emit({ kind: "error", name: "offer: " + error.message }); });
    }
  }

  Peer.prototype.signal = function (data) {
    var self = this;
    var connection = this.connection;
    if (!connection || this.closed) return;
    if (data.description) {
      connection.setRemoteDescription(data.description)
        .then(function () {
          self.candidates.splice(0).forEach(function (candidate) { connection.addIceCandidate(candidate); });
          if (data.description.type !== "offer") return;
          return self.tracks
            .then(function () { return connection.createAnswer(); })
            .then(function (description) { return connection.setLocalDescription(description); })
            .then(function () { self.voice.signal(self.name, { description: connection.localDescription.toJSON() }); });
        })
        .catch(function (error) { self.voice.emit({ kind: "error", name: "answer: " + error.message }); });
    } else if (data.candidate) {
      if (connection.remoteDescription) connection.addIceCandidate(data.candidate);
      else this.candidates.push(data.candidate);
    }
  };

  Peer.prototype.changed = function () {
    var self = this;
    var state = this.connection.connectionState;
    if (state === "connected") {
      clearTimeout(this.timer);
      this.relaying = false;
      this.voice.updateSending();
      this.route = "direct";
      this.voice.emit(null);
      this.findRoute().then(function (route) { self.route = route; self.voice.emit(null); });
    } else if (state === "failed") {
      this.fallBack();
    } else if (state === "disconnected") {
      clearTimeout(this.timer);
      this.timer = setTimeout(function () { self.fallBack(); }, this.voice.wait);
    }
  };

  Peer.prototype.findRoute = function () {
    return this.connection.getStats().then(function (stats) {
      var pair = null;
      var candidates = {};
      stats.forEach(function (report) {
        if (report.type === "transport" && report.selectedCandidatePairId) pair = stats.get(report.selectedCandidatePairId);
        if (report.type === "candidate-pair" && report.nominated && report.state === "succeeded" && !pair) pair = report;
        if (report.type === "local-candidate" || report.type === "remote-candidate") candidates[report.id] = report;
      });
      if (!pair) return "direct";
      var local = candidates[pair.localCandidateId] || {};
      var remote = candidates[pair.remoteCandidateId] || {};
      if (local.candidateType === "relay" || remote.candidateType === "relay") return "turn";
      if (local.candidateType === "host" && remote.candidateType === "host") return "local";
      return "direct";
    }).catch(function () { return "direct"; });
  };

  Peer.prototype.fallBack = function () {
    if (this.closed || this.relaying) return;
    if (this.connection && this.connection.connectionState === "connected") return;
    clearTimeout(this.timer);
    if (this.voice.relay && this.voice.supported.relay) {
      this.relaying = true;
      this.route = "server";
      this.voice.updateSending();
    } else {
      this.route = "failed";
    }
    this.voice.emit(null);
  };

  Peer.prototype.hear = function (stream) {
    if (this.element) return;
    this.element = new Audio();
    this.element.muted = true;
    this.element.srcObject = stream;
    this.element.play().catch(function () {});
    this.voice.context().createMediaStreamSource(stream).connect(this.gain);
  };

  Peer.prototype.at = function (position) {
    if (position) {
      if (!this.placed) { this.gain.disconnect(); this.gain.connect(this.panner); this.placed = true; }
      var panner = this.panner;
      if (panner.positionX) { panner.positionX.value = position[0]; panner.positionY.value = position[1]; panner.positionZ.value = position[2]; }
      else panner.setPosition(position[0], position[1], position[2]);
    } else if (this.placed) {
      this.gain.disconnect();
      this.gain.connect(this.voice.master);
      this.placed = false;
    }
  };

  Peer.prototype.decode = function (packet) {
    var self = this;
    if (!this.voice.supported.relay) return;
    if (!this.playback) {
      this.playback = new global.AudioDecoder({
        output: function (data) { self.play(data); },
        error: function (error) { self.voice.emit({ kind: "error", name: "decoder: " + error.message }); }
      });
      this.playback.configure({ codec: "opus", sampleRate: 48000, numberOfChannels: 1 });
    }
    if (this.playback.state !== "configured") return;
    this.playback.decode(new global.EncodedAudioChunk({ type: "key", timestamp: this.clock, data: packet }));
    this.clock += 20000;
  };

  Peer.prototype.play = function (data) {
    var audio = this.voice.context();
    var frames = data.numberOfFrames;
    var samples = new Float32Array(frames);
    data.copyTo(samples, { planeIndex: 0, format: "f32-planar" });
    var buffer = audio.createBuffer(1, frames, data.sampleRate);
    data.close();
    buffer.copyToChannel(samples, 0);
    var source = audio.createBufferSource();
    source.buffer = buffer;
    source.connect(this.gain);
    var now = audio.currentTime;
    if (this.next < now + 0.02 || this.next > now + 0.5) this.next = now + 0.1;
    source.start(this.next);
    this.next += buffer.duration;
  };

  Peer.prototype.close = function () {
    this.closed = true;
    clearTimeout(this.timer);
    if (this.connection) this.connection.close();
    if (this.element) { this.element.srcObject = null; this.element = null; }
    if (this.playback && this.playback.state !== "closed") this.playback.close();
    this.gain.disconnect();
    this.panner.disconnect();
  };

  global.CauldronVoice = { start: function (socket) { return new Voice(socket); }, supported: supported };
})(window);
