defmodule JumpTicketsWeb.PageController do
  use JumpTicketsWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/integration_requests")
  end
end
