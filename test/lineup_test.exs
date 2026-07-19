defmodule LineupTest do
  use ExUnit.Case

  test "consult/1 is exposed and delegates to the orchestrator" do
    Code.ensure_loaded!(Lineup)
    assert function_exported?(Lineup, :consult, 1)
  end
end
