// The walkthrough: a joyride over the real page, run once on a first visit
// and again whenever the "Walk me through using this" button is pressed.
// One tour per page; each remembers in localStorage that it has been seen.

import { driver } from "driver.js"

const seenKey = (page) => `dave:tour:${page}`

export function tourSeen(page) {
  try { return localStorage.getItem(seenKey(page)) === "seen" } catch { return false }
}

function markSeen(page) {
  try { localStorage.setItem(seenKey(page), "seen") } catch {}
}

// `steps` may name elements that are not on the page right now (an empty
// song list has no rows); those steps are dropped at start time.
export function makeTour(page, steps, { autoStart = true } = {}) {
  function start() {
    const live = steps.filter((s) => !s.element || document.querySelector(s.element))
    const d = driver({
      showProgress: live.length > 1,
      popoverClass: "dave-tour",
      stagePadding: 8,
      stageRadius: 18,
      overlayColor: "#3d3a5c",
      overlayOpacity: 0.55,
      nextBtnText: "Next",
      prevBtnText: "Back",
      doneBtnText: "Got it",
      progressText: "{{current}} of {{total}}",
      allowClose: true,
      steps: live,
      onDestroyed: () => markSeen(page),
    })
    d.drive()
    return d
  }

  for (const btn of document.querySelectorAll("#btn-tour")) {
    btn.addEventListener("click", start)
  }

  if (autoStart && !tourSeen(page)) {
    // let the page settle (fonts, score fetch) so the spotlight lands right
    setTimeout(start, 600)
  }

  return { start }
}
