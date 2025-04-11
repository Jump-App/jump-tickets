defmodule JumpTickets.UserMatcherTest do
  use ExUnit.Case
  alias JumpTickets.UserMatcher

  describe "match_users/2" do
    test "matches users by email" do
      admins = [
        %{email: "user1@example.com", name: "User One"},
        %{email: "user2@example.com", name: "User Two"}
      ]

      slack_users = [
        %{id: "U1", name: "Different Name", email: "user1@example.com"},
        %{id: "U2", name: "User Two", email: "user2@example.com"},
        %{id: "U3", name: "User Three", email: "user3@example.com"}
      ]

      assert UserMatcher.match_users(admins, slack_users) == ["U1", "U2"]
    end

    test "matches on real data" do
      admins = [
        %{name: "Vinícius Misael", type: "admin", email: "vmmmgbapb57@gmail.com"}
      ]

      slack_users = [
        %{id: "USLACKBOT", name: "Slackbot", email: nil},
        %{
          id: "U08HPMYC8GN",
          name: "Vinicius Misael",
          email: "vinicius_gbapb@icloud.com"
        },
        %{id: "U08HYA0CMNF", name: "Ticket Bot", email: nil}
      ]

      assert UserMatcher.match_users(admins, slack_users) == ["U08HPMYC8GN"]
    end

    test "falls back to name matching when email doesn't match" do
      admins = [
        %{email: "nomatch@example.com", name: "John Smith"}
      ]

      slack_users = [
        %{id: "U1", name: "John Smith", email: "different@example.com"},
        %{id: "U2", name: "Jane Doe", email: "jane@example.com"}
      ]

      assert UserMatcher.match_users(admins, slack_users) == ["U1"]
    end

    test "returns empty list when no matches found" do
      admins = [
        %{email: "nomatch@example.com", name: "No Match"}
      ]

      slack_users = [
        %{id: "U1", name: "Completely Different", email: "different@example.com"}
      ]

      assert UserMatcher.match_users(admins, slack_users) == []
    end

    test "handles empty inputs" do
      assert UserMatcher.match_users([], []) == []

      assert UserMatcher.match_users([%{email: "test@example.com", name: "Test"}], []) ==
               []

      assert UserMatcher.match_users([], [%{id: "U1", name: "Test", email: "test@example.com"}]) ==
               []
    end
  end

  describe "find_matching_slack_user/2" do
    test "prioritizes email match over name match" do
      admin = %{email: "user@example.com", name: "Completely Different"}

      slack_users = [
        %{id: "U1", name: "Perfect Name Match", email: "different@example.com"},
        %{id: "U2", name: "No Match", email: "user@example.com"}
      ]

      assert UserMatcher.find_matching_slack_user(admin, slack_users) == "U2"
    end

    test "falls back to name similarity when email doesn't match" do
      admin = %{email: "nomatch@example.com", name: "Robert Johnson"}

      slack_users = [
        %{id: "U1", name: "Rob Johnson", email: "different@example.com"},
        %{id: "U2", name: "Bobby J", email: "bobby@example.com"},
        %{id: "U3", name: "Alice Williams", email: "alice@example.com"}
      ]

      assert UserMatcher.find_matching_slack_user(admin, slack_users) == "U1"
    end

    test "returns nil when no match is found" do
      admin = %{email: "nomatch@example.com", name: "No Match"}

      slack_users = [
        %{id: "U1", name: "Completely Different", email: "different@example.com"}
      ]

      assert UserMatcher.find_matching_slack_user(admin, slack_users) == nil
    end
  end

  describe "find_by_email/2" do
    test "finds user with exact email match" do
      slack_users = [
        %{id: "U1", name: "User One", email: "user1@example.com"},
        %{id: "U2", name: "User Two", email: "user2@example.com"}
      ]

      assert UserMatcher.find_by_email("user1@example.com", slack_users) == "U1"
    end

    test "matches email case-insensitively" do
      slack_users = [
        %{id: "U1", name: "User One", email: "User1@Example.COM"}
      ]

      assert UserMatcher.find_by_email("user1@example.com", slack_users) == "U1"
    end

    test "returns nil when email doesn't match" do
      slack_users = [
        %{id: "U1", name: "User One", email: "user1@example.com"}
      ]

      assert UserMatcher.find_by_email("nomatch@example.com", slack_users) == nil
    end

    test "handles nil email" do
      slack_users = [
        %{id: "U1", name: "User One", email: nil},
        %{id: "U2", name: "User Two", email: "user2@example.com"}
      ]

      assert UserMatcher.find_by_email("user1@example.com", slack_users) == nil
      assert UserMatcher.find_by_email(nil, slack_users) == nil
    end
  end

  describe "find_by_name_similarity/2" do
    test "finds user with similar name" do
      slack_users = [
        %{id: "U1", name: "John Smith", email: "john@example.com"},
        %{id: "U2", name: "Jane Doe", email: "jane@example.com"}
      ]

      assert UserMatcher.find_by_name_similarity("John Smith", slack_users) == "U1"
      assert UserMatcher.find_by_name_similarity("Johnny Smith", slack_users) == "U1"
    end

    test "matches similar names case-insensitively" do
      slack_users = [
        %{id: "U1", name: "JOHN SMITH", email: "john@example.com"}
      ]

      assert UserMatcher.find_by_name_similarity("john smith", slack_users) == "U1"
    end

    test "returns highest similarity match" do
      slack_users = [
        %{id: "U1", name: "John S", email: "john@example.com"},
        %{id: "U2", name: "John Smith", email: "john.smith@example.com"},
        %{id: "U3", name: "J Smith", email: "jsmith@example.com"}
      ]

      assert UserMatcher.find_by_name_similarity("John Smith", slack_users) == "U2"
    end

    test "returns nil when similarity is below threshold" do
      slack_users = [
        %{id: "U1", name: "Completely Different", email: "diff@example.com"}
      ]

      assert UserMatcher.find_by_name_similarity("John Smith", slack_users) == nil
    end

    test "handles nil name" do
      slack_users = [
        %{id: "U1", name: "John Smith", email: "john@example.com"}
      ]

      assert UserMatcher.find_by_name_similarity(nil, slack_users) == nil
    end

    test "handles empty slack users list" do
      assert UserMatcher.find_by_name_similarity("John Smith", []) == nil
    end
  end

  # Real-world scenario test
  test "matches user from the provided example" do
    admins = [
      %{
        email: "vmmmgbapb57@gmail.com",
        name: "Vinícius Misael"
      }
    ]

    slack_users = [
      %{id: "USLACKBOT", name: "Slackbot", email: nil},
      %{id: "U08HPMYC8GN", name: "Vinicius", email: "vmmmgbapb57@gmail.com"},
      %{id: "U08HYA0CMNF", name: "Ticket Bot", email: nil}
    ]

    assert UserMatcher.match_users(admins, slack_users) == ["U08HPMYC8GN"]
  end

  test "matches by name when email is missing" do
    admins = [
      %{
        email: nil,
        name: "Vinícius Misael"
      }
    ]

    slack_users = [
      %{id: "USLACKBOT", name: "Slackbot", email: nil},
      %{id: "U08HPMYC8GN", name: "Vinicius Misael", email: nil},
      %{id: "U08HYA0CMNF", name: "Ticket Bot", email: nil}
    ]

    assert UserMatcher.match_users(admins, slack_users) == ["U08HPMYC8GN"]
  end
end
