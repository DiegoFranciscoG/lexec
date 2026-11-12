# Integration tests that need external services run only when those services exist:
#   MEILI_URL=... mix test --include meilisearch
#   LEXEC_MODELS=1 mix test --include models   (downloads the pinned Hugging Face models)
exclude =
  [
    meilisearch: System.get_env("MEILI_URL") in [nil, ""],
    models: System.get_env("LEXEC_MODELS") in [nil, ""]
  ]
  |> Enum.filter(fn {_tag, skip?} -> skip? end)
  |> Enum.map(fn {tag, _} -> tag end)

{:ok, _} = Lexec.Spy.start_link()
ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Lexec.Repo, :manual)
