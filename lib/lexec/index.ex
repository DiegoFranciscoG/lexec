defmodule Lexec.Index do
  @moduledoc """
  Search index of anonymized paragraphs.

  Backend from `config :lexec, :index`: `Lexec.Index.Meili` (hybrid search)
  or `Lexec.Index.Sql` (keyword search on the catalog, used in tests and as a
  fallback). Only rulings with status `published` are ever indexed.
  """

  import Ecto.Query
  alias Lexec.Catalog.{Paragraph, Ruling}
  alias Lexec.{Embeddings, Repo}

  @type filters :: %{
          optional(:action_type) => String.t(),
          optional(:year_from) => integer(),
          optional(:year_to) => integer(),
          optional(:rapporteur) => String.t()
        }

  @type hit :: %{
          id: String.t(),
          ruling_id: integer(),
          case_number: String.t(),
          paragraph_number: integer(),
          text: String.t(),
          action_type: String.t(),
          ruling_year: integer() | nil,
          decided_on: String.t() | nil,
          rapporteur: String.t() | nil,
          official_url: String.t()
        }

  @type search_opts :: [
          filters: filters(),
          semantic_ratio: float(),
          limit: pos_integer(),
          offset: non_neg_integer()
        ]

  @callback setup() :: :ok | {:error, term()}
  @callback upsert([map()]) :: :ok | {:error, term()}
  @callback delete_ruling(integer()) :: :ok | {:error, term()}
  @callback search(String.t(), search_opts()) ::
              {:ok, %{hits: [hit()], total: non_neg_integer()}} | {:error, term()}
  @callback reset() :: :ok | {:error, term()}

  @spec backend() :: module()
  def backend, do: Application.fetch_env!(:lexec, :index)

  @spec setup() :: :ok | {:error, term()}
  def setup, do: backend().setup()

  @spec search(String.t(), search_opts()) ::
          {:ok, %{hits: [hit()], total: non_neg_integer()}} | {:error, term()}
  def search(query, opts \\ []), do: backend().search(query, opts)

  @spec delete_ruling(integer()) :: :ok | {:error, term()}
  def delete_ruling(ruling_id), do: backend().delete_ruling(ruling_id)

  @doc "Indexes every paragraph of a published ruling (with embeddings if enabled)."
  @spec index_ruling(Ruling.t()) :: :ok | {:error, term()}
  def index_ruling(%Ruling{status: "published"} = ruling) do
    paragraphs =
      Repo.all(from p in Paragraph, where: p.ruling_id == ^ruling.id, order_by: p.number)

    vectors = Embeddings.embed_passages(Enum.map(paragraphs, & &1.text))

    docs =
      paragraphs
      |> Enum.with_index()
      |> Enum.map(fn {paragraph, i} ->
        doc = document(ruling, paragraph)
        if vectors, do: Map.put(doc, "_vectors", %{"e5" => Enum.at(vectors, i)}), else: doc
      end)

    backend().upsert(docs)
  end

  def index_ruling(%Ruling{}), do: {:error, :not_published}

  @doc "Rebuilds the whole index from the catalog."
  @spec reindex_all() :: {:ok, non_neg_integer()} | {:error, term()}
  def reindex_all do
    with :ok <- backend().reset(),
         :ok <- backend().setup() do
      Ruling
      |> where([r], r.status == "published")
      |> Repo.all()
      |> Enum.reduce_while({:ok, 0}, fn ruling, {:ok, n} ->
        case index_ruling(ruling) do
          :ok -> {:cont, {:ok, n + 1}}
          error -> {:halt, error}
        end
      end)
    end
  end

  @doc false
  @spec document(Ruling.t(), Paragraph.t()) :: map()
  def document(ruling, paragraph) do
    %{
      "id" => "#{ruling.id}-#{paragraph.number}",
      "ruling_id" => ruling.id,
      "case_number" => ruling.case_number,
      "paragraph_number" => paragraph.number,
      "text" => paragraph.text,
      "action_type" => ruling.action_type,
      "ruling_year" => ruling.ruling_year,
      "decided_on" => ruling.decided_on && Date.to_iso8601(ruling.decided_on),
      "rapporteur" => ruling.rapporteur,
      "official_url" => ruling.official_url
    }
  end

  @doc false
  @spec to_hit(map()) :: hit()
  def to_hit(doc) do
    %{
      id: doc["id"],
      ruling_id: doc["ruling_id"],
      case_number: doc["case_number"],
      paragraph_number: doc["paragraph_number"],
      text: doc["text"],
      action_type: doc["action_type"],
      ruling_year: doc["ruling_year"],
      decided_on: doc["decided_on"],
      rapporteur: doc["rapporteur"],
      official_url: doc["official_url"]
    }
  end
end
