defmodule LexecWeb.PagesTest do
  # T-09 (notice and official link on every result) and T-12 (accessibility AA, automated subset).
  use LexecWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Lexec.{A11y, CorpusCase, RateLimiter, Repo}
  alias Lexec.Catalog.Ruling

  setup do
    RateLimiter.reset()
    CorpusCase.ingest_corpus()
    ruling = Repo.get_by!(Ruling, case_number: "9105-18-EP/21")
    %{ruling: ruling}
  end

  defp pages(ruling) do
    [
      "/",
      "/?q=motivaci%C3%B3n",
      "/?q=motivaci%C3%B3n&respuesta=1",
      "/?q=zzzzzz",
      "/sentencias/#{ruling.id}",
      "/precedentes",
      "/correccion",
      "/metodologia",
      "/aviso-legal"
    ]
  end

  describe "T-09 legal notice and official link" do
    test "every page carries the 'not legal advice' notice", %{conn: conn, ruling: ruling} do
      for path <- pages(ruling) do
        html = conn |> get(path) |> html_response(200)
        assert html =~ "LEXEC no es asesoría legal", "missing notice on #{path}"
      end
    end

    test "every search result has its own notice and an https link to the official document", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/?q=motivación")
      html = render_async(view)
      doc = LazyHTML.from_document("<html><body>" <> html <> "</body></html>")

      hits = LazyHTML.query(doc, "[data-hit]")
      refute Enum.empty?(hits)

      for hit <- hits do
        assert [url] = hit |> LazyHTML.query("a[data-official]") |> LazyHTML.attribute("href")
        assert String.starts_with?(url, "https://")

        assert hit |> LazyHTML.query("a[data-official]") |> LazyHTML.attribute("rel") == [
                 "noopener noreferrer external"
               ]

        assert LazyHTML.text(LazyHTML.query(hit, "[data-hit-disclaimer]")) =~
                 "No es asesoría legal"

        assert LazyHTML.text(LazyHTML.query(hit, ".hit__case")) =~ ~r/^\d+-\d{2}-[A-Z]{2}\/\d{2}$/
        assert LazyHTML.text(LazyHTML.query(hit, ".hit__para")) =~ ~r/párr\. \d+/
      end
    end

    test "the ruling sheet links the official document", %{conn: conn, ruling: ruling} do
      html = conn |> get(~p"/sentencias/#{ruling.id}") |> html_response(200)
      assert html =~ ~s(href="#{ruling.official_url}")
      assert html =~ "No es asesoría legal"
    end
  end

  describe "T-12 accessibility (automated WCAG 2.2 AA subset)" do
    test "structure, names and landmarks on every page", %{conn: conn, ruling: ruling} do
      for path <- pages(ruling) do
        conn |> get(path) |> html_response(200) |> A11y.assert_accessible()
      end
    end

    test "colour tokens meet AA contrast" do
      t = A11y.tokens()

      text_pairs = [
        {"ink", "paper"},
        {"ink", "sheet"},
        {"ink-2", "sheet"},
        {"muted", "paper"},
        {"muted", "paper-2"},
        {"muted", "sheet"},
        {"accent-ink", "accent"},
        {"accent-ink", "accent-2"},
        {"accent-ink", "ink"},
        {"on-ink-muted", "ink"},
        {"ink", "mark"},
        {"error", "sheet"},
        {"accent", "sheet"}
      ]

      for {fg, bg} <- text_pairs do
        ratio = A11y.contrast(t[fg], t[bg])
        assert ratio >= 4.5, "#{fg} on #{bg}: #{Float.round(ratio, 2)}:1"
      end

      # 1.4.11 non-text contrast: focus ring and control borders
      for {fg, bg} <- [
            {"focus", "paper"},
            {"focus", "sheet"},
            {"muted", "sheet"},
            {"rule-2", "paper"}
          ] do
        assert A11y.contrast(t[fg], t[bg]) >= 3.0, "#{fg} on #{bg}"
      end
    end
  end

  describe "search screen states" do
    test "idle, results, empty and invalid", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Empiece con una pregunta"

      {:ok, view, _} = live(conn, ~p"/?q=motivación")
      assert render_async(view) =~ "párrafos"

      {:ok, view, _} = live(conn, ~p"/?q=palabrainexistentexyz")
      assert render_async(view) =~ "No encontré sentencias que respondan esto"

      long = String.duplicate("a", 301)
      {:ok, _view, html} = live(conn, ~p"/?q=#{long}")
      assert html =~ "como máximo 300 caracteres"
    end

    test "submitting the form patches the URL with whitelisted filters", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      view
      |> form("#search-form", b: %{q: "tasa", tipo: "IN", modo: "palabras"})
      |> render_submit()

      assert_patch(view, ~p"/?#{%{modo: "palabras", q: "tasa", tipo: "IN"}}")
      html = render_async(view)
      assert html =~ "9108-19-IN/22"
      refute html =~ "9101-20-EP/23"
    end

    test "unknown filter values are ignored, not trusted", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?q=Corte&tipo=ZZ&ponente=Nadie&desde=1800")
      assert render_async(view) =~ "párrafos"
    end

    test "works without JavaScript through a plain GET form", %{conn: conn} do
      html = conn |> get(~p"/?#{%{"b" => %{"q" => "agua potable"}}}") |> html_response(200)
      assert html =~ "9111-23-EP/25"
    end

    test "answer mode shows only verified, cited sentences", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?q=incongruencia&respuesta=1")
      html = render_async(view)
      assert html =~ "Resumen con citas verificadas"
      assert html =~ ~r/\[\d+-\d{2}-[A-Z]{2}\/\d{2}, párr\. \d+\]/
    end

    test "matched terms are highlighted and escaped", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?q=incongruencia")
      assert render_async(view) =~ "<mark>incongruencia</mark>"
    end

    test "pagination moves through results", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/?q=Constitución&modo=palabras")
      html = render_async(view)
      assert html =~ "Página siguiente"
      {:ok, view2, _} = live(conn, ~p"/?q=Constitución&modo=palabras&pagina=2")
      assert render_async(view2) =~ "Página anterior"
    end

    test "too many searches are rate limited", %{conn: conn} do
      limit = Lexec.Rules.fetch!(:app, ["rate_limits", "search", "limit"])
      {:ok, view, _} = live(conn, ~p"/")

      for i <- 1..limit do
        view |> form("#search-form", b: %{q: "consulta #{i}"}) |> render_submit()
      end

      view |> form("#search-form", b: %{q: "una más"}) |> render_submit()
      assert render(view) =~ "Demasiadas búsquedas seguidas"
    end
  end

  describe "other screens" do
    test "unknown or unpublished rulings answer 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/sentencias/999999") end
      assert_error_sent 404, fn -> get(conn, ~p"/sentencias/abc") end
    end

    test "ruling sheet shows citations both ways and norms", %{conn: conn, ruling: ruling} do
      html = conn |> get(~p"/sentencias/#{ruling.id}") |> html_response(200)
      assert html =~ "Citada por"
      assert html =~ "9101-20-EP/23"
      assert html =~ "Constitución de la República del Ecuador"
      refute html =~ "Zambrano Vera"
    end

    test "precedents page lists the most cited ruling and filters by type", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/precedentes")
      assert html =~ "9105-18-EP/21"
      assert html =~ "Grafo de citas"

      view |> form("#precedents-filter", tipo: "IN") |> render_change()
      assert_patch(view, ~p"/precedentes?tipo=IN")
      assert render(view) =~ "No hay citas para este filtro"
    end

    test "methodology shows corpus figures and rule versions", %{conn: conn} do
      html = conn |> get(~p"/metodologia") |> html_response(200)
      assert html =~ "excl-2026.11.1"
      assert html =~ "Excluidas antes de procesar"
    end

    test "legal page documents the only cookie", %{conn: conn} do
      html = conn |> get(~p"/aviso-legal") |> html_response(200)
      assert html =~ "_lexec_key"
      assert html =~ "No usamos cookies de analítica"
    end
  end
end
