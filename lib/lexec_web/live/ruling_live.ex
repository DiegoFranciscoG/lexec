defmodule LexecWeb.RulingLive do
  @moduledoc "Ruling sheet: metadata, decision, rapporteur, paragraphs and related rulings."
  use LexecWeb, :live_view

  alias Lexec.{Catalog, Relations, Rules}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Catalog.get_published_ruling(id) do
      nil ->
        raise LexecWeb.NotFoundError, "sentencia no publicada"

      sheet ->
        {:ok,
         socket
         |> assign(:page_title, "Sentencia #{sheet.ruling.case_number}")
         |> assign(:sheet, sheet)
         |> assign(:types, Rules.fetch!(:action_types, ["types"]))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:search}>
      <div class="page-head">
        <p><a class="link" href="/">Volver a la búsqueda</a></p>
        <h1>Sentencia <span class="mono">{@sheet.ruling.case_number}</span></h1>
        <p>{@types[@sheet.ruling.action_type]}</p>
      </div>

      <div class="ruling">
        <section aria-labelledby="parrafos">
          <h2 id="parrafos" class="visually-hidden">Párrafos</h2>
          <ol class="paragraphs">
            <li :for={p <- @sheet.ruling.paragraphs} id={"p-#{p.number}"}>
              <span class="n" aria-label={"Párrafo #{p.number}"}>{p.number}</span>
              <p>{p.text}</p>
            </li>
          </ol>
        </section>

        <aside class="aside" aria-label="Datos de la sentencia">
          <section>
            <h2>Ficha</h2>
            <dl class="facts">
              <dt>Caso</dt>
              <dd class="mono">{@sheet.ruling.case_file || @sheet.ruling.case_number}</dd>
              <dt>Fecha</dt>
              <dd>{LexecWeb.Format.date(@sheet.ruling.decided_on)}</dd>
              <dt>Ponente</dt>
              <dd>{@sheet.ruling.rapporteur || "No consta"}</dd>
              <dt>Decisión</dt>
              <dd>{LexecWeb.Format.decision(@sheet.ruling.decision)}</dd>
              <dt>Párrafos</dt>
              <dd class="mono">{@sheet.ruling.paragraph_count}</dd>
            </dl>
            <p>
              <.official_link href={@sheet.ruling.official_url}>Documento oficial</.official_link>
            </p>
            <p class="hint" data-hit-disclaimer>
              No es asesoría legal. Verifique el documento oficial.
            </p>
          </section>

          <section>
            <h2>Sentencias que cita</h2>
            <p :if={@sheet.cites == []} class="hint">No cita otras sentencias.</p>
            <ul>
              <li :for={c <- @sheet.cites}>
                <a :if={c.ruling_id} class="link mono" href={~p"/sentencias/#{c.ruling_id}"}>{c.case_number}</a>
                <span :if={!c.ruling_id} class="mono">{c.case_number}</span>
                <a class="link" href={"#p-#{c.paragraph_number}"}>párr. {c.paragraph_number}</a>
              </li>
            </ul>
          </section>

          <section>
            <h2>Citada por</h2>
            <p :if={@sheet.cited_by == []} class="hint">Ninguna sentencia del corpus la cita.</p>
            <ul>
              <li :for={c <- @sheet.cited_by}>
                <a
                  class="link mono"
                  href={~p"/sentencias/#{c.ruling_id}" <> "#p-#{c.paragraph_number}"}
                >{c.case_number}</a>
                párr. {c.paragraph_number}
              </li>
            </ul>
          </section>

          <section>
            <h2>Normas citadas</h2>
            <ul>
              <li :for={n <- @sheet.norms}>
                Art. <span class="mono">{n.article}</span>, {Relations.body_name(n.norm_body)}
              </li>
            </ul>
          </section>

          <section>
            <h2>Anonimización</h2>
            <p class="hint">
              Datos reemplazados en esta sentencia: {anonymization_summary(@sheet.anonymization)}.
              <a class="link" href={~p"/correccion?#{%{caso: @sheet.ruling.case_number}}"}>Pedir corrección o retiro</a>
            </p>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  @labels %{
    "person" => {"persona", "personas"},
    "id_number" => {"número de identificación", "números de identificación"},
    "phone" => {"teléfono", "teléfonos"},
    "email" => {"correo", "correos"},
    "address" => {"dirección", "direcciones"}
  }

  defp anonymization_summary(stats) when map_size(stats) == 0, do: "ninguno"

  defp anonymization_summary(stats) do
    stats
    |> Enum.sort()
    |> Enum.map_join(", ", fn {type, count} ->
      {one, many} = Map.get(@labels, type, {type, type})
      "#{count} #{if count == 1, do: one, else: many}"
    end)
  end
end

defmodule LexecWeb.NotFoundError do
  defexception message: "no encontrado", plug_status: 404
end
