defmodule Lexec.Harvest.ListProducer do
  @moduledoc "GenStage producer that emits the entries of a harvest manifest."
  use GenStage

  @impl true
  def init(opts) do
    {:producer, %{queue: Keyword.fetch!(opts, :entries), caller: Keyword.fetch!(opts, :caller)}}
  end

  @impl true
  def handle_demand(demand, state) do
    {take, rest} = Enum.split(state.queue, demand)

    messages =
      Enum.map(take, fn entry ->
        %Broadway.Message{
          data: entry,
          acknowledger: {Lexec.Harvest.Acker, state.caller, entry.url}
        }
      end)

    {:noreply, messages, %{state | queue: rest}}
  end
end

defmodule Lexec.Harvest.Acker do
  @moduledoc "Reports processed messages back to the process running the harvest."
  @behaviour Broadway.Acknowledger

  @impl true
  def ack(caller, successful, failed) do
    send(
      caller,
      {:harvest_ack,
       Enum.map(successful, &{&1.acknowledger |> elem(2), :ok, &1.data}) ++
         Enum.map(failed, fn m ->
           {m.acknowledger |> elem(2), :failed, failure_reason(m.status)}
         end)}
    )

    :ok
  end

  defp failure_reason({:failed, reason}), do: reason
  defp failure_reason({kind, reason, _stack}), do: {kind, reason}
  defp failure_reason(other), do: other
end

defmodule Lexec.Harvest.Pipeline do
  @moduledoc """
  Broadway pipeline. The producer is rate limited (1 message per second, from
  `app.yaml`) and every HTTP request is paced again by the throttle. A
  failing document (broken PDF, HTTP error, exception) is marked failed and
  the pipeline keeps going (T-10).
  """

  use Broadway
  require Logger

  alias Broadway.Message
  alias Lexec.Harvest.Worker

  def start_link(opts) do
    harvest = Lexec.Rules.fetch!(:app, ["harvest"])

    Broadway.start_link(__MODULE__,
      name: Keyword.fetch!(opts, :name),
      producer: [
        module:
          {Lexec.Harvest.ListProducer,
           entries: Keyword.fetch!(opts, :entries), caller: Keyword.fetch!(opts, :caller)},
        concurrency: 1,
        rate_limiting: [
          allowed_messages: harvest["allowed_messages"],
          interval: harvest["interval_ms"]
        ]
      ],
      processors: [default: [concurrency: 2, max_demand: 1]]
    )
  end

  @impl true
  def handle_message(_processor, %Message{data: entry} = message, _context) do
    case Worker.process(entry) do
      {:ok, outcome} -> Message.update_data(message, fn _ -> outcome end)
      {:error, reason} -> Message.failed(message, reason)
    end
  end

  @impl true
  def handle_failed(messages, _context) do
    Enum.each(messages, fn %Message{data: entry, status: status} ->
      Logger.warning("harvest failed for #{entry.url}: #{inspect(status)}")
    end)

    messages
  end
end

defmodule Lexec.Harvest do
  @moduledoc "Runs a harvest over a manifest and waits until every entry is acknowledged."

  alias Lexec.Harvest.Pipeline

  @type summary :: %{ok: [{String.t(), atom()}], failed: [{String.t(), term()}]}

  @doc """
  Loads a JSON manifest: a list of `{"url": ..., "case_number": ..., "flags": [...]}`.
  """
  @spec load_manifest(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def load_manifest(path) do
    with {:ok, json} <- File.read(path),
         {:ok, list} when is_list(list) <- Jason.decode(json) do
      {:ok,
       Enum.map(list, fn item ->
         %{
           url: Map.fetch!(item, "url"),
           case_number: item["case_number"],
           flags: item["flags"] || []
         }
       end)}
    else
      {:ok, _other} -> {:error, :manifest_must_be_a_list}
      error -> error
    end
  end

  @spec run([map()], keyword()) :: summary()
  def run(entries, opts \\ []) do
    entries = Enum.uniq_by(entries, & &1.url)
    name = Module.concat(Pipeline, "Run#{System.unique_integer([:positive])}")
    timeout = Keyword.get(opts, :timeout, max(60_000, length(entries) * 60_000))

    {:ok, _pid} = Pipeline.start_link(name: name, entries: entries, caller: self())

    try do
      collect(length(entries), %{ok: [], failed: []}, timeout)
    after
      Broadway.stop(name)
    end
  end

  defp collect(0, acc, _timeout),
    do: %{ok: Enum.reverse(acc.ok), failed: Enum.reverse(acc.failed)}

  defp collect(remaining, acc, timeout) do
    receive do
      {:harvest_ack, results} ->
        acc =
          Enum.reduce(results, acc, fn
            {url, :ok, outcome}, a -> %{a | ok: [{url, outcome} | a.ok]}
            {url, :failed, reason}, a -> %{a | failed: [{url, reason} | a.failed]}
          end)

        collect(remaining - length(results), acc, timeout)
    after
      timeout -> raise "harvest timed out with #{remaining} entries pending"
    end
  end
end
