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
end
