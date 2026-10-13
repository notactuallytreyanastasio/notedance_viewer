defmodule DaveWeb.PageControllerTest do
  use DaveWeb.ConnCase, async: true

  alias Dave.Scores

  test "GET / with no songs: import form, example button, walkthrough button", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ ~s|action="/import"|
    assert html =~ ~s|action="/import/example"|
    assert html =~ "Walk me through using this"
    assert html =~ "No songs yet"
    assert html =~ "<title"
    assert html =~ "Songs · DaveDance"
    assert html =~ ~s|property="og:title" content="Songs · DaveDance"|
    assert html =~ ~r|property="og:image" content="http://localhost:\d+/images/og.png"|
    assert html =~ ~s|rel="icon" href="/images/favicon.svg"|
  end

  test "GET / with songs: both doors per song, no example button", %{conn: conn} do
    Scores.import_example()
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "Mary Had a Little Lamb"
    assert html =~ ~s|href="/s/mary-had-a-little-lamb/master"|
    assert html =~ ~s|href="/s/mary-had-a-little-lamb"|
    assert html =~ "Open on the TV"
    assert html =~ "Kids' link"
    refute html =~ ~s|action="/import/example"|
  end

  test "POST /import/example loads the bundled song and lands on the TV view", %{conn: conn} do
    conn = post(conn, ~p"/import/example")
    assert redirected_to(conn) == "/s/mary-had-a-little-lamb/master"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Loaded the example song"

    html = conn |> recycle() |> get(~p"/s/mary-had-a-little-lamb/master") |> html_response(200)
    assert html =~ "Loaded the example song"
    assert html =~ ~s|id="btn-play"|
    assert html =~ ~s|id="btn-join"|
    assert html =~ "Walk me through using this"
  end

  test "POST /import with a bad link comes back to / with the reason", %{conn: conn} do
    conn = post(conn, ~p"/import", %{"url" => "https://example.com/not-a-score"})
    assert redirected_to(conn) == "/"

    html = conn |> recycle() |> get(~p"/") |> html_response(200)
    assert html =~ "Could not import that link"
  end

  test "GET /s/:id is the kid view: instruments, status strip, help button", %{conn: conn} do
    Scores.import_example()
    html = conn |> get(~p"/s/mary-had-a-little-lamb") |> html_response(200)

    assert html =~ ~s|id="parts"|
    assert html =~ "Tap your instrument"
    assert html =~ "Pick an instrument to start"
    assert html =~ ~s|aria-label="Walk me through using this"|
    refute html =~ ~s|id="btn-play"|
  end

  test "DELETE /s/:id takes a song off the list and says how to get it back", %{conn: conn} do
    Scores.import_example()
    conn = delete(conn, ~p"/s/mary-had-a-little-lamb")
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Paste its link again"
    assert Scores.list_scores() == []
  end

  test "a song that is not there gets the friendly 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/s/not-a-song") end
  end
end
