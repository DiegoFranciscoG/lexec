defmodule Lexec.Eval do
  @moduledoc """
  Search quality evaluation over `priv/seeds/eval/queries.json`: 50 queries
  with known answers (`case_number#paragraph`). Reports MRR@10 and recall@5
  for a given `semanticRatio` (0.0 = keywords only).
  """

  alias Lexec.Index

  @type metrics :: %{mrr: float(), recall_at_5: float(), queries: non_neg_integer()}

  @spec queries() :: [%{query: String.t(), expected: [String.t()]}]
  def queries do
    :lexec
    |> Application.app_dir("priv/seeds/eval/queries.json")
    |> File.read!()
    |> Jason.decode!()
    |> Enum.map(&%{query: &1["query"], expected: &1["expected"]})
  end

  @spec run(float()) :: metrics()
  def run(semantic_ratio) do
    qs = queries()

    ranks =
      Enum.map(qs, fn %{query: query, expected: expected} ->
        {:ok, %{hits: hits}} = Index.search(query, limit: 10, semantic_ratio: semantic_ratio)

        hits
        |> Enum.map(&"#{&1.case_number}##{&1.paragraph_number}")
        |> Enum.find_index(&(&1 in expected))
      end)

    n = length(qs)

    %{
      mrr: Enum.sum(Enum.map(ranks, fn r -> if r, do: 1 / (r + 1), else: 0 end)) / n,
      recall_at_5: Enum.count(ranks, &(&1 != nil and &1 < 5)) / n,
      queries: n
    }
  end
end
