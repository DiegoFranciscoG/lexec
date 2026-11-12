defmodule Lexec.Harvest.Worker do
  @moduledoc """
  Processes one manifest entry: cache check → robots.txt → download (paced)
  → PDF checks → text extraction → `Lexec.Ingest`. The downloaded PDF is
  deleted right after extraction (minimization); only its hash is kept.
  """

  import Ecto.Query
  alias Lexec.Catalog.{FetchedDocument, Ruling}
  alias Lexec.Extract.Pdf
  alias Lexec.Harvest.{Fetcher, Robots}
  alias Lexec.{Ingest, Repo, Rules}

  @type entry :: %{
          required(:url) => String.t(),
          optional(:case_number) => String.t(),
          optional(:flags) => [String.t()]
        }

  @spec process(entry()) :: {:ok, atom()} | {:error, term()}
  def process(%{url: url} = entry) do
    with :ok <- validate_url(url),
         :fresh <- cached(url),
         true <- Robots.allowed?(url) || {:error, :disallowed_by_robots},
         {:ok, body} <- download(url),
         sha = sha256(body),
         :new <- known_hash(sha),
         {:ok, text} <- extract(body, sha) do
      outcome =
        case Ingest.ingest(text, %{
               url: url,
               sha256: sha,
               flags: entry[:flags] || [],
               case_number: entry[:case_number]
             }) do
          {:ok, %Ruling{status: "published"}} -> {:ok, :published}
          {:ok, %Ruling{}} -> {:ok, :pending_review}
          {:excluded, _reason} -> {:ok, :excluded}
          {:skipped, reason} -> {:ok, reason}
          {:error, reason} -> {:error, {:ingest, reason}}
        end

      case outcome do
        {:ok, :excluded} -> record(url, sha, "excluded", nil)
        {:ok, _} -> record(url, sha, "ok", nil)
        {:error, reason} -> record(url, sha, "failed", reason)
      end

      outcome
    else
      :cached ->
        {:ok, :cached}

      {:known, sha} ->
        record(url, sha, "ok", nil)
        {:ok, :duplicate}

      {:error, reason} = error ->
        record(url, nil, "failed", reason)
        error
    end
  end

  defp validate_url(url) do
    allow_http = Application.get_env(:lexec, :harvest, [])[:allow_http] == true

    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) -> :ok
      %URI{scheme: "http", host: host} when is_binary(host) and allow_http -> :ok
      _ -> {:error, :invalid_url}
    end
  end

  defp cached(url) do
    exists =
      Repo.exists?(
        from d in FetchedDocument, where: d.url == ^url and d.status in ["ok", "excluded"]
      )

    if exists, do: :cached, else: :fresh
  end

  defp known_hash(sha) do
    if Repo.exists?(from r in Ruling, where: r.pdf_sha256 == ^sha), do: {:known, sha}, else: :new
  end

  defp download(url) do
    max = Rules.fetch!(:app, ["harvest", "max_pdf_bytes"])

    case Fetcher.get(url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        cond do
          byte_size(body) > max -> {:error, :too_large}
          not Pdf.pdf?(body) -> {:error, :not_a_pdf}
          true -> {:ok, body}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract(body, sha) do
    dir = Path.join(System.tmp_dir!(), "lexec-harvest")
    File.mkdir_p!(dir)
    path = Path.join(dir, sha <> ".pdf")

    try do
      File.write!(path, body)
      Pdf.to_text(path)
    after
      File.rm(path)
    end
  end

  defp sha256(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

  defp record(url, sha, status, error) do
    now = DateTime.utc_now(:second)

    Repo.insert!(
      %FetchedDocument{
        url: url,
        sha256: sha,
        status: status,
        error: error && String.slice(inspect(error), 0, 250),
        fetched_at: now,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [
        set: [
          sha256: sha,
          status: status,
          error: error && String.slice(inspect(error), 0, 250),
          fetched_at: now,
          updated_at: now
        ]
      ],
      conflict_target: :url
    )

    :ok
  end
end
