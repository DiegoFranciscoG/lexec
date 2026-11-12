defmodule Lexec.Harvest.Throttle do
  @moduledoc """
  Global request pacer for every outgoing harvest request (robots.txt,
  PDFs and retries): consecutive requests are at least `interval_ms` apart.
  The server only hands out time slots, so callers sleep outside of it.
  It also owns the robots.txt cache table.
  """

  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Blocks the caller until its slot arrives."
  @spec wait() :: :ok
  def wait do
    case GenServer.call(__MODULE__, :slot) do
      0 -> :ok
      ms -> Process.sleep(ms)
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(:lexec_robots, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{next_at: nil}}
  end

  @impl true
  def handle_call(:slot, _from, state) do
    interval = Lexec.Rules.fetch!(:app, ["harvest", "interval_ms"])
    now = System.monotonic_time(:millisecond)
    at = if state.next_at && state.next_at > now, do: state.next_at, else: now
    {:reply, at - now, %{state | next_at: at + interval}}
  end
end
