import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :lexec, Lexec.Repo,
  database: Path.expand("../lexec_test.db", __DIR__),
  pool_size: 5,
  busy_timeout: 10_000,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :lexec, LexecWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("test-only-not-a-secret-", 4),
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :lexec,
  index: Lexec.Index.Sql,
  embeddings: Lexec.Embeddings.Null,
  ner: Lexec.Privacy.Ner.Null,
  answer: Lexec.Answer.Extractive,
  admin_user: "revisor",
  admin_password: "test-only-password"

# Harvest tests talk to a Req.Test stub, never to the network.
config :lexec, :harvest,
  user_agent: "LEXEC-bot/0.1",
  contact: "contacto@example.org",
  base_backoff_ms: 50,
  req_options: [plug: {Req.Test, Lexec.Harvest.Fetcher}]

config :lexec, Lexec.Answer.Ollama,
  url: "http://ollama.test",
  model: "test-model",
  req_options: [plug: {Req.Test, Lexec.Answer.Ollama}]

config :lexec, Lexec.Index.Meili,
  url: System.get_env("MEILI_URL"),
  api_key: System.get_env("MEILI_API_KEY"),
  index: "paragraphs_test"

config :nx, default_backend: Nx.BinaryBackend
