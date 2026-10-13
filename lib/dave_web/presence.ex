defmodule DaveWeb.Presence do
  @moduledoc """
  Who is in the room. Every open view tracks itself on its score topic with
  `%{role: "kid" | "master", part: name | nil}`, so the TV can say
  "4 iPads following" and which instruments they picked.
  """
  use Phoenix.Presence, otp_app: :dave, pubsub_server: Dave.PubSub
end
