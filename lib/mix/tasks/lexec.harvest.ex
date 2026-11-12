defmodule Mix.Tasks.Lexec.Harvest do
  @shortdoc "Harvests rulings from a JSON manifest (1 req/s, robots.txt, cache)"
  @moduledoc """
      mix lexec.harvest --manifest path/to/manifest.json

  The manifest is a list of `{"url": ..., "case_number": ..., "flags": [...]}`.
  Requires HARVEST_USER_AGENT and HARVEST_CONTACT. Prefer the corpus delivered
  by the Court through a LOTAIP request over harvesting the portal.
  """
  use Mix.Task

  alias Lexec.Harvest
  alias Lexec.Harvest.Fetcher

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [manifest: :string])
    path = opts[:manifest] || Mix.raise("use --manifest path/to/manifest.json")

    Mix.Task.run("app.start")
    Fetcher.user_agent!()

    {:ok, entries} = Harvest.load_manifest(path)
    summary = Harvest.run(entries)

    Mix.shell().info("ok: #{length(summary.ok)} · failed: #{length(summary.failed)}")

    Enum.each(summary.failed, fn {url, reason} ->
      Mix.shell().error("#{url}: #{inspect(reason)}")
    end)
  end
end
