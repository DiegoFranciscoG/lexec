defmodule Mix.Tasks.Lexec.Reindex do
  @shortdoc "Rebuilds the search index from the catalog"
  @moduledoc "Deletes the index and re-sends every published ruling (with embeddings if enabled)."
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case Lexec.Index.reindex_all() do
      {:ok, n} -> Mix.shell().info("#{n} rulings indexed")
      {:error, reason} -> Mix.raise("reindex failed: #{inspect(reason)}")
    end
  end
end
