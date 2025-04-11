defmodule JumpTickets.External.Intercom do
  @moduledoc """
  Intercom client
  """
  alias JumpTickets.External.Intercom.Client
  alias JumpTickets.External.Intercom.Parser

  def get_conversation(conversation_id) do
    case Client.get("/conversations/#{conversation_id}?display_as=plaintext") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, Parser.parse_conversation(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Intercom API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch conversation: #{inspect(reason)}"}
    end
  end

  @doc """
  Gets the list of admin users who participated in a conversation
  """
  def get_participating_admins(conversation_id) do
    case get_conversation(conversation_id) do
      {:ok, %{messages: messages}} ->
        # Extract unique admin participants from messages
        admins =
          messages
          |> Enum.map(& &1.author)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&(&1.type == "admin"))
          |> Enum.uniq_by(&"#{&1.name}-#{&1.email}")

        {:ok, admins}

      error ->
        error
    end
  end

  @doc """
  Replies to a conversation with a message
  """
  def reply_to_conversation(conversation_id, message) do
    body = %{
      message_type: "comment",
      type: "admin",
      admin_id: Application.get_env(:jump_tickets, :intercom)[:admin_id],
      body: message
    }

    case Client.post("/conversations/#{conversation_id}/reply", body) do
      {:ok, %Tesla.Env{status: 200}} ->
        {:ok, "Message sent"}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Intercom API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end

  @doc """
  Get admin user details from Intercom
  """
  def get_admin_details() do
    case Client.get("/admins") do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body["admins"] || []}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Intercom API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to fetch admins: #{inspect(reason)}"}
    end
  end
end

defmodule JumpTickets.External.Intercom.Client do
  @moduledoc false
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://api.intercom.io"

  plug Tesla.Middleware.Headers, [
    {"Authorization", "Bearer #{Application.get_env(:jump_tickets, :intercom_token)}"},
    {"Accept", "application/json"}
  ]

  plug Tesla.Middleware.JSON
end

defmodule JumpTickets.External.Intercom.Parser do
  @moduledoc false

  @doc """
  Parses an Intercom conversation response into a list of messages.
  Returns: %{messages: [%{author: String.t(), text: String.t()}]}
  """
  def parse_conversation(conversation) do
    # Extract initial message from conversation_message
    initial_message = parse_initial_message(conversation["conversation_message"])

    # Extract conversation parts
    conversation_parts = get_in(conversation, ["conversation_parts", "conversation_parts"]) || []

    # Parse messages from parts, filtering out non-message entries
    part_messages =
      Enum.map(conversation_parts, &parse_part/1)
      |> Enum.filter(& &1)

    # Combine initial message with conversation parts
    messages =
      [initial_message | part_messages]
      |> Enum.filter(& &1)

    %{messages: messages}
  end

  # Parse the initial conversation message
  defp parse_initial_message(%{"author" => author, "body" => body}) do
    if body && body != "" do
      %{
        author: format_author(author),
        text: clean_text(body)
      }
    else
      nil
    end
  end

  defp parse_initial_message(_), do: nil

  # Parse a single conversation part
  defp parse_part(%{
         "author" => author,
         "body" => body,
         "part_type" => part_type
       }) do
    # Only include parts with actual message content (e.g., comments, not assignments)
    if body && body != "" && part_type in ["comment", "note"] do
      %{
        author: format_author(author),
        text: clean_text(body)
      }
    else
      nil
    end
  end

  defp parse_part(_), do: nil

  # Format author details into a string (e.g., "Name (type)")
  defp format_author(%{"email" => email, "name" => name, "type" => type}) do
    %{
      email: email,
      name: name,
      type: type
    }
  end

  defp format_author(%{"email" => email, "type" => type}) do
    %{
      email: email,
      name: "",
      type: type
    }
  end

  defp format_author(%{"name" => name, "type" => type}) do
    %{
      email: "",
      name: name,
      type: type
    }
  end

  defp format_author(_), do: nil

  # Clean HTML and handle special cases like image attachments
  defp clean_text(nil), do: ""

  defp clean_text(body) do
    body
    # Remove HTML tags
    |> String.replace(~r/<[^>]+>/, "")
    # Simplify image refs
    |> String.replace(~r/\[Image[^\]]+\]/, "[Image Attachment]")
    |> String.trim()
  end
end
