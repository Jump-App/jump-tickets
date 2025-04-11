defmodule JumpTickets.UserMatcher do
  @moduledoc """
  Matches Intercom admins to Slack users using email and name similarity.
  Uses String.jaro_distance for name matching when emails don't match directly.
  """

  @doc """
  Match Intercom admins to Slack users and return the list of matching Slack user IDs.

  ## Parameters

    - admins: List of Intercom admin maps with "email" and "name" keys
    - slack_users: List of Slack user maps with :id, :name, and :email keys

  ## Returns

    List of Slack user IDs that match the given Intercom admins
  """
  def match_users(admins, slack_users) do
    admins
    |> Enum.map(fn admin -> find_matching_slack_user(admin, slack_users) end)
    |> Enum.filter(&(&1 != nil))
  end

  @doc """
  Find a matching Slack user for a given Intercom admin.
  First tries to match by email, then falls back to name similarity using Jaro distance.

  ## Parameters

    - admin: Map containing Intercom admin data with "email" and "name" keys
    - slack_users: List of Slack user maps with :id, :name, and :email keys

  ## Returns

    Slack user ID if a match is found, nil otherwise
  """
  def find_matching_slack_user(admin, slack_users) do
    # First try exact email match (case insensitive)
    email_match = find_by_email(admin.email, slack_users)

    if email_match do
      email_match
    else
      # If no email match, try name similarity using Jaro distance
      find_by_name_similarity(admin.name, slack_users)
    end
  end

  @doc """
  Find a Slack user by exact email match (case insensitive).

  ## Parameters

    - admin_email: Email string from Intercom admin
    - slack_users: List of Slack user maps

  ## Returns

    Slack user ID if email match is found, nil otherwise
  """
  def find_by_email(nil, _slack_users), do: nil
  def find_by_email(_admin_email, []), do: nil

  def find_by_email(admin_email, slack_users) do
    admin_email = String.downcase(admin_email)

    slack_users
    |> Enum.find(fn user ->
      user.email && String.downcase(user.email) == admin_email
    end)
    |> case do
      nil -> nil
      user -> user.id
    end
  end

  @doc """
  Find a Slack user by name similarity using Jaro distance.

  ## Parameters

    - admin_name: Name string from Intercom admin
    - slack_users: List of Slack user maps

  ## Returns

    Slack user ID for the best match if similarity exceeds threshold, nil otherwise
  """
  def find_by_name_similarity(nil, _slack_users), do: nil
  def find_by_name_similarity(_admin_name, []), do: nil

  def find_by_name_similarity(admin_name, slack_users) do
    # Minimum similarity threshold - adjust as needed
    threshold = 0.75

    slack_users
    |> Enum.map(fn user ->
      similarity =
        String.jaro_distance(
          String.downcase(admin_name),
          String.downcase(user.name)
        )

      {user.id, similarity}
    end)
    |> Enum.max_by(fn {_id, similarity} -> similarity end, fn -> {nil, 0} end)
    |> case do
      {id, similarity} when similarity >= threshold -> id
      _ -> nil
    end
  end
end
