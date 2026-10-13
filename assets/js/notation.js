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
    // NFMXML's <beam/> is an empty marker nothing explains, so the reader
    // drops it and OSMD groups eighths and sixteenths by beat itself
    autoBeam: true,
    zoom,
  })
  await osmd.load(musicxml)
  // The constructor's `zoom` option is ignored by OSMD 2.2.1 (osmd.Zoom
  // stays 1 after construction, measured in headless Chromium); the
  // setter before render() is what scales the engraving.
  osmd.Zoom = zoom
  // Every render (the first, and each autoResize) redraws the SVG from
  // scratch, so the letters go on again after each one. autoResize calls
  // the instance's render, so wrapping it here is enough.
  const render = osmd.render.bind(osmd)
  osmd.render = () => {
    render()
    labelNoteheads(osmd)
  }
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
export function noteTracker(osmd, allOnsets) {
  // One stop per distinct time: a chord is several notes at one onset, and
  // the cursor stops there once. Mandalorian's xylophone part is all
  // octave chords; counted per note, its cursor ran ahead at twice speed.
  const onsets = distinctByMs(allOnsets)
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

function distinctByMs(onsets) {
  const seen = new Set()
  return onsets.filter((o) => (seen.has(o.ms) ? false : (seen.add(o.ms), true)))
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

// The letter name inside every notehead, the way Noteflight's "note names"
// noteheads look: a disc in the note's color with a white letter for a
// filled head, a ring with the letter in the note's color for a hollow
// one (half, whole), so the two still read differently. Drawn as SVG
// over the engraving, located from each notehead's on-screen box rather
// than OSMD's coordinates, so zoom and nested transforms do not matter.
const LETTERS = { 0: "C", 2: "D", 4: "E", 5: "F", 7: "G", 9: "A", 11: "B" }
const NS = "http://www.w3.org/2000/svg"

export function labelNoteheads(osmd) {
  const svg = osmd.container.querySelector("svg")
  if (!svg) return
  svg.querySelector(".note-names")?.remove()
  const layer = document.createElementNS(NS, "g")
  layer.setAttribute("class", "note-names")
  const toSvg = svg.getScreenCTM().inverse()

  for (const staves of osmd.GraphicSheet.MeasureList) {
    for (const measure of staves) {
      if (!measure) continue
      for (const entry of measure.staffEntries) {
        for (const gve of entry.graphicalVoiceEntries) {
          const notes = gve.notes
            .filter((n) => n.sourceNote.Pitch && !n.sourceNote.isRest())
            // vexflow draws a chord's heads lowest pitch first
            .sort((a, b) => a.sourceNote.Pitch.getHalfTone() - b.sourceNote.Pitch.getHalfTone())
          if (!notes.length) continue
          const group = notes[0].getSVGGElement?.()
          if (!group) continue
          const heads = [...group.querySelectorAll(".vf-notehead")]
          notes.forEach((note, i) => {
            const head = heads[i]
            if (!head) return
            const pitch = note.sourceNote.Pitch
            const name = LETTERS[pitch.FundamentalNote] ?? "?"
            const alter = pitch.AccidentalHalfTones ?? 0
            const label = name + (alter > 0 ? "♯" : alter < 0 ? "♭" : "")
            const color = headColor(head) || "#3d3a5c"
            const hollow = note.sourceNote.Length.RealValue >= 0.5
            const r = head.getBoundingClientRect()
            const c = new DOMPoint(r.left + r.width / 2, r.top + r.height / 2).matrixTransform(toSvg)
            // A notehead is one staff space tall, and so is the disc: it sits
            // inside its space or on its line, where the head was. Spanning two
            // spaces (the first version) covered the neighbouring lines and
            // Dave could not see which space a note was in.
            const radius = (r.height / 2) * toSvg.a
            layer.appendChild(disc(c.x, c.y, radius, color, hollow))
            layer.appendChild(letter(c.x, c.y, radius, label, hollow ? color : "#ffffff"))
          })
        }
      }
    }
  }
  svg.appendChild(layer)
}

// the fill the engraver gave the head: a per-note color from the score, or black
function headColor(head) {
  const path = head.querySelector("path") || head
  const fill = path.getAttribute("fill") || head.getAttribute("fill")
  return fill && fill !== "none" ? fill : null
}

function disc(x, y, radius, color, hollow) {
  const el = document.createElementNS(NS, "circle")
  el.setAttribute("cx", x)
  el.setAttribute("cy", y)
  if (hollow) {
    el.setAttribute("r", radius - radius * 0.14)
    el.setAttribute("fill", "#ffffff")
    el.setAttribute("stroke", color)
    el.setAttribute("stroke-width", radius * 0.28)
  } else {
    el.setAttribute("r", radius)
    el.setAttribute("fill", color)
  }
  return el
}

function letter(x, y, radius, label, color) {
  const el = document.createElementNS(NS, "text")
  el.setAttribute("x", x)
  el.setAttribute("y", y)
  el.setAttribute("fill", color)
  el.setAttribute("text-anchor", "middle")
  el.setAttribute("dominant-baseline", "central")
  // Fredoka 700 caps are about 0.7em tall and wide; 1.6 radii keeps the
  // letter inside the disc with a hair of margin (a 0.7em square fits a
  // circle of radius 0.5em at font-size 2r, and 1.6r leaves the rim clear)
  el.setAttribute("font-size", radius * (label.length > 1 ? 1.15 : 1.6))
  el.setAttribute("font-family", "Fredoka, system-ui, sans-serif")
  el.setAttribute("font-weight", "700")
  el.setAttribute("style", "pointer-events: none; user-select: none")
  el.textContent = label
  return el
}
