defmodule Lineup.Agents.SpotsTest do
  use ExUnit.Case, async: true

  alias Lineup.Agents.Spots

  test "distance_km is ~0 for the same point" do
    assert_in_delta Spots.distance_km(-3.62, -38.73, -3.62, -38.73), 0.0, 0.001
  end

  test "distance_km matches a known reference distance" do
    # Formosa Beach (CE) to Joaquina (SC), roughly 2860km apart.
    km = Spots.distance_km(-3.62, -38.73, -27.63, -48.45)
    assert_in_delta km, 2862, 20
  end

  test "fetch/1 returns only spots within the radius, nearest first" do
    # Praia do Futuro is real but ~31km from Formosa Beach — outside the 20km
    # radius, so exactly Formosa Beach itself should come back here.
    {:ok, %{nearby: nearby}} = Spots.fetch(%{lat: -3.62, lon: -38.73})

    assert Enum.map(nearby, & &1.name) == ["Formosa Beach"]
    assert Enum.all?(nearby, &(&1.distance_km <= 20))
  end

  test "fetch/1 near two spots returns both, nearest first" do
    # Praia Mole and Joaquina (Florianópolis) are ~5km apart.
    {:ok, %{nearby: nearby}} = Spots.fetch(%{lat: -27.61, lon: -48.42})

    assert Enum.map(nearby, & &1.name) == ["Praia Mole", "Joaquina"]
    assert [%{distance_km: d1}, %{distance_km: d2}] = nearby
    assert d1 <= d2
  end

  test "fetch/1 without lat/lon errors" do
    assert {:error, :missing_lat_lon} = Spots.fetch(%{})
  end
end
