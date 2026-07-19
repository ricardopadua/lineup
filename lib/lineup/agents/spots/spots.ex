defmodule Lineup.Agents.Spots do
  @moduledoc """
  Local surf spot knowledge: which known spots are near a given point.

  Backed by a small hardcoded seed list — not a real spot database yet
  (no rules/skill-level/seabed detail per spot), but a real, working
  distance filter rather than a stub. `Lineup.Session` triggers this
  asynchronously as soon as a location resolves.
  """

  @behaviour Lineup.Agents.Behaviour

  @radius_km 20

  @spots [
    %{name: "Praia Formosa", lat: -3.7155, lon: -38.5355, state: "Ceará"},
    %{name: "Praia do Futuro", lat: -3.7300, lon: -38.4700, state: "Ceará"},
    %{name: "Joaquina", lat: -27.6300, lon: -48.4500, state: "Santa Catarina"},
    %{name: "Guarda do Embaú", lat: -27.9900, lon: -48.5800, state: "Santa Catarina"},
    %{name: "Praia Mole", lat: -27.6100, lon: -48.4200, state: "Santa Catarina"},
    %{name: "Maresias", lat: -23.7900, lon: -45.5600, state: "São Paulo"},
    %{name: "Itamambuca", lat: -23.3900, lon: -44.8300, state: "São Paulo"},
    %{name: "Arpoador", lat: -22.9880, lon: -43.1900, state: "Rio de Janeiro"}
  ]

  @impl true
  def name, do: :spots

  @impl true
  def cache_ttl, do: :timer.hours(24)

  @impl true
  def fetch(%{lat: lat, lon: lon}) do
    nearby =
      @spots
      |> Enum.map(fn spot ->
        Map.put(spot, :distance_km, distance_km(lat, lon, spot.lat, spot.lon))
      end)
      |> Enum.filter(&(&1.distance_km <= @radius_km))
      |> Enum.sort_by(& &1.distance_km)

    {:ok, %{nearby: nearby}}
  end

  def fetch(_request), do: {:error, :missing_lat_lon}

  # Haversine distance in km. `@doc false` — public only so it's
  # unit-testable without a network call.
  @doc false
  def distance_km(lat1, lon1, lat2, lon2) do
    earth_radius_km = 6371.0

    dlat = deg_to_rad(lat2 - lat1)
    dlon = deg_to_rad(lon2 - lon1)

    a =
      :math.sin(dlat / 2) * :math.sin(dlat / 2) +
        :math.cos(deg_to_rad(lat1)) * :math.cos(deg_to_rad(lat2)) *
          :math.sin(dlon / 2) * :math.sin(dlon / 2)

    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    earth_radius_km * c
  end

  defp deg_to_rad(deg), do: deg * :math.pi() / 180
end
