import Config

# Runtime configuration from environment variables. Secrets have no defaults:
# in production the release refuses to start if one is missing.

if System.get_env("PHX_SERVER") do
  config :lexec, LexecWeb.Endpoint, server: true
end

config :lexec, LexecWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  config :lexec, LexecWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        ~r"lib/lexec_web/router\.ex$"E,
        ~r"lib/lexec_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() != :test do
  pick = fn var, options, default ->
    value = System.get_env(var, default)

    Map.get(options, value) ||
      raise "#{var} must be one of #{Enum.join(Map.keys(options), ", ")} (got #{inspect(value)})"
  end

  config :lexec,
    embeddings:
      pick.(
        "EMBEDDINGS_BACKEND",
        %{"none" => Lexec.Embeddings.Null, "bumblebee" => Lexec.Embeddings.Bumblebee},
        "none"
      ),
    ner:
      pick.(
        "NER_BACKEND",
        %{"rules" => Lexec.Privacy.Ner.Null, "bumblebee" => Lexec.Privacy.Ner.Bumblebee},
        "rules"
      ),
    answer:
      pick.(
        "ANSWER_BACKEND",
        %{"extractive" => Lexec.Answer.Extractive, "ollama" => Lexec.Answer.Ollama},
        "extractive"
      )

  if System.get_env("DEMO_MODE") do
    config :lexec, demo_mode: System.get_env("DEMO_MODE") == "true"
  end

  if meili_url = System.get_env("MEILI_URL") do
    config :lexec, :index, Lexec.Index.Meili

    config :lexec, Lexec.Index.Meili,
      url: meili_url,
      api_key:
        System.get_env("MEILI_API_KEY") ||
          raise("MEILI_API_KEY is required when MEILI_URL is set"),
      index: System.get_env("MEILI_INDEX", "paragraphs"),
      timeout: 30_000
  end

  if System.get_env("ANSWER_BACKEND") == "ollama" do
    config :lexec, Lexec.Answer.Ollama,
      url: System.get_env("OLLAMA_URL") || raise("OLLAMA_URL is required for ANSWER_BACKEND=ollama"),
      model:
        System.get_env("OLLAMA_MODEL") || raise("OLLAMA_MODEL is required for ANSWER_BACKEND=ollama"),
      timeout: 60_000
  end

  # Harvesting is opt-in: the User-Agent and contact are checked when it starts.
  config :lexec, :harvest,
    user_agent: System.get_env("HARVEST_USER_AGENT"),
    contact: System.get_env("HARVEST_CONTACT")

  # Review queue credentials. Without them the /admin area always answers 401.
  config :lexec,
    admin_user: System.get_env("ADMIN_USER"),
    admin_password: System.get_env("ADMIN_PASSWORD")
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise "environment variable DATABASE_PATH is missing (for example /data/lexec.db)"

  config :lexec, Lexec.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (mix phx.gen.secret)"

  if byte_size(secret_key_base) < 64 do
    raise "SECRET_KEY_BASE must be at least 64 bytes"
  end

  admin_password =
    System.get_env("ADMIN_PASSWORD") ||
      raise "environment variable ADMIN_PASSWORD is missing"

  if String.length(admin_password) < 16 do
    raise "ADMIN_PASSWORD must have at least 16 characters"
  end

  System.get_env("ADMIN_USER") || raise "environment variable ADMIN_USER is missing"

  host = System.get_env("PHX_HOST") || raise "environment variable PHX_HOST is missing"
  scheme = System.get_env("PHX_SCHEME", "https")
  public_port = String.to_integer(System.get_env("PHX_PUBLIC_PORT", "443"))

  config :lexec, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :lexec, LexecWeb.Endpoint,
    url: [host: host, port: public_port, scheme: scheme],
    check_origin: ["#{scheme}://#{host}" <> if(public_port in [80, 443], do: "", else: ":#{public_port}")],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
