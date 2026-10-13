defmodule Dave.Repo do
  use Ecto.Repo,
    otp_app: :dave,
    adapter: Ecto.Adapters.Postgres
end
