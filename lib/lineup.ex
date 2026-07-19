defmodule Lineup do
  @moduledoc """
  Public API: concurrent, fault-tolerant surf-conditions consultation.

      Lineup.consult(%{lat: -27.5, lon: -48.5})
      #=> %{
      #     wave: {:ok, %{wave_height_m: 1.2, ...}},
      #     wind: {:error, :timeout},          # one agent failing doesn't block the rest
      #     recommendation: {:ok, "Conditions look fair..."}
      #   }
  """

  @spec consult(map()) :: map()
  defdelegate consult(request), to: Lineup.Orchestrator

  @doc """
  Sends a chat message to `user_id`'s session (started on demand),
  resolving location and consulting agents as needed. Returns
  `{:ok, reply}`.

      Lineup.chat("user-1", "I'm in Formosa Beach, worth going out today?")
  """
  @spec chat(term(), String.t()) :: {:ok, String.t()}
  defdelegate chat(user_id, text), to: Lineup.Session, as: :message
end
