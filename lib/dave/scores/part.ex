defmodule Dave.Scores.Part do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "parts" do
    belongs_to :score, Dave.Scores.Score
    field :index, :integer
    field :name, :string
    field :short_name, :string
    field :instrument_uri, :string
    # MusicXML for this part alone — the kid's single-instrument view
    field :music_xml, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(part, attrs) do
    part
    |> cast(attrs, [:score_id, :index, :name, :short_name, :instrument_uri, :music_xml])
    |> validate_required([:score_id, :index, :name, :music_xml])
    |> unique_constraint([:score_id, :index])
  end
end
