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

      Anything else (32nds, triplets) is still unobserved and raises.
    * `position` is an onset inside the measure, 64 units per quarter
      (observed: 0, 64, 128, 192 across a 4/4 measure).
    * `<tied/>` on a note means the tie STARTS there and ends on the next
      note of that pitch in the voice, usually the first note of the next
      measure (every observed tie sits at a measure's end).
    * A `<voice/>` with no noteSets is a whole-measure rest (Mandalorian's
      bells rest for 12 measures that way).
  """

  defmodule Score do
    @enforce_keys [:title, :composer, :beats, :beat_type, :fifths, :mode, :bpm, :parts]
    defstruct [:title, :composer, :beats, :beat_type, :fifths, :mode, :bpm, :parts]
  end

  defmodule Part do
    @enforce_keys [:nfm_id, :name, :short_name, :instrument_uri, :measures]
    defstruct [:nfm_id, :name, :short_name, :instrument_uri, :measures]
  end

  defmodule Measure do
    @enforce_keys [:index, :clef, :notes]
    defstruct [:index, :clef, :notes]
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
      lyric: nil,
      measure_rest: false,
      beats: nil
    ]

    # pitch is nil for a rest, else %{step: "D", alter: 0, octave: 5}
    # chord: true on every note after the first of a chord's noteSet
    # dotted: <dotted/> on the noteSet, length x1.5
    # tied: <tied/> on the note; the tie starts here (see moduledoc)
    # tie_stop: set by the parser on the note a tie lands on
    # lyric: nil | %{text: "C", color: "#33BB33" | nil}
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

  def beats(%Note{value: value, dotted: dotted}) do
    {_type, beats} = note_value(value)
    if dotted, do: beats * 1.5, else: beats
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
