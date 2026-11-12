defmodule Lexec.Harvest.Fetcher do
  @moduledoc """
  HTTP GET for the harvester. Every attempt (including retries) goes through
  `Lexec.Harvest.Throttle`; retries use exponential backoff on transient
  errors (408, 429, 5xx, network). Identifies itself with a User-Agent that
  includes a contact, both from environment variables.
  """

  alias Lexec.Harvest.Throttle
  alias Lexec.Rules

  @transient [408, 429, 500, 502, 503, 504]

  @spec get(String.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def get(url, opts \\ []) do
    config = Rules.fetch!(:app, ["harvest"])
    retries = Keyword.get(opts, :retries, config["max_retries"])
    # Tests may shorten the backoff; production uses the value in app.yaml.
    backoff =
      Application.get_env(:lexec, :harvest, [])[:base_backoff_ms] || config["base_backoff_ms"]

    do_get(url, retries, backoff, config, 0, 5)
  end

  @redirects [301, 302, 303, 307, 308]

  # Redirects are followed by hand so every hop is paced by the throttle too.
  defp do_get(_url, _retries_left, _backoff, _config, _attempt, -1),
    do: {:error, :too_many_redirects}

  defp do_get(url, retries_left, backoff, config, attempt, redirects_left) do
    Throttle.wait()

    req =
      [
        url: url,
        headers: [{"user-agent", user_agent!()}],
        retry: false,
        redirect: false,
        decode_body: false,
        receive_timeout: config["receive_timeout_ms"]
      ] ++ req_options()

    result =
      case Req.get(req) do
        {:ok, %Req.Response{status: status}} = ok when status not in @transient -> ok
        {:ok, %Req.Response{status: status}} -> {:retry, {:http, status}}
        {:error, exception} -> {:retry, {:transport, Exception.message(exception)}}
      end

    case result do
      {:ok, %Req.Response{status: status} = response} when status in @redirects ->
        case Req.Response.get_header(response, "location") do
          [location | _] ->
            next = url |> URI.merge(location) |> URI.to_string()
            do_get(next, retries_left, backoff, config, attempt, redirects_left - 1)

          [] ->
            {:ok, response}
        end

      {:ok, response} ->
        {:ok, response}

      {:retry, _reason} when retries_left > 0 ->
        Process.sleep(backoff * Integer.pow(2, attempt))
        do_get(url, retries_left - 1, backoff, config, attempt + 1, redirects_left)

      {:retry, reason} ->
        {:error, reason}
    end
  end

  @doc "First token of the User-Agent, used to match robots.txt groups."
  @spec product_token() :: String.t()
  def product_token, do: user_agent!() |> String.split(["/", " "]) |> hd()

  @doc "User-Agent with contact. Raises if not configured (no defaults)."
  @spec user_agent!() :: String.t()
  def user_agent! do
    config = Application.get_env(:lexec, :harvest, [])

    case {config[:user_agent], config[:contact]} do
      {ua, contact} when is_binary(ua) and ua != "" and is_binary(contact) and contact != "" ->
        "#{ua} (+#{contact})"

      _ ->
        raise ArgumentError,
              "HARVEST_USER_AGENT and HARVEST_CONTACT must be set before harvesting"
    end
  end

  defp req_options, do: Application.get_env(:lexec, :harvest, [])[:req_options] || []
end
