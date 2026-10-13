defmodule Dave.NFM do
  @moduledoc """
  The parsed Noteflight score and its parts.

  Everything here comes from NFMXML, Noteflight's native format, fetched
  straight off a Learning site URL (see `Dave.NFM.Fetch`). NFMXML timing:

    * `value` is a NOTE-VALUE ENUM, not a duration amount, consecutive
      integers doubling each step. Confirmed against `position` on three
      real scores (Mary Had a Little Lamb, Mandalorian, Baby Shark): every
      measure's onsets equal the running sum of its note lengths, with
      `<dotted/>` adding half.

          4 = 16th (16 units)   5 = eighth (32)   6 = quarter (64)
          7 = half (128)        8 = whole (256)

      Anything else (32nds) is still unobserved and raises.
    * A `<tuplet>` in a voice holds its own `<contents>` of noteSets. Its
      `units`/`unitValue` say how long it really is (1 x eighth), its
      `rhythmUnits`/`rhythmValue` what it is written as (3 x 16th), and the
      inner `position`s count in the WRITTEN units from the tuplet's own
      position (0, 16, 32 inside a one-eighth triplet). Nine to Five, bar 6.
    * `<tempo>` can appear in a later systemPart measure's `<attributes>`:
      a tempo change from that bar on (Nine to Five: 100 at bar 1, 70 at
      bar 3). `Score.tempos` lists them; `Score.bpm` is the first.
    * A `<part>` can have two `<staff>`s (piano). Their measures are kept
      on one `Part`, each `Measure` saying which `staff` it belongs to.
    * `<voice><tacet/></voice>` is a silent voice: a whole-measure rest,
      like an empty `<voice/>`.
    * `<hidden/>` on a part (Nine to Five's Voice) is kept and noted, not
      dropped: it holds the melody and every lyric.
    * Repeat barlines, segno, coda and performance texts ("D.S. al Coda")
      are read only to WARN: the timeline plays the score straight through
      once, and so must the engraving, or the cursor and the clock part.
    * `position` is an onset inside the measure, 64 units per quarter
      (observed: 0, 64, 128, 192 across a 4/4 measure).
    * `<tied/>` on a note means the tie STARTS there and ends on the next
      note of that pitch in the voice, usually the first note of the next
      measure (every observed tie sits at a measure's end).
    * A `<voice/>` with no noteSets is a whole-measure rest (Mandalorian's
      bells rest for 12 measures that way).
    * `<clef><sign>G</sign><note>G4</note><line>1</line></clef>` counts
      staff lines from ZERO. MusicXML counts from one, and a G clef on
      MusicXML line 1 is the French violin clef: every note drew a third
      low until the `<note>` (G4, the pitch the clef marks) was used to
      place it instead of the line number.
  """

  defmodule Score do
    @enforce_keys [:title, :composer, :beats, :beat_type, :fifths, :mode, :bpm, :parts]
    defstruct [
      :title,
      :composer,
      :beats,
      :beat_type,
      :fifths,
      :mode,
      :bpm,
      :parts,
      # [{measure_index, quarter_bpm}], first entry at measure 0; bpm is its bpm
      tempos: [],
      # sentences for Dave about what the import does not follow (repeats)
      warnings: []
    ]
  end

  defmodule Part do
    @enforce_keys [:nfm_id, :name, :short_name, :instrument_uri, :measures]
    defstruct [:nfm_id, :name, :short_name, :instrument_uri, :measures, staves: 1, hidden: false]
    # measures: staff 1's measures, then staff 2's (each Measure says its staff)
  end

  defmodule Measure do
    @enforce_keys [:index, :clef, :notes]
    defstruct [:index, :clef, :notes, staff: 1]
  end

  defmodule Note do
    @enforce_keys [:voice, :value, :position, :pitch, :color, :chord]
    defstruct [
      :voice,
      :value,
      :position,
      :pitch,
      :color,
      :chord,
      dotted: false,
      tied: false,
      tie_stop: false,
      lyrics: [],
      tuplet: nil,
      measure_rest: false,
      beats: nil
    ]

    # pitch is nil for a rest, else %{step: "D", alter: 0, octave: 5,
    #   accidental: nil | "flat" | "sharp" | "natural" ...}: alter is the
    #   sounding alteration (an F# in a sharp key has alter 1), accidental
    #   the mark Noteflight engraves, which is only the first in a bar
    # chord: true on every note after the first of a chord's noteSet
    # dotted: <dotted/> on the noteSet, length x1.5
    # tied: <tied/> on the note; the tie starts here (see moduledoc)
    # tie_stop: set by the parser on the note a tie lands on
    # lyrics: one per verse, %{number: 1, text: "C", color: "#33BB33" | nil,
    #   placement: "below" | "above" | nil, syllabic: "single" | "begin",
    #   extend: bool}; [] when the slot is empty
    # tuplet: nil | %{actual: 3, normal: 2, start: bool, stop: bool, bracket: bool}
    #   three 16ths in the time of two; beats already carries the 2/3
    # measure_rest: a voice with no noteSets; value is nil, beats is the
    #   measure's length in quarter notes
    # beats: length in quarter notes, dot included (set by the parser)
  end

  @note_values %{
    # value -> {MusicXML type, beats} — observed facts only (see moduledoc)
    4.0 => {:"16th", 0.25},
    5.0 => {:eighth, 0.5},
    6.0 => {:quarter, 1.0},
    7.0 => {:half, 2.0},
    8.0 => {:whole, 4.0}
  }

  @doc "A note's length in quarter notes: the enum's beats, x1.5 when dotted."
  def beats(%Note{measure_rest: true, beats: beats}), do: beats

  def beats(%Note{value: value, dotted: dotted, tuplet: tuplet}) do
    {_type, beats} = note_value(value)
    beats = if dotted, do: beats * 1.5, else: beats

    case tuplet do
      nil -> beats
      %{actual: actual, normal: normal} -> beats * normal / actual
    end
  end

  @doc """
  The observed note values, for introspection and tests.
  """
  def note_values, do: @note_values

  @doc """
  A note value's MusicXML type and length in quarter-note beats.

      Dave.NFM.note_value(6)  #=> {:quarter, 1.0}
  """
  def note_value(value) do
    case Map.fetch(@note_values, value) do
      {:ok, tv} ->
        tv

      :error ->
        raise ArgumentError,
              "TODO: NFMXML note value #{inspect(value)} not yet observed — " <>
                "add it to Dave.NFM's @note_values when a real score shows what it is"
    end
  end

  @doc "One quarter note, in NFMXML position units (how onsets are measured)."
  def quarter_position, do: 64

  @doc "Quarter-notes-per-minute into beats per second."
  @spec seconds_per_beat(number()) :: float()
  def seconds_per_beat(bpm), do: 60.0 / bpm
end
