defmodule Mix.Tasks.Lexec.EvalSearch do
  @shortdoc "Compares keyword vs hybrid search on the 50 evaluation queries"
  @moduledoc "Prints MRR@10 and recall@5 for semanticRatio 0.0 and the configured ratio."
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")
    ratio = Lexec.Rules.fetch!(:app, ["search", "default_semantic_ratio"])

    for {label, r} <- [{"keyword", 0.0}, {"hybrid", ratio}] do
      m = Lexec.Eval.run(r)

      Mix.shell().info(
        "#{label}: MRR@10 #{Float.round(m.mrr, 3)} · recall@5 #{Float.round(m.recall_at_5, 3)} (#{m.queries} queries)"
      )
    end
  end
end
