defmodule LexecWeb.CorrectionReviewTest do
  use LexecWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lexec.Catalog.{ReviewItem, Ruling}
  alias Lexec.{CorpusCase, RateLimiter, Repo}
  alias Lexec.Corrections.Request

  setup do
    RateLimiter.reset()
    CorpusCase.ingest_corpus()
    :ok
  end

  defp admin(conn),
    do:
      put_req_header(
        conn,
        "authorization",
        Plug.BasicAuth.encode_basic_auth("revisor", "test-only-password")
      )

  describe "correction form" do
    test "validates, then stores the request with its due date", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/correccion?caso=9101-20-EP/23")
      assert html =~ ~s(value="9101-20-EP/23")

      assert view
             |> form("#correction-form", request: %{case_number: "mal", reason: "x"})
             |> render_change() =~ "use el formato 1234-19-EP/23"

      html =
        view
        |> form("#correction-form",
          request: %{
            case_number: "9101-20-EP/23",
            request_type: "withdrawal",
            reason: "El párrafo 1 permite identificarme."
          }
        )
        |> render_submit()

      assert html =~ "Solicitud recibida"
      assert [%Request{case_number: "9101-20-EP/23", contact_email: nil}] = Repo.all(Request)
    end

    test "is rate limited per connection", %{conn: conn} do
      limit = Lexec.Rules.fetch!(:app, ["rate_limits", "correction", "limit"])

      for _ <- 1..limit do
        {:ok, view, _} = live(conn, ~p"/correccion")

        view
        |> form("#correction-form",
          request: %{case_number: "9101-20-EP/23", reason: "Motivo suficientemente largo."}
        )
        |> render_submit()
      end

      {:ok, view, _} = live(conn, ~p"/correccion")

      html =
        view
        |> form("#correction-form",
          request: %{case_number: "9101-20-EP/23", reason: "Motivo suficientemente largo."}
        )
        |> render_submit()

      assert html =~ "Ya recibimos varias solicitudes"
    end
  end

  describe "review area" do
    test "requires basic auth", %{conn: conn} do
      assert conn |> get(~p"/admin/revision") |> response(401)

      bad =
        put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth("revisor", "otra"))

      assert bad |> get(~p"/admin/revision") |> response(401)
    end

    test "refuses everyone when credentials are not configured", %{conn: conn} do
      previous = Application.get_env(:lexec, :admin_password)
      Application.put_env(:lexec, :admin_password, nil)
      on_exit(fn -> Application.put_env(:lexec, :admin_password, previous) end)

      assert conn |> admin() |> get(~p"/admin/revision") |> response(401)
    end

    test "approves a pending ruling and resolves a withdrawal request", %{conn: conn} do
      ruling = Repo.get_by!(Ruling, case_number: "9110-20-EP/24")
      ruling |> Ecto.Changeset.change(status: "pending_review") |> Repo.update!()

      item =
        Repo.insert!(%ReviewItem{
          ruling_id: ruling.id,
          reason: "ner_low_confidence:1",
          status: "pending"
        })

      {:ok, request} =
        Lexec.Corrections.create_request(%{
          "case_number" => "9111-23-EP/25",
          "request_type" => "withdrawal",
          "reason" => "Solicito retirar esta sentencia."
        })

      {:ok, view, html} = conn |> admin() |> live(~p"/admin/revision")
      assert html =~ "9110-20-EP/24"
      assert html =~ "Sesión de revisor"

      assert view
             |> element("#item-#{item.id} button", "Leer texto anonimizado")
             |> render_click() =~ "[PERSONA 1]"

      assert view |> element("#item-#{item.id} button", "Aprobar y publicar") |> render_click() =~
               "Sentencia publicada."

      assert Repo.get!(Ruling, ruling.id).status == "published"

      assert view |> element("#request-#{request.id} button", "Retirar") |> render_click() =~
               "Solicitud cerrada."

      assert Repo.get_by!(Ruling, case_number: "9111-23-EP/25").status == "withdrawn"
    end
  end

  describe "operations and security headers" do
    test "health check reports ok without details", %{conn: conn} do
      assert %{"status" => "ok"} = conn |> get(~p"/health") |> json_response(200)
    end

    test "strict CSP and security headers on every page", %{conn: conn} do
      conn = get(conn, ~p"/")
      [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'self'"
      assert csp =~ "script-src 'self'"
      refute csp =~ "unsafe-inline"
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    end

    test "the session cookie is Secure when the site runs over HTTPS", %{conn: conn} do
      Application.put_env(:lexec, :secure_cookies, true)
      on_exit(fn -> Application.delete_env(:lexec, :secure_cookies) end)

      [cookie] = conn |> get(~p"/") |> get_resp_header("set-cookie")
      assert cookie =~ ~r/;\s*secure/i
    end

    test "the session cookie is the only cookie and is HttpOnly", %{conn: conn} do
      conn = get(conn, ~p"/")
      cookies = get_resp_header(conn, "set-cookie")
      assert Enum.all?(cookies, &String.starts_with?(&1, "_lexec_key="))
      assert Enum.all?(cookies, &(&1 =~ ~r/HttpOnly/i))
    end

    test "page loads are rate limited per IP", %{conn: conn} do
      limit = Lexec.Rules.fetch!(:app, ["rate_limits", "page", "limit"])
      for _ <- 1..limit, do: get(conn, ~p"/aviso-legal")
      assert get(conn, ~p"/aviso-legal") |> response(429)
    end
  end
end
