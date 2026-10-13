defmodule Dave.SessionsTest do
  use ExUnit.Case, async: false

  alias Dave.Sessions

  @nf_id "eea68d68d65a761a2d228b73163cee89518a66c4"

  setup do
    on_exit(fn -> Sessions.reset_all() end)
    :ok
  end

  test "a session nobody has touched is paused at zero" do
    state = Sessions.state(@nf_id)
    assert state.status == :paused
    assert state.position_ms == 0
    assert is_integer(state.at)
  end

  test "play from a position advances with real time" do
    Sessions.play(@nf_id, 0)
    s1 = Sessions.state(@nf_id)
    Process.sleep(60)
    s2 = Sessions.state(@nf_id)

    assert s1.status == :playing
    assert s2.status == :playing
    assert s2.position_ms - s1.position_ms >= 50
  end

  test "pause freezes the position, play resumes from it" do
    Sessions.play(@nf_id, 0)
    Process.sleep(50)
    paused = Sessions.pause(@nf_id)
    Process.sleep(60)
    still = Sessions.state(@nf_id)

    assert paused.status == :paused
    assert still.position_ms == paused.position_ms

    Sessions.play(@nf_id)
    assert Sessions.state(@nf_id).position_ms >= still.position_ms
  end

  test "seek while playing re-bases the clock" do
    Sessions.play(@nf_id, 0)
    Sessions.seek(@nf_id, 10_000)
    state = Sessions.state(@nf_id)

    assert state.status == :playing
    assert state.position_ms >= 10_000
  end

  test "the at timestamp and position in a payload agree with now" do
    Sessions.play(@nf_id, 0)
    state = Sessions.state(@nf_id)

    # position is computed at payload-build time; nothing in between
    assert state.position_ms >= 0
    assert_in_delta state.at, System.system_time(:millisecond), 50
  end
end
