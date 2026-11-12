defmodule Lexec.RateLimiter do
  @moduledoc """
  Fixed-window rate limiter on ETS. Buckets and limits come from
  `rate_limits` in `priv/rules/app.yaml`. Keys are hashed client IPs, never
  stored anywhere else.
  """

  use GenServer

  @table __MODULE__

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Counts a hit for `{bucket, client}`; `:ok` or `{:error, :rate_limited}`."
  @spec hit(String.t(), term()) :: :ok | {:error, :rate_limited}
  def hit(bucket, client) do
    %{"limit" => limit, "window_seconds" => window} =
      Lexec.Rules.fetch!(:app, ["rate_limits", bucket])

    now = System.system_time(:second)
    window_id = div(now, window)
    key = {bucket, :erlang.phash2(client), window_id}
    expires_at = (window_id + 1) * window
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0, expires_at})

    if count <= limit, do: :ok, else: {:error, :rate_limited}
  end

  @doc "Removes every counter (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    # Drop expired windows.
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, :timer.minutes(10))
end
