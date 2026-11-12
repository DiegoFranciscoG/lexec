defmodule Lexec.Models do
  @moduledoc """
  Loads the local Hugging Face models with Bumblebee and starts their
  `Nx.Serving`s. Model ids and revisions are pinned in config.
  """

  @doc "Children to add to the supervision tree for the configured backends."
  @spec children() :: [Supervisor.child_spec()]
  def children do
    embeddings =
      if Application.fetch_env!(:lexec, :embeddings) == Lexec.Embeddings.Bumblebee,
        do: [
          {Nx.Serving,
           serving: embedding_serving(), name: Lexec.EmbeddingServing, batch_timeout: 50}
        ],
        else: []

    ner =
      if Application.fetch_env!(:lexec, :ner) == Lexec.Privacy.Ner.Bumblebee,
        do: [{Nx.Serving, serving: ner_serving(), name: Lexec.NerServing, batch_timeout: 50}],
        else: []

    embeddings ++ ner
  end

  @doc false
  def embedding_serving do
    config = Application.fetch_env!(:lexec, :embedding_model)
    repo = {:hf, config[:repo], revision: config[:revision]}

    {:ok, model_info} = Bumblebee.load_model(repo)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)

    Bumblebee.Text.text_embedding(model_info, tokenizer,
      output_pool: :mean_pooling,
      output_attribute: :hidden_state,
      embedding_processor: :l2_norm,
      compile: [batch_size: config[:batch_size], sequence_length: config[:sequence_length]],
      defn_options: [compiler: EXLA]
    )
  end

  @doc false
  def ner_serving do
    config = Application.fetch_env!(:lexec, :ner_model)

    {:ok, model_info} = Bumblebee.load_model({:hf, config[:repo], revision: config[:revision]})

    {:ok, tokenizer} =
      Bumblebee.load_tokenizer(
        {:hf, config[:vocabulary_repo], revision: config[:vocabulary_revision]}
      )

    Bumblebee.Text.token_classification(model_info, tokenizer,
      aggregation: :same,
      compile: [batch_size: config[:batch_size], sequence_length: config[:sequence_length]],
      defn_options: [compiler: EXLA]
    )
  end
end

defmodule Lexec.Embeddings.Bumblebee do
  @moduledoc "multilingual-e5-small served by `Nx.Serving` (384 dimensions)."
  @behaviour Lexec.Embeddings

  @impl true
  def embed([]), do: []

  def embed(texts) do
    Lexec.EmbeddingServing
    |> Nx.Serving.batched_run(texts)
    |> Enum.map(fn %{embedding: tensor} -> Nx.to_flat_list(tensor) end)
  end

  @impl true
  def dimensions, do: Application.fetch_env!(:lexec, :embedding_model)[:dimensions]

  @impl true
  def model_name, do: Application.fetch_env!(:lexec, :embedding_model)[:repo]
end

defmodule Lexec.Privacy.Ner.Bumblebee do
  @moduledoc "Multilingual BERT NER served by `Nx.Serving`. Texts are chunked by sentence."
  @behaviour Lexec.Privacy.Ner

  @max_chunk 900

  @impl true
  def entities(texts) do
    Enum.map(texts, fn text ->
      text
      |> chunks()
      |> case do
        [] ->
          []

        chunks ->
          Lexec.NerServing
          |> Nx.Serving.batched_run(chunks)
          |> Enum.flat_map(fn %{entities: entities} ->
            Enum.map(entities, &%{label: &1.label, phrase: &1.phrase, score: &1.score})
          end)
      end
    end)
  end

  @impl true
  def model_name, do: Application.fetch_env!(:lexec, :ner_model)[:repo]

  defp chunks(text) do
    text
    |> String.split(~r/(?<=[.;:])\s+/u, trim: true)
    |> Enum.chunk_while(
      "",
      fn sentence, acc ->
        candidate = if acc == "", do: sentence, else: acc <> " " <> sentence

        if String.length(candidate) > @max_chunk and acc != "",
          do: {:cont, acc, sentence},
          else: {:cont, candidate}
      end,
      fn
        "" -> {:cont, ""}
        acc -> {:cont, acc, ""}
      end
    )
    |> Enum.reject(&(&1 == ""))
  end
end
