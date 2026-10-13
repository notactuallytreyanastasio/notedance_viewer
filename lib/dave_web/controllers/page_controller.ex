defmodule DaveWeb.PageController do
  use DaveWeb, :controller

  alias Dave.Scores

  def home(conn, _params) do
    # the typeable address shown next to each song: dave.bobbby.online/sunny-fox
    host =
      case conn.port do
        p when p in [80, 443] -> conn.host
        p -> "#{conn.host}:#{p}"
      end

    render(conn, :home, scores: Scores.list_scores(), page_title: "Songs", host: host)
  end
end
