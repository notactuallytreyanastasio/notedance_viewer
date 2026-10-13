defmodule Dave.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      DaveWeb.Telemetry,
      Dave.Repo,
      {DNSCluster, query: Application.get_env(:dave, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Dave.PubSub},
      # the master clock for every playing score (DaveWeb.SessionChannel broadcasts)
      Dave.Sessions,
      # Start a worker by calling: Dave.Worker.start_link(arg)
      # {Dave.Worker, arg},
      # Start to serve requests, typically the last entry
      DaveWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Dave.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    DaveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
