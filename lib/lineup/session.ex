defmodule Lineup.Session do
  @moduledoc """
  Per-user state machine: the single source of truth for one user's
  conversation. Holds chat history, whatever intent has resolved so far
  (currently just `lat`/`lon`), and every agent result gathered — however
  it was obtained (an async trigger or the full Orchestrator fan-out).

  One process per `user_id`, started on demand, checkpointed into
  `Lineup.Cache` after every transition so a crash (process or node)
  rehydrates instead of losing the conversation. Idle sessions stop
  themselves after `session_idle_timeout_ms`; the checkpoint is what
  makes that safe — the next message just starts a fresh process that
  picks up where the old one left off.
  """

  use GenServer
  require Logger

  @idle_timeout Application.compile_env(:lineup, :session_idle_timeout_ms, :timer.minutes(30))
  @checkpoint_ttl :timer.hours(24)

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via(user_id))
  end

  def via(user_id), do: {:via, Registry, {Lineup.SessionRegistry, user_id}}

  @doc """
  Sends a chat message to `user_id`'s session, starting it if it isn't
  already running. Returns `{:ok, reply}`.
  """
  @spec message(term(), String.t()) :: {:ok, String.t()}
  def message(user_id, text) do
    ensure_started(user_id)
    GenServer.call(via(user_id), {:message, text}, 20_000)
  end

  defp ensure_started(user_id) do
    case Lineup.Session.Supervisor.start_session(user_id) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @impl true
  def init(user_id) do
    state =
      case Lineup.Cache.get({:session, user_id}) do
        {:ok, saved} -> saved
        {:stale, saved} -> saved
        :error -> fresh_state(user_id)
      end

    {:ok, state, @idle_timeout}
  end

  defp fresh_state(user_id) do
    %{user_id: user_id, history: [], base_request: %{}, agent_results: %{}}
  end

  @impl true
  def handle_call({:message, text}, _from, state) do
    state = append_history(state, :user, text)
    {reply, state} = respond(text, state)
    state = append_history(state, :assistant, reply)
    checkpoint(state)
    {:reply, {:ok, reply}, state, @idle_timeout}
  end

  # Location already resolved earlier in this conversation — go straight
  # to the full fan-out.
  defp respond(text, %{base_request: %{lat: _lat, lon: _lon}} = state) do
    fan_out_and_reply(text, state)
  end

  # No location yet — this message is the trigger: try to resolve one
  # before we can call any data agent at all. Just stating a place
  # ("I'm in Formosa Beach") shouldn't immediately dump a full recommendation —
  # only fan out if this same message actually asks something; otherwise
  # ask a clarifying follow-up and wait for the next turn.
  defp respond(text, state) do
    case extract_signals(text) do
      {:ok, %{place: nil}} ->
        {"Where are you surfing today?", state}

      {:ok, %{place: place, has_question: has_question?}} ->
        case Lineup.Agents.Server.call(:geocode, %{query: place}) do
          {:ok, %{lat: lat, lon: lon}} ->
            base_request = %{lat: lat, lon: lon}

            state =
              state
              |> Map.put(:base_request, base_request)
              |> trigger_async_spots(base_request)

            if has_question? do
              fan_out_and_reply(text, state)
            else
              reply =
                "Got it, #{place}! Want to know how it's looking right now, " <>
                  "or were you thinking about a specific day or time?"

              {reply, state}
            end

          _ ->
            {"Couldn't find \"#{place}\" — mind naming the city or beach again?", state}
        end

      :error ->
        {"Where are you surfing today?", state}
    end
  end

  defp fan_out_and_reply(text, state) do
    result = Lineup.Orchestrator.consult(Map.put(state.base_request, :question, text))
    agent_results = Map.merge(state.agent_results, Map.delete(result, :recommendation))
    state = %{state | agent_results: agent_results}

    reply =
      case result.recommendation do
        {:ok, content} ->
          content

        {:stale, content} ->
          content

        {:error, _reason} ->
          "Couldn't put together a recommendation right now — try again in a bit."
      end

    {reply, state}
  end

  # Fires `:spots` in the background the moment location is known,
  # instead of waiting for the rest of the intent — its result merges in
  # via handle_info/2 whenever it lands.
  defp trigger_async_spots(state, base_request) do
    session = self()

    Task.Supervisor.start_child(Lineup.TaskSupervisor, fn ->
      result = Lineup.Agents.Server.call(:spots, base_request, timeout: 6_000)
      send(session, {:spots_result, result})
    end)

    state
  end

  # Combined into one LLM call (JSON mode, temperature 0) rather than two:
  # which place is mentioned, if any, and whether the message is actually
  # asking for something or just stating context.
  defp extract_signals(text) do
    messages = [
      %{
        "role" => "system",
        "content" =>
          "Extract structured signals from a surfer's chat message. Reply " <>
            "with a JSON object with exactly two keys: " <>
            "\"place\" — the city, neighborhood, or beach mentioned, or null " <>
            "if none is mentioned; " <>
            "\"has_question\" — true if the user is asking something or " <>
            "wants a recommendation, false if they are only stating where " <>
            "they are with no request attached."
      },
      %{"role" => "user", "content" => text}
    ]

    with {:ok, %{"content" => content}} <- Lineup.Groq.chat(messages, temperature: 0, json: true),
         {:ok, %{"place" => place, "has_question" => has_question}} <- Jason.decode(content) do
      {:ok, %{place: place, has_question: has_question == true}}
    else
      _ -> :error
    end
  end

  @impl true
  def handle_info({:spots_result, result}, state) do
    state = %{state | agent_results: Map.put(state.agent_results, :spots, result)}
    checkpoint(state)
    {:noreply, state, @idle_timeout}
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.debug("Lineup.Session[#{inspect(state.user_id)}] idle, stopping")
    {:stop, :normal, state}
  end

  defp append_history(state, role, content) do
    %{state | history: state.history ++ [%{role: role, content: content}]}
  end

  defp checkpoint(state) do
    Lineup.Cache.put({:session, state.user_id}, state, @checkpoint_ttl)
  end
end
