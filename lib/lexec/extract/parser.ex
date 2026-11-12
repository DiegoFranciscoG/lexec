defmodule Lexec.Extract.Parser do
  @moduledoc "Turns extracted text into a `Lexec.Extract.Document` (regex only, no models)."

  alias Lexec.Extract.{Cleaner, Document, Metadata, Segmenter}

  @spec parse(String.t()) :: Document.t()
  def parse(text) when is_binary(text) do
    lines = Cleaner.clean(text)
    %{preamble: preamble, paragraphs: paragraphs} = Segmenter.segment(lines)
    meta = Metadata.extract(preamble, Enum.join(lines, "\n"))

    struct!(Document, Map.merge(meta, %{preamble: preamble, paragraphs: paragraphs}))
  end
end
