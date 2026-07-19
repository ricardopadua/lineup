defmodule Lineup.Agents.Traffic do
  @moduledoc """
  Estimates driving time from the surfer's location to the spot using the
  free, keyless OSRM public routing API.

  Note: the public OSRM demo server computes routing distance/duration
  from road network data, not live traffic conditions — it's a real,
  working stand-in until this is wired up to a proper traffic-aware
  provider (e.g. Google Distance Matrix, Mapbox).

  Expects a request shaped like:

      %{lat: origin_lat, lon: origin_lon, spot: %{lat: spot_lat, lon: spot_lon}}
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://router.project-osrm.org/route/v1/driving"

  @impl true
  def name, do: :traffic

  @impl true
  def cache_ttl, do: :timer.minutes(5)

  @impl true
  def fetch(%{lat: lat, lon: lon, spot: %{lat: spot_lat, lon: spot_lon}}) do
    url = "#{@base_url}/#{lon},#{lat};#{spot_lon},#{spot_lat}"

    case Req.get(url, params: [overview: "false"], retry: false, receive_timeout: 5_000) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"routes" => [%{"duration" => seconds, "distance" => meters} | _]}
       }} ->
        {:ok,
         %{
           travel_time_min: round(seconds / 60),
           distance_km: Float.round(meters / 1000, 1)
         }}

      {:ok, %Req.Response{status: 200, body: _body}} ->
        {:error, :no_route_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_spot}
end
