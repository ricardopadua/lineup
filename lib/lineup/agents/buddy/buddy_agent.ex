defmodule Lineup.Agents.BuddyAgent do
  @moduledoc """
  Synthesizes a surf recommendation from the other agents' results using
  Groq's OpenAI-compatible chat-completions endpoint.

  Implements a bounded ReAct-style agentic loop: the model can call the
  `reconsult` tool to re-check a data agent (subject to the normal cache)
  if it judges the given conditions insufficient, before producing a final
  answer. `@max_iterations` is a hard safety rail against a runaway loop.
  """

  @behaviour Lineup.Agents.Behaviour

  require Logger

  @base_url "https://api.groq.com/openai/v1/chat/completions"
  @max_iterations 3

  @tools [
    %{
      "type" => "function",
      "function" => %{
        "name" => "reconsult",
        "description" =>
          "Re-check a data agent's current conditions (subject to normal caching).",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "agent" => %{"type" => "string", "enum" => ["wave", "wind"]}
          },
          "required" => ["agent"]
        }
      }
    }
  ]

  @impl true
  def name, do: :buddy

  @impl true
  def cache_ttl, do: :timer.minutes(2)

  @impl true
  def fetch(request) do
    conditions = Map.get(request, :conditions, %{})

    messages = [
      %{"role" => "system", "content" => system_prompt()},
      %{"role" => "user", "content" => "Current conditions: #{Jason.encode!(conditions)}"}
    ]

    loop(messages, @max_iterations)
  end

  defp loop(_messages, 0), do: {:error, :max_iterations_reached}

  defp loop(messages, iterations_left) do
    case chat_completion(messages) do
      {:ok, %{"tool_calls" => tool_calls} = message}
      when is_list(tool_calls) and tool_calls != [] ->
        messages = messages ++ [strip_nil(message)] ++ Enum.map(tool_calls, &run_tool/1)
        loop(messages, iterations_left - 1)

      {:ok, %{"content" => content}} when is_binary(content) ->
        {:ok, content}

      {:ok, _other} ->
        {:error, :unexpected_llm_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_tool(%{"id" => id, "function" => %{"name" => "reconsult", "arguments" => args_json}}) do
    result =
      with {:ok, %{"agent" => agent}} <- Jason.decode(args_json),
           atom_agent <- String.to_existing_atom(agent),
           {:ok, value} <- Lineup.Agents.Server.call(atom_agent, %{}, timeout: 6_000) do
        Jason.encode!(value)
      else
        _ -> Jason.encode!(%{error: "reconsult_failed"})
      end

    %{"role" => "tool", "tool_call_id" => id, "content" => result}
  end

  defp chat_completion(messages) do
    body = %{
      "model" => System.get_env("LLM_MODEL", "llama-3.3-70b-versatile"),
      "messages" => messages,
      "tools" => @tools,
      "temperature" => 0.3
    }

    case Req.post(@base_url,
           json: body,
           auth: {:bearer, System.get_env("LLM_API_KEY")},
           retry: false,
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"choices" => [%{"message" => message} | _]}}} ->
        {:ok, message}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("Groq request failed: #{status} #{inspect(body)}")
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp strip_nil(message), do: Map.reject(message, fn {_k, v} -> is_nil(v) end)

  defp system_prompt do
    """
    You are a surf conditions assistant. Given wave and wind data, produce a
    short recommendation on whether conditions are good to surf right now.
    If the provided data for an agent is missing or looks wrong, you may
    call the `reconsult` tool once per agent. Otherwise answer directly.
    """
  end
end
