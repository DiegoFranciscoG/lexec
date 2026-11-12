defmodule Lexec.Index.MeiliTest do
  # Integration with a real Meilisearch server (MEILI_URL). Run with --include meilisearch.
  use Lexec.DataCase, async: false

  @moduletag :meilisearch

  alias Lexec.Catalog.Ruling
  alias Lexec.{CorpusCase, Index, Spy}
  alias Lexec.Index.Meili

  setup do
    Spy.reset()
    Spy.use_backends(index: Meili, embeddings: Spy.Embeddings)
    :ok = Meili.reset()
    :ok = Meili.setup()
    CorpusCase.ingest_corpus()
    :ok
  end

  test "keyword search over anonymized paragraphs with filters" do
    {:ok, %{hits: hits, total: total}} = Index.search("seguridad jurídica", limit: 5)
    assert total > 0
    assert hd(hits).case_number == "9104-22-EP/24"
    assert hd(hits).official_url =~ "https://"

    {:ok, %{hits: in_hits}} = Index.search("tasa", filters: %{action_type: "IN"})
    assert in_hits != []
    assert Enum.all?(in_hits, &(&1.action_type == "IN"))

    {:ok, %{hits: years}} =
      Index.search("derecho", filters: %{year_from: 2025, year_to: 2025}, limit: 50)

    assert Enum.all?(years, &(&1.ruling_year == 2025))

    {:ok, %{hits: none}} = Index.search("Cando Mejía 0102030405")
    refute Enum.any?(none, &(&1.text =~ "Cando"))
  end

  test "hybrid search sends the query vector and still returns results" do
    {:ok, %{hits: hits}} = Index.search("motivación", semantic_ratio: 0.5, limit: 5)
    assert hits != []
    assert Enum.any?(Spy.calls(:embeddings), fn texts -> texts == ["query: motivación"] end)
  end

  test "filter values are escaped" do
    assert Meili.filter_expression(%{rapporteur: ~s(a" OR action_type = "EP)}) ==
             [~s(rapporteur = "a\\" OR action_type = \\"EP")]

    {:ok, %{hits: []}} =
      Index.search("derecho", filters: %{rapporteur: ~s(x" OR ruling_year > "0)})
  end

  test "withdrawing removes the ruling's paragraphs from Meilisearch" do
    ruling = Repo.get_by!(Ruling, case_number: "9111-23-EP/25")
    {:ok, %{hits: [_ | _]}} = Index.search("agua potable", filters: %{action_type: "EP"})

    {:ok, _} = Lexec.Catalog.withdraw(ruling.case_number)
    {:ok, %{hits: hits}} = Index.search("agua potable")
    refute Enum.any?(hits, &(&1.ruling_id == ruling.id))
  end

  test "reindex rebuilds from the catalog" do
    assert {:ok, 16} = Index.reindex_all()
    {:ok, %{total: total}} = Index.search("Constitución", limit: 1)
    assert total > 0
  end
end
