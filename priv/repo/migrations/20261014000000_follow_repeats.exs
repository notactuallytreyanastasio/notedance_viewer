defmodule Dave.Repo.Migrations.FollowRepeats do
  use Ecto.Migration

  @moduledoc """
  Rewrite every stored MusicXML and timeline from its raw NFMXML: the
  timeline now unrolls repeats and jumps (Nine to Five's D.S. al Coda,
  Twinkle's repeat) and carries each onset's straight-read time for the
  cursor; the MusicXML engraves the repeat barlines, signs and chord
  symbols.
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
