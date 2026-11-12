defmodule Lexec.Release do
  @moduledoc """
  Tasks for the production release, where Mix is not available:

      bin/lexec eval "Lexec.Release.migrate()"
      bin/lexec eval "Lexec.Release.seed_demo()"
  """
  @app :lexec

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc "Loads the fictitious demo corpus through the real pipeline (idempotent)."
  def seed_demo do
    {:ok, _} = Application.ensure_all_started(@app)

    Lexec.Demo.seed()
    |> Enum.sort()
    |> Enum.each(fn {file, outcome} -> IO.puts("#{file}: #{outcome}") end)
  end

  def reindex do
    {:ok, _} = Application.ensure_all_started(@app)
    {:ok, n} = Lexec.Index.reindex_all()
    IO.puts("#{n} rulings indexed")
  end

  defp load_app do
    Application.ensure_loaded(@app)
  end
end
