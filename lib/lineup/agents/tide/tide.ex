defmodule Lineup.Agents.Tide do
  @moduledoc """
  Fetches tide data from the free, keyless Open-Meteo Marine API and turns
  the hourly sea-level curve into a table of high/low tide events, so the
  buddy agent can reason about the full tide cycle (low/mid/high, rising
  or falling, how fast it's moving) instead of a single snapshot.

  Defaults to **today only**. Pass `:date` (a single ISO 8601 date string)
  or `:dates` (a list of them) in the request to get the table for other
  days instead — e.g. when the surfer explicitly asks about tomorrow or
  the weekend.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://marine-api.open-meteo.com/v1/marine"

  @impl true
  def name, do: :tide

  @impl true
  def cache_ttl, do: :timer.minutes(15)

  @impl true
  def fetch(%{lat: lat, lon: lon} = request) do
    dates = requested_dates(request)
    {start_date, end_date} = date_range(dates)

    params = [
      latitude: lat,
      longitude: lon,
      current: "sea_level_height_msl",
      hourly: "sea_level_height_msl",
      start_date: Date.to_iso8601(start_date),
      end_date: Date.to_iso8601(end_date),
      timezone: "auto"
    ]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, build_result(body, dates)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_lat_lon}

  defp requested_dates(%{dates: dates}) when is_list(dates) and dates != [] do
    Enum.map(dates, &to_date/1)
  end

  defp requested_dates(%{date: date}), do: [to_date(date)]
  defp requested_dates(_request), do: [Date.utc_today()]

  defp to_date(%Date{} = date), do: date
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)

  # Pad a day on each side of the requested range so tide turning points
  # right around midnight can still be detected — they need a neighbour on
  # both sides to tell a peak/trough from a straight climb.
  defp date_range(dates) do
    {Enum.min(dates, Date) |> Date.add(-1), Enum.max(dates, Date) |> Date.add(1)}
  end

  defp build_result(
         %{"hourly" => %{"time" => times, "sea_level_height_msl" => levels}} = body,
         dates
       ) do
    events_by_date = tide_events(times, levels)

    dates
    |> Map.new(fn date ->
      iso = Date.to_iso8601(date)
      {iso, %{date: iso, events: Map.get(events_by_date, iso, [])}}
    end)
    |> attach_current(body["current"], dates)
  end

  defp attach_current(tables, %{"time" => time, "sea_level_height_msl" => level}, dates) do
    today = Date.utc_today()

    if today in dates do
      Map.update!(
        tables,
        Date.to_iso8601(today),
        &Map.put(&1, :current, %{time: time, sea_level_m: level})
      )
    else
      tables
    end
  end

  defp attach_current(tables, _current, _dates), do: tables

  # Local maxima/minima of the hourly sea-level curve are the closest thing
  # Open-Meteo gives us to actual high/low tide events, grouped by day.
  # `@doc false` — kept public only so it can be unit-tested without a
  # network call.
  @doc false
  def tide_events(times, levels) do
    times
    |> Enum.zip(levels)
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.flat_map(fn [{_t0, l0}, {t1, l1}, {_t2, l2}] ->
      cond do
        l1 > l0 and l1 > l2 -> [%{time: t1, type: :high, height_m: l1}]
        l1 < l0 and l1 < l2 -> [%{time: t1, type: :low, height_m: l1}]
        true -> []
      end
    end)
    |> Enum.group_by(fn %{time: time} -> String.slice(time, 0, 10) end)
  end
end
