defmodule Dave.NFM.TimelineTest do
  use ExUnit.Case, async: true

  alias Dave.NFM.{Parser, Timeline}

  @nfmxml File.read!("test/support/fixtures/mary_had_a_little_lamb.nfmxml")

  test "4/4 at 90bpm: 2667ms per measure, 8 measures, starts at multiples" do
    tl = Timeline.build(Parser.parse(@nfmxml))

    assert tl["bpm"] == 90.0
    assert tl["measure_ms"] == 2667
    assert length(tl["measures"]) == 8
    assert [0, 2667, 5333, 8000] == Enum.map(Enum.take(tl["measures"], 4), & &1["start_ms"])
  end

  test "parts carry names and notes with onsets, ends, midis and rests" do
    tl = Timeline.build(Parser.parse(@nfmxml))

    assert Map.keys(tl["parts"]) == ["0", "1", "2"]
    assert tl["parts"]["0"]["name"] == "Soprano Xylophone"

    notes = tl["parts"]["0"]["notes"]
    # quarter at 90bpm = 667ms
    [first, second, _third, _fourth | _] = notes

    assert first == %{"ms" => 0, "end" => 667, "midi" => 74, "m" => 0}
    assert second["ms"] == 667
    # m1 ("had a lit-tle LAMB") is quarter quarter half — the half note is
    # overall note index 6, on beat 3 of the measure
    half = Enum.at(notes, 6)
    assert half["ms"] == 4_000
    assert half["end"] - half["ms"] == 1_333
    # the last measure's half rest is in the timeline with midi nil
    rest = List.last(notes)
    assert rest["midi"] == nil
    assert rest["m"] == 7
  end

  test "D5 is midi 74, A4 is 69, and accidentals shift" do
    assert Timeline.midi(%{step: "D", octave: 5, alter: 0}) == 74
    assert Timeline.midi(%{step: "A", octave: 4, alter: 0}) == 69
    assert Timeline.midi(%{step: "A", octave: 4, alter: 1}) == 70
  end
end
