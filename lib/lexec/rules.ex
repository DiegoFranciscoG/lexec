defmodule Lexec.Rules do
  @moduledoc """
  Loads the versioned rule files in `priv/rules/*.yaml`.

  Thresholds, patterns and texts live in data files, never in code. Files are
  parsed once and cached in `:persistent_term`; `reload/0` clears the cache.
  """

  @names ~w(app exclusion anonymization preserve action_types relations segmentation)a

  @type name ::
          :app
          | :exclusion
          | :anonymization
          | :preserve
          | :action_types
          | :relations
          | :segmentation

  @doc "Returns the parsed YAML map for a rule file."
  @spec get(name()) :: map()
  def get(name) when name in @names do
    key = {__MODULE__, name}

    case :persistent_term.get(key, :missing) do
      :missing ->
        value = load!(name)
        :persistent_term.put(key, value)
        value

      value ->
        value
    end
  end

  @doc "Fetches a nested value, raising if any key is missing."
  @spec fetch!(name(), [String.t()]) :: term()
  def fetch!(name, path) when is_list(path) do
    Enum.reduce(path, get(name), fn key, acc ->
      case acc do
        %{^key => value} -> value
        _ -> raise KeyError, "missing rule #{Enum.join(path, ".")} in #{name}.yaml"
      end
    end)
  end

  @doc "Version string declared by a rule file."
  @spec version(name()) :: String.t()
  def version(name), do: fetch!(name, ["version"])

  @doc "Combined version of every rule file that changes the published text."
  @spec pipeline_version() :: String.t()
  def pipeline_version do
    [:exclusion, :anonymization, :preserve, :segmentation, :relations]
    |> Enum.map_join("+", &version/1)
  end

  @doc "Compiles a pattern from the rule files (unicode, optional extra flags)."
  @spec regex!(String.t(), String.t()) :: Regex.t()
  def regex!(source, flags \\ "") when is_binary(source) do
    Regex.compile!(source, "u" <> flags)
  end

  @doc """
  Memoizes a value derived from the rules (for example compiled regexes)
  under `key`. Cleared by `reload/0`.
  """
  @spec memo(term(), (-> value)) :: value when value: term()
  def memo(key, fun) when is_function(fun, 0) do
    pkey = {__MODULE__, :memo, key}

    case :persistent_term.get(pkey, :missing) do
      :missing ->
        value = fun.()
        :persistent_term.put(pkey, value)
        keys = :persistent_term.get({__MODULE__, :memo_keys}, [])
        :persistent_term.put({__MODULE__, :memo_keys}, [pkey | keys])
        value

      value ->
        value
    end
  end

  @doc "Clears the cache so files are read again."
  @spec reload() :: :ok
  def reload do
    Enum.each(@names, &:persistent_term.erase({__MODULE__, &1}))

    {__MODULE__, :memo_keys}
    |> :persistent_term.get([])
    |> Enum.each(&:persistent_term.erase/1)

    :persistent_term.erase({__MODULE__, :memo_keys})
    :ok
  end

  defp load!(name) do
    path = Path.join(rules_dir(), "#{name}.yaml")

    case YamlElixir.read_from_file(path) do
      {:ok, %{} = map} -> map
      {:ok, other} -> raise ArgumentError, "#{path} must be a map, got: #{inspect(other)}"
      {:error, error} -> raise ArgumentError, "cannot read #{path}: #{inspect(error)}"
    end
  end

  defp rules_dir do
    Application.get_env(:lexec, :rules_dir) || Application.app_dir(:lexec, "priv/rules")
  end
end
