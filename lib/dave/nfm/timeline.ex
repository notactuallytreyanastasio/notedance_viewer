defmodule Dave.NFM.Timeline do
  @moduledoc """
  The `Dave.NFM` score as a JSON-shaped timeline: every measure's start time
  and every part's notes as onsets in milliseconds — rests included, because
  the cursor steps on them too, with `"midi": null` so the synth skips them.

  A tempo change (`Score.tempos`, Nine to Five goes 100 to 70 at bar 3)
  changes the length of every bar from there on, so bar starts are summed
  bar by bar rather than multiplied. `measure_ms` stays as the FIRST
  tempo's bar length for the older pages; `duration_ms` is the real end.
  Repeats are not followed: the bars play once, in order, like the cursor.
  """

  alias Dave.NFM

  @step_semitones %{"C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11}

  def build(%NFM.Score{} = score) do
    # beats/beat_type quarter-notes per measure, e.g. 6/8 -> 3 quarters
    quarters_per_measure = score.beats * 4.0 / score.beat_type

    measure_count =
      score.parts
      |> Enum.map(fn part -> part.measures |> Enum.map(& &1.index) |> Enum.max(fn -> -1 end) end)
      |> Enum.max()
      |> Kernel.+(1)

    # {start_ms, ms_per_quarter} per measure, under the tempo in force there
    {clocks, duration_ms} =
      Enum.map_reduce(0..(measure_count - 1)//1, 0.0, fn i, start ->
        ms_per_quarter = 60_000.0 / tempo_at(score, i)
        {{start, ms_per_quarter}, start + quarters_per_measure * ms_per_quarter}
      end)

    clocks = List.to_tuple(clocks)

    measures =
      for i <- 0..(measure_count - 1)//1 do
        {start, _} = elem(clocks, i)
        %{"i" => i, "start_ms" => round(start)}
      end

    parts =
      score.parts
      |> Enum.with_index()
      |> Map.new(fn {part, idx} ->
        notes =
          for m <- part.measures, n <- m.notes do
            {start, ms_per_quarter} = elem(clocks, m.index)
            onset = start + n.position / NFM.quarter_position() * ms_per_quarter
            beats = NFM.beats(n)

            %{
              "ms" => round(onset),
              "end" => round(onset + beats * ms_per_quarter),
              "midi" => (n.pitch && midi(n.pitch)) || nil,
              "m" => m.index
            }
          end
          # a two-staff part lists the left hand after the right; the
          # cursor wants one time-ordered stream
          |> Enum.sort_by(&{&1["ms"], &1["m"]})

        {Integer.to_string(idx),
         %{"name" => part.name, "short_name" => part.short_name, "notes" => notes}}
      end)

    {_, first_ms_per_quarter} = elem(clocks, 0)

    %{
      "bpm" => score.bpm,
      "beats" => score.beats,
      "beat_type" => score.beat_type,
      "measure_ms" => round(quarters_per_measure * first_ms_per_quarter),
      "duration_ms" => round(duration_ms),
      "measures" => measures,
      "parts" => parts
    }
  end

  # the last tempo at or before measure i; Score.tempos starts at measure 0
  defp tempo_at(%NFM.Score{tempos: [], bpm: bpm}, _i), do: bpm

  defp tempo_at(%NFM.Score{tempos: tempos}, i) do
    tempos
    |> Enum.take_while(fn {at, _} -> at <= i end)
    |> List.last()
    |> elem(1)
  end

  @doc "A pitch to a MIDI number: D5 -> 74."
  def midi(%{step: step, octave: octave, alter: alter}) do
    (octave + 1) * 12 + Map.fetch!(@step_semitones, step) + alter
  end
end
