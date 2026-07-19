defmodule Lineup.CacheTest do
  use ExUnit.Case, async: true

  test "put/get returns a fresh value before ttl expires" do
    Lineup.Cache.put(:test_key_fresh, %{a: 1}, 1_000)
    assert {:ok, %{a: 1}} = Lineup.Cache.get(:test_key_fresh)
  end

  test "returns a stale value after ttl but within the grace period" do
    Lineup.Cache.put(:test_key_stale, %{a: 2}, 10)
    Process.sleep(30)
    assert {:stale, %{a: 2}} = Lineup.Cache.get(:test_key_stale)
  end

  test "returns :error for a missing key" do
    assert :error = Lineup.Cache.get(:nonexistent_key)
  end
end
