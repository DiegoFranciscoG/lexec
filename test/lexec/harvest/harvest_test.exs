defmodule Lexec.HarvestTest do
  # T-07 respectful harvesting and T-10 fault tolerance, against a local stub (never the network).
  use Lexec.DataCase, async: false

  alias Lexec.Catalog.{FetchedDocument, Ruling}
  alias Lexec.{Fixtures, Harvest, Spy}
  alias Lexec.Harvest.Robots

  @base "https://corte.test"

  setup do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)
    Robots.clear()
    Spy.reset()
    Spy.use_backends(index: Spy.Index)
    {:ok, log} = Agent.start_link(fn -> [] end)
    %{log: log}
  end

  defp pdf_for(case_number, paragraphs) do
    case_number
    |> then(&Fixtures.ruling_text(case_number: &1, paragraphs: paragraphs, per_page: 2))
    |> String.split("\f")
    |> Enum.map(&String.split(&1, "\n"))
    |> Fixtures.pdf()
  end

  # Serves robots.txt and PDFs, logging every request with a monotonic timestamp.
  defp stub_server(log, routes) do
    Req.Test.stub(Lexec.Harvest.Fetcher, fn conn ->
      Agent.update(
        log,
        &[
          {conn.request_path, System.monotonic_time(:millisecond),
           Plug.Conn.get_req_header(conn, "user-agent")}
          | &1
        ]
      )

      case Map.get(routes, conn.request_path) do
        nil -> Plug.Conn.send_resp(conn, 404, "not found")
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
        fun when is_function(fun, 1) -> fun.(conn)
      end
    end)
  end

  defp entries(paths), do: Enum.map(paths, &%{url: @base <> &1, flags: []})

  describe "T-07 respectful harvesting" do
    test "never more than one request per second, with a User-Agent that has a contact", %{
      log: log
    } do
      routes =
        for i <- 1..3, into: %{"/robots.txt" => {200, "User-agent: *\nDisallow: /privado/\n"}} do
          {"/s#{i}.pdf", {200, pdf_for("93#{i}0-22-EP/24", ["Contenido del párrafo #{i}."])}}
        end

      stub_server(log, routes)
      summary = Harvest.run(entries(["/s1.pdf", "/s2.pdf", "/s3.pdf"]))

      assert Enum.sort(Enum.map(summary.ok, &elem(&1, 1))) == [:published, :published, :published]

      requests = log |> Agent.get(& &1) |> Enum.reverse()
      assert length(requests) == 4

      times = Enum.map(requests, &elem(&1, 1))

      for [a, b] <- Enum.chunk_every(times, 2, 1, :discard) do
        assert b - a >= 990, "requests only #{b - a} ms apart"
      end

      for {_path, _t, [ua]} <- requests do
        assert ua == "LEXEC-bot/0.1 (+contacto@example.org)"
      end
    end

    test "respects robots.txt and records the refusal", %{log: log} do
      stub_server(log, %{
        "/robots.txt" =>
          {200, "User-agent: *\nDisallow: /privado/\nAllow: /privado/publico.pdf\n"},
        "/privado/publico.pdf" => {200, pdf_for("9340-22-EP/24", ["Texto permitido."])}
      })

      summary = Harvest.run(entries(["/privado/x.pdf", "/privado/publico.pdf"]))

      assert [{_, :disallowed_by_robots}] = summary.failed
      assert [{_, :published}] = summary.ok
      paths = log |> Agent.get(& &1) |> Enum.map(&elem(&1, 0))
      refute "/privado/x.pdf" in paths
    end

    test "never downloads the same URL or the same PDF twice", %{log: log} do
      pdf = pdf_for("9350-22-EP/24", ["Texto único."])

      stub_server(log, %{
        "/robots.txt" => {404, ""},
        "/a.pdf" => {200, pdf},
        "/copia.pdf" => {200, pdf}
      })

      first = Harvest.run(entries(["/a.pdf"]))
      assert [{_, :published}] = first.ok

      second = Harvest.run(entries(["/a.pdf", "/copia.pdf"]))
      assert Enum.sort(Enum.map(second.ok, &elem(&1, 1))) == [:cached, :duplicate]

      a_downloads = log |> Agent.get(& &1) |> Enum.count(&(elem(&1, 0) == "/a.pdf"))
      assert a_downloads == 1
      assert Repo.aggregate(Ruling, :count) == 1
    end

    test "a 5xx robots.txt means nothing may be fetched", %{log: log} do
      stub_server(log, %{"/robots.txt" => {503, "down"}})
      summary = Harvest.run(entries(["/s.pdf"]))
      assert [{_, :disallowed_by_robots}] = summary.failed
    end
  end

  describe "T-10 one broken document does not stop the pipeline" do
    test "corrupt PDF, HTTP error and exception are logged; the rest is processed", %{log: log} do
      stub_server(log, %{
        "/robots.txt" => {404, ""},
        "/ok1.pdf" => {200, pdf_for("9361-22-EP/24", ["Primer documento válido."])},
        "/roto.pdf" => {200, "%PDF-1.4 esto no es un PDF válido"},
        "/html.pdf" => {200, "<html>error</html>"},
        "/caido.pdf" => {404, "no"},
        "/ok2.pdf" => {200, pdf_for("9362-22-EP/24", ["Segundo documento válido."])}
      })

      summary =
        Harvest.run(entries(["/ok1.pdf", "/roto.pdf", "/html.pdf", "/caido.pdf", "/ok2.pdf"]))

      assert Enum.sort(Enum.map(summary.ok, &elem(&1, 0))) == [
               @base <> "/ok1.pdf",
               @base <> "/ok2.pdf"
             ]

      failed = Map.new(summary.failed)
      assert failed[@base <> "/html.pdf"] == :not_a_pdf
      assert failed[@base <> "/caido.pdf"] == {:http, 404}
      assert Map.has_key?(failed, @base <> "/roto.pdf")

      assert Repo.get_by!(FetchedDocument, url: @base <> "/caido.pdf").status == "failed"
      assert Repo.aggregate(Ruling, :count) == 2
    end

    test "transient errors are retried with backoff", %{log: log} do
      {:ok, attempts} = Agent.start_link(fn -> 0 end)
      pdf = pdf_for("9370-22-EP/24", ["Llega al tercer intento."])

      stub_server(log, %{
        "/robots.txt" => {404, ""},
        "/lento.pdf" => fn conn ->
          n = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})

          if n < 3,
            do: Plug.Conn.send_resp(conn, 503, "busy"),
            else: Plug.Conn.send_resp(conn, 200, pdf)
        end
      })

      assert %{ok: [{_, :published}]} = Harvest.run(entries(["/lento.pdf"]))
      assert Agent.get(attempts, & &1) == 3
    end

    test "redirects are followed through the throttle", %{log: log} do
      stub_server(log, %{
        "/robots.txt" => {404, ""},
        "/viejo.pdf" => fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "/nuevo.pdf")
          |> Plug.Conn.send_resp(301, "")
        end,
        "/nuevo.pdf" => {200, pdf_for("9380-22-EP/24", ["Movido."])}
      })

      assert %{ok: [{_, :published}]} = Harvest.run(entries(["/viejo.pdf"]))
    end

    test "invalid URLs fail fast" do
      assert %{failed: [{"ftp://x/y.pdf", :invalid_url}]} =
               Harvest.run([%{url: "ftp://x/y.pdf", flags: []}])
    end
  end

  describe "manifest" do
    @describetag :tmp_dir

    test "loads JSON entries", %{tmp_dir: dir} do
      path = Path.join(dir, "m.json")
      File.write!(path, ~s([{"url": "https://a.test/1.pdf", "flags": ["minors"]}]))

      assert {:ok, [%{url: "https://a.test/1.pdf", flags: ["minors"], case_number: nil}]} =
               Harvest.load_manifest(path)

      File.write!(path, ~s({"url": 1}))
      assert {:error, :manifest_must_be_a_list} = Harvest.load_manifest(path)
    end
  end
end
