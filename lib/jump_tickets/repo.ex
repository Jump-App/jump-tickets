defmodule JumpTickets.Repo do
  use Ecto.Repo,
    otp_app: :jump_tickets,
    adapter: Ecto.Adapters.SQLite3
end
