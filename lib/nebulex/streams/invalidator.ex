defmodule Nebulex.Streams.Invalidator do
  @moduledoc """
  Automatic cache invalidation for distributed Nebulex caches.

  The `Invalidator` watches cache events and removes stale entries from the
  local cache when changes occur. It implements a "fail-safe" approach to cache
  consistency in distributed systems: when in doubt, remove entries to force
  fresh data fetches.

  ## What It Does

  The invalidator subscribes to cache events and automatically deletes entries
  when they change. This ensures that:

  - **Data Freshness**: After an entry changes on any node, other nodes'
    cached copies are invalidated, forcing fetches from the System-Of-Record
    (SoR).
  - **Consistency**: All nodes eventually see the same data.
  - **Simplicity**: No need to manually invalidate dependent caches.

  ## When to Use

  Use the Invalidator when:

  - **Distributed caches**: Running the same cache on multiple nodes.
  - **Data consistency required**: Can't tolerate stale data being read.
  - **Simple cache patterns**: Using cache for basic read-through or aside
    patterns.
  - **System-Of-Record available**: Fresh data can be fetched when cache misses
    occur.

  ## How It Works

  ```
  Node A Cache              Node B Cache
  ┌──────────┐             ┌──────────┐
  │ key: val │             │ key: val │
  └──────────┘             └──────────┘
       │                         │
       │ Cache.delete("key")     │
       │                         │
       └──► Event Stream ────────┘
                │
                ▼ (from another node)
           [Invalidator]
                │
                ▼
           Delete "key" locally
                │
                ▼
           Next read = cache miss
           Fetch from SoR
  ```

  The process:
  1. An entry is modified/deleted on Node A (e.g., `Cache.delete("key")`).
  2. Cache fires an event (`:deleted`, `:updated`, etc.).
  3. Event is streamed via `Nebulex.Streams` to all subscribed nodes.
  4. Invalidator on Node B receives the event.
  5. Invalidator deletes the entry from Node B's cache.
  6. Next read on Node B: cache miss → fetch fresh from SoR.

  ## Event Scope

  The `:event_scope` option controls which events trigger invalidation:

  ### `:remote` (default, recommended)

  Only invalidate when events come from remote nodes. This prevents
  double-invalidation and is the safest default for distributed scenarios.

      # Node A: Cache.delete("key")
      #   Event fires with metadata.node = :nodeA
      #
      # Node B: Sees event from :nodeA (remote)
      #   Invalidator deletes "key" from its cache
      #
      # Node A: Invalidator ignores the event (local node)
      #   Key already deleted, no need to invalidate

  ### `:local`

  Only invalidate when events come from the local node. Useful for single-node
  scenarios or when you want to invalidate related caches based on primary cache
  changes.

  ### `:all`

  Invalidate for all events regardless of origin. Rarely used but useful when
  you want to keep a backup/mirror cache perfectly in sync with all changes.

  ## Quick Start

  ### Step 1: Start the Stream Server

  First, ensure the stream server is running (see `Nebulex.Streams` for details):

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.Cache,
            {Nebulex.Streams, cache: MyApp.Cache},
            # Add more children...
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ### Step 2: Start the Invalidator

  Add the invalidator to your supervision tree **after** the stream:

      children = [
        MyApp.Cache,
        {Nebulex.Streams, cache: MyApp.Cache},
        {Nebulex.Streams.Invalidator, cache: MyApp.Cache}  # <-- Add this
      ]

      opts = [strategy: :rest_for_one, name: MyApp.Supervisor]
      Supervisor.start_link(children, opts)

  That's it! The invalidator now watches for events and removes stale entries.

  ### Step 3: Observe It Working

      # On Node A:
      iex> MyApp.Cache.put("user:123", %{name: "Alice"})
      :ok

      # On Node B (after a moment):
      iex> MyApp.Cache.get("user:123")  # Cache miss!
      nil
      # Fetch from SoR will refresh the data

  ## Dynamic Caches

  For dynamic caches started at runtime, use the `:name` option instead of
  `:cache`:

      # Start a dynamic cache
      {:ok, _pid} = MyApp.Cache.start_link(name: :my_cache)

      # Start stream for the dynamic cache
      {:ok, _pid} = Nebulex.Streams.start_link(cache: MyApp.Cache, name: :my_cache)

      # Start invalidator for the dynamic cache
      {:ok, _pid} = Nebulex.Streams.Invalidator.start_link(name: :my_cache)

  ## Partitioned Invalidators

  When the stream uses partitions, the invalidator automatically creates a
  worker per partition for parallel invalidation:

      # Stream with 4 partitions
      {Nebulex.Streams, cache: MyApp.Cache, partitions: 4}

      # Invalidator spawns 4 workers, one per partition
      {Nebulex.Streams.Invalidator, cache: MyApp.Cache}
      # This starts 4 invalidator processes, one per partition

  ## Options

  #{Nebulex.Streams.Invalidator.Options.options_docs()}

  ## Telemetry Events

  * `[:nebulex, :streams, :invalidator, :started]` - Dispatched when
    the invalidator worker starts.

    * Measurements: `%{system_time: non_neg_integer()}`
    * Metadata:

      ```
      %{
        cache: atom(),
        name: atom(),
        partition: non_neg_integer(),
        partitions: non_neg_integer(),
        start_time: integer(),
        event_scope: atom(),
        started_at: DateTime.t()
      }
      ```

  * `[:nebulex, :streams, :invalidator, :stopped]` - Dispatched when
    the invalidator worker stops.

    * Measurements: `%{duration: non_neg_integer()}`
    * Metadata:

      ```
      %{
        cache: atom(),
        name: atom(),
        partition: non_neg_integer(),
        partitions: non_neg_integer(),
        start_time: integer(),
        event_scope: atom(),
        stopped_at: DateTime.t()
        reason: term()
      }
      ```

  * `[:nebulex, :streams, :invalidator, :invalidate, :start]` - Dispatched when
    the invalidation process starts.

    * Measurements: `%{system_time: non_neg_integer()}`
    * Metadata:

      ```
      %{
        cache: atom(),
        name: atom(),
        partition: non_neg_integer(),
        partitions: non_neg_integer(),
        start_time: integer(),
        event_scope: atom(),
        event: Nebulex.Event.CacheEntryEvent.t(),
        status: atom(),
        reason: term(),
        deleted: non_neg_integer()
      }
      ```

  * `[:nebulex, :streams, :invalidator, :invalidate, :stop]` - Dispatched when
    the invalidation process stops.

    * Measurements: `%{duration: non_neg_integer()}`
    * Metadata:

      ```
      %{
        cache: atom(),
        name: atom(),
        partition: non_neg_integer(),
        partitions: non_neg_integer(),
        start_time: integer(),
        event_scope: atom(),
        event: Nebulex.Event.CacheEntryEvent.t(),
        status: atom(),
        reason: term(),
        deleted: non_neg_integer()
      }
      ```

  * `[:nebulex, :streams, :invalidator, :unhandled_event]` - Dispatched when
    the invalidator receives an unhandled event.

    * Measurements: `%{system_time: non_neg_integer()}`
    * Metadata:

      ```
      %{
        cache: atom(),
        name: atom(),
        partition: non_neg_integer(),
        partitions: non_neg_integer(),
        start_time: integer(),
        event_scope: atom(),
        unhandled_event: term()
      }
      ```

  """

  use Supervisor

  alias Nebulex.Streams
  alias Nebulex.Streams.Invalidator.{Options, Worker}

  import Nebulex.Utils, only: [camelize_and_concat: 1]

  ## API

  @doc """
  Starts an invalidator supervisor that watches cache events and removes stale
  entries.

  This supervisor spawns one invalidator worker per stream partition. Each
  worker subscribes to cache events and removes entries when they change,
  ensuring data freshness across distributed cache instances.

  The invalidator must be started **after** the stream server, as it depends on
  the stream being already registered.

  ## Prerequisites

  Before starting an invalidator:

  1. The cache must be running: `MyApp.Cache`.
  2. The stream server must be running: `Nebulex.Streams` for `MyApp.Cache`.

  If these are missing, the invalidator will fail to start with a clear error
  message.

  ## Options

  #{Nebulex.Streams.Invalidator.Options.options_docs()}

  ## Examples

  Start invalidator for a static cache:

      {Nebulex.Streams.Invalidator, cache: MyApp.Cache}

  Start invalidator for a dynamic cache:

      {Nebulex.Streams.Invalidator, name: :my_cache}

  Start with a different event scope (only invalidate on local events):

      {Nebulex.Streams.Invalidator, cache: MyApp.Cache, event_scope: :local}

  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    opts = Options.validate!(opts)
    name = get_cache_name(opts)
    event_scope = Keyword.fetch!(opts, :event_scope)
    sup_name = camelize_and_concat([name, Invalidator])

    metadata =
      name
      |> Streams.lookup_meta!()
      |> Map.merge(%{name: name, event_scope: event_scope})

    Supervisor.start_link(__MODULE__, metadata, name: sup_name)
  end

  ## Supervisor callback

  @impl true
  def init(metadata) do
    partitions = metadata.partitions || 1

    children =
      for p <- 0..(partitions - 1) do
        Supervisor.child_spec(
          {Worker, Map.put(metadata, :partition, p)},
          id: {Worker, p}
        )
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private functions

  defp get_cache_name(opts) do
    opts
    |> Keyword.get_lazy(:name, fn -> Keyword.get(opts, :cache) end)
    |> Kernel.||(raise "Missing :name or :cache option")
  end
end
