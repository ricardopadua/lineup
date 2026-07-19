defmodule Lineup.Agents.Waves do
  @moduledoc """
  Fetches current wave conditions from the free, keyless Open-Meteo Marine
  API. Retries and caching are handled by `Lineup.Agents.Server`.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://marine-api.open-meteo.com/v1/marine"

  @impl true
  def name, do: :waves

  @impl true
  def cache_ttl, do: :timer.minutes(10)

  @impl true
  def fetch(%{lat: lat, lon: lon}) do
    params = [latitude: lat, longitude: lon, current: "wave_height,wave_direction,wave_period"]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 4_000) do
      {:ok, %Req.Response{status: 200, body: %{"current" => current}}} ->
        {:ok,
         %{
           wave_height_m: current["wave_height"],
           wave_direction_deg: current["wave_direction"],
           wave_period_s: current["wave_period"]
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_lat_lon}
end
