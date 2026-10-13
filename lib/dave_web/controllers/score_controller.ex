defmodule DaveWeb.ScoreController do
  use DaveWeb, :controller

  alias Dave.Scores

  # the kid's view: pick your instrument, see only your part, follow the red line
  def play(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score!(nf_id)

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
  def master(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score!(nf_id)

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
  def musicxml(conn, %{"noteflight_id" => nf_id, "part" => part_index}) do
    part = Scores.get_part!(nf_id, String.to_integer(part_index))

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, part.music_xml)
  end

  def musicxml(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score!(nf_id)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, score.music_xml)
  end

  def timeline(conn, %{"noteflight_id" => nf_id}) do
    score = Scores.get_score!(nf_id)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(score.timeline))
  end
end
