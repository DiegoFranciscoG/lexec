defmodule Mix.Tasks.Lexec.NerEval do
  @shortdoc "Measures person recall of rules (+ NER if enabled) on 30 synthetic paragraphs"
  @moduledoc """
      NER_BACKEND=bumblebee mix lexec.ner_eval

  Reads `test/fixtures/ner_paragraphs.json` and reports how many annotated
  persons, ID numbers, phones and e-mails were removed.
  """
  use Mix.Task

  alias Lexec.Privacy.{Anonymizer, Ner}

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    items = "test/fixtures/ner_paragraphs.json" |> File.read!() |> Jason.decode!()

    results =
      Enum.map(items, fn item ->
        out = Anonymizer.anonymize_text(item["text"])

        persons =
          Enum.map(item["persons"], fn name ->
            surnames = name |> String.split(" ") |> Enum.take(-2) |> Enum.join(" ")
            not String.contains?(out, name) and not String.contains?(out, surnames)
          end)

        others =
          Enum.map(
            item["id_numbers"] ++ item["phones"] ++ item["emails"],
            &(not String.contains?(out, &1))
          )

        {persons, others}
      end)

    persons = Enum.flat_map(results, &elem(&1, 0))
    others = Enum.flat_map(results, &elem(&1, 1))

    Mix.shell().info("NER model: #{Ner.model_name() || "none (rules only)"}")
    Mix.shell().info("persons removed: #{Enum.count(persons, & &1)}/#{length(persons)}")

    Mix.shell().info(
      "IDs, phones and e-mails removed: #{Enum.count(others, & &1)}/#{length(others)}"
    )
  end
end
