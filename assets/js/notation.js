// OpenSheetMusicDisplay: drawing a score and walking its cursor.

import { OpenSheetMusicDisplay } from "opensheetmusicdisplay"

const FOLLOW_LINE = "#ef6b6b"

export async function drawScore(el, url, zoom) {
  const musicxml = await (await fetch(url)).text()
  const osmd = new OpenSheetMusicDisplay(el, {
    autoResize: true,
    drawTitle: false,
    drawSubtitle: false,
    drawComposer: false,
    drawPartNames: false,
    disableCursor: false,
    followCursor: false,
    cursorsOptions: [{ type: 0, color: FOLLOW_LINE, alpha: 0.6, follow: false }],
    zoom,
  })
  await osmd.load(musicxml)
  // The constructor's `zoom` option is ignored by OSMD 2.2.1 (osmd.Zoom
  // stays 1 after construction, measured in headless Chromium); the
  // setter before render() is what scales the engraving.
  osmd.Zoom = zoom
  osmd.render()
  window.__osmd = osmd // for the headless checks in the scratchpad
  osmd.cursor.reset()
  osmd.cursor.show()
  return osmd
}

// Advance the OSMD cursor to the latest onset at or before `ms`.
// `onsets` are {ms} in document order: a part's notes for the kid page, or
// every distinct onset across all parts for the TV, which is the order
// OSMD's cursor walks the score (cursor.next() steps to the next distinct
// timestamp across every staff). After reset() the cursor is already ON
// the first onset, so the walk starts at 0, not before it; starting at -1
// put the line on the second note at time zero.
export function noteTracker(osmd, onsets) {
  let idx = 0 // onsets[idx] is the first onset still in the future
  let at = 0 // the onset the cursor is on

  function seekTo(ms) {
    if (idx > 0 && ms < onsets[idx - 1].ms) {
      osmd.cursor.reset()
      idx = 0
      at = 0
    }
    while (idx < onsets.length && onsets[idx].ms <= ms) idx++
    const target = Math.max(0, idx - 1)
    let moved = false
    while (at < target) {
      osmd.cursor.next()
      at++
      moved = true
    }
    if (moved) keepCursorVisible()
  }

  return { seekTo }
}

// Every distinct onset across all parts, sorted: the TV's walk order.
export function mergedOnsets(timeline) {
  const seen = new Set()
  for (const key of Object.keys(timeline.parts)) {
    for (const n of timeline.parts[key].notes) seen.add(n.ms)
  }
  return [...seen].sort((a, b) => a - b).map((ms) => ({ ms }))
}

function keepCursorVisible() {
  const el = document.querySelector("img[id^='cursor'], #cursor")
  if (!el) return
  const r = el.getBoundingClientRect()
  const top = 180
  const bottom = window.innerHeight - 120
  if (r.top < top || r.bottom > bottom) {
    el.scrollIntoView({ block: "center", behavior: "smooth" })
  }
}
