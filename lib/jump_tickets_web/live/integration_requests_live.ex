defmodule JumpTicketsWeb.IntegrationRequestsLive do
  alias JumpTickets.IntegrationRequest
  alias JumpTickets.IntegrationRequest.Logic
  use JumpTicketsWeb, :live_view

  alias JumpTickets.IntegrationRequest.Coordinator
  alias JumpTickets.IntegrationRequest.Request
  alias JumpTickets.Ticket

  @impl true
  def mount(_, _, socket) do
    if connected?(socket) do
      Coordinator.subscribe()
    end

    socket =
      socket
      |> assign(
        :integration_requests,
        Coordinator.list_requests()
        |> Enum.sort_by(& &1.created_at, NaiveDateTime)
        |> Enum.reverse()
      )
      |> assign_stats()

    {:ok, socket}
  end

  def integration_request(assigns) do
    ~H"""
    <div class="overflow-hidden rounded-lg bg-gray-800 shadow-lg">
      <%!-- border-green-500 border-red-500 border-blue-500 --%>
      <div class={[
        "border-l-4  px-6 py-4",
        get_status_border(@integration_request.status)
      ]}>
        <div class="flex items-center justify-between">
          <div>
            <.card_title integration_request={@integration_request} />

            <div class="mt-1 flex items-center text-sm text-gray-400">
              <span class="mr-4">
                <i class="far fa-clock mr-1"></i>{Calendar.strftime(
                  @integration_request.created_at,
                  "%a, %B %d %Y - %I:%M:%S %p"
                )}
              </span>

              <span class="mr-4">
                <a
                  href={@integration_request.intercom_conversation_url}
                  target="_blank"
                  class="text-sm text-indigo-400 hover:text-indigo-300"
                >
                  View in Intercom <i class="fas fa-external-link-alt ml-1 text-xs"></i>
                </a>
              </span>

              <.status_pill status={@integration_request.status} />
            </div>
          </div>
        </div>
      </div>
      
    <!-- Integration Steps -->

      <div class="border-t border-gray-700 px-6 py-3">
        <div class="mb-2 flex items-center">
          <h4 class="font-medium text-white">Integration Steps</h4>

          <span
            :if={@integration_request.status == :completed}
            class="ml-2 rounded-full bg-gray-700 px-2 py-0.5 text-xs"
          >
            Completed in {step_duration(%{
              started_at: @integration_request.created_at,
              completed_at: @integration_request.steps.add_intercom_users_to_slack.completed_at
            })}s
          </span>
        </div>

        <div class="mt-4 flex flex-col space-y-4">
          <.step
            :for={step_key <- Logic.step_types()}
            key={step_key}
            request_id={@integration_request.id}
            step={@integration_request.steps[step_key]}
          />
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_info({:integration_request_updated, %Request{id: id} = request}, socket) do
    integration_requests = socket.assigns.integration_requests
    existing = Enum.find_index(integration_requests, &(&1.id == id))

    if existing == nil do
      integration_requests =
        [request | integration_requests]
        |> Enum.sort_by(& &1.created_at, NaiveDateTime)
        |> Enum.reverse()

      {:noreply, assign(socket, :integration_requests, integration_requests) |> assign_stats()}
    else
      integration_requests =
        integration_requests
        |> List.update_at(existing, fn _ -> request end)
        |> Enum.sort_by(& &1.created_at, NaiveDateTime)
        |> Enum.reverse()

      {:noreply, assign(socket, :integration_requests, integration_requests) |> assign_stats()}
    end
  end

  @impl true
  def handle_event("retry-step", %{"request-id" => request_id, "step" => step}, socket) do
    step = String.to_existing_atom(step)
    IntegrationRequest.retry_step(request_id, step)

    {:noreply, socket}
  end

  defp card_title(
         %{
           integration_request: %{
             steps: %{
               create_or_update_notion_ticket: %{
                 result: %Ticket{ticket_id: ticket_id, title: title}
               }
             }
           }
         } = assigns
       ) do
    assigns =
      assigns
      |> assign(:ticket_id, ticket_id)
      |> assign(:title, title)

    ~H"""
    <h3 class="text-lg font-semibold text-white">
      #{@ticket_id} - {@title}
    </h3>
    """
  end

  defp card_title(assigns) do
    ~H"""
    <h3 class={[
      "text-lg font-semibold text-gray-400",
      if @integration_request.status == :running do
        "animate-pulse"
      end
    ]}>
      Ticket not created/found yet...
    </h3>
    """
  end

  defp status_pill(%{status: :completed} = assigns),
    do: ~H"""
    <span class="rounded-md bg-green-900 px-2 py-0.5 text-green-300">
      Completed
    </span>
    """

  defp status_pill(%{status: :pending} = assigns),
    do: ~H"""
    <span class="rounded-md bg-yellow-900 px-2 py-0.5 text-yellow-300">
      Enqueued
    </span>
    """

  defp status_pill(%{status: :failed} = assigns),
    do: ~H"""
    <span class="rounded-md bg-red-900 px-2 py-0.5 text-red-300">Failed</span>
    """

  defp status_pill(%{status: :running} = assigns),
    do: ~H"""
    <span class="rounded-md bg-blue-900 px-2 py-0.5 text-blue-300">
      In Progress
    </span>
    """

  defp get_status_border(:pending), do: "border-yellow-500"
  defp get_status_border(:completed), do: "border-green-500"
  defp get_status_border(:running), do: "border-blue-500"
  defp get_status_border(:failed), do: "border-red-500"

  defp step_icon(%{status: :completed} = assigns) do
    ~H"""
    <div class="flex h-8 w-8 items-center justify-center rounded-full bg-green-900">
      <i class="fas fa-check text-green-400"></i>
    </div>
    """
  end

  defp step_icon(%{status: :failed} = assigns) do
    ~H"""
    <div class="flex h-8 w-8 items-center justify-center rounded-full bg-red-900">
      <i class="fas fa-times text-red-400"></i>
    </div>
    """
  end

  defp step_icon(%{status: :pending} = assigns) do
    ~H"""
    <div class="flex h-8 w-8 items-center justify-center rounded-full bg-gray-700">
      <i class="fas fa-clock text-gray-400"></i>
    </div>
    """
  end

  defp step_icon(%{status: :running} = assigns) do
    ~H"""
    <div class="flex h-8 w-8 items-center justify-center rounded-full bg-blue-900">
      <i class="fas fa-spinner fa-spin text-blue-400"></i>
    </div>
    """
  end

  defp error_details(assigns) do
    assigns = assign(assigns, :error, safe_error_message(assigns[:error]))

    ~H"""
    <div class="custom-scrollbar mt-2 max-h-40 overflow-y-auto overflow-x-hidden rounded-lg bg-gray-900 p-3">
      <code class="font-mono text-sm text-red-400">
        {@error}
      </code>
    </div>
    """
  end

  defp step(%{key: key, step: step} = assigns),
    do: ~H"""
    <div class="flex items-center">
      <div class="relative">
        <.step_icon status={@step.status} />
      </div>

      <div class="ml-4 flex-1 flex-col">
        <div class="flex items-start justify-between">
          <div>
            <h5 class="font-medium text-white">{get_step_title(@key)}</h5>

            <p class="text-sm text-gray-400">
              {get_step_subtitle(@key, @step)}
            </p>
          </div>

          <div class="flex gap-4 items-center">
            <span
              :if={@step.started_at != nil and @step.completed_at != nil}
              class="text-xs text-gray-500"
            >
              {step_duration(@step)}s
            </span>
            <button
              :if={@step.status == :failed}
              phx-click="retry-step"
              phx-throttle="500"
              phx-value-request-id={@request_id}
              phx-value-step={@key}
              class="rounded-md bg-gray-700 px-3 py-1 text-sm hover:bg-gray-600"
            >
              Retry Step
            </button>
          </div>
        </div>

        <.error_details :if={step.status == :failed} error={@step.error} />
      </div>
    </div>
    """

  defp get_step_title(:check_existing_tickets), do: "Check Existing Tickets"
  defp get_step_title(:ai_analysis), do: "AI Analysis"
  defp get_step_title(:create_or_update_notion_ticket), do: "Create/Update Notion Ticket"
  defp get_step_title(:maybe_create_slack_channel), do: "Create Slack Channel"
  defp get_step_title(:maybe_update_notion_with_slack), do: "Update Ticket With Channel"
  defp get_step_title(:add_intercom_users_to_slack), do: "Invite Slack Users"

  defp get_step_subtitle(:check_existing_tickets, %{status: :completed, result: tickets} = step),
    do: "Retrieved #{Enum.count(tickets)} ticket(s) from Notion Database"

  defp get_step_subtitle(:check_existing_tickets, %{status: :failed} = step),
    do: "Failed To Retrieve Tickets"

  defp get_step_subtitle(:check_existing_tickets, %{status: :running} = step),
    do: "Waiting on response"

  defp get_step_subtitle(:ai_analysis, _), do: ""

  defp get_step_subtitle(
         :create_or_update_notion_ticket,
         %{status: :completed, result: ticket} = step
       ),
       do: "#{ticket.ticket_id} created with AI-generated title"

  defp get_step_subtitle(
         :maybe_create_slack_channel,
         %{status: :completed, result: %{url: url}} = step
       ) do
    assigns = %{url: url}

    ~H"""
    <a href={@url} target="_blank" class="text-sm text-indigo-400 hover:text-indigo-300">
      View in Slack <i class="fas fa-external-link-alt ml-1 text-xs"></i>
    </a>
    """
  end

  defp get_step_subtitle(:maybe_update_notion_with_slack, _), do: "Update Ticket With Channel"
  defp get_step_subtitle(:add_intercom_users_to_slack, _), do: "Invite Slack Users"

  defp get_step_subtitle(_, %{status: :running}), do: "Waiting on response..."
  defp get_step_subtitle(_, %{status: :pending}), do: "Waiting to start..."
  defp get_step_subtitle(_, %{status: :failed}), do: "Failed"
  defp get_step_subtitle(_, %{status: :completed}), do: ""

  defp get_step_title(_) do
    "Unknown"
  end

  defp safe_error_message(value) do
    if Phoenix.HTML.Safe.impl_for(value) do
      value
    else
      "Unknown error"
    end
  end

  defp step_duration(%{started_at: started_at, completed_at: completed_at}) do
    DateTime.diff(completed_at, started_at, :second)
  end

  defp assign_stats(socket) do
    socket
    |> assign(
      :completed_count,
      socket.assigns.integration_requests
      |> Enum.count(&(&1.status == :completed))
    )
    |> assign(
      :pending_count,
      socket.assigns.integration_requests |> Enum.count(&(&1.status == :pending))
    )
    |> assign(
      :failed_count,
      socket.assigns.integration_requests |> Enum.count(&(&1.status == :failed))
    )
    |> assign(
      :running_count,
      socket.assigns.integration_requests |> Enum.count(&(&1.status == :running))
    )
  end
end
