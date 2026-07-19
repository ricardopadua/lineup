defmodule Lineup.Application do
  @moduledoc false

  use Application

  alias Lineup.Agents.WaveAgent, as: Wave
  alias Lineup.Agents.WindAgent, as: Wind
  alias Lineup.Agents.BuddyAgent, as: Buddy
  alias Lineup.Agents.Supervisor, as: AgentSupervisor

  @agents [Wave, Wind, Buddy]
  @opts [strategy: :one_for_one, name: Lineup.Supervisor]

  @children [
    Lineup.Cache,
    {Registry, keys: :unique, name: Lineup.AgentRegistry},
    {Task.Supervisor, name: Lineup.TaskSupervisor},
    Lineup.Agents.Supervisor
  ]

  @impl true
  def start(_type, _args) do
    load_dotenv()

    @children
    |> Supervisor.start_link(@opts)
    |> spawn_agents(@agents)
  end

  defp spawn_agents({:ok, _} = result, list), do: loop_agents(list, result)
  defp spawn_agents(error, _), do: error

  defp loop_agents([], result), do: result

  defp loop_agents([agent | tail], result),
    do:
      (
        AgentSupervisor.start_agent(agent)
        loop_agents(tail, result)
      )

  # `.env` isn't loaded by the BEAM automatically; pick up LLM_NAME/LLM_API_KEY
  # (and anything else) from it without needing an extra dependency.
  defp load_dotenv do
    case File.read(".env") do
      {:ok, contents} ->
        contents
        |> String.split("\n", trim: true)
        |> Enum.each(&put_env_line/1)

      {:error, _} ->
        :ok
    end
  end

  defp put_env_line(line) do
    line = String.trim(line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] -> System.put_env(String.trim(key), String.trim(value))
        _ -> :ok
      end
    end
  end
end
