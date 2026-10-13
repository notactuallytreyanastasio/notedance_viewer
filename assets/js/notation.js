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
  osmd.render()
  osmd.cursor.reset()
  osmd.cursor.show()
  return osmd
}

// Advance the OSMD cursor to the next timeline note at or before `ms`.
// `notes` are the part's notes in document order — the same order OSMD's
// cursor walks them for a single-voice part. Scrolls only when the cursor
// actually moved, so a paused page stays still.
export function noteTracker(osmd, notes) {
  let idx = 0
  let currentIdx = -1

  function seekTo(ms) {
    if (idx > 0 && ms < notes[idx - 1].ms) {
      osmd.cursor.reset()
      idx = 0
      currentIdx = -1
    }
    while (idx < notes.length && notes[idx].ms <= ms) idx++
    let moved = false
    while (currentIdx < idx - 1) {
      osmd.cursor.next()
      currentIdx++
      moved = true
    }
    if (moved) keepCursorVisible()
  }

  return { seekTo }
}

// Measure-level cursor for the TV: jump to the start of measure m.
export function measureTracker(osmd) {
  let current = -1

  function seekToMeasure(m) {
    if (m === current) return
    osmd.cursor.reset()
    for (let i = 0; i < m; i++) osmd.cursor.nextMeasure()
    current = m
    keepCursorVisible()
  }

  return { seekToMeasure }
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
