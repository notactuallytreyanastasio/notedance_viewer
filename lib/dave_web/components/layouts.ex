defmodule DaveWeb.Layouts do
  @moduledoc """
  Page chrome for dave. There is deliberately almost none: the three pages
  (songs, TV, kid) each own their header, so the layout only supplies the
  flash messages. Every template wraps itself in `<Layouts.app>`.
  """
  use DaveWeb, :html

  embed_templates "layouts/*"

  @default_description "Put a song on the TV and hand the kids the link. " <>
                         "Every iPad in the classroom follows the line while the teacher presses play."

  @doc "The tagline used wherever a page does not set its own description."
  def default_description, do: @default_description

  attr :flash, :map, required: true, doc: "the map of flash messages"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    {render_slot(@inner_block)}
    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The flash messages, one line each at the top of the page. They go away on
  a tap and on their own after a few seconds (see assets/js/flash.js).
  """
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id="flash-group" class="flash-group" aria-live="polite">
      <.flash_line kind="info" msg={Phoenix.Flash.get(@flash, :info)} />
      <.flash_line kind="error" msg={Phoenix.Flash.get(@flash, :error)} />
    </div>
    """
  end

  attr :kind, :string, required: true
  attr :msg, :string, default: nil

  defp flash_line(assigns) do
    ~H"""
    <button :if={@msg} type="button" class={"flash flash-#{@kind}"} data-flash role="alert">
      <.icon :if={@kind == "info"} name="hero-check-circle" class="size-6 shrink-0" />
      <.icon :if={@kind == "error"} name="hero-exclamation-circle" class="size-6 shrink-0" />
      <span>{@msg}</span>
    </button>
    """
  end
end
