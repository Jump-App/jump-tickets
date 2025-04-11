defmodule JumpTickets.IntegrationRequest.Coordinator do
  @moduledoc """
  Coordinates the execution of integration requests, ensuring only one runs at a time.
  Provides management of request queues and broadcasts status updates via Phoenix channels.
  """
  use GenServer
  require Logger
  alias JumpTickets.IntegrationRequest.Logic
  alias JumpTickets.IntegrationRequest.Request
  alias Phoenix.PubSub

  @pubsub_topic "integration_request_updates"

  # Client API

  @doc """
  Starts the coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new integration request and adds it to the queue.
  """
  @spec create_request(map()) :: {:ok, String.t()} | {:error, term()}
  def create_request(params) do
    GenServer.call(__MODULE__, {:create_request, params})
  end

  @doc """
  Retrieves all integration requests.
  """
  @spec list_requests() :: [Request.t()]
  def list_requests do
    GenServer.call(__MODULE__, :list_requests)
  end

  @doc """
  Retrieves a specific integration request by ID.
  """
  @spec get_request(String.t()) :: {:ok, Request.t()} | {:error, :not_found}
  def get_request(id) do
    GenServer.call(__MODULE__, {:get_request, id})
  end

  @doc """
  Retries a specific step in an integration request.
  The request will be enqueued if another request is currently running.
  """
  @spec retry_step(String.t(), Logic.step_type()) ::
          {:ok, Request.t()} | {:error, :not_found | :request_running}
  def retry_step(id, step_type) do
    GenServer.call(__MODULE__, {:retry_step, id, step_type})
  end

  @doc """
  Retries an entire integration request from the beginning.
  The request will be enqueued if another request is currently running.
  """
  @spec retry_request(String.t()) :: {:ok, Request.t()} | {:error, :not_found | :request_running}
  def retry_request(id) do
    GenServer.call(__MODULE__, {:retry_request, id})
  end

  @doc """
  Cancels a pending integration request.
  Cannot cancel requests that are already running.
  """
  @spec cancel_request(String.t()) :: {:ok, Request.t()} | {:error, :not_found | :request_running}
  def cancel_request(id) do
    GenServer.call(__MODULE__, {:cancel_request, id})
  end

  @doc """
  Broadcasts an update for a specific integration request.
  This is to be used by the IntegrationRequest module when steps are updated.
  """
  @spec broadcast_update(Request.t()) :: :ok
  def broadcast_update(%Request{} = request) do
    PubSub.broadcast(
      JumpTickets.PubSub,
      @pubsub_topic,
      {:integration_request_updated, request}
    )

    :ok
  end

  @doc """
  Subscribe to integration request updates.
  """
  @spec subscribe() :: :ok
  def subscribe do
    PubSub.subscribe(JumpTickets.PubSub, @pubsub_topic)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      # Map of request_id => request
      requests: %{},
      # List of request_ids in order of submission
      queue: [],
      # Currently running request_id, if any
      current: nil
    }

    # Restore state from persistence if implemented
    # state = restore_state() || state
    subscribe()

    {:ok, state}
  end

  @impl true
  def handle_call({:create_request, params}, _from, state) do
    request = Logic.new(params)
    request_id = generate_id()
    request = %{request | id: request_id}

    # Add to requests map and queue
    state = %{
      state
      | requests: Map.put(state.requests, request_id, request),
        queue: state.queue ++ [request_id]
    }

    broadcast_update(request)

    # Start processing the queue if nothing is currently running
    state = maybe_process_next(state)

    {:reply, {:ok, request_id}, state}
  end

  @impl true
  def handle_call(:list_requests, _from, state) do
    requests = Map.values(state.requests)
    {:reply, requests, state}
  end

  @impl true
  def handle_call({:get_request, id}, _from, state) do
    case Map.fetch(state.requests, id) do
      {:ok, request} -> {:reply, {:ok, request}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:retry_step, id, step_type}, _from, state) do
    with {:ok, request} <- Map.fetch(state.requests, id),
         false <- request.id == state.current && request.status == :running do
      # Remove from queue if it's there (could be pending)
      state = %{state | queue: Enum.reject(state.queue, &(&1 == id))}

      # Reset the request step but don't run it yet, just add to queue
      reset_request = Logic.reset_from_step(request, step_type)

      state = %{
        state
        | requests: Map.put(state.requests, id, reset_request),
          queue: state.queue ++ [id]
      }

      broadcast_update(reset_request)

      # Try to process the next item if nothing is currently running
      state = maybe_process_next(state)

      {:reply, {:ok, reset_request}, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      true -> {:reply, {:error, :request_running}, state}
    end
  end

  @impl true
  def handle_call({:retry_request, id}, _from, state) do
    with {:ok, request} <- Map.fetch(state.requests, id),
         false <- request.id == state.current && request.status == :running do
      # Remove from queue if it's there
      state = %{state | queue: Enum.reject(state.queue, &(&1 == id))}

      # Reset the entire request but don't run it yet, just add to queue
      reset_request = %{
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

      state = %{
        state
        | requests: Map.put(state.requests, id, reset_request),
          queue: state.queue ++ [id]
      }

      broadcast_update(reset_request)

      # Try to process the next item if nothing is currently running
      state = maybe_process_next(state)

      {:reply, {:ok, reset_request}, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      true -> {:reply, {:error, :request_running}, state}
    end
  end

  @impl true
  def handle_call({:cancel_request, id}, _from, state) do
    with {:ok, request} <- Map.fetch(state.requests, id),
         false <- request.id == state.current && request.status == :running do
      # Remove from queue if it's there
      state = %{state | queue: Enum.reject(state.queue, &(&1 == id))}

      # Mark as cancelled
      cancelled_request = %{request | status: :cancelled, updated_at: DateTime.utc_now()}

      state = %{state | requests: Map.put(state.requests, id, cancelled_request)}

      broadcast_update(cancelled_request)

      {:reply, {:ok, cancelled_request}, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      true -> {:reply, {:error, :request_running}, state}
    end
  end

  @impl true
  def handle_info({:integration_request_updated, %Request{id: id} = request}, state) do
    # Update our local state with the latest request data
    state = %{state | requests: Map.put(state.requests, id, request)}

    # If this is the current request and it's completed or failed, mark it as done
    if id == state.current && (request.status == :completed || request.status == :failed) do
      Logger.info("Integration request #{id} completed with status: #{request.status}")
      state = %{state | current: nil}
      # Try to process the next request in queue
      state = maybe_process_next(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # Private Functions

  # Update the maybe_process_next function to not use the request_completed message
  defp maybe_process_next(state) do
    if state.current == nil && length(state.queue) > 0 do
      # Get the next request ID from the queue
      [next_id | remaining_queue] = state.queue
      request = state.requests[next_id]

      # Start processing it in a separate task
      Task.start(fn ->
        # Run the request - all updates will be broadcasted through PubSub
        Logic.run(request)
        # No need to send completion message as we'll get it via PubSub updates
      end)

      # Update state to mark this request as current and remove it from queue
      %{state | current: next_id, queue: remaining_queue}
    else
      state
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
  end
end

# JumpTickets.IntegrationRequest.create_integration_request(%{conversation_id: "2",conversation_url: "https://test.com",message_body: "What is happening?"})
