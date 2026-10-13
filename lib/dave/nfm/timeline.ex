defmodule Dave.NFM.Timeline do
  @moduledoc """
  The `Dave.NFM` score as a JSON-shaped timeline: every measure's start time
  and every part's notes as onsets in milliseconds — rests included, because
  the cursor steps on them too, with `"midi": null` so the synth skips them.

  Times are exact under the parser's single-tempo guarantee: a mid-piece
  tempo change raises back in `Dave.NFM.Parser`, so a uniform quarter-note
  pulse is all a timeline ever encodes.
  """

  alias Dave.NFM

  @step_semitones %{"C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11}

  def build(%NFM.Score{} = score) do
    ms_per_quarter = 60_000.0 / score.bpm
    # beats/beat_type quarter-notes per measure, e.g. 6/8 -> 3 quarters
    measure_ms = score.beats * 4.0 / score.beat_type * ms_per_quarter

    measure_count =
      score.parts |> Enum.map(&length(&1.measures)) |> Enum.max()

    measures =
      for i <- 0..(measure_count - 1) do
        %{"i" => i, "start_ms" => round(i * measure_ms)}
      end

    parts =
      score.parts
      |> Enum.with_index()
      |> Map.new(fn {part, idx} ->
        notes =
          for m <- part.measures, n <- m.notes do
            onset = m.index * measure_ms + n.position / NFM.quarter_position() * ms_per_quarter
            {_type, beats} = NFM.note_value(n.value)

            %{
              "ms" => round(onset),
              "end" => round(onset + beats * ms_per_quarter),
              "midi" => (n.pitch && midi(n.pitch)) || nil,
              "m" => m.index
            }
          end

        {Integer.to_string(idx),
         %{"name" => part.name, "short_name" => part.short_name, "notes" => notes}}
      end)

    %{
      "bpm" => score.bpm,
      "beats" => score.beats,
      "beat_type" => score.beat_type,
      "measure_ms" => round(measure_ms),
      "measures" => measures,
      "parts" => parts
    }
  end

  @doc "A pitch to a MIDI number: D5 -> 74."
  def midi(%{step: step, octave: octave, alter: alter}) do
    (octave + 1) * 12 + Map.fetch!(@step_semitones, step) + alter
  end
end
