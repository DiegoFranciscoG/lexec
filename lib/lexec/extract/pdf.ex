defmodule Lexec.Extract.Pdf do
  @moduledoc """
  Extracts text from a PDF with poppler's `pdftotext` (reading order kept,
  pages separated by form feeds). Runs without a shell; the path is passed as
  an argument, never interpolated.
  """

  @spec to_text(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def to_text(path) when is_binary(path) do
    with {:ok, exe} <- executable(),
         true <- File.regular?(path) || {:error, :enoent},
         {:ok, header} <- read_header(path),
         true <- header == "%PDF-" || {:error, :not_a_pdf} do
      case System.cmd(exe, ["-q", "-enc", "UTF-8", "-eol", "unix", path, "-"]) do
        {text, 0} -> {:ok, text}
        {_out, status} -> {:error, {:pdftotext_failed, status}}
      end
    end
  end

  @doc "True when the binary starts with the PDF magic bytes."
  @spec pdf?(binary()) :: boolean()
  def pdf?(<<"%PDF-", _::binary>>), do: true
  def pdf?(_), do: false

  defp read_header(path) do
    File.open(path, [:read, :binary], fn file -> IO.binread(file, 5) end)
    |> case do
      {:ok, header} when is_binary(header) -> {:ok, header}
      {:ok, _} -> {:error, :not_a_pdf}
      error -> error
    end
  end

  defp executable do
    case System.find_executable("pdftotext") do
      nil -> {:error, :pdftotext_not_installed}
      exe -> {:ok, exe}
    end
  end
end
