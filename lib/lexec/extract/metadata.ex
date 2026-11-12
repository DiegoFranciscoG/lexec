defmodule Lexec.Extract.Metadata do
  @moduledoc """
  Reads ruling metadata (number, case file, action type, date, rapporteur and
  decision) with the patterns in `segmentation.yaml` and the catalog in
  `action_types.yaml`.
  """

  alias Lexec.Rules

  @type t :: %{
          case_number: String.t() | nil,
          case_file: String.t() | nil,
          action_type: String.t() | nil,
          ruling_year: integer() | nil,
          decided_on: Date.t() | nil,
          rapporteur: String.t() | nil,
          decision: String.t()
        }

  @doc """
  Extracts metadata. `head` is the text before the first paragraph and `body`
  the full clean text (used to find the decision section).
  """
  @spec extract(String.t(), String.t()) :: t()
  def extract(head, body) when is_binary(head) and is_binary(body) do
    p = patterns()
    case_number = capture(p.ruling_number, head) || capture(p.ruling_number, body)
    case_file = capture(p.case_file, head) || case_file_from(case_number)

    %{
      case_number: case_number,
      case_file: case_file,
      action_type: action_type(case_number || case_file),
      ruling_year: ruling_year(case_number),
      decided_on: date(p, head),
      rapporteur: head |> then(&capture(p.rapporteur, &1)) |> clean_name(),
      decision: decision(p, body)
    }
  end

  @doc "Action type code for a ruling or case number (legacy codes mapped)."
  @spec action_type(String.t() | nil) :: String.t() | nil
  def action_type(nil), do: nil

  def action_type(number) do
    types = Rules.fetch!(:action_types, ["types"])
    legacy = Rules.fetch!(:action_types, ["legacy"])

    code =
      case Regex.run(~r/^\d{1,5}-\d{2}-([A-Z]{2,3})/u, number) do
        [_, code] -> Map.get(legacy, code, code)
        nil -> nil
      end

    if Map.has_key?(types, code), do: code, else: nil
  end

  @doc "Four-digit year of the ruling, from the `/YY` suffix or legacy number."
  @spec ruling_year(String.t() | nil) :: integer() | nil
  def ruling_year(nil), do: nil

  def ruling_year(number) do
    cond do
      match = Regex.run(~r/\/(\d{2})$/u, number) ->
        2000 + String.to_integer(Enum.at(match, 1))

      match = Regex.run(~r/^\d{3}-(\d{2})-S[A-Z]{2,3}-CC$/u, number) ->
        2000 + String.to_integer(Enum.at(match, 1))

      true ->
        nil
    end
  end

  defp case_file_from(nil), do: nil
  defp case_file_from(number), do: number |> String.split("/") |> hd()

  defp capture(regex, text) do
    case Regex.named_captures(regex, text) do
      %{"v" => value} -> String.trim(value)
      nil -> nil
    end
  end

  defp clean_name(nil), do: nil

  defp clean_name(name) do
    name = name |> String.trim() |> String.trim_trailing(".")
    if name == "", do: nil, else: name
  end

  defp date(p, head) do
    with %{"d" => d, "m" => m, "y" => y} <- Regex.named_captures(p.date, head),
         month when is_integer(month) <- Map.get(p.months, String.downcase(m)),
         {:ok, date} <- Date.new(String.to_integer(y), month, String.to_integer(d)) do
      date
    else
      _ -> nil
    end
  end

  defp decision(p, body) do
    case Regex.split(p.decision_heading, body, parts: 2) do
      [_before, after_heading] ->
        p.decision_rules
        |> Enum.map(fn {regex, value} -> {first_index(regex, after_heading), value} end)
        |> Enum.reject(fn {index, _} -> is_nil(index) end)
        |> Enum.min_by(fn {index, _} -> index end, fn -> {nil, "other"} end)
        |> elem(1)

      _ ->
        "other"
    end
  end

  defp first_index(regex, text) do
    case Regex.run(regex, text, return: :index) do
      [{index, _} | _] -> index
      nil -> nil
    end
  end

  defp patterns do
    Rules.memo(:metadata_patterns, fn ->
      meta = Rules.fetch!(:segmentation, ["metadata"])

      %{
        ruling_number: Rules.regex!(meta["ruling_number"]),
        case_file: Rules.regex!(meta["case_file"]),
        date: Rules.regex!(meta["date"], "i"),
        rapporteur: Rules.regex!(meta["rapporteur"]),
        decision_heading: Rules.regex!(meta["decision_heading"]),
        months: Rules.fetch!(:segmentation, ["months"]),
        decision_rules:
          :segmentation
          |> Rules.fetch!(["decision_rules"])
          |> Enum.map(fn %{"pattern" => pattern, "value" => value} ->
            {Rules.regex!(pattern), value}
          end)
      }
    end)
  end
end
