defmodule Lineup.Agents.Sun do
  @moduledoc """
  Fetches today's sunrise/sunset times from the free, keyless Open-Meteo
  Weather API.
  """

  @behaviour Lineup.Agents.Behaviour

  @base_url "https://api.open-meteo.com/v1/forecast"

  @impl true
  def name, do: :sun

  @impl true
  def cache_ttl, do: :timer.hours(6)

  @impl true
  def fetch(%{lat: lat, lon: lon}) do
    params = [latitude: lat, longitude: lon, daily: "sunrise,sunset", timezone: "auto"]

    case Req.get(@base_url, params: params, retry: false, receive_timeout: 4_000) do
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"daily" => %{"sunrise" => [sunrise | _], "sunset" => [sunset | _]}}
       }} ->
        {:ok, %{sunrise: sunrise, sunset: sunset}}

      {:ok, %Req.Response{status: 200, body: _body}} ->
        {:error, :unexpected_response}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch(_request), do: {:error, :missing_lat_lon}
end
