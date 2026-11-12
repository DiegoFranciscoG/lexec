defmodule Lexec.Extract.Document do
  @moduledoc """
  A ruling parsed from extracted text, before privacy processing.

  `paragraphs` still contain the original text: this struct must never be
  persisted or sent to a model until it has passed exclusion and anonymization.
  """

  @type paragraph :: %{number: pos_integer(), text: String.t()}

  @type t :: %__MODULE__{
          case_number: String.t() | nil,
          case_file: String.t() | nil,
          action_type: String.t() | nil,
          ruling_year: integer() | nil,
          decided_on: Date.t() | nil,
          rapporteur: String.t() | nil,
          decision: String.t(),
          preamble: String.t(),
          paragraphs: [paragraph()]
        }

  defstruct case_number: nil,
            case_file: nil,
            action_type: nil,
            ruling_year: nil,
            decided_on: nil,
            rapporteur: nil,
            decision: "other",
            preamble: "",
            paragraphs: []
end
