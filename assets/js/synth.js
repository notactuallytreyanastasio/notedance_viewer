// A school xylophone, roughly: fundamental + a third partial, fast attack,
// exponential decay. The scheduler keeps a short lookahead window topped up
// from a timer, so (re)starting never cuts a note that is already ringing
// and songs of any length keep sounding.

const LOOKAHEAD_S = 0.8
const TICK_MS = 200

export function makeSynth() {
  const synth = { ctx: null, muted: false, unlock, start, stop }
  let timer = null
  let pending = [] // oscillators scheduled but not yet started

  // Create and resume the AudioContext. Must run inside a user gesture
  // (Safari refuses to resume otherwise), so the play button calls it
  // before anything goes over the wire.
  function unlock() {
    if (!synth.ctx) synth.ctx = new (window.AudioContext || window.webkitAudioContext)()
    if (synth.ctx.state === "suspended") synth.ctx.resume()
    return synth.ctx
  }

  function voice(ctx, midi, at) {
    const freq = 440 * Math.pow(2, (midi - 69) / 12)
    const dur = 0.6
    for (const [mult, gain] of [[1, 0.22], [3, 0.05]]) {
      const osc = ctx.createOscillator()
      const g = ctx.createGain()
      osc.type = "sine"
      osc.frequency.value = freq * mult
      g.gain.setValueAtTime(0, at)
      g.gain.linearRampToValueAtTime(gain, at + 0.008)
      g.gain.exponentialRampToValueAtTime(0.0001, at + dur)
      osc.connect(g).connect(ctx.destination)
      osc.start(at)
      osc.stop(at + dur + 0.05)
      pending.push({ osc, at })
    }
  }

  // Start from `positionMs` (song time) at `ctx.currentTime` now.
  function start(timeline, positionMs) {
    stop()
    if (!timeline || synth.muted || !synth.ctx) return
    const ctx = synth.ctx
    const t0 = ctx.currentTime + 0.05 - positionMs / 1000 // ctx time of song position 0

    // every part's pitched notes from here on, in time order
    const notes = []
    for (const key of Object.keys(timeline.parts)) {
      for (const n of timeline.parts[key].notes) {
        if (n.midi != null && n.ms >= positionMs - 30) notes.push(n)
      }
    }
    notes.sort((a, b) => a.ms - b.ms)

    let i = 0
    function schedule() {
      const horizon = ctx.currentTime + LOOKAHEAD_S
      while (i < notes.length && t0 + notes[i].ms / 1000 <= horizon) {
        voice(ctx, notes[i].midi, Math.max(t0 + notes[i].ms / 1000, ctx.currentTime))
        i++
      }
      pending = pending.filter((p) => p.at > ctx.currentTime)
      if (i >= notes.length) {
        clearInterval(timer)
        timer = null
      }
    }
    schedule()
    timer = setInterval(schedule, TICK_MS)
  }

  // Cancel what has not started yet; let ringing notes decay like real bars.
  function stop() {
    if (timer) clearInterval(timer)
    timer = null
    const ctx = synth.ctx
    for (const p of pending) {
      if (!ctx || p.at > ctx.currentTime) {
        try { p.osc.stop() } catch {}
      }
    }
    pending = []
  }

  return synth
}
