defmodule DaveWeb.SessionChannel do
  @moduledoc """
  One channel per open view (master, TV, each iPad), on `"score:<id>"`.

  Every join is pushed the live clock state, so a kid arriving mid-song
  starts in the right place. `ping` is the clock-offset probe: the reply
  carries the server's wall clock, and the client computes
  `offset = server_now + rtt/2 - client_now` from the round trip.

  Every view also tracks itself in `DaveWeb.Presence` with its role and,
  for kids, the instrument they picked, so the TV can show who is following.

  Any member can send transport control; only the master page shows the
  controls. This is a classroom, not a bank.
  """
  use DaveWeb, :channel

  alias Dave.Sessions
  alias DaveWeb.Presence

  # No explicit PubSub.subscribe: Phoenix subscribes every channel process
  # to the topic it joins automatically (that is how Phoenix.Channel.broadcast
  # reaches everyone without manual subscriptions). Subscribing by hand too
  # delivers each Dave.Sessions broadcast twice — verified by watching one
  # PID push the same "state" twice before this comment existed.
  @impl true
  def join("score:" <> nf_id, params, socket) do
    send(self(), :after_join)

    role = if params["role"] == "master", do: "master", else: "kid"
    client_id = Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
    # the kid page sends its instrument on every join, so a reconnect after a
    # wifi hiccup does not drop it from the TV's count
    part = if is_binary(params["part"]), do: params["part"], else: nil

    {:ok, assign(socket, nf_id: nf_id, role: role, client_id: client_id, part: part)}
  end

  @impl true
  def handle_info(:after_join, socket) do
    push(socket, "state", Sessions.state(socket.assigns.nf_id))

    {:ok, _} =
      Presence.track(socket, socket.assigns.client_id, %{
        role: socket.assigns.role,
        part: socket.assigns.part
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  # broadcasts from Dave.Sessions on the score topic
  def handle_info({:state, payload}, socket) do
    push(socket, "state", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_in("ping", %{"t" => t}, socket) do
    {:reply, {:ok, %{t: t, now: System.system_time(:millisecond)}}, socket}
  end

  def handle_in("play", %{"position_ms" => pos}, socket) do
    Sessions.play(socket.assigns.nf_id, pos)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("play", _params, socket) do
    Sessions.play(socket.assigns.nf_id)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("pause", _params, socket) do
    Sessions.pause(socket.assigns.nf_id)
    {:reply, {:ok, %{}}, socket}
  end

  def handle_in("seek", %{"position_ms" => pos}, socket) do
    Sessions.seek(socket.assigns.nf_id, pos)
    {:reply, {:ok, %{}}, socket}
  end

  # a kid picked (or changed) their instrument
  def handle_in("part", %{"name" => name}, socket) when is_binary(name) do
    {:ok, _} =
      Presence.update(socket, socket.assigns.client_id, %{
        role: socket.assigns.role,
        part: name
      })

    {:reply, {:ok, %{}}, socket}
  end
end
