defmodule Lexec.Extract.MetadataTest do
  use ExUnit.Case, async: true

  alias Lexec.Extract.{Metadata, Parser, Pdf}
  alias Lexec.Fixtures

  test "reads case number, type, year, date, rapporteur and decision" do
    doc = "9108-19-IN-22.txt" |> Fixtures.corpus_text() |> Parser.parse()

    assert doc.case_number == "9108-19-IN/22"
    assert doc.case_file == "9108-19-IN"
    assert doc.action_type == "IN"
    assert doc.ruling_year == 2022
    assert doc.decided_on == ~D[2022-11-17]
    assert doc.rapporteur == "Elena Paredes Loja"
    assert doc.decision == "partially_accepted"
  end

  test "dismissed rulings are detected" do
    doc = "9102-21-EP-24.txt" |> Fixtures.corpus_text() |> Parser.parse()
    assert doc.decision == "dismissed"
  end

  test "legacy numbers map to the current action type" do
    assert Metadata.action_type("001-10-SEP-CC") == "EP"
    assert Metadata.ruling_year("001-10-SEP-CC") == 2010
    assert Metadata.action_type("12-20-ZZ/21") == nil
    assert Metadata.action_type(nil) == nil
  end

  test "missing metadata yields nils and 'other'" do
    doc = Parser.parse("Texto sin estructura.\n1. Un párrafo.")
    assert doc.case_number == nil
    assert doc.decision == "other"
    assert [%{number: 1}] = doc.paragraphs
  end

  describe "pdftotext" do
    @describetag :tmp_dir

    test "extracts text from a PDF keeping pages", %{tmp_dir: dir} do
      path = Path.join(dir, "s.pdf")

      File.write!(
        path,
        Fixtures.pdf([
          ["Sentencia No. 9301-22-EP/24", "1. Garantía de motivación."],
          ["2. Segundo párrafo."]
        ])
      )

      assert {:ok, text} = Pdf.to_text(path)
      assert text =~ "9301-22-EP/24"
      assert text =~ "Garantía de motivación"
      assert text =~ "\f"
    end

    test "rejects files that are not PDFs", %{tmp_dir: dir} do
      path = Path.join(dir, "fake.pdf")
      File.write!(path, "<html>no</html>")
      assert Pdf.to_text(path) == {:error, :not_a_pdf}
      assert Pdf.to_text(Path.join(dir, "missing.pdf")) == {:error, :enoent}
      refute Pdf.pdf?("<html>")
    end
  end
end
