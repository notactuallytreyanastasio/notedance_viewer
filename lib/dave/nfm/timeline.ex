defmodule Dave.NFM.Timeline do
  @moduledoc """
  The `Dave.NFM` score as a JSON-shaped timeline: every measure's start time
  and every part's notes as onsets in milliseconds — rests included, because
  the cursor steps on them too, with `"midi": null` so the synth skips them.

  A tempo change (`Score.tempos`, Nine to Five goes 100 to 70 at bar 3)
  changes the length of every bar from there on, so bar starts are summed
  bar by bar rather than multiplied. `measure_ms` stays as the FIRST
  tempo's bar length for the older pages; `duration_ms` is the real end.

  Repeats and jumps (`Score.form`) are unrolled by `Dave.NFM.Form`: a
  bar played twice has its notes twice, at two `ms`. Every note also
  carries `lin`, its onset on a straight read-through, which is the
  clock the OSMD cursor walks: the pages map `ms` to `lin` to the
  cursor step, and jump the cursor back when `lin` goes backwards.
  `playback` is the bar order with starts; `measures` keeps each bar's
  first start for the TV's "start from" buttons.
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

    ms_per_quarter = fn i -> 60_000.0 / tempo_at(score, i) end
    bar_ms = fn i -> quarters_per_measure * ms_per_quarter.(i) end

    # a straight read-through: where each bar sits on the page's own clock
    {linear_starts, _} =
      Enum.map_reduce(0..(measure_count - 1)//1, 0.0, fn i, start -> {start, start + bar_ms.(i)} end)

    linear_starts = List.to_tuple(linear_starts)

    # the order the bars are played, with repeats and jumps unrolled
    order = NFM.Form.unroll(score.form, measure_count)

    {playback, duration_ms} =
      Enum.map_reduce(order, 0.0, fn i, start -> {{i, start}, start + bar_ms.(i)} end)

    # the first time each bar is played, for the TV's "start from" buttons
    first_pass =
      Enum.reduce(playback, %{}, fn {i, start}, acc -> Map.put_new(acc, i, start) end)

    measures =
      for i <- 0..(measure_count - 1)//1 do
        %{"i" => i, "start_ms" => round(Map.fetch!(first_pass, i))}
      end

    parts =
      score.parts
      |> Enum.with_index()
      |> Map.new(fn {part, idx} ->
        by_index = Enum.group_by(part.measures, & &1.index)

        notes =
          for {i, start} <- playback,
              m <- Map.get(by_index, i, []),
              n <- m.notes do
            mpq = ms_per_quarter.(i)
            offset = n.position / NFM.quarter_position() * mpq
            beats = NFM.beats(n)

            %{
              "ms" => round(start + offset),
              # the same onset on a straight read: the cursor's own clock
              "lin" => round(elem(linear_starts, i) + offset),
              "end" => round(start + offset + beats * mpq),
              "midi" => (n.pitch && midi(n.pitch)) || nil,
              "m" => i
            }
          end
          # a two-staff part lists the left hand after the right; the
          # cursor wants one time-ordered stream
          |> Enum.sort_by(&{&1["ms"], &1["m"]})

        {Integer.to_string(idx),
         %{"name" => part.name, "short_name" => part.short_name, "notes" => notes}}
      end)

    %{
      "bpm" => score.bpm,
      "beats" => score.beats,
      "beat_type" => score.beat_type,
      "measure_ms" => round(bar_ms.(0)),
      "duration_ms" => round(duration_ms),
      "measures" => measures,
      "playback" => Enum.map(playback, fn {i, start} -> %{"m" => i, "start_ms" => round(start)} end),
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
