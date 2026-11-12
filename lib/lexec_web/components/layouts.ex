defmodule LexecWeb.Layouts do
  @moduledoc "Page shell: brand, navigation, legal notices, footer and cookie notice."
  use LexecWeb, :html

  embed_templates "layouts/*"

  @nav [
    {"/", "Buscar", :search},
    {"/precedentes", "Precedentes", :precedents},
    {"/metodologia", "Metodología", :methodology},
    {"/correccion", "Corrección y retiro", :correction},
    {"/aviso-legal", "Aviso legal", :legal}
  ]

  attr :flash, :map, required: true
  attr :active, :atom, default: nil, doc: "current section, marked with aria-current"
  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:nav, @nav)
      |> assign(:disclaimer, Lexec.Rules.fetch!(:app, ["texts", "disclaimer"]))
      |> assign(:demo_notice, Lexec.Rules.fetch!(:app, ["texts", "demo_notice"]))
      |> assign(:demo?, Application.get_env(:lexec, :demo_mode, false))

    ~H"""
    <header class="topbar">
      <div class="container topbar__inner">
        <.brand />
        <nav aria-label="Principal">
          <ul class="nav">
            <li :for={{href, label, key} <- @nav}>
              <a href={href} aria-current={if @active == key, do: "page"}>{label}</a>
            </li>
          </ul>
        </nav>
      </div>
    </header>
    <div :if={@demo?} class="band band--demo" role="note">
      <p class="container">{@demo_notice}</p>
    </div>
    <div class="band band--legal" role="note">
      <p class="container" data-disclaimer><strong>Aviso:</strong> {@disclaimer}</p>
    </div>

    <main id="contenido" class="main container" tabindex="-1">
      {render_slot(@inner_block)}
    </main>

    <footer class="footer">
      <div class="container footer__grid">
        <div>
          <.brand />
          <p>
            Proyecto académico, gratuito y sin publicidad. Sin cuentas de usuario.
            Las sentencias pertenecen a la Corte Constitucional del Ecuador; LEXEC muestra solo texto
            anonimizado y enlaza siempre al documento oficial.
          </p>
        </div>
        <div>
          <h2>El proyecto</h2>
          <ul>
            <li><a href="/metodologia">Metodología y fuentes</a></li>
            <li><a href="/precedentes">Red de precedentes</a></li>
            <li><a href="/correccion">Solicitar corrección o retiro</a></li>
          </ul>
        </div>
        <div>
          <h2>Legal</h2>
          <ul>
            <li><a href="/aviso-legal">Aviso legal</a></li>
            <li><a href="/aviso-legal#privacidad">Privacidad</a></li>
            <li><a href="/aviso-legal#cookies">Cookies</a></li>
          </ul>
        </div>
      </div>
    </footer>

    <div class="cookie-note" id="cookie-note" role="region" aria-label="Aviso de cookies">
      <p>
        Solo usamos una cookie técnica necesaria para que el sitio funcione. No hay analítica ni publicidad. <a href="/aviso-legal#cookies">Más información</a>.
      </p>
      <button type="button" class="btn" data-cookie-ack>Entendido</button>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  def brand(assigns) do
    ~H"""
    <a href="/" class="brand" aria-label="LEXEC, inicio">
      <svg class="brand__mark" viewBox="0 0 40 40" aria-hidden="true" focusable="false">
        <path d="M3 11.5 20 3l17 8.5z" fill="currentColor" />
        <rect class="brand__band" x="5" y="12.5" width="30" height="2" />
        <rect x="8.5" y="16" width="4" height="15" fill="currentColor" />
        <rect x="18" y="16" width="4" height="15" fill="currentColor" />
        <rect x="27.5" y="16" width="4" height="15" fill="currentColor" />
        <rect x="4" y="32" width="32" height="2.5" fill="currentColor" />
        <rect x="2" y="35.5" width="36" height="1.5" fill="currentColor" />
      </svg>
      <span>
        <span class="brand__name">LEXEC</span>
        <span class="brand__sub">Jurisprudencia constitucional del Ecuador</span>
      </span>
    </a>
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
