defmodule Nebulex.Streams.Server do
  @moduledoc false

  use GenServer

  import Nebulex.Utils, only: [camelize_and_concat: 1]

  alias Nebulex.Streams
  alias Nebulex.Streams.Options

  # Internal state
  defstruct cache: nil,
            name: nil,
            pubsub: nil,
            partitions: nil,
            hash: nil,
            broadcast_fun: nil,
            opts: nil

  @typedoc "The type for the stream server metadata"
  @type metadata() :: %{
          required(:pubsub) => atom(),
          required(:partitions) => non_neg_integer() | nil
        }

  ## API

  @doc """
  Starts a stream server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = Options.validate_start_opts!(opts)
    {cache, opts} = Keyword.pop!(opts, :cache)
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, {cache, name, opts}, name: server_name(name || cache))
  end

  @doc """
  Returns the stream server metadata.
  """
  @spec get_metadata(atom()) :: metadata()
  def get_metadata(name) do
    name
    |> server_name()
    |> GenServer.call(:get_metadata)
  end

  ## GenServer callbacks

  @impl true
  def init({cache, name, opts}) do
    _ignore = Process.flag(:trap_exit, true)

    {pubsub, opts} = Keyword.pop!(opts, :pubsub)
    {partitions, opts} = Keyword.pop(opts, :partitions)
    {hash, opts} = Keyword.pop!(opts, :hash)
    {broadcast_fun, opts} = Keyword.pop!(opts, :broadcast_fun)

    state = %__MODULE__{
      cache: cache,
      name: name,
      pubsub: pubsub,
      partitions: partitions,
      hash: hash,
      broadcast_fun: broadcast_fun,
      opts: opts
    }

    {:ok, state, {:continue, :register_listener}}
  end

  @impl true
  def handle_continue(:register_listener, %__MODULE__{} = state) do
    :ok = register_listener(state)

    {:noreply, state}
  end

  @impl true
  def handle_call(:get_metadata, _from, %__MODULE__{} = state) do
    {:reply, Map.take(state, [:pubsub, :partitions]), state}
  end

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    unregister_listener(state)
  end

  ## Private functions

  # Inline common instructions
  @compile {:inline, server_name: 1}

  defp server_name(name), do: camelize_and_concat([__MODULE__, name])

  defp register_listener(%__MODULE__{cache: cache, name: name, opts: opts} = state) do
    listener = &Streams.broadcast_event/1
    opts = [metadata: Map.from_struct(state)] ++ opts

    if name do
      cache.register_event_listener(name, listener, opts)
    else
      cache.register_event_listener(listener, opts)
    end
  end

  defp unregister_listener(%__MODULE__{cache: cache, name: name, opts: opts}) do
    {id, opts} = Keyword.pop(opts, :id, &Streams.broadcast_event/1)

    if name do
      cache.unregister_event_listener(name, id, opts)
    else
      cache.unregister_event_listener(id, opts)
    end
  end
end
