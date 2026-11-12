# Credo configuration. The defaults are kept except two refactoring limits:
# the pipeline steps (harvest worker, ingestion, search params) read clearer as
# one flat `with`/`cond` than split into helpers, so complexity allows 12 and
# nesting allows 3. Everything else runs in --strict mode in CI.
%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/", "config/"], excluded: [~r"/_build/", ~r"/deps/"]},
      strict: true,
      checks: %{
        extra: [
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 12]},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]}
        ]
      }
    }
  ]
}
