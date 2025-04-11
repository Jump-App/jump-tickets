defmodule JumpTickets.Logic.LogicTest do
  use ExUnit.Case, async: true

  import Mox

  alias JumpTickets.Ticket
  alias JumpTickets.IntegrationRequest.Logic
  alias JumpTickets.IntegrationRequest.Request

  setup :verify_on_exit!

  describe "happy path for new ticket" do
    test "successfully creates a new ticket through all steps" do
      request =
        Logic.new(%{
          conversation_id: "123",
          conversation_url: "https://app.intercom.com/conversations/123",
          message_body: "Customer reports sync issue"
        })

      # Step 1: Query Notion database – no existing tickets.
      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      # Step 2: Get the conversation from Intercom.
      expect(MockIntercom, :get_conversation, fn "123" ->
        {:ok,
         %{
           messages: [
             %{author: %{type: "customer", name: "John"}, text: "Sync broken"}
           ]
         }}
      end)

      # Step 3: Ask LLM to analyze conversation.
      expect(MockLLM, :find_or_create_ticket, fn tickets, message_body, conversation ->
        assert tickets == []
        assert message_body == "Customer reports sync issue"

        {:ok,
         {:new,
          %{title: "Sync Failure", summary: "Sync broken after update", slug: "sync-failure"}}}
      end)

      # Step 4: Create a new Notion ticket.
      expect(MockNotion, :create_ticket, fn ticket ->
        assert ticket.title == "Sync Failure"
        assert ticket.summary == "Sync broken after update"

        {:ok,
         %Ticket{
           ticket_id: "JMP-001",
           notion_id: "notion123",
           notion_url: "https://notion.so/JMP-001"
         }}
      end)

      # Step 5: Create a new Slack channel for the new ticket.
      expect(MockSlack, :create_channel, fn "JMP-001-sync-failure" ->
        {:ok, %{channel_id: "C123", url: "https://slack.com/C123"}}
      end)

      # Step 6: Update the Notion ticket with the Slack channel URL.
      expect(MockNotion, :update_ticket, fn "notion123", %{slack_channel: slack_url} ->
        assert slack_url == "https://slack.com/C123"
        {:ok, %Ticket{ticket_id: "JMP-001", slack_channel: slack_url}}
      end)

      # Step 7: Add Intercom admins to the Slack channel.
      expect(MockIntercom, :get_participating_admins, fn "123" ->
        {:ok, [%{name: "Admin1", email: "admin1@example.com"}]}
      end)

      expect(MockSlack, :get_all_users, fn ->
        {:ok, [%{id: "U123", name: "Admin1", email: "admin1@example.com"}]}
      end)

      expect(MockSlack, :invite_users_to_channel, fn "C123", ["U123"] ->
        {:ok, "invited"}
      end)

      # Step 8: Set Slack channel topic linking to the Notion ticket.
      expect(MockSlack, :set_channel_topic, fn "C123", "https://notion.so/JMP-001" ->
        {:ok, "topic set"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :completed
      assert result.steps[:check_existing_tickets].status == :completed
      assert result.steps[:ai_analysis].status == :completed
      assert result.steps[:create_or_update_notion_ticket].status == :completed
      assert result.steps[:maybe_create_slack_channel].status == :completed
      assert result.steps[:maybe_update_notion_with_slack].status == :completed
      assert result.steps[:add_intercom_users_to_slack].status == :completed
    end
  end

  describe "happy path for existing ticket" do
    test "successfully updates an existing ticket and adds conversation" do
      request =
        Logic.new(%{
          conversation_id: "456",
          conversation_url: "https://app.intercom.com/conversations/456",
          message_body: "Customer reports login issue"
        })

      # Step 1: Query Notion database returns one existing ticket.
      expect(MockNotion, :query_db, fn ->
        {:ok,
         [
           %Ticket{
             ticket_id: "JMP-002",
             notion_id: "notion456",
             intercom_conversations: "https://app.intercom.com/conversations/111",
             slack_channel: "https://slack.com/client/T123/C456?entry_point=nav_menu"
           }
         ]}
      end)

      # Step 2: Get conversation details.
      expect(MockIntercom, :get_conversation, fn "456" ->
        {:ok,
         %{
           messages: [
             %{author: %{type: "customer", name: "Jane"}, text: "Issue details"}
           ]
         }}
      end)

      # Step 3: LLM determines this conversation matches an existing ticket.
      expect(MockLLM, :find_or_create_ticket, fn tickets, message_body, _conversation ->
        {:ok,
         {:existing,
          %Ticket{
            ticket_id: "JMP-002",
            notion_id: "notion456",
            intercom_conversations: "https://app.intercom.com/conversations/111",
            slack_channel: "https://slack.com/client/T123/C456?entry_point=nav_menu"
          }}}
      end)

      expect(MockNotion, :update_ticket, 2, fn "notion456", update_params ->
        cond do
          Map.has_key?(update_params, :intercom_conversations) ->
            assert update_params[:intercom_conversations] ==
                     "https://app.intercom.com/conversations/456,https://app.intercom.com/conversations/111"

            {:ok,
             %Ticket{
               ticket_id: "JMP-002",
               notion_id: "notion456",
               intercom_conversations: update_params[:intercom_conversations],
               slack_channel: "https://slack.com/client/T123/C456?entry_point=nav_menu"
             }}

          Map.has_key?(update_params, :slack_channel) ->
            assert update_params[:slack_channel] ==
                     "https://slack.com/client/T123/C456?entry_point=nav_menu"

            {:ok,
             %Ticket{
               ticket_id: "JMP-002",
               notion_id: "notion456",
               intercom_conversations:
                 "https://app.intercom.com/conversations/456,https://app.intercom.com/conversations/111",
               slack_channel: update_params[:slack_channel]
             }}

          true ->
            flunk("Unexpected update_ticket parameters: #{inspect(update_params)}")
        end
      end)

      # Step 5: For existing tickets, the Slack channel is already set.
      # The logic will extract the channel ID from the URL.
      # (No external call is made here for channel creation.)

      # Step 6: Expect list_channel_users to be called with the proper channel id "C456"
      expect(MockSlack, :list_channel_users, fn "C456" ->
        {:ok, []}
      end)

      # Step 7: Add Intercom admins to the Slack channel.
      expect(MockIntercom, :get_participating_admins, fn "456" ->
        {:ok, [%{name: "Admin2", email: "admin2@example.com"}]}
      end)

      expect(MockSlack, :get_all_users, fn ->
        {:ok, [%{id: "U456", name: "Admin2", email: "admin2@example.com"}]}
      end)

      expect(MockSlack, :invite_users_to_channel, fn "C456", ["U456"] ->
        {:ok, "invited"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :completed
      assert result.steps[:check_existing_tickets].status == :completed
      assert result.steps[:ai_analysis].status == :completed
      assert result.steps[:create_or_update_notion_ticket].status == :completed
      assert result.steps[:maybe_create_slack_channel].status == :completed
      assert result.steps[:add_intercom_users_to_slack].status == :completed
    end
  end

  describe "failure paths" do
    test "fails when Intercom.get_conversation returns an error" do
      request =
        Logic.new(%{
          conversation_id: "789",
          conversation_url: "https://app.intercom.com/conversations/789",
          message_body: "Error test"
        })

      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      expect(MockIntercom, :get_conversation, fn "789" ->
        {:error, "Intercom API error"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :failed
      assert result.steps[:check_existing_tickets].status == :completed
      assert result.steps[:ai_analysis].status == :failed
    end

    test "fails when LLM.find_or_create_ticket returns an error" do
      request =
        Logic.new(%{
          conversation_id: "101",
          conversation_url: "https://app.intercom.com/conversations/101",
          message_body: "LLM failure test"
        })

      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      expect(MockIntercom, :get_conversation, fn "101" ->
        {:ok,
         %{
           messages: [
             %{author: %{type: "customer", name: "Test"}, text: "Test message"}
           ]
         }}
      end)

      expect(MockLLM, :find_or_create_ticket, fn _tickets, _message_body, _conversation ->
        {:error, "LLM error"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :failed
      assert result.steps[:check_existing_tickets].status == :completed
      assert result.steps[:ai_analysis].status == :failed
    end
  end

  describe "retry logic" do
    test "retry_step resets specified step and subsequent steps" do
      # Create a request that fails at ai_analysis.
      request =
        Logic.new(%{
          conversation_id: "202",
          conversation_url: "https://app.intercom.com/conversations/202",
          message_body: "Retry test"
        })

      # Initial run fails because Intercom.get_conversation returns an error.
      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      expect(MockIntercom, :get_conversation, fn "202" ->
        {:error, "Simulated failure"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :failed
      assert result.steps[:ai_analysis].status == :failed

      # Now simulate a successful retry from the failing step.
      expect(MockIntercom, :get_conversation, fn _ ->
        {:ok,
         %{
           messages: [
             %{author: %{type: "customer", name: "Retry"}, text: "Recovered message"}
           ]
         }}
      end)

      expect(MockLLM, :find_or_create_ticket, fn _tickets, _message_body, _conversation ->
        # Force a new ticket decision.
        {:ok,
         {:new,
          %{title: "Recovered Ticket", summary: "Recovered summary", slug: "recovered-ticket"}}}
      end)

      expect(MockNotion, :create_ticket, fn ticket ->
        {:ok,
         %Ticket{
           ticket_id: "JMP-003",
           notion_id: "notion-retry",
           notion_url: "https://notion.so/JMP-003"
         }}
      end)

      expect(MockSlack, :create_channel, fn "JMP-003-recovered-ticket" ->
        {:ok, %{channel_id: "C789", url: "https://slack.com/C789"}}
      end)

      expect(MockNotion, :update_ticket, fn "notion-retry",
                                            %{slack_channel: "https://slack.com/C789"} ->
        {:ok,
         %Ticket{
           ticket_id: "JMP-003",
           notion_id: "notion-retry",
           slack_channel: "https://slack.com/C789"
         }}
      end)

      # In the new-ticket flow for adding Intercom users, we use the clause that doesn't call list_channel_users.
      expect(MockIntercom, :get_participating_admins, fn "202" ->
        {:ok, [%{name: "AdminRetry", email: "adminretry@example.com"}]}
      end)

      expect(MockSlack, :get_all_users, fn ->
        {:ok, [%{id: "U999", name: "AdminRetry", email: "adminretry@example.com"}]}
      end)

      expect(MockSlack, :invite_users_to_channel, fn "C789", ["U999"] ->
        {:ok, "invited"}
      end)

      expect(MockSlack, :set_channel_topic, fn "C789", "https://notion.so/JMP-003" ->
        {:ok, "topic set"}
      end)

      retry_result =
        result
        |> Logic.reset_from_step(:ai_analysis)
        |> Logic.run(intercom: MockIntercom, notion: MockNotion, slack: MockSlack, llm: MockLLM)

      assert retry_result.status == :completed
      assert retry_result.steps[:ai_analysis].status == :completed
      assert retry_result.steps[:create_or_update_notion_ticket].status == :completed
      assert retry_result.steps[:maybe_create_slack_channel].status == :completed
      assert retry_result.steps[:maybe_update_notion_with_slack].status == :completed
      assert retry_result.steps[:add_intercom_users_to_slack].status == :completed
    end

    test "retry_all resets the entire request" do
      # Create a request that fails.
      request =
        Logic.new(%{
          conversation_id: "303",
          conversation_url: "https://app.intercom.com/conversations/303",
          message_body: "Retry all test"
        })

      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      expect(MockIntercom, :get_conversation, fn "303" ->
        {:error, "Simulated failure for retry_all"}
      end)

      result =
        Logic.run(request,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert result.status == :failed

      # Now simulate a full successful run after a retry.
      expect(MockNotion, :query_db, fn ->
        {:ok, []}
      end)

      expect(MockIntercom, :get_conversation, fn "303" ->
        {:ok,
         %{
           messages: [
             %{author: %{type: "customer", name: "FullRetry"}, text: "Recovered message"}
           ]
         }}
      end)

      expect(MockLLM, :find_or_create_ticket, fn _tickets, _message_body, _conversation ->
        {:ok,
         {:new,
          %{
            title: "Full Recovered Ticket",
            summary: "Full recovered summary",
            slug: "full-recovered-ticket"
          }}}
      end)

      expect(MockNotion, :create_ticket, fn ticket ->
        {:ok,
         %Ticket{
           ticket_id: "JMP-004",
           notion_id: "notion-full-retry",
           notion_url: "https://notion.so/JMP-004"
         }}
      end)

      expect(MockSlack, :create_channel, fn "JMP-004-full-recovered-ticket" ->
        {:ok, %{channel_id: "C101", url: "https://slack.com/C101"}}
      end)

      expect(MockNotion, :update_ticket, fn "notion-full-retry",
                                            %{slack_channel: "https://slack.com/C101"} ->
        {:ok,
         %Ticket{
           ticket_id: "JMP-004",
           notion_id: "notion-full-retry",
           slack_channel: "https://slack.com/C101"
         }}
      end)

      expect(MockIntercom, :get_participating_admins, fn "303" ->
        {:ok, [%{name: "AdminFull", email: "adminfull@example.com"}]}
      end)

      expect(MockSlack, :get_all_users, fn ->
        {:ok, [%{id: "U303", name: "AdminFull", email: "adminfull@example.com"}]}
      end)

      expect(MockSlack, :invite_users_to_channel, fn "C101", ["U303"] ->
        {:ok, "invited"}
      end)

      expect(MockSlack, :set_channel_topic, fn "C101", "https://notion.so/JMP-004" ->
        {:ok, "topic set"}
      end)

      retry_all_result =
        Logic.retry_all(result,
          intercom: MockIntercom,
          notion: MockNotion,
          slack: MockSlack,
          llm: MockLLM
        )

      assert retry_all_result.status == :completed
      assert Enum.all?(retry_all_result.steps, fn {_type, step} -> step.status == :completed end)
    end
  end
end
