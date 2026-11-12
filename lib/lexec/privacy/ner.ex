defmodule Lexec.Privacy.Ner do
  @moduledoc """
  Named-entity recognition used to find person names the rules missed.

  The backend is chosen with `config :lexec, :ner` (`Lexec.Privacy.Ner.Null`
  or `Lexec.Privacy.Ner.Bumblebee`). Only already-cleared (non excluded) text
  ever reaches it.
  """

  @type entity :: %{label: String.t(), phrase: String.t(), score: float()}

  @callback entities([String.t()]) :: [[entity()]]
  @callback model_name() :: String.t() | nil

  @spec backend() :: module()
  def backend, do: Application.fetch_env!(:lexec, :ner)

  @doc "Entities for each text, in order."
  @spec entities([String.t()]) :: [[entity()]]
  def entities(texts) when is_list(texts), do: backend().entities(texts)

  @spec model_name() :: String.t() | nil
  def model_name, do: backend().model_name()
end

defmodule Lexec.Privacy.Ner.Null do
  @moduledoc "No NER: anonymization relies on the deterministic rules only."
  @behaviour Lexec.Privacy.Ner

  @impl true
  def entities(texts), do: Enum.map(texts, fn _ -> [] end)

  @impl true
  def model_name, do: nil
end
