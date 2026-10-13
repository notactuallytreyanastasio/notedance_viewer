defmodule DaveWeb.PageControllerTest do
  use DaveWeb.ConnCase, async: true

  test "GET / shows the import form and the score list", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "paste a Noteflight score URL"
    assert html =~ ~s|action="/import"|
    assert html =~ "No scores yet"
  end
end
