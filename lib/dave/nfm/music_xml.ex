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
  #
  # A two-staff part (piano) writes staff 1's notes, a <backup> of the whole
  # measure, then staff 2's, every note saying its <staff>. Voices are
  # numbered 1-4 on staff 1 and 5-8 on staff 2, the MusicXML convention,
  # so OSMD never merges the hands into one voice.
  defp measures_xml(%Score{} = score, %Part{} = part, part_index) do
    by_index =
      part.measures
      |> Enum.group_by(& &1.index)
      |> Enum.sort_by(fn {index, _} -> index end)

    {measures, _prev_clefs} =
      Enum.map_reduce(by_index, nil, fn {index, staff_measures}, prev_clefs ->
        staff_measures = Enum.sort_by(staff_measures, & &1.staff)
        clefs = Enum.map(staff_measures, &clef_xml(&1, part))

        attrs =
          cond do
            index == 0 ->
              [first_attributes_xml(score, part, clefs)]

            clefs != prev_clefs ->
              changed =
                Enum.zip(clefs, prev_clefs)
                |> Enum.reject(fn {c, p} -> c == p end)
                |> Enum.map(fn {c, _} -> c end)

              [{"attributes", [], changed}]

            true ->
              []
          end

        direction = direction_xml(score, index, part_index) |> List.wrap()

        notes =
          staff_measures
          |> Enum.map(fn m -> Enum.map(m.notes, &note_xml(&1, part, m.staff)) end)
          |> Enum.intersperse([backup_xml(score)])
          |> List.flatten()

        {{"measure", [{"number", Integer.to_string(index + 1)}], attrs ++ direction ++ notes},
         clefs}
      end)

    measures
  end

  defp backup_xml(%Score{} = score) do
    {"backup", [], [{"duration", [], [Integer.to_string(measure_divisions(score))]}]}
  end

  defp measure_divisions(%Score{beats: beats, beat_type: beat_type}),
    do: round(@divisions * beats * 4 / beat_type)

  defp first_attributes_xml(%Score{} = score, %Part{staves: staves}, clefs) do
    {"attributes", [],
     [
       {"divisions", [], [Integer.to_string(@divisions)]},
       {"key", [], [{"fifths", [], [Integer.to_string(score.fifths)]}]},
       {"time", [],
        [
          {"beats", [], [Integer.to_string(score.beats)]},
          {"beat-type", [], [Integer.to_string(score.beat_type)]}
        ]},
       if(staves > 1, do: {"staves", [], [Integer.to_string(staves)]})
     ]
     |> Enum.reject(&is_nil/1)
     |> Kernel.++(clefs)}
  end

  defp clef_xml(%Measure{clef: nil} = m, %Part{} = part) do
    # Xylophone parts with no explicit clef default to treble: G on line 2
    {"clef", clef_number(m, part), [{"sign", [], ["G"]}, {"line", [], ["2"]}]}
  end

  defp clef_xml(%Measure{clef: clef} = m, %Part{} = part) do
    {"clef", clef_number(m, part),
     [{"sign", [], [clef.sign]}, {"line", [], [Integer.to_string(clef.line)]}]}
  end

  defp clef_number(%Measure{staff: staff}, %Part{staves: staves}) when staves > 1,
    do: [{"number", Integer.to_string(staff)}]

  defp clef_number(_measure, _part), do: []

  # Tempo markings in part 1 only, at the first measure and at every
  # change (Score.tempos): OSMD reads the <sound> for playback tempo and
  # the metronome shows visually.
  defp direction_xml(%Score{tempos: tempos}, index, 0) do
    case List.keyfind(tempos, index, 0) do
      {^index, bpm} -> tempo_direction(bpm)
      nil -> []
    end
  end

  defp direction_xml(_score, _index, _part_index), do: []

  defp tempo_direction(bpm) do
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

  defp note_xml(%Note{measure_rest: true} = note, part, staff) do
    {"note", [],
     [
       {"rest", [{"measure", "yes"}], []},
       {"duration", [], [Integer.to_string(duration!(note))]},
       {"voice", [], [voice_number(note, part, staff)]}
     ]
     |> Kernel.++(staff_xml(part, staff))}
  end

  # MusicXML's element order inside <note> is fixed: chord, pitch/rest,
  # duration, tie, voice, type, dot, time-modification, staff, notations,
  # lyric. OSMD ignores a time-modification placed after staff.
  defp note_xml(%Note{} = note, part, staff) do
    attrs = if(note.color, do: [{"color", note.color}], else: [])

    children =
      [
        if(note.chord, do: {"chord", [], []}),
        note_body(note),
        {"duration", [], [Integer.to_string(duration!(note))]},
        if(note.tie_stop, do: {"tie", [{"type", "stop"}], []}),
        if(note.tied, do: {"tie", [{"type", "start"}], []}),
        {"voice", [], [voice_number(note, part, staff)]}
      ]
      |> Enum.reject(&is_nil/1)
      |> Kernel.++(note_type_xml(note))
      |> Kernel.++(if(note.dotted, do: [{"dot", [], []}], else: []))
      |> Kernel.++(accidental_xml(note))
      |> Kernel.++(time_modification_xml(note))
      |> Kernel.++(staff_xml(part, staff))
      |> Kernel.++(notations_xml(note))
      |> Kernel.++(lyrics_xml(note))

    {"note", attrs, children}
  end

  # the staff is the Measure's, not the Note's, so it rides along as an argument
  defp staff_xml(%Part{staves: staves}, staff) when staves > 1,
    do: [{"staff", [], [Integer.to_string(staff)]}]

  defp staff_xml(_part, _staff), do: []

  defp voice_number(%Note{voice: voice}, %Part{staves: staves}, staff) when staves > 1,
    do: Integer.to_string((staff - 1) * 4 + voice)

  defp voice_number(%Note{voice: voice}, _part, _staff), do: Integer.to_string(voice)

  # the mark Noteflight engraves, where it engraves it: MusicXML's names
  # are the same words except for the doubles
  @accidental_names %{
    "sharp" => "sharp",
    "flat" => "flat",
    "natural" => "natural",
    "doubleSharp" => "double-sharp",
    "doubleFlat" => "flat-flat"
  }

  defp accidental_xml(%Note{pitch: %{accidental: acc}}) when is_binary(acc),
    do: [{"accidental", [], [Map.fetch!(@accidental_names, acc)]}]

  defp accidental_xml(_note), do: []

  defp time_modification_xml(%Note{tuplet: nil}), do: []

  defp time_modification_xml(%Note{tuplet: t}) do
    [
      {"time-modification", [],
       [
         {"actual-notes", [], [Integer.to_string(t.actual)]},
         {"normal-notes", [], [Integer.to_string(t.normal)]}
       ]}
    ]
  end

  defp notations_xml(%Note{} = note) do
    items =
      Enum.reject(
        [
          if(note.tie_stop, do: {"tied", [{"type", "stop"}], []}),
          if(note.tied, do: {"tied", [{"type", "start"}], []}),
          tuplet_notation(note, "start", note.tuplet && note.tuplet.start),
          tuplet_notation(note, "stop", note.tuplet && note.tuplet.stop)
        ],
        &is_nil/1
      )

    if items == [], do: [], else: [{"notations", [], items}]
  end

  defp tuplet_notation(_note, _type, false), do: nil
  defp tuplet_notation(_note, _type, nil), do: nil

  defp tuplet_notation(%Note{tuplet: t}, type, true),
    do: {"tuplet", [{"type", type}, {"bracket", if(t.bracket, do: "yes", else: "no")}], []}

  defp lyrics_xml(%Note{lyrics: lyrics}) do
    Enum.map(lyrics, fn lyric ->
      attrs =
        [{"number", Integer.to_string(lyric.number)}] ++
          if(lyric.color, do: [{"color", lyric.color}], else: []) ++
          if(lyric[:placement], do: [{"placement", lyric.placement}], else: [])

      {"lyric", attrs,
       [
         {"syllabic", [], [lyric.syllabic]},
         {"text", [], [escape(lyric.text)]},
         if(lyric.extend, do: {"extend", [], []})
       ]
       |> Enum.reject(&is_nil/1)}
    end)
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
