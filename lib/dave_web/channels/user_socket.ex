defmodule DaveWeb.UserSocket do
  @moduledoc """
  The socket for classroom sync. No identity: kids open a URL and join.
  """
  use Phoenix.Socket

  channel "score:*", DaveWeb.SessionChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
