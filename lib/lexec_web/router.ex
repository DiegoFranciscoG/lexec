defmodule LexecWeb.Router do
  use LexecWeb, :router

  # Everything is served from this origin: no third-party scripts, fonts or trackers.
  @csp Enum.join(
         [
           "default-src 'self'",
           "script-src 'self'",
           "style-src 'self'",
           "img-src 'self' data:",
           "font-src 'self'",
           "connect-src 'self' ws: wss:",
           "frame-ancestors 'none'",
           "base-uri 'self'",
           "form-action 'self'",
           "object-src 'none'"
         ],
         "; "
       )

  @security_headers %{
    "content-security-policy" => @csp,
    "referrer-policy" => "strict-origin-when-cross-origin",
    "permissions-policy" => "camera=(), microphone=(), geolocation=(), interest-cohort=()",
    "cross-origin-opener-policy" => "same-origin",
    "x-frame-options" => "DENY"
  }

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LexecWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, @security_headers
    plug LexecWeb.Plugs.RateLimit, bucket: "page"
  end

  pipeline :admin do
    plug LexecWeb.Plugs.AdminAuth
  end

  scope "/", LexecWeb do
    get "/health", HealthController, :show
  end

  scope "/", LexecWeb do
    pipe_through :browser

    get "/metodologia", PageController, :methodology
    get "/aviso-legal", PageController, :legal

    live_session :public, on_mount: LexecWeb.ClientInfo do
      live "/", SearchLive, :index
      live "/sentencias/:id", RulingLive, :show
      live "/precedentes", PrecedentsLive, :index
      live "/correccion", CorrectionLive, :new
    end
  end

  scope "/admin", LexecWeb do
    pipe_through [:browser, :admin]

    live_session :admin,
      on_mount: [LexecWeb.ClientInfo, {LexecWeb.Plugs.AdminAuth, :ensure_reviewer}],
      session: {LexecWeb.Plugs.AdminAuth, :live_session, []} do
      live "/revision", ReviewLive, :index
    end
  end
end
