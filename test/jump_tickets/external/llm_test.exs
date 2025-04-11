defmodule JumpTickets.External.LlmTest do
  @moduledoc false

  use ExUnit.Case
  import Mock
  alias JumpTickets.External.LLM

  describe "format_existing_tickets/1" do
    test "formats tickets into readable strings" do
      tickets = [
        %JumpTickets.Ticket{ticket_id: "JMP-001", title: "Login Issues"},
        %JumpTickets.Ticket{ticket_id: "JMP-002", title: "API Integration Failure"}
      ]

      expected = "ID: JMP-001 | Title: Login Issues\nID: JMP-002 | Title: API Integration Failure"

      assert LLM.format_existing_tickets(tickets) == expected
    end
  end

  describe "extract_json_string/1" do
    test "extracts JSON from code blocks" do
      text = """
      Here's my analysis:

      ```json
      {"decision": "new", "reasoning": "No matching tickets found"}
      ```

      Hope that helps!
      """

      expected = ~s({"decision": "new", "reasoning": "No matching tickets found"})

      assert LLM.extract_json_string(text) == expected
    end

    test "extracts JSON without code blocks" do
      text = """
      Here's my analysis:

      {"decision": "existing", "ticket_id": "JMP-001", "reasoning": "Matches first ticket"}

      Hope that helps!
      """

      expected =
        ~s({"decision": "existing", "ticket_id": "JMP-001", "reasoning": "Matches first ticket"})

      assert String.trim(LLM.extract_json_string(text)) == String.trim(expected)
    end
  end

  describe "fallback_parse_json/1" do
    test "extracts fields from malformed JSON" do
      text = """
      I think this should be a new ticket because there's nothing similar.

      "decision": "new",
      "reasoning": "No existing tickets match this conversation"
      """

      expected = %{"decision" => "new"}

      assert LLM.fallback_parse_json(text) == expected
    end
  end
end
