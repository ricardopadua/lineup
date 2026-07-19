defmodule Lineup.Groq do
  @moduledoc """
  Thin client for Groq's OpenAI-compatible chat-completions endpoint.
  Shared by `Lineup.Agents.BuddyAgent` (surf recommendation synthesis)
  and `Lineup.Session` (small structured-extraction calls during intent
  discovery) so the HTTP/auth/parsing boilerplate lives in one place.
  """

  require Logger

  @base_url "https://api.groq.com/openai/v1/chat/completions"

  @doc """
  Sends `messages` (OpenAI-style role/content maps) to Groq.

  Options:
    * `:tools` — OpenAI-style tool schemas, omitted if not given
    * `:json` — when `true`, asks Groq for strict JSON-object output
      (`response_format: {"type" => "json_object"}`) instead of free text —
      use this for structured-extraction calls instead of hoping the model
      follows a "reply with JSON only" instruction
    * `:temperature` — defaults to `0.3`
    * `:receive_timeout` — defaults to `10_000`

  Returns `{:ok, message}` where `message` is the raw assistant message
  map (may contain `"tool_calls"`), or `{:error, reason}`.
  """
  @spec chat([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def chat(messages, opts \\ []) do
    body =
      %{
        "model" => System.get_env("LLM_MODEL", "llama-3.3-70b-versatile"),
        "messages" => messages,
        "temperature" => Keyword.get(opts, :temperature, 0.3)
      }
      |> maybe_put_tools(opts[:tools])
      |> maybe_put_json_mode(opts[:json])

    case Req.post(@base_url,
           json: body,
           auth: {:bearer, System.get_env("LLM_API_KEY")},
           retry: false,
           receive_timeout: Keyword.get(opts, :receive_timeout, 10_000)
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

  defp maybe_put_tools(body, nil), do: body
  defp maybe_put_tools(body, tools), do: Map.put(body, "tools", tools)

  defp maybe_put_json_mode(body, true),
    do: Map.put(body, "response_format", %{"type" => "json_object"})

  defp maybe_put_json_mode(body, _falsy), do: body
end
