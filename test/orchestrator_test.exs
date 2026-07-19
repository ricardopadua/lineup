defmodule Lineup.OrchestratorTest do
  use ExUnit.Case, async: false

  defmodule OkAgent do
    @behaviour Lineup.Agents.Behaviour
    @impl true
    def name, do: :test_ok_agent
    @impl true
    def cache_ttl, do: :timer.seconds(5)
    @impl true
    def fetch(_request), do: {:ok, %{status: :fine}}
  end

  defmodule CrashAgent do
    @behaviour Lineup.Agents.Behaviour
    @impl true
    def name, do: :test_crash_agent
    @impl true
    def cache_ttl, do: :timer.seconds(5)
    @impl true
    def fetch(_request), do: raise("boom")
  end

  setup do
    {:ok, _} = Lineup.Agents.Supervisor.start_agent(OkAgent)
    {:ok, _} = Lineup.Agents.Supervisor.start_agent(CrashAgent)

    on_exit(fn ->
      stop_agent(:test_ok_agent)
      stop_agent(:test_crash_agent)
    end)

    :ok
  end

  test "fan_out returns partial results when one agent keeps crashing" do
    results = Lineup.Orchestrator.fan_out(%{}, [:test_ok_agent, :test_crash_agent])

    assert {:ok, %{status: :fine}} = results[:test_ok_agent]
    assert {:error, _reason} = results[:test_crash_agent]
  end

  defp stop_agent(name) do
    case Registry.lookup(Lineup.AgentRegistry, name) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Lineup.Agents.Supervisor, pid)
      [] -> :ok
    end
  end
end
