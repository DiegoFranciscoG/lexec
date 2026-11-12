defmodule LexecWeb.PrecedentsLive do
  @moduledoc """
  Precedent network: most cited rulings, most invoked articles per action
  type, and the citation graph (drawn server-side as SVG, with the tables as
  its text alternative).
  """
  use LexecWeb, :live_view

  alias Lexec.{Catalog, Relations, Rules}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Red de precedentes")
     |> assign(:types, Rules.fetch!(:action_types, ["types"]))
     |> assign(:available, Catalog.filter_options().action_types)
     |> assign(:graph, layout(Catalog.precedent_graph()))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    type = if params["tipo"] in socket.assigns.available, do: params["tipo"]

    {:noreply,
     socket
     |> assign(:type, type)
     |> assign(:most_cited, Catalog.most_cited(action_type: type))
     |> assign(:norms, Catalog.top_norms(action_type: type))}
  end

  @impl true
  def handle_event("filter", %{"tipo" => type}, socket) do
    params = if type == "", do: %{}, else: %{tipo: type}
    {:noreply, push_patch(socket, to: ~p"/precedentes?#{params}")}
  end

  # Nodes on a circle; rulings cited at least twice are hubs.
  defp layout(%{nodes: nodes, edges: edges}) do
    n = max(length(nodes), 1)
    {cx, cy, r} = {400, 280, 220}

    indegree = Enum.frequencies(Enum.map(edges, & &1.to))

    positioned =
      nodes
      |> Enum.with_index()
      |> Map.new(fn {node, i} ->
        angle = 2 * :math.pi() * i / n - :math.pi() / 2

        {node.id,
         Map.merge(node, %{
           x: Float.round(cx + r * :math.cos(angle), 1),
           y: Float.round(cy + r * :math.sin(angle), 1),
           hub?: Map.get(indegree, node.id, 0) >= 2,
           label_anchor: if(:math.cos(angle) < -0.1, do: "end", else: "start"),
           lx: Float.round(cx + (r + 14) * :math.cos(angle), 1),
           ly: Float.round(cy + (r + 14) * :math.sin(angle) + 4, 1)
         })}
      end)

    %{
      nodes: Map.values(positioned),
      edges: Enum.map(edges, &arrow(positioned[&1.from], positioned[&1.to])),
      count: length(nodes)
    }
  end

  # Edge from citing to cited ruling, stopped short of the target circle so the arrowhead shows.
  defp arrow(from, to) do
    {dx, dy} = {to.x - from.x, to.y - from.y}
    len = max(:math.sqrt(dx * dx + dy * dy), 1.0)
    gap = if to.hub?, do: 13, else: 10

    %{
      x1: from.x,
      y1: from.y,
      x2: Float.round(to.x - dx / len * gap, 1),
      y2: Float.round(to.y - dy / len * gap, 1)
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:precedents}>
      <div class="page-head">
        <h1>Red de precedentes</h1>
        <p>
          Qué sentencias citan a cuáles y qué artículos se invocan más, calculado a partir de las propias sentencias publicadas.
        </p>
      </div>

      <form
        id="precedents-filter"
        phx-change="filter"
        class="field filter-form"
        action="/precedentes"
        method="get"
      >
        <label for="tipo">Tipo de acción de las sentencias que citan</label>
        <select id="tipo" name="tipo" class="select">
          {Phoenix.HTML.Form.options_for_select(
            [{"Todos", ""} | Enum.map(@available, &{"#{&1} · #{@types[&1]}", &1})],
            @type || ""
          )}
        </select>
      </form>

      <div class="grid-2">
        <div class="table-wrap">
          <table class="table">
            <caption>Sentencias más citadas</caption>
            <thead>
              <tr>
                <th scope="col">Sentencia</th><th scope="col">Tipo</th><th scope="col" class="num">
                  Citada por
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@most_cited == []}>
                <td colspan="3">No hay citas para este filtro.</td>
              </tr>
              <tr :for={row <- @most_cited}>
                <td>
                  <a :if={row.ruling_id} class="link mono" href={~p"/sentencias/#{row.ruling_id}"}>{row.case_number}</a>
                  <span :if={!row.ruling_id} class="mono">{row.case_number}</span>
                </td>
                <td>{row.action_type || "fuera del corpus"}</td>
                <td class="num">{row.citations}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="table-wrap">
          <table class="table">
            <caption>Artículos más invocados</caption>
            <thead>
              <tr>
                <th scope="col">Artículo</th><th scope="col">Tipo</th><th scope="col" class="num">
                  Sentencias
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :if={@norms == []}>
                <td colspan="3">No hay normas para este filtro.</td>
              </tr>
              <tr :for={row <- @norms}>
                <td>
                  Art. <span class="mono">{row.article}</span>
                  <abbr title={Relations.body_name(row.norm_body)}>{row.norm_body}</abbr>
                </td>
                <td>{row.action_type}</td>
                <td class="num">{row.rulings}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <section class="graph" aria-labelledby="graph-title">
        <h2 id="graph-title">Grafo de citas</h2>
        <p :if={@graph.count == 0} class="hint">Aún no hay citas entre sentencias publicadas.</p>
        <svg
          :if={@graph.count > 0}
          viewBox="0 0 800 560"
          role="img"
          aria-labelledby="graph-svg-title graph-svg-desc"
        >
          <title id="graph-svg-title">Grafo de citas entre sentencias</title>
          <desc id="graph-svg-desc">
            {@graph.count} sentencias conectadas por sus citas. Cada flecha va de la sentencia que cita a la citada. Las sentencias en burdeos son citadas por dos o más. La tabla de sentencias más citadas contiene la misma información.
          </desc>
          <defs>
            <marker
              id="arrow"
              viewBox="0 0 10 10"
              refX="9"
              refY="5"
              markerWidth="7"
              markerHeight="7"
              orient="auto-start-reverse"
            >
              <path class="arrowhead" d="M0 0 10 5 0 10z" />
            </marker>
          </defs>
          <line
            :for={e <- @graph.edges}
            class="edge"
            x1={e.x1}
            y1={e.y1}
            x2={e.x2}
            y2={e.y2}
            marker-end="url(#arrow)"
          />
          <a
            :for={node <- @graph.nodes}
            href={~p"/sentencias/#{node.id}"}
            class={["node", node.hub? && "node--hub"]}
          >
            <circle cx={node.x} cy={node.y} r={if node.hub?, do: 9, else: 6} />
            <text x={node.lx} y={node.ly} text-anchor={node.label_anchor}>{node.case_number}</text>
          </a>
        </svg>
      </section>
    </Layouts.app>
    """
  end
end
