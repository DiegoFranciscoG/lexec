defmodule Lexec.Index.Sql do
  @moduledoc """
  Keyword-only search over the SQLite catalog (parameterized `LIKE`).
  Used in tests and when no Meilisearch server is configured.
  """

  @behaviour Lexec.Index

  import Ecto.Query
  alias Lexec.Catalog.{Paragraph, Ruling}
  alias Lexec.{Index, Repo}

  @impl true
  def setup, do: :ok

  @impl true
  def upsert(_docs), do: :ok

  @impl true
  def delete_ruling(_ruling_id), do: :ok

  @impl true
  def reset, do: :ok

  @impl true
  def search(query, opts) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/[^\p{L}\p{N}\/-]+/u, trim: true)
      |> Enum.filter(&(String.length(&1) >= 2))
      |> Enum.take(10)

    base =
      from p in Paragraph,
        join: r in Ruling,
        on: r.id == p.ruling_id,
        where: r.status == "published"

    base =
      Enum.reduce(terms, base, fn term, q ->
        pattern = "%" <> escape_like(term) <> "%"

        from [p, r] in q,
          where:
            fragment("lower(?) LIKE ? ESCAPE '\\'", p.text, ^pattern) or
              fragment("lower(?) LIKE ? ESCAPE '\\'", r.case_number, ^pattern)
      end)

    filtered = apply_filters(base, Keyword.get(opts, :filters, %{}))
    total = Repo.aggregate(filtered, :count)

    hits =
      filtered
      |> order_by([p, r], desc: r.ruling_year, asc: r.id, asc: p.number)
      |> limit(^Keyword.get(opts, :limit, 10))
      |> offset(^Keyword.get(opts, :offset, 0))
      |> select([p, r], {p, r})
      |> Repo.all()
      |> Enum.map(fn {p, r} -> r |> Index.document(p) |> Index.to_hit() end)

    {:ok,
     %{hits: if(terms == [], do: [], else: hits), total: if(terms == [], do: 0, else: total)}}
  end

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:action_type, v}, q when is_binary(v) -> where(q, [_p, r], r.action_type == ^v)
      {:year_from, v}, q when is_integer(v) -> where(q, [_p, r], r.ruling_year >= ^v)
      {:year_to, v}, q when is_integer(v) -> where(q, [_p, r], r.ruling_year <= ^v)
      {:rapporteur, v}, q when is_binary(v) -> where(q, [_p, r], r.rapporteur == ^v)
      _, q -> q
    end)
  end

  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
