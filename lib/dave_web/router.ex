defmodule DaveWeb.Router do
  use DaveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", DaveWeb do
    pipe_through :browser

    get "/", PageController, :home
    post "/import", ImportController, :create
    post "/import/example", ImportController, :example

    # The old addresses, from before songs had two-word slugs. Dave may have
    # one bookmarked or printed; they land on the new one.
    get "/s/:noteflight_id", ScoreController, :legacy
    get "/s/:noteflight_id/master", ScoreController, :legacy_master

    # The kids' address is the song's two words at the root, so that
    # dave.bobbby.online/sunny-fox is the whole thing to type. These stay
    # last: every other route wins over them.
    get "/:slug", ScoreController, :play
    get "/:slug/tv", ScoreController, :master
    get "/:slug/musicxml", ScoreController, :musicxml
    get "/:slug/musicxml/:part", ScoreController, :musicxml
    get "/:slug/timeline", ScoreController, :timeline
    delete "/:slug", ScoreController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", DaveWeb do
  #   pipe_through :api
  # end
end
