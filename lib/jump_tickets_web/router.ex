defmodule JumpTicketsWeb.Router do
  use JumpTicketsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JumpTicketsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :basic_auth do
    plug :auth
  end

  scope "/", JumpTicketsWeb do
    pipe_through [:browser, :basic_auth]

    get "/", PageController, :home
    live "/integration_requests", IntegrationRequestsLive
  end

  scope "/webhooks", JumpTicketsWeb do
    pipe_through :api

    post "/notion/ticket_done", TicketDoneController, :notion_webhook
  end

  # Other scopes may use custom stacks.
  scope "/api", JumpTicketsWeb do
    pipe_through :api

    post "/initialize", IntercomController, :initialize
    post "/submit", IntercomController, :submit
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:jump_tickets, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: JumpTicketsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  defp auth(conn, _opts) do
    username = System.fetch_env!("AUTH_USERNAME")
    password = System.fetch_env!("AUTH_PASSWORD")
    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
