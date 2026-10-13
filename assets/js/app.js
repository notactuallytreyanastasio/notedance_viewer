// DaveDance — classroom music viewer.
//
// Three pages, one script:
//   home   (Dave's laptop): import a song, open the TV, copy the kids' link
//   master (the TV):        full score, xylophone synth, transport controls
//   kid    (each iPad):     one part, big, following the line
//
// The TV and the iPads share a clock (clock.js) over a Phoenix channel.

import { Socket } from "phoenix"
import { initFlash } from "./flash"
import { initHome } from "./home"
import { initKid } from "./kid"
import { initMaster } from "./master"

initFlash()

const pageEl = document.getElementById("page")

if (pageEl) {
  const kind = pageEl.dataset.page

  if (kind === "home") initHome()

  if (kind === "kid" || kind === "master") {
    const socket = new Socket("/socket")
    socket.connect()
    const channel = socket.channel(`score:${pageEl.dataset.scoreId}`, { role: kind })

    if (kind === "kid") initKid(pageEl, channel)
    if (kind === "master") initMaster(pageEl, channel)

    channel.join().receive("error", (e) => console.error("channel join failed", e))
  }
}
