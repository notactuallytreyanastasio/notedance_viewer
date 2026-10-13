defmodule DaveWeb.ImportController do
  use DaveWeb, :controller

  alias Dave.Scores

  def create(conn, %{"url" => url}) do
    case Scores.import_from_url(url) do
      %Scores.Score{} = score ->
        conn
        |> put_flash(:info, "Imported “#{score.title}”")
        |> redirect(to: "/s/#{score.noteflight_id}/master")

      other ->
        raise "import returned #{inspect(other)}"
    end
  rescue
    e in Scores.ImportError ->
      conn
      |> put_flash(:error, "Import failed: #{Exception.message(e)}")
      |> redirect(to: "/")
  end
end
