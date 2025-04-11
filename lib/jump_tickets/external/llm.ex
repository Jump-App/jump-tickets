defmodule JumpTickets.External.LLM do
  @moduledoc """
  Integration with Claude for ticket management:
  - Finding matching tickets
  - Creating new ticket titles and summaries
  - Analyzing Intercom conversations
  """

  alias JumpTickets.Ticket
  alias Anthropix

  @doc """
  Main function to determine if a conversation matches an existing ticket or needs a new one.

  Returns either:
  - {:existing, %Ticket{}} if a matching ticket is found
  - {:new, %{title: String.t(), summary: String.t()}} if a new ticket should be created
  """
  def find_or_create_ticket(
        existing_tickets,
        message_body,
        conversation,
        request_analysis \\ &request_claude_analysis/1
      ) do
    # Convert raw conversation to a formatted string for Claude
    formatted_conversation = format_conversation(conversation)

    # Format existing tickets as a list of titles and IDs for Claude
    formatted_tickets = format_existing_tickets(existing_tickets)

    # Prepare the prompt for Claude
    prompt = build_ticket_matching_prompt(formatted_tickets, formatted_conversation, message_body)

    # Get Claude's analysis
    case request_analysis.(prompt) do
      {:ok, %{"decision" => "existing", "ticket_id" => ticket_id}} ->
        # Find the matching ticket from the existing tickets list

        matching_ticket =
          Enum.find(existing_tickets, fn ticket -> ticket.ticket_id == ticket_id end)

        if matching_ticket do
          {:ok, {:existing, matching_ticket}}
        else
          # Fallback if the ticket ID wasn't found (shouldn't happen)
          create_new_ticket_with_ai(conversation, message_body)
        end

      {:ok, %{"decision" => "new"}} ->
        create_new_ticket_with_ai(conversation, message_body)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new ticket with AI-generated title and summary
  """
  def create_new_ticket_with_ai(conversation, message_body) do
    # Format conversation for Claude
    formatted_conversation = format_conversation(conversation)

    # Build prompt for ticket creation
    prompt = build_ticket_creation_prompt(formatted_conversation, message_body)

    # Get Claude's response with title and summary
    case request_claude_ticket_creation(prompt) do
      {:ok, %{"title" => title, "summary" => summary, "slug" => slug}} ->
        {:ok, {:new, %{title: title, summary: summary, slug: slug}}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Formats a conversation into a string suitable for Claude's analysis
  """
  def format_conversation(%{messages: messages}) do
    conversation =
      messages
      |> Enum.map(fn %{text: text, author: author} ->
        author_type = if author.type == "admin", do: "Agent", else: "Customer"
        author_name = author.name
        "#{author_type} (#{author_name}): #{text}"
      end)
      |> Enum.join("\n\n")

    conversation
  end

  @doc """
  Formats existing tickets into a string suitable for Claude's analysis
  """
  def format_existing_tickets(tickets) do
    tickets
    |> Enum.map(fn ticket ->
      "ID: #{ticket.ticket_id} | Title: #{ticket.title}"
    end)
    |> Enum.join("\n")
  end

  @doc """
  Builds the prompt for Claude to decide if we need a new ticket or can use an existing one
  """
  def build_ticket_matching_prompt(formatted_tickets, formatted_conversation, message_body) do
    """
    <ticket_matching_task>
    Your task is to determine if a customer conversation matches an existing support ticket or requires a new one.

    <existing_tickets>
    #{formatted_tickets}
    </existing_tickets>

    <customer_conversation>
    #{formatted_conversation}
    </customer_conversation>

    <highlighted_message>
    #{message_body}
    </highlighted_message>

    Based on the conversation and existing tickets, determine if this conversation matches an existing ticket or needs a new one.

    Think carefully about:
    1. The main issue being discussed in the conversation
    2. Whether any existing ticket titles address the same issue
    3. Key details and context in the conversation that might indicate it's related to an existing ticket

    Respond in this JSON format:

    If it matches an existing ticket:
    {
      "decision": "existing",
      "ticket_id": "[THE TICKET ID]",
      "reasoning": "[YOUR REASONING]"
    }

    If it needs a new ticket:
    {
      "decision": "new",
      "reasoning": "[YOUR REASONING]"
    }
    </ticket_matching_task>
    """
  end

  @doc """
  Builds the prompt for Claude to generate a title and summary for a new ticket
  """
  def build_ticket_creation_prompt(formatted_conversation, message_body) do
    """
    <ticket_creation_task>
    Based on the following customer conversation, create a support ticket with a clear title and detailed summary.

    <customer_conversation>
    #{formatted_conversation}
    </customer_conversation>

    <highlighted_message>
    #{message_body}
    </highlighted_message>

    Respond with a JSON object containing three fields:
    1. A concise, specific ticket title (max 80 characters)
    2. A comprehensive summary of the issue and what needs to be addressed (200-400 words)
    3. A URL-friendly slug for the ticket title (lowercase, hyphenated, no special characters)

    For example:
    {
      "title": "Customer Exchange sync failing after recent update",
      "summary": "Customer reports their Exchange calendar is no longer syncing with our application after the v3.2 update. They've tried restarting the sync service and reinstalling the Outlook plugin, but the issue persists. Based on their description, this appears to be related to the authentication changes in the latest build. Engineering team should investigate the OAuth token refresh mechanism that was modified in the recent release. Customer needs this resolved urgently as it's affecting their scheduling system.",
      "slug": "customer-exchange-sync-failing"
    }
    </ticket_creation_task>
    """
  end

  @doc """
  Makes the actual request to Claude via the Anthropic API
  """
  def request_claude_analysis(prompt) do
    client =
      Anthropix.init(Application.get_env(:jump_tickets, :claude_secret),
        retry: :safe_transient,
        max_retries: 5
      )

    response =
      Anthropix.chat(client,
        model: "claude-3-5-haiku-20241022",
        # max_tokens: 1000,
        # temperature: 0.2,
        messages: [
          %{role: "user", content: prompt}
        ]
      )

    case response do
      {:ok, result} ->
        # Extract the content from Claude's response
        content = result["content"] |> List.first() |> Map.get("text")

        # Extract the JSON from the content
        {:ok, parse_json_from_response(content)}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Similar to request_claude_analysis but specifically for ticket creation responses
  """
  def request_claude_ticket_creation(prompt) do
    request_claude_analysis(prompt)
  end

  @doc """
  Parses JSON from Claude's response text
  """
  def parse_json_from_response(response_text) do
    # Extract JSON from the response (it might be wrapped in markdown code blocks)
    json_text =
      response_text
      |> extract_json_string()

    case Jason.decode(json_text) do
      {:ok, parsed} ->
        parsed

      {:error, _} ->
        # Fallback parsing method if the first attempt fails
        fallback_parse_json(response_text)
    end
  end

  @doc """
  Extracts JSON string from Claude's response, handling code blocks
  """
  def extract_json_string(text) do
    # Try to extract JSON from markdown code blocks first
    code_block_regex = ~r/```(?:json)?\s*({[\s\S]*?})\s*```/

    case Regex.run(code_block_regex, text) do
      [_, json] ->
        json

      nil ->
        # If no code blocks, look for JSON patterns directly
        case Regex.run(~r/{[\s\S]*?}/, text) do
          [json] -> json
          # Empty JSON as fallback
          nil -> "{}"
        end
    end
  end

  @doc """
  Fallback JSON parsing for cases where the structure might be malformed
  """
  def fallback_parse_json(text) do
    # Extract keys using regex patterns
    decision_match = Regex.run(~r/"decision":\s*"([^"]+)"/, text)
    ticket_id_match = Regex.run(~r/"ticket_id":\s*"([^"]+)"/, text)
    title_match = Regex.run(~r/"title":\s*"([^"]+)"/, text)
    summary_match = Regex.run(~r/"summary":\s*"([^"]+)"/, text)
    slug_match = Regex.run(~r/"slug":\s*"([^"]+)"/, text)

    # Build a map with the extracted values
    %{}
    |> maybe_add_field("decision", decision_match)
    |> maybe_add_field("ticket_id", ticket_id_match)
    |> maybe_add_field("title", title_match)
    |> maybe_add_field("summary", summary_match)
    |> maybe_add_field("slug", slug_match)
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, [_, value]), do: Map.put(map, key, value)
end
