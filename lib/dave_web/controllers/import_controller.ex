defmodule DaveWeb.ImportController do
  use DaveWeb, :controller

  alias Dave.Scores

  def create(conn, %{"url" => url}) do
    case Scores.import_from_url(url) do
      %Scores.Score{} = score ->
        conn
        |> put_flash(:info, "Imported “#{score.title}”. This is the TV view.")
        |> put_warnings(score.import_warnings)
        |> redirect(to: "/#{score.slug}/tv")

      other ->
        raise "import returned #{inspect(other)}"
    end
  rescue
    e in Scores.ImportError ->
      conn
      |> put_flash(:error, "Could not import that link: #{Exception.message(e)}")
      |> redirect(to: "/")
  end

  # what the song has that DaveDance does not follow (repeats), from the parser
  defp put_warnings(conn, []), do: conn
  defp put_warnings(conn, warnings), do: put_flash(conn, :error, Enum.join(warnings, " "))

  # the bundled example song, for a first visit with no Noteflight link yet
  def example(conn, _params) do
    score = Scores.import_example()

    conn
    |> put_flash(:info, "Loaded the example song. This is the TV view.")
    |> redirect(to: "/#{score.slug}/tv")
  end
end
