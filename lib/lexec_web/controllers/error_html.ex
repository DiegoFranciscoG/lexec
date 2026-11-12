defmodule LexecWeb.ErrorHTML do
  @moduledoc "Error pages without stack traces or internal details."
  use LexecWeb, :html

  def render("404.html", _assigns), do: "Página no encontrada"
  def render("500.html", _assigns), do: "Error interno del servidor"
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
