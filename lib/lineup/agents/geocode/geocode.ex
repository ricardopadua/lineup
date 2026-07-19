defmodule Lineup.Agents.Geocode do
  @moduledoc """
  Resolves a free-text place name ("Formosa Beach") to coordinates using the
  free, keyless Open-Meteo Geocoding API. This is what lets
  `Lineup.Session` turn a chat message into a `lat`/`lon` the rest of the
  agents can work with.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://geocoding-api.open-meteo.com/v1/search"

  @impl true
  def name, do: :geocode

  @impl true
  def cache_ttl, do: :timer.hours(24)

  @impl true
  def fetch(%{query: query}) when is_binary(query) and query != "" do
    params = [name: query, count: 1, language: "en", format: "json"]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 4_000) do
      {:ok, %Req.Response{status: 200, body: %{"results" => [result | _]}}} ->
        {:ok,
         %{
           lat: result["latitude"],
           lon: result["longitude"],
           name: result["name"],
           admin1: result["admin1"],
           country: result["country"]
         }}

      {:ok, %Req.Response{status: 200, body: _body}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_query}
end
