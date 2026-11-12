defmodule Lexec.Extract.Segmenter do
  @moduledoc """
  Splits clean lines into the numbered paragraphs used by the Court.
  Everything after the "Decisión" heading (the operative part) is left out:
  it is read by `Lexec.Extract.Metadata` instead.

  A line `N. text` opens paragraph N only if N is exactly the next expected
  number. Restarted numbering (for example the numbered list in the decision)
  and numbered headings therefore never break the sequence. Headings are
  dropped; hyphenated line breaks are joined.
  """

  alias Lexec.Rules

  @type result :: %{preamble: String.t(), paragraphs: [Lexec.Extract.Document.paragraph()]}

  @spec segment([String.t()]) :: result()
  def segment(lines) when is_list(lines) do
    {start_re, heading_res, decision_re} = patterns()

    initial = %{expected: 1, current: nil, preamble: [], done: [], in_decision: false}

    state =
      Enum.reduce(lines, initial, fn line, acc ->
        cond do
          acc.in_decision or String.trim(line) == "" ->
            acc

          # The operative part restarts its own numbering: it is not a paragraph.
          acc.current != nil and Regex.match?(decision_re, line) ->
            acc |> close_current() |> Map.put(:in_decision, true)

          match = paragraph_start(start_re, line, acc.expected) ->
            acc
            |> close_current()
            |> Map.merge(%{current: {acc.expected, [match]}, expected: acc.expected + 1})

          Enum.any?(heading_res, &Regex.match?(&1, line)) ->
            acc

          acc.current == nil ->
            %{acc | preamble: [line | acc.preamble]}

          true ->
            {num, parts} = acc.current
            %{acc | current: {num, [line | parts]}}
        end
      end)
      |> close_current()

    %{
      preamble: state.preamble |> Enum.reverse() |> Enum.map_join("\n", &String.trim/1),
      paragraphs: Enum.reverse(state.done)
    }
  end

  defp paragraph_start(regex, line, expected) do
    case Regex.named_captures(regex, line) do
      %{"num" => num, "rest" => rest} ->
        if String.to_integer(num) == expected, do: rest, else: nil

      nil ->
        nil
    end
  end

  defp close_current(%{current: nil} = acc), do: acc

  defp close_current(%{current: {num, parts}} = acc) do
    text = parts |> Enum.reverse() |> join_lines()
    %{acc | current: nil, done: [%{number: num, text: text} | acc.done]}
  end

  @doc false
  @spec join_lines([String.t()]) :: String.t()
  def join_lines(lines) do
    lines
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce("", fn line, acc ->
      cond do
        acc == "" -> line
        Regex.match?(~r/\p{Ll}-$/u, acc) -> String.slice(acc, 0..-2//1) <> line
        true -> acc <> " " <> line
      end
    end)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp patterns do
    Rules.memo(:segmenter_patterns, fn ->
      start = Rules.regex!(Rules.fetch!(:segmentation, ["paragraph_start"]))

      headings =
        :segmentation
        |> Rules.fetch!(["headings"])
        |> Enum.map(&Rules.regex!/1)

      decision = Rules.regex!(Rules.fetch!(:segmentation, ["metadata", "decision_heading"]))
      {start, headings, decision}
    end)
  end
end
