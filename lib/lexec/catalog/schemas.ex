defmodule Lexec.Catalog.Ruling do
  @moduledoc "A published (or pending/withdrawn) ruling. Only anonymized text hangs from it."
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending_review published withdrawn)
  @decisions ~w(accepted partially_accepted dismissed rejected other)

  schema "rulings" do
    field :case_number, :string
    field :case_file, :string
    field :action_type, :string
    field :ruling_year, :integer
    field :decided_on, :date
    field :rapporteur, :string
    field :decision, :string, default: "other"
    field :official_url, :string
    field :pdf_sha256, :string
    field :status, :string
    field :rules_version, :string
    field :paragraph_count, :integer, default: 0

    has_many :paragraphs, Lexec.Catalog.Paragraph, preload_order: [asc: :number]
    has_many :citations, Lexec.Catalog.Citation, foreign_key: :citing_ruling_id
    has_many :norms, Lexec.Catalog.CitedNorm

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def decisions, do: @decisions

  def changeset(ruling, attrs) do
    types = Map.keys(Lexec.Rules.fetch!(:action_types, ["types"]))

    ruling
    |> cast(attrs, [
      :case_number,
      :case_file,
      :action_type,
      :ruling_year,
      :decided_on,
      :rapporteur,
      :decision,
      :official_url,
      :pdf_sha256,
      :status,
      :rules_version,
      :paragraph_count
    ])
    |> validate_required([:case_number, :action_type, :official_url, :status, :rules_version])
    |> validate_format(:case_number, ~r/^(\d{1,5}-\d{2}-[A-Z]{2}\/\d{2}|\d{3}-\d{2}-S[A-Z]{2,3}-CC)$/)
    |> validate_inclusion(:action_type, types)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:decision, @decisions)
    |> validate_format(:official_url, ~r/^https:\/\/[^\s]+$/)
    |> validate_format(:pdf_sha256, ~r/^[0-9a-f]{64}$/)
    |> validate_number(:paragraph_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:case_number)
    |> unique_constraint(:pdf_sha256)
  end
end

defmodule Lexec.Catalog.Paragraph do
  @moduledoc "A numbered paragraph of a ruling. `text` is always anonymized."
  use Ecto.Schema

  schema "paragraphs" do
    belongs_to :ruling, Lexec.Catalog.Ruling
    field :number, :integer
    field :text, :string
  end
end

defmodule Lexec.Catalog.Citation do
  @moduledoc "Ruling A cites ruling B (by case number) in paragraph N."
  use Ecto.Schema

  schema "ruling_citations" do
    belongs_to :citing_ruling, Lexec.Catalog.Ruling
    belongs_to :cited_ruling, Lexec.Catalog.Ruling
    field :cited_case_number, :string
    field :paragraph_number, :integer
  end
end

defmodule Lexec.Catalog.CitedNorm do
  @moduledoc "An article of a legal body invoked in paragraph N."
  use Ecto.Schema

  schema "cited_norms" do
    belongs_to :ruling, Lexec.Catalog.Ruling
    field :norm_body, :string
    field :article, :string
    field :paragraph_number, :integer
  end
end

defmodule Lexec.Catalog.Exclusion do
  @moduledoc "Why a document was excluded. Never stores any of its text."
  use Ecto.Schema
  import Ecto.Changeset

  @reasons ~w(minors violence reserved other)

  schema "exclusions" do
    field :source_url, :string
    field :case_number, :string
    field :reason, :string
    field :rule_id, :string
    field :rules_version, :string
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(exclusion, attrs) do
    exclusion
    |> cast(attrs, [:source_url, :case_number, :reason, :rule_id, :rules_version])
    |> validate_required([:source_url, :reason, :rule_id, :rules_version])
    |> validate_inclusion(:reason, @reasons)
    |> unique_constraint(:source_url)
  end
end

defmodule Lexec.Catalog.AnonymizationStat do
  @moduledoc "How many entities of a type were replaced. Never the original value."
  use Ecto.Schema

  schema "anonymization_stats" do
    belongs_to :ruling, Lexec.Catalog.Ruling
    field :entity_type, :string
    field :count, :integer
    field :rules_version, :string
    field :ner_model, :string
  end
end

defmodule Lexec.Catalog.ReviewItem do
  @moduledoc "A ruling waiting for human review before it is published."
  use Ecto.Schema

  schema "review_items" do
    belongs_to :ruling, Lexec.Catalog.Ruling
    field :reason, :string
    field :status, :string, default: "pending"
    field :reviewer, :string
    field :reviewed_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end

defmodule Lexec.Catalog.FetchedDocument do
  @moduledoc "Download cache: a URL is never fetched twice once it succeeded."
  use Ecto.Schema

  schema "fetched_documents" do
    field :url, :string
    field :sha256, :string
    field :status, :string
    field :error, :string
    field :fetched_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
