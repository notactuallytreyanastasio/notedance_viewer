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
end
