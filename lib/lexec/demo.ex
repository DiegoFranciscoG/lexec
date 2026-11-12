defmodule Lexec.Demo do
  @moduledoc """
  Loads the FICTITIOUS demo corpus (`priv/seeds/corpus`) through the real
  ingestion pipeline: exclusion, anonymization, relations and indexing.
  Idempotent: rulings already in the catalog are skipped.
  """

  require Logger
  alias Lexec.{Index, Ingest}

  @spec seed() :: %{String.t() => term()}
  def seed do
    dir = Application.app_dir(:lexec, "priv/seeds/corpus")

    case Index.setup() do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("index setup failed, seeding catalog only: #{inspect(reason)}")
    end

    dir
    |> Path.join("manifest.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.new(fn entry ->
      text = File.read!(Path.join(dir, entry["file"]))
      result = Ingest.ingest(text, %{url: entry["url"], flags: entry["flags"] || []})
      {entry["file"], summarize(result)}
    end)
  end

  defp summarize({:ok, ruling}), do: ruling.status
  defp summarize({:excluded, reason}), do: "excluded: #{reason}"
  defp summarize({:skipped, reason}), do: "skipped: #{reason}"
  defp summarize({:error, reason}), do: "error: #{inspect(reason)}"
end
