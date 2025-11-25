defmodule CnsCrucible.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add supervised children here as needed
      # {CnsCrucible.ModelServer, []}
    ]

    opts = [strategy: :one_for_one, name: CnsCrucible.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
