defmodule LexecWeb.SearchLive do
  @moduledoc """
  Paragraph-level search. All state lives in the URL (query, filters, mode,
  page, answer mode). Every result shows the case number, paragraph number,
  date, action type, the "not legal advice" notice and the official link.
  """
  use LexecWeb, :live_view

  alias Lexec.{Answer, Catalog, Embeddings, Index, RateLimiter, Rules}
  alias LexecWeb.Highlight

  @modes %{"hibrida" => :hybrid, "palabras" => :keywords}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Buscar jurisprudencia")
     |> assign(:options, Catalog.filter_options())
     |> assign(:types, Rules.fetch!(:action_types, ["types"]))
     |> assign(:semantic?, Embeddings.enabled?())
     |> assign(:page_size, Rules.fetch!(:app, ["search", "page_size"]))
     |> assign(:state, :idle)
     |> assign(:hits, [])
     |> assign(:total, 0)
     |> assign(:answer, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # A plain GET form (no JavaScript) submits the fields nested under "b".
    params =
      case params do
        %{"b" => %{} = nested} -> Map.merge(Map.delete(params, "b"), nested)
        _ -> params
      end

    criteria = criteria(params, socket.assigns)
    socket = assign(socket, criteria: criteria, form: to_form(form_params(criteria), as: :b))

    cond do
      criteria.query == "" ->
        {:noreply, assign(socket, state: :idle, hits: [], total: 0, answer: nil)}

      criteria.error ->
        {:noreply, assign(socket, state: {:invalid, criteria.error}, hits: [], answer: nil)}

      not rate_ok?(socket) ->
        {:noreply, assign(socket, state: :rate_limited, hits: [], answer: nil)}

      connected?(socket) ->
        {:noreply,
         socket
         |> assign(state: :loading)
         |> start_async(:search, fn -> run(criteria) end)}

      true ->
        {:noreply, apply_result(socket, run(criteria))}
    end
  end

  @impl true
  def handle_event("search", %{"b" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{query_string(params)}")}
  end

  @impl true
  def handle_async(:search, {:ok, result}, socket), do: {:noreply, apply_result(socket, result)}

  def handle_async(:search, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, state: :error)}

  defp apply_result(socket, {:ok, %{hits: hits, total: total}, answer}),
    do: assign(socket, state: :ok, hits: hits, total: total, answer: answer)

  defp apply_result(socket, {:error, _reason}),
    do: assign(socket, state: :error, hits: [], answer: nil)

  defp run(criteria) do
    page_size = Rules.fetch!(:app, ["search", "page_size"])

    opts = [
      filters: criteria.filters,
      semantic_ratio:
        if(criteria.mode == :hybrid,
          do: Rules.fetch!(:app, ["search", "default_semantic_ratio"]),
          else: 0.0
        ),
      limit: page_size,
      offset: (criteria.page - 1) * page_size
    ]

    case Index.search(criteria.query, opts) do
      {:ok, result} ->
        answer = if criteria.answer?, do: Answer.answer(criteria.query, result.hits)
        {:ok, result, answer}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rate_ok?(%{assigns: %{client_ip: :dead_render}}), do: true
  defp rate_ok?(socket), do: RateLimiter.hit("search", socket.assigns.client_ip) == :ok

  # -- URL params <-> criteria (whitelisted and bounded) ------------------------

  defp criteria(params, assigns) do
    search = Rules.fetch!(:app, ["search"])
    query = params |> Map.get("q", "") |> to_string() |> String.trim()
    years = Map.new(assigns.options.years, &{Integer.to_string(&1), &1})

    filters =
      %{
        action_type: Map.has_key?(assigns.types, params["tipo"]) && params["tipo"],
        year_from: Map.get(years, params["desde"]),
        year_to: Map.get(years, params["hasta"]),
        rapporteur: params["ponente"] in assigns.options.rapporteurs && params["ponente"]
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, false] end)
      |> Map.new()

    mode =
      case Map.get(@modes, params["modo"]) do
        nil -> if assigns.semantic?, do: :hybrid, else: :keywords
        :hybrid -> if assigns.semantic?, do: :hybrid, else: :keywords
        other -> other
      end

    error =
      cond do
        query != "" and String.length(query) < search["min_query_length"] ->
          "Escriba al menos #{search["min_query_length"]} caracteres."

        String.length(query) > search["max_query_length"] ->
          "La consulta admite como máximo #{search["max_query_length"]} caracteres."

        true ->
          nil
      end

    %{
      query: query,
      filters: filters,
      mode: mode,
      answer?: params["respuesta"] == "1",
      page: parse_page(params["pagina"]),
      error: error
    }
  end

  defp parse_page(value) do
    case Integer.parse(to_string(value)) do
      {n, ""} when n >= 1 and n <= 100 -> n
      _ -> 1
    end
  end

  defp form_params(c) do
    %{
      "q" => c.query,
      "tipo" => c.filters[:action_type],
      "desde" => c.filters[:year_from] && Integer.to_string(c.filters[:year_from]),
      "hasta" => c.filters[:year_to] && Integer.to_string(c.filters[:year_to]),
      "ponente" => c.filters[:rapporteur],
      "modo" => if(c.mode == :hybrid, do: "hibrida", else: "palabras"),
      "respuesta" => if(c.answer?, do: "1", else: "0")
    }
  end

  defp query_string(params) do
    params
    |> Map.take(~w(q tipo desde hasta ponente modo respuesta pagina))
    |> Enum.reject(fn {_k, v} -> v in [nil, "", "0"] end)
    |> Map.new()
  end

  defp page_link(criteria, page),
    do:
      ~p"/?#{criteria |> form_params() |> Map.put("pagina", Integer.to_string(page)) |> query_string()}"

  # -- render ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:search}>
      <div class="page-head">
        <h1>Buscar en la jurisprudencia constitucional</h1>
        <p>
          Cada resultado es un párrafo de una sentencia, con su número de caso y el enlace al documento oficial.
        </p>
      </div>

      <.form
        for={@form}
        id="search-form"
        class="search"
        role="search"
        phx-submit="search"
        action={~p"/"}
        method="get"
      >
        <div class="search__row">
          <div class="field">
            <label for="b_q">Qué busca</label>
            <input
              id="b_q"
              name="b[q]"
              type="search"
              class="input search__query"
              value={@form[:q].value}
              maxlength="300"
              autocomplete="off"
              placeholder="Por ejemplo: despido de una mujer embarazada"
            />
          </div>
          <button type="submit" class="btn btn--primary" phx-disable-with="Buscando…">Buscar</button>
        </div>

        <div class="search__filters">
          <div class="field">
            <label for="b_tipo">Tipo de acción</label>
            <select id="b_tipo" name="b[tipo]" class="select">
              {Phoenix.HTML.Form.options_for_select(
                [{"Todos", ""} | Enum.map(@options.action_types, &{"#{&1} · #{@types[&1]}", &1})],
                @form[:tipo].value
              )}
            </select>
          </div>
          <div class="field">
            <label for="b_desde">Desde el año</label>
            <select id="b_desde" name="b[desde]" class="select">
              {Phoenix.HTML.Form.options_for_select(
                [{"Cualquiera", ""} | Enum.map(@options.years, &{"#{&1}", "#{&1}"})],
                @form[:desde].value
              )}
            </select>
          </div>
          <div class="field">
            <label for="b_hasta">Hasta el año</label>
            <select id="b_hasta" name="b[hasta]" class="select">
              {Phoenix.HTML.Form.options_for_select(
                [{"Cualquiera", ""} | Enum.map(@options.years, &{"#{&1}", "#{&1}"})],
                @form[:hasta].value
              )}
            </select>
          </div>
          <div class="field">
            <label for="b_ponente">Juez o jueza ponente</label>
            <select id="b_ponente" name="b[ponente]" class="select">
              {Phoenix.HTML.Form.options_for_select(
                [{"Cualquiera", ""} | @options.rapporteurs],
                @form[:ponente].value
              )}
            </select>
          </div>
        </div>

        <fieldset class="search__modes">
          <legend class="label">Modo de búsqueda</legend>
          <label class="radio">
            <input
              type="radio"
              name="b[modo]"
              value="hibrida"
              checked={@form[:modo].value == "hibrida"}
              disabled={!@semantic?}
            /> Por palabras y por significado
          </label>
          <label class="radio">
            <input
              type="radio"
              name="b[modo]"
              value="palabras"
              checked={@form[:modo].value == "palabras"}
            /> Solo palabras exactas
          </label>
          <label class="radio">
            <input type="hidden" name="b[respuesta]" value="0" />
            <input
              type="checkbox"
              name="b[respuesta]"
              value="1"
              checked={@form[:respuesta].value == "1"}
            /> Resumir con citas verificadas
          </label>
          <p :if={!@semantic?} class="hint">
            La búsqueda por significado no está activa en este servidor.
          </p>
        </fieldset>
      </.form>

      <section
        class="results"
        aria-labelledby="results-title"
        aria-busy={to_string(@state == :loading)}
      >
        <h2 id="results-title" class="visually-hidden">Resultados</h2>
        <div role="status" aria-live="polite" class="visually-hidden">
          {status_text(@state, @total)}
        </div>
        <.results_body
          state={@state}
          hits={@hits}
          total={@total}
          answer={@answer}
          criteria={@criteria}
          page_size={@page_size}
          link={&page_link(@criteria, &1)}
        />
      </section>
    </Layouts.app>
    """
  end

  defp status_text(:loading, _), do: "Buscando…"
  defp status_text(:ok, 0), do: "Sin resultados."
  defp status_text(:ok, n), do: "#{n} párrafos encontrados."
  defp status_text(:error, _), do: "La búsqueda falló."
  defp status_text(_, _), do: ""

  attr :state, :any, required: true
  attr :hits, :list, required: true
  attr :total, :integer, required: true
  attr :answer, :any, required: true
  attr :criteria, :map, required: true
  attr :page_size, :integer, default: 10
  attr :link, :any, required: true

  defp results_body(%{state: :idle} = assigns) do
    ~H"""
    <div class="state">
      <h3>Empiece con una pregunta o un tema</h3>
      <p>
        Pruebe con «motivación de las sentencias», «derecho al agua» o un número de caso como 9105-18-EP/21.
      </p>
    </div>
    """
  end

  defp results_body(%{state: :loading} = assigns) do
    ~H"""
    <div class="sheet" aria-hidden="true">
      <div :for={_ <- 1..3} class="hit">
        <div class="skeleton"><span></span><span></span></div>
        <div class="skeleton"><span></span><span></span><span></span></div>
      </div>
    </div>
    """
  end

  defp results_body(%{state: {:invalid, message}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="state state--error" role="alert">
      <h3>Revise la consulta</h3>
      <p>{@message}</p>
    </div>
    """
  end

  defp results_body(%{state: :rate_limited} = assigns) do
    ~H"""
    <div class="state state--error" role="alert">
      <h3>Demasiadas búsquedas seguidas</h3>
      <p>Espere un minuto y vuelva a intentarlo.</p>
    </div>
    """
  end

  defp results_body(%{state: :error} = assigns) do
    ~H"""
    <div class="state state--error" role="alert">
      <h3>No pudimos completar la búsqueda</h3>
      <p>
        El índice no respondió. Intente de nuevo en unos segundos; si persiste, use el modo «Solo palabras exactas».
      </p>
    </div>
    """
  end

  defp results_body(%{state: :ok, hits: []} = assigns) do
    ~H"""
    <div class="state">
      <h3>No encontré sentencias que respondan esto</h3>
      <p>Pruebe con otras palabras, quite filtros o cambie al modo por significado.</p>
    </div>
    """
  end

  defp results_body(assigns) do
    ~H"""
    <div :if={@answer} class="answer" id="answer">
      <h3>Resumen con citas verificadas</h3>
      <p :if={@answer.empty?}>{@answer.message}</p>
      <ol :if={!@answer.empty?}>
        <li :for={s <- @answer.sentences}>{s.text}</li>
      </ol>
      <p class="answer__note">
        Cada oración cita textualmente un párrafo recuperado; las que no se pudieron verificar se eliminaron ({@answer.dropped}).
        No es asesoría legal.
      </p>
    </div>

    <div class="results__meta">
      <span :if={@criteria.mode == :keywords}>{@total} párrafos</span>
      <span :if={@criteria.mode == :hybrid}>Los párrafos más cercanos primero</span>
      <span>Página {@criteria.page}</span>
    </div>

    <div class="sheet">
      <article :for={hit <- @hits} class="hit" id={"hit-#{hit.id}"} data-hit>
        <div class="hit__cite">
          <a
            class="hit__case link"
            href={~p"/sentencias/#{hit.ruling_id}" <> "#p-#{hit.paragraph_number}"}
          >{hit.case_number}</a>
          <span class="hit__para">párr. {hit.paragraph_number}</span>
          <span>{hit.action_type}</span>
          <span :if={hit.decided_on}><time datetime={hit.decided_on}>{LexecWeb.Format.date(
            hit.decided_on
          )}</time></span>
        </div>
        <div>
          <p class="hit__text">
            <%= for {kind, text} <- Highlight.segments(hit.text, @criteria.query) do %>
              <mark :if={kind == :mark}>{text}</mark><span :if={kind == :text}>{text}</span>
            <% end %>
          </p>
          <div class="hit__links">
            <a class="link" href={~p"/sentencias/#{hit.ruling_id}"}>Ver ficha de la sentencia</a>
            <.official_link href={hit.official_url}>Documento oficial</.official_link>
            <span class="hint" data-hit-disclaimer>No es asesoría legal.</span>
          </div>
        </div>
      </article>
    </div>

    <nav class="pager" aria-label="Paginación">
      <.link :if={@criteria.page > 1} class="btn" patch={@link.(@criteria.page - 1)}>Página anterior</.link>
      <.link :if={@criteria.page * @page_size < @total} class="btn" patch={@link.(@criteria.page + 1)}>
        Página siguiente
      </.link>
    </nav>
    """
  end
end
