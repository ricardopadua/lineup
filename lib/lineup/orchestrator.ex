defmodule Lineup.Orchestrator do
  @moduledoc """
  Fans a consult request out to every data agent concurrently, tolerates
  any subset of them failing or hanging, then asks the LLM agent to
  synthesize a recommendation from whatever data actually came back.
  """

  # :traffic needs an extra `:spot` destination in the request and :spots
  # isn't implemented yet, so both are opt-in rather than part of the
  # default fan-out (call fan_out/2 or consult/2 directly to include them).
  @default_agents [:waves, :weather, :water_temp, :tide, :sun]
  @per_agent_timeout 6_000

  @spec consult(map(), [atom()]) :: map()
  def consult(request, agents \\ @default_agents) do
    results = fan_out(request, agents)
    conditions = summarize(results)
    recommendation = Lineup.Agents.Server.call(:buddy, Map.put(request, :conditions, conditions))
    Map.put(results, :recommendation, recommendation)
  end

  # `results` carries {:ok, _} / {:stale, _} / {:error, _} tags for the
  # caller's benefit, but tuples have no Jason.Encoder — BuddyAgent needs a
  # plain, JSON-safe map to hand the LLM.
  defp summarize(results) do
    Map.new(results, fn
      {agent, {:ok, value}} -> {agent, value}
      {agent, {:stale, value}} -> {agent, Map.put(value, :stale, true)}
      {agent, {:error, reason}} -> {agent, %{error: inspect(reason)}}
    end)
  end

  @doc """
  Concurrently consults `agents` and returns `%{agent_name => result}`.

  Uses `Task.Supervisor.async_stream_nolink/4` (not `Task.async/await`):
  `nolink` means a crashing task never crashes the caller, and
  `on_timeout: :kill_task` means a hung agent gets killed instead of
  blocking the whole batch. Either way the caller still gets a result for
  every other agent — partial failure, not total failure.
  """
  @spec fan_out(map(), [atom()]) :: %{atom() => term()}
  def fan_out(request, agents) do
    Lineup.TaskSupervisor
    |> Task.Supervisor.async_stream_nolink(
      agents,
      fn agent ->
        {agent, Lineup.Agents.Server.call(agent, request, timeout: @per_agent_timeout)}
      end,
      timeout: @per_agent_timeout,
      on_timeout: :kill_task,
      max_concurrency: max(length(agents), 1)
    )
    |> Enum.zip(agents)
    |> Map.new(fn
      {{:ok, {agent, result}}, _agent} -> {agent, result}
      {{:exit, _reason}, agent} -> {agent, {:error, :agent_crashed}}
    end)
  end
end
