defmodule Dave.NFM.Chord do
  @moduledoc """
  A Noteflight chord symbol ("A7/C#", "Am7b5", "Fdim7") as MusicXML's
  root, kind and bass. Only kinds seen on a real score are known; a new
  suffix raises with the text, so it gets added rather than drawn wrong.
  """

  @kinds %{
    "" => "major",
    "m" => "minor",
    "7" => "dominant",
    "maj7" => "major-seventh",
    "m7" => "minor-seventh",
    "dim" => "diminished",
    "dim7" => "diminished-seventh",
    "m7b5" => "half-diminished",
    "6" => "major-sixth",
    "m6" => "minor-sixth",
    "9" => "dominant-ninth",
    "sus4" => "suspended-fourth",
    "sus2" => "suspended-second",
    "aug" => "augmented",
    "+" => "augmented"
  }

  @doc """
      Dave.NFM.Chord.parse("A7/C#")
      #=> %{root: {"A", 0}, kind: "dominant", bass: {"C", 1}, text: "A7/C#"}
  """
  def parse(text) do
    case Regex.run(~r/^([A-G])([#b]?)([^\/]*)(?:\/([A-G])([#b]?))?$/, String.trim(text)) do
      [_, root, root_acc, suffix, bass, bass_acc] ->
        %{root: {root, alter(root_acc)}, kind: kind!(suffix, text), bass: {bass, alter(bass_acc)}, text: text}

      [_, root, root_acc, suffix] ->
        %{root: {root, alter(root_acc)}, kind: kind!(suffix, text), bass: nil, text: text}

      nil ->
        raise ArgumentError, "TODO: chord symbol #{inspect(text)} is not root + kind (+ /bass)"
    end
  end

  defp kind!(suffix, text) do
    Map.get(@kinds, suffix) ||
      raise(ArgumentError, "TODO: chord kind #{inspect(suffix)} in chord symbol #{inspect(text)}")
  end

  defp alter("#"), do: 1
  defp alter("b"), do: -1
  defp alter(""), do: 0
end
