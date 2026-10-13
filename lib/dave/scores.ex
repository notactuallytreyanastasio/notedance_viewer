defmodule Dave.Scores do
  @moduledoc """
  Scores imported from Noteflight, persisted: raw NFMXML, full-score
  MusicXML, per-part MusicXML (the kid's single-instrument view) and the
  timeline (see `Dave.NFM.Timeline`).
  """

  alias Dave.NFM.{Fetch, MusicXML, Parser, Timeline}
  alias Dave.Repo
  alias Dave.Scores.{Part, Score}

  import Ecto.Query

  defmodule ImportError do
    defexception [:message]
  end

  @doc """
  Import a score from its Noteflight URL, fetching the NFMXML live.
  Re-importing an already-known score updates it in place.
  """
  def import_from_url(url) do
    {host, id} = Fetch.parse_url(url)
    {xml, _meta} = Fetch.fetch(url)
    import_xml(host, id, xml)
  rescue
    e in ArgumentError ->
      raise ImportError, Exception.message(e)
  end

  @doc """
  Import from already-fetched NFMXML (also the offline test path).
  """
  def import_xml(host, id, xml) do
    score = Parser.parse(xml)
    timeline = Timeline.build(score)
    full_xml = MusicXML.to_music_xml(score)

    Repo.transaction(fn ->
      changeset =
        case Repo.get_by(Score, noteflight_host: host, noteflight_id: id) do
          nil -> %Score{}
          existing -> existing
        end
        |> Score.changeset(%{
          noteflight_host: host,
          noteflight_id: id,
          title: score.title,
          composer: score.composer,
          beats: score.beats,
          beat_type: score.beat_type,
          fifths: score.fifths,
          mode: score.mode,
          bpm: score.bpm,
          raw_nfmxml: xml,
          music_xml: full_xml,
          timeline: timeline
        })

      score_row =
        if is_nil(changeset.data.id),
          do: Repo.insert!(changeset),
          else: Repo.update!(changeset)

      # parts are replaced wholesale on re-import
      Repo.delete_all(from p in Part, where: p.score_id == ^score_row.id)

      for {part, idx} <- Enum.with_index(score.parts) do
        %Part{}
        |> Part.changeset(%{
          score_id: score_row.id,
          index: idx,
          name: part.name,
          short_name: part.short_name,
          instrument_uri: part.instrument_uri,
          music_xml: MusicXML.to_music_xml(score, [idx])
        })
        |> Repo.insert!()
      end

      score_row
    end)
    |> case do
      {:ok, score_row} -> Repo.preload(score_row, parts: part_query())
      {:error, reason} -> raise reason
    end
  end

  @doc "All scores, newest first."
  def list_scores do
    query = from s in Score, order_by: [desc: s.inserted_at], preload: [parts: ^part_query()]
    Repo.all(query)
  end

  @doc "One score by its Noteflight id (the public URL identifier)."
  def get_score!(noteflight_id) do
    Repo.one!(
      from s in Score,
        where: s.noteflight_id == ^noteflight_id,
        preload: [parts: ^part_query()]
    )
  end

  @doc "One part row, by score and part index."
  def get_part!(noteflight_id, index) do
    score = get_score!(noteflight_id)

    Enum.find(score.parts, &(&1.index == index)) ||
      raise Ecto.NoResultsError, queryable: Part
  end

  defp part_query do
    from p in Part, order_by: p.index
  end
end
