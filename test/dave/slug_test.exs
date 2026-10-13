defmodule Dave.SlugTest do
  use ExUnit.Case, async: true

  alias Dave.Slug

  test "two lower-case words joined by one hyphen" do
    for _ <- 1..50 do
      assert Slug.generate() =~ ~r/^[a-z]{3,8}-[a-z]{3,8}$/
    end
  end

  test "enough room for a classroom's songs" do
    assert Slug.combinations() >= 1000
  end

  test "normalize is what a kid types" do
    assert Slug.normalize("sunny-fox") == "sunnyfox"
    assert Slug.normalize("Sunny Fox") == "sunnyfox"
    assert Slug.normalize("  SUNNY_FOX\n") == "sunnyfox"
  end
end
