defmodule JumpTickets.IntegrationRequest.Logic do
  @moduledoc """
  Core integration request handling and execution.
  """

  require Logger

  alias JumpTickets.IntegrationRequest.Coordinator
  alias JumpTickets.Ticket
  alias JumpTickets.IntegrationRequest.Step
  alias JumpTickets.IntegrationRequest.Request
  alias JumpTickets.UserMatcher

  # Define all possible statuses for steps and the overall request
  @status_types [:pending, :running, :completed, :failed]

  # Define all possible step types
  @step_types [
    :check_existing_tickets,
    :ai_analysis,
    :create_or_update_notion_ticket,
    :maybe_create_slack_channel,
    :maybe_update_notion_with_slack,
    :add_intercom_users_to_slack
  ]
  def step_types(), do: @step_types

  @type step_type ::
          :check_existing_tickets
          | :ai_analysis
          | :create_or_update_notion_ticket
          | :maybe_create_slack_channel
          | :maybe_update_notion_with_slack
          | :add_intercom_users_to_slack

  @type step_status :: :pending | :running | :completed | :failed

  @doc """
  Creates a new integration request with all required steps.
  """
  @spec new(String.t()) :: Request.t()
  def new(%{
        conversation_id: conversation_id,
        conversation_url: conversation_url,
        message_body: message_body
      }) do
    steps =
      @step_types
      |> Enum.map(fn type -> {type, %Step{type: type}} end)
      |> Enum.into(%{})

    %Request{
      intercom_conversation_id: conversation_id,
      intercom_conversation_url: conversation_url,
      message_body: message_body,
      steps: steps,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Runs an integration request through all its steps.
  """
  @spec run(Request.t()) :: Request.t()
  def run(%Request{} = request, opts \\ []) do
    intercom = Keyword.get(opts, :intercom, JumpTickets.External.Intercom)
    notion = Keyword.get(opts, :notion, JumpTickets.External.Notion)
    slack = Keyword.get(opts, :slack, JumpTickets.External.Slack)
    llm = Keyword.get(opts, :llm, JumpTickets.External.LLM)

    # Start with the first step and run through them sequentially
    request = mark_as_running(request)

    Coordinator.broadcast_update(request)

    final_request =
      @step_types
      |> Enum.reduce_while(request, fn step_type, acc ->
        case run_step(acc, step_type, intercom: intercom, notion: notion, slack: slack, llm: llm) do
          {:ok, updated_request} -> {:cont, updated_request}
          {:error, updated_request} -> {:halt, updated_request}
        end
      end)
      |> complete_request()

    Coordinator.broadcast_update(final_request)
    final_request
  end

  # Private functions

  defp run_step(request, step_type, opts) do
    step = get_in(request.steps, [step_type])
    # Skip if any previous step has failed
    cond do
      step.status == :completed ->
        {:ok, request}

      has_failed_steps?(request) ->
        {:error, request}

      true ->
        # Update step status to running
        request =
          update_step(request, step_type, %{
            status: :running,
            started_at: DateTime.utc_now()
          })

        Coordinator.broadcast_update(request)

        # Run the actual integration
        try do
          case execute_step(step_type, request, opts) do
            {:ok, result} ->
              request =
                update_step(request, step_type, %{
                  status: :completed,
                  completed_at: DateTime.utc_now(),
                  result: result
                })

              Coordinator.broadcast_update(request)

              {:ok, request}

            {:error, error} ->
              request =
                update_step(request, step_type, %{
                  status: :failed,
                  completed_at: DateTime.utc_now(),
                  error: error
                })

              Coordinator.broadcast_update(request)

              {:error, request}
          end
        rescue
          e ->
            err_message = Exception.format(:error, e, __STACKTRACE__)

            request =
              update_step(request, step_type, %{
                status: :failed,
                completed_at: DateTime.utc_now(),
                error: err_message
              })

            Coordinator.broadcast_update(request)

            {:error, request}
        end
    end
  end

  defp execute_step(:check_existing_tickets, request, opts) do
    opts[:notion].query_db()
  end

  defp execute_step(
         :ai_analysis,
         %{
           intercom_conversation_id: conversation_id,
           message_body: message_body,
           steps: %{
             check_existing_tickets: %{result: tickets}
           }
         },
         opts
       ) do
    with {:ok, conversation} <- opts[:intercom].get_conversation(conversation_id),
         {:ok, decision} <-
           opts[:llm].find_or_create_ticket(tickets, message_body, conversation) do
      {:ok, decision}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_step(
         :create_or_update_notion_ticket,
         %{
           intercom_conversation_url: conversation_url,
           steps: %{ai_analysis: %{result: {:new, ticket_params}}}
         },
         opts
       ) do
    ticket = %Ticket{
      title: ticket_params.title,
      summary: ticket_params.summary,
      intercom_conversations: conversation_url
    }

    result = opts[:notion].create_ticket(ticket)

    result
  end

  defp execute_step(
         :create_or_update_notion_ticket,
         %{
           intercom_conversation_url: conversation_url,
           steps: %{ai_analysis: %{result: {:existing, existing_ticket}}}
         },
         opts
       ) do
    existing_conversations =
      if is_nil(existing_ticket.intercom_conversations) do
        ""
      else
        existing_ticket.intercom_conversations
      end
      |> String.split(",")
      |> Enum.reject(&(String.length(&1) == 0))

    if conversation_url in existing_conversations do
      {:ok, existing_ticket}
    else
      result =
        opts[:notion].update_ticket(existing_ticket.notion_id, %{
          intercom_conversations: [conversation_url | existing_conversations] |> Enum.join(",")
        })

      result
    end
  end

  defp execute_step(
         :maybe_update_notion_with_slack,
         %{
           steps: %{
             create_or_update_notion_ticket: %{result: %Ticket{notion_id: notion_id}},
             maybe_create_slack_channel: %{result: %{url: slack_url}}
           }
         },
         opts
       ) do
    opts[:notion].update_ticket(notion_id, %{slack_channel: slack_url})
  end

  defp execute_step(
         :maybe_create_slack_channel,
         %{
           steps: %{
             ai_analysis: %{result: {:existing, %Ticket{slack_channel: channel_url}}}
           }
         },
         opts
       ) do
    %URI{path: path} = URI.parse(channel_url)

    channel_id =
      path
      |> String.split("/")
      |> Enum.at(3)

    {:ok, %{channel_id: channel_id, url: channel_url}}
  end

  defp execute_step(
         :maybe_create_slack_channel,
         %{
           steps: %{
             ai_analysis: %{result: {:new, %{slug: ai_generated_slug}}},
             create_or_update_notion_ticket: %{result: %Ticket{ticket_id: ticket_id}}
           }
         },
         opts
       ) do
    channel_name = "#{ticket_id}-#{ai_generated_slug}"
    opts[:slack].create_channel(channel_name)
  end

  defp execute_step(
         :add_intercom_users_to_slack,
         %{
           intercom_conversation_id: conversation_id,
           steps: %{
             ai_analysis: %{result: {:existing, _}},
             maybe_create_slack_channel: %{result: %{channel_id: channel_id}}
           }
         },
         opts
       ) do
    with {:ok, admins} <- opts[:intercom].get_participating_admins(conversation_id),
         {:ok, slack_users} <-
           opts[:slack].get_all_users(),
         {:ok, existing_channel_members} <-
           opts[:slack].list_channel_users(channel_id),
         slack_user_ids <- UserMatcher.match_users(admins, slack_users) do
      existing_channel_members_ids = existing_channel_members |> Enum.map(& &1.id)

      slack_users_ids_to_invite =
        slack_user_ids |> Enum.filter(&(&1 not in existing_channel_members_ids))

      if slack_users_ids_to_invite == [] do
        {:ok, nil}
      else
        {:ok, _} = opts[:slack].invite_users_to_channel(channel_id, slack_user_ids)
        {:ok, nil}
      end

      {:ok, nil}
    end
  end

  defp execute_step(
         :add_intercom_users_to_slack,
         %{
           intercom_conversation_id: conversation_id,
           steps: %{
             create_or_update_notion_ticket: %{result: %Ticket{notion_url: notion_url}},
             maybe_create_slack_channel: %{result: %{channel_id: channel_id}}
           }
         },
         opts
       ) do
    with {:ok, admins} <- opts[:intercom].get_participating_admins(conversation_id),
         {:ok, slack_users} <-
           opts[:slack].get_all_users(),
         slack_user_ids <- UserMatcher.match_users(admins, slack_users),
         {:ok, _} <-
           opts[:slack].invite_users_to_channel(channel_id, slack_user_ids),
         {:ok, channel} <- opts[:slack].set_channel_topic(channel_id, notion_url) do
      {:ok, nil}
    end
  end

  defp execute_step(_, _, _) do
    {:error, :missing_implementation}
  end

  defp mark_as_running(request) do
    %{request | status: :running, updated_at: DateTime.utc_now()}
  end

  defp complete_request(request) do
    new_status = if has_failed_steps?(request), do: :failed, else: :completed

    %{request | status: new_status, updated_at: DateTime.utc_now()}
  end

  defp has_failed_steps?(request) do
    Enum.any?(request.steps, fn {_type, step} -> step.status == :failed end)
  end

  defp update_step(request, step_type, updates) do
    updated_step =
      request.steps[step_type]
      |> Map.merge(Map.new(updates))

    put_in(request.steps[step_type], updated_step)
  end

  @doc """
  Retries a specific step in the integration request.
  """
  @spec retry_step(Request.t(), step_type(), any()) :: Request.t()
  def retry_step(request, step_type, opts \\ []) do
    # Reset the specified step and all subsequent steps
    reset_from_step(request, step_type)
    |> run(opts)
  end

  @doc """
  Retries the entire integration request from the beginning.
  """
  @spec retry_all(Request.t()) :: Request.t()
  def retry_all(request, opts \\ []) do
    # Reset all steps to pending
    %{
      request
      | status: :pending,
        steps:
          Enum.map(request.steps, fn {type, step} ->
            {type,
             %{
               step
               | status: :pending,
                 started_at: nil,
                 completed_at: nil,
                 error: nil,
                 result: nil
             }}
          end)
          |> Enum.into(%{})
    }
    |> run(opts)
  end

  def reset_from_step(request, step_type) do
    # Find the index of the step to reset
    step_index = Enum.find_index(@step_types, &(&1 == step_type))

    # Reset this step and all subsequent steps
    steps =
      @step_types
      |> Enum.with_index()
      |> Enum.reduce(request.steps, fn {type, index}, acc ->
        if index >= step_index do
          Map.update!(acc, type, fn step ->
            %{
              step
              | status: :pending,
                started_at: nil,
                completed_at: nil,
                error: nil,
                result: nil
            }
          end)
        else
          acc
        end
      end)

    %{request | steps: steps, status: :pending}
  end
end
