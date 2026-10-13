defmodule Dave.ScoresTest do
  use Dave.DataCase, async: true

  alias Dave.Scores
  alias Dave.Scores.{Part, Score}

  @nfmxml File.read!("test/support/fixtures/mary_had_a_little_lamb.nfmxml")
  @host "test.learning.noteflight.com"
  @id "eea68d68d65a761a2d228b73163cee89518a66c4"

  test "import_xml persists a score with all its parts, xml and timeline" do
    score = Scores.import_xml(@host, @id, @nfmxml)

    assert score.title == "Mary Had a Little Lamb - Xylophone"
    assert score.bpm == 90.0
    assert score.timeline["measure_ms"] == 2667
    assert score.music_xml =~ "<part-name>Soprano Xylophone</part-name>"

    assert Enum.map(score.parts, &{&1.index, &1.name}) == [
             {0, "Soprano Xylophone"},
             {1, "Alto / Tenor Xylophone"},
             {2, "Bass Xylophone"}
           ]

    bass = Enum.find(score.parts, &(&1.index == 2))
    assert bass.music_xml =~ "<part-name>Bass Xylophone</part-name>"
    refute bass.music_xml =~ "<part-name>Soprano Xylophone</part-name>"
  end

  test "re-import updates in place instead of duplicating" do
    Scores.import_xml(@host, @id, @nfmxml)
    Scores.import_xml(@host, @id, @nfmxml)

    assert Repo.all(Score) |> length() == 1
    assert Repo.all(Part) |> length() == 3
  end

  test "get_score! by noteflight id, get_part! by index" do
    Scores.import_xml(@host, @id, @nfmxml)

    score = Scores.get_score!(@id)
    assert score.noteflight_id == @id

    part = Scores.get_part!(@id, 1)
    assert part.name == "Alto / Tenor Xylophone"

    assert_raise Ecto.NoResultsError, fn ->
      Scores.get_part!(@id, 9)
    end
  end

  test "list_scores is newest first with parts preloaded" do
    Scores.import_xml(@host, @id, @nfmxml)
    [score] = Scores.list_scores()
    assert length(score.parts) == 3
  end

  test "import_from_url rejects non-Noteflight URLs loudly" do
    assert_raise Dave.Scores.ImportError, ~r/not a Noteflight score URL/, fn ->
      Scores.import_from_url("https://example.com/scores/view/whatever")
    end
  end
end
