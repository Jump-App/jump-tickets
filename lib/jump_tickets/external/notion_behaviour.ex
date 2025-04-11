defmodule JumpTickets.External.NotionBehaviour do
  @callback query_db() :: {:ok, [JumpTickets.Ticket.t()]} | {:error, String.t()}
  @callback create_ticket(JumpTickets.Ticket.t()) ::
              {:ok, JumpTickets.Ticket.t()} | {:error, String.t()}
  @callback update_ticket(String.t(), map()) ::
              {:ok, JumpTickets.Ticket.t()} | {:error, String.t()}
end
