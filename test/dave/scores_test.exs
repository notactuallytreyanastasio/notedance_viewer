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

  test "get_score! by slug, get_part! by index" do
    score = Scores.import_xml(@host, @id, @nfmxml)
    assert score.slug =~ ~r/^[a-z]+-[a-z]+$/

    assert Scores.get_score!(score.slug).noteflight_id == @id
    assert Scores.get_score_by_noteflight_id!(@id).slug == score.slug

    part = Scores.get_part!(score.slug, 1)
    assert part.name == "Alto / Tenor Xylophone"

    assert_raise Ecto.NoResultsError, fn ->
      Scores.get_part!(score.slug, 9)
    end
  end

  test "a Noteflight import gets two words; the example is always little-lamb" do
    score = Scores.import_xml(@host, @id, @nfmxml)
    [adjective, animal] = String.split(score.slug, "-")
    assert adjective != "" and animal != ""
    refute score.slug == "little-lamb"

    assert Scores.import_example().slug == "little-lamb"
  end

  test "re-import keeps the slug the kids already typed" do
    first = Scores.import_xml(@host, @id, @nfmxml)
    second = Scores.import_xml(@host, @id, @nfmxml)
    assert second.slug == first.slug
  end

  test "slug: lookup ignores case, hyphens and spaces" do
    score = Scores.import_xml(@host, @id, @nfmxml)
    [a, b] = String.split(score.slug, "-")

    for typed <- [a <> b, String.upcase(score.slug), "#{a} #{b}", " #{a}-#{b} "] do
      assert Scores.get_score!(typed).id == score.id, typed
    end
  end

  test "list_scores is newest first with parts preloaded" do
    Scores.import_xml(@host, @id, @nfmxml)
    [score] = Scores.list_scores()
    assert length(score.parts) == 3
  end

  test "import_from_url turns a non-score link into a sentence for Dave" do
    assert_raise Scores.ImportError, ~r/not a Noteflight score link/, fn ->
      Scores.import_from_url("https://example.com/not-a-score")
    end
  end

  test "delete_score! removes the song and its parts" do
    score = Scores.import_xml(@host, @id, @nfmxml)
    assert %Score{} = Scores.delete_score!(score.slug)
    assert Repo.all(Score) == []
    assert Repo.all(Part) == []
  end
end
