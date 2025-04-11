defmodule JumpTicketsWeb.TicketDoneController do
  use JumpTicketsWeb, :controller

  alias JumpTickets.Ticket
  alias JumpTickets.External.Notion
  alias JumpTickets.External.Notion.Parser
  alias JumpTickets.Ticket.DoneNotifier

  @doc """
  Handles a Notion webhook for when a ticket is marked as Done.

  Expects a JSON payload with the `page_id` key.
  """
  def notion_webhook(conn, %{"page_id" => page_id}) do
    with %Ticket{} = ticket <- Notion.get_ticket_by_page_id(page_id),
         :ok <- DoneNotifier.notify_ticket_done(ticket) do
      json(conn, %{status: "ok", message: "Ticket done notification sent."})
    else
      error ->
        # Log or handle error as needed
        conn
        |> put_status(500)
        |> json(%{status: "error", error: inspect(error)})
    end
  end
end
