defmodule LexecWeb.PageController do
  use LexecWeb, :controller

  alias Lexec.{Catalog, Embeddings, Rules}
  alias Lexec.Privacy.Ner

  def methodology(conn, _params) do
    render(conn, :methodology,
      page_title: "Metodología",
      stats: Catalog.stats(),
      versions: %{
        exclusion: Rules.version(:exclusion),
        anonymization: Rules.version(:anonymization),
        segmentation: Rules.version(:segmentation),
        relations: Rules.version(:relations)
      },
      response_days: Rules.fetch!(:app, ["corrections", "response_days"]),
      embedding_model: Embeddings.backend().model_name(),
      ner_model: Ner.model_name()
    )
  end

  def legal(conn, _params) do
    render(conn, :legal,
      page_title: "Aviso legal, privacidad y cookies",
      response_days: Rules.fetch!(:app, ["corrections", "response_days"])
    )
  end
end
