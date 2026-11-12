defmodule Lexec.Corrections.Request do
  @moduledoc """
  A public correction or withdrawal request. Contact e-mail is optional and
  only stored with explicit consent (LOPDP: minimization and consent).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @types ~w(correction withdrawal)
  @statuses ~w(received withdrawn corrected rejected)

  schema "correction_requests" do
    field :case_number, :string
    field :paragraph_number, :integer
    field :request_type, :string
    field :reason, :string
    field :contact_email, :string
    field :consent, :boolean, default: false
    field :status, :string, default: "received"
    field :action_taken, :string
    field :due_on, :date
    field :resolved_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def types, do: @types
  def statuses, do: @statuses

  def changeset(request, attrs) do
    config = Lexec.Rules.fetch!(:app, ["corrections"])

    request
    |> cast(attrs, [
      :case_number,
      :paragraph_number,
      :request_type,
      :reason,
      :contact_email,
      :consent
    ])
    |> update_change(:case_number, &(&1 && String.trim(&1)))
    |> update_change(:contact_email, &blank_to_nil/1)
    |> validate_required([:case_number, :request_type, :reason])
    |> validate_format(
      :case_number,
      ~r/^(\d{1,5}-\d{2}-[A-Z]{2}\/\d{2}|\d{3}-\d{2}-S[A-Z]{2,3}-CC)$/,
      message: "use el formato 1234-19-EP/23"
    )
    |> validate_inclusion(:request_type, @types)
    |> validate_length(:reason, min: config["reason_min"], max: config["reason_max"])
    |> validate_number(:paragraph_number, greater_than: 0, less_than: 10_000)
    |> validate_format(:contact_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: "correo no válido"
    )
    |> validate_length(:contact_email, max: 160)
    |> validate_consent()
  end

  defp validate_consent(changeset) do
    if get_field(changeset, :contact_email) && get_field(changeset, :consent) != true do
      add_error(changeset, :consent, "debe aceptar el uso de su correo para responderle")
    else
      changeset
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end

defmodule Lexec.Corrections do
  @moduledoc "Correction and withdrawal workflow (T-11)."

  import Ecto.Query
  alias Lexec.{Catalog, Repo, Rules}
  alias Lexec.Corrections.Request

  @spec change_request(map()) :: Ecto.Changeset.t()
  def change_request(attrs \\ %{}), do: Request.changeset(%Request{}, attrs)

  @spec create_request(map()) :: {:ok, Request.t()} | {:error, Ecto.Changeset.t()}
  def create_request(attrs) do
    days = Rules.fetch!(:app, ["corrections", "response_days"])

    %Request{due_on: Date.add(Date.utc_today(), days)}
    |> Request.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_open() :: [Request.t()]
  def list_open do
    Repo.all(from r in Request, where: r.status == "received", order_by: r.due_on)
  end

  @doc """
  Resolves a request. `:withdraw` removes the ruling from the index and the
  catalog; `:correct` and `:reject` only close the request with a note.
  """
  @spec resolve(integer(), :withdraw | :correct | :reject, String.t()) ::
          {:ok, Request.t()} | {:error, term()}
  def resolve(id, action, note \\ "") when action in [:withdraw, :correct, :reject] do
    with %Request{status: "received"} = request <- Repo.get(Request, id),
         :ok <- apply_action(action, request) do
      request
      |> Ecto.Changeset.change(
        status: status_for(action),
        action_taken: String.slice(note, 0, 250),
        # The contact address was only kept to answer this request.
        contact_email: nil,
        resolved_at: DateTime.utc_now(:second)
      )
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      %Request{} -> {:error, :already_resolved}
      error -> error
    end
  end

  defp apply_action(:withdraw, request) do
    case Catalog.withdraw(request.case_number) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok
      error -> error
    end
  end

  defp apply_action(_other, _request), do: :ok

  defp status_for(:withdraw), do: "withdrawn"
  defp status_for(:correct), do: "corrected"
  defp status_for(:reject), do: "rejected"
end
