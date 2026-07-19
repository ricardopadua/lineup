defmodule Lineup.Agents.Spots do
  @moduledoc """
  Surf spot metadata: local rules, characteristics, recommended skill
  level, seabed type, etc.

  Not implemented yet — this needs a real spot knowledge base/database to
  back it. Registered and supervised like every other agent so the rest of
  the system (Orchestrator, caching, circuit breaker) already knows how to
  handle it once it's filled in; for now it always reports unavailable.
  """

  @behaviour Lineup.Agents.Behaviour

  @impl true
  def name, do: :spots

  @impl true
  def cache_ttl, do: :timer.minutes(1)

  @impl true
  def fetch(_request), do: {:error, :not_implemented}
end
