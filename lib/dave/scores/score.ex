defmodule Dave.Scores.Score do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  schema "scores" do
    field :noteflight_host, :string
    field :noteflight_id, :string
    # the kids' address, two words like "sunny-fox"; set once, kept on re-import
    field :slug, :string
    # the Noteflight version the raw NFMXML came from (nil for the example)
    field :noteflight_version, :integer
    field :title, :string
    field :composer, :string
    field :beats, :integer
    field :beat_type, :integer
    field :fifths, :integer
    field :mode, :string, default: "major"
    field :bpm, :float
    field :raw_nfmxml, :string
    field :music_xml, :string
    # Dave.NFM.Timeline.build/1's output, as jsonb
    field :timeline, :map

    has_many :parts, Dave.Scores.Part

    timestamps(type: :utc_datetime)
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :noteflight_host,
      :noteflight_id,
      :slug,
      :noteflight_version,
      :title,
      :composer,
      :beats,
      :beat_type,
      :fifths,
      :mode,
      :bpm,
      :raw_nfmxml,
      :music_xml,
      :timeline
    ])
    |> validate_required([:noteflight_host, :noteflight_id, :slug, :title, :music_xml, :timeline])
    |> unique_constraint([:noteflight_host, :noteflight_id])
    |> unique_constraint(:slug)
  end
end
