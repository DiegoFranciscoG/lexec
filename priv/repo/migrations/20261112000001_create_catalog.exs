defmodule Lexec.Repo.Migrations.CreateCatalog do
  use Ecto.Migration

  def change do
    create table(:fetched_documents) do
      add :url, :string, null: false
      add :sha256, :string, size: 64
      add :status, :string, null: false
      add :error, :string
      add :fetched_at, :utc_datetime, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:fetched_documents, [:url])

    create table(:rulings) do
      add :case_number, :string, null: false
      add :case_file, :string
      add :action_type, :string, null: false
      add :ruling_year, :integer
      add :decided_on, :date
      add :rapporteur, :string
      add :decision, :string, null: false, default: "other"
      add :official_url, :string, null: false
      add :pdf_sha256, :string, size: 64
      add :status, :string, null: false
      add :rules_version, :string, null: false
      add :paragraph_count, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create unique_index(:rulings, [:case_number])
    create unique_index(:rulings, [:pdf_sha256])
    create index(:rulings, [:status])
    create index(:rulings, [:action_type, :ruling_year])

    create table(:paragraphs) do
      add :ruling_id, references(:rulings, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :text, :text, null: false
    end

    create unique_index(:paragraphs, [:ruling_id, :number])
    create constraint(:paragraphs, :number_positive, check: "number >= 1")

    create table(:ruling_citations) do
      add :citing_ruling_id, references(:rulings, on_delete: :delete_all), null: false
      add :cited_case_number, :string, null: false
      add :cited_ruling_id, references(:rulings, on_delete: :nilify_all)
      add :paragraph_number, :integer, null: false
    end

    create unique_index(:ruling_citations, [
             :citing_ruling_id,
             :cited_case_number,
             :paragraph_number
           ])

    create index(:ruling_citations, [:cited_case_number])
    create index(:ruling_citations, [:cited_ruling_id])

    create table(:cited_norms) do
      add :ruling_id, references(:rulings, on_delete: :delete_all), null: false
      add :norm_body, :string, null: false
      add :article, :string, null: false
      add :paragraph_number, :integer, null: false
    end

    create unique_index(:cited_norms, [:ruling_id, :norm_body, :article, :paragraph_number])
    create index(:cited_norms, [:norm_body, :article])

    create table(:exclusions) do
      add :source_url, :string, null: false
      add :case_number, :string
      add :reason, :string, null: false
      add :rule_id, :string, null: false
      add :rules_version, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:exclusions, [:source_url])

    create table(:anonymization_stats) do
      add :ruling_id, references(:rulings, on_delete: :delete_all), null: false
      add :entity_type, :string, null: false
      add :count, :integer, null: false
      add :rules_version, :string, null: false
      add :ner_model, :string
    end

    create index(:anonymization_stats, [:ruling_id])
    create constraint(:anonymization_stats, :count_not_negative, check: "count >= 0")

    create table(:review_items) do
      add :ruling_id, references(:rulings, on_delete: :delete_all), null: false
      add :reason, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :reviewer, :string
      add :reviewed_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:review_items, [:status])

    create table(:correction_requests) do
      add :case_number, :string, null: false
      add :paragraph_number, :integer
      add :request_type, :string, null: false
      add :reason, :text, null: false
      add :contact_email, :string
      add :consent, :boolean, null: false, default: false
      add :status, :string, null: false, default: "received"
      add :action_taken, :string
      add :due_on, :date, null: false
      add :resolved_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create index(:correction_requests, [:status])
  end
end
