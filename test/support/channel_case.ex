defmodule DaveWeb.ChannelCase do
  @moduledoc """
  This module defines the test case for channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import DaveWeb.ChannelCase

      @endpoint DaveWeb.Endpoint
    end
  end
end
