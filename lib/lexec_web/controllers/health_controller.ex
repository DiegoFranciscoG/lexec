defmodule LexecWeb.HealthController do
  use LexecWeb, :controller

  alias Ecto.Adapters.SQL

  @doc "Liveness and database check for container health checks. Exposes nothing else."
  def show(conn, _params) do
    case SQL.query(Lexec.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(503) |> json(%{status: "unavailable"})
    end
  end
end
