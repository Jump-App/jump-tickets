defmodule JumpTickets.External.Notion do
  alias JumpTickets.Ticket
  alias Notionex

  def query_db() do
    db_id = Application.get_env(:jump_tickets, :notion_db_id)
    fetch_all_pages(db_id)
  end

  defp fetch_all_pages(db_id, start_cursor \\ nil, accumulated_results \\ []) do
    query_params = %{
      database_id: db_id,
      page_size: 100
    }

    # Add start_cursor if we're continuing pagination
    query_params =
      if start_cursor, do: Map.put(query_params, :start_cursor, start_cursor), else: query_params

    case Notionex.API.query_database(query_params) do
      %Notionex.Object.List{results: results, has_more: true, next_cursor: next_cursor} ->
        # More pages available, recurse with the next cursor
        parsed_results = Enum.map(results, &__MODULE__.Parser.parse_ticket_page/1)
        fetch_all_pages(db_id, next_cursor, accumulated_results ++ parsed_results)

      %Notionex.Object.List{results: results, has_more: false} ->
        # Last page, return all accumulated results plus this page
        parsed_results = Enum.map(results, &__MODULE__.Parser.parse_ticket_page/1)
        {:ok, accumulated_results ++ parsed_results}

      error ->
        {:error, "Failed to query database: #{inspect(error)}"}
    end
  end

  def get_ticket_by_page_id(page_id) do
    case Notionex.API.retrieve_page(%{page_id: page_id}) do
      %Notionex.Object.Page{} = page ->
        __MODULE__.Parser.parse_ticket_page(page)

      _ ->
        {:error, "Failed to get page #{page_id}"}
    end
  end

  def create_ticket(%Ticket{} = ticket) do
    db_id = Application.get_env(:jump_tickets, :notion_db_id)

    properties = %{
      "Title" => %{
        title: [%{text: %{content: ticket.title}}]
      },
      "Intercom Conversations" => %{
        rich_text: [%{text: %{content: ticket.intercom_conversations}}]
      }
    }

    ticket =
      Notionex.API.create_page(%{
        parent: %{database_id: db_id},
        properties: properties,
        children: [
          %{
            object: "block",
            type: "paragraph",
            paragraph: %{
              rich_text: [
                %{
                  type: "text",
                  text: %{
                    content: ticket.summary
                  }
                }
              ]
            }
          }
        ]
      })
      |> JumpTickets.External.Notion.Parser.parse_ticket_page()

    {:ok, ticket}
  end

  def update_ticket(page_id, properties_to_update) when is_map(properties_to_update) do
    notion_properties =
      properties_to_update
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        case key do
          :title ->
            Map.put(acc, "Title", %{
              title: [%{text: %{content: value}}]
            })

          :intercom_conversations ->
            Map.put(acc, "Intercom Conversations", %{
              rich_text: [%{text: %{content: value}}]
            })

          :slack_channel ->
            Map.put(acc, "Slack Channel", %{
              rich_text: [%{text: %{content: value}}]
            })

          _ ->
            acc
        end
      end)

    result =
      Notionex.API.update_page_properties(%{
        page_id: page_id,
        properties: notion_properties
      })

    updated_ticket = result |> JumpTickets.External.Notion.Parser.parse_ticket_page()

    {:ok, updated_ticket}
  end
end

defmodule JumpTickets.External.Notion.Parser do
  @moduledoc false
  alias JumpTickets.Ticket

  require Logger

  def parse_response(response) do
    case response do
      %Notionex.Object.List{results: results} ->
        Enum.map(results, &parse_ticket_page/1)

      _ ->
        {:error, "Invalid response format"}
    end
  end

  def parse_ticket_page(page) do
    notion_url = Map.get(page, "url", Map.get(page, :url))
    notion_id = Map.get(page, "id", Map.get(page, :id))
    properties = Map.get(page, "properties", Map.get(page, :properties))

    %Ticket{
      ticket_id: Map.get(properties, "ID") |> extract_id(),
      notion_id: notion_id,
      notion_url: notion_url,
      title: Map.get(properties, "Title") |> extract_title(),
      intercom_conversations:
        Map.get(properties, "Intercom Conversations") |> extract_rich_text(),
      summary: Map.get(properties, "children") |> extract_rich_text(),
      slack_channel: Map.get(properties, "Slack Channel") |> extract_rich_text()
    }
  end

  defp extract_id(nil), do: nil

  defp extract_id(%{"unique_id" => %{"number" => number, "prefix" => prefix}}) do
    "#{prefix}-#{number}"
  end

  # Extract plain text from a title property
  defp extract_title(nil), do: nil

  defp extract_title(%{"title" => title}) do
    case title do
      [%{"plain_text" => text} | _] -> text
      _ -> nil
    end
  end

  defp extract_title(_), do: nil

  # Extract plain text from a rich_text property
  defp extract_rich_text(nil), do: nil

  defp extract_rich_text(%{"rich_text" => rich_text}) do
    case rich_text do
      [%{"plain_text" => text} | _] -> text
      _ -> nil
    end
  end

  defp extract_rich_text(_), do: nil
end
