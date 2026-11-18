import { draw } from "./cauldron3d.js";

/**
 * The browser side of `Cauldron3D.Net.Drawer` for the game pages (`cauldron.js`): the
 * scene is drawn on a canvas placed behind the page's own, which stays clear and keeps
 * taking the player's input, and the pane reported is the canvas's size in pixels.
 */
window.CauldronDrawer = {
  mount(canvas) {
    const view = document.createElement("canvas");
    const parent = canvas.parentElement;
    if (getComputedStyle(parent).position === "static") parent.style.position = "relative";
    view.style.cssText = "position:absolute;inset:0;width:100%;height:100%;display:block";
    canvas.style.position = "relative";
    canvas.style.background = "transparent";
    parent.insertBefore(view, canvas);
    const scene = draw(view);
    return {
      events: { changes: (payload) => scene.apply(payload instanceof ArrayBuffer ? payload : payload.buffer) },
      pane: () => { const size = scene.resize(); return [Math.max(1, Math.round(size.width)), Math.max(1, Math.round(size.height))]; },
      stop: () => scene.stop()
    };
  }
};
