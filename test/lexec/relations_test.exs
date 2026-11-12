defmodule Lexec.RelationsTest do
  # T-05: citations between rulings, precision and recall on 100 annotated snippets.
  use ExUnit.Case, async: true

  alias Lexec.{Fixtures, Relations, Rules}

  test "T-05 precision and recall on 100 annotated cases" do
    cases = Fixtures.json_fixture("citations_annotated.json")
    assert length(cases) == 100

    {tp, fp, fn_} =
      Enum.reduce(cases, {0, 0, 0}, fn %{"text" => text, "expected" => expected}, {tp, fp, fn_} ->
        found = MapSet.new(Relations.cited_rulings(text))
        expected = MapSet.new(expected)

        {tp + MapSet.size(MapSet.intersection(found, expected)),
         fp + MapSet.size(MapSet.difference(found, expected)),
         fn_ + MapSet.size(MapSet.difference(expected, found))}
      end)

    precision = tp / max(tp + fp, 1)
    recall = tp / max(tp + fn_, 1)
    quality = Rules.fetch!(:app, ["quality"])

    assert precision >= quality["citation_precision_min"], "precision #{precision}"
    assert recall >= quality["citation_recall_min"], "recall #{recall}"
  end

  test "self citations are ignored and paragraph numbers kept" do
    paragraphs = [
      %{number: 4, text: "En esta sentencia 9101-20-EP/23 citamos la sentencia 9105-18-EP/21."},
      %{number: 9, text: "Ver también 9105-18-EP/21 y 001-10-SEP-CC."}
    ]

    %{citations: citations} = Relations.extract(paragraphs, "9101-20-EP/23")

    assert citations == [
             %{cited_case_number: "9105-18-EP/21", paragraph_number: 4},
             %{cited_case_number: "9105-18-EP/21", paragraph_number: 9},
             %{cited_case_number: "001-10-SEP-CC", paragraph_number: 9}
           ]
  end

  test "articles are attributed to the nearest legal body" do
    text =
      "Los artículos 75, 76 y 82 de la Constitución y el artículo 40 de la LOGJCC; " <>
        "además el art. 534 del Código Orgánico Integral Penal. El artículo 5 no dice de qué cuerpo."

    assert Relations.cited_norms(text) == [
             {"CRE", "75"},
             {"CRE", "76"},
             {"CRE", "82"},
             {"LOGJCC", "40"},
             {"COIP", "534"}
           ]
  end

  test "accents near the window edge never break extraction" do
    text = "artículo 1 " <> String.duplicate("ñ", 200) <> " de la Constitución"
    assert Relations.cited_norms(text) == []
  end

  test "body names come from the catalog" do
    assert Relations.body_name("CRE") == "Constitución de la República del Ecuador"
    assert Relations.body_name("XYZ") == "XYZ"
  end
end
