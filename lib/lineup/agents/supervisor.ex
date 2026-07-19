defmodule Lineup.Agents.Supervisor do
  @moduledoc """
  Supervises one `Lineup.Agents.Server` process per registered agent.

  `:one_for_one` means a crash in one agent restarts only that agent —
  siblings are untouched. `max_restarts`/`max_seconds` bound how many times
  that can happen in a short window so a single pathological agent
  crash-looping can't exhaust the tree's restart budget and take the whole
  supervisor down with it.
  """

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 5, max_seconds: 10)
  end

  @spec start_agent(module()) :: DynamicSupervisor.on_start_child()
  def start_agent(module) do
    spec = %{
      id: module,
      start: {Lineup.Agents.Server, :start_link, [module]},
      restart: :permanent
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
