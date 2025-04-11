defmodule JumpTickets.External.SlackBehaviour do
  @callback create_channel(String.t()) :: {:ok, map()} | {:error, String.t()}
  @callback get_all_users() :: {:ok, [map()]} | {:error, String.t()}
  @callback invite_users_to_channel(String.t(), [String.t()]) ::
              {:ok, map()} | {:error, String.t()}
  @callback set_channel_topic(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  @callback list_channel_users(String.t()) :: {:ok, [map()]} | {:error, String.t()}
end
