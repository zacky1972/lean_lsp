defmodule LeanLsp.Runtime.Options do
  @moduledoc false

  @gen_server_options [:debug, :hibernate_after, :name, :spawn_opt]

  @spec gen_server_options() :: [atom()]
  def gen_server_options(), do: @gen_server_options

  @spec validate(map(), keyword()) :: {:ok, map()} | {:error, {:invalid_option, atom()}}
  def validate(config, validators) when is_map(config) and is_list(validators) do
    case Enum.find(validators, fn {key, validator} -> not validator.(Map.fetch!(config, key)) end) do
      nil -> {:ok, config}
      {key, _validator} -> {:error, {:invalid_option, key}}
    end
  end

  @spec keyword?(term()) :: boolean()
  def keyword?(value), do: is_list(value) and Keyword.keyword?(value)

  @spec string_list?(term()) :: boolean()
  def string_list?(value) when is_list(value), do: Enum.all?(value, &is_binary/1)
  def string_list?(_value), do: false

  @spec optional_binary?(term()) :: boolean()
  def optional_binary?(nil), do: true
  def optional_binary?(value), do: non_empty_binary?(value)

  @spec non_empty_binary?(term()) :: boolean()
  def non_empty_binary?(value), do: is_binary(value) and value != ""

  @spec valid_timeout?(term()) :: boolean()
  def valid_timeout?(:infinity), do: true
  def valid_timeout?(timeout), do: is_integer(timeout) and timeout >= 0
end
