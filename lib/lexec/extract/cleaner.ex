defmodule Lexec.Extract.Cleaner do
  @moduledoc """
  Removes page headers, footers and page numbers from `pdftotext` output.

  Pages are separated by form feeds (`\\f`). A line is noise when it matches a
  pattern in `segmentation.yaml` or when it repeats on many pages.
  """

  alias Lexec.Rules

  @doc "Returns clean lines (pages joined, noise removed)."
  @spec clean(String.t()) :: [String.t()]
  def clean(text) when is_binary(text) do
    pages =
      text
      |> String.replace("\r\n", "\n")
      |> String.split("\f")
      |> Enum.map(&String.split(&1, "\n"))

    repeated = repeated_lines(pages)
    noise = noise_patterns()

    pages
    |> List.flatten()
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(fn line ->
      key = normalize(line)
      key != "" and (MapSet.member?(repeated, key) or Enum.any?(noise, &Regex.match?(&1, line)))
    end)
  end

  defp repeated_lines(pages) do
    min_pages = Rules.fetch!(:segmentation, ["repeated_line_min_pages"])

    if length(pages) < min_pages do
      MapSet.new()
    else
      pages
      |> Enum.flat_map(fn lines -> lines |> Enum.map(&normalize/1) |> Enum.uniq() end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.frequencies()
      |> Enum.filter(fn {_line, count} -> count >= min_pages end)
      |> MapSet.new(fn {line, _} -> line end)
    end
  end

  defp noise_patterns do
    Rules.memo(:cleaner_noise, fn ->
      :segmentation
      |> Rules.fetch!(["noise_lines"])
      |> Enum.map(&Rules.regex!/1)
    end)
  end

  defp normalize(line), do: line |> String.trim() |> String.replace(~r/\s+/u, " ")
end
