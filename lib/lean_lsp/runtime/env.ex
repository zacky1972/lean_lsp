defmodule LeanLsp.Runtime.Env do
  @moduledoc false

  @type env_pair :: {String.t(), String.t()}

  @spec valid?(term()) :: boolean()
  def valid?(nil), do: true

  def valid?(env) when is_map(env) do
    Enum.all?(env, fn {key, value} -> valid_entry?({key, value}) end)
  end

  def valid?(env) when is_list(env), do: Enum.all?(env, &valid_entry?/1)
  def valid?(_env), do: false

  @spec normalize_pairs(term()) :: {:ok, [env_pair()]} | {:error, {:invalid_option, :env}}
  def normalize_pairs(nil), do: {:ok, []}

  def normalize_pairs(env) when is_map(env) do
    env
    |> Map.to_list()
    |> normalize_pairs()
  end

  def normalize_pairs(env) when is_list(env) do
    case Enum.reduce_while(env, {:ok, []}, fn entry, {:ok, entries} ->
           case_entry(normalize_entry(entry), entries)
         end) do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  def normalize_pairs(_env), do: {:error, {:invalid_option, :env}}

  defp case_entry({:ok, pair}, entries), do: {:cont, {:ok, [pair | entries]}}
  defp case_entry({:error, reason}, _entries), do: {:halt, {:error, reason}}

  @spec merge([env_pair()], [env_pair()]) :: [env_pair()]
  def merge(runtime_env, exec_env) when is_list(runtime_env) and is_list(exec_env) do
    runtime_env
    |> Map.new()
    |> Map.merge(Map.new(exec_env))
    |> Map.to_list()
  end

  @spec to_cli_args(String.t(), term()) :: [String.t()]
  def to_cli_args(_option, nil), do: []

  def to_cli_args(option, env) when is_map(env) do
    to_cli_args(option, Map.to_list(env))
  end

  def to_cli_args(option, env) when is_list(env) do
    Enum.flat_map(env, fn
      value when is_binary(value) ->
        [option, value]

      {key, value} ->
        [option, "#{env_part_to_string(key)}=#{env_part_to_string(value)}"]
    end)
  end

  @spec path_value([env_pair()]) :: String.t()
  def path_value(env) when is_list(env) do
    case Enum.find(env, fn {key, _value} -> key == "PATH" end) do
      {"PATH", value} -> value
      nil -> System.get_env("PATH", "")
    end
  end

  defp valid_entry?(value) when is_binary(value), do: value != ""

  defp valid_entry?({key, value}) do
    valid_key?(key) and valid_value?(value)
  end

  defp valid_entry?(_value), do: false

  defp valid_key?(key), do: is_atom(key) or is_binary(key)

  defp valid_value?(value)
       when is_binary(value) or is_atom(value) or is_integer(value) or is_float(value) or
              is_boolean(value) do
    true
  end

  defp valid_value?(_value), do: false

  defp normalize_entry(value) when is_binary(value) do
    case String.split(value, "=", parts: 2) do
      [key, env_value] when key != "" -> {:ok, {key, env_value}}
      _other -> {:error, {:invalid_option, :env}}
    end
  end

  defp normalize_entry({key, value}) do
    with {:ok, key} <- normalize_key(key),
         {:ok, value} <- normalize_value(value) do
      {:ok, {key, value}}
    else
      {:error, _reason} -> {:error, {:invalid_option, :env}}
    end
  end

  defp normalize_entry(_value), do: {:error, {:invalid_option, :env}}

  defp normalize_key(key) when is_atom(key), do: normalize_key(Atom.to_string(key))

  defp normalize_key(key) when is_binary(key) do
    if key != "" and not String.contains?(key, "=") do
      {:ok, key}
    else
      {:error, :invalid_env_key}
    end
  end

  defp normalize_key(_key), do: {:error, :invalid_env_key}

  defp normalize_value(value) when is_binary(value), do: {:ok, value}

  defp normalize_value(value)
       when is_atom(value) or is_integer(value) or is_float(value) or is_boolean(value) do
    {:ok, to_string(value)}
  end

  defp normalize_value(_value), do: {:error, :invalid_env_value}

  defp env_part_to_string(value) when is_binary(value), do: value
  defp env_part_to_string(value), do: to_string(value)
end
