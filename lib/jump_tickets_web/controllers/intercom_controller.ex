defmodule JumpTicketsWeb.IntercomController do
  use JumpTicketsWeb, :controller

  alias JumpTickets.IntegrationRequest

  def submit(conn, %{
        "conversationId" => conversation_id,
        "conversationUrl" => conversation_url,
        "messageBody" => message_body
      }) do
    # Log the incoming payload for debugging
    {:ok, request_id} =
      IntegrationRequest.create_integration_request(%{
        conversation_id: conversation_id,
        conversation_url: conversation_url,
        message_body: message_body
      })

    conn
    |> put_status(:ok)
    |> json(%{
      requestId: request_id
    })
  end
end
