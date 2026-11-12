defmodule LexecWeb.PageController do
  use LexecWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
