defmodule JumpTickets.External.Notion.ParserTest do
  use ExUnit.Case, async: true
  alias JumpTickets.External.Notion.Parser
  alias JumpTickets.Ticket
  alias Notionex.Object.List

  describe "parse_response/1" do
    test "successfully parses a valid Notion response" do
      response = %List{
        results: [
          %{
            "properties" => %{
              "ID" => %{"unique_id" => %{"number" => "123", "prefix" => "JMP"}},
              "Title" => %{
                "title" => [
                  %{"plain_text" => "Test Ticket"}
                ]
              },
              "Intercom Conversations" => %{
                "rich_text" => [
                  %{"plain_text" => "conv-123"}
                ]
              },
              "children" => %{
                "rich_text" => [
                  %{"plain_text" => "Test summary"}
                ]
              },
              "Slack Channel" => %{
                "rich_text" => [
                  %{"plain_text" => "#test-channel"}
                ]
              }
            }
          }
        ]
      }

      [result] = Parser.parse_response(response)

      assert %Ticket{} = result
      assert result.ticket_id == "JMP-123"
      assert result.title == "Test Ticket"
      assert result.intercom_conversations == "conv-123"
      assert result.summary == "Test summary"
      assert result.slack_channel == "#test-channel"
    end

    test "handles empty response list" do
      response = %List{results: []}
      assert [] = Parser.parse_response(response)
    end

    test "returns error for invalid response format" do
      invalid_response = %{foo: "bar"}
      assert {:error, "Invalid response format"} = Parser.parse_response(invalid_response)
    end

    test "handles missing properties" do
      response = %List{
        results: [
          %{
            "properties" => %{
              "ID" => %{"unique_id" => %{"number" => "123", "prefix" => "JMP"}},
              "Title" => %{
                "title" => [
                  %{"plain_text" => "Test Ticket"}
                ]
              }
            }
          }
        ]
      }

      [result] = Parser.parse_response(response)

      assert %Ticket{} = result
      assert result.ticket_id == "JMP-123"
      assert result.title == "Test Ticket"
      assert result.intercom_conversations == nil
      assert result.summary == nil
      assert result.slack_channel == nil
    end

    test "parses multiple tickets" do
      response = %List{
        results: [
          %{
            "archived" => false,
            "cover" => nil,
            "created_by" => %{
              "id" => "936c8b81-c8b3-4fd7-804b-2abe165b4a65",
              "object" => "user"
            },
            "created_time" => "2025-03-17T02:29:00.000Z",
            "icon" => nil,
            "id" => "1b9d3c1b-90d3-811c-a25c-f1666f655e60",
            "in_trash" => false,
            "last_edited_by" => %{
              "id" => "936c8b81-c8b3-4fd7-804b-2abe165b4a65",
              "object" => "user"
            },
            "last_edited_time" => "2025-03-17T02:29:00.000Z",
            "object" => "page",
            "parent" => %{
              "database_id" => "1b7d3c1b-90d3-806a-8e42-ef7d903589cb",
              "type" => "database_id"
            },
            "properties" => %{
              "Done" => %{"checkbox" => false, "id" => "s%3DSw", "type" => "checkbox"},
              "ID" => %{
                "id" => "~rjk",
                "type" => "unique_id",
                "unique_id" => %{"number" => 42, "prefix" => "JMP"}
              },
              "Intercom Conversations" => %{
                "id" => "DRly",
                "rich_text" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" =>
                      "https://app.intercom.com/a/inbox/j3d3b7en/inbox/shared/all/conversation/3",
                    "text" => %{
                      "content" =>
                        "https://app.intercom.com/a/inbox/j3d3b7en/inbox/shared/all/conversation/3",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "rich_text"
              },
              "Slack Channel" => %{
                "id" => "b~en",
                "rich_text" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" =>
                      "https://app.slack.com/client/T08HPMYC8G6/C08J0TUA69H?entry_point=nav_menu",
                    "text" => %{
                      "content" =>
                        "https://app.slack.com/client/T08HPMYC8G6/C08J0TUA69H?entry_point=nav_menu",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "rich_text"
              },
              "Title" => %{
                "id" => "title",
                "title" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" => "Intercom Support Inbox Demo Email Test",
                    "text" => %{
                      "content" => "Intercom Support Inbox Demo Email Test",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "title"
              }
            },
            "public_url" => nil,
            "url" =>
              "https://www.notion.so/Intercom-Support-Inbox-Demo-Email-Test-1b9d3c1b90d3811ca25cf1666f655e60"
          },
          %{
            "archived" => false,
            "cover" => nil,
            "created_by" => %{
              "id" => "936c8b81-c8b3-4fd7-804b-2abe165b4a65",
              "object" => "user"
            },
            "created_time" => "2025-03-17T02:23:00.000Z",
            "icon" => nil,
            "id" => "1b9d3c1b-90d3-8169-96b2-e6eba6399d74",
            "in_trash" => false,
            "last_edited_by" => %{
              "id" => "936c8b81-c8b3-4fd7-804b-2abe165b4a65",
              "object" => "user"
            },
            "last_edited_time" => "2025-03-17T04:33:00.000Z",
            "object" => "page",
            "parent" => %{
              "database_id" => "1b7d3c1b-90d3-806a-8e42-ef7d903589cb",
              "type" => "database_id"
            },
            "properties" => %{
              "Done" => %{"checkbox" => false, "id" => "s%3DSw", "type" => "checkbox"},
              "ID" => %{
                "id" => "~rjk",
                "type" => "unique_id",
                "unique_id" => %{"number" => 41, "prefix" => "JMP"}
              },
              "Intercom Conversations" => %{
                "id" => "DRly",
                "rich_text" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" =>
                      "https://test.com,https://example.com,https://app.intercom.com/a/inbox/j3d3b7en/inbox/shared/all/conversation/2",
                    "text" => %{
                      "content" =>
                        "https://test.com,https://example.com,https://app.intercom.com/a/inbox/j3d3b7en/inbox/shared/all/conversation/2",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "rich_text"
              },
              "Slack Channel" => %{
                "id" => "b~en",
                "rich_text" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" =>
                      "https://app.slack.com/client/T08HPMYC8G6/C08J9CK1DK3?entry_point=nav_menu",
                    "text" => %{
                      "content" =>
                        "https://app.slack.com/client/T08HPMYC8G6/C08J9CK1DK3?entry_point=nav_menu",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "rich_text"
              },
              "Title" => %{
                "id" => "title",
                "title" => [
                  %{
                    "annotations" => %{
                      "bold" => false,
                      "code" => false,
                      "color" => "default",
                      "italic" => false,
                      "strikethrough" => false,
                      "underline" => false
                    },
                    "href" => nil,
                    "plain_text" =>
                      "Setup Guidance Needed for WhatsApp and Social Media Channels",
                    "text" => %{
                      "content" => "Setup Guidance Needed for WhatsApp and Social Media Channels",
                      "link" => nil
                    },
                    "type" => "text"
                  }
                ],
                "type" => "title"
              }
            },
            "public_url" => nil,
            "url" =>
              "https://www.notion.so/Setup-Guidance-Needed-for-WhatsApp-and-Social-Media-Channels-1b9d3c1b90d3816996b2e6eba6399d74"
          }
        ],
        has_more: false,
        next_cursor: nil,
        page_or_database: %{}
      }

      result = Parser.parse_response(response)
      [first, second] = result

      assert first.ticket_id == "JMP-42"
      assert first.title == "Intercom Support Inbox Demo Email Test"
      assert second.ticket_id == "JMP-41"
      assert second.title == "Setup Guidance Needed for WhatsApp and Social Media Channels"
    end
  end

  describe "parse_ticket_page" do
    test "handles ticket page" do
      page = %{
        "archived" => false,
        "cover" => nil,
        "created_by" => %{
          "id" => "936c8b81-c8b3-4fd7-804b-2abe165b4a65",
          "object" => "user"
        },
        "created_time" => "2025-03-15T21:10:00.000Z",
        "icon" => nil,
        "id" => "1b7d3c1b-90d3-81c2-a83f-f57f0328a4e6",
        "in_trash" => false,
        "last_edited_by" => %{
          "id" => "d8b149e2-2698-49ac-8ff7-456b53c415f0",
          "object" => "user"
        },
        "last_edited_time" => "2025-03-15T21:10:00.000Z",
        "object" => "page",
        "parent" => %{
          "database_id" => "1b7d3c1b-90d3-806a-8e42-ef7d903589cb",
          "type" => "database_id"
        },
        "properties" => %{
          "ID" => %{
            "id" => "~rjk",
            "type" => "unique_id",
            "unique_id" => %{"number" => 7, "prefix" => "JMP"}
          },
          "Intercom Conversations" => %{
            "id" => "DRly",
            "rich_text" => [
              %{
                "annotations" => %{
                  "bold" => false,
                  "code" => false,
                  "color" => "default",
                  "italic" => false,
                  "strikethrough" => false,
                  "underline" => false
                },
                "href" => nil,
                "plain_text" => "teste,teste,teste",
                "text" => %{"content" => "teste,teste,teste", "link" => nil},
                "type" => "text"
              }
            ],
            "type" => "rich_text"
          },
          "Slack Channel" => %{
            "id" => "b~en",
            "rich_text" => [
              %{
                "annotations" => %{
                  "bold" => false,
                  "code" => false,
                  "color" => "default",
                  "italic" => false,
                  "strikethrough" => false,
                  "underline" => false
                },
                "href" => nil,
                "plain_text" => "vinicius",
                "text" => %{"content" => "vinicius", "link" => nil},
                "type" => "text"
              }
            ],
            "type" => "rich_text"
          },
          "Title" => %{
            "id" => "title",
            "title" => [
              %{
                "annotations" => %{
                  "bold" => false,
                  "code" => false,
                  "color" => "default",
                  "italic" => false,
                  "strikethrough" => false,
                  "underline" => false
                },
                "href" => nil,
                "plain_text" => "API Integration Failure",
                "text" => %{"content" => "API Integration Failure", "link" => nil},
                "type" => "text"
              }
            ],
            "type" => "title"
          }
        },
        "public_url" => nil,
        "url" => "https://www.notion.so/API-Integration-Failure-1b7d3c1b90d381c2a83ff57f0328a4e6"
      }

      ticket = Parser.parse_ticket_page(page)
    end
  end

  describe "extract_title/1" do
    test "handles nil input" do
      result =
        Parser.parse_response(%List{
          results: [
            %{
              "properties" => %{
                "Id" => nil,
                "Title" => %{"rich_text" => [%{"plain_text" => "Test"}]}
              }
            }
          ]
        })

      [ticket] = result
      assert ticket.ticket_id == nil
    end
  end

  describe "extract_rich_text/1" do
    test "handles nil input" do
      result =
        Parser.parse_response(%List{
          results: [
            %{
              "properties" => %{
                "ID" => %{"unique_id" => %{"number" => "123", "prefix" => "JMP"}},
                "Title" => nil
              }
            }
          ]
        })

      [ticket] = result
      assert ticket.title == nil
    end
  end
end
