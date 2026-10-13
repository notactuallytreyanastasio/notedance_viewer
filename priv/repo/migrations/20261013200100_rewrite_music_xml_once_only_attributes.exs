defmodule Dave.Repo.Migrations.RewriteMusicXmlOnceOnlyAttributes do
  use Ecto.Migration

  @moduledoc """
  A data migration. The MusicXML writer used to copy NFMXML's habit of
  restating the clef and time signature in every measure's <attributes>,
  and OSMD engraved all of them. Rows store their MusicXML at import time,
  so every existing song is rewritten here from its raw NFMXML with the
  fixed writer; no re-import from Noteflight is needed.
  """

  alias Dave.NFM.{MusicXML, Parser}

  def up do
    %{rows: rows} = repo().query!("SELECT id, raw_nfmxml FROM scores ORDER BY id")

    for [id, xml] <- rows do
      score = Parser.parse(xml)

      repo().query!("UPDATE scores SET music_xml = $1 WHERE id = $2", [
        MusicXML.to_music_xml(score),
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
