defmodule Lexec.Privacy.Exclusion do
  @moduledoc """
  Decides whether a ruling must be excluded **before** any model sees it.

  Order: case numbers flagged by the Court, metadata flags from the harvest
  manifest, excluded action types and finally keyword rules over the raw text.
  The result carries the reason and the rule id; never any text.
  """

  alias Lexec.Rules

  @type reason :: String.t()
  @type decision :: :ok | {:exclude, reason(), rule_id :: String.t()}

  @type input :: %{
          required(:text) => String.t(),
          optional(:case_number) => String.t() | nil,
          optional(:action_type) => String.t() | nil,
          optional(:flags) => [String.t()]
        }

  @spec evaluate(input()) :: decision()
  def evaluate(%{text: text} = input) when is_binary(text) do
    config = Rules.get(:exclusion)

    by_case(input, config) || by_flags(input, config) || by_type(input, config) ||
      by_keywords(text) || :ok
  end

  @doc "Version of the exclusion rules, stored with every exclusion."
  @spec rules_version() :: String.t()
  def rules_version, do: Rules.version(:exclusion)

  defp by_case(%{case_number: number}, config) when is_binary(number) do
    if number in (config["excluded_case_numbers"] || []),
      do: {:exclude, "reserved", "excluded-case-number"}
  end

  defp by_case(_input, _config), do: nil

  defp by_flags(%{flags: flags}, config) when is_list(flags) do
    mapping = config["metadata_flags"] || %{}

    Enum.find_value(flags, fn flag ->
      case Map.fetch(mapping, flag) do
        {:ok, reason} -> {:exclude, reason, "metadata-flag-#{flag}"}
        :error -> nil
      end
    end)
  end

  defp by_flags(_input, _config), do: nil

  defp by_type(%{action_type: type}, config) when is_binary(type) do
    if type in (config["excluded_action_types"] || []),
      do: {:exclude, "other", "excluded-action-type-#{type}"}
  end

  defp by_type(_input, _config), do: nil

  defp by_keywords(text) do
    Enum.find_value(compiled_rules(), fn {id, reason, regexes} ->
      if Enum.any?(regexes, &Regex.match?(&1, text)), do: {:exclude, reason, id}
    end)
  end

  defp compiled_rules do
    Rules.memo(:exclusion_rules, fn ->
      :exclusion
      |> Rules.fetch!(["rules"])
      |> Enum.map(fn %{"id" => id, "reason" => reason, "patterns" => patterns} ->
        {id, reason, Enum.map(patterns, &Rules.regex!(&1, "i"))}
      end)
    end)
  end
end
