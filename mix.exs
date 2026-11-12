defmodule Lexec.MixProject do
  use Mix.Project

  def project do
    [
      app: :lexec,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        summary: [threshold: 70],
        ignore_modules: [
          ~r/^Inspect\./,
          LexecWeb.CoreComponents,
          LexecWeb.Layouts,
          LexecWeb.Telemetry,
          LexecWeb.ErrorJSON,
          Lexec.Release,
          Lexec.Embeddings.Bumblebee,
          Lexec.Privacy.Ner.Bumblebee,
          Lexec.Models,
          Mix.Tasks.Lexec.NerEval,
          Mix.Tasks.Lexec.EvalSearch,
          Mix.Tasks.Lexec.Harvest,
          Mix.Tasks.Lexec.Reindex,
          Mix.Tasks.Lexec.IngestText
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Lexec.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:ecto_sqlite3, "~> 0.26.0"},
      {:phoenix_html, "~> 4.4"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.13"},
      {:lazy_html, "== 0.1.13", only: :test},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.14"},
      # Pipeline, HTTP and rules
      {:broadway, "~> 1.3"},
      {:req, "~> 0.7.5"},
      {:yaml_elixir, "~> 2.12"},
      # Local models (NER and embeddings) without Python
      {:bumblebee, "~> 0.8.0"},
      {:nx, "~> 1.0"},
      {:exla, "~> 1.0"},
      # exla 1.0.0 does not build with fine 0.2.0 (released 2026-11-03)
      {:fine, "~> 0.1.6", runtime: false},
      # lazy_html 0.1.14 requires fine 0.2; 0.1.13 is the last release on fine 0.1
      # Quality
      {:stream_data, "~> 1.4", only: [:dev, :test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind lexec", "esbuild lexec"],
      "assets.deploy": [
        "tailwind lexec --minify",
        "esbuild lexec --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format --check-formatted",
        "credo --strict",
        "test --cover"
      ]
    ]
  end
end
