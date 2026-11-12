defmodule Lexec.IngestTest do
  # T-01: excluded rulings never reach NER, embeddings, the index or a generator.
  use Lexec.DataCase, async: false

  alias Lexec.Catalog.{AnonymizationStat, Citation, CitedNorm, Exclusion, Paragraph, ReviewItem, Ruling}
  alias Lexec.{CorpusCase, Fixtures, Ingest, Spy}

  setup do
    Spy.reset()

    Spy.use_backends(
      ner: Spy.Ner,
      embeddings: Spy.Embeddings,
      index: Spy.Index
    )

    :ok
  end

  describe "T-01 exclusion before any model" do
    test "excluded corpus rulings leave only a reason, and no model sees them" do
      results = CorpusCase.ingest_corpus()
      excluded = for e <- Fixtures.corpus_manifest(), e["expected_exclusion"], do: e

      assert length(excluded) == 2

      for e <- excluded do
        {_, result} = List.keyfind(results, e["file"], 0)
        assert result == {:excluded, e["expected_exclusion"]}

        exclusion = Repo.get_by!(Exclusion, source_url: e["url"])
        assert exclusion.reason == e["expected_exclusion"]
        assert exclusion.rule_id =~ "keywords"
        # The exclusion row has no text fields at all.
        refute Map.has_key?(Map.from_struct(exclusion), :text)
      end

      excluded_numbers = ["9117-22-EP/24", "9118-21-EP/23"]
      refute Repo.exists?(from r in Ruling, where: r.case_number in ^excluded_numbers)

      # Nothing that went to NER, embeddings or the index mentions the excluded texts.
      everything_sent = Spy.all_text()
      refute everything_sent =~ "9117-22-EP/24"
      refute everything_sent =~ "9118-21-EP/23"
      refute everything_sent =~ "alimentos"
      refute everything_sent =~ "violencia intrafamiliar"

      # ...while every published ruling did go through NER and the index.
      assert length(Spy.calls(:ner)) == 16
      assert length(Spy.calls(:index_upsert)) == 16
    end

    test "a metadata flag excludes even an innocuous text" do
      text = Fixtures.ruling_text(paragraphs: ["Texto sin palabras clave."])

      assert {:excluded, "reserved"} =
               Ingest.ingest(text, %{url: "https://demo.lexec.invalid/x.pdf", flags: ["reserved"]})

      assert Spy.calls(:ner) == []
      assert Spy.calls(:embeddings) == []
    end
  end

  test "published rulings store anonymized paragraphs, relations and counts only" do
    CorpusCase.ingest_corpus()

    ruling = Repo.get_by!(Ruling, case_number: "9101-20-EP/23")
    assert ruling.status == "published"
    assert ruling.action_type == "EP"
    assert ruling.paragraph_count == 7
    assert ruling.rules_version =~ "anon-"

    texts = Repo.all(from p in Paragraph, where: p.ruling_id == ^ruling.id, select: p.text)
    joined = Enum.join(texts, " ")
    refute joined =~ "Cando Mejía"
    refute joined =~ "0102030405"
    refute joined =~ "rosa.cando@"
    assert joined =~ "[PERSONA 1]"

    stats = Repo.all(from s in AnonymizationStat, where: s.ruling_id == ^ruling.id, select: {s.entity_type, s.count})
    assert {"id_number", 1} in stats
    assert {"email", 1} in stats
    assert {"phone", 1} in stats

    # Citation resolved to the ruling in the corpus, in either ingestion order.
    cited = Repo.get_by!(Ruling, case_number: "9105-18-EP/21")
    assert Repo.get_by!(Citation, citing_ruling_id: ruling.id).cited_ruling_id == cited.id

    assert Repo.exists?(from n in CitedNorm, where: n.ruling_id == ^ruling.id and n.norm_body == "CRE" and n.article == "332")

    # Index documents carry metadata and the 3-d spy embedding.
    [docs | _] =
      Spy.calls(:index_upsert)
      |> Enum.filter(fn docs -> hd(docs)["case_number"] == "9101-20-EP/23" end)

    assert length(docs) == 7
    assert %{"_vectors" => %{"e5" => [_, _, _]}, "official_url" => "https://demo.lexec.invalid/" <> _} = hd(docs)
  end

  test "ingesting twice is a no-op and withdrawn rulings are never re-ingested" do
    [{_, {:ok, _}}] = CorpusCase.ingest_corpus(["9113-19-EP-23.txt"])
    assert [{_, {:skipped, :duplicate}}] = CorpusCase.ingest_corpus(["9113-19-EP-23.txt"])

    {:ok, _} = Lexec.Catalog.withdraw("9113-19-EP/23")
    assert [{_, {:skipped, :withdrawn}}] = CorpusCase.ingest_corpus(["9113-19-EP-23.txt"])
  end

  test "doubtful NER results hold the ruling for human review and out of the index" do
    Application.put_env(:lexec, :spy_ner_names, [{"Galo Patricio", 0.40}])
    on_exit(fn -> Application.delete_env(:lexec, :spy_ner_names) end)

    [{_, {:ok, ruling}}] = CorpusCase.ingest_corpus(["9113-19-EP-23.txt"])
    assert ruling.status == "pending_review"
    assert Repo.get_by!(ReviewItem, ruling_id: ruling.id).reason =~ "ner_low_confidence"
    assert Spy.calls(:index_upsert) == []
  end

  test "documents without a ruling number or paragraphs are rejected" do
    assert {:error, :missing_case_number} = Ingest.ingest("1. Párrafo sin metadatos.", %{url: "https://x.invalid/a"})

    text = "Sentencia No. 9301-22-EP/24\nSin párrafos numerados."
    assert {:error, :no_paragraphs} = Ingest.ingest(text, %{url: "https://x.invalid/b"})
  end
end
