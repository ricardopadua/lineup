defmodule Lineup.Agents.WaterTemp do
  @moduledoc """
  Fetches current sea surface temperature from the free, keyless
  Open-Meteo Marine API.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://marine-api.open-meteo.com/v1/marine"

  @impl true
  def name, do: :water_temp

  @impl true
  def cache_ttl, do: :timer.minutes(30)

  @impl true
  def fetch(%{lat: lat, lon: lon}) do
    params = [latitude: lat, longitude: lon, current: "sea_surface_temperature"]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 4_000) do
      {:ok, %Req.Response{status: 200, body: %{"current" => current}}} ->
        {:ok, %{water_temp_c: current["sea_surface_temperature"]}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_lat_lon}
end
