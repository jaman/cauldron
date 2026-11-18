// The player is a real element: a browser may refuse to start sound that no click asked
// for, and then the controls are there to press.
window.addEventListener("phx:sfx", (event) => {
  const player = document.getElementById("sfx-player")
  if (!player) return

  player.src = "data:audio/wav;base64," + event.detail.wav
  player.play().catch(() => {})
})
