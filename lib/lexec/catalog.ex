defmodule Lexec.Catalog do
  @moduledoc "Read models for the interface and the withdrawal workflow."

  import Ecto.Query
  alias Lexec.Catalog.{AnonymizationStat, Citation, CitedNorm, Paragraph, Ruling}
  alias Lexec.{Index, Repo}

  @doc "A published ruling with paragraphs, outgoing/incoming citations and norms."
  @spec get_published_ruling(integer() | String.t()) :: map() | nil
  def get_published_ruling(id) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %Ruling{} = ruling <- Repo.get_by(Ruling, id: int_id, status: "published") do
      ruling = Repo.preload(ruling, :paragraphs)

      %{
        ruling: ruling,
        cites:
          Repo.all(
            from c in Citation,
              left_join: r in Ruling,
              on: r.id == c.cited_ruling_id and r.status == "published",
              where: c.citing_ruling_id == ^ruling.id,
              order_by: [c.paragraph_number, c.cited_case_number],
              select: %{
                case_number: c.cited_case_number,
                paragraph_number: c.paragraph_number,
                ruling_id: r.id
              }
          ),
        cited_by:
          Repo.all(
            from c in Citation,
              join: r in Ruling,
              on: r.id == c.citing_ruling_id and r.status == "published",
              where: c.cited_ruling_id == ^ruling.id,
              order_by: [r.case_number, c.paragraph_number],
              select: %{
                case_number: r.case_number,
                paragraph_number: c.paragraph_number,
                ruling_id: r.id
              }
          ),
        norms:
          Repo.all(
            from n in CitedNorm,
              where: n.ruling_id == ^ruling.id,
              group_by: [n.norm_body, n.article],
              order_by: [n.norm_body, fragment("CAST(? AS INTEGER)", n.article)],
              select: %{norm_body: n.norm_body, article: n.article, count: count(n.id)}
          ),
        anonymization:
          Repo.all(
            from s in AnonymizationStat,
              where: s.ruling_id == ^ruling.id,
              select: {s.entity_type, s.count}
          )
          |> Map.new()
      }
    else
      _ -> nil
    end
  end

  @doc "Most cited rulings (published citing rulings only), optionally by action type."
  @spec most_cited(keyword()) :: [map()]
  def most_cited(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)

    query =
      from c in Citation,
        join: citing in Ruling,
        on: citing.id == c.citing_ruling_id and citing.status == "published",
        left_join: cited in Ruling,
        on: cited.id == c.cited_ruling_id and cited.status == "published",
        group_by: [c.cited_case_number, cited.id, cited.action_type],
        order_by: [desc: count(fragment("DISTINCT ?", citing.id)), asc: c.cited_case_number],
        limit: ^limit,
        select: %{
          case_number: c.cited_case_number,
          ruling_id: cited.id,
          action_type: cited.action_type,
          citations: count(fragment("DISTINCT ?", citing.id))
        }

    query =
      case Keyword.get(opts, :action_type) do
        nil -> query
        type -> where(query, [_c, citing], citing.action_type == ^type)
      end

    Repo.all(query)
  end

  @doc "Most invoked articles per action type."
  @spec top_norms(keyword()) :: [map()]
  def top_norms(opts \\ []) do
    limit = Keyword.get(opts, :limit, 15)

    query =
      from n in CitedNorm,
        join: r in Ruling,
        on: r.id == n.ruling_id and r.status == "published",
        group_by: [r.action_type, n.norm_body, n.article],
        order_by: [desc: count(fragment("DISTINCT ?", r.id)), asc: n.norm_body, asc: n.article],
        limit: ^limit,
        select: %{
          action_type: r.action_type,
          norm_body: n.norm_body,
          article: n.article,
          rulings: count(fragment("DISTINCT ?", r.id))
        }

    case Keyword.get(opts, :action_type) do
      nil -> Repo.all(query)
      type -> query |> where([_n, r], r.action_type == ^type) |> Repo.all()
    end
  end

  @doc "Nodes and edges of the precedent graph among published rulings."
  @spec precedent_graph() :: %{nodes: [map()], edges: [map()]}
  def precedent_graph do
    edges =
      Repo.all(
        from c in Citation,
          join: a in Ruling,
          on: a.id == c.citing_ruling_id and a.status == "published",
          join: b in Ruling,
          on: b.id == c.cited_ruling_id and b.status == "published",
          distinct: true,
          select: %{from: a.id, to: b.id}
      )

    ids = edges |> Enum.flat_map(&[&1.from, &1.to]) |> Enum.uniq()

    nodes =
      Repo.all(
        from r in Ruling,
          where: r.id in ^ids,
          order_by: r.case_number,
          select: %{id: r.id, case_number: r.case_number, action_type: r.action_type}
      )

    %{nodes: nodes, edges: edges}
  end

  @doc "Distinct filter values for the search form."
  @spec filter_options() :: %{
          action_types: [String.t()],
          rapporteurs: [String.t()],
          years: [integer()]
        }
  def filter_options do
    published = from(r in Ruling, where: r.status == "published")

    %{
      action_types:
        Repo.all(
          from r in published, distinct: true, order_by: r.action_type, select: r.action_type
        ),
      rapporteurs:
        Repo.all(
          from r in published,
            where: not is_nil(r.rapporteur),
            distinct: true,
            order_by: r.rapporteur,
            select: r.rapporteur
        ),
      years:
        Repo.all(
          from r in published,
            where: not is_nil(r.ruling_year),
            distinct: true,
            order_by: r.ruling_year,
            select: r.ruling_year
        )
    }
  end

  @doc "Corpus counters for the methodology page."
  @spec stats() :: map()
  def stats do
    %{
      published: Repo.aggregate(from(r in Ruling, where: r.status == "published"), :count),
      pending: Repo.aggregate(from(r in Ruling, where: r.status == "pending_review"), :count),
      withdrawn: Repo.aggregate(from(r in Ruling, where: r.status == "withdrawn"), :count),
      excluded: Repo.aggregate(Lexec.Catalog.Exclusion, :count),
      paragraphs:
        Repo.aggregate(
          from(p in Paragraph,
            join: r in Ruling,
            on: r.id == p.ruling_id,
            where: r.status == "published"
          ),
          :count
        )
    }
  end

  @doc """
  Withdraws a ruling: removes it from the search index and deletes every
  paragraph, relation and stat from the catalog. Only the case number and the
  `withdrawn` status remain, so it is never harvested again.
  """
  @spec withdraw(String.t()) :: {:ok, Ruling.t()} | {:error, term()}
  def withdraw(case_number) when is_binary(case_number) do
    case Repo.get_by(Ruling, case_number: case_number) do
      nil ->
        {:error, :not_found}

      %Ruling{status: "withdrawn"} = ruling ->
        {:ok, ruling}

      ruling ->
        with :ok <- Index.delete_ruling(ruling.id) do
          Repo.transaction(fn ->
            Repo.delete_all(from p in Paragraph, where: p.ruling_id == ^ruling.id)
            Repo.delete_all(from c in Citation, where: c.citing_ruling_id == ^ruling.id)
            Repo.delete_all(from n in CitedNorm, where: n.ruling_id == ^ruling.id)
            Repo.delete_all(from s in AnonymizationStat, where: s.ruling_id == ^ruling.id)

            from(c in Citation, where: c.cited_ruling_id == ^ruling.id)
            |> Repo.update_all(set: [cited_ruling_id: nil])

            ruling
            |> Ecto.Changeset.change(status: "withdrawn", paragraph_count: 0)
            |> Repo.update!()
          end)
        end
    end
  end

  @doc "Publishes a ruling that was waiting for review and indexes it."
  @spec publish(Ruling.t()) :: {:ok, Ruling.t()} | {:error, term()}
  def publish(%Ruling{status: "pending_review"} = ruling) do
    ruling = ruling |> Ecto.Changeset.change(status: "published") |> Repo.update!()

    case Index.index_ruling(ruling) do
      :ok -> {:ok, ruling}
      {:error, reason} -> {:error, {:index_failed, reason}}
    end
  end

  def publish(%Ruling{}), do: {:error, :not_pending}
end
