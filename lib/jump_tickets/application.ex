defmodule JumpTickets.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JumpTicketsWeb.Telemetry,
      JumpTickets.Repo,
      {DNSCluster, query: Application.get_env(:jump_tickets, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JumpTickets.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: JumpTickets.Finch},
      # Start a worker by calling: JumpTickets.Worker.start_link(arg)
      # {JumpTickets.Worker, arg},
      # Start to serve requests, typically the last entry
      JumpTicketsWeb.Endpoint,
      JumpTickets.IntegrationRequest.Coordinator
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: JumpTickets.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JumpTicketsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
