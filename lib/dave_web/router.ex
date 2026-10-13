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

    get "/s/:noteflight_id", ScoreController, :play
    get "/s/:noteflight_id/master", ScoreController, :master
    get "/s/:noteflight_id/musicxml", ScoreController, :musicxml
    get "/s/:noteflight_id/musicxml/:part", ScoreController, :musicxml
    get "/s/:noteflight_id/timeline", ScoreController, :timeline
  end

  # Other scopes may use custom stacks.
  # scope "/api", DaveWeb do
  #   pipe_through :api
  # end
end
