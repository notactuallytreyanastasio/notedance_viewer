defmodule Dave.Repo.Migrations.AddSlugToScores do
  use Ecto.Migration

  @moduledoc """
  Every score gets a two-word address for the kids' link. Rows that exist
  already (production has the example song and whatever Dave pasted) are
  backfilled here, so the column can be NOT NULL from the start.
  """

  def up do
    alter table(:scores) do
      add :slug, :text
    end

    flush()

    %{rows: rows} = repo().query!("SELECT id, noteflight_host FROM scores ORDER BY id")

    Enum.reduce(rows, MapSet.new(), fn [id, host], taken ->
      slug =
        if host == "example",
          do: "little-lamb",
          else: fresh(taken)

      repo().query!("UPDATE scores SET slug = $1 WHERE id = $2", [slug, id])
      MapSet.put(taken, slug)
    end)

    alter table(:scores) do
      modify :slug, :text, null: false
    end

    create unique_index(:scores, [:slug])
  end

  def down do
    drop unique_index(:scores, [:slug])

    alter table(:scores) do
      remove :slug
    end
  end

  defp fresh(taken) do
    slug = Dave.Slug.generate()
    if MapSet.member?(taken, slug), do: fresh(taken), else: slug
  end
end
