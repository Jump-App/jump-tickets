defmodule JumpTickets.Ticket do
  use Ecto.Schema

  schema "tickets" do
    field :notion_id, :string
    field :notion_url, :string
    field :ticket_id, :string
    field :title, :string
    field :intercom_conversations, :string
    field :summary, :string
    field :slack_channel, :string
  end
end
