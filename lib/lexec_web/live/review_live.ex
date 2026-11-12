defmodule LexecWeb.ReviewLive do
  @moduledoc "Review queue (basic auth): doubtful anonymizations and correction requests."
  use LexecWeb, :live_view

  alias Lexec.{Corrections, Review}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Revisión") |> assign(:open, nil) |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:items, Review.list_pending())
    |> assign(:requests, Corrections.list_open())
  end

  @impl true
  def handle_event("open", %{"ruling" => id}, socket) do
    {id, ""} = Integer.parse(id)
    {:noreply, assign(socket, :open, {id, Review.pending_paragraphs(id)})}
  end

  def handle_event("approve", %{"id" => id}, socket),
    do: resolve_item(socket, id, &Review.approve/2, "Sentencia publicada.")

  def handle_event("withdraw", %{"id" => id}, socket),
    do: resolve_item(socket, id, &Review.withdraw/2, "Sentencia retirada.")

  def handle_event("resolve", %{"id" => id, "action" => action}, socket)
      when action in ["withdraw", "correct", "reject"] do
    {id, ""} = Integer.parse(id)

    case Corrections.resolve(
           id,
           String.to_existing_atom(action),
           "Resuelto por #{socket.assigns.reviewer}"
         ) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Solicitud cerrada.") |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "No se pudo cerrar: #{inspect(reason)}")}
    end
  end

  defp resolve_item(socket, id, fun, message) do
    {id, ""} = Integer.parse(id)

    case fun.(id, socket.assigns.reviewer) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, message) |> assign(:open, nil) |> load()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "No se pudo completar: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="page-head">
        <h1>Revisión</h1>
        <p>Sesión de {@reviewer}. Nada de lo pendiente es público hasta que se aprueba.</p>
      </div>

      <div class="table-wrap">
        <table class="table">
          <caption>Anonimizaciones dudosas</caption>
          <thead>
            <tr>
              <th scope="col">Sentencia</th><th scope="col">Motivo</th><th scope="col">Acciones</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@items == []}>
              <td colspan="3">No hay sentencias pendientes de revisión.</td>
            </tr>
            <tr :for={item <- @items} id={"item-#{item.id}"}>
              <td class="mono">{item.case_number}</td>
              <td>{item.reason}</td>
              <td>
                <button type="button" class="btn" phx-click="open" phx-value-ruling={item.ruling_id}>Leer texto anonimizado</button>
                <button
                  type="button"
                  class="btn btn--primary"
                  phx-click="approve"
                  phx-value-id={item.id}
                  data-confirm="¿Publicar esta sentencia?"
                >Aprobar y publicar</button>
                <button
                  type="button"
                  class="btn"
                  phx-click="withdraw"
                  phx-value-id={item.id}
                  data-confirm="¿Retirar esta sentencia del catálogo?"
                >Retirar</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <section :if={@open} class="results" aria-label="Texto en revisión">
        <ol class="paragraphs">
          <li :for={p <- elem(@open, 1)}>
            <span class="n">{p.number}</span><p>{p.text}</p>
          </li>
        </ol>
      </section>

      <div class="table-wrap results">
        <table class="table">
          <caption>Solicitudes de corrección y retiro</caption>
          <thead>
            <tr>
              <th scope="col">N.º</th><th scope="col">Sentencia</th><th scope="col">Tipo</th><th scope="col">
                Motivo
              </th><th scope="col">Vence</th><th scope="col">Acciones</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@requests == []}>
              <td colspan="6">No hay solicitudes abiertas.</td>
            </tr>
            <tr :for={r <- @requests} id={"request-#{r.id}"}>
              <td class="num">{r.id}</td>
              <td class="mono">
                {r.case_number}<span :if={r.paragraph_number}>, párr. {r.paragraph_number}</span>
              </td>
              <td>{if r.request_type == "withdrawal", do: "Retiro", else: "Corrección"}</td>
              <td>{r.reason}</td>
              <td>{LexecWeb.Format.date(r.due_on)}</td>
              <td>
                <button
                  type="button"
                  class="btn btn--primary"
                  phx-click="resolve"
                  phx-value-id={r.id}
                  phx-value-action="withdraw"
                  data-confirm="Se eliminará del índice y del catálogo. ¿Continuar?"
                >Retirar</button>
                <button
                  type="button"
                  class="btn"
                  phx-click="resolve"
                  phx-value-id={r.id}
                  phx-value-action="correct"
                >Marcar corregida</button>
                <button
                  type="button"
                  class="btn"
                  phx-click="resolve"
                  phx-value-id={r.id}
                  phx-value-action="reject"
                >Rechazar</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
