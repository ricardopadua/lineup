defmodule Lineup.Session.Supervisor do
  @moduledoc """
  Supervises one `Lineup.Session` process per active user.

  `:one_for_one` isolates crashes to a single user's session. Children
  are `restart: :transient`: a crash restarts the session (it rehydrates
  its checkpoint from `Lineup.Cache` in `init/1`), but a deliberate
  idle-timeout stop does not — the next message from that user just
  starts a fresh process that rehydrates the same way.
  """

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_session(term()) :: DynamicSupervisor.on_start_child()
  def start_session(user_id) do
    spec = %{
      id: {Lineup.Session, user_id},
      start: {Lineup.Session, :start_link, [user_id]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
