// The kid's page: tap your instrument, see only your part, follow the line.

import { makeClock, onFrame } from "./clock"
import { drawScore, noteTracker } from "./notation"
import { makeTour, tourSeen } from "./tour"

export function initKid(pageEl, channel, session) {
  const clock = makeClock(channel)
  const scoreId = pageEl.dataset.scoreId
  const slug = pageEl.dataset.slug
  const osmdEl = document.getElementById("osmd")
  const loadingEl = document.getElementById("sheet-loading")
  const barsEl = document.getElementById("parts")
  const statusEl = document.getElementById("kid-status")
  const statusText = document.getElementById("kid-status-text")
  const liveDot = statusEl.querySelector(".live-dot")
  const changeBtn = document.getElementById("btn-change")
  const partPill = document.getElementById("kid-part")
  const rememberKey = `dave:part:${scoreId}`

  let tracker = null
  let picked = null

  fetch(pageEl.dataset.timelineUrl)
    .then((r) => r.json())
    .then((timeline) => {
      const indices = Object.keys(timeline.parts).sort((a, b) => a - b)
      indices.forEach((i, n) => {
        const part = timeline.parts[i]
        const btn = document.createElement("button")
        btn.type = "button"
        btn.className = "bar"
        btn.textContent = part.name
        btn.dataset.index = i
        btn.dataset.bar = String(n % 8)
        btn.style.setProperty("--i", String(n))
        btn.setAttribute("aria-pressed", "false")
        btn.addEventListener("click", () => pickPart(i, part, n))
        barsEl.appendChild(btn)
      })

      // the same iPad usually plays the same instrument next time
      let remembered = null
      try { remembered = localStorage.getItem(rememberKey) } catch {}
      if (remembered != null && timeline.parts[remembered]) {
        pickPart(remembered, timeline.parts[remembered], indices.indexOf(remembered))
      }

      // The walkthrough runs by itself only on a device that has already
      // seen the songs page, i.e. Dave's own. A kid's iPad never saw it,
      // so a kid is never interrupted; the ? button is always there.
      makeTour("kid", kidSteps(), { autoStart: tourSeen("home") })
    })

  async function pickPart(i, part, n) {
    picked = i
    try { localStorage.setItem(rememberKey, i) } catch {}
    pageEl.dataset.picked = "true"
    barsEl.dataset.picked = "true"
    for (const b of barsEl.querySelectorAll(".bar")) {
      b.setAttribute("aria-pressed", b.dataset.index === i ? "true" : "false")
    }
    statusEl.dataset.part = part.name
    partPill.textContent = part.name
    partPill.dataset.bar = String(n % 8)
    partPill.classList.remove("hidden")
    changeBtn.classList.remove("hidden")
    session.part = part.name
    channel.push("part", { name: part.name })
    keepScreenAwake()

    if (osmdEl.dataset.loadedPart !== i) {
      osmdEl.dataset.loadedPart = i
      osmdEl.innerHTML = ""
      tracker = null
      loadingEl.classList.remove("hidden")
      // Big enough that a one-space disc with a letter in it reads from a
      // lap: a staff space is 10px at zoom 1, so this is 17-24px. A
      // portrait iPad (768px) gets 1.7, landscape (1024px) 2.1, a laptop 2.4.
      const zoom = Math.min(2.4, Math.max(1.7, window.innerWidth / 480))
      const osmd = await drawScore(osmdEl, `/${slug}/musicxml/${i}`, zoom)
      loadingEl.classList.add("hidden")
      tracker = noteTracker(osmd, part.notes)
      window.__tracker = tracker // for the headless checks in the scratchpad
    }

    // jump straight to wherever the class is
    if (tracker) tracker.seekTo(clock.positionMs())
    renderStatus()
  }

  changeBtn.addEventListener("click", () => {
    pageEl.dataset.picked = "false"
    window.scrollTo({ top: 0, behavior: "smooth" })
  })

  let online = true

  function renderStatus() {
    const status = picked == null ? "none" : clock.status
    statusEl.dataset.status = online ? status : "offline"
    liveDot.dataset.live = picked == null || !online ? "" : clock.status
    if (!online) statusText.textContent = "Reconnecting to the TV…"
    else if (status === "none") statusText.textContent = "Pick an instrument to start"
    else if (status === "playing") statusText.textContent = "Follow the line"
    else statusText.textContent = "Waiting for your teacher to press play"
  }

  clock.onState(renderStatus)
  document.addEventListener("dave:connection", (e) => {
    online = e.detail === "online"
    renderStatus()
  })
  renderStatus()

  onFrame(clock, () => {
    if (tracker) tracker.seekTo(clock.positionMs())
  })

  // the screen should not go dark in the middle of a song
  async function keepScreenAwake() {
    try {
      if (navigator.wakeLock) await navigator.wakeLock.request("screen")
    } catch {}
  }
}

function kidSteps() {
  return [
    {
      element: "#instruments",
      popover: {
        title: "Kids tap their instrument",
        description:
          "One bar per part in the song. The iPad remembers the choice, so next time the same kid opens the link their part is already up.",
        side: "bottom",
      },
    },
    {
      element: "#kid-status",
      popover: {
        title: "Then they just follow the line",
        description:
          "This strip says what the TV is doing. When you press play on the TV, the line starts moving here within a blink. Nothing for a kid to press.",
        side: "bottom",
      },
    },
    {
      element: "#btn-tour",
      popover: {
        title: "That's the whole kid side",
        description: "The ? replays this. It is small on purpose: the big buttons are the instruments.",
        side: "left",
      },
    },
  ]
}
