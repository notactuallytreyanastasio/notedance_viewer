// dave — classroom music viewer.
//
// Two pages, both driven by the same clock:
//   master (TV/teacher): full score, WebAudio synth, transport controls
//   kid (iPad): one part, huge, following the red line
//
// Sync scheme (mirrors Dave.Sessions): the server broadcasts
// {status, position_ms, at (server wall ms)}; every client advances
// position + (serverNow - at) locally, with serverNow = Date.now() + a
// ping-estimated offset. Nobody trusts their own wall clock.

import { Socket } from "phoenix"
import { OpenSheetMusicDisplay } from "opensheetmusicdisplay"

// ---------------------------------------------------------------- bootstrap

const pageEl = document.getElementById("page")

if (pageEl) {
  const kind = pageEl.dataset.page
  const socket = new Socket("/socket")
  socket.connect()
  const channel = socket.channel(`score:${pageEl.dataset.scoreId}`, {})

  if (kind === "kid") initKid(channel)
  if (kind === "master") initMaster(channel)

  const statusDot = document.getElementById("status-dot")
  channel.on("state", (s) => {
    statusDot.className =
      "inline-block w-3 h-3 rounded-full " +
      (s.status === "playing" ? "bg-red-500 animate-pulse" : "bg-zinc-300")
  })

  channel.join().receive("error", (e) => console.error("channel join failed", e))
}

// ---------------------------------------------------------------- clock

// The clock: server time offset estimated by ping round-trips (best of N,
// re-sampled periodically), and the latest broadcast position.
function makeClock(channel) {
  const clock = {
    status: "paused",
    position: 0,
    at: 0,
    offset: null,
    samples: [],
    onState: null,
  }

  clock.nowMs = () => Date.now() + (clock.offset ?? 0)

  clock.positionMs = () =>
    clock.status === "playing"
      ? clock.position + (clock.nowMs() - clock.at)
      : clock.position

  clock.applyState = (s) => {
    clock.status = s.status
    clock.position = s.position_ms
    clock.at = s.at
    if (clock.onState) clock.onState(s)
  }

  function ping() {
    const t = Date.now()
    channel
      .push("ping", { t })
      .receive("ok", (reply) => {
        const rtt = Date.now() - t
        // server now ≈ reply.now + rtt/2 (half the trip each way)
        const offset = reply.now + rtt / 2 - Date.now()
        clock.samples.push({ rtt, offset })
        // keep the best few; prefer lowest rtt
        clock.samples.sort((a, b) => a.rtt - b.rtt)
        if (clock.samples.length > 5) clock.samples.length = 5
        clock.offset = clock.samples[0].offset
      })
  }

  for (let i = 0; i < 6; i++) setTimeout(ping, i * 400)
  setInterval(ping, 10_000)

  channel.on("state", clock.applyState)
  return clock
}

// ---------------------------------------------------------------- OSMD

async function drawScore(el, url, zoom) {
  const musicxml = await (await fetch(url)).text()
  const osmd = new OpenSheetMusicDisplay(el, {
    autoResize: true,
    drawTitle: false,
    drawSubtitle: false,
    drawPartNames: false,
    disableCursor: false,
    followCursor: true,
    zoom,
  })
  await osmd.load(musicxml)
  osmd.render()
  return osmd
}

// Advance the OSMD cursor to the next timeline note at or before `ms`.
// `notes` are the part's notes in document order — the same order OSMD's
// cursor walks them for a single-voice part.
function cursorTracker(osmd, notes) {
  let idx = 0
  let currentIdx = -1

  function seekTo(ms) {
    if (idx > 0 && ms < notes[idx - 1].ms) {
      // jumped backwards: restart the walk
      osmd.cursor.reset()
      idx = 0
      currentIdx = -1
    }
    while (idx < notes.length && notes[idx].ms <= ms) idx++
    while (currentIdx < idx - 1) {
      osmd.cursor.next()
      currentIdx++
    }
    followCursorEl()
  }

  return { seekTo }
}

function followCursorEl() {
  // OSMD renders the cursor with a stable id (cursor.d.ts: cursorElementId)
  const el = document.querySelector("g[id^='cursor'], img[id^='cursor'], #cursor")
  if (el && el.scrollIntoView) el.scrollIntoView({ block: "center", behavior: "smooth" })
}

