defmodule Lexec.Privacy.Anonymizer do
  @moduledoc """
  Anonymizes natural persons in the paragraphs of a ruling.

  1. Deterministic rules: e-mails, ID numbers (cédula/RUC), phones, addresses.
  2. Names after trigger words ("señora", "accionante", ...) or before
     "con cédula", plus person entities from NER (if enabled).
  3. Institutions and authorities in office (`preserve.yaml`) are never touched.

  Each distinct person gets a stable pseudonym inside the ruling
  (`[PERSONA 1]`). The mapping lives only in memory: only counts are returned.
  """

  alias Lexec.Privacy.Ner
  alias Lexec.Rules

  @type stats :: %{String.t() => non_neg_integer()}
  @type result :: %{
          paragraphs: [Lexec.Extract.Document.paragraph()],
          stats: stats(),
          review_reasons: [String.t()]
        }

  @spec anonymize([Lexec.Extract.Document.paragraph()]) :: result()
  def anonymize(paragraphs) when is_list(paragraphs) do
    texts = Enum.map(paragraphs, & &1.text)

    # 1) structured identifiers
    {texts, stats} =
      Enum.map_reduce(texts, %{}, fn text, acc ->
        {text, counts} = replace_structured(text)
        {text, Map.merge(acc, counts, fn _k, a, b -> a + b end)}
      end)

    # 2) person names (rules + NER)
    rule_names = Enum.flat_map(texts, &rule_names/1)
    entity_lists = Ner.entities(texts)
    min_score = Rules.fetch!(:anonymization, ["review", "ner_min_score"])
    labels = Rules.fetch!(:anonymization, ["review", "ner_labels"])

    ner_entities =
      entity_lists
      |> List.flatten()
      |> Enum.filter(&(&1.label in labels))

    low_confidence =
      Enum.filter(ner_entities, fn e -> e.score < min_score and person_candidate?(e.phrase) end)

    ner_names =
      ner_entities
      |> Enum.map(&clean_phrase(&1.phrase))
      |> Enum.filter(&person_candidate?/1)

    # Names introduced as authorities in office ("jueza ponente X") are kept.
    authorities = texts |> Enum.flat_map(&authority_names/1) |> MapSet.new()

    names =
      (rule_names ++ ner_names)
      |> Enum.uniq()
      |> Enum.filter(&person_candidate?/1)
      |> Enum.reject(&MapSet.member?(authorities, &1))

    {texts, person_count} = replace_names(texts, names)

    stats = if person_count > 0, do: Map.put(stats, "person", person_count), else: stats

    review_reasons =
      if low_confidence == [], do: [], else: ["ner_low_confidence:#{length(low_confidence)}"]

    paragraphs =
      paragraphs
      |> Enum.zip(texts)
      |> Enum.map(fn {paragraph, text} -> %{paragraph | text: text} end)

    %{paragraphs: paragraphs, stats: stats, review_reasons: review_reasons}
  end

  @doc "Anonymizes a single text (used by tests and the evaluation task)."
  @spec anonymize_text(String.t()) :: String.t()
  def anonymize_text(text) do
    [%{text: out}] = anonymize([%{number: 1, text: text}]).paragraphs
    out
  end

  # -- structured identifiers ------------------------------------------------

  defp replace_structured(text) do
    placeholders = Rules.fetch!(:anonymization, ["placeholders"])

    Enum.reduce(structured_patterns(), {text, %{}}, fn {type, regex}, {acc, counts} ->
      placeholder = Map.fetch!(placeholders, type)
      {new_text, n} = replace_counting(acc, regex, placeholder)
      counts = if n > 0, do: Map.update(counts, type, n, &(&1 + n)), else: counts
      {new_text, counts}
    end)
  end

  defp replace_counting(text, regex, placeholder) do
    parts = Regex.split(regex, text, include_captures: true, trim: false)

    names = Regex.names(regex)

    {pieces, n} =
      parts
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {part, i}, n ->
        if rem(i, 2) == 1 do
          {replace_match(regex, names, part, placeholder), n + 1}
        else
          {part, n}
        end
      end)

    {IO.iodata_to_binary(pieces), n}
  end

  # Only the "value" group is replaced when the pattern defines it.
  defp replace_match(regex, names, match, placeholder) do
    if "value" in names do
      case Regex.run(regex, match, capture: ["value"], return: :index) do
        [{start, len}] ->
          binary_part(match, 0, start) <>
            placeholder <> binary_part(match, start + len, byte_size(match) - start - len)

        _ ->
          placeholder
      end
    else
      placeholder
    end
  end

  # -- names -------------------------------------------------------------------

  defp rule_names(text) do
    %{trigger: trigger, before_id: before_id} = name_patterns()

    from_trigger = Regex.scan(trigger, text, capture: ["name"]) |> List.flatten()
    from_id = Regex.scan(before_id, text, capture: ["name"]) |> List.flatten()

    Enum.map(from_trigger ++ from_id, &clean_phrase/1)
  end

  defp authority_names(text) do
    name_patterns().authority
    |> Regex.scan(text, capture: ["name"])
    |> List.flatten()
    |> Enum.map(&clean_phrase/1)
  end

  defp replace_names(texts, []), do: {texts, 0}

  defp replace_names(texts, names) do
    template = Rules.fetch!(:anonymization, ["placeholders", "person"])

    # Longest names first so "Ana María Pérez Soto" wins over "Pérez Soto".
    numbered =
      names
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {name, n} ->
        placeholder = String.replace(template, "%{n}", Integer.to_string(n))
        Enum.map(variants(name), &{&1, placeholder})
      end)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.sort_by(fn {variant, _} -> -String.length(variant) end)

    texts =
      Enum.map(texts, fn text ->
        Enum.reduce(numbered, text, fn {variant, placeholder}, acc ->
          regex = Regex.compile!("(?<![\\p{L}])" <> Regex.escape(variant) <> "(?![\\p{L}])", "u")
          Regex.replace(regex, acc, placeholder)
        end)
      end)

    {texts, length(names)}
  end

  # Full name plus the surname pair (last two tokens) for names of 3+ words.
  defp variants(name) do
    tokens = String.split(name, " ")

    surnames =
      if length(tokens) >= 3,
        do: [tokens |> Enum.take(-2) |> Enum.join(" ")],
        else: []

    [name | surnames] |> Enum.reject(&preserved?/1)
  end

  defp person_candidate?(phrase) do
    tokens = String.split(phrase, " ", trim: true)
    first = List.first(tokens)
    non_person = non_person_tokens()

    length(tokens) >= 2 and first not in non_person and not preserved?(phrase) and
      Enum.all?(tokens, &Regex.match?(~r/^\p{L}/u, &1))
  end

  defp preserved?(phrase) do
    %{institutions: institutions, authorities: authorities} = preserve_lists()
    down = String.downcase(phrase)

    Enum.any?(authorities, fn a ->
      a_down = String.downcase(a)
      String.contains?(a_down, down) or String.contains?(down, a_down)
    end) or Enum.any?(institutions, &String.contains?(down, String.downcase(&1)))
  end

  defp clean_phrase(phrase) do
    phrase
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.trim_trailing(",")
  end

  # -- compiled patterns ---------------------------------------------------------

  defp structured_patterns do
    Rules.memo(:anon_structured, fn ->
      patterns = Rules.fetch!(:anonymization, ["patterns"])

      # Order matters: e-mails first, then phones (by context), then any ID-like number.
      for type <- ~w(email phone id_number address) do
        {type, Rules.regex!(Map.fetch!(patterns, type))}
      end
    end)
  end

  defp name_patterns do
    Rules.memo(:anon_names, fn ->
      config = Rules.get(:anonymization)
      token = config["name_token"]

      particles =
        config["name_particles"]
        |> Enum.sort_by(&(-String.length(&1)))
        |> Enum.map_join("|", &Regex.escape/1)

      name = "#{token}(?:\\s+(?:(?:#{particles})\\s+)?#{token}){1,4}"
      triggers = Enum.join(config["name_triggers"], "|")

      %{
        trigger:
          Rules.regex!(
            "(?<![\\p{L}])(?i:#{triggers})\\s+(?:(?i:la|el|los|las)\\s+)?(?<name>#{name})"
          ),
        before_id: Rules.regex!(String.replace(config["name_before_id"], "{NAME}", name)),
        authority:
          Rules.regex!(
            "(?i:#{Enum.join(Rules.fetch!(:preserve, ["authority_triggers"]), "|")}):?\\s+(?<name>#{name})"
          )
      }
    end)
  end

  defp non_person_tokens do
    Rules.memo(:anon_non_person, fn ->
      MapSet.new(Rules.fetch!(:anonymization, ["non_person_first_tokens"]))
    end)
  end

  defp preserve_lists do
    Rules.memo(:anon_preserve, fn ->
      %{
        institutions: Rules.fetch!(:preserve, ["institutions"]),
        authorities: Rules.fetch!(:preserve, ["authorities"])
      }
    end)
  end
end
