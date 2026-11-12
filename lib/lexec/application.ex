defmodule Lexec.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [
        LexecWeb.Telemetry,
        Lexec.Repo,
        {Ecto.Migrator,
         repos: Application.fetch_env!(:lexec, :ecto_repos), skip: skip_migrations?()},
        {DNSCluster, query: Application.get_env(:lexec, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Lexec.PubSub},
        Lexec.RateLimiter,
        Lexec.Harvest.Throttle
      ] ++
        Lexec.Models.children() ++
        [
          {Task, &setup_index/0},
          LexecWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Lexec.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LexecWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Creates the search index and its settings; failures are logged, not fatal,
  # so the site keeps serving the catalog while Meilisearch starts.
  defp setup_index do
    case Lexec.Index.setup() do
      :ok -> :ok
      {:error, reason} -> Logger.error("index setup failed: #{inspect(reason)}")
    end
  end

  defp skip_migrations? do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
