defmodule Lexec.SearchQualityTest do
  # T-08: hybrid search beats keyword-only search on 50 queries with known answers.
  # Needs Meilisearch and the pinned e5 model: --include meilisearch --include models
  use Lexec.DataCase, async: false

  @moduletag :meilisearch
  @moduletag :models
  @moduletag timeout: 900_000

  alias Lexec.{CorpusCase, Eval, Rules, Spy}
  alias Lexec.Index.Meili

  setup do
    start_supervised!(
      {Nx.Serving,
       serving: Lexec.Models.embedding_serving(), name: Lexec.EmbeddingServing, batch_timeout: 50}
    )

    Spy.use_backends(index: Meili, embeddings: Lexec.Embeddings.Bumblebee)
    :ok = Meili.reset()
    :ok = Meili.setup()
    CorpusCase.ingest_corpus()
    :ok
  end

  test "T-08 hybrid search beats keyword search" do
    keyword = Eval.run(0.0)
    hybrid = Eval.run(0.5)
    gain = Rules.fetch!(:app, ["quality", "hybrid_min_mrr_gain"])

    IO.puts("\n[T-08] keyword #{inspect(keyword)}\n[T-08] hybrid  #{inspect(hybrid)}")

    assert hybrid.queries == 50
    assert hybrid.mrr >= keyword.mrr + gain
    assert hybrid.recall_at_5 >= keyword.recall_at_5
  end
end
