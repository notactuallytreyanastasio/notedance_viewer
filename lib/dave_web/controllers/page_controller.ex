defmodule DaveWeb.PageController do
  use DaveWeb, :controller

  alias Dave.Scores

  def home(conn, _params) do
    render(conn, :home, scores: Scores.list_scores())
  end
end
