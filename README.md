# DaveDance

Put a song on the TV. Hand the kids the link.

A classroom music viewer for Noteflight Learning scores, built for one
music teacher and his xylophones. The TV runs the clock; every iPad in
the room follows the red line through its own part. Live at
https://dave.bobbby.online. The teacher's guide is
[docs/for-dave.md](docs/for-dave.md).

## How a lesson goes

1. Paste a Noteflight Learning score link on the home page. The score
   is fetched, read, and saved under a two-word address like
   `dave.bobbby.online/sunny-fox`. Paste the same link again after
   editing in Noteflight and it updates in place, address kept.
2. Open the song on the TV. Play, pause, start from any bar, sound on
   or off. **Kids join** shows a QR code and the two words.
3. Each kid opens the address on an iPad, taps their instrument, and
   sees only that part, big, with the letter name inside every
   notehead in the color the teacher gave it in Noteflight. The line
   moves when the TV presses play. There is nothing for a kid to press.

Every page starts with a walkthrough the first time; the `?` replays it.

## What it reads

Noteflight has no public API. A Learning site serves a score's native
XML (NFMXML, zlib inside base64) to anyone with the link, and the
reader in `lib/dave/nfm/` turns that into MusicXML for
[OpenSheetMusicDisplay](https://opensheetmusicdisplay.org/) and a
timeline of onsets in milliseconds for the clock. It is strict on
purpose: anything it has not met on a real score raises with the
offending node, and the import says "something DaveDance cannot read
yet" instead of drawing it wrong. Seven of the teacher's scores taught
it, in this order:

- note values as an enum (4 = 16th … 8 = whole), dots, ties, rests,
  whole-bar rests, chords, per-note colors, note-name noteheads
- tuplets, whose inner positions count in the written units
- accidentals: `<pitch>` is the sounding pitch and `<accidental>` only
  the mark that is engraved, so the alteration comes from the pitch
- tempo changes, key changes, pickup bars
- two-staff parts (piano), lyrics with verses and hyphens, chord
  symbols, hidden parts
- repeats, segno, coda, "To Coda", "D.S. al Coda": the timeline unrolls
  the form and the cursor is jumped to match, while OSMD's own
  repetition following is switched off so there is one clock
- the clef's `<line>` counts from zero (every note drew a third low
  until that was found), and the number after a score id in the
  content URL is a version, which once pinned an old draft for a day

Still refused by name: a second voice with notes, 32nd notes, a time
signature change, first and second endings, a chord kind outside the
sixteen seen so far. The module docs in `lib/dave/nfm.ex` and
`lib/dave/nfm/parser.ex` record what each fact was checked against.

## How the room stays in time

The TV owns a session clock and broadcasts play, pause and seek over a
Phoenix channel; each iPad keeps a local copy and advances it between
messages, so a frame never waits on the network. A kid who opens the
page mid-song lands on the current bar. The iPad remembers its
instrument, keeps the screen awake, and says "Reconnecting to the TV"
while the wifi is away.

## Pages

| Path | What |
| --- | --- |
| `/` | the song list and the import box |
| `/:slug/tv` | the TV: transport, bar buttons, QR code, who has joined |
| `/:slug` | the kid page: pick an instrument, follow the line |
| `/:slug/musicxml`, `/:slug/musicxml/:part` | the engraving OSMD draws |
| `/:slug/timeline` | onsets, bars and playback order in milliseconds |

Slugs are forgiving: `SunnyFox`, `sunny fox` and `sunnyfox` all work,
since kids type them.

## Running it

Elixir 1.18, Phoenix 1.8, Postgres. Then:

```sh
mix setup          # deps, database, assets
mix phx.server     # http://localhost:4000
mix test           # the reader's facts, 77 of them
```

With no Noteflight link handy, **Load the example song** on the home
page imports Mary Had a Little Lamb for three xylophones from a bundled
fixture.

`deploy.sh` runs the tests, rsyncs the tree to the server, rebuilds the
container and migrates. It needs `DEPLOY_HOST=user@host`; the address
is not in the repo.

## Verifying against the real thing

Nothing here is trusted on reading alone. The scratchpad scripts that
drove the work (not in the repo) load the live pages in headless
Chromium, step the OSMD cursor through every onset of every part, and
compare the bar it lands on to the timeline. The commit messages carry
the measurements: 465 cursor stops versus 311 when OSMD followed the
repeats itself, a Unicode segno that drew as a box, the lyric font size
that only takes effect before load.

## Layout

```
lib/dave/nfm/      the Noteflight reader: fetch, parse, form, chord, music_xml, timeline
lib/dave/scores.ex import, slugs, storage
lib/dave/sessions.ex the per-song clock the TV drives
lib/dave_web/      controllers, templates, the session channel
assets/js/         notation.js (OSMD, letters, cursor), master.js (TV), kid.js, synth.js, clock.js
test/support/fixtures/  the real scores, as fetched
docs/for-dave.md   the teacher's guide
```
