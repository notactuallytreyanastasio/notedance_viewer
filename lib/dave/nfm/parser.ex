defmodule Dave.NFM.Parser do
  @moduledoc """
  NFMXML (Noteflight native XML) into `Dave.NFM` structs.

  Strict on purpose: anything the parser has not met on a real classroom
  score (ties, tempo changes, unknown noteSet children) raises with the
  offending node, per house style — a crash is a work item, a silent
  misparse is a hidden bug.
  """

  alias Dave.NFM
  alias Dave.NFM.{Part, Score, Note, Measure}

  @accidentals %{
    "sharp" => 1, "doubleSharp" => 2, "flat" => -1, "doubleFlat" => -2,
    "natural" => 0
  }

  @known_noteset_children ~w(value position color note)
  @known_note_children ~w(pitch step noteHead accidental)

  def parse(xml) do
    {:ok, doc} = Saxy.SimpleForm.parse_string(xml)
    parse_score(doc)
  end

  defp parse_score({"noteflightScore", _, children} = doc) do
    {beats, beat_type} = time_signature!(children)
    {fifths, mode} = key_signature!(children)
    {tempo_value, bpm} = tempo!(children)

    parts =
      children
      |> all("part")
      |> with_index(&parse_part/2)

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

  defp parse_part({"part", _, children}, index) do
    staves = all(children, "staff")

    measures =
      staves
      |> Enum.flat_map(&all(&1, "measure"))
      |> with_index(&parse_measure/2)

    %Part{
      nfm_id: text(children, "id") || "part-#{index}",
      name: text!(children, "name"),
      short_name: text(children, "shortName") || "",
      instrument_uri: text(children, "instrumentUri") || "",
      measures: measures
    }
  end

  defp parse_measure({"measure", _, children}, index) do
    clef =
      case attributes_clef(children) do
        nil -> nil
        c -> %{sign: text!(c, "sign"), line: text_to_int!(c, "line")}
      end

    notes =
      children
      |> one("voices")
      |> kids()
      |> all("voice")
      |> with_index(fn {"voice", _, voice_children}, voice ->
        voice_children
        |> all("noteSet")
        |> Enum.flat_map(&parse_note_set(&1, voice + 1))
      end)
      |> List.flatten()

    %Measure{index: index, clef: clef, notes: notes}
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

    color = text(children, "color")

    note_children = all(children, "note")

    case note_children do
      [] ->
        [
          %Note{
            voice: voice,
            value: value,
            position: position,
            pitch: nil,
            color: color,
            chord: false
          }
        ]

      note_children ->
        note_children
        |> with_index(fn n, i ->
          %Note{
            voice: voice,
            value: value,
            position: position,
            pitch: parse_pitch(n),
            color: color,
            chord: i > 0
          }
        end)
    end
  end

  defp parse_pitch({"note", _, children} = node) do
    assert_known_children!(node, children, @known_note_children)

    name = text!(children, "pitch")
    step = text!(children, "step")

    unless step in ~w(A B C D E F G) do
      raise(ArgumentError, "unknown step: #{inspect(step)} in #{inspect(node)}")
    end

    alter =
      case all(children, "accidental") do
        [] -> 0
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

  defp with_index(list, fun), do: list |> Enum.with_index() |> Enum.map(fn {e, i} -> fun.(e, i) end)

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
      {i, ""} -> {:ok, i * 1.0}
      _ ->
        case Float.parse(s) do
          {f, ""} -> {:ok, f}
          _ -> :error
        end
    end
  end
end
