(function (global) {
  "use strict";

  var checker = ["#282830", "#383842"];

  var EaselCanvas = {
    mounted: function () {
      var self = this;
      this.canvas = this.el.querySelector("canvas");
      this.context = this.canvas.getContext("2d");
      this.frame = JSON.parse(this.el.dataset.frame || "null");
      this.down = false;
      this.last = null;
      this.handleEvent("frame", function (frame) { self.frame = frame; self.draw(); });
      this.canvas.addEventListener("pointerdown", function (event) { self.down = true; self.canvas.setPointerCapture(event.pointerId); self.send(event, "start"); });
      this.canvas.addEventListener("pointermove", function (event) { if (self.down) self.send(event, "drag"); });
      var up = function (event) { if (!self.down) return; self.down = false; self.send(event, "end"); };
      this.canvas.addEventListener("pointerup", up);
      this.canvas.addEventListener("pointercancel", up);
      this.canvas.addEventListener("contextmenu", function (event) { event.preventDefault(); });
      this.onKey = function (event) {
        var tag = event.target && event.target.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || event.metaKey || event.ctrlKey || event.altKey) return;
        self.pushEvent("key", { key: event.key });
        if (event.key.indexOf("Arrow") === 0) event.preventDefault();
      };
      window.addEventListener("keydown", this.onKey);
      this.draw();
    },

    destroyed: function () {
      window.removeEventListener("keydown", this.onKey);
    },

    pixel: function (event) {
      var rect = this.canvas.getBoundingClientRect();
      var zoom = this.frame.zoom;
      var x = Math.floor((event.clientX - rect.left) * (this.canvas.width / rect.width) / zoom);
      var y = Math.floor((event.clientY - rect.top) * (this.canvas.height / rect.height) / zoom);
      return { x: x, y: y };
    },

    send: function (event, phase) {
      if (!this.frame) return;
      var pixel = this.pixel(event);
      if (phase === "drag" && this.last && this.last.x === pixel.x && this.last.y === pixel.y) return;
      this.last = phase === "end" ? null : pixel;
      this.pushEvent("paint", { x: pixel.x, y: pixel.y, phase: phase });
    },

    draw: function () {
      var frame = this.frame;
      if (!frame) return;
      var zoom = frame.zoom;
      this.canvas.width = frame.width * zoom;
      this.canvas.height = frame.height * zoom;
      var context = this.context;
      context.imageSmoothingEnabled = false;
      for (var y = 0; y < frame.height; y++) {
        for (var x = 0; x < frame.width; x++) {
          context.fillStyle = checker[(x + y) % 2];
          context.fillRect(x * zoom, y * zoom, zoom, zoom);
          var ghost = frame.ghost && frame.ghost[y][x];
          if (ghost) {
            context.globalAlpha = 0.35;
            context.fillStyle = ghost;
            context.fillRect(x * zoom, y * zoom, zoom, zoom);
            context.globalAlpha = 1;
          }
          var colour = frame.pixels[y][x];
          if (colour) {
            context.fillStyle = colour;
            context.fillRect(x * zoom, y * zoom, zoom, zoom);
          }
        }
      }
      if (zoom >= 8) {
        context.strokeStyle = "rgba(0,0,0,0.25)";
        context.lineWidth = 1;
        for (var gx = 0; gx <= frame.width; gx++) { context.beginPath(); context.moveTo(gx * zoom + 0.5, 0); context.lineTo(gx * zoom + 0.5, this.canvas.height); context.stroke(); }
        for (var gy = 0; gy <= frame.height; gy++) { context.beginPath(); context.moveTo(0, gy * zoom + 0.5); context.lineTo(this.canvas.width, gy * zoom + 0.5); context.stroke(); }
      }
    }
  };

  var csrf = document.querySelector("meta[name='csrf-token']");
  var liveSocket = new global.LiveView.LiveSocket("/live", global.Phoenix.Socket, {
    hooks: { EaselCanvas: EaselCanvas },
    params: { _csrf_token: csrf && csrf.getAttribute("content") }
  });
  liveSocket.connect();
  global.liveSocket = liveSocket;
})(window);
