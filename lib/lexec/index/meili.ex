defmodule Lexec.Index.Meili do
  @moduledoc """
  Meilisearch backend (Community Edition, MIT). Hybrid search combines
  keyword ranking with the `e5` user-provided embedder via `semanticRatio`.
  """

  @behaviour Lexec.Index

  alias Lexec.{Embeddings, Index}

  @filterable ~w(action_type ruling_year rapporteur ruling_id case_number)

  @impl true
  def setup do
    uid = index_uid()

    with {:ok, _} <- ensure_index(uid),
         {:ok, task} <-
           request(:patch, "/indexes/#{uid}/settings", json: settings()) do
      wait_task(task)
    end
  end

  @impl true
  def upsert([]), do: :ok

  def upsert(docs) do
    with {:ok, task} <-
           request(:post, "/indexes/#{index_uid()}/documents?primaryKey=id", json: docs) do
      wait_task(task)
    end
  end

  @impl true
  def delete_ruling(ruling_id) when is_integer(ruling_id) do
    with {:ok, task} <-
           request(:post, "/indexes/#{index_uid()}/documents/delete",
             json: %{filter: "ruling_id = #{ruling_id}"}
           ) do
      wait_task(task)
    end
  end

  @impl true
  def reset do
    # Deletion is asynchronous: a missing index shows up as a failed task.
    with {:ok, task} <- request(:delete, "/indexes/#{index_uid()}"),
         {:error, {:task_failed, %{"code" => "index_not_found"}}} <- wait_task(task) do
      :ok
    else
      {:error, {:http, 404, _}} -> :ok
      other -> other
    end
  end

  @impl true
  def search(query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    offset = Keyword.get(opts, :offset, 0)
    ratio = Keyword.get(opts, :semantic_ratio, 0.0)

    body =
      %{
        q: query,
        limit: limit,
        offset: offset,
        filter: filter_expression(Keyword.get(opts, :filters, %{})),
        attributesToRetrieve: ~w(id ruling_id case_number paragraph_number text action_type
          ruling_year decided_on rapporteur official_url)
      }
      |> maybe_hybrid(query, ratio)

    case request(:post, "/indexes/#{index_uid()}/search", json: body) do
      {:ok, %{"hits" => hits} = response} ->
        total = response["estimatedTotalHits"] || response["totalHits"] || length(hits)
        {:ok, %{hits: Enum.map(hits, &Index.to_hit/1), total: total}}

      error ->
        error
    end
  end

  @doc "Builds a Meilisearch filter from whitelisted, escaped values."
  @spec filter_expression(Index.filters()) :: [String.t()]
  def filter_expression(filters) do
    [
      filters[:action_type] && ~s(action_type = "#{escape(filters[:action_type])}"),
      is_integer(filters[:year_from]) && "ruling_year >= #{filters[:year_from]}",
      is_integer(filters[:year_to]) && "ruling_year <= #{filters[:year_to]}",
      filters[:rapporteur] && ~s(rapporteur = "#{escape(filters[:rapporteur])}")
    ]
    |> Enum.filter(&is_binary/1)
  end

  defp maybe_hybrid(body, query, ratio) when ratio > 0 do
    case Embeddings.enabled?() && Embeddings.embed_query(query) do
      vector when is_list(vector) and vector != [] ->
        Map.merge(body, %{hybrid: %{embedder: "e5", semanticRatio: ratio}, vector: vector})

      _ ->
        body
    end
  end

  defp maybe_hybrid(body, _query, _ratio), do: body

  defp escape(value), do: value |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))

  defp settings do
    base = %{
      searchableAttributes: ["text", "case_number"],
      filterableAttributes: @filterable,
      sortableAttributes: ["ruling_year"],
      typoTolerance: %{minWordSizeForTypos: %{oneTypo: 5, twoTypos: 9}},
      pagination: %{maxTotalHits: 1000}
    }

    case Embeddings.dimensions() do
      nil -> base
      dims -> Map.put(base, :embedders, %{e5: %{source: "userProvided", dimensions: dims}})
    end
  end

  defp ensure_index(uid) do
    case request(:get, "/indexes/#{uid}") do
      {:ok, index} ->
        {:ok, index}

      {:error, {:http, 404, _}} ->
        with {:ok, task} <- request(:post, "/indexes", json: %{uid: uid, primaryKey: "id"}) do
          # Two processes may race to create it; "already exists" is success too.
          case wait_task(task) do
            :ok ->
              {:ok, %{"uid" => uid}}

            {:error, {:task_failed, %{"code" => "index_already_exists"}}} ->
              {:ok, %{"uid" => uid}}

            error ->
              error
          end
        end

      error ->
        error
    end
  end

  defp wait_task(%{"taskUid" => uid}), do: wait_task(uid, 600)
  defp wait_task(_other), do: :ok

  defp wait_task(_uid, 0), do: {:error, :task_timeout}

  defp wait_task(uid, attempts) do
    case request(:get, "/tasks/#{uid}") do
      {:ok, %{"status" => "succeeded"}} ->
        :ok

      {:ok, %{"status" => "failed", "error" => error}} ->
        {:error, {:task_failed, error}}

      {:ok, %{"status" => status}} when status in ["canceled"] ->
        {:error, {:task_failed, status}}

      {:ok, _pending} ->
        Process.sleep(100)
        wait_task(uid, attempts - 1)

      error ->
        error
    end
  end

  defp request(method, path, opts \\ []) do
    config = Application.fetch_env!(:lexec, __MODULE__)

    headers =
      case config[:api_key] do
        key when is_binary(key) and key != "" -> [{"authorization", "Bearer " <> key}]
        _ -> []
      end

    req_opts =
      [
        method: method,
        base_url: config[:url],
        url: path,
        headers: headers,
        retry: false,
        receive_timeout: config[:timeout] || 30_000
      ] ++ opts ++ (config[:req_options] || [])

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http, status, body}}
      {:error, exception} -> {:error, {:transport, Exception.message(exception)}}
    end
  end

  defp index_uid, do: Application.fetch_env!(:lexec, __MODULE__)[:index]
end
