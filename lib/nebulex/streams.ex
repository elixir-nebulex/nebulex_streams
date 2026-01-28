defmodule Nebulex.Streams do
  @moduledoc """
  Real-time event streaming for Nebulex caches.

  `Nebulex.Streams` enables processes to subscribe to and react to cache entry
  events as they occur. Built on `Phoenix.PubSub`, it provides a pub/sub
  infrastructure for monitoring cache operations and coordinating state
  changes across processes and nodes.

  ## Overview

  When cache operations (put, delete, update, etc.) occur on a Nebulex cache,
  events are emitted. A Nebulex stream provides a named logical channel where
  these events are published. Processes can subscribe to the stream to receive
  events and react to them in real-time.

  ### Key Features

  - **Real-time Events** - React to cache operations as they happen, enabling
    event-driven architectures.
  - **Partitioned Streams** - Scale event processing across multiple independent
    processes for high-volume scenarios.
  - **Event Filtering** - Subscribe to specific event types (inserted, updated,
    deleted, expired, evicted) to reduce processing overhead.
  - **Distributed by Design** - Built on Phoenix.PubSub for seamless
    cluster-wide event distribution.
  - **Telemetry Integration** - Comprehensive observability for monitoring
    streams and debugging.

  ## When to Use Streams

  Streams are useful when you need to:

  - **React to cache changes**: Invalidate related caches or trigger workflows
    when data changes.
  - **Monitor cache activity**: Track cache hit rates, event volumes, or
    performance.
  - **Keep data in sync**: Ensure consistency across multiple cache instances or
    systems-of-record in distributed scenarios.
  - **Implement cache invalidation patterns**: Propagate cache updates to
    databases or other systems.
  - **Build event-driven features**: React to data mutations for notifications,
    analytics, or state updates.

  ## Core Concepts

  - **Stream**: A named, logical channel for events from a specific cache.
  - **Event**: A representation of a cache operation (insert, update, delete,
    expire, evict).
  - **Topic**: An internal PubSub topic routing events to subscribers.
  - **Partition**: A subdivision of the stream for parallel, concurrent
    processing.
  - **Subscriber**: A process that receives and handles events from a stream.

  ## Event Types

  Cache entry events (`Nebulex.Event.CacheEntryEvent`) represent different
  operations on cache entries:

  - `:inserted` - A new cache entry was created (e.g., first `put`).
  - `:updated` - An existing cache entry was modified
    (e.g., `put` overwrites value).
  - `:deleted` - A cache entry was explicitly removed (e.g., `delete`).
  - `:expired` - A cache entry reached its TTL (if supported by adapter).
  - `:evicted` - A cache entry was removed due to capacity limits or eviction
    policy.

  ## Getting Started

  ### Step 1: Add Streaming to Your Cache

  Extend your Nebulex cache with streaming capabilities:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Local

        use Nebulex.Streams
      end

  ### Step 2: Start the Stream Server

  Add the stream server to your application's supervision tree. The stream
  server must be started **after** the cache:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache}
        ]

        opts = [strategy: :rest_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ### Step 3: Create an Event Handler

  Implement a GenServer that subscribes to cache events:

      defmodule MyApp.EventHandler do
        use GenServer

        def start_link(_) do
          GenServer.start_link(__MODULE__, nil)
        end

        def init(_) do
          # Subscribe to all cache events
          :ok = MyApp.Cache.subscribe()
          {:ok, nil}
        end

        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          # Process the event
          case event.type do
            :inserted -> handle_insert(event)
            :updated -> handle_update(event)
            :deleted -> handle_delete(event)
            _ -> :ok
          end

          {:noreply, state}
        end

        defp handle_insert(%{target: {:key, key}}) do
          IO.puts("Cache insert: \#{key}")
        end

        defp handle_update(%{target: {:key, key}}) do
          IO.puts("Cache update: \#{key}")
        end

        defp handle_delete(%{target: {:key, key}}) do
          IO.puts("Cache delete: \#{key}")
        end
      end

  ### Step 4: Start the Event Handler

  Add your event handler to the supervision tree:

      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache},
          MyApp.EventHandler
        ]

        opts = [strategy: :rest_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ### Step 5: Verify It Works

  Perform cache operations and observe the events:

      iex> MyApp.Cache.put("user:123", %{name: "Alice"})
      Cache insert: user:123
      :ok

      iex> MyApp.Cache.put("user:123", %{name: "Bob"})
      Cache update: user:123
      :ok

      iex> MyApp.Cache.delete("user:123")
      Cache delete: user:123
      :ok

  ## Partitions

  By default, all cache events go to a single topic and all subscribers receive
  all events. This works fine for low event volumes, but becomes a bottleneck
  under high load.

  Partitions divide the event stream into multiple independent sub-streams,
  each with its own topic. This allows:

  - **Parallel Processing** - Multiple processes (one per partition) process
    events concurrently.
  - **Scalability** - Handle higher event volumes without overwhelming a single
    process.
  - **Load Balancing** - Distribute event handling across CPU cores or cluster
    nodes.
  - **Ordering Guarantees** - Events within a partition maintain order; events
    to different partitions can be processed concurrently.

  ### How Partitions Work

  1. When a cache event occurs, a **hash function** determines which partition
    it belongs to.
  2. The event is published to that partition's topic.
  3. Subscribers can choose to subscribe to specific partitions or all
    partitions.
  4. Each partition can have independent subscriber(s) processing events in
    parallel.

  ### When to Use Partitions

  - **Want parallelism** - Leverage multiple CPU cores for event processing
    (e.g., high event volume).
  - **CPU-bound processing** - Event handlers do significant computation.
  - **I/O-bound processing** - Event handlers call external services or
    databases.

  ### Example: Partitioned Event Processing

  To use partitions, you need to:

  1. Configure the stream with a partition count.
  2. Create a pool of event handler processes (one per partition).
  3. Have each handler subscribe to its specific partition.

  **Step 1: Configure stream with partitions**

      def start(_type, _args) do
        # Use one partition per CPU core
        partitions = System.schedulers_online()

        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache, partitions: partitions},
          {MyApp.EventHandler.Pool, partitions}
        ]

        Supervisor.start_link(children, strategy: :rest_for_one)
      end

  **Step 2: Create a pool supervisor for event handlers**

      defmodule MyApp.EventHandler.Pool do
        use Supervisor

        def start_link(partitions) do
          Supervisor.start_link(__MODULE__, partitions, name: __MODULE__)
        end

        def init(partitions) do
          children =
            for partition <- 0..(partitions - 1) do
              Supervisor.child_spec(
                {MyApp.EventHandler, partition},
                id: {MyApp.EventHandler, partition}
              )
            end

          Supervisor.init(children, strategy: :one_for_one)
        end
      end

  **Step 3: Create partition-aware event handler**

      defmodule MyApp.EventHandler do
        use GenServer

        def start_link(partition) do
          GenServer.start_link(__MODULE__, partition)
        end

        def init(partition) do
          # Subscribe to events for this specific partition only
          :ok = MyApp.Cache.subscribe(partition: partition)

          {:ok, %{partition: partition, count: 0}}
        end

        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          # Each handler processes its partition independently
          handle_event(event, state)

          {:noreply, %{state | count: state.count + 1}}
        end

        defp handle_event(%{type: :inserted, target: {:key, key}}, state) do
          IO.puts("Partition \#{state.partition}: inserted \#{key}")
        end

        defp handle_event(%{type: :deleted, target: {:key, key}}, state) do
          IO.puts("Partition \#{state.partition}: deleted \#{key}")
        end

        defp handle_event(_, _), do: :ok
      end

  **Step 4: Observe partitioned event distribution**

      iex> MyApp.Cache.put("foo", "bar")
      Partition 2: inserted foo
      :ok

      iex> MyApp.Cache.put("baz", "qux")
      Partition 5: inserted baz
      :ok

  Note that different cache keys are routed to different partitions. The
  partition number in the event metadata shows which partition processed
  the event:

      %Nebulex.Event.CacheEntryEvent{
        ...
        metadata: %{
          partition: 2,        # This event went to partition 2
          partitions: 8,       # Out of 8 total partitions
          topic: "Elixir.MyApp.Cache:2:inserted"
        }
      }

  ## Advanced Usage Patterns

  ### Event Filtering by Type

  Subscribe only to the events you care about to reduce message overhead:

      defmodule MyApp.DeleteTracker do
        use GenServer

        def init(_) do
          # Only subscribe to deletion events, ignore everything else
          :ok = MyApp.Cache.subscribe(events: [:deleted])
          {:ok, %{deleted_count: 0}}
        end

        def handle_info(%Nebulex.Event.CacheEntryEvent{type: :deleted, target: {:key, key}}, state) do
          IO.puts("Entry deleted: \#{key}")
          {:noreply, %{state | deleted_count: state.deleted_count + 1}}
        end
      end

  ### Custom Hash Functions for Domain Routing

  Use custom hash functions to route events to partitions based on business
  logic:

      defmodule MyApp.DomainAwareHash do
        def hash(%Nebulex.Event.CacheEntryEvent{target: {:key, key}}) do
          cond do
            String.starts_with?(key, "user:") -> 0     # User events -> partition 0
            String.starts_with?(key, "session:") -> 1  # Session events -> partition 1
            String.starts_with?(key, "temp:") -> :none # Discard temporary entries
            true -> 2                                  # Everything else -> partition 2
          end
        end
      end

      # Configure the stream with custom hash
      {Nebulex.Streams,
       cache: MyApp.Cache,
       partitions: 3,
       hash: &MyApp.DomainAwareHash.hash/1}

  ### Synchronizing Related Caches

  Invalidate dependent caches when primary cache changes:

      defmodule MyApp.CacheSynchronizer do
        use GenServer

        def start_link(primary_cache) do
          GenServer.start_link(__MODULE__, primary_cache)
        end

        def init(primary_cache) do
          :ok = primary_cache.subscribe()
          {:ok, %{primary_cache: primary_cache}}
        end

        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          # When primary cache updates, invalidate dependent caches
          case event do
            %{type: :deleted, target: {:key, key}} ->
              # Clean up derived data in other caches
              MyApp.DerivedCache.delete(key)
              MyApp.AggregateCache.delete(key)

            %{type: :updated, target: {:key, key}} ->
              # Invalidate caches that depend on this key
              MyApp.DerivedCache.delete(key)

            _ ->
              :ok
          end

          {:noreply, state}
        end
      end

  ### Batch Processing Events

  Collect events and process them in batches for efficiency:

      defmodule MyApp.BatchEventProcessor do
        use GenServer

        def start_link(_) do
          GenServer.start_link(__MODULE__, nil)
        end

        def init(_) do
          :ok = MyApp.Cache.subscribe()
          # Process batches every 1 second
          Process.send_interval(self(), :flush_batch, 1_000)
          {:ok, %{batch: []}}
        end

        def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
          {:noreply, %{state | batch: [event | state.batch]}}
        end

        def handle_info(:flush_batch, %{batch: []} = state) do
          {:noreply, state}
        end

        def handle_info(:flush_batch, %{batch: batch} = state) do
          # Process accumulated events at once
          process_batch(Enum.reverse(batch))
          {:noreply, %{state | batch: []}}
        end

        defp process_batch(events) do
          # More efficient than processing one by one
          IO.inspect("Processing batch of \#{length(events)} events")
        end
      end

  ## Configuration

  See `start_link/1` for available options.

  ## Telemetry Events

  `Nebulex.Streams` emits telemetry events for observability and monitoring:

  ### Listener Lifecycle Events

  **`[:nebulex, :streams, :listener_registered]`** - Fired when a stream
  listener is registered. Metadata includes:

    * `:cache` - The cache module.
    * `:name` - Cache instance name.
    * `:pubsub` - PubSub instance name.
    * `:partitions` - Number of partitions (nil if not partitioned).

  **`[:nebulex, :streams, :listener_unregistered]`** - Fired when a stream
  listener stops. Same metadata as `listener_registered`.

  ### Event Broadcast Events

  **`[:nebulex, :streams, :broadcast]`** - Fired when a cache event is broadcast
  to subscribers. Metadata includes:

    * `:status` - `:ok` or `:error`.
    * `:reason` - Error reason (nil on success).
    * `:pubsub` - PubSub instance name.
    * `:topic` - The internal topic name.
    * `:event` - The `CacheEntryEvent` that was broadcast.

  ## Best Practices

  ### 1. Use the Right Partition Count

      # Low volume, simple processing: no partitions needed
      {Nebulex.Streams, cache: MyApp.Cache}

      # Normal volume: use CPU core count
      partitions = System.schedulers_online()
      {Nebulex.Streams, cache: MyApp.Cache, partitions: partitions}

      # Very high volume or I/O-bound: use more than cores
      {Nebulex.Streams, cache: MyApp.Cache, partitions: System.schedulers_online() * 2}

  ### 2. Filter Events You Care About

      # ✓ Good: only subscribe to events you need
      :ok = MyApp.Cache.subscribe(events: [:deleted])

      # ✗ Avoid: subscribing to all events if you only handle some
      :ok = MyApp.Cache.subscribe()

  ### 3. Handle Errors Gracefully

      def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
        case process_event(event) do
          :ok ->
            {:noreply, state}

          {:error, reason} ->
            Logger.error("Failed to process event: \#{inspect(reason)}")
            {:noreply, state}
        end
      end

  ### 4. Monitor via Telemetry

  Track stream health and performance:

      :telemetry.attach_many(
        "stream-monitoring",
        [
          [:nebulex, :streams, :listener_registered],
          [:nebulex, :streams, :listener_unregistered],
          [:nebulex, :streams, :broadcast]
        ],
        &MyApp.StreamTelemetry.handle/4,
        nil
      )

  """

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams.{Options, Server}
  alias Phoenix.PubSub

  import Nebulex.Utils, only: [wrap_error: 2]

  ## Types and constants

  @typedoc """
  The metadata associated with the stream.

  A map containing runtime information about the stream configuration:

    * `:cache` - The defined cache module.
    * `:name` - The name of the cache supervisor process (same as cache if not
      dynamic).
    * `:pubsub` - The name of `Phoenix.PubSub` system being used.
    * `:partitions` - The number of partitions (nil if not partitioned).
    * `:partition` - The specific partition for subscription.

  This metadata is useful for debugging and understanding stream configuration.
  """
  @type metadata() :: %{
          required(:cache) => atom(),
          required(:name) => atom(),
          required(:pubsub) => atom(),
          required(:partitions) => non_neg_integer() | nil,
          required(:partition) => non_neg_integer()
        }

  @typedoc """
  A hash function for custom partition routing.

  Receives a cache event and returns:

    * A partition number (`0..(partitions-1)`) - routes the event to that
      partition.
    * `:none` - discards the event completely

  The hash function is only invoked when the `:partitions` option is configured.
  """
  @type hash() :: (Nebulex.Event.t() -> non_neg_integer() | :none)

  # The registry used to store the stream servers
  @registry Nebulex.Streams.Registry

  # Inline common instructions
  @compile {:inline, registry: 0, server_name: 1, topic: 3}

  ## Inherited behaviour

  @doc false
  defmacro __using__(_opts) do
    quote do
      @doc false
      def subscribe(opts \\ []), do: subscribe(__MODULE__, opts)

      @doc false
      def subscribe!(opts \\ []), do: subscribe!(__MODULE__, opts)

      @doc false
      defdelegate subscribe(name, opts), to: unquote(__MODULE__)

      @doc false
      defdelegate subscribe!(name, opts), to: unquote(__MODULE__)
    end
  end

  ## API

  @doc """
  Starts a stream server for a cache.

  This function starts a stream server that registers itself as an event
  listener with the cache. The server then broadcasts cache events to
  subscribed processes via `Phoenix.PubSub`.

  The stream server is typically started as part of your application's
  supervision tree.

  ## Options

  #{Options.start_options_docs()}

  ## Examples

  Start a simple stream without partitions:

      {Nebulex.Streams, cache: MyApp.Cache}

  Start a stream with 4 partitions for parallel processing:

      {Nebulex.Streams, cache: MyApp.Cache, partitions: 4}

  Start a stream with a custom hash function:

      {Nebulex.Streams, cache: MyApp.Cache, partitions: 2, hash: &MyApp.custom_hash/1}

  Use a custom PubSub instance:

      {Nebulex.Streams, cache: MyApp.Cache, pubsub: MyApp.CustomPubSub}

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  defdelegate start_link(opts \\ []), to: Server

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
  Subscribes the calling process to cache entry events.

  This function subscribes the current process to events from a Nebulex stream.
  The process will receive `Nebulex.Event.CacheEntryEvent` messages in its
  mailbox.

  ## Options

  #{Options.subscribe_options_docs()}

  ## Examples

  The recommended approach is to subscribe from the cache module itself:

      iex> MyApp.Cache.subscribe()
      :ok

  You can also use `Nebulex.Streams.subscribe/2` directly with the cache name:

      iex> Nebulex.Streams.subscribe(MyApp.Cache)
      :ok

  Subscribe to specific event types only:

      iex> MyApp.Cache.subscribe(events: [:inserted, :deleted])
      :ok

  When using partitioned streams, subscribe to a specific partition:

      iex> MyApp.Cache.subscribe(partition: 0)
      :ok

  With dynamic caches, pass the cache instance name:

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

  ## Examples

      iex> MyApp.Cache.subscribe!()
      :ok

      iex> MyApp.Cache.subscribe!(partition: 0)
      :ok

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
  Returns the stream metadata for the given cache name.

  This function retrieves runtime configuration details about a stream server.

  ## Examples

      iex> Nebulex.Streams.lookup_meta(MyApp.Cache)
      %{
        cache: MyApp.Cache,
        name: MyApp.Cache,
        pubsub: Nebulex.Streams.PubSub,
        partitions: 4,
        partition: nil
      }

      iex> Nebulex.Streams.lookup_meta(:not_started)
      nil

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

  ## Examples

      iex> Nebulex.Streams.lookup_meta!(MyApp.Cache)
      %{...}

      iex> Nebulex.Streams.lookup_meta!(:not_started)
      ** (RuntimeError) stream server not found: :not_started

  """
  @spec lookup_meta!(any()) :: metadata()
  def lookup_meta!(name) do
    name
    |> lookup_meta()
    |> Kernel.||(raise "stream server not found: #{inspect(name)}")
  end

  @doc """
  Broadcasts a cache event to all interested subscribers via Phoenix.PubSub.

  This is the internal callback function registered with the cache as an event
  listener. It is called automatically whenever a cache operation (put, delete,
  etc.) occurs.

  > #### Internal Use {: .warning}
  >
  > This function is for internal use by Nebulex.Streams and the cache event
  > listener system. Do not call this directly in application code.
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
  The default hash function for partitioning events.
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
