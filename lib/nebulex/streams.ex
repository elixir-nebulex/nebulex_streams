defmodule Nebulex.Streams do
  @moduledoc """
  Nebulex Streams provides real-time event streaming capabilities for Nebulex
  caches.

  ## Overview

  A Nebulex stream is a named logical channel (topic) where cache entry events
  are published and consumed. It enables real-time monitoring and reaction to
  cache operations like insertions, updates, and deletions.

  ### Key Features

  - **Real-time Event Streaming**: React to cache operations as they happen.
  - **Partitioned Consumption**: Scale event processing across multiple
    processes.
  - **Flexible Event Filtering**: Subscribe to specific event types.
  - **Distributed by Design**: Built on Phoenix.PubSub for cluster-wide event
    distribution.

  ### Core Concepts

  - **Stream**: A named channel for cache events.
  - **Event**: A cache operation (insert, update, delete, etc.).
  - **Partition**: A subdivision of a stream for parallel processing.
  - **Subscriber**: A process that receives events from a stream.

  ## Event Types

  Cache entry events include:

  - `:inserted` - New cache entry created.
  - `:updated` - Existing cache entry modified.
  - `:deleted` - Cache entry removed.
  - `:expired` - Cache entry expired (if supported by adapter).
  - `:evicted` - Cache entry evicted due to size limits.

  ## Usage

  First, define a Nebulex cache using `Nebulex.Streams`:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :nebulex_streams,
          adapter: Nebulex.Adapters.Local

        use Nebulex.Streams
      end

  Then, add the cache and the stream to your application's supervision tree:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache}
        ]

        Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
      end

  The stream setup is ready. Now processes can subscribe and listen for cache
  events. For example, you can use a `GenServer`:

      defmodule MyApp.Cache.EventHandler do
        use GenServer

        @doc false
        def start_link(args) do
          GenServer.start_link(__MODULE__, args)
        end

        @impl true
        def init(_args) do
          # Subscribe the process to the cache topic
          :ok = MyApp.Cache.subscribe()

          {:ok, nil}
        end

        @impl true
        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          # Your logic for handling the event
          IO.inspect(event)

          {:noreply, state}
        end
      end

  Remember to add the event handler to your application's supervision tree:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache},
          MyApp.Cache.EventHandler
        ]

        Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
      end

  All the pieces are in place. You can run cache actions to see how events are handled:

      iex> MyApp.Cache.put("foo", "bar")
      :ok

      #=> MyApp.Cache.EventHandler:
      %Nebulex.Event.CacheEntryEvent{
        cache: MyApp.Cache,
        name: MyApp.Cache,
        type: :inserted,
        target: {:key, "foo"},
        command: :put,
        metadata: %{
          node: :nonode@nohost,
          pid: #PID<0.241.0>,
          partition: nil,
          partitions: nil,
          topic: "Elixir.MyApp.Cache:inserted"
        }
      }

  ## Partitions

  If a stream were constrained to be consumed by a single process only, that
  would place a significant limit on the system's scalability. While it could
  manage many streams across many machines (Phoenix.PubSub is distributed),
  a single topic could not handle too many events. Fortunately,
  `Nebulex.Streams` provides partitioning capabilities.

  Partitioning breaks a single topic into multiple ones, each consumed by a
  separate process. This allows the consumer workload to be split among many
  processes and nodes in the cluster.

  ### Example: Partitioned Event Processing

  First, create a supervisor to set up the pool of processes:

      defmodule MyApp.Cache.EventHandler.Supervisor do
        use Supervisor

        def start_link(partitions) do
          Supervisor.start_link(__MODULE__, partitions, name: __MODULE__)
        end

        @impl true
        def init(partitions) do
          children =
            for p <- 0..(partitions - 1) do
              Supervisor.child_spec({MyApp.Cache.EventHandler, p},
                id: {MyApp.Cache.EventHandler, p}
              )
            end

          Supervisor.init(children, strategy: :one_for_one)
        end
      end

  Then, modify the event handler to subscribe to a specific partition:

      defmodule MyApp.Cache.EventHandler do
        use GenServer

        @doc false
        def start_link(partition) do
          GenServer.start_link(__MODULE__, partition)
        end

        @impl true
        def init(partition) do
          # Subscribe the process to the cache topic partition
          :ok = MyApp.Cache.subscribe(partition: partition)

          {:ok, %{partition: partition}}
        end

        @impl true
        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          # Your logic for handling the event
          IO.inspect(event)

          {:noreply, state}
        end
      end

  Update the application's supervision tree:

      # lib/my_app/application.ex
      def start(_type, _args) do
        partitions = System.schedulers_online()

        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache, partitions: partitions},
          {MyApp.Cache.EventHandler.Supervisor, partitions}
        ]

        Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
      end

  Try running a cache action again:

      iex> MyApp.Cache.put("foo", "bar")
      :ok

      #=> MyApp.Cache.EventHandler:
      %Nebulex.Event.CacheEntryEvent{
        cache: MyApp.Cache,
        name: MyApp.Cache,
        type: :inserted,
        target: {:key, "foo"},
        command: :put,
        metadata: %{
          node: :nonode@nohost,
          pid: #PID<0.248.0>,
          partition: 4,
          partitions: 12,
          topic: "Elixir.MyApp.Cache:4:inserted"
        }
      }

  ## Advanced Usage Patterns

  ### Event Filtering and Processing

  ```elixir
  defmodule MyApp.EventProcessor do
    use GenServer

    def init(_) do
      # Subscribe to specific events only
      :ok = MyApp.Cache.subscribe(events: [:inserted, :updated])
      {:ok, %{}}
    end

    def handle_info(%CacheEntryEvent{type: :inserted, target: {:key, key}}, state) do
      # Handle new entries
      Logger.info("New cache entry: \#{key}")
      {:noreply, state}
    end

    def handle_info(%CacheEntryEvent{type: :updated, target: {:key, key}}, state) do
      # Handle updates
      Logger.info("Updated cache entry: \#{key}")
      {:noreply, state}
    end
  end
  ```

  ### Custom Hash Functions

      # Route events based on key patterns
      def custom_hash(%CacheEntryEvent{target: {:key, key}}) do
        case String.starts_with?(key, "user:") do
          true -> 0   # User events to partition 0
          false -> 1  # Other events to partition 1
        end
      end

      {Nebulex.Streams, cache: MyCache, partitions: 2, hash: &MyApp.custom_hash/1}

  ## Adapter-specific telemetry events

  This adapter exposes following Telemetry events:

    * `[nebulex, :streams, :listener_registered]` - Dispatched by the
      adapter when the stream listener is registered.

      * Measurements: `%{}`
      * Metadata:

        ```
        %{
          cache: atom(),
          name: atom(),
          pubsub: atom(),
          partitions: non_neg_integer() | nil
        }
        ```

    * `[nebulex, :streams, :listener_unregistered]` - Dispatched by the
      adapter when the stream listener is unregistered.

      * Measurements: `%{}`
      * Metadata:

        ```
        %{
          cache: atom(),
          name: atom(),
          pubsub: atom(),
          partitions: non_neg_integer() | nil
        }
        ```

    * `[nebulex, :streams, :broadcast]` - Dispatched by the
      adapter when a cache event is broadcast.

      * Measurements: `%{}`
      * Metadata:

        ```
        %{
          status: :ok | :error,
          reason: any(),
          pubsub: atom(),
          topic: String.t(),
          event: Nebulex.Event.t()
        }
        ```

  ## Troubleshooting

  ### Common Issues

  **Events not received**
  - Ensure the stream server is started before subscribing
  - Check that the cache is configured correctly
  - Verify Phoenix.PubSub is running

  **High memory usage**
  - Reduce number of partitions
  - Implement event filtering to reduce message volume
  - Monitor process mailbox sizes

  **Performance issues**
  - Increase partition count for CPU-bound processing
  - Use `:broadcast_from` to avoid self-messages
  - Implement batching in event handlers

  ### Debugging

  Enable logging to see stream activity:

      config :logger, level: :debug

      # Add telemetry handler for logging stream events
      :telemetry.attach_many(
        "logging-stream-events",
        [
          [:nebulex, :streams, :broadcast],
          [:nebulex, :streams, :listener_registered],
          [:nebulex, :streams, :listener_unregistered]
        ],
        &MyApp.TelemetryHandler.handle_event/4,
        nil
      )

  The handler module should look like this:

      defmodule MyApp.TelemetryHandler do
        require Logger

        def handle_event(event, _measurements, metadata, _config) do
          Logger.info("Event \#{Enum.join(event, ".")}: \#{inspect(metadata)}")
        end
      end

  """

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams.{Options, Server}
  alias Phoenix.PubSub

  import Nebulex.Utils, only: [wrap_error: 2]

  ## Types and constants

  @typedoc """
  The metadata associated with the stream.

  It is a map with the following keys:

    * `:cache` - The defined cache module.
    * `:name` - The name of the cache supervisor process.
    * `:pubsub` - The name of `Phoenix.PubSub` system to use.
    * `:partitions` - The number of partitions.
    * `:partition` - The partition to subscribe to.

  """
  @type metadata() :: %{
          required(:cache) => atom(),
          required(:name) => atom(),
          required(:pubsub) => atom(),
          required(:partitions) => non_neg_integer() | nil,
          required(:partition) => non_neg_integer()
        }

  @typedoc "The type used for the function passed to the `:hash` option."
  @type hash() :: (Nebulex.Event.t() -> non_neg_integer() | :none)

  # The registry used to store the stream servers
  @registry Nebulex.Streams.Registry

  # Inline common instructions
  @compile {:inline, registry: 0, server_name: 1, topic: 3}

  ## Inherited behaviour

  @doc false
  defmacro __using__(_opts) do
    quote do
      @doc """
      Subscribes the calling process to cache events.

      This is a convenience function that calls `Nebulex.Streams.subscribe/2`
      with the module name.

      ## Examples

          iex> MyCache.subscribe()
          :ok

          iex> MyCache.subscribe(events: [:inserted, :deleted])
          :ok
      """
      def subscribe(opts \\ []), do: subscribe(__MODULE__, opts)

      @doc """
      Same as `subscribe/1` but raises an exception if an error occurs.
      """
      def subscribe!(opts \\ []), do: subscribe!(__MODULE__, opts)

      @doc false
      defdelegate subscribe(name, opts), to: unquote(__MODULE__)

      @doc false
      defdelegate subscribe!(name, opts), to: unquote(__MODULE__)
    end
  end

  ## API

  @doc """
  Starts a stream server.

  ## Options

  #{Options.start_options_docs()}

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Server

  @doc """
  Subscribes the caller to the cache events topic (a.k.a cache event stream).

  ## Options

  #{Options.subscribe_options_docs()}

  ## Examples

  Although you can directly use `Nebulex.Streams.subscribe/2`, like this:

      iex> Nebulex.Streams.subscribe(MyApp.Cache)
      :ok
      iex> Nebulex.Streams.subscribe(MyApp.Cache, events: [:inserted, :deleted])
      :ok
      iex> Nebulex.Streams.subscribe(:my_cache, partition: 0)
      :ok

  It is recommended you do it from the cache itself:

      iex> MyApp.Cache.subscribe()
      :ok

  You can subscribe to specific events types:

      iex> MyApp.Cache.subscribe(events: [:inserted, :deleted])
      :ok

  In case you have partitions, you should use the option `:partition`:

      iex> MyApp.Cache.subscribe(partition: 0)
      :ok

  When using dynamic caches:

      iex> MyApp.Cache.subscribe(:my_cache)
      :ok
      iex> MyApp.Cache.subscribe(:my_cache, events: [:inserted, :deleted])
      :ok

  """
  @spec subscribe(cache_name :: atom(), opts :: keyword()) :: :ok | {:error, Nebulex.Error.t()}
  def subscribe(name, opts \\ []) do
    # Validate options
    opts = Options.validate_subscribe_opts!(opts)

    # Get the subscribe options
    events = Keyword.fetch!(opts, :events)
    partition = Keyword.get(opts, :partition)

    # Get the stream metadata
    %{pubsub: pubsub, partitions: partitions} = lookup_meta!(name)

    # Make the subscriptions
    events
    |> Enum.map(&topic(name, &1, check_partition(partitions, partition)))
    |> Enum.reduce_while({:ok, []}, fn topic, {res, acc} ->
      case PubSub.subscribe(pubsub, topic) do
        :ok ->
          # Continue with the subscriptions
          {:cont, {res, [topic | acc]}}

        {:error, reason} ->
          # Unsubscribes the caller from the previous subscriptions
          :ok = Enum.each(acc, &PubSub.unsubscribe(pubsub, &1))

          # Wrap the error
          e =
            wrap_error Nebulex.Error,
              module: __MODULE__,
              reason: {:nbx_stream_subscribe_error, reason},
              name: name,
              opts: opts

          # Halt with error
          {:halt, {e, acc}}
      end
    end)
    |> elem(0)
  end

  @doc """
  Same as `subscribe/2` but raises an exception if an error occurs.
  """
  @spec subscribe!(cache_name :: atom(), opts :: keyword()) :: :ok
  def subscribe!(name, opts \\ []) do
    with {:error, reason} <- subscribe(name, opts) do
      raise reason
    end
  end

  ## Internal API

  @doc """
  Returns the registry used to store the stream servers.
  """
  @spec registry() :: atom()
  def registry, do: @registry

  @doc """
  Returns the server name.
  """
  @spec server_name(atom()) :: {atom(), atom()}
  def server_name(name), do: {__MODULE__, name}

  @doc """
  Returns the child specification for the stream.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  @doc """
  Returns the stream metadata for the given name or `nil` if the stream server
  is not found.
  """
  @spec lookup_meta(any()) :: metadata() | nil
  def lookup_meta(name) do
    case Registry.lookup(@registry, server_name(name)) do
      [{_pid, state}] ->
        Map.take(state, [:cache, :name, :pubsub, :partitions, :partition])

      [] ->
        nil
    end
  end

  @doc """
  Same as `lookup_meta/1` but raises an exception if the stream server is not
  found.
  """
  @spec lookup_meta!(any()) :: metadata()
  def lookup_meta!(name) do
    name
    |> lookup_meta()
    |> Kernel.||(raise "Stream server not found: #{inspect(name)}")
  end

  @doc """
  The event listener function broadcasts the events via `Phoenix.PubSub`.

  > #### `broadcast_event/1` {: .info}
  >
  > This function is used internally by the stream server to broadcast the
  > events via `Phoenix.PubSub`.
  """
  @spec broadcast_event(Nebulex.Event.t()) :: :ok | {:error, any()}
  def broadcast_event(
        %CacheEntryEvent{
          cache: cache,
          name: name,
          type: type,
          metadata: %{
            pubsub: pubsub,
            partitions: partitions,
            broadcast_fun: broadcast_fun
          }
        } = event
      ) do
    case get_partition(event) do
      :none ->
        # Discard the event
        :ok

      partition ->
        # Get the topic
        topic = topic(name || cache, type, partition)

        # Build new event metadata
        metadata = %{
          topic: topic,
          partition: partition,
          partitions: partitions,
          node: node(),
          pid: self()
        }

        # Broadcast the event
        do_broadcast(broadcast_fun, pubsub, topic, %{event | metadata: metadata})
    end
  end

  @doc """
  The default hash function is used when the `:partitions` option is configured.
  """
  @spec default_hash(Nebulex.Event.t()) :: non_neg_integer()
  def default_hash(%CacheEntryEvent{metadata: %{partitions: partitions}} = event) do
    :erlang.phash2(event, partitions)
  end

  ## Error formatter

  @doc false
  def format_error({:nbx_stream_subscribe_error, reason}, metadata) do
    name = Keyword.fetch!(metadata, :name)
    opts = Keyword.fetch!(metadata, :opts)

    "#{inspect(__MODULE__)}.subscribe(#{inspect(name)}, #{inspect(opts)}) " <>
      "failed with reason: #{inspect(reason)}"
  end

  ## Private functions

  # Build the topic name
  defp topic(name, event, nil), do: "#{name}:#{event}"
  defp topic(name, event, partition), do: "#{name}:#{partition}:#{event}"

  # The option `:partitions` is not configured
  defp get_partition(%CacheEntryEvent{metadata: %{partitions: nil}}) do
    nil
  end

  # The option `:partitions` is configured, then compute the partition
  defp get_partition(%CacheEntryEvent{metadata: %{hash: hash}} = event) do
    hash.(event)
  end

  # The option `:partitions` is not configured
  defp check_partition(nil, _p) do
    nil
  end

  # The option `:partition` is not provided
  defp check_partition(n, nil) do
    :erlang.phash2(self(), n)
  end

  # The option `:partition` is provided
  defp check_partition(n, p) when p < n do
    p
  end

  # The option `:partition` is provided but invalid
  defp check_partition(n, p) do
    raise NimbleOptions.ValidationError,
          "invalid value for :partition option: expected integer >= 0 " <>
            "and < #{inspect(n)} (total number of partitions), got: #{inspect(p)}"
  end

  defp do_broadcast(:broadcast, pubsub, topic, event) do
    pubsub
    |> PubSub.broadcast(topic, event)
    |> handle_broadcast_response(pubsub, topic, event)
  end

  defp do_broadcast(:broadcast_from, pubsub, topic, event) do
    pubsub
    |> PubSub.broadcast_from(self(), topic, event)
    |> handle_broadcast_response(pubsub, topic, event)
  end

  defp handle_broadcast_response({:error, reason}, pubsub, topic, event) do
    dispatch_telemetry_event(:error, reason, pubsub, topic, event)
  end

  defp handle_broadcast_response(:ok, pubsub, topic, event) do
    dispatch_telemetry_event(:ok, nil, pubsub, topic, event)
  end

  defp dispatch_telemetry_event(status, reason, pubsub, topic, event) do
    :telemetry.execute(
      [:nebulex, :streams, :broadcast],
      %{},
      %{status: status, reason: reason, pubsub: pubsub, topic: topic, event: event}
    )
  end
end
