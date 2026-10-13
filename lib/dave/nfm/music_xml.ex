defmodule Dave.NFM.MusicXML do
  @moduledoc """
  `Dave.NFM` structs into MusicXML for OpenSheetMusicDisplay.

  Divisions are 48 per quarter, so `value * 8` is an integer down to
  128th notes (the NFMXML ladder bottoms out at 0.1875 = 1.5 divisions).
  """

  alias Dave.NFM.{Measure, Note, Part, Score}

  @divisions 48

  # NFMXML value is an enum (6 = quarter, 7 = half; see Dave.NFM). The type
  # and beats come from Dave.NFM.note_value/1 — observed facts only.

  @doc """
  Render the score as MusicXML. `part_indices` picks parts (for a kid's
  single-part view); `nil` renders all of them (the master view).
  """
  def to_music_xml(score, part_indices \\ nil)

  def to_music_xml(%Score{parts: parts} = score, nil) do
    to_music_xml(score, Enum.to_list(0..(length(parts) - 1)//1))
  end

  def to_music_xml(%Score{parts: parts} = score, part_indices) do
    selected = Enum.map(part_indices, &Enum.at(parts, &1))

    [
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
      "<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">",
      {"score-partwise", [{"version", "4.0"}],
       [
         {"work", [], [{"work-title", [], [escape(score.title)]}]},
         {"identification", [], [{"creator", [{"type", "composer"}], [escape(score.composer)]}]},
         {"part-list", [], part_list(selected)},
         parts_xml(score, part_indices, selected)
       ]}
    ]
    |> render()
  end

  defp part_list(selected) do
    selected
    |> Enum.with_index()
    |> Enum.map(fn {%Part{} = part, j} ->
      i = j + 1

      {"score-part", [{"id", "P#{i}"}],
       [
         {"part-name", [], [escape(part.name)]},
         {"part-abbreviation", [], [escape(part.short_name)]}
       ]}
    end)
  end

  defp parts_xml(score, part_indices, selected) do
    part_indices
    |> Enum.zip(selected)
    |> Enum.with_index()
    |> Enum.map(fn {{idx, %Part{} = part}, j} ->
      {"part", [{"id", "P#{j + 1}"}], measures_xml(score, part, idx)}
    end)
  end

  # NFMXML repeats the clef in every measure's <attributes>. MusicXML reads an
  # <attributes> as a change, and OSMD engraves a fresh clef and time
  # signature wherever it finds one, so copying NFMXML's habit put a treble
  # clef and a 4/4 at the start of every bar. Here: everything in measure 1,
  # after that only a clef, and only when it differs from the bar before.
  defp measures_xml(%Score{} = score, %Part{} = part, part_index) do
    {measures, _prev_clef} =
      Enum.map_reduce(part.measures, nil, fn %Measure{} = m, prev_clef ->
        clef = clef_xml(m, part)

        attrs =
          cond do
            m.index == 0 -> [first_attributes_xml(score, clef)]
            clef != prev_clef -> [{"attributes", [], [clef]}]
            true -> []
          end

        direction = direction_xml(score, m, part_index) |> List.wrap()
        notes = Enum.map(m.notes, &note_xml/1)

        {{"measure", [{"number", Integer.to_string(m.index + 1)}], attrs ++ direction ++ notes},
         clef}
      end)

    measures
  end

  defp first_attributes_xml(%Score{} = score, clef) do
    {"attributes", [],
     [
       {"divisions", [], [Integer.to_string(@divisions)]},
       {"key", [], [{"fifths", [], [Integer.to_string(score.fifths)]}]},
       {"time", [],
        [
          {"beats", [], [Integer.to_string(score.beats)]},
          {"beat-type", [], [Integer.to_string(score.beat_type)]}
        ]},
       clef
     ]}
  end

  defp clef_xml(%Measure{clef: nil}, %Part{}) do
    # Xylophone parts with no explicit clef default to treble
    {"clef", [], [{"sign", [], ["G"]}, {"line", [], ["1"]}]}
  end

  defp clef_xml(%Measure{clef: clef}, %Part{}) do
    {"clef", [], [{"sign", [], [clef.sign]}, {"line", [], [Integer.to_string(clef.line)]}]}
  end

  # Tempo marking only once, in part 1's first measure: OSMD reads the
  # <sound> for playback tempo and the metronome shows visually.
  defp direction_xml(%Score{bpm: bpm}, %Measure{index: 0}, 0) do
    bpm_str = Integer.to_string(round(bpm))

    {
      "direction",
      [{"placement", "above"}],
      [
        {
          "direction-type",
          [],
          [
            {
              "metronome",
              [],
              [
                {"beat-unit", [], ["quarter"]},
                {"per-minute", [], [bpm_str]}
              ]
            }
          ]
        },
        {"sound", [{"tempo", bpm_str}], []}
      ]
    }
  end

  defp direction_xml(_score, _measure, _part_index), do: []

  defp note_xml(%Note{measure_rest: true} = note) do
    {"note", [],
     [
       {"rest", [{"measure", "yes"}], []},
       {"duration", [], [Integer.to_string(duration!(note))]},
       {"voice", [], [Integer.to_string(note.voice)]}
     ]}
  end

  defp note_xml(%Note{} = note) do
    attrs = if(note.color, do: [{"color", note.color}], else: [])

    children =
      [
        if(note.chord, do: {"chord", [], []}),
        note_body(note),
        {"duration", [], [Integer.to_string(duration!(note))]},
        if(note.tie_stop, do: {"tie", [{"type", "stop"}], []}),
        if(note.tied, do: {"tie", [{"type", "start"}], []}),
        {"voice", [], [Integer.to_string(note.voice)]}
      ]
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(note_type_xml(note))
      |> Kernel.++(if(note.dotted, do: [{"dot", [], []}], else: []))
      |> Kernel.++(tied_notations(note))
      |> Kernel.++(lyric_xml(note))

    {"note", attrs, children}
  end

  defp tied_notations(%Note{tied: false, tie_stop: false}), do: []

  defp tied_notations(note) do
    [
      {"notations", [],
       Enum.reject(
         [
           if(note.tie_stop, do: {"tied", [{"type", "stop"}], []}),
           if(note.tied, do: {"tied", [{"type", "start"}], []})
         ],
         &is_nil/1
       )}
    ]
  end

  defp lyric_xml(%Note{lyric: nil}), do: []

  defp lyric_xml(%Note{lyric: lyric}) do
    attrs = [{"number", "1"}] ++ if(lyric.color, do: [{"color", lyric.color}], else: [])
    [{"lyric", attrs, [{"syllabic", [], ["single"]}, {"text", [], [escape(lyric.text)]}]}]
  end

  defp note_body(%Note{pitch: nil}), do: {"rest", [], []}

  defp note_body(%Note{pitch: p}) do
    {"pitch", [],
     [
       {"step", [], [p.step]},
       if(p.alter != 0, do: {"alter", [], [Integer.to_string(p.alter)]}),
       {"octave", [], [Integer.to_string(p.octave)]}
     ]
     |> Enum.reject(&is_nil/1)}
  end

  defp note_type_xml(%Note{value: value}) do
    {type, _beats} = Dave.NFM.note_value(value)
    [{"type", [], [Atom.to_string(type)]}]
  end

  defp duration!(%Note{} = note), do: round(@divisions * Dave.NFM.beats(note))

  defp escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp render(node) when is_list(node), do: IO.iodata_to_binary(render_list(node))
  defp render(node) when is_binary(node), do: node

  defp render_list(list) when is_list(list), do: Enum.map(list, &render_one/1)

  defp render_one({tag, attrs, []}) do
    attr_str =
      attrs
      |> Enum.map(fn {k, v} -> [" ", k, "=", "\"", v, "\""] end)
      |> IO.iodata_to_binary()

    ["<", tag, attr_str, "/>"]
  end

  defp render_one({tag, attrs, children}) do
    attr_str =
      attrs
      |> Enum.map(fn {k, v} -> [" ", k, "=", "\"", v, "\""] end)
      |> IO.iodata_to_binary()

    ["<", tag, attr_str, ">", render_list(List.wrap(children)), "</", tag, ">"]
  end

  defp render_one(text) when is_binary(text), do: text

  # charlists that slipped into the tree (~c"..."), e.g. the XML header
  defp render_one(i) when is_list(i) and is_integer(hd(i)), do: to_string(i)

  # nested lists from helpers returning their own element lists
  defp render_one(other) when is_list(other), do: IO.iodata_to_binary(render_list(other))
end
