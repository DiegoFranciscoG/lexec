defmodule Lexec.Extract.SegmenterTest do
  # T-04: the number of paragraphs matches the document's own numbering.
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Lexec.Extract.{Cleaner, Parser, Segmenter}
  alias Lexec.Fixtures

  describe "T-04 segmentation on the fictitious corpus" do
    test "every ruling yields paragraphs numbered 1..N without gaps" do
      for %{"file" => file} <- Fixtures.corpus_manifest() do
        text = Fixtures.corpus_text(file)
        doc = Parser.parse(text)

        # Highest paragraph number written in the source document (before the decision).
        [body | _] = String.split(text, "IV. Decisión")

        expected =
          ~r/^(\d{1,4})\. /m
          |> Regex.scan(body, capture: :all_but_first)
          |> List.flatten()
          |> Enum.map(&String.to_integer/1)
          |> Enum.max()

        numbers = Enum.map(doc.paragraphs, & &1.number)
        assert numbers == Enum.to_list(1..expected), "#{file}: #{inspect(numbers)}"
      end
    end

    test "headers, footers, page numbers and headings never leak into paragraphs" do
      for %{"file" => file} <- Fixtures.corpus_manifest() do
        doc = file |> Fixtures.corpus_text() |> Parser.parse()

        for %{text: text} <- doc.paragraphs do
          refute text =~ "CORTE CONSTITUCIONAL DEL ECUADOR"
          refute text =~ "corteconstitucional.gob.ec"
          refute text =~ ~r/Página \d+ de \d+/
          refute text =~ ~r/\b(I|II|III|IV)\. [A-Z]/
        end
      end
    end

    test "the operative part (numbered again from 1) is not a paragraph" do
      doc = "9101-20-EP-23.txt" |> Fixtures.corpus_text() |> Parser.parse()
      refute List.last(doc.paragraphs).text =~ "Aceptar la acción"
      assert doc.decision == "accepted"
    end
  end

  property "any synthetic ruling is split back into exactly its paragraphs" do
    word =
      StreamData.string(Enum.concat([?a..?z, [?á, ?é, ?ñ]]), min_length: 1, max_length: 10)

    paragraph =
      gen all(words <- StreamData.list_of(word, min_length: 3, max_length: 40)) do
        Enum.join(words, " ") <> "."
      end

    check all(
            paragraphs <- StreamData.list_of(paragraph, min_length: 1, max_length: 25),
            per_page <- StreamData.integer(1..6)
          ) do
      text = Fixtures.ruling_text(paragraphs: paragraphs, per_page: per_page)
      doc = Parser.parse(text)

      assert Enum.map(doc.paragraphs, & &1.number) == Enum.to_list(1..length(paragraphs))
      assert Enum.map(doc.paragraphs, & &1.text) == paragraphs
    end
  end

  test "a number out of sequence continues the current paragraph" do
    lines = ["1. Primero dice que", "2010. fue un año", "2. Segundo."]
    %{paragraphs: paragraphs} = Segmenter.segment(lines)
    assert [%{number: 1, text: "Primero dice que 2010. fue un año"}, %{number: 2}] = paragraphs
  end

  test "hyphenated line breaks are joined" do
    assert Segmenter.join_lines(["la garantía consti-", "tucional"]) ==
             "la garantía constitucional"
  end

  test "lines repeated on many pages are removed as header/footer" do
    text = Enum.map_join(1..4, "\f", fn i -> "Encabezado X\n#{i}. texto #{i}\nPie Y" end)

    assert Cleaner.clean(text) |> Enum.reject(&(&1 == "")) ==
             Enum.map(1..4, &"#{&1}. texto #{&1}")
  end
end
