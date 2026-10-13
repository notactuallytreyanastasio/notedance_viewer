defmodule DaveWeb.SessionChannelTest do
  use DaveWeb.ChannelCase, async: false

  alias Dave.Sessions

  @nf_id "eea68d68d65a761a2d228b73163cee89518a66c4"
  @topic "score:" <> @nf_id

  setup do
    on_exit(fn -> Sessions.reset_all() end)

    {:ok, socket} = connect(DaveWeb.UserSocket, %{}, %{})
    {:ok, _reply, socket} = subscribe_and_join(socket, DaveWeb.SessionChannel, @topic)
    %{socket: socket}
  end

  test "joining pushes the live state (a kid arriving mid-song starts right)" do
    Sessions.play(@nf_id, 1_000)
    assert_push "state", %{status: :playing, position_ms: pos, at: at}
    assert pos >= 1_000
    assert is_integer(at)
  end

  test "ping carries the server clock for offset estimation", %{socket: socket} do
    ref = push(socket, "ping", %{"t" => 123})
    assert_reply ref, :ok, %{t: 123, now: now}
    assert_in_delta now, System.system_time(:millisecond), 1_000
  end

  test "play and pause broadcast to everyone on the topic", %{socket: socket} do
    ref = push(socket, "play", %{"position_ms" => 0})
    assert_reply ref, :ok
    assert_push "state", %{status: :playing}

    ref = push(socket, "pause", %{})
    assert_reply ref, :ok
    assert_push "state", %{status: :paused}
  end

  test "seek re-bases the clock", %{socket: socket} do
    # the join push is still in the mailbox (paused at 0) — consume it first
    assert_push "state", %{status: :paused, position_ms: 0}

    ref = push(socket, "seek", %{"position_ms" => 10_000})
    assert_reply ref, :ok
    assert_push "state", %{status: :paused, position_ms: pos}
    assert pos >= 10_000
  end

  # The setup's kid socket and the socket under test both push to this
  # process, and a channel receives the diff of its own join, so presence
  # messages are read until one carries the expected metas.
  defp presence_metas_until(event, pred, tries \\ 5) do
    assert_push ^event, payload
    metas = payload |> Map.get(:joins, payload) |> Map.values() |> Enum.flat_map(& &1.metas)

    cond do
      Enum.any?(metas, pred) -> metas
      tries > 1 -> presence_metas_until(event, pred, tries - 1)
      true -> flunk("no #{event} matched; last metas: #{inspect(metas)}")
    end
  end

  test "every view is tracked; a kid's instrument pick shows up in presence", %{socket: socket} do
    assert [%{role: "kid", part: nil}] =
             presence_metas_until("presence_state", &(&1.role == "kid"))
             |> Enum.map(&Map.take(&1, [:role, :part]))

    ref = push(socket, "part", %{"name" => "Bass Xylophone"})
    assert_reply ref, :ok

    assert [%{part: "Bass Xylophone", role: "kid"}] =
             presence_metas_until("presence_diff", &(&1.part == "Bass Xylophone"))
             |> Enum.map(&Map.take(&1, [:role, :part]))
  end

  test "the master page joins with its role" do
    {:ok, socket} = connect(DaveWeb.UserSocket, %{}, %{})

    {:ok, _reply, _socket} =
      subscribe_and_join(socket, DaveWeb.SessionChannel, @topic, %{"role" => "master"})

    metas = presence_metas_until("presence_state", &(&1.role == "master"))
    assert Enum.any?(metas, &(&1.role == "master"))
  end
end
