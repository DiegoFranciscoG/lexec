defmodule Lexec.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Lexec.{RateLimiter, Rules}

  setup do
    RateLimiter.reset()
    :ok
  end

  test "allows up to the configured limit per client and window" do
    limit = Rules.fetch!(:app, ["rate_limits", "correction", "limit"])

    for _ <- 1..limit, do: assert(RateLimiter.hit("correction", {127, 0, 0, 1}) == :ok)
    assert RateLimiter.hit("correction", {127, 0, 0, 1}) == {:error, :rate_limited}
    assert RateLimiter.hit("correction", {10, 0, 0, 2}) == :ok
    assert RateLimiter.hit("search", {127, 0, 0, 1}) == :ok
  end

  test "expired windows are swept" do
    :ok = RateLimiter.hit("search", :someone)
    send(RateLimiter, :sweep)
    assert :sys.get_state(RateLimiter) == %{}
  end
end
