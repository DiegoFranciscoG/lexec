defmodule Lexec.Fixtures do
  @moduledoc "Synthetic test data. Every name, ID and case number here is fictitious."

  @corpus_dir Path.expand("../../priv/seeds/corpus", __DIR__)
  @fixtures_dir Path.expand("../fixtures", __DIR__)

  def corpus_dir, do: @corpus_dir
  def fixtures_dir, do: @fixtures_dir

  def corpus_manifest do
    Path.join(@corpus_dir, "manifest.json") |> File.read!() |> Jason.decode!()
  end

  def corpus_text(file), do: File.read!(Path.join(@corpus_dir, file))

  def json_fixture(name), do: Path.join(@fixtures_dir, name) |> File.read!() |> Jason.decode!()

  @doc """
  Renders paragraphs the way `pdftotext` prints a ruling: preamble, repeated
  header and footer on every page, page numbers, headings and a decision
  list that restarts numbering.
  """
  def ruling_text(opts \\ []) do
    number = Keyword.get(opts, :case_number, "9301-22-EP/24")
    paragraphs = Keyword.get(opts, :paragraphs, ["Primer párrafo de prueba.", "Segundo párrafo."])
    per_page = Keyword.get(opts, :per_page, 3)
    judge = Keyword.get(opts, :judge, "Alba Ruiz Andrade")

    preamble = [
      "CORTE CONSTITUCIONAL DEL ECUADOR",
      "Quito, D.M., 3 de mayo de 2024",
      "CASO No. #{number |> String.split("/") |> hd()}",
      "Sentencia No. #{number}",
      "Jueza ponente: #{judge}",
      ""
    ]

    body =
      paragraphs
      |> Enum.with_index(1)
      |> Enum.map(fn {text, n} ->
        heading = if rem(n, 4) == 1, do: ["#{roman(div(n, 4) + 1)}. Sección #{n}"], else: []
        heading ++ wrap("#{n}. #{text}")
      end)
      |> Enum.chunk_every(per_page)
      |> Enum.map(&List.flatten/1)

    pages = List.update_at(body, 0, &(preamble ++ &1))
    pages = List.update_at(pages, -1, &(&1 ++ decision()))
    total = length(pages)

    pages
    |> Enum.with_index(1)
    |> Enum.map(fn {lines, page} ->
      header = if page > 1, do: ["CORTE CONSTITUCIONAL DEL ECUADOR"], else: []
      Enum.join(header ++ lines ++ ["", "www.corteconstitucional.gob.ec", "Página #{page} de #{total}"], "\n")
    end)
    |> Enum.join("\n\f")
  end

  defp decision do
    [
      "IV. Decisión",
      "En mérito de lo expuesto, la Corte Constitucional resuelve:",
      "1. Aceptar la acción extraordinaria de protección.",
      "2. Notifíquese y archívese."
    ]
  end

  defp wrap(text) do
    text
    |> String.split(" ")
    |> Enum.chunk_while(
      "",
      fn word, acc ->
        candidate = String.trim(acc <> " " <> word)
        if String.length(candidate) > 80 and acc != "", do: {:cont, acc, word}, else: {:cont, candidate}
      end,
      fn acc -> {:cont, acc, ""} end
    )
  end

  defp roman(n), do: Enum.at(~w(I II III IV V VI VII VIII IX X XI XII XIII XIV XV), n - 1, "XX")

  @doc """
  Minimal valid PDF (Helvetica, WinAnsi) with one line of text per entry and
  one page per list of lines. Good enough for `pdftotext`.
  """
  def pdf(pages) when is_list(pages) do
    page_count = length(pages)
    font_id = 3 + page_count * 2

    page_objs =
      pages
      |> Enum.with_index()
      |> Enum.flat_map(fn {lines, i} ->
        page_id = 3 + i * 2
        content_id = page_id + 1

        stream =
          ["BT /F1 11 Tf 50 780 Td 14 TL"] ++
            Enum.map(lines, fn line -> "(#{escape(line)}) Tj T*" end) ++ ["ET"]

        stream = Enum.join(stream, "\n")

        [
          {page_id,
           "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents #{content_id} 0 R /Resources << /Font << /F1 #{font_id} 0 R >> >> >>"},
          {content_id, "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream"}
        ]
      end)

    kids = Enum.map_join(0..(page_count - 1), " ", fn i -> "#{3 + i * 2} 0 R" end)

    objects =
      [
        {1, "<< /Type /Catalog /Pages 2 0 R >>"},
        {2, "<< /Type /Pages /Kids [#{kids}] /Count #{page_count} >>"}
      ] ++
        page_objs ++
        [{font_id, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"}]

    header = "%PDF-1.4\n"

    {body, offsets} =
      Enum.reduce(objects, {header, []}, fn {id, content}, {acc, offs} ->
        {acc <> "#{id} 0 obj\n#{content}\nendobj\n", [{id, byte_size(acc)} | offs]}
      end)

    xref_at = byte_size(body)
    count = length(objects) + 1

    xref =
      offsets
      |> Enum.sort()
      |> Enum.map_join("", fn {_id, off} -> String.pad_leading("#{off}", 10, "0") <> " 00000 n \n" end)

    body <>
      "xref\n0 #{count}\n0000000000 65535 f \n" <>
      xref <> "trailer\n<< /Size #{count} /Root 1 0 R >>\nstartxref\n#{xref_at}\n%%EOF\n"
  end

  # PDF literal strings in WinAnsi (Latin-1 for Spanish accents), with escapes.
  defp escape(line) do
    line
    |> :unicode.characters_to_binary(:utf8, :latin1)
    |> :binary.bin_to_list()
    |> Enum.map_join(fn
      ?( -> "\\("
      ?) -> "\\)"
      ?\\ -> "\\\\"
      c when c > 126 -> "\\" <> String.pad_leading(Integer.to_string(c, 8), 3, "0")
      c -> <<c>>
    end)
  end
end
