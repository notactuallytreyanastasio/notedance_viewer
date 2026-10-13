// The shared clock. Mirrors Dave.Sessions: the server broadcasts
// {status, position_ms, at (server wall ms)}; every client advances
// position + (serverNow - at) locally, with serverNow = Date.now() + a
// ping-estimated offset. Nobody trusts their own wall clock.

export function makeClock(channel) {
  const clock = {
    status: "paused",
    position: 0,
    at: 0,
    offset: null,
    samples: [],
    listeners: [],
  }

  clock.nowMs = () => Date.now() + (clock.offset ?? 0)

  clock.positionMs = () =>
    clock.status === "playing"
      ? clock.position + (clock.nowMs() - clock.at)
      : clock.position

  // fires on every broadcast with (state, {statusChanged, jumped}) so a
  // listener can tell a heartbeat from a real transport event
  clock.onState = (fn) => clock.listeners.push(fn)

  clock.applyState = (s) => {
    const predicted = clock.positionMs()
    const statusChanged = s.status !== clock.status
    clock.status = s.status
    clock.position = s.position_ms
    clock.at = s.at
    const jumped = Math.abs(clock.positionMs() - predicted) > 150
    for (const fn of clock.listeners) fn(s, { statusChanged, jumped })
  }

  function ping() {
    const t = Date.now()
    channel.push("ping", { t }).receive("ok", (reply) => {
      const rtt = Date.now() - t
      // server now ≈ reply.now + rtt/2 (half the trip each way)
      const offset = reply.now + rtt / 2 - Date.now()
      clock.samples.push({ rtt, offset })
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

// run `tick` every animation frame while playing, and once on every
// status change (so a pause lands the cursor on the right note)
export function onFrame(clock, tick) {
  let wasStatus = null
  function frame() {
    if (clock.status !== wasStatus) {
      wasStatus = clock.status
      tick()
    }
    if (clock.status === "playing") tick()
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

export function formatTime(ms) {
  const s = Math.max(0, Math.floor(ms / 1000))
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
}
