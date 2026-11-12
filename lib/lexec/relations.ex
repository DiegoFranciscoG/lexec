defmodule Lexec.Relations do
  @moduledoc """
  Extracts the relations of a ruling from its (anonymized) paragraphs:
  rulings it cites and legal provisions it invokes. Patterns live in
  `priv/rules/relations.yaml`.
  """

  alias Lexec.Rules

  @type citation :: %{cited_case_number: String.t(), paragraph_number: pos_integer()}
  @type norm :: %{norm_body: String.t(), article: String.t(), paragraph_number: pos_integer()}

  @spec extract([Lexec.Extract.Document.paragraph()], String.t() | nil) :: %{
          citations: [citation()],
          norms: [norm()]
        }
  def extract(paragraphs, own_case_number) do
    %{
      citations:
        paragraphs
        |> Enum.flat_map(fn %{number: n, text: text} ->
          text
          |> cited_rulings()
          |> Enum.reject(&(&1 == own_case_number))
          |> Enum.map(&%{cited_case_number: &1, paragraph_number: n})
        end)
        |> Enum.uniq(),
      norms:
        paragraphs
        |> Enum.flat_map(fn %{number: n, text: text} ->
          text
          |> cited_norms()
          |> Enum.map(fn {body, article} ->
            %{norm_body: body, article: article, paragraph_number: n}
          end)
        end)
        |> Enum.uniq()
    }
  end

  @doc "Ruling numbers mentioned in a text, in order of appearance, without duplicates."
  @spec cited_rulings(String.t()) :: [String.t()]
  def cited_rulings(text) do
    %{modern: modern, legacy: legacy} = patterns()

    (Regex.scan(modern, text, return: :index, capture: :first) ++
       Regex.scan(legacy, text, return: :index, capture: :first))
    |> List.flatten()
    |> Enum.sort()
    |> Enum.map(fn {start, len} -> binary_part(text, start, len) end)
    |> Enum.uniq()
  end

  @doc "`{body, article}` pairs mentioned in a text."
  @spec cited_norms(String.t()) :: [{String.t(), String.t()}]
  def cited_norms(text) do
    %{article: article_re, window: window, bodies: bodies} = patterns()

    mentions = Regex.scan(article_re, text, return: :index, capture: ["arts"])
    starts = Enum.map(mentions, fn [{start, _}] -> start end)

    mentions
    |> Enum.with_index()
    |> Enum.flat_map(fn {[{start, len}], i} ->
      articles =
        text
        |> binary_part(start, len)
        |> then(&Regex.scan(~r/\d{1,4}/u, &1))
        |> List.flatten()

      tail_start = start + len
      next = Enum.at(starts, i + 1, byte_size(text))
      tail_len = min(min(window, next - tail_start), byte_size(text) - tail_start)
      tail = if tail_len > 0, do: valid_prefix(binary_part(text, tail_start, tail_len)), else: ""

      case first_body(bodies, tail) do
        nil -> []
        body -> Enum.map(articles, &{body, &1})
      end
    end)
    |> Enum.uniq()
  end

  # A byte window may cut a multi-byte character; drop the incomplete tail.
  defp valid_prefix(binary) do
    if String.valid?(binary) or binary == "",
      do: binary,
      else: valid_prefix(binary_part(binary, 0, byte_size(binary) - 1))
  end

  defp first_body(bodies, tail) do
    bodies
    |> Enum.map(fn {code, regexes} ->
      index =
        regexes
        |> Enum.map(&Regex.run(&1, tail, return: :index))
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn [{i, _} | _] -> i end)
        |> Enum.min(fn -> nil end)

      {index, code}
    end)
    |> Enum.reject(fn {index, _} -> is_nil(index) end)
    |> Enum.min_by(fn {index, _} -> index end, fn -> {nil, nil} end)
    |> elem(1)
  end

  @doc "Display name of a norm body code."
  @spec body_name(String.t()) :: String.t()
  def body_name(code) do
    case Rules.fetch!(:relations, ["norm_bodies"]) do
      %{^code => %{"name" => name}} -> name
      _ -> code
    end
  end

  defp patterns do
    Rules.memo(:relations_patterns, fn ->
      config = Rules.get(:relations)

      %{
        modern: Rules.regex!(config["case_patterns"]["modern"]),
        legacy: Rules.regex!(config["case_patterns"]["legacy"]),
        article: Rules.regex!(config["article_mention"]),
        window: config["article_window"],
        bodies:
          Enum.map(config["norm_bodies"], fn {code, %{"aliases" => aliases}} ->
            {code, Enum.map(aliases, &Rules.regex!/1)}
          end)
      }
    end)
  end
end
