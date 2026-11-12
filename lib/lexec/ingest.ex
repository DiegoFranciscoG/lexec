defmodule Lexec.Ingest do
  @moduledoc """
  Processes one ruling's extracted text end to end:

      parse (regex) → EXCLUDE? → anonymize (rules + NER) → relations → catalog → index

  Exclusion happens before any model is invoked: an excluded ruling only
  leaves a row in `exclusions` (reason and rule id, no text).
  """

  require Logger
  import Ecto.Query

  alias Lexec.Catalog.{AnonymizationStat, Citation, CitedNorm, Paragraph, ReviewItem, Ruling}
  alias Lexec.Catalog.Exclusion, as: ExclusionRecord
  alias Lexec.Extract.Parser
  alias Lexec.{Index, Relations, Repo, Rules}
  alias Lexec.Privacy.{Anonymizer, Exclusion, Ner}

  @type source :: %{
          required(:url) => String.t(),
          optional(:sha256) => String.t() | nil,
          optional(:flags) => [String.t()],
          optional(:case_number) => String.t() | nil
        }

  @type result ::
          {:ok, %Ruling{}}
          | {:excluded, String.t()}
          | {:skipped, :duplicate | :withdrawn}
          | {:error, term()}

  @spec ingest(String.t(), source()) :: result()
  def ingest(text, %{url: url} = source) when is_binary(text) do
    doc = Parser.parse(text)
    case_number = doc.case_number || source[:case_number]

    decision =
      Exclusion.evaluate(%{
        text: text,
        case_number: case_number,
        action_type: doc.action_type,
        flags: source[:flags] || []
      })

    cond do
      match?({:exclude, _, _}, decision) ->
        {:exclude, reason, rule_id} = decision
        record_exclusion(url, case_number, reason, rule_id)

      is_nil(case_number) or is_nil(doc.action_type) ->
        {:error, :missing_case_number}

      doc.paragraphs == [] ->
        {:error, :no_paragraphs}

      existing = Repo.get_by(Ruling, case_number: case_number) ->
        if existing.status == "withdrawn",
          do: {:skipped, :withdrawn},
          else: {:skipped, :duplicate}

      true ->
        process(%{doc | case_number: case_number}, source)
    end
  end

  defp record_exclusion(url, case_number, reason, rule_id) do
    %ExclusionRecord{}
    |> ExclusionRecord.changeset(%{
      source_url: url,
      case_number: case_number,
      reason: reason,
      rule_id: rule_id,
      rules_version: Exclusion.rules_version()
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: :source_url)
    |> case do
      {:ok, _} -> {:excluded, reason}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp process(doc, source) do
    %{paragraphs: paragraphs, stats: stats, review_reasons: reasons} =
      Anonymizer.anonymize(doc.paragraphs)

    relations = Relations.extract(paragraphs, doc.case_number)
    status = if reasons == [], do: "published", else: "pending_review"
    rules_version = Rules.pipeline_version()

    Repo.transaction(fn ->
      ruling =
        %Ruling{}
        |> Ruling.changeset(%{
          case_number: doc.case_number,
          case_file: doc.case_file,
          action_type: doc.action_type,
          ruling_year: doc.ruling_year,
          decided_on: doc.decided_on,
          rapporteur: doc.rapporteur,
          decision: doc.decision,
          official_url: source.url,
          pdf_sha256: source[:sha256],
          status: status,
          rules_version: rules_version,
          paragraph_count: length(paragraphs)
        })
        |> Repo.insert!()

      Repo.insert_all(
        Paragraph,
        Enum.map(paragraphs, &%{ruling_id: ruling.id, number: &1.number, text: &1.text})
      )

      cited_ids = resolve_cited(relations.citations)

      Repo.insert_all(
        Citation,
        Enum.map(relations.citations, fn c ->
          %{
            citing_ruling_id: ruling.id,
            cited_case_number: c.cited_case_number,
            cited_ruling_id: Map.get(cited_ids, c.cited_case_number),
            paragraph_number: c.paragraph_number
          }
        end)
      )

      # Earlier rulings that cited this one now point to it.
      from(c in Citation, where: c.cited_case_number == ^ruling.case_number)
      |> Repo.update_all(set: [cited_ruling_id: ruling.id])

      Repo.insert_all(CitedNorm, Enum.map(relations.norms, &Map.put(&1, :ruling_id, ruling.id)))

      Repo.insert_all(
        AnonymizationStat,
        Enum.map(stats, fn {type, count} ->
          %{
            ruling_id: ruling.id,
            entity_type: type,
            count: count,
            rules_version: Rules.version(:anonymization),
            ner_model: Ner.model_name()
          }
        end)
      )

      if reasons != [] do
        now = DateTime.utc_now(:second)

        Repo.insert!(%ReviewItem{
          ruling_id: ruling.id,
          reason: Enum.join(reasons, ","),
          status: "pending",
          inserted_at: now,
          updated_at: now
        })
      end

      ruling
    end)
    |> case do
      {:ok, %Ruling{status: "published"} = ruling} ->
        index_or_log(ruling)
        {:ok, ruling}

      {:ok, ruling} ->
        {:ok, ruling}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error in Ecto.InvalidChangesetError -> {:error, error.changeset}
  end

  defp resolve_cited([]), do: %{}

  defp resolve_cited(citations) do
    numbers = citations |> Enum.map(& &1.cited_case_number) |> Enum.uniq()

    from(r in Ruling, where: r.case_number in ^numbers, select: {r.case_number, r.id})
    |> Repo.all()
    |> Map.new()
  end

  @doc false
  def index_or_log(ruling) do
    case Index.index_ruling(ruling) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("index failed for ruling #{ruling.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
