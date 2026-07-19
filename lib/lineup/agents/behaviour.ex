defmodule Lineup.Agents.Behaviour do
  @moduledoc """
  Behaviour implemented by every concrete data or LLM agent.

  A module implementing this behaviour is plain, stateless logic (an HTTP
  call, an LLM call). `Lineup.Agents.Server` is the process that wraps it with
  caching, retries, and a circuit breaker, so implementing a new agent never
  requires writing any new process-management code.
  """

  @type request :: map()
  @type result :: term()

  @doc "Registry name this agent is looked up by (e.g. `:wave`)."
  @callback name() :: atom()

  @doc "How long a successful result stays fresh in the cache, in milliseconds."
  @callback cache_ttl() :: pos_integer()

  @doc "Performs the actual work. May raise; `Lineup.Agents.Server` handles that."
  @callback fetch(request()) :: {:ok, result()} | {:error, term()}
end
