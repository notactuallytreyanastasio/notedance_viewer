defmodule Dave.Repo.Migrations.RereadTupletsAndAccidentals do
  use Ecto.Migration

  @moduledoc """
  Rewrite every stored MusicXML and timeline from its raw NFMXML, because
  the reader skipped `<tuplet>`s: a voice holding only tuplets looked like
  an empty voice, so Mandalorian's bar of quarter-note triplets (bells, bar
  12) was stored as a whole-measure rest and drawn as silence. The reader
  also took a note's alteration from the engraved accidental only, so a
  second B flat in a bar, or any F sharp under a sharp key signature, came
  out natural in the timeline's MIDI numbers.
  """

  alias Dave.NFM.{MusicXML, Parser, Timeline}

  def up do
    %{rows: rows} = repo().query!("SELECT id, raw_nfmxml FROM scores ORDER BY id")

    for [id, xml] <- rows do
      score = Parser.parse(xml)

      repo().query!("UPDATE scores SET music_xml = $1, timeline = $2 WHERE id = $3", [
        MusicXML.to_music_xml(score),
        Timeline.build(score),
        id
      ])

      for {_part, idx} <- Enum.with_index(score.parts) do
        repo().query!("UPDATE parts SET music_xml = $1 WHERE score_id = $2 AND index = $3", [
          MusicXML.to_music_xml(score, [idx]),
          id,
          idx
        ])
      end
    end
  end

  def down, do: :ok
end
