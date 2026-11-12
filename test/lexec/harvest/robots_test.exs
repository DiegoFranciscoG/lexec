defmodule Lexec.Harvest.RobotsTest do
  use ExUnit.Case, async: true

  alias Lexec.Harvest.Robots

  @robots """
  # comentario
  User-agent: OtroBot
  Disallow: /

  User-agent: LEXEC-bot
  User-agent: otro
  Disallow: /storage/
  Allow: /storage/api/v1/publico
  Disallow: /*.zip$

  User-agent: *
  Disallow: /admin
  """

  test "uses the group of our product token, not *" do
    rules = Robots.parse(@robots, "LEXEC-bot")
    refute Robots.allowed_by?(rules, "/storage/x.pdf")
    assert Robots.allowed_by?(rules, "/storage/api/v1/publico/1.pdf")
    assert Robots.allowed_by?(rules, "/admin")
    refute Robots.allowed_by?(rules, "/archivo.zip")
    assert Robots.allowed_by?(rules, "/archivo.zip?x=1")
  end

  test "falls back to * when no group names us" do
    rules = Robots.parse(@robots, "Desconocido")
    refute Robots.allowed_by?(rules, "/admin/panel")
    assert Robots.allowed_by?(rules, "/storage/x.pdf")
  end

  test "empty Disallow allows everything (Corte's robots.txt)" do
    assert Robots.parse("User-agent: *\nDisallow:\n", "LEXEC-bot") == :allow_all
    assert Robots.allowed_by?(:allow_all, "/x")
    refute Robots.allowed_by?(:disallow_all, "/x")
  end

  test "longest rule wins and Allow wins ties" do
    rules = [{:disallow, "/a"}, {:allow, "/a"}, {:disallow, "/a/b"}]
    assert Robots.allowed_by?(rules, "/a/c")
    refute Robots.allowed_by?(rules, "/a/b/c")
  end
end
