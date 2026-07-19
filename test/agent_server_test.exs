defmodule Lineup.Agents.ServerTest do
  use ExUnit.Case, async: false

  defmodule AlwaysFailAgent do
    @behaviour Lineup.Agents.Behaviour
    @impl true
    def name, do: :test_always_fail_agent
    @impl true
    def cache_ttl, do: :timer.seconds(5)
    @impl true
    def fetch(_request), do: {:error, :boom}
  end

  setup do
    {:ok, _} = Lineup.Agents.Supervisor.start_agent(AlwaysFailAgent)

    on_exit(fn ->
      case Registry.lookup(Lineup.AgentRegistry, :test_always_fail_agent) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Lineup.Agents.Supervisor, pid)
        [] -> :ok
      end
    end)

    :ok
  end

  test "circuit opens after repeated failures and then short-circuits" do
    threshold = Application.get_env(:lineup, :agent_failure_threshold, 5)

    for _ <- 1..threshold do
      assert {:error, _reason} = Lineup.Agents.Server.call(:test_always_fail_agent, %{})
    end

    assert {:error, :circuit_open} = Lineup.Agents.Server.call(:test_always_fail_agent, %{})
  end
end
