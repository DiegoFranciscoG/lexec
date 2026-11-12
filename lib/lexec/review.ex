defmodule Lexec.Review do
  @moduledoc "Human review queue: rulings with doubtful anonymization wait here."

  import Ecto.Query
  alias Lexec.{Catalog, Repo}
  alias Lexec.Catalog.{ReviewItem, Ruling}

  @spec list_pending() :: [map()]
  def list_pending do
    Repo.all(
      from i in ReviewItem,
        join: r in Ruling,
        on: r.id == i.ruling_id,
        where: i.status == "pending",
        order_by: i.inserted_at,
        select: %{id: i.id, reason: i.reason, case_number: r.case_number, ruling_id: r.id}
    )
  end

  @doc "Paragraphs of a pending ruling (already anonymized) for the reviewer."
  @spec pending_paragraphs(integer()) :: [map()]
  def pending_paragraphs(ruling_id) do
    Repo.all(
      from p in Lexec.Catalog.Paragraph,
        join: r in Ruling,
        on: r.id == p.ruling_id,
        where: r.id == ^ruling_id and r.status == "pending_review",
        order_by: p.number,
        select: %{number: p.number, text: p.text}
    )
  end

  @spec approve(integer(), String.t()) :: {:ok, ReviewItem.t()} | {:error, term()}
  def approve(item_id, reviewer), do: resolve(item_id, reviewer, "approved")

  @spec withdraw(integer(), String.t()) :: {:ok, ReviewItem.t()} | {:error, term()}
  def withdraw(item_id, reviewer), do: resolve(item_id, reviewer, "withdrawn")

  defp resolve(item_id, reviewer, status) do
    with %ReviewItem{status: "pending"} = item <- Repo.get(ReviewItem, item_id),
         ruling = Repo.get!(Ruling, item.ruling_id),
         {:ok, _ruling} <- apply_decision(status, ruling) do
      item
      |> Ecto.Changeset.change(
        status: status,
        reviewer: reviewer,
        reviewed_at: DateTime.utc_now(:second)
      )
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      %ReviewItem{} -> {:error, :already_resolved}
      error -> error
    end
  end

  defp apply_decision("approved", ruling), do: Catalog.publish(ruling)
  defp apply_decision("withdrawn", ruling), do: Catalog.withdraw(ruling.case_number)
end
