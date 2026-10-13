defmodule Dave.Repo.Migrations.CreateScores do
  use Ecto.Migration

  def change do
    create table(:scores) do
      add :noteflight_host, :text, null: false
      add :noteflight_id, :text, null: false
      add :title, :text, null: false
      add :composer, :text
      add :beats, :integer
      add :beat_type, :integer
      add :fifths, :integer
      add :mode, :text, default: "major"
      add :bpm, :float
      add :raw_nfmxml, :text, null: false
      add :music_xml, :text, null: false
      add :timeline, :jsonb, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:scores, [:noteflight_host, :noteflight_id])

    create table(:parts) do
      add :score_id, references(:scores, on_delete: :delete_all), null: false
      add :index, :integer, null: false
      add :name, :text, null: false
      add :short_name, :text
      add :instrument_uri, :text
      add :music_xml, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:parts, [:score_id, :index])
  end
end
