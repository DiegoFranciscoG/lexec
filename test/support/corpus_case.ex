defmodule Lexec.CorpusCase do
  @moduledoc "Helpers to ingest the fictitious corpus inside the SQL sandbox."

  alias Lexec.{Fixtures, Ingest}

  def ingest_corpus(files \\ :all) do
    Fixtures.corpus_manifest()
    |> Enum.filter(fn entry -> files == :all or entry["file"] in files end)
    |> Enum.map(fn entry ->
      {entry["file"],
       Ingest.ingest(Fixtures.corpus_text(entry["file"]), %{url: entry["url"], flags: entry["flags"]})}
    end)
  end
end
