# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :lexec,
  ecto_repos: [Lexec.Repo],
  generators: [timestamp_type: :utc_datetime]

# Pluggable backends (overridden per environment and at runtime).
config :lexec,
  index: Lexec.Index.Sql,
  embeddings: Lexec.Embeddings.Null,
  ner: Lexec.Privacy.Ner.Null,
  answer: Lexec.Answer.Extractive,
  demo_mode: false

# Pinned local models (Hugging Face repo + commit).
config :lexec, :embedding_model,
  repo: "intfloat/multilingual-e5-small",
  revision: "614241f622f53c4eeff9890bdc4f31cfecc418b3",
  dimensions: 384,
  batch_size: 8,
  sequence_length: 512

config :lexec, :ner_model,
  repo: "Davlan/bert-base-multilingual-cased-ner-hrl",
  revision: "e756de7f7b8f64fea0c3d7c3872f1322fab747b1",
  vocabulary_repo: "google-bert/bert-base-multilingual-cased",
  vocabulary_revision: "3f076fdb1ab68d5b2880cb87a0886f315b8146f8",
  batch_size: 4,
  sequence_length: 512

config :lexec, Lexec.Index.Meili, index: "paragraphs", timeout: 30_000

config :lexec, Lexec.Answer.Ollama, timeout: 60_000

config :nx, default_backend: EXLA.Backend

# Configure the endpoint
config :lexec, LexecWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: LexecWeb.ErrorHTML, json: LexecWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Lexec.PubSub,
  live_view: [signing_salt: "dEhROBsI"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  lexec: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  lexec: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
