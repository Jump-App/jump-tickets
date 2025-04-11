defmodule JumpTickets.Ticket.DoneNotifier do
  @moduledoc """
  Notifies related channels and conversations when a ticket is marked as Done.
  """

  alias JumpTickets.External.{Slack, Intercom}

  @spec notify_ticket_done(%{
          :intercom_conversations => nil | binary(),
          :slack_channel => nil | binary() | URI.t(),
          :ticket_id => any(),
          optional(any()) => any()
        }) :: :ok
  @doc """
  Sends a done notification to the ticket’s Slack channel and all linked Intercom conversations.
  """
  def notify_ticket_done(
        %{
          ticket_id: ticket_id,
          slack_channel: slack_channel,
          intercom_conversations: convs
        } = ticket
      ) do
    slack_message = "Ticket #{ticket_id} has been marked as Done."

    # Post to Slack
    with {:ok, _} <- post_slack_message(slack_channel, slack_message) do
      :ok
    else
      error -> IO.puts("Failed to notify Slack: #{inspect(error)}")
    end

    # Post to each linked Intercom conversation
    convs
    |> parse_intercom_conversations()
    |> Enum.each(fn conversation_id ->
      intercom_message = "Ticket #{ticket_id} has been marked as Done."

      case Intercom.reply_to_conversation(conversation_id, intercom_message) do
        {:ok, _} ->
          :ok

        {:error, err} ->
          IO.puts("Failed to notify Intercom conversation #{conversation_id}: #{inspect(err)}")
      end
    end)

    :ok
  end

  defp post_slack_message(nil, _), do: {:error, :no_slack_channel}

  defp post_slack_message(slack_channel, message) do
    # Example: Slack channel URL is like "https://app.slack.com/client/TEAM_ID/CHANNEL_ID?entry_point=nav_menu"
    case URI.parse(slack_channel) do
      %URI{path: path} ->
        # Extract the channel id (assuming it's the fourth segment)
        parts = String.split(path, "/")
        channel_id = Enum.at(parts, 2)
        Slack.post_message(channel_id, message)

      _ ->
        {:error, :invalid_slack_channel_url}
    end
  end

  defp parse_intercom_conversations(nil), do: []

  defp parse_intercom_conversations(conversations) when is_binary(conversations) do
    conversations
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&extract_conversation_id/1)
  end

  defp extract_conversation_id(url) do
    # Assuming conversation URLs are in the format:
    # "https://app.intercom.io/a/apps/APP_ID/conversations/CONVERSATION_ID"
    case URI.parse(url) do
      %URI{path: path} ->
        parts = String.split(path, "/")
        List.last(parts)

      _ ->
        url
    end
  end
end
