defmodule Dave.NFM.Parser do
  @moduledoc """
  NFMXML (Noteflight native XML) into `Dave.NFM` structs.

  Strict on purpose: anything the parser has not met on a real classroom
  score (unknown noteSet or voice children, a note whose position is not
  where the previous note ended) raises with the offending node, per
  house style — a crash is a work item, a silent misparse is a hidden bug.

  Repeat barlines, segno, coda and performance texts are the one
  exception: they are read and turned into `Score.warnings` sentences
  rather than a raise, because the score still reads correctly straight
  through, and the warning reaches Dave on the import flash.

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

  @step_semitones %{"C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11}

  @known_noteset_children ~w(value position color note beam dotted lyric)
  # explicitAccidental: the accidental is engraved even where the key makes
  # it redundant; the pitch is the same, so it is accepted and dropped
  @known_note_children ~w(pitch step noteHead accidental tied explicitAccidental)
  @known_lyric_children ~w(text color direction continued line extend)
  @known_tuplet_children ~w(position units unitValue rhythmUnits rhythmValue showBracket contents)
  # everything a measure can hold, listed from the seven real scores; an
  # ending (1st/2nd time), for one, has never been seen and must raise
  @known_system_measure_children ~w(attributes notations endRepeat startRepeat breakType layoutWeight)
  @known_part_measure_children ~w(voices attributes notations breakType)
  @known_system_notations ~w(barline timeSignature tempo segno coda)
  @known_part_notations ~w(chordSymbol performance)
  @known_system_attributes ~w(keySignature timeSignature tempo)
  @known_part_attributes ~w(clef)

  def parse(xml) do
    {:ok, doc} = Saxy.SimpleForm.parse_string(xml)
    parse_score(doc)
  end

  defp parse_score({"noteflightScore", _, children} = doc) do
    check_structure!(children)
    {beats, beat_type} = time_signature!(children)
    keys = keys!(children)
    [{0, fifths, mode} | _] = keys
    tempos = tempos!(children)
    [{0, bpm} | _] = tempos
    form = form_marks(children)

    measure_beats = beats * 4 / beat_type

    parts =
      children
      |> all("part")
      |> with_index(&parse_part(&1, &2, measure_beats))
      |> agree_on_bar_lengths(measure_beats)

    %Score{
      title: text!(doc, "title"),
      composer: text(doc, "composer") || "",
      beats: beats,
      beat_type: beat_type,
      fifths: fifths,
      mode: mode,
      bpm: bpm,
      tempos: tempos,
      keys: keys,
      parts: parts,
      form: form,
      barlines: barlines(children),
      warnings: Enum.reject([NFM.Form.describe(form)], &is_nil/1)
    }
  end

  # Repeats, segno and coda live in the systemPart's measures (barline
  # kinds as measure children, the signs under <notations>); the texts that
  # drive them ("To Coda", "D.S. al Coda") sit in a part's measure
  # notations, Nine to Five's Voice. Dave.NFM.Form turns them into a
  # playback order. A performance text we have not met raises.
  @performance_texts %{
    "To Coda" => :to_coda,
    "D.S. al Coda" => :ds_al_coda,
    "D.C. al Coda" => :dc_al_coda,
    "D.S. al Fine" => :ds_al_fine,
    "D.C. al Fine" => :dc_al_fine,
    "D.S." => :ds,
    "D.C." => :dc,
    "Fine" => :fine
  }

  # <notations><barline><type>double</type><position>256</position></barline>
  # on a systemPart measure; no <type> is the plain barline
  defp barlines(children) do
    children
    |> system_measures()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {{"measure", _, mc}, bar} ->
      notations = one(mc, "notations") |> then(&if(&1, do: kids(&1), else: []))

      case one(notations, "barline") do
        nil -> []
        b -> if(t = text(b, "type"), do: [{bar, t}], else: [])
      end
    end)
    |> Map.new()
  end

  defp form_marks(children) do
    part_measures =
      children
      |> all("part")
      |> Enum.flat_map(&all(&1, "staff"))
      |> Enum.flat_map(fn staff -> staff |> all("measure") |> Enum.with_index(1) end)

    (Enum.with_index(system_measures(children), 1) ++ part_measures)
    |> Enum.flat_map(fn {{"measure", _, mc}, bar} ->
      notations = one(mc, "notations") |> then(&if(&1, do: kids(&1), else: []))

      Enum.reject(
        [
          if(one(mc, "startRepeat"), do: :start_repeat),
          if(one(mc, "endRepeat"), do: :end_repeat),
          if(one(notations, "segno"), do: :segno),
          if(one(notations, "coda"), do: :coda)
        ] ++
          for {"performance", _, pc} = node <- notations do
            t = text(pc, "text") || ""

            Map.get(@performance_texts, String.trim(t)) ||
              raise(ArgumentError, "TODO: performance text #{inspect(t)} in #{inspect(node)}")
          end,
        &is_nil/1
      )
      |> Enum.map(&%{bar: bar, kind: &1})
    end)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.bar)
  end

  # Every measure, attributes and notations child must be one we have met
  # on a real score. Checked once, up front, so an unknown element names
  # itself before anything is read around it.
  defp check_structure!(children) do
    for {"measure", _, mc} = m <- system_measures(children) do
      assert_known_children!(m, mc, @known_system_measure_children)
      for {"notations", _, nc} = n <- all(mc, "notations"), do: assert_known_children!(n, nc, @known_system_notations)
      for {"attributes", _, ac} = a <- all(mc, "attributes"), do: assert_known_children!(a, ac, @known_system_attributes)
    end

    for part <- all(children, "part"),
        staff <- all(part, "staff"),
        {"measure", _, mc} = m <- all(staff, "measure") do
      assert_known_children!(m, mc, @known_part_measure_children)
      for {"notations", _, nc} = n <- all(mc, "notations"), do: assert_known_children!(n, nc, @known_part_notations)
      for {"attributes", _, ac} = a <- all(mc, "attributes"), do: assert_known_children!(a, ac, @known_part_attributes)
    end

    :ok
  end

  # Time, key and tempo live in <systemPart>'s own staff of measures, not in
  # the parts. NFMXML duplicates the first measure's tempo into <notations>
  # too; we read <attributes> only. One time signature for the whole
  # score: a change mid-piece has not been seen and would move every bar
  # length after it, so it raises.
  defp time_signature!(children) do
    sigs =
      children
      |> system_measures()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {m, bar} ->
        m
        |> all("attributes")
        |> Enum.flat_map(&all(&1, "timeSignature"))
        |> Enum.map(&{bar, {text_to_int!(&1, "beats"), text_to_int!(&1, "beatType")}})
      end)

    case Enum.uniq_by(sigs, fn {_, sig} -> sig end) do
      [{1, sig}] -> sig
      [] -> raise(ArgumentError, "no time signature in systemPart")
      [_ | [{bar, sig} | _]] -> raise(ArgumentError, "TODO: time signature changes to #{inspect(sig)} at bar #{bar}")
      [{bar, _}] -> raise(ArgumentError, "TODO: first time signature is at bar #{bar}, not 1")
    end
  end

  # Every <keySignature> in a systemPart measure's <attributes>, as
  # [{measure_index, fifths, mode}]; a repeat of the same key is dropped.
  # No key at all is C major.
  defp keys!(children) do
    keys =
      children
      |> system_measures()
      |> Enum.with_index()
      |> Enum.flat_map(fn {m, i} ->
        m
        |> all("attributes")
        |> Enum.flat_map(&all(&1, "keySignature"))
        |> Enum.map(&{i, text_to_int!(&1, "fifths"), text(&1, "mode") || "major"})
      end)
      |> Enum.dedup_by(fn {_, fifths, mode} -> {fifths, mode} end)

    case keys do
      [] -> [{0, 0, "major"}]
      [{0, _, _} | _] -> keys
      [{i, _, _} | _] -> raise(ArgumentError, "TODO: first key signature is at measure #{i + 1}, not 1")
    end
  end

  # Every <tempo> in a systemPart measure's <attributes>, as
  # [{measure_index, quarter_bpm}]. A tempo repeated unchanged is dropped;
  # the first measure must carry one, or the timeline has no clock.
  defp tempos!(children) do
    tempos =
      children
      |> system_measures()
      |> Enum.with_index()
      |> Enum.flat_map(fn {m, i} ->
        m
        |> all("attributes")
        |> Enum.flat_map(&all(&1, "tempo"))
        |> Enum.map(fn t -> {i, bpm_quarter(text_to_num!(t, "value"), text_to_num!(t, "bpm"))} end)
      end)
      |> Enum.dedup_by(fn {_i, bpm} -> bpm end)

    case tempos do
      [{0, _} | _] -> tempos
      [] -> raise(ArgumentError, "no tempo in systemPart")
      [{i, _} | _] -> raise(ArgumentError, "TODO: first tempo is at measure #{i + 1}, not 1")
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

  # A piano part has two <staff>s with the same number of measures. Ties
  # resolve within a staff: a tie open at the end of the right hand must
  # not land on the left hand's first bar. A clef is carried forward: the
  # xylophone scores repeat it in every bar, Nine to Five's piano writes
  # its bass clef once, in bar 1 (bar 2 drew a treble clef before this).
  defp parse_part({"part", _, children}, index, measure_beats) do
    staves = all(children, "staff")

    measures =
      staves
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {staff, staff_no} ->
        ms = all(staff, "measure")
        last = length(ms) - 1

        ms
        |> with_index(&parse_measure(&1, &2, measure_beats, &2 == last))
        |> Enum.map(&%{&1 | staff: staff_no})
        |> carry_clefs()
        |> resolve_ties()
      end)

    %Part{
      nfm_id: text(children, "id") || "part-#{index}",
      name: text!(children, "name"),
      short_name: text(children, "shortName") || "",
      instrument_uri: text(children, "instrumentUri") || "",
      measures: measures,
      staves: length(staves),
      hidden: one(children, "hidden") != nil
    }
  end

  # A short first or last bar is as long as its notes, and every part and
  # staff must agree on that length. A part whose bar is only a rest
  # takes the others' length (a piano's left hand resting through the
  # pickup); two parts with notes of different lengths in one bar is a
  # misread and raises.
  defp agree_on_bar_lengths(parts, measure_beats) do
    by_index = parts |> Enum.flat_map(& &1.measures) |> Enum.group_by(& &1.index)

    Enum.map(parts, fn part ->
      measures =
        Enum.map(part.measures, fn m ->
          played =
            by_index
            |> Map.fetch!(m.index)
            |> Enum.reject(&match?([%Note{measure_rest: true}], &1.notes))
            |> Enum.map(& &1.beats)
            |> Enum.uniq()

          case played do
            [] ->
              m

            [beats] ->
              if match?([%Note{measure_rest: true}], m.notes),
                do: %{m | beats: beats, notes: Enum.map(m.notes, &%{&1 | beats: beats})},
                else: m

            many ->
              raise(
                ArgumentError,
                "TODO: bar #{m.index + 1} is #{inspect(Enum.sort(many))} beats long in different parts (of #{measure_beats})"
              )
          end
        end)

      %{part | measures: measures}
    end)
  end

  defp carry_clefs(measures) do
    {measures, _} =
      Enum.map_reduce(measures, nil, fn m, prev ->
        clef = m.clef || prev
        {%{m | clef: clef}, clef}
      end)

    measures
  end

  defp parse_measure({"measure", _, children}, index, measure_beats, last?) do
    clef =
      case attributes_clef(children) do
        nil -> nil
        c -> clef!(c)
      end

    notations = one(children, "notations") |> then(&if(&1, do: kids(&1), else: []))

    chords =
      for {"chordSymbol", _, cc} <- notations do
        position = text(cc, "position") |> then(&if(&1, do: String.to_integer(&1), else: 0))
        %{position: position, chord: NFM.Chord.parse(text!(cc, "chord"))}
      end

    voices =
      children
      |> one("voices")
      |> kids()
      |> all("voice")
      |> with_index(fn {"voice", _, voice_children}, voice ->
        case voice_notes(voice_children, voice + 1) do
          [] ->
            {[measure_rest(voice + 1, measure_beats)], nil}

          notes ->
            check_positions!(notes, index, measure_beats, last?)
        end
      end)

    beats =
      voices |> Enum.map(fn {_, b} -> b end) |> Enum.reject(&is_nil/1) |> List.first() || measure_beats

    voices = Enum.map(voices, fn {notes, _} -> notes end)

    case voices do
      [notes] ->
        %Measure{index: index, clef: clef, notes: notes, chords: chords, beats: beats}

      [notes | rest] ->
        if Enum.all?(rest, &match?([%Note{measure_rest: true}], &1)),
          do: %Measure{index: index, clef: clef, notes: notes, chords: chords, beats: beats},
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
            # the same sounding pitch, marked or not: a tied Bb is engraved
            # with its flat in the first bar and bare in the next
            key = note.pitch && Map.take(note.pitch, [:step, :alter, :octave])
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

  # A voice's children in document order: noteSets, tuplets (whose own
  # noteSets take their place in the sequence), slurs (drawn, not timed:
  # dropped) and <tacet/> (a silent voice, like an empty one). Anything
  # else is unobserved and raises.
  defp voice_notes(voice_children, voice) do
    Enum.flat_map(voice_children, fn
      {"noteSet", _, _} = set -> parse_note_set(set, voice)
      {"tuplet", _, _} = tuplet -> parse_tuplet(tuplet, voice)
      {"slur", _, _} -> []
      {"tacet", _, _} -> []
      {tag, _, _} = child -> raise(ArgumentError, "TODO: <#{tag}> in a voice, in #{inspect(child)}")
    end)
  end

  # <tuplet><position>96</position><units>1</units><unitValue>5</unitValue>
  #   <rhythmUnits>3</rhythmUnits><rhythmValue>4</rhythmValue>
  #   <showBracket>false</showBracket><contents>…noteSets…</contents></tuplet>
  # One eighth (units x unitValue) written as three 16ths (rhythmUnits x
  # rhythmValue). The inner positions are in the written units, so a note's
  # real onset is the tuplet's position plus its own scaled by real/written.
  defp parse_tuplet({"tuplet", _, children} = node, voice) do
    assert_known_children!(node, children, @known_tuplet_children)

    position = text(children, "position") |> then(&if(&1, do: String.to_integer(&1), else: 0))
    {_, unit_beats} = NFM.note_value(text_to_num!(node, "unitValue"))
    {_, written_beats} = NFM.note_value(text_to_num!(node, "rhythmValue"))
    real = text_to_int!(node, "units") * unit_beats
    actual = text_to_int!(node, "rhythmUnits")
    written = actual * written_beats
    normal = real / written_beats

    unless normal == trunc(normal) do
      raise(ArgumentError, "TODO: tuplet of #{real} beats written as #{actual} x #{written_beats} in #{inspect(node)}")
    end

    bracket = text(children, "showBracket") != "false"
    factor = real / written

    sets =
      children
      |> one("contents")
      |> kids()
      |> all("noteSet")

    last = length(sets) - 1

    sets
    |> with_index(fn set, i ->
      tuplet = %{actual: actual, normal: trunc(normal), start: i == 0, stop: i == last, bracket: bracket}

      set
      |> parse_note_set(voice)
      |> Enum.map(fn note ->
        note = %{note | tuplet: tuplet, position: position + note.position * factor}
        %{note | beats: NFM.beats(note)}
      end)
    end)
    |> List.flatten()
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

  # Every onset must be where the previous note ended. True on every real
  # score so far; a gap would mean an implicit rest NFMXML never writes,
  # and we would rather stop than draw a measure short. Tuplet notes land
  # on thirds of a unit (96, 106.67, 117.33), so the comparison allows a
  # hundredth. The first bar may end early (a pickup), and so may the last
  # (the pickup's complement); any other short or long bar raises.
  # Returns {notes, beats}: the bar's real length.
  defp check_positions!(notes, index, measure_beats, last?) do
    unit = NFM.quarter_position()

    {_cursor, notes} =
      Enum.reduce(notes, {0.0, []}, fn note, {cursor, acc} ->
        cond do
          note.chord ->
            {cursor, [note | acc]}

          abs(note.position - cursor) > 0.01 ->
            raise(
              ArgumentError,
              "TODO: measure #{index + 1} note at position #{note.position}, " <>
                "previous note ended at #{cursor} (implicit rest?) in #{inspect(note)}"
            )

          true ->
            {cursor + note.beats * unit, [note | acc]}
        end
      end)

    notes = Enum.reverse(notes)
    last_end = List.last(notes) |> then(&(&1.position + &1.beats * unit))
    short? = last_end < measure_beats * unit - 0.01

    cond do
      abs(last_end - measure_beats * unit) <= 0.01 -> {notes, measure_beats}
      short? and (index == 0 or last?) -> {notes, last_end / unit}
      true -> raise(ArgumentError, "TODO: measure #{index + 1} ends at #{last_end}, expected #{measure_beats * unit}")
    end
  end

  # The clef's <note> names the pitch the sign marks (G4 for treble), and
  # that pitch has one MusicXML line. NFMXML's own <line> is zero-based and
  # is not trusted: see the moduledoc in Dave.NFM.
  @clef_lines %{{"G", "G4"} => 2, {"F", "F3"} => 4, {"C", "C4"} => 3}

  defp clef!(c) do
    sign = text!(c, "sign")
    note = text!(c, "note")

    case Map.fetch(@clef_lines, {sign, note}) do
      {:ok, line} -> %{sign: sign, line: line}
      :error -> raise(ArgumentError, "TODO: clef #{sign} on #{note} in #{inspect(c)}")
    end
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
    lyrics = children |> all("lyric") |> Enum.map(&parse_lyric/1) |> Enum.reject(&is_nil/1)

    base = %Note{
      voice: voice,
      value: value,
      position: position,
      pitch: nil,
      color: color,
      chord: false,
      dotted: dotted,
      lyrics: lyrics
    }

    base = %{base | beats: NFM.beats(base)}

    case all(children, "note") do
      [] ->
        [base]

      note_children ->
        note_children
        |> with_index(fn {"note", _, nc} = n, i ->
          # the lyrics sit under the chord once, on its first note
          %{
            base
            | pitch: parse_pitch(n),
              chord: i > 0,
              tied: one(nc, "tied") != nil,
              lyrics: if(i == 0, do: lyrics, else: [])
          }
        end)
    end
  end

  # <lyric><text>C</text><color>#0x33BB33</color><direction>down</direction></lyric>;
  # the text can be empty (Dave leaves a lyric slot on rests), which is no
  # lyric at all. <direction> is where the lyric sits: down = below the
  # staff. <line>1</line> is the second verse (zero-based; absent for the
  # first). <continued/> means a hyphen follows: the syllable goes on in
  # the next note ("Tum-ble"). <extend/> is a melisma line after the word.
  defp parse_lyric({"lyric", _, children} = node) do
    assert_known_children!(node, children, @known_lyric_children)

    placement =
      case text(children, "direction") do
        nil ->
          nil

        "down" ->
          "below"

        "up" ->
          "above"

        other ->
          raise(ArgumentError, "TODO: lyric direction #{inspect(other)} in #{inspect(node)}")
      end

    case text(children, "text") do
      nil ->
        nil

      "" ->
        nil

      t ->
        %{
          number: (text(children, "line") || "0") |> String.to_integer() |> Kernel.+(1),
          text: t,
          color: color(text(children, "color")),
          placement: placement,
          syllabic: if(one(children, "continued"), do: "begin", else: "single"),
          extend: one(children, "extend") != nil
        }
    end
  end

  # Noteflight writes colors two ways on real scores: "#ff0000" and
  # "#0x33BB33". Only the first is a color to a browser.
  defp color(nil), do: nil
  defp color("#0x" <> hex), do: "#" <> hex
  defp color(c), do: c

  # <note><pitch>A#4</pitch><step>B</step><accidental>flat</accidental></note>:
  # <pitch> is the SOUNDING pitch, <step> the written letter, and
  # <accidental> (plain text: flat, sharp, natural) is only the mark that is
  # ENGRAVED. A second Bb in the same bar has step B, pitch A#4 and no
  # accidental at all, and so does every F# in a one-sharp key: the
  # alteration comes from the sounding pitch, never from the mark. Seen on
  # Mandalorian's triplets and all over Nine to Five. The written octave is
  # the sounding one except across the B/C seam (Cb4 sounds B3, B#3 sounds
  # C4). An engraved mark that disagrees with the pitch raises.
  defp parse_pitch({"note", _, children} = node) do
    assert_known_children!(node, children, @known_note_children)

    name = text!(children, "pitch")
    step = text!(children, "step")

    unless step in ~w(A B C D E F G) do
      raise(ArgumentError, "unknown step: #{inspect(step)} in #{inspect(node)}")
    end

    [_, sounding_letter, sounding_alter, octave_str] =
      Regex.run(~r/^([A-G])(#*|b*)(-?\d+)$/, name) ||
        raise(ArgumentError, "TODO: pitch spelled #{inspect(name)} in #{inspect(node)}")

    sounding_octave = String.to_integer(octave_str)

    octave =
      case {step, sounding_letter} do
        {"B", "C"} -> sounding_octave - 1
        {"C", "B"} -> sounding_octave + 1
        _ -> sounding_octave
      end

    sounding =
      Map.fetch!(@step_semitones, sounding_letter) + semitones(sounding_alter) +
        12 * sounding_octave

    alter = sounding - (Map.fetch!(@step_semitones, step) + 12 * octave)

    if abs(alter) > 2 do
      raise(
        ArgumentError,
        "TODO: <pitch>#{name}</pitch> is #{alter} semitones from step #{step}#{octave} in #{inspect(node)}"
      )
    end

    accidental =
      case all(children, "accidental") do
        [] ->
          nil

        [{"accidental", _, acc_children} | _] ->
          acc = texts(acc_children)

          case Map.fetch(@accidentals, acc) do
            {:ok, ^alter} ->
              acc

            {:ok, marked} ->
              raise(
                ArgumentError,
                "TODO: accidental #{acc} (#{marked}) on a note that sounds #{alter} from its step in #{inspect(node)}"
              )

            :error ->
              raise(ArgumentError, "TODO: accidental #{inspect(acc)} in #{inspect(node)}")
          end
      end

    %{step: step, alter: alter, octave: octave, accidental: accidental}
  end

  defp semitones("#" <> rest), do: 1 + semitones(rest)
  defp semitones("b" <> rest), do: -1 + semitones(rest)
  defp semitones(""), do: 0

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
