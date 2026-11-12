defmodule Lexec.Harvest.Robots do
  @moduledoc """
  robots.txt support following RFC 9309: groups by user-agent (our product
  token, else `*`), longest matching rule wins, `Allow` wins ties, `*` and `$`
  wildcards. 4xx ⇒ everything allowed; 5xx or network error ⇒ nothing allowed.
  Results are cached per origin for the life of the node.
  """

  alias Lexec.Harvest.Fetcher

  @type rules :: :allow_all | :disallow_all | [{:allow | :disallow, String.t()}]

  @spec allowed?(String.t()) :: boolean()
  def allowed?(url) do
    uri = URI.parse(url)
    origin = "#{uri.scheme}://#{uri.host}#{port_suffix(uri)}"

    rules =
      case :ets.lookup(:lexec_robots, origin) do
        [{^origin, cached}] ->
          cached

        [] ->
          fetched = fetch_rules(origin)
          :ets.insert(:lexec_robots, {origin, fetched})
          fetched
      end

    path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")
    allowed_by?(rules, path)
  end

  @doc "Clears the cache (tests)."
  def clear, do: :ets.delete_all_objects(:lexec_robots)

  defp fetch_rules(origin) do
    case Fetcher.get(origin <> "/robots.txt", retries: 0) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        parse(to_string(body), Fetcher.product_token())

      {:ok, %{status: status}} when status in 400..499 ->
        :allow_all

      _ ->
        :disallow_all
    end
  end

  @doc "Parses robots.txt and returns the rules that apply to `token`."
  @spec parse(String.t(), String.t()) :: rules()
  def parse(text, token) do
    token = String.downcase(token)

    groups =
      text
      |> String.split(~r/\r?\n/u)
      |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd() |> String.trim()))
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn line ->
        case String.split(line, ":", parts: 2) do
          [key, value] -> {key |> String.trim() |> String.downcase(), String.trim(value)}
          _ -> {:invalid, line}
        end
      end)
      |> group()

    specific =
      Enum.filter(groups, fn {agents, _} ->
        Enum.any?(agents, &(&1 != "*" and String.starts_with?(token, &1)))
      end)

    chosen =
      if specific != [],
        do: specific,
        else: Enum.filter(groups, fn {agents, _} -> "*" in agents end)

    case Enum.flat_map(chosen, &elem(&1, 1)) do
      [] -> :allow_all
      rules -> rules
    end
  end

  # Consecutive user-agent lines open a group; following rules belong to it.
  defp group(lines) do
    {groups, current, _} =
      Enum.reduce(lines, {[], nil, :rules}, fn
        {"user-agent", agent}, {groups, current, :agents} ->
          {agents, rules} = current
          {groups, {[String.downcase(agent) | agents], rules}, :agents}

        {"user-agent", agent}, {groups, current, :rules} ->
          {push(groups, current), {[String.downcase(agent)], []}, :agents}

        {key, value}, {groups, {agents, rules}, _} when key in ["allow", "disallow"] ->
          rules = if value == "", do: rules, else: [{String.to_existing_atom(key), value} | rules]
          {groups, {agents, rules}, :rules}

        _other, acc ->
          acc
      end)

    groups |> push(current) |> Enum.reverse() |> Enum.map(fn {a, r} -> {a, Enum.reverse(r)} end)
  end

  defp push(groups, nil), do: groups
  defp push(groups, current), do: [current | groups]

  @doc false
  @spec allowed_by?(rules(), String.t()) :: boolean()
  def allowed_by?(:allow_all, _path), do: true
  def allowed_by?(:disallow_all, _path), do: false

  def allowed_by?(rules, path) do
    rules
    |> Enum.filter(fn {_kind, pattern} -> matches?(pattern, path) end)
    |> Enum.sort_by(fn {kind, pattern} ->
      {-String.length(pattern), if(kind == :allow, do: 0, else: 1)}
    end)
    |> case do
      [] -> true
      [{kind, _} | _] -> kind == :allow
    end
  end

  defp matches?(pattern, path) do
    anchored = String.ends_with?(pattern, "$")
    body = if anchored, do: String.slice(pattern, 0..-2//1), else: pattern

    source =
      body
      |> String.split("*")
      |> Enum.map_join(".*", &Regex.escape/1)

    Regex.match?(Regex.compile!("^" <> source <> if(anchored, do: "$", else: ""), "u"), path)
  end

  defp port_suffix(%URI{scheme: "https", port: 443}), do: ""
  defp port_suffix(%URI{scheme: "http", port: 80}), do: ""
  defp port_suffix(%URI{port: nil}), do: ""
  defp port_suffix(%URI{port: port}), do: ":#{port}"
end
