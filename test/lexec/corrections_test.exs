defmodule Lexec.CorrectionsTest do
  # T-11: a withdrawal request removes the content from the index and the catalog.
  use Lexec.DataCase, async: false

  alias Lexec.Catalog.{Citation, Paragraph, Ruling}
  alias Lexec.{Catalog, Corrections, CorpusCase, Index, Review, Spy}

  setup do
    Spy.reset()
    Spy.use_backends(index: Spy.Index)
    CorpusCase.ingest_corpus()
    :ok
  end

  describe "T-11 withdrawal" do
    test "removes paragraphs from the catalog and the search index" do
      ruling = Repo.get_by!(Ruling, case_number: "9105-18-EP/21")
      assert {:ok, %{hits: [_ | _]}} = Index.search("incongruencia")

      {:ok, request} =
        Corrections.create_request(%{
          "case_number" => "9105-18-EP/21",
          "request_type" => "withdrawal",
          "reason" => "Solicito el retiro porque contiene datos que me identifican."
        })

      assert request.status == "received"
      assert Date.diff(request.due_on, Date.utc_today()) == 15

      assert {:ok, resolved} = Corrections.resolve(request.id, :withdraw, "Retirada del índice")
      assert resolved.status == "withdrawn"
      assert resolved.resolved_at

      assert Spy.calls(:index_delete) == [ruling.id]
      refute Repo.exists?(from p in Paragraph, where: p.ruling_id == ^ruling.id)
      assert Repo.get!(Ruling, ruling.id).status == "withdrawn"
      assert {:ok, %{hits: []}} = Index.search("incongruencia")
      assert Catalog.get_published_ruling(ruling.id) == nil

      # Rulings that cited it keep the public case number but lose the link.
      assert Repo.all(from c in Citation, where: c.cited_case_number == "9105-18-EP/21", select: c.cited_ruling_id)
             |> Enum.all?(&is_nil/1)

      assert {:error, :already_resolved} = Corrections.resolve(request.id, :reject)
    end

    test "correction and rejection close the request without touching content" do
      {:ok, r} =
        Corrections.create_request(%{
          "case_number" => "9101-20-EP/23",
          "paragraph_number" => "4",
          "request_type" => "correction",
          "reason" => "El párrafo tiene un error de transcripción."
        })

      assert {:ok, %{status: "corrected"}} = Corrections.resolve(r.id, :correct, "Corregido")
      assert Repo.get_by!(Ruling, case_number: "9101-20-EP/23").status == "published"
      assert Spy.calls(:index_delete) == []
      assert {:error, :not_found} = Corrections.resolve(-1, :reject)
    end
  end

  describe "request validation (LOPDP minimization)" do
    test "contact e-mail requires explicit consent" do
      attrs = %{
        "case_number" => "9101-20-EP/23",
        "request_type" => "correction",
        "reason" => "Texto suficientemente largo.",
        "contact_email" => "persona@example.org"
      }

      assert {:error, cs} = Corrections.create_request(attrs)
      assert "debe aceptar el uso de su correo para responderle" in errors_on(cs).consent

      assert {:ok, r} = Corrections.create_request(Map.put(attrs, "consent", "true"))
      assert r.contact_email == "persona@example.org"
    end

    test "rejects bad case numbers, short reasons and unknown types" do
      assert {:error, cs} =
               Corrections.create_request(%{"case_number" => "abc", "request_type" => "x", "reason" => "corto"})

      errors = errors_on(cs)
      assert errors.case_number
      assert errors.request_type
      assert errors.reason
    end

    test "open requests are listed by due date" do
      {:ok, _} =
        Corrections.create_request(%{
          "case_number" => "9101-20-EP/23",
          "request_type" => "correction",
          "reason" => "Texto suficientemente largo."
        })

      assert [%{case_number: "9101-20-EP/23"}] = Corrections.list_open()
    end
  end

  describe "review queue" do
    test "approving publishes and indexes; withdrawing removes" do
      Spy.reset()
      ruling = Repo.get_by!(Ruling, case_number: "9110-20-EP/24")
      ruling |> Ecto.Changeset.change(status: "pending_review") |> Repo.update!()

      item =
        Repo.insert!(%Lexec.Catalog.ReviewItem{ruling_id: ruling.id, reason: "ner_low_confidence:1", status: "pending"})

      assert [%{case_number: "9110-20-EP/24"}] = Review.list_pending()
      assert [%{number: 1} | _] = Review.pending_paragraphs(ruling.id)

      assert {:ok, %{status: "approved", reviewer: "revisor"}} = Review.approve(item.id, "revisor")
      assert Repo.get!(Ruling, ruling.id).status == "published"
      assert [_docs] = Spy.calls(:index_upsert)
      assert {:error, :already_resolved} = Review.withdraw(item.id, "revisor")

      ruling2 = Repo.get_by!(Ruling, case_number: "9111-23-EP/25")
      ruling2 |> Ecto.Changeset.change(status: "pending_review") |> Repo.update!()
      item2 = Repo.insert!(%Lexec.Catalog.ReviewItem{ruling_id: ruling2.id, reason: "x", status: "pending"})

      assert {:ok, %{status: "withdrawn"}} = Review.withdraw(item2.id, "revisor")
      assert Repo.get!(Ruling, ruling2.id).status == "withdrawn"
      assert {:error, :not_found} = Review.approve(-1, "revisor")
    end
  end
end
