defmodule Lineup.SessionTest do
  use ExUnit.Case, async: false

  test "starts on demand and is reachable via the registry" do
    user_id = "session-test-#{System.unique_integer([:positive])}"

    refute Registry.lookup(Lineup.SessionRegistry, user_id) != []

    {:ok, pid} = Lineup.Session.Supervisor.start_session(user_id)
    assert [{^pid, _}] = Registry.lookup(Lineup.SessionRegistry, user_id)
    assert Process.alive?(pid)
  end

  test "starting twice for the same user returns the same process" do
    user_id = "session-test-dup-#{System.unique_integer([:positive])}"

    {:ok, pid} = Lineup.Session.Supervisor.start_session(user_id)
    assert {:error, {:already_started, ^pid}} = Lineup.Session.Supervisor.start_session(user_id)
  end

  test "an idle session stops itself, cleanly, without being restarted" do
    user_id = "session-test-idle-#{System.unique_integer([:positive])}"

    {:ok, pid} = Lineup.Session.Supervisor.start_session(user_id)
    ref = Process.monitor(pid)

    # session_idle_timeout_ms is 100ms in :test config (see config/config.exs)
    send(pid, :timeout)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

    # Registry removes the entry via its own monitor on the same process,
    # which isn't guaranteed to have run yet just because *our* monitor
    # already got the DOWN — give it a moment before checking.
    Process.sleep(20)
    assert Registry.lookup(Lineup.SessionRegistry, user_id) == []
  end
end