// run `tick` every animation frame while playing (and once immediately)
function onFrame(clock, tick) {
  let wasPlaying = null
  function frame() {
    if (clock.status !== wasPlaying) {
      wasPlaying = clock.status
      tick()
    }
    if (clock.status === "playing") tick()
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

// ---------------------------------------------------------------- kid page

function initKid(channel) {
  const clock = makeClock(channel)
  const osmdEl = document.getElementById("osmd")
  const partsBar = document.getElementById("parts")
  const hint = document.getElementById("pick-hint")

  let tracker = null
  let notes = null

  fetch(pageEl.dataset.timelineUrl)
    .then((r) => r.json())
    .then((timeline) => {
      const indices = Object.keys(timeline.parts).sort((a, b) => a - b)
      for (const i of indices) {
        const part = timeline.parts[i]
        const btn = document.createElement("button")
        btn.textContent = part.name
        btn.className =
          "rounded-full border-2 px-4 py-2 text-lg font-semibold border-zinc-300 hover:border-orange-500"
        btn.onclick = () => pickPart(i, part)
        btn.dataset.index = i
        partsBar.appendChild(btn)
      }
    })

  async function pickPart(i, part) {
    hint.classList.add("hidden")

    for (const b of partsBar.children) {
      const selected = b.dataset.index === i
      b.className = selected
        ? "rounded-full border-2 px-4 py-2 text-lg font-semibold border-orange-600 bg-orange-600 text-white"
        : "rounded-full border-2 px-4 py-2 text-lg font-semibold border-zinc-300 hover:border-orange-500"
    }

    if (osmdEl.dataset.loadedPart !== i) {
      osmdEl.dataset.loadedPart = i
      osmdEl.innerHTML = ""
      const osmd = await drawScore(
        osmdEl,
        `/s/${pageEl.dataset.scoreId}/musicxml/${i}`,
        1.6
      )
      osmd.cursor.reset()
      osmd.cursor.show()
      tracker = cursorTracker(osmd, part.notes)
    }

    // jump straight to wherever the class is
    if (tracker) tracker.seekTo(clock.positionMs())
  }

  onFrame(clock, () => {
    if (tracker) tracker.seekTo(clock.positionMs())
  })
}

// ---------------------------------------------------------------- master page

function initMaster(channel) {
  const clock = makeClock(channel)
  const osmdEl = document.getElementById("osmd")
  const positionEl = document.getElementById("position")
  const measuresBar = document.getElementById("measures")

  let osmd = null
  let measures = []
  let cursorMeasure = -1
  let timeline = null

  // WebAudio: schedule every note (all parts) as a struck-bar-ish blip
  const audio = makeSynth()

  drawScore(osmdEl, pageEl.dataset.musicxmlUrl, 1.1).then((o) => {
    osmd = o
    osmd.cursor.reset()
    osmd.cursor.show()
  })

  fetch(pageEl.dataset.timelineUrl)
    .then((r) => r.json())
    .then((tl) => {
      timeline = tl
      measures = tl.measures
      for (const m of measures) {
        const btn = document.createElement("button")
        btn.textContent = m.i + 1
        btn.className =
          "w-10 h-10 rounded-lg border border-zinc-300 font-semibold hover:border-orange-500"
        btn.onclick = () => channel.push("seek", { position_ms: m.start_ms })
        measuresBar.appendChild(btn)
      }
    })

  clock.onState = (s) => {
    if (s.status === "playing") audio.start(timeline, clock.positionMs())
    else audio.stop()
  }

  document.getElementById("btn-play").onclick = () => channel.push("play", {})
  document.getElementById("btn-pause").onclick = () => channel.push("pause", {})
  document.getElementById("btn-restart").onclick = () =>
    channel.push("play", { position_ms: 0 })
  document.getElementById("btn-mute").onclick = (e) => {
    audio.muted = !audio.muted
    e.target.textContent = audio.muted ? "🔇" : "🔊"
  }

  onFrame(clock, () => {
    const pos = clock.positionMs()
    positionEl.textContent = (pos / 1000).toFixed(1) + "s"

    if (osmd && measures.length) {
      const m = measureAt(pos)
      if (m !== cursorMeasure) {
        // measure-level cursor on the TV: jump the OSMD cursor to measure m
        osmd.cursor.reset()
        for (let i = 0; i < m; i++) osmd.cursor.nextMeasure()
        cursorMeasure = m
      }
    }
  })

  function measureAt(pos) {
    if (!measures.length) return 0
    let m = 0
    for (let i = 0; i < measures.length; i++) if (measures[i].start_ms <= pos) m = i
    return m
  }
}

// ---------------------------------------------------------------- synth

// A school xylophone, roughly: fundamental + a third partial, fast attack,
// exponential decay. Scheduler starts from a position and stops cleanly.
function makeSynth() {
  const audio = { ctx: null, muted: false, scheduled: [], start, stop }

  function ensureCtx() {
    if (!audio.ctx) audio.ctx = new (window.AudioContext || window.webkitAudioContext)()
    if (audio.ctx.state === "suspended") audio.ctx.resume()
    return audio.ctx
  }

  function voice(ctx, dest, midi, at) {
    const freq = 440 * Math.pow(2, (midi - 69) / 12)
    const dur = 0.6

    for (const [mult, gain] of [
      [1, 0.22],
      [3, 0.05],
    ]) {
      const osc = ctx.createOscillator()
      const g = ctx.createGain()
      osc.type = "sine"
      osc.frequency.value = freq * mult
      g.gain.setValueAtTime(0, at)
      g.gain.linearRampToValueAtTime(gain, at + 0.008)
      g.gain.exponentialRampToValueAtTime(0.0001, at + dur)
      osc.connect(g).connect(dest)
      osc.start(at)
      osc.stop(at + dur + 0.05)
      audio.scheduled.push(osc)
    }
  }

  function start(timeline, positionMs) {
    if (!timeline || audio.muted) return
    stop()
    const ctx = ensureCtx()
    const t0 = ctx.currentTime + 0.05
    for (const key of Object.keys(timeline.parts)) {
      for (const note of timeline.parts[key].notes) {
        if (note.midi == null) continue
        if (note.ms < positionMs - 30) continue
        const at = t0 + (note.ms - positionMs) / 1000
        if (at > t0 + 30) break // schedule a 30s window at a time
        voice(ctx, ctx.destination, note.midi, at)
      }
    }
  }

  function stop() {
    for (const osc of audio.scheduled) {
      try {
        osc.stop()
      } catch {}
    }
    audio.scheduled = []
  }

  return audio
}
