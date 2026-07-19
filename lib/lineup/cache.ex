defmodule Lineup.Cache do
  @moduledoc """
  ETS-backed cache shared by every agent.

  Reads hit the public ETS table directly (no message-passing to a
  GenServer), which is what keeps this cheap under high concurrency. Writes
  go through the owner process. Entries carry both a fresh TTL and a longer
  "stale" grace window: once the TTL passes but before the grace window
  ends, `get/1` still returns the value tagged `:stale` so callers can fall
  back to slightly-old data instead of nothing when an agent is failing. A
  periodic sweep loop evicts anything past the grace window.
  """

  use GenServer
  require Logger

  @table :lineup_cache
  @sweep_interval :timer.seconds(30)
  @stale_grace_multiplier 5

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec get(term()) :: {:ok, term()} | {:stale, term()} | :error
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at, stale_until}] ->
        now = System.monotonic_time(:millisecond)

        cond do
          now < expires_at -> {:ok, value}
          now < stale_until -> {:stale, value}
          true -> :error
        end

      [] ->
        :error
    end
  end

  @spec put(term(), term(), pos_integer()) :: :ok
  def put(key, value, ttl_ms) do
    now = System.monotonic_time(:millisecond)
    expires_at = now + ttl_ms
    stale_until = expires_at + ttl_ms * @stale_grace_multiplier
    :ets.insert(@table, {key, value, expires_at, stale_until})
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    match_spec = [{{:_, :_, :_, :"$1"}, [{:<, :"$1", now}], [true]}]
    deleted = :ets.select_delete(@table, match_spec)

    if deleted > 0 do
      Logger.debug("Lineup.Cache swept #{deleted} expired entries")
    end

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
