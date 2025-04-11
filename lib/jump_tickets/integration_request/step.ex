defmodule JumpTickets.IntegrationRequest.Step do
  @type t :: %__MODULE__{
          type: Integration.step_type(),
          status: Integration.step_status(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          error: String.t() | nil,
          result: map() | nil
        }

  defstruct type: nil,
            status: :pending,
            started_at: nil,
            completed_at: nil,
            error: nil,
            result: nil
end
