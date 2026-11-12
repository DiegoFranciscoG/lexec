defmodule LexecWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP Basic auth for the review area. Credentials come only from the
  environment (`ADMIN_USER`, `ADMIN_PASSWORD`); without them every request
  is refused. Failed attempts are rate limited per client.
  """

  import Plug.Conn
  alias Lexec.RateLimiter

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = Application.get_env(:lexec, :admin_user)
    password = Application.get_env(:lexec, :admin_password)

    with true <- is_binary(user) and user != "" and is_binary(password) and password != "",
         :ok <- RateLimiter.hit("admin_auth", conn.remote_ip),
         {given_user, given_password} <- Plug.BasicAuth.parse_basic_auth(conn),
         true <-
           Plug.Crypto.secure_compare(given_user, user) and
             Plug.Crypto.secure_compare(given_password, password) do
      assign(conn, :reviewer, user)
    else
      {:error, :rate_limited} ->
        conn |> send_resp(429, "Demasiados intentos. Intente más tarde.") |> halt()

      _ ->
        conn |> Plug.BasicAuth.request_basic_auth(realm: "LEXEC revision") |> halt()
    end
  end

  @doc false
  def live_session(conn), do: %{"reviewer" => conn.assigns[:reviewer]}

  @doc false
  def on_mount(:ensure_reviewer, _params, session, socket) do
    case session do
      %{"reviewer" => reviewer} when is_binary(reviewer) ->
        {:cont, Phoenix.Component.assign(socket, :reviewer, reviewer)}

      _ ->
        {:halt, Phoenix.LiveView.redirect(socket, to: "/")}
    end
  end
end
