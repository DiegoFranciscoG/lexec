defmodule Lexec.CatalogTest do
  use Lexec.DataCase, async: false

  alias Lexec.{Catalog, CorpusCase, Index}
  alias Lexec.Catalog.Ruling

  setup do
    CorpusCase.ingest_corpus()
    :ok
  end

  test "ruling sheet has paragraphs, citations both ways, norms and counts" do
    motivation = Repo.get_by!(Ruling, case_number: "9105-18-EP/21")
    sheet = Catalog.get_published_ruling(motivation.id)

    assert length(sheet.ruling.paragraphs) == 7
    assert Enum.map(sheet.ruling.paragraphs, & &1.number) == Enum.to_list(1..7)

    citing = Enum.map(sheet.cited_by, & &1.case_number) |> Enum.uniq() |> Enum.sort()
    assert citing == ["9101-20-EP/23", "9102-21-EP/24", "9104-22-EP/24"]

    assert %{norm_body: "CRE", article: "76"} = Enum.find(sheet.norms, &(&1.article == "76"))
    assert sheet.anonymization["person"] == 1

    assert Catalog.get_published_ruling("no-numero") == nil
    assert Catalog.get_published_ruling(-1) == nil
  end

  test "most cited rulings and top norms" do
    [first | _] = Catalog.most_cited()
    assert first.case_number == "9105-18-EP/21"
    assert first.citations == 3

    assert Catalog.most_cited(action_type: "IN") == []

    top = Catalog.top_norms(action_type: "EP")
    assert Enum.any?(top, &(&1.norm_body == "CRE" and &1.article == "94"))
    assert Enum.all?(top, &(&1.action_type == "EP"))
    assert [_ | _] = Catalog.top_norms()
  end

  test "precedent graph only links published rulings" do
    %{nodes: nodes, edges: edges} = Catalog.precedent_graph()
    ids = MapSet.new(nodes, & &1.id)
    assert Enum.all?(edges, &(MapSet.member?(ids, &1.from) and MapSet.member?(ids, &1.to)))
    assert length(edges) >= 5
  end

  test "filter options and corpus stats" do
    options = Catalog.filter_options()
    assert "EP" in options.action_types
    assert "Alba Ruiz Andrade" in options.rapporteurs
    assert 2021 in options.years

    stats = Catalog.stats()
    assert stats.published == 16
    assert stats.excluded == 2
    assert stats.paragraphs == 16 * 7
  end

  test "publish only accepts pending rulings" do
    ruling = Repo.get_by!(Ruling, case_number: "9101-20-EP/23")
    assert Catalog.publish(ruling) == {:error, :not_pending}
    assert Catalog.withdraw("0-00-XX/00") == {:error, :not_found}
    assert {:ok, %{status: "withdrawn"}} = Catalog.withdraw("9101-20-EP/23")
    assert {:ok, %{status: "withdrawn"}} = Catalog.withdraw("9101-20-EP/23")
  end

  describe "SQL keyword index" do
    test "searches anonymized paragraphs with filters" do
      {:ok, %{hits: hits, total: total}} = Index.search("motivación", limit: 3)
      assert total >= 3
      assert length(hits) == 3
      assert Enum.all?(hits, &(&1.official_url =~ "https://"))

      {:ok, %{hits: in_hits}} = Index.search("tasa", filters: %{action_type: "IN"})
      assert Enum.all?(in_hits, &(&1.action_type == "IN"))

      {:ok, %{hits: year_hits}} =
        Index.search("Corte", filters: %{year_from: 2025, year_to: 2025})

      assert Enum.all?(year_hits, &(&1.ruling_year == 2025))

      {:ok, %{hits: r_hits}} = Index.search("Corte", filters: %{rapporteur: "Elena Paredes Loja"})
      assert Enum.all?(r_hits, &(&1.rapporteur == "Elena Paredes Loja"))
    end

    test "never finds personal data and treats LIKE wildcards literally" do
      assert {:ok, %{hits: []}} = Index.search("Cando Mejía")
      assert {:ok, %{hits: []}} = Index.search("%")
      assert {:ok, %{hits: []}} = Index.search("a")
    end

    test "reindex_all walks every published ruling" do
      assert {:ok, 16} = Index.reindex_all()
    end
  end
end
