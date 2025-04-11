defmodule JumpTickets.External.LLMBehaviour do
  @callback find_or_create_ticket([JumpTickets.Ticket.t()], String.t(), map()) ::
              {:ok, {:new, map()}}
              | {:ok, {:existing, JumpTickets.Ticket.t()}}
              | {:error, String.t()}
end
