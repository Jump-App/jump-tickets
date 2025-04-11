defmodule JumpTickets.External.IntercomBehaviour do
  @callback get_conversation(String.t()) :: {:ok, map()} | {:error, String.t()}
  @callback get_participating_admins(String.t()) :: {:ok, [map()]} | {:error, String.t()}
end
