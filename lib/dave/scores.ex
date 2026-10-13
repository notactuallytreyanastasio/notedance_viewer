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
  require Logger

  defmodule ImportError do
    defexception [:message]
  end

  @doc """
  Import a score from its Noteflight URL, fetching the NFMXML live.
  Re-importing an already-known score updates it in place.
  """
  def import_from_url(url) do
    {host, id} = Fetch.parse_url(url)

    {xml, _meta} =
      try do
        Fetch.fetch({host, id})
      rescue
        e ->
          Logger.warning("noteflight fetch failed for #{host}/#{id}: #{Exception.message(e)}")

          reraise ImportError,
                  [
                    message:
                      "Noteflight did not hand over that score. Check that it is shared " <>
                        "with anyone who has the link, then try again."
                  ],
                  __STACKTRACE__
      end

    import_xml(host, id, xml)
  rescue
    e in ImportError ->
      reraise e, __STACKTRACE__

    e in ArgumentError ->
      # Fetch.parse_url (not a score link) or the parser (a notation we have
      # not met yet, which raises a TODO naming the node). Dave gets a plain
      # sentence; the node goes to the log so it can be added.
      Logger.warning("import of #{inspect(url)} failed: #{Exception.message(e)}")

      message =
        if String.starts_with?(Exception.message(e), "TODO") do
          "This score uses something DaveDance cannot read yet. " <>
            "Send Bobby the link and it will get added."
        else
          "That is not a Noteflight score link. It should look like " <>
            "https://your-school.learning.noteflight.com/scores/view/… ."
        end

      reraise ImportError, [message: message], __STACKTRACE__
  end

  @doc "Remove a song and its parts. Re-importing the link brings it back."
  def delete_score!(slug) do
    score = get_score!(slug)
    Repo.delete!(score)
  end

  @example_host "example"
  @example_id "mary-had-a-little-lamb"
  @example_slug "little-lamb"

  @doc """
  Import the bundled example song (Mary Had a Little Lamb, three
  xylophones), so a first visit has something to put on the TV before any
  Noteflight link exists. Idempotent: re-running updates the same row.
  """
  def import_example do
    xml = File.read!(Application.app_dir(:dave, "priv/examples/mary_had_a_little_lamb.nfmxml"))
    import_xml(@example_host, @example_id, xml)
  end

  @doc "True for the row `import_example/0` creates."
  def example?(%Score{noteflight_host: @example_host}), do: true
  def example?(_score), do: false

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
          slug: slug_for(host),
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

      # A song keeps its slug across re-imports: the kids may already have it
      # typed in. Only a fresh row gets one.
      changeset =
        if is_nil(changeset.data.id),
          do: changeset,
          else: Ecto.Changeset.delete_change(changeset, :slug)

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

  # The example song has a fixed address so the handout can name it. Everything
  # else draws two random words, retrying past the (rare) song that already has
  # them. 1200 combinations against a classroom's handful of songs.
  defp slug_for(@example_host), do: @example_slug

  defp slug_for(_host) do
    slug = Dave.Slug.generate()

    if Repo.exists?(from s in Score, where: s.slug == ^slug),
      do: slug_for(nil),
      else: slug
  end

  @doc "All scores, newest first."
  def list_scores do
    query = from s in Score, order_by: [desc: s.inserted_at], preload: [parts: ^part_query()]
    Repo.all(query)
  end

  @doc """
  One score by its two-word slug, as typed: `sunny-fox`, `sunnyfox` and
  `Sunny Fox` all find the same row.
  """
  def get_score!(slug) do
    key = Dave.Slug.normalize(slug)

    Repo.one!(
      from s in Score,
        where: fragment("replace(?, '-', '')", s.slug) == ^key,
        preload: [parts: ^part_query()]
    )
  end

  @doc "One score by its Noteflight id, for the old `/s/<id>` links."
  def get_score_by_noteflight_id!(noteflight_id) do
    Repo.one!(
      from s in Score,
        where: s.noteflight_id == ^noteflight_id,
        preload: [parts: ^part_query()]
    )
  end

  @doc "One part row, by score slug and part index."
  def get_part!(slug, index) do
    score = get_score!(slug)

    Enum.find(score.parts, &(&1.index == index)) ||
      raise Ecto.NoResultsError, queryable: Part
  end

  defp part_query do
    from p in Part, order_by: p.index
  end
end
