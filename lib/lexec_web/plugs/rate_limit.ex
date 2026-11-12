defmodule LexecWeb.Plugs.RateLimit do
  @moduledoc "Per-IP rate limit for page loads (bucket `page` in app.yaml)."
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: Keyword.get(opts, :bucket, "page")

  @impl true
  def call(conn, bucket) do
    case Lexec.RateLimiter.hit(bucket, conn.remote_ip) do
      :ok ->
        conn

      {:error, :rate_limited} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> send_resp(429, "Demasiadas solicitudes. Intente de nuevo en un minuto.")
        |> halt()
    end
  end
end
