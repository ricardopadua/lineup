defmodule Lineup.Agents.Weather do
  @moduledoc """
  Fetches current weather conditions (air temperature, wind, cloud cover,
  precipitation) from the free, keyless Open-Meteo Weather API.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://api.open-meteo.com/v1/forecast"

  @impl true
  def name, do: :weather

  @impl true
  def cache_ttl, do: :timer.minutes(5)

  @impl true
  def fetch(%{lat: lat, lon: lon}) do
    params = [
      latitude: lat,
      longitude: lon,
      current:
        "temperature_2m,wind_speed_10m,wind_direction_10m,wind_gusts_10m,cloud_cover,precipitation,weather_code"
    ]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 4_000) do
      {:ok, %Req.Response{status: 200, body: %{"current" => current}}} ->
        {:ok,
         %{
           air_temp_c: current["temperature_2m"],
           wind_speed_kmh: current["wind_speed_10m"],
           wind_direction_deg: current["wind_direction_10m"],
           wind_gusts_kmh: current["wind_gusts_10m"],
           cloud_cover_pct: current["cloud_cover"],
           precipitation_mm: current["precipitation"],
           weather_code: current["weather_code"]
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_lat_lon}
end
