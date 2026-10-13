defmodule Dave.Repo.Migrations.FixClefLineAndRecordVersion do
  use Ecto.Migration

  @moduledoc """
  Two things. A column for the Noteflight version a score was imported
  from, so a stale import is visible. And a rewrite of every stored
  MusicXML from its raw NFMXML, because the writer put the treble clef on
  line 1 (NFMXML counts from zero) and every note drew a third low.
  """

  alias Dave.NFM.{MusicXML, Parser}

  def up do
    alter table(:scores) do
      add :noteflight_version, :integer
    end

    flush()

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

  def down do
    alter table(:scores) do
      remove :noteflight_version
    end
  end
end
