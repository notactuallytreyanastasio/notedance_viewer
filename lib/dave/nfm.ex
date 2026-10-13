defmodule Dave.NFM do
  @moduledoc """
  The parsed Noteflight score and its parts.

  Everything here comes from NFMXML, Noteflight's native format, fetched
  straight off a Learning site URL (see `Dave.NFM.Fetch`). NFMXML timing:

    * `value` is a NOTE-VALUE ENUM, not a duration amount. Observed on the
      real Mary Had a Little Lamb score: 6 = quarter (four per 4/4 measure),
      7 = half (the "quarter quarter half" phrase measures, and the final
      half-note + half-rest measure). The ladder is presumably consecutive
      integers (5 = eighth? 8 = whole?) but nothing here guesses: unobserved
      values raise, and the first score with eighths in it will name its
      own value in the crash.
    * `position` is an onset inside the measure, 64 units per quarter
      (observed: 0, 64, 128, 192 across a 4/4 measure).
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
    defstruct [:voice, :value, :position, :pitch, :color, :chord]
    # pitch is nil for a rest, else %{step: "D", alter: 0, octave: 5}
    # chord: true on every note after the first of a chord's noteSet
  end

  @note_values %{
    # value -> {MusicXML type, beats} — observed facts only (see moduledoc)
    6.0 => {:quarter, 1.0},
    7.0 => {:half, 2.0}
  }

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
