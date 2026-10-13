defmodule DaveWeb.ErrorHTMLTest do
  use DaveWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "404 is a full page in the house style with a way home" do
    html = render_to_string(DaveWeb.ErrorHTML, "404", "html", [])
    assert html =~ "That song is not here."
    assert html =~ ~s|href="/"|
    assert html =~ "<!DOCTYPE html>"
  end

  test "500 says it is our fault" do
    html = render_to_string(DaveWeb.ErrorHTML, "500", "html", [])
    assert html =~ "Something broke on our side."
  end
end
