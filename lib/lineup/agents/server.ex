defmodule Lineup.Agents.Server do
  @moduledoc """
  Generic GenServer that wraps any `Lineup.Agent` implementation.

  Responsibilities live here once, instead of being duplicated per agent:

    * cache-aside reads/writes through `Lineup.Cache`
    * bounded retry with exponential backoff + jitter on failure
    * a per-agent circuit breaker (closed -> open -> half-open) so a
      failing upstream (an HTTP API, the LLM provider) stops being
      hammered once it is clearly down
    * telemetry events around every call

  Each agent runs as its own process under `Lineup.Agents.Supervisor`, so one
  agent crashing or repeatedly failing never affects the others.
  """

  use GenServer
  require Logger

  @max_attempts Application.compile_env(:lineup, :agent_max_attempts, 3)
  @base_backoff_ms Application.compile_env(:lineup, :agent_base_backoff_ms, 200)
  @failure_threshold Application.compile_env(:lineup, :agent_failure_threshold, 5)
  @open_cooldown_ms Application.compile_env(:lineup, :agent_open_cooldown_ms, :timer.seconds(30))

  defmodule State do
    @moduledoc false
    defstruct [:module, :name, circuit: :closed, failures: 0, opened_at: nil]
  end

  def start_link(module) do
    GenServer.start_link(__MODULE__, module, name: via(module.name()))
  end

  def via(name), do: {:via, Registry, {Lineup.AgentRegistry, name}}

  @doc """
  Consults the named agent. Always returns a result instead of raising:

    * `{:ok, value}` — fresh, either from cache or a live fetch
    * `{:stale, value}` — the live fetch failed or the circuit is open,
      but a previous (expired) value was available
    * `{:error, reason}` — no cached value exists either
  """
  @spec call(atom(), map(), keyword()) :: {:ok, term()} | {:stale, term()} | {:error, term()}
  def call(name, request, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    GenServer.call(via(name), {:consult, request}, timeout)
  catch
    :exit, {:noproc, _} -> {:error, :agent_unavailable}
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, reason -> {:error, reason}
  end

  @impl true
  def init(module) do
    {:ok, %State{module: module, name: module.name()}}
  end

  @impl true
  def handle_call({:consult, request}, _from, %State{name: name} = state) do
    cache_key = {name, request}

    case Lineup.Cache.get(cache_key) do
      {:ok, value} ->
        {:reply, {:ok, value}, state}

      cached ->
        case circuit_status(state) do
          :open ->
            {:reply, fallback(cached, :circuit_open), state}

          _ ->
            do_fetch(request, cache_key, cached, state)
        end
    end
  end

  defp do_fetch(request, cache_key, cached, %State{module: module, name: name} = state) do
    start = System.monotonic_time()

    :telemetry.execute([:lineup, :agent, :start], %{system_time: System.system_time()}, %{
      agent: name
    })

    case call_with_retry(module, request, @max_attempts) do
      {:ok, value} ->
        Lineup.Cache.put(cache_key, value, module.cache_ttl())
        emit_stop(name, start, :ok)
        {:reply, {:ok, value}, %{state | circuit: :closed, failures: 0, opened_at: nil}}

      {:error, reason} ->
        emit_stop(name, start, :error)
        new_state = register_failure(state)
        {:reply, fallback(cached, reason), new_state}
    end
  end

  defp call_with_retry(module, request, attempts_left, attempt \\ 1)

  defp call_with_retry(module, request, 1, _attempt) do
    module.fetch(request)
  rescue
    e -> {:error, e}
  end

  defp call_with_retry(module, request, attempts_left, attempt) when attempts_left > 1 do
    case module.fetch(request) do
      {:ok, _} = ok -> ok
      {:error, _reason} -> retry_after_backoff(module, request, attempts_left, attempt)
    end
  rescue
    _e -> retry_after_backoff(module, request, attempts_left, attempt)
  end

  defp retry_after_backoff(module, request, attempts_left, attempt) do
    backoff = round(@base_backoff_ms * :math.pow(2, attempt - 1))
    jitter = :rand.uniform(div(backoff, 2) + 1)
    Process.sleep(backoff + jitter)
    call_with_retry(module, request, attempts_left - 1, attempt + 1)
  end

  defp fallback({:stale, value}, _reason), do: {:stale, value}
  defp fallback(:error, reason), do: {:error, reason}

  defp circuit_status(%State{circuit: :closed}), do: :closed

  defp circuit_status(%State{circuit: :open, opened_at: opened_at}) do
    if System.monotonic_time(:millisecond) - opened_at > @open_cooldown_ms do
      :half_open
    else
      :open
    end
  end

  defp register_failure(%State{failures: failures, name: name} = state) do
    failures = failures + 1

    if failures >= @failure_threshold do
      Logger.warning(
        "Lineup.Agents.Server[#{name}] opening circuit after #{failures} consecutive failures"
      )

      %{
        state
        | circuit: :open,
          failures: failures,
          opened_at: System.monotonic_time(:millisecond)
      }
    else
      %{state | failures: failures}
    end
  end

  defp emit_stop(name, start, result) do
    duration = System.monotonic_time() - start

    :telemetry.execute([:lineup, :agent, :stop], %{duration: duration}, %{
      agent: name,
      result: result
    })
  end
end
