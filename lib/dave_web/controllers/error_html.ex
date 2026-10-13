defmodule DaveWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use DaveWeb, :html

  # Error pages render without the root layout (config :dave, render_errors
  # has layout: false), so the page below carries its own small stylesheet.
  def render("404.html", assigns), do: error_page(Map.put(assigns, :kind, :not_found))
  def render(_template, assigns), do: error_page(Map.put(assigns, :kind, :broken))

  defp error_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{if @kind == :not_found, do: "Not here", else: "Something broke"} · DaveDance</title>
        <style>
          body { margin: 0; min-height: 100dvh; display: grid; place-items: center; background: #f6f3fc; color: #3d3a5c; font-family: "Fredoka", "Avenir Next", system-ui, sans-serif; text-align: center; }
          .bars { display: inline-flex; align-items: flex-end; gap: 6px; height: 48px; margin-bottom: 20px; }
          .bars i { display: block; width: 14px; border-radius: 5px; }
          h1 { font-size: 34px; margin: 0 0 10px; font-weight: 600; }
          p { font-size: 19px; color: #7a7795; margin: 0 0 26px; max-width: 28em; }
          a { display: inline-block; padding: 14px 24px; border-radius: 18px; background: #b9c6fa; color: #3d3a5c; font-weight: 600; font-size: 18px; text-decoration: none; }
        </style>
      </head>
      <body>
        <main>
          <span class="bars" aria-hidden="true"><i style="height:48px;background:#ffe39a"></i><i style="height:40px;background:#ffb3a7"></i><i style="height:32px;background:#a8d8f0"></i><i style="height:24px;background:#bdebc4"></i></span>
          <h1 :if={@kind == :not_found}>That song is not here.</h1>
          <p :if={@kind == :not_found}>
            It may have been removed, or the link is missing a character. The songs page has everything that is on the TV.
          </p>
          <h1 :if={@kind == :broken}>Something broke on our side.</h1>
          <p :if={@kind == :broken}>
            Give it another try in a moment. If it keeps happening, send Bobby the link you were using.
          </p>
          <a href="/">Back to the songs</a>
        </main>
      </body>
    </html>
    """
  end
end
