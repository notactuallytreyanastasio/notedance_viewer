// The TV page: the whole score, the transport, the sound, and who is following.

import { Presence } from "phoenix"
import QRCode from "qrcode"
import { makeClock, onFrame, formatTime } from "./clock"
import { drawScore, noteTracker, mergedOnsets } from "./notation"
import { makeSynth } from "./synth"
import { makeTour } from "./tour"

export function initMaster(pageEl, channel) {
  const clock = makeClock(channel)
  const osmdEl = document.getElementById("osmd")
  const loadingEl = document.getElementById("sheet-loading")
  const positionEl = document.getElementById("position")
  const durationEl = document.getElementById("duration")
  const progressEl = document.getElementById("progress-bar")
  const measuresEl = document.getElementById("measures")
  const playBtn = document.getElementById("btn-play")
  const soundBtn = document.getElementById("btn-sound")
  const liveDot = document.getElementById("live-dot")
  const followingText = document.getElementById("following-text")

  const synth = makeSynth()
  let tracker = null
  let timeline = null
  let measures = []
  let durationMs = 0

  // the line steps note by note across all parts, so it needs both the
  // drawn score and the timeline before it can start walking
  const timelineLoaded = fetch(pageEl.dataset.timelineUrl).then((r) => r.json())

  // bigger on a big screen: a 1080p TV at the back of a music room gets 1.4
  const zoom = Math.min(1.5, Math.max(1.0, window.innerWidth / 1300))

  Promise.all([drawScore(osmdEl, pageEl.dataset.musicxmlUrl, zoom), timelineLoaded]).then(([osmd, tl]) => {
    loadingEl.classList.add("hidden")
    tracker = noteTracker(osmd, mergedOnsets(tl))
    tracker.seekTo(clock.positionMs())
  })

  timelineLoaded
    .then((tl) => {
      timeline = tl
      measures = tl.measures
      durationMs = measures.length * tl.measure_ms
      durationEl.textContent = formatTime(durationMs)
      for (const m of measures) {
        const btn = document.createElement("button")
        btn.type = "button"
        btn.textContent = m.i + 1
        btn.setAttribute("aria-label", `Start from measure ${m.i + 1}`)
        btn.addEventListener("click", () => {
          synth.unlock()
          channel.push("play", { position_ms: m.start_ms })
        })
        measuresEl.appendChild(btn)
      }
    })

  // ---- transport
  function togglePlay() {
    synth.unlock() // inside the gesture: Safari will not resume audio later
    if (clock.status === "playing") channel.push("pause", {})
    else channel.push("play", {})
  }
  playBtn.addEventListener("click", togglePlay)

  // keyboard, for a laptop driving the TV: space plays/pauses, ← starts
  // over, m mutes. Ignored while typing or while the tour has the keys.
  document.addEventListener("keydown", (e) => {
    if (e.target.closest("input, textarea, dialog") || document.querySelector(".driver-popover")) return
    if (e.key === " ") { e.preventDefault(); togglePlay() }
    if (e.key === "ArrowLeft") { e.preventDefault(); synth.unlock(); channel.push("play", { position_ms: 0 }) }
    if (e.key === "m") soundBtn.click()
  })
  document.getElementById("btn-pause").addEventListener("click", () => channel.push("pause", {}))
  document.getElementById("btn-restart").addEventListener("click", () => {
    synth.unlock()
    channel.push("play", { position_ms: 0 })
  })
  soundBtn.addEventListener("click", () => {
    synth.muted = !synth.muted
    soundBtn.setAttribute("aria-pressed", synth.muted ? "false" : "true")
    soundBtn.title = synth.muted ? "Sound off" : "Sound on"
    soundBtn.setAttribute("aria-label", soundBtn.title)
    if (synth.muted) synth.stop()
    else if (clock.status === "playing") synth.start(timeline, clock.positionMs())
  })

  // sound follows real transport events only; the 1s heartbeat is ignored
  clock.onState((s, { statusChanged, jumped }) => {
    liveDot.dataset.live = s.status
    playBtn.dataset.playing = s.status === "playing" ? "true" : "false"
    document.getElementById("play-label").textContent = s.status === "playing" ? "Pause" : "Play"
    if (s.status === "playing" && (statusChanged || jumped)) synth.start(timeline, clock.positionMs())
    if (s.status !== "playing") synth.stop()
  })

  // The server clock runs on forever; the TV is the one that knows where
  // the song ends, so it stops the room there and winds back to the start.
  let ended = false
  function stopAtEnd(pos) {
    if (!durationMs || clock.status !== "playing") { ended = false; return }
    if (pos < durationMs + 400 || ended) return
    ended = true
    channel.push("pause", {})
    channel.push("seek", { position_ms: 0 })
  }

  onFrame(clock, () => {
    const pos = clock.positionMs()
    stopAtEnd(pos)
    positionEl.textContent = formatTime(pos)
    if (durationMs) progressEl.style.width = `${Math.min(100, (pos / durationMs) * 100)}%`
    const m = measureAt(pos)
    if (tracker) tracker.seekTo(pos)
    measuresEl.querySelectorAll("button").forEach((b, i) => {
      const current = i === m
      if (current && b.dataset.current !== "true") {
        // a long song's strip scrolls sideways; keep the lit measure in view
        b.scrollIntoView({ block: "nearest", inline: "center", behavior: "smooth" })
      }
      b.dataset.current = current ? "true" : "false"
    })
  })

  function measureAt(pos) {
    let m = 0
    for (let i = 0; i < measures.length; i++) if (measures[i].start_ms <= pos) m = i
    return m
  }

  // ---- who is following
  let online = true
  document.addEventListener("dave:connection", (e) => {
    online = e.detail === "online"
    if (!online) followingText.textContent = "Reconnecting…"
    liveDot.dataset.live = online ? clock.status : ""
  })

  const presence = new Presence(channel)
  presence.onSync(() => {
    if (!online) return
    const parts = {}
    let kids = 0
    presence.list((_id, { metas }) => {
      const meta = metas[0]
      if (meta.role !== "kid") return
      kids++
      if (meta.part) parts[meta.part] = (parts[meta.part] || 0) + 1
    })
    const picked = Object.entries(parts).map(([n, c]) => (c > 1 ? `${n} ×${c}` : n))
    followingText.textContent =
      kids === 0
        ? "No iPads yet"
        : `${kids} iPad${kids === 1 ? "" : "s"}${picked.length ? ": " + picked.join(", ") : ""}`
  })

  // ---- kids join: QR + link
  const dialog = document.getElementById("join-dialog")
  const kidUrl = `${window.location.origin}${pageEl.dataset.kidPath}`
  document.getElementById("join-url").textContent = kidUrl
  QRCode.toCanvas(document.getElementById("join-qr"), kidUrl, {
    width: 360,
    margin: 1,
    color: { dark: "#3d3a5c", light: "#ffffff" },
  })
  document.getElementById("btn-join").addEventListener("click", () => dialog.showModal())
  document.getElementById("btn-join-close").addEventListener("click", () => dialog.close())
  dialog.addEventListener("click", (e) => { if (e.target === dialog) dialog.close() })
  document.getElementById("btn-copy-link").addEventListener("click", async (e) => {
    try {
      await navigator.clipboard.writeText(kidUrl)
      e.target.textContent = "Copied"
      setTimeout(() => (e.target.textContent = "Copy the link"), 1500)
    } catch {}
  })

  makeTour("master", [
    {
      element: "#transport",
      popover: {
        title: "This is the TV. You run it from here.",
        description:
          "Play and pause are for the whole room: every iPad follows this clock, so the line moves on every screen within a blink of this button.",
        side: "bottom",
      },
    },
    {
      element: "#measures",
      popover: {
        title: "Start from any measure",
        description: "Tap a number to play from there. The kids' screens jump with you.",
        side: "bottom",
        align: "start",
      },
    },
    {
      element: "#btn-sound",
      popover: {
        title: "The sound comes out of the TV",
        description:
          "A simple xylophone plays every part so the kids have something to play along with. Turn it off if you would rather hear the room.",
        side: "bottom",
      },
    },
    {
      element: "#btn-join",
      popover: {
        title: "Getting the kids in",
        description:
          "Press this to put a big code on the TV. A kid points the iPad camera at it, taps their instrument, and they are in. Or copy the link and send it.",
        side: "bottom",
        align: "end",
      },
    },
    {
      element: "#following",
      popover: {
        title: "Who is following",
        description:
          "This counts the iPads on this song and which instruments they picked, so you can see when everyone is ready.",
        side: "bottom",
        align: "end",
      },
    },
    {
      element: "#btn-tour",
      popover: {
        title: "Replay this any time",
        description: "That is the whole TV side. Press play when the room is ready.",
        side: "bottom",
        align: "end",
      },
    },
  ])
}
