defmodule LexecWeb.Highlight do
  @moduledoc """
  Splits a paragraph into plain and highlighted segments for the query terms.
  Returns data, never HTML: the template escapes every segment.
  """

  @spec segments(String.t(), String.t()) :: [{:text | :mark, String.t()}]
  def segments(text, query) do
    terms =
      query
      |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
      |> Enum.filter(&(String.length(&1) >= 4))
      |> Enum.uniq()
      |> Enum.take(12)

    case terms do
      [] ->
        [{:text, text}]

      terms ->
        # Whole words that start with a query term: "mujer" marks "mujeres".
        regex =
          Regex.compile!(
            "(?<![\\p{L}])((?:" <> Enum.map_join(terms, "|", &Regex.escape/1) <> ")\\p{L}*)",
            "iu"
          )

        regex
        |> Regex.split(text, include_captures: true, trim: true)
        |> Enum.map(fn part ->
          if Regex.match?(regex, part), do: {:mark, part}, else: {:text, part}
        end)
    end
  end
end

defmodule LexecWeb.Format do
  @moduledoc "Spanish formatting helpers."

  @months ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

  @spec date(Date.t() | String.t() | nil) :: String.t()
  def date(nil), do: ""

  def date(%Date{} = d), do: "#{d.day} de #{Enum.at(@months, d.month - 1)} de #{d.year}"

  def date(iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> date(d)
      _ -> iso
    end
  end

  @decisions %{
    "accepted" => "Acepta",
    "partially_accepted" => "Acepta parcialmente",
    "dismissed" => "Desestima",
    "rejected" => "Rechaza",
    "other" => "Otra"
  }

  @spec decision(String.t()) :: String.t()
  def decision(value), do: Map.get(@decisions, value, value)
end
