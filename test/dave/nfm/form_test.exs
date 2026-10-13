defmodule Dave.NFM.FormTest do
  use ExUnit.Case, async: true

  alias Dave.NFM.{Chord, Form}

  defp m(bar, kind), do: %{bar: bar, kind: kind}

  test "no marks: the bars in order" do
    assert Form.unroll([], 4) == [0, 1, 2, 3]
  end

  test "an end repeat with no start goes back to bar 1, once (Twinkle)" do
    assert Form.unroll([m(13, :end_repeat)], 13) == Enum.to_list(0..12) ++ Enum.to_list(0..12)
  end

  test "a repeat between its signs" do
    assert Form.unroll([m(3, :start_repeat), m(4, :end_repeat)], 6) == [0, 1, 2, 3, 2, 3, 4, 5]
  end

  test "D.S. al Coda: back to the segno, To Coda jumps to the coda, the coda's repeat is taken (Nine to Five)" do
    marks = [
      m(5, :segno),
      m(12, :to_coda),
      m(30, :ds_al_coda),
      m(31, :start_repeat),
      m(31, :coda),
      m(38, :end_repeat)
    ]

    order = Form.unroll(marks, 38)
    assert order == Enum.to_list(0..29) ++ Enum.to_list(4..11) ++ Enum.to_list(30..37) ++ Enum.to_list(30..37)
    assert length(order) == 54
  end

  test "D.C. al Fine: from the top, stop at Fine; Fine before the jump is just a word" do
    assert Form.unroll([m(2, :fine), m(4, :dc_al_fine)], 4) == [0, 1, 2, 3, 0, 1]
  end

  test "a repeat already played is not played again after a D.S." do
    marks = [m(1, :segno), m(2, :end_repeat), m(4, :ds)]
    assert Form.unroll(marks, 4) == [0, 1, 0, 1, 2, 3, 0, 1, 2, 3]
  end

  test "describe names the marks for the import flash" do
    assert Form.describe([]) == nil
    assert Form.describe([m(13, :end_repeat)]) =~ "a repeat of bars 1 to 13"
    assert Form.describe([m(5, :segno), m(30, :ds_al_coda)]) =~ "a segno at bar 5, “D.S. al Coda” at bar 30"
  end

  test "chord symbols split into root, kind and bass" do
    assert Chord.parse("A7/C#") == %{root: {"A", 0}, kind: "dominant", bass: {"C", 1}, text: "A7/C#"}
    assert Chord.parse("Am7b5").kind == "half-diminished"
    assert Chord.parse("Fdim7").kind == "diminished-seventh"
    assert Chord.parse("Bb").root == {"B", -1}
    assert Chord.parse("G").bass == nil

    assert_raise ArgumentError, ~r/TODO: chord kind "13"/, fn -> Chord.parse("G13") end
  end
end
