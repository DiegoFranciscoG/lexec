defmodule Mix.Tasks.Lexec.IngestText do
  @shortdoc "Ingests already-extracted texts listed in a manifest"
  @moduledoc """
      mix lexec.ingest_text --dir priv/seeds/corpus

  `dir/manifest.json` lists `{"file": ..., "url": ..., "flags": [...]}`. Useful
  for a corpus delivered as text (for example, the answer to a LOTAIP request).
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    dir = opts[:dir] || Mix.raise("use --dir path/with/manifest.json")
    Mix.Task.run("app.start")

    dir
    |> Path.join("manifest.json")
    |> File.read!()
    |> Jason.decode!()
    |> Enum.each(fn entry ->
      text = File.read!(Path.join(dir, entry["file"]))
      result = Lexec.Ingest.ingest(text, %{url: entry["url"], flags: entry["flags"] || []})
      Mix.shell().info("#{entry["file"]}: #{inspect(elem(result, 0))}")
    end)
  end
end
