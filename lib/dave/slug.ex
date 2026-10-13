defmodule Dave.Slug do
  @moduledoc """
  The kids' address for a song: two short words, like `sunny-fox`.

  A Noteflight id is 40 hex characters. A nine-year-old typing that into an
  iPad is not going to happen, so every song gets an adjective and an
  animal instead. Both lists are words a young child can spell from
  hearing them once: no silent letters, nothing that sounds like another
  word in the list.

  `normalize/1` is what lookups compare on: lower case, letters only. So
  `Sunny-Fox`, `sunnyfox` and `sunny fox` all open the same song.
  """

  @adjectives ~w(
    sunny happy fuzzy jolly bouncy sleepy silly tiny cozy zippy
    merry lucky snowy rosy dizzy wiggly perky breezy shiny bubbly
    cheery dandy jumpy peppy sparkly swirly chirpy puffy jazzy minty
  )

  @animals ~w(
    fox duck frog bunny panda otter koala puppy kitten piggy
    pony owl bee bear cub chick goose moose whale seal
    crab snail turtle tiger lion zebra hippo llama robin finch
    dolphin penguin puffin parrot gecko monkey mouse deer
  )

  @doc "A fresh random slug. Not checked for collisions; see `Dave.Scores`."
  def generate do
    Enum.random(@adjectives) <> "-" <> Enum.random(@animals)
  end

  @doc "How many distinct slugs `generate/0` can produce."
  def combinations, do: length(@adjectives) * length(@animals)

  @doc """
  The comparison key for a typed address: lower case, letters only.

      iex> Dave.Slug.normalize("Sunny-Fox")
      "sunnyfox"
  """
  def normalize(slug) when is_binary(slug) do
    slug |> String.downcase() |> String.replace(~r/[^a-z]/, "")
  end
end
