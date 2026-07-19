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
          "Re-check a data agent's conditions (subject to normal caching). " <>
            "For `tide`, optionally pass `dates` to get the tide table for " <>
            "other day(s) instead of just today — use this when the surfer " <>
            "asks about a specific day.",
        "parameters" => %{
          "type" => "object",
          "properties" => %{
            "agent" => %{
              "type" => "string",
              "enum" => ["waves", "weather", "water_temp", "tide", "sun"]
            },
            "dates" => %{
              "type" => "array",
              "items" => %{"type" => "string", "format" => "date"},
              "description" =>
                "Only used when agent is \"tide\". ISO 8601 dates, e.g. \"2026-07-20\"."
            }
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
    question = Map.get(request, :question)
    base_request = Map.take(request, [:lat, :lon])

    messages = [
      %{"role" => "system", "content" => system_prompt()},
      %{"role" => "user", "content" => user_prompt(question, conditions)}
    ]

    loop(messages, @max_iterations, base_request)
  end

  # No question from the surfer: default to whatever the conditions map
  # already contains (today only — see Lineup.Agents.Tide).
  defp user_prompt(nil, conditions) do
    "Today is #{Date.utc_today()}. Conditions: #{Jason.encode!(conditions)}"
  end

  defp user_prompt(question, conditions) do
    "Today is #{Date.utc_today()}. The surfer asked: \"#{question}\"\n" <>
      "Conditions: #{Jason.encode!(conditions)}"
  end

  defp loop(_messages, 0, _base_request), do: {:error, :max_iterations_reached}

  defp loop(messages, iterations_left, base_request) do
    case chat_completion(messages) do
      {:ok, %{"tool_calls" => tool_calls} = message}
      when is_list(tool_calls) and tool_calls != [] ->
        tool_results = Enum.map(tool_calls, &run_tool(&1, base_request))
        messages = messages ++ [strip_nil(message)] ++ tool_results
        loop(messages, iterations_left - 1, base_request)

      {:ok, %{"content" => content}} when is_binary(content) ->
        {:ok, content}

      {:ok, _other} ->
        {:error, :unexpected_llm_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_tool(
         %{"id" => id, "function" => %{"name" => "reconsult", "arguments" => args_json}},
         base_request
       ) do
    result =
      with {:ok, args} <- Jason.decode(args_json),
           %{"agent" => agent} <- args,
           atom_agent <- String.to_existing_atom(agent),
           agent_request <- with_dates(base_request, args["dates"]),
           {:ok, value} <- Lineup.Agents.Server.call(atom_agent, agent_request, timeout: 6_000) do
        Jason.encode!(value)
      else
        _ -> Jason.encode!(%{error: "reconsult_failed"})
      end

    %{"role" => "tool", "tool_call_id" => id, "content" => result}
  end

  defp with_dates(base_request, dates) when is_list(dates) and dates != [] do
    Map.put(base_request, :dates, dates)
  end

  defp with_dates(base_request, _dates), do: base_request

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
    You are an experienced local surfer helping another surfer decide if it's worth paddling out.

    Talk like you're texting a surf buddy after checking the forecast. Be friendly, confident and natural. Never sound like a weather report or an AI assistant.

    Keep your response between 70 and 120 words.

    Analyze all available information together:
    - Wave conditions
    - Weather
    - Wind
    - Tide table
    - Water temperature
    - Sunrise and sunset
    - Surf spot information (if available)

    Don't simply repeat the forecast. Interpret it like an experienced surfer would.

    Naturally include:
    - Whether today is worth surfing.
    - Why the conditions look good or bad.
    - Which board you'd ride (shortboard, fish, funboard, longboard, etc.).
    - Whether a wetsuit is needed.
    - One useful tip or warning if applicable.

    When a tide table is available, analyze the entire tide cycle and recommend the best surfing windows.

    Be specific with time ranges. Say things like "6:00–8:00 AM" or "4:30–6:00 PM". Never say only "in the morning", "later today", or "around high tide".

    Determine the recommended surf windows by combining:
    - tide table
    - waves
    - wind
    - sunrise/sunset
    - surf spot characteristics

    If there are multiple good sessions, recommend them in order of quality and briefly explain why.

    Mention wave height, wind, tide or water temperature only when they help justify your recommendation. Avoid dumping raw numbers.

    Do not use bullet points.
    Do not explain your reasoning step by step.
    Do not list every metric.
    Keep the conversation flowing naturally, like two surfers talking before a session.

    If data from an agent is missing or appears incorrect, you may call the `reconsult` tool once for that specific agent. Otherwise, answer using the available data.
    """
  end
end
