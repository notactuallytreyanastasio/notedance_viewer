defmodule Dave.NFMTest do
  use ExUnit.Case, async: true

  alias Dave.NFM
  alias Dave.NFM.{Fetch, MusicXML, Parser}

  @compressed File.read!("test/support/fixtures/mary_had_a_little_lamb.compressed.xml")
  @nfmxml File.read!("test/support/fixtures/mary_had_a_little_lamb.nfmxml")

  # The score the fixtures were taken from, fetched live while developing:
  # Burlington Public Schools, "Mary Had a Little Lamb - Xylophone",
  # https://mflms-bsdk5.learning.noteflight.com/scores/view/eea68d68d65a761a2d228b73163cee89518a66c4
  # 3 xylophone parts, 8 measures of 4/4, quarter notes, half notes, rests,
  # per-note colors (teacher color-codes the parts).

  test "inflate reverses the <noteflightCompressed> envelope" do
    assert Fetch.inflate(@compressed) == @nfmxml
  end

  test "parse_url extracts host and score id" do
    url =
      "https://mflms-bsdk5.learning.noteflight.com/scores/view/eea68d68d65a761a2d228b73163cee89518a66c4"

    assert Fetch.parse_url(url) ==
             {"mflms-bsdk5.learning.noteflight.com", "eea68d68d65a761a2d228b73163cee89518a66c4"}
  end

  test "parse_url takes what a browser address bar hands over" do
    host = "mflms-bsdk5.learning.noteflight.com"
    id = "eea68d68d65a761a2d228b73163cee89518a66c4"

    for url <- [
          "https://#{host}/scores/view/#{id}/",
          "https://#{host}/scores/view/#{id}?share=1&x=y",
          "https://#{host}/scores/view/#{id}#top",
          "  https://#{host}/scores/view/#{String.upcase(id)}\n"
        ] do
      assert Fetch.parse_url(url) == {host, id}, url
    end
  end

  test "parse_url rejects non-Noteflight URLs" do
    assert_raise ArgumentError, ~r/not a Noteflight score URL/, fn ->
      Fetch.parse_url("https://example.com/nope")
    end
  end

  test "parse: three parts, 8 measures each, 4/4, 90bpm" do
    score = Parser.parse(@nfmxml)

    assert score.title == "Mary Had a Little Lamb - Xylophone"
    assert score.composer == "Arr. Mr. Dave"
    assert {score.beats, score.beat_type} == {4, 4}
    assert score.fifths == 0
    assert score.bpm == 90.0

    assert Enum.map(score.parts, & &1.name) == [
             "Soprano Xylophone",
             "Alto / Tenor Xylophone",
             "Bass Xylophone"
           ]

    for part <- score.parts, do: assert(length(part.measures) == 8)
  end

  test "parse: first soprano note is D5 quarter, colored red" do
    note =
      Parser.parse(@nfmxml).parts
      |> hd()
      |> Map.fetch!(:measures)
      |> hd()
      |> Map.fetch!(:notes)
      |> hd()

    assert note.value == 6.0
    assert note.pitch == %{step: "D", alter: 0, octave: 5}
    assert note.color == "#ff0000"
  end

  test "parse: measure 8 is a half note and a half rest" do
    notes =
      Parser.parse(@nfmxml).parts
      |> hd()
      |> Map.fetch!(:measures)
      |> Enum.at(7)
      |> Map.fetch!(:notes)

    assert [%{value: 7.0, pitch: %{step: "B", octave: 4}}, %{value: 7.0, pitch: nil}] = notes
  end

  test "note_value: observed enum only, raises on the unobserved" do
    assert NFM.note_value(6.0) == {:quarter, 1.0}
    assert NFM.note_value(7.0) == {:half, 2.0}

    assert_raise ArgumentError, ~r/TODO.*8\.0/, fn -> NFM.note_value(8.0) end
  end

  test "musicxml: full score is well-formed and lists all parts" do
    score = Parser.parse(@nfmxml)
    musicxml = MusicXML.to_music_xml(score)

    assert {:ok, _} = Saxy.SimpleForm.parse_string(musicxml)
    assert musicxml =~ "<part-name>Soprano Xylophone</part-name>"
    assert musicxml =~ "<part-name>Alto / Tenor Xylophone</part-name>"
    assert musicxml =~ "<part-name>Bass Xylophone</part-name>"
    assert musicxml =~ ~s|<sound tempo="90"|
  end

  test "musicxml: single-part render carries exactly one part" do
    score = Parser.parse(@nfmxml)
    musicxml = MusicXML.to_music_xml(score, [2])

    assert {:ok, _} = Saxy.SimpleForm.parse_string(musicxml)
    assert musicxml =~ "<part-name>Bass Xylophone</part-name>"
    refute musicxml =~ "<part-name>Soprano Xylophone</part-name>"
  end

  test "musicxml: quarter is 48 divisions, half is 96, rests render" do
    musicxml = MusicXML.to_music_xml(Parser.parse(@nfmxml))

    assert musicxml =~ "<divisions>48</divisions>"
    assert musicxml =~ "<duration>48</duration><voice>1</voice><type>quarter</type>"
    assert musicxml =~ "<duration>96</duration><voice>1</voice><type>half</type>"
    assert musicxml =~ "<rest/>"
  end
end
