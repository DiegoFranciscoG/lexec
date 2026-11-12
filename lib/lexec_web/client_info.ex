defmodule LexecWeb.ClientInfo do
  @moduledoc """
  Stores the client's IP in the LiveView socket, only to key the rate limiter
  (it is hashed there and never stored or logged).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  def on_mount(:default, _params, _session, socket) do
    ip =
      if connected?(socket) do
        case get_connect_info(socket, :peer_data) do
          %{address: address} -> address
          _ -> :unknown
        end
      else
        :dead_render
      end

    {:cont, assign(socket, :client_ip, ip)}
  end
end
