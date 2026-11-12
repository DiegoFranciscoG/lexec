defmodule Lexec.Spy do
  @moduledoc "Records every call made to a fake backend so tests can assert what reached a model."
  use Agent

  def start_link(_opts \\ []), do: Agent.start_link(fn -> [] end, name: __MODULE__)

  def record(kind, payload) do
    if Process.whereis(__MODULE__), do: Agent.update(__MODULE__, &[{kind, payload} | &1])
    :ok
  end

  def reset, do: Agent.update(__MODULE__, fn _ -> [] end)

  def calls(kind) do
    __MODULE__
    |> Agent.get(&Enum.reverse/1)
    |> Enum.filter(fn {k, _} -> k == kind end)
    |> Enum.map(&elem(&1, 1))
  end

  def all_text do
    __MODULE__
    |> Agent.get(& &1)
    |> Enum.map_join("\n", fn {_k, payload} ->
      inspect(payload, limit: :infinity, printable_limit: :infinity)
    end)
  end

  @doc "Swaps backends for the duration of a test and restores them afterwards."
  def use_backends(backends) do
    previous = Enum.map(backends, fn {key, _} -> {key, Application.get_env(:lexec, key)} end)
    Enum.each(backends, fn {key, mod} -> Application.put_env(:lexec, key, mod) end)

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(previous, fn {key, mod} -> Application.put_env(:lexec, key, mod) end)
    end)
  end
end

defmodule Lexec.Spy.Ner do
  @moduledoc "NER double: records inputs; tags configured names as PER."
  @behaviour Lexec.Privacy.Ner

  @impl true
  def entities(texts) do
    Lexec.Spy.record(:ner, texts)
    names = Application.get_env(:lexec, :spy_ner_names, [])

    Enum.map(texts, fn text ->
      names
      |> Enum.filter(fn {name, _score} -> String.contains?(text, name) end)
      |> Enum.map(fn {name, score} -> %{label: "PER", phrase: name, score: score} end)
    end)
  end

  @impl true
  def model_name, do: "spy-ner"
end

defmodule Lexec.Spy.Embeddings do
  @moduledoc "Embedding double: records inputs; returns a tiny deterministic vector."
  @behaviour Lexec.Embeddings

  @impl true
  def embed(texts) do
    Lexec.Spy.record(:embeddings, texts)
    Enum.map(texts, fn text -> [rem(:erlang.phash2(text), 100) / 100, 0.5, 0.25] end)
  end

  @impl true
  def dimensions, do: 3

  @impl true
  def model_name, do: "spy-embeddings"
end

defmodule Lexec.Spy.Index do
  @moduledoc "Index double: records documents and deletions, searches via the SQL backend."
  @behaviour Lexec.Index

  alias Lexec.Index.Sql

  @impl true
  def setup, do: :ok

  @impl true
  def upsert(docs) do
    Lexec.Spy.record(:index_upsert, docs)
    :ok
  end

  @impl true
  def delete_ruling(id) do
    Lexec.Spy.record(:index_delete, id)
    :ok
  end

  @impl true
  def reset, do: :ok

  @impl true
  def search(query, opts), do: Sql.search(query, opts)
end
