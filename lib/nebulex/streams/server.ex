defmodule Nebulex.Streams.Server do
  @moduledoc false

  use GenServer

  alias Nebulex.Streams
  alias Nebulex.Streams.Options

  ## API

  @doc """
  Starts a stream server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = Options.validate_start_opts!(opts)
    {cache, opts} = Keyword.pop!(opts, :cache)
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(__MODULE__, {cache, name, opts})
  end

  ## GenServer callbacks

  @impl true
  def init({cache, name, opts}) do
    _ignore = Process.flag(:trap_exit, true)

    {pubsub, opts} = Keyword.pop!(opts, :pubsub)
    {partitions, opts} = Keyword.pop(opts, :partitions)
    {hash, opts} = Keyword.pop!(opts, :hash)
    {broadcast_fun, opts} = Keyword.pop!(opts, :broadcast_fun)

    state = %Streams{
      cache: cache,
      name: name,
      pubsub: pubsub,
      partitions: partitions,
      hash: hash,
      broadcast_fun: broadcast_fun,
      opts: opts
    }

    with {:ok, _} <-
           Registry.register(Streams.registry(), Streams.server_name(name || cache), state) do
      :ok = register_listener(state)

      {:ok, state, {:continue, :registered}}
    end
  end

  @impl true
  def handle_continue(:registered, %Streams{} = state) do
    :ok = dispatch_telemetry_event(:listener_registered, state)

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %Streams{} = state) do
    _ = unregister_listener(state)

    dispatch_telemetry_event(:listener_unregistered, state)
  end

  ## Private functions

  defp register_listener(%Streams{cache: cache, name: name, opts: opts} = state) do
    listener = &Streams.broadcast_event/1
    opts = [metadata: Map.from_struct(state)] ++ opts

    if name do
      cache.register_event_listener!(name, listener, opts)
    else
      cache.register_event_listener!(listener, opts)
    end
  end

  defp unregister_listener(%Streams{cache: cache, name: name, opts: opts}) do
    {id, opts} = Keyword.pop(opts, :id, &Streams.broadcast_event/1)

    if name do
      cache.unregister_event_listener(name, id, opts)
    else
      cache.unregister_event_listener(id, opts)
    end
  end

  defp dispatch_telemetry_event(event, state) do
    :telemetry.execute(
      [:nebulex, :streams, event],
      %{},
      Map.take(state, [:cache, :name, :pubsub, :partitions])
    )
  end
end
