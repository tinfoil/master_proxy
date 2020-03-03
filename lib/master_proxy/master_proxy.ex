defmodule MasterProxy do
  @moduledoc false
  use Supervisor
  import Supervisor.Spec, warn: false
  require Logger

  def child_spec(opts) do
    %{
      id: opts[:name] || __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def init(opts), do: {:ok, opts}

  def start_link(opts) do
    opts = merge_runtime_and_compiled_opts(opts)
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)

    backends =
      opts
      |> Keyword.get(:backends, [])

    children =
      Enum.reduce([:http, :https], [], fn scheme, result ->
        case Keyword.get(opts, scheme) do
          nil ->
            # no config for this scheme, that's ok, just skip
            result

          scheme_opts ->
            port = :proplists.get_value(:port, scheme_opts)

            cowboy_opts =
              [
                port: port_to_integer(port),
                dispatch: [
                  {:_, [{:_, MasterProxy.Cowboy2Handler, {backends, opts}}]}
                ]
              ] ++ :proplists.delete(:port, scheme_opts)

            Logger.info("[master_proxy] Listening on #{scheme} with options: #{inspect(opts)}")

            [{Plug.Cowboy, scheme: scheme, plug: {nil, nil}, options: cowboy_opts} | result]
        end
      end)

    supervisor_opts = [strategy: :one_for_one, name: :"#{name}.Supervisor"]
    Supervisor.start_link(children, supervisor_opts)
  end

  defp merge_runtime_and_compiled_opts(options) do
    relevant_keys = [:http, :https, :log_requests, :conn, :backends, :name]
    compiled_opts = Application.get_all_env(:master_proxy)

    env_configed =
      relevant_keys
      |> Enum.reduce([], fn key, acc ->
        set_opt_or_skip(key, acc, compiled_opts)
      end)

    relevant_keys
    |> Enum.reduce(env_configed, fn key, acc ->
      set_opt_or_skip(key, acc, options)
    end)
  end

  def set_opt_or_skip(key, target_list, source_list) do
    if val = Keyword.get(source_list, key) do
      target_list
      |> Keyword.put(key, val)
    else
      target_list
    end
  end

  # :undefined is what :proplist.get_value returns
  defp port_to_integer(:undefined),
    do: raise("port is missing from the master_proxy configuration")

  defp port_to_integer(port) when is_binary(port), do: String.to_integer(port)
  defp port_to_integer(port) when is_integer(port), do: port
end
