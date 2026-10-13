defmodule Dave.NFM.Parser do
  @moduledoc """
  NFMXML (Noteflight native XML) into `Dave.NFM` structs.

  Strict on purpose: anything the parser has not met on a real classroom
  score (tempo changes, unknown noteSet children, a note whose position
  is not where the previous note ended) raises with the offending node,
  per house style — a crash is a work item, a silent misparse is a hidden
  bug.

  `<beam/>` is accepted and dropped: it is an empty marker whose meaning
  (start? member?) nothing confirms, and OSMD beams eighths itself with
  autoBeam. Second voices are refused until a score has one; the MusicXML
  writer has no <backup>.
  """

  alias Dave.NFM
  alias Dave.NFM.{Part, Score, Note, Measure}

  @accidentals %{
    "sharp" => 1,
    "doubleSharp" => 2,
    "flat" => -1,
    "doubleFlat" => -2,
    "natural" => 0
  }

  @known_noteset_children ~w(value position color note beam dotted lyric)
  @known_note_children ~w(pitch step noteHead accidental tied)

  def parse(xml) do
    {:ok, doc} = Saxy.SimpleForm.parse_string(xml)
    parse_score(doc)
  end

  defp parse_score({"noteflightScore", _, children} = doc) do
    {beats, beat_type} = time_signature!(children)
    {fifths, mode} = key_signature!(children)
    {tempo_value, bpm} = tempo!(children)

    measure_beats = beats * 4 / beat_type

    parts =
      children
      |> all("part")
      |> with_index(&parse_part(&1, &2, measure_beats))

    %Score{
      title: text!(doc, "title"),
      composer: text(doc, "composer") || "",
      beats: beats,
      beat_type: beat_type,
      fifths: fifths,
      mode: mode,
      bpm: bpm_quarter(tempo_value, bpm),
      parts: parts
    }
  end

  # Time, key and tempo live in <systemPart>'s own staff of measures, not in
  # the parts. NFMXML duplicates the first measure's tempo into <notations>
  # too; we read <attributes> only and dedupe, so a real mid-piece tempo
  # change is what trips the raise.
  defp time_signature!(children) do
    ts =
      children
      |> system_measures()
      |> Enum.flat_map(&all(&1, "attributes"))
      |> Enum.flat_map(&all(&1, "timeSignature"))
      |> List.first()

    unless ts, do: raise(ArgumentError, "no time signature in systemPart")
    {text_to_int!(ts, "beats"), text_to_int!(ts, "beatType")}
  end

  defp key_signature!(children) do
    ks =
      children
      |> system_measures()
      |> Enum.flat_map(&all(&1, "attributes"))
      |> Enum.flat_map(&all(&1, "keySignature"))
      |> List.first()

    case ks do
      nil -> {0, "major"}
      ks -> {text_to_int!(ks, "fifths"), text(ks, "mode") || "major"}
    end
  end

  defp tempo!(children) do
    tempos =
      children
      |> system_measures()
      |> Enum.flat_map(fn m -> all(m, "attributes") end)
      |> Enum.flat_map(fn a -> all(a, "tempo") end)
      |> Enum.map(fn t -> {text_to_num!(t, "value"), text_to_num!(t, "bpm")} end)
      |> Enum.uniq()

    case tempos do
      [{value, bpm}] ->
        {value, bpm}

      [] ->
        raise(ArgumentError, "no tempo in systemPart")

      tempos ->
        raise(ArgumentError, "TODO: mid-piece tempo changes: #{inspect(tempos)}")
    end
  end

  # NFMXML expresses bpm relative to the tempo unit (<value>); MusicXML and
  # our timeline want quarter-note bpm. Observed tempo unit on the real
  # score: 6 (the quarter note enum value).
  defp bpm_quarter(value, bpm) do
    {_type, beats} = NFM.note_value(value)
    bpm * beats
  end

  defp system_measures(children) do
    case one(children, "systemPart") do
      nil ->
        raise(ArgumentError, "no systemPart (no place to read time/key/tempo)")

      sp ->
        sp |> kids() |> all("staff") |> Enum.flat_map(&all(&1, "measure"))
    end
  end

  defp parse_part({"part", _, children}, index, measure_beats) do
    staves = all(children, "staff")

    measures =
      staves
      |> Enum.flat_map(&all(&1, "measure"))
      |> with_index(&parse_measure(&1, &2, measure_beats))
      |> resolve_ties()

    %Part{
      nfm_id: text(children, "id") || "part-#{index}",
      name: text!(children, "name"),
      short_name: text(children, "shortName") || "",
      instrument_uri: text(children, "instrumentUri") || "",
      measures: measures
    }
  end

  defp parse_measure({"measure", _, children}, index, measure_beats) do
    clef =
      case attributes_clef(children) do
        nil -> nil
        c -> %{sign: text!(c, "sign"), line: text_to_int!(c, "line")}
      end

    voices =
      children
      |> one("voices")
      |> kids()
      |> all("voice")
      |> with_index(fn {"voice", _, voice_children}, voice ->
        case all(voice_children, "noteSet") do
          [] ->
            [measure_rest(voice + 1, measure_beats)]

          sets ->
            sets
            |> Enum.flat_map(&parse_note_set(&1, voice + 1))
            |> check_positions!(index, measure_beats)
        end
      end)

    case voices do
      [notes] ->
        %Measure{index: index, clef: clef, notes: notes}

      [notes | rest] ->
        if Enum.all?(rest, &match?([%Note{measure_rest: true}], &1)),
          do: %Measure{index: index, clef: clef, notes: notes},
          else:
            raise(
              ArgumentError,
              "TODO: measure #{index + 1} has #{length(voices)} voices with notes; " <>
                "the MusicXML writer has no <backup> yet"
            )
    end
  end

  # A <tied/> note ties to the next note of its pitch in the voice, across
  # the barline. Mark that note so the writer can close the tie; a tie left
  # open at the end of the part is a misread and raises.
  defp resolve_ties(measures) do
    {measures, open} =
      Enum.map_reduce(measures, MapSet.new(), fn measure, open ->
        {notes, open} =
          Enum.map_reduce(measure.notes, open, fn note, open ->
            key = note.pitch
            stop = key != nil and MapSet.member?(open, key)
            open = if stop, do: MapSet.delete(open, key), else: open
            open = if note.tied, do: MapSet.put(open, key), else: open
            {%{note | tie_stop: stop}, open}
          end)

        {%{measure | notes: notes}, open}
      end)

    if MapSet.size(open) > 0 do
      raise(ArgumentError, "TODO: tie never lands: #{inspect(MapSet.to_list(open))}")
    end

    measures
  end

  defp measure_rest(voice, measure_beats) do
    %Note{
      voice: voice,
      value: nil,
      position: 0,
      pitch: nil,
      color: nil,
      chord: false,
      measure_rest: true,
      beats: measure_beats
    }
  end

  # Every onset must be where the previous note ended. True on all three
  # real scores; a gap would mean an implicit rest NFMXML never writes, and
  # we would rather stop than draw a measure short.
  defp check_positions!(notes, index, measure_beats) do
    unit = NFM.quarter_position()

    {_cursor, notes} =
      Enum.reduce(notes, {0, []}, fn note, {cursor, acc} ->
        cond do
          note.chord ->
            {cursor, [note | acc]}

          note.position != cursor ->
            raise(
              ArgumentError,
              "TODO: measure #{index + 1} note at position #{note.position}, " <>
                "previous note ended at #{cursor} (implicit rest?) in #{inspect(note)}"
            )

          true ->
            {cursor + round(note.beats * unit), [note | acc]}
        end
      end)

    notes = Enum.reverse(notes)
    last_end = List.last(notes) |> then(&(&1.position + round(&1.beats * unit)))

    if last_end != round(measure_beats * unit) do
      raise(
        ArgumentError,
        "TODO: measure #{index + 1} ends at #{last_end}, expected #{round(measure_beats * unit)}"
      )
    end

    notes
  end

  defp attributes_clef(children) do
    children
    |> all("attributes")
    |> Enum.flat_map(&all(&1, "clef"))
    |> List.first()
  end

  defp parse_note_set({"noteSet", _, children} = node, voice) do
    assert_known_children!(node, children, @known_noteset_children)

    value = text_to_num!(node, "value")

    position =
      case text(children, "position") do
        nil -> 0
        s -> String.to_integer(s)
      end

    color = color(text(children, "color"))
    dotted = one(children, "dotted") != nil
    lyric = parse_lyric(one(children, "lyric"))

    base = %Note{
      voice: voice,
      value: value,
      position: position,
      pitch: nil,
      color: color,
      chord: false,
      dotted: dotted,
      lyric: lyric
    }

    base = %{base | beats: NFM.beats(base)}

    case all(children, "note") do
      [] ->
        [base]

      note_children ->
        note_children
        |> with_index(fn {"note", _, nc} = n, i ->
          # the lyric sits under the chord once, on its first note
          %{
            base
            | pitch: parse_pitch(n),
              chord: i > 0,
              tied: one(nc, "tied") != nil,
              lyric: if(i == 0, do: lyric, else: nil)
          }
        end)
    end
  end

  # <lyric><text>C</text><color>#0x33BB33</color></lyric>; the text can be
  # empty (Dave leaves a lyric slot on rests), which is no lyric at all.
  defp parse_lyric(nil), do: nil

  defp parse_lyric({"lyric", _, children} = node) do
    assert_known_children!(node, children, ~w(text color))

    case text(children, "text") do
      nil -> nil
      "" -> nil
      t -> %{text: t, color: color(text(children, "color"))}
    end
  end

  # Noteflight writes colors two ways on real scores: "#ff0000" and
  # "#0x33BB33". Only the first is a color to a browser.
  defp color(nil), do: nil
  defp color("#0x" <> hex), do: "#" <> hex
  defp color(c), do: c

  defp parse_pitch({"note", _, children} = node) do
    assert_known_children!(node, children, @known_note_children)

    name = text!(children, "pitch")
    step = text!(children, "step")

    unless step in ~w(A B C D E F G) do
      raise(ArgumentError, "unknown step: #{inspect(step)} in #{inspect(node)}")
    end

    alter =
      case all(children, "accidental") do
        [] ->
          0

        [a | _] ->
          acc = text!(a, "type")

          Map.fetch(@accidentals, acc) ||
            raise(ArgumentError, "TODO: accidental #{inspect(acc)} in #{inspect(node)}")
      end

    {octave, ""} = Integer.parse(String.replace_leading(name, step, ""))

    %{step: step, alter: alter, octave: octave}
  end

  defp assert_known_children!(_node, children, known) do
    for {tag, _, _} = child <- children, tag not in known do
      raise(ArgumentError, "TODO: <#{tag}> not handled yet, in #{inspect(child)}")
    end
  end

  defp with_index(list, fun),
    do: list |> Enum.with_index() |> Enum.map(fn {e, i} -> fun.(e, i) end)

  defp kids({_tag, _attrs, children}), do: children

  defp all(node_or_children, tag) when is_tuple(node_or_children),
    do: all(kids(node_or_children), tag)

  defp all(children, tag) when is_list(children),
    do: for({^tag, _, _} = e <- children, do: e)

  defp one(children, tag), do: children |> all(tag) |> List.first()

  defp text!(node_or_children, tag) do
    case text(node_or_children, tag) do
      nil -> raise(ArgumentError, "no <#{tag}> in #{inspect(node_or_children)}")
      t -> t
    end
  end

  defp text(node_or_children, tag) do
    case one(children_of(node_or_children), tag) do
      nil -> nil
      el -> el |> kids() |> texts()
    end
  end

  defp children_of(node_or_children) when is_tuple(node_or_children), do: kids(node_or_children)
  defp children_of(children) when is_list(children), do: children

  # Saxy.SimpleForm represents text content as a plain binary child.
  defp texts(children), do: for(t when is_binary(t) <- children, do: t) |> Enum.join()

  defp text_to_num!(node, tag) do
    case text(node, tag) |> to_float() do
      {:ok, f} -> f
      :error -> raise(ArgumentError, "<#{tag}> is not a number in #{inspect(node)}")
    end
  end

  defp text_to_int!(node, tag) do
    case text(node, tag) do
      nil -> raise(ArgumentError, "no <#{tag}> in #{inspect(node)}")
      s -> String.to_integer(s)
    end
  end

  defp to_float(nil), do: :error

  defp to_float(s) do
    case Integer.parse(s) do
      {i, ""} ->
        {:ok, i * 1.0}

      _ ->
        case Float.parse(s) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end
end
