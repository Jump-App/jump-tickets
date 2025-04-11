defmodule JumpTickets.External.Slack do
  @moduledoc """
  Handles Slack integration functionality
  """

  require Logger

  alias JumpTickets.External.Slack.Client

  @slack_api_url "https://slack.com/api"

  def get_slack_token do
    Application.get_env(:jump_tickets, :slack)[:bot_token]
  end

  @doc """
  Creates a new Slack channel with the given name
  """
  def create_channel(channel_name) do
    # Normalize channel name (lowercase, no spaces, only alphanumeric and hyphens)
    normalized_name =
      channel_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\-]/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    body = %{
      name: normalized_name,
      is_private: false
    }

    case Client.post("/conversations.create", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => "name_taken"}}} ->
        get_channel(channel_name)

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true, "channel" => channel}}} ->
        {:ok,
         %{
           channel_id: channel["id"],
           url:
             "https://app.slack.com/client/#{channel["context_team_id"]}/#{channel["id"]}?entry_point=nav_menu"
         }}

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to create Slack channel: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when creating Slack channel: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sets the topic of the given channel
  """
  def set_channel_topic(channel_id, topic) do
    body = %{
      channel: channel_id,
      topic: topic
    }

    case Client.post("/conversations.setTopic", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true} = response}} ->
        {:ok, response}

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to set channel topic: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when setting channel topic: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets all users from Slack
  """
  def get_all_users do
    case Client.get("/users.list") do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true, "members" => members}}} ->
        users =
          members
          |> Enum.map(
            &%{
              id: &1["id"],
              name: &1["real_name"],
              email: get_in(&1, ["profile", "email"])
            }
          )

        {:ok, users}

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to get Slack users: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when getting Slack users: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Invites users to a channel
  """
  def invite_users_to_channel(channel_id, user_ids) when is_list(user_ids) do
    # Slack API requires at least one user and no more than 1000
    user_ids = user_ids |> Enum.uniq() |> Enum.take(1000)

    # Skip if no users to invite
    if Enum.empty?(user_ids) do
      {:ok, "No users to invite"}
    else
      body = %{
        channel: channel_id,
        users: Enum.join(user_ids, ",")
      }

      case Client.post("/conversations.invite", body) do
        {:ok, %Tesla.Env{status: 200, body: %{"ok" => true} = response}} ->
          {:ok, response}

        {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
          Logger.error("Failed to invite users to channel: #{error}")
          {:error, error}

        {:error, reason} ->
          Logger.error("HTTP error when inviting users to channel: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Posts a message to a channel
  """
  def post_message(channel_id, text) do
    body = %{
      channel: channel_id,
      text: text
    }

    case Client.post("/chat.postMessage", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true} = response}} ->
        {:ok, response}

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to post message: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when posting message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets a channel by its name
  """
  def get_channel(channel_name) do
    # Normalize channel name to match Slack's format
    normalized_name =
      channel_name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\-]/, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")

    params = %{
      types: "public_channel",
      limit: "1000"
    }

    case Client.get("/conversations.list", query: params) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true, "channels" => channels}}} ->
        # Find the channel with matching name
        channel =
          Enum.find(channels, fn channel ->
            channel["name"] == normalized_name
          end)

        if channel do
          team_id =
            channel["context_team_id"] || Application.get_env(:jump_tickets, :slack)[:team_id]

          {:ok,
           %{
             channel_id: channel["id"],
             url: "https://app.slack.com/client/#{team_id}/#{channel["id"]}?entry_point=nav_menu"
           }}
        else
          {:error, :channel_not_found}
        end

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to get Slack channels: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when getting Slack channels: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Lists users in a given Slack channel.

  Returns a list of users in the format:
  %{
    id: user["id"],
    name: user["real_name"],
    email: get_in(user, ["profile", "email"])
  }
  """
  def list_channel_users(channel_id) do
    params = %{channel: channel_id}

    case Client.get("/conversations.members", query: params) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true, "members" => member_ids}}} ->
        # Retrieve all users and filter by member IDs.
        case get_all_users() do
          {:ok, users} ->
            channel_users =
              users
              |> Enum.filter(fn user -> user[:id] in member_ids end)

            {:ok, channel_users}

          {:error, error} ->
            {:error, error}
        end

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to list channel users: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when listing channel users: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sets the topic of the given channel
  """
  def set_topic(channel_id, topic) do
    body = %{
      channel: channel_id,
      topic: topic
    }

    case Client.post("/conversations.setTopic", body) do
      {:ok, %Tesla.Env{status: 200, body: %{"ok" => true} = response}} ->
        {:ok, response}

      {:ok, %Tesla.Env{status: 200, body: %{"ok" => false, "error" => error}}} ->
        Logger.error("Failed to set channel topic: #{error}")
        {:error, error}

      {:error, reason} ->
        Logger.error("HTTP error when setting channel topic: #{inspect(reason)}")
        {:error, reason}
    end
  end
end

defmodule JumpTickets.External.Slack.Client do
  @moduledoc """
  Tesla HTTP client for Slack API
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://slack.com/api"

  plug Tesla.Middleware.Headers, [
    {"Content-Type", "application/json; charset=utf-8"}
  ]

  plug Tesla.Middleware.JSON
  plug Tesla.Middleware.BearerAuth, token: get_token()

  plug Tesla.Middleware.Retry,
    delay: 60_000,
    max_retries: 8,
    max_delay: 180_000,
    should_retry: fn
      {:ok, %{status: 429}} ->
        true

      {:ok, %{status: 200, body: %{"ok" => false, "error" => "ratelimited"}}} ->
        true

      {:error, reason} ->
        true

      _other ->
        false
    end

  plug Tesla.Middleware.Logger

  defp get_token do
    Application.get_env(:jump_tickets, :slack)[:bot_token]
  end
end
