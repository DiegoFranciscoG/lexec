defmodule Lexec.Repo do
  use Ecto.Repo,
    otp_app: :lexec,
    adapter: Ecto.Adapters.SQLite3
end
