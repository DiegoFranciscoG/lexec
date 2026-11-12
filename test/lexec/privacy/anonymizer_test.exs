defmodule Lexec.Privacy.AnonymizerTest do
  # T-02 (persons, IDs, phones, e-mails) and T-03 (institutions and authorities kept).
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Lexec.{Fixtures, Rules}
  alias Lexec.Privacy.Anonymizer

  @items Fixtures.json_fixture("ner_paragraphs.json")

  describe "T-02 anonymization on 30 annotated synthetic paragraphs" do
    test "zero ID numbers, phones or e-mails survive" do
      for item <- @items do
        out = Anonymizer.anonymize_text(item["text"])

        for value <- item["id_numbers"] ++ item["phones"] ++ item["emails"] do
          refute String.contains?(out, value), "leaked #{value} in: #{out}"
        end

        refute out =~ ~r/(?:\d[\s.-]?){9}\d/
      end
    end

    test "person recall (rules only) reaches the configured minimum" do
      persons =
        Enum.flat_map(@items, fn item -> Enum.map(item["persons"], &{item["text"], &1}) end)

      found =
        Enum.count(persons, fn {text, name} ->
          out = Anonymizer.anonymize_text(text)
          # A person counts as protected when neither the full name nor the surnames remain.
          surnames = name |> String.split(" ") |> Enum.take(-2) |> Enum.join(" ")
          not String.contains?(out, name) and not String.contains?(out, surnames)
        end)

      recall = found / length(persons)
      assert recall >= Rules.fetch!(:anonymization, ["person_recall_min"]), "recall #{recall}"
    end

    test "the same person keeps the same pseudonym across paragraphs" do
      %{paragraphs: [p1, p2], stats: stats} =
        Anonymizer.anonymize([
          %{number: 1, text: "La señora Ana Lucía Pazmiño Rivas presentó la demanda."},
          %{
            number: 2,
            text: "Luego Pazmiño Rivas apeló. El señor Jorge Enrique Cueva Granda contestó."
          }
        ])

      assert p1.text == "La señora [PERSONA 1] presentó la demanda."
      assert p2.text == "Luego [PERSONA 1] apeló. El señor [PERSONA 2] contestó."
      assert stats["person"] == 2
    end

    test "only the address value is replaced" do
      out =
        Anonymizer.anonymize_text(
          "Vive con domicilio en la calle Olmedo 3-21 y Larga, en Cuenca."
        )

      assert out == "Vive con domicilio en [DIRECCIÓN], en Cuenca."
    end

    test "phones with context are labelled as phones" do
      out = Anonymizer.anonymize_text("Celular: 099 123 4567 y teléfono +593 2 2345678.")
      assert out == "Celular: [TELÉFONO] y teléfono [TELÉFONO]."
    end
  end

  property "T-02 no 10-digit ID number survives, whatever the separators" do
    sep = StreamData.member_of(["", "", "-", " ", "."])

    check all(
            digits <- StreamData.list_of(StreamData.integer(0..9), length: 10),
            seps <- StreamData.list_of(sep, length: 9),
            prefix <-
              StreamData.member_of(["cédula ", "C.I. ", "número ", "", "identificado con "])
          ) do
      [first | rest] = Enum.map(digits, &Integer.to_string/1)
      number = Enum.zip(seps, rest) |> Enum.reduce(first, fn {s, d}, acc -> acc <> s <> d end)

      out =
        Anonymizer.anonymize_text("El ciudadano presentó su #{prefix}#{number} en la audiencia.")

      refute out =~ ~r/(?:\d[\s.-]?){9}\d/, out
    end
  end

  describe "T-03 institutions and authorities in office are kept" do
    test "preserved names stay intact in the annotated fixtures" do
      for item <- @items, keep <- item["preserve"] do
        assert Anonymizer.anonymize_text(item["text"]) =~ keep
      end
    end

    test "every institution in preserve.yaml survives after a trigger word" do
      for institution <- Rules.fetch!(:preserve, ["institutions"]) do
        text = "El accionante demandó a la #{institution} ante el juez."
        assert Anonymizer.anonymize_text(text) == text
      end
    end

    test "judges introduced as authorities are kept even after 'Dra.'" do
      text = "La jueza ponente Dra. Carmen Salazar Vintimilla dictó sentencia."
      assert Anonymizer.anonymize_text(text) == text

      text2 = "El juez constitucional Tomás Benavides Ortega votó a favor."
      assert Anonymizer.anonymize_text(text2) == text2
    end

    test "case numbers, articles and dates are not mistaken for personal data" do
      text =
        "Según la sentencia 9105-18-EP/21, el artículo 76 numeral 7 rige desde el 20 de octubre de 2008."

      assert Anonymizer.anonymize_text(text) == text
    end
  end

  describe "NER layer" do
    setup do
      Lexec.Spy.reset()
      Lexec.Spy.use_backends(ner: Lexec.Spy.Ner)

      Application.put_env(:lexec, :spy_ner_names, [
        {"Mónica Alexandra Naranjo Vela", 0.99},
        {"Fabián Marcelo Cueva", 0.42}
      ])

      on_exit(fn -> Application.delete_env(:lexec, :spy_ner_names) end)
    end

    test "names without trigger words are caught by NER" do
      out = Anonymizer.anonymize_text("Comparecieron Mónica Alexandra Naranjo Vela sin abogado.")
      assert out == "Comparecieron [PERSONA 1] sin abogado."
    end

    test "low-confidence entities send the ruling to review" do
      result =
        Anonymizer.anonymize([
          %{number: 1, text: "Declaró Fabián Marcelo Cueva en la audiencia."}
        ])

      assert result.review_reasons == ["ner_low_confidence:1"]
    end
  end
end
