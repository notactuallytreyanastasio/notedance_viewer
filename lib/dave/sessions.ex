defmodule Dave.Sessions do
  @moduledoc """
  The master clock, one process for every playing score.

  The whole sync scheme lives here: the server holds
  `%{status: :playing|:paused, position_ms: ..., set at monotonic T}` per
  score and broadcasts `{status, position_ms, at}` on `Dave.PubSub`
  ("score:<id>") on every control event and once a second while playing.
  Each client advances `position + (now - at)` on its own clock, corrected
  to server time by a ping round-trip in `DaveWeb.SessionChannel`.

  `at` is wall-clock milliseconds (server). Clients never trust their own
  wall clock — they carry an estimated offset instead.
  """

  use GenServer

  # Phoenix.PubSub is the module; Dave.PubSub is the registered server name
  alias Phoenix.PubSub, as: PubSubModule

  @heartbeat 1_000

  # client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Play, from `position_ms` when given, else from where it stands."
  def play(nf_id, position_ms \\ nil) do
    GenServer.call(__MODULE__, {:control, nf_id, {:play, position_ms}})
  end

  def pause(nf_id), do: GenServer.call(__MODULE__, {:control, nf_id, :pause})

  def seek(nf_id, position_ms),
    do: GenServer.call(__MODULE__, {:control, nf_id, {:seek, position_ms}})

  @doc """
  The live position for a score, as the broadcast payload
  (`%{status, position_ms, at}`), always consistent with "now".
  """
  def state(nf_id), do: GenServer.call(__MODULE__, {:state, nf_id})

  @doc "Every session back to paused at zero (tests)."
  def reset_all, do: GenServer.call(__MODULE__, :reset_all)

  # GenServer

  @impl true
  def init(:ok) do
    :timer.send_interval(@heartbeat, :tick)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:state, nf_id}, _from, sessions) do
    session =
      Map.get(sessions, nf_id, %{
        status: :paused,
        position_ms: 0,
        at_mono: monotonic(),
        at_wall: wall()
      })

    {:reply, payload(session, monotonic(), wall()), sessions}
  end

  def handle_call(:reset_all, _from, _sessions), do: {:reply, :ok, %{}}

  def handle_call({:control, nf_id, control}, _from, sessions) do
    now_mono = monotonic()
    now_wall = wall()

    session =
      Map.get(sessions, nf_id, %{
        status: :paused,
        position_ms: 0,
        at_mono: now_mono,
        at_wall: now_wall
      })
      |> control(control, now_mono, now_wall)

    sessions = Map.put(sessions, nf_id, session)
    broadcast(nf_id, session)
    {:reply, payload(session, now_mono, now_wall), sessions}
  end

  @impl true
  def handle_info(:tick, sessions) do
    for {nf_id, session} <- sessions, session.status == :playing do
      broadcast(nf_id, session)
    end

    {:noreply, sessions}
  end

  defp control(session, {:play, nil}, now_mono, now_wall) do
    position = current_position(session, now_mono)

    %{session | status: :playing, position_ms: position, at_mono: now_mono, at_wall: now_wall}
  end

  defp control(session, {:play, position_ms}, now_mono, now_wall) do
    %{session | status: :playing, position_ms: position_ms, at_mono: now_mono, at_wall: now_wall}
  end

  defp control(session, :pause, now_mono, now_wall) do
    position = current_position(session, now_mono)

    %{session | status: :paused, position_ms: position, at_mono: now_mono, at_wall: now_wall}
  end

  defp control(session, {:seek, position_ms}, now_mono, now_wall) do
    %{session | position_ms: position_ms, at_mono: now_mono, at_wall: now_wall}
  end

  defp control(_session, :reset, _now_mono, _now_wall) do
    %{status: :paused, position_ms: 0, at_mono: 0, at_wall: 0}
  end

  defp current_position(session, now_mono) do
    case session.status do
      :playing -> session.position_ms + (now_mono - session.at_mono)
      :paused -> session.position_ms
    end
  end

  # The payload: everything a client needs to know where "now" is, computed
  # at the same instant for position and at.
  defp payload(session, now_mono, now_wall) do
    %{
      status: session.status,
      position_ms: current_position(session, now_mono),
      at: now_wall
    }
  end

  defp broadcast(nf_id, session) do
    now_mono = monotonic()
    now_wall = wall()

    PubSubModule.broadcast(Dave.PubSub, "score:#{nf_id}", {
      :state,
      payload(session, now_mono, now_wall)
    })
  end

  defp monotonic, do: System.monotonic_time(:millisecond)
  defp wall, do: System.system_time(:millisecond)
end
