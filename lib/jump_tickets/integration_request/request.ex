defmodule JumpTickets.IntegrationRequest.Request do
  @type t :: %__MODULE__{
          intercom_conversation_id: String.t(),
          intercom_conversation_url: String.t(),
          message_body: String.t(),
          status: Integration.step_status(),
          steps: %{Integration.step_type() => Integration.Step.t()},
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct id: nil,
            intercom_conversation_id: nil,
            intercom_conversation_url: nil,
            message_body: nil,
            status: :pending,
            steps: %{},
            created_at: nil,
            updated_at: nil,
            context: %{}
end
