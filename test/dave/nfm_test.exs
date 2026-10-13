defmodule Dave.NFMTest do
  use ExUnit.Case, async: true

  alias Dave.NFM
  alias Dave.NFM.{Fetch, MusicXML, Parser, Timeline}

  @compressed File.read!("test/support/fixtures/mary_had_a_little_lamb.compressed.xml")
  @nfmxml File.read!("test/support/fixtures/mary_had_a_little_lamb.nfmxml")
  # Dave's first two real scores, the ones that stopped the reader on
  # 2026-10-13: letter-name lyrics, eighths, sixteenths, dots, ties, and
  # twelve empty measures for the bells.
  @mandalorian File.read!("test/support/fixtures/mandalorian.nfmxml")
  @mandalorian_v16 File.read!("test/support/fixtures/mandalorian_v16.nfmxml")
  @baby_shark File.read!("test/support/fixtures/baby_shark.nfmxml")

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

  test "content_url: the latest version from score_data, never a fixed number" do
    meta = %{
      "score_contents_url" => "https://h.learning.noteflight.com/score_content/abc/55",
      "score_latest_version" => %{"version_id" => 55}
    }

    assert Fetch.content_url("h.learning.noteflight.com", "abc", meta) =~
             ~r|/score_content/abc/55$|

    assert Fetch.version(meta) == 55

    assert Fetch.content_url("h.learning.noteflight.com", "abc", %{}) ==
             "https://h.learning.noteflight.com/score_content/abc"

    assert Fetch.version(%{}) == nil
  end

  test "the treble clef lands on MusicXML line 2, not Noteflight's zero-based 1" do
    for xml <- [@nfmxml, @mandalorian, @baby_shark] do
      musicxml = MusicXML.to_music_xml(Parser.parse(xml))
      assert musicxml =~ "<clef><sign>G</sign><line>2</line></clef>"
      refute musicxml =~ "<line>1</line>"
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

  test "note_value: the ladder 4..8, raises on the unobserved" do
    assert NFM.note_value(4.0) == {:"16th", 0.25}
    assert NFM.note_value(5.0) == {:eighth, 0.5}
    assert NFM.note_value(6.0) == {:quarter, 1.0}
    assert NFM.note_value(7.0) == {:half, 2.0}
    assert NFM.note_value(8.0) == {:whole, 4.0}

    assert_raise ArgumentError, ~r/TODO.*3\.0/, fn -> NFM.note_value(3.0) end
  end

  test "every real score's measures add up: onsets equal the running sum of lengths" do
    # the parser raises otherwise, so parsing is the assertion
    for xml <- [@nfmxml, @mandalorian, @baby_shark] do
      score = Parser.parse(xml)
      timeline = Timeline.build(score)
      measures = length(hd(score.parts).measures)

      last =
        timeline["parts"]
        |> Map.values()
        |> Enum.flat_map(& &1["notes"])
        |> Enum.map(& &1["end"])
        |> Enum.max()

      # measure_ms is rounded once; the onsets are rounded per note
      assert_in_delta last, 60_000 / score.bpm * 4 * measures, measures
    end
  end

  test "baby shark: eighths and wholes, ties across the barline" do
    score = Parser.parse(@baby_shark)
    assert score.bpm == 120.0
    notes = for p <- score.parts, m <- p.measures, n <- m.notes, do: n

    assert Enum.count(notes, &(&1.value == 5.0)) == 36
    assert Enum.count(notes, &(&1.value == 8.0)) == 3
    assert Enum.count(notes, & &1.tied) == 9
    assert Enum.count(notes, & &1.tie_stop) == 9

    musicxml = MusicXML.to_music_xml(score)
    assert musicxml =~ "<type>eighth</type>"
    assert musicxml =~ "<type>whole</type>"
    assert musicxml =~ ~s|<tie type="start"/>|
    assert musicxml =~ ~s|<notations><tied type="stop"/></notations>|
    assert {:ok, _} = Saxy.SimpleForm.parse_string(musicxml)
  end

  test "mandalorian v55: dotted eighths and sixteenths, bells resting whole measures, no lyrics" do
    score = Parser.parse(@mandalorian)
    [bells | _] = score.parts
    notes = for p <- score.parts, m <- p.measures, n <- m.notes, do: n

    assert Enum.count(bells.measures, &match?([%{measure_rest: true}], &1.notes)) == 6
    assert Enum.count(notes, & &1.measure_rest) == 11
    assert Enum.count(notes, & &1.dotted) == 11
    assert Enum.count(notes, &(&1.value == 4.0)) == 26
    # Dave's latest version dropped the letter lyrics (v16 still has them)
    assert Enum.count(notes, & &1.lyric) == 0
    # a dotted eighth is 0.75 beats; a 16th 0.25
    assert Enum.find(notes, &(&1.dotted and &1.value == 5.0)).beats == 0.75

    musicxml = MusicXML.to_music_xml(score, [0])
    assert musicxml =~ ~s|<rest measure="yes"/><duration>192</duration>|
    assert musicxml =~ "<type>16th</type>"
    assert musicxml =~ "<type>eighth</type><dot/>"
    assert {:ok, _} = Saxy.SimpleForm.parse_string(musicxml)
  end

  test "mandalorian v16: letter lyrics in Noteflight's #0x color spelling, placed when asked" do
    notes = for p <- Parser.parse(@mandalorian_v16).parts, m <- p.measures, n <- m.notes, do: n
    lyric = notes |> Enum.find(& &1.lyric) |> Map.fetch!(:lyric)
    assert lyric == %{text: "C", color: "#33BB33", placement: nil}

    musicxml = MusicXML.to_music_xml(Parser.parse(@mandalorian_v16), [0])

    assert musicxml =~
             ~s|<lyric number="1" color="#33BB33"><syllabic>single</syllabic><text>C</text></lyric>|

    refute musicxml =~ "#0x"

    # <direction>down</direction> inside a lyric is its placement
    placed =
      String.replace(
        @mandalorian_v16,
        "<lyric><text>C</text>",
        "<lyric><text>C</text><direction>down</direction>",
        global: false
      )

    assert MusicXML.to_music_xml(Parser.parse(placed), [0]) =~
             ~s|<lyric number="1" color="#33BB33" placement="below">|
  end

  test "a note that is not where the previous one ended is refused, not drawn short" do
    # take Mary's first measure and push the second note late
    broken =
      String.replace(@nfmxml, "<position>64</position>", "<position>96</position>", global: false)

    assert_raise ArgumentError, ~r/TODO: measure 1 note at position 96/, fn ->
      Parser.parse(broken)
    end
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

  test "musicxml: clef and time signature are written once, not per measure" do
    musicxml = MusicXML.to_music_xml(Parser.parse(@nfmxml), [0])

    # one part, 8 measures of the same treble clef: a single <attributes>
    assert length(String.split(musicxml, "<attributes>")) - 1 == 1
    assert length(String.split(musicxml, "<clef>")) - 1 == 1
    assert length(String.split(musicxml, "<time>")) - 1 == 1
  end

  test "musicxml: quarter is 48 divisions, half is 96, rests render" do
    musicxml = MusicXML.to_music_xml(Parser.parse(@nfmxml))

    assert musicxml =~ "<divisions>48</divisions>"
    assert musicxml =~ "<duration>48</duration><voice>1</voice><type>quarter</type>"
    assert musicxml =~ "<duration>96</duration><voice>1</voice><type>half</type>"
    assert musicxml =~ "<rest/>"
  end
end
