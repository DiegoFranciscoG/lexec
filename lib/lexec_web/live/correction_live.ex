defmodule LexecWeb.CorrectionLive do
  @moduledoc """
  Public correction and withdrawal channel. No identification required; the
  contact e-mail is optional and needs explicit consent.
  """
  use LexecWeb, :live_view

  alias Lexec.{Corrections, RateLimiter, Rules}

  @impl true
  def mount(params, _session, socket) do
    initial = %{"case_number" => params["caso"] || "", "request_type" => "withdrawal"}

    {:ok,
     socket
     |> assign(:page_title, "Corrección y retiro")
     |> assign(:days, Rules.fetch!(:app, ["corrections", "response_days"]))
     |> assign(:sent, nil)
     |> assign(:form, to_form(Corrections.change_request(initial), as: :request))}
  end

  @impl true
  def handle_event("validate", %{"request" => attrs}, socket) do
    changeset = attrs |> Corrections.change_request() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :request))}
  end

  def handle_event("save", %{"request" => attrs}, socket) do
    with :ok <- RateLimiter.hit("correction", socket.assigns.client_ip),
         {:ok, request} <- Corrections.create_request(attrs) do
      {:noreply,
       socket
       |> assign(:sent, request)
       |> assign(:form, to_form(Corrections.change_request(%{}), as: :request))}
    else
      {:error, :rate_limited} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Ya recibimos varias solicitudes desde esta conexión. Intente en una hora."
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :request))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:correction}>
      <div class="page-head">
        <h1>Corrección y retiro</h1>
        <p>
          Si un párrafo publicado le identifica, contiene un error o no debió publicarse, pida su corrección o su retiro.
          Respondemos en un plazo de {@days} días. No necesita identificarse.
        </p>
      </div>

      <div :if={@sent} class="state" role="status" id="correction-sent">
        <h2>Solicitud recibida</h2>
        <p>
          Número de solicitud <span class="mono">{@sent.id}</span>, sobre la sentencia <span class="mono">{@sent.case_number}</span>.
          Plazo de respuesta: {LexecWeb.Format.date(@sent.due_on)}.
        </p>
      </div>

      <.form
        :if={!@sent}
        for={@form}
        id="correction-form"
        class="form"
        phx-change="validate"
        phx-submit="save"
      >
        <div class="form__row">
          <.field
            field={@form[:case_number]}
            label="Número de sentencia"
            hint="Formato 1234-19-EP/23"
            required
            maxlength="20"
            autocomplete="off"
          />
          <.field
            field={@form[:paragraph_number]}
            type="number"
            label="Párrafo (opcional)"
            inputmode="numeric"
          />
        </div>
        <.field
          field={@form[:request_type]}
          type="select"
          label="Qué solicita"
          options={[{"Retiro del contenido", "withdrawal"}, {"Corrección de un error", "correction"}]}
        />
        <.field
          field={@form[:reason]}
          type="textarea"
          label="Motivo"
          hint="Describa el problema sin incluir datos personales que no sean necesarios."
          required
          maxlength="1000"
        />
        <.field
          field={@form[:contact_email]}
          type="email"
          label="Correo para responderle (opcional)"
          autocomplete="email"
          maxlength="160"
        />
        <.field
          field={@form[:consent]}
          type="checkbox"
          label="Acepto que LEXEC use este correo solo para responder a esta solicitud y lo elimine al cerrarla."
        />
        <div>
          <button type="submit" class="btn btn--primary" phx-disable-with="Enviando…">Enviar solicitud</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
