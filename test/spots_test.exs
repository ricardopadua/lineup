defmodule Lineup.Agents.SpotsTest do
  use ExUnit.Case, async: true

  alias Lineup.Agents.Spots

  test "distance_km is ~0 for the same point" do
    assert_in_delta Spots.distance_km(-3.7155, -38.5355, -3.7155, -38.5355), 0.0, 0.001
  end

  test "distance_km matches a known reference distance" do
    # Praia Formosa (CE) to Joaquina (SC), roughly 2850km apart.
    km = Spots.distance_km(-3.7155, -38.5355, -27.63, -48.45)
    assert_in_delta km, 2850, 20
  end

  test "fetch/1 returns only spots within the radius, nearest first" do
    # Praia do Futuro is real and ~7.4km from Praia Formosa — both should
    # come back here, ordered by distance.
    {:ok, %{nearby: nearby}} = Spots.fetch(%{lat: -3.7155, lon: -38.5355})

    assert Enum.map(nearby, & &1.name) == ["Praia Formosa", "Praia do Futuro"]
    assert Enum.all?(nearby, &(&1.distance_km <= 20))
    assert [%{distance_km: d1}, %{distance_km: d2}] = nearby
    assert d1 <= d2
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
