defmodule DaveWeb.PageController do
  use DaveWeb, :controller

  alias Dave.Scores

  def home(conn, _params) do
    render(conn, :home, scores: Scores.list_scores(), page_title: "Songs")
  end
end
