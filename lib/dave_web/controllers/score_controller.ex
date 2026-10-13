defmodule DaveWeb.ScoreController do
  use DaveWeb, :controller

  alias Dave.Scores

  # the kid's view: pick your instrument, see only your part, follow the red line
  def play(conn, %{"slug" => slug}) do
    score = Scores.get_score!(slug)

    conn
    |> assign(:score, score)
    |> assign(:page_title, score.title)
    |> assign(
      :page_description,
      "Tap your instrument and follow the line. #{score.title} on DaveDance."
    )
    |> render(:play)
  end

  # the master view: the whole score, audio, transport
  def master(conn, %{"slug" => slug}) do
    score = Scores.get_score!(slug)

    conn
    |> assign(:score, score)
    |> assign(:page_title, "#{score.title} on the TV")
    |> assign(
      :page_description,
      "The TV view: play, pause, start from any measure. #{score.title} on DaveDance."
    )
    |> render(:master)
  end

  # MusicXML for OpenSheetMusicDisplay: full score (master) or one part (kid)
  def musicxml(conn, %{"slug" => slug, "part" => part_index}) do
    part = Scores.get_part!(slug, String.to_integer(part_index))

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, part.music_xml)
  end

  def musicxml(conn, %{"slug" => slug}) do
    score = Scores.get_score!(slug)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, score.music_xml)
  end

  def delete(conn, %{"slug" => slug}) do
    score = Scores.delete_score!(slug)

    conn
    |> put_flash(:info, "Removed “#{score.title}”. Paste its link again to bring it back.")
    |> redirect(to: "/")
  end

  def timeline(conn, %{"slug" => slug}) do
    score = Scores.get_score!(slug)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(score.timeline))
  end

  # /s/<noteflight id> was the kids' address before slugs; the TV's QR codes
  # pointed there too. Both land where they used to, by the new name.
  def legacy(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score_by_noteflight_id!(nf_id)
    redirect(conn, to: "/#{score.slug}")
  end

  def legacy_master(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score_by_noteflight_id!(nf_id)
    redirect(conn, to: "/#{score.slug}/tv")
  end
end
