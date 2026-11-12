defmodule Lexec.Embeddings do
  @moduledoc """
  Text embeddings for the semantic half of hybrid search.

  Backend from `config :lexec, :embeddings`: `Lexec.Embeddings.Null` (keyword
  search only) or `Lexec.Embeddings.Bumblebee` (multilingual-e5-small, local).
  e5 models expect the `passage: ` / `query: ` prefixes.
  """

  @callback embed([String.t()]) :: [[float()]]
  @callback dimensions() :: pos_integer() | nil
  @callback model_name() :: String.t() | nil

  @spec backend() :: module()
  def backend, do: Application.fetch_env!(:lexec, :embeddings)

  @doc "True when a semantic backend is configured."
  @spec enabled?() :: boolean()
  def enabled?, do: backend().dimensions() != nil

  @spec dimensions() :: pos_integer() | nil
  def dimensions, do: backend().dimensions()

  @spec embed_passages([String.t()]) :: [[float()]] | nil
  def embed_passages(texts) do
    if enabled?(), do: backend().embed(Enum.map(texts, &("passage: " <> &1)))
  end

  @spec embed_query(String.t()) :: [float()] | nil
  def embed_query(text) do
    if enabled?(), do: hd(backend().embed(["query: " <> text]))
  end
end

defmodule Lexec.Embeddings.Null do
  @moduledoc "No embeddings: search falls back to keywords."
  @behaviour Lexec.Embeddings

  @impl true
  def embed(texts), do: Enum.map(texts, fn _ -> [] end)

  @impl true
  def dimensions, do: nil

  @impl true
  def model_name, do: nil
end
