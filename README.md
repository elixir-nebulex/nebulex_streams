# Nebulex Streams 🌩
> Real-time event streaming for Nebulex caches

![CI](https://github.com/elixir-nebulex/nebulex_streams/workflows/CI/badge.svg)
[![Codecov](https://codecov.io/gh/elixir-nebulex/nebulex_streams/graph/badge.svg)](https://codecov.io/gh/elixir-nebulex/nebulex_streams)
[![Hex.pm](https://img.shields.io/hexpm/v/nebulex_streams.svg)](https://hex.pm/packages/nebulex_streams)
[![Documentation](https://img.shields.io/badge/Documentation-ff69b4)](https://hexdocs.pm/nebulex_streams)

Nebulex Streams provides real-time event streaming capabilities for
[Nebulex](https://github.com/elixir-nebulex/nebulex) caches. Subscribe to cache
events like insertions, updates, and deletions as they happen, enabling reactive
applications and real-time monitoring.

## Features

- 🚀 **Real-time Events** - React to cache operations instantly.
- 🔄 **Partitioned Streams** - Scale event processing across multiple processes.
- 🎯 **Event Filtering** - Subscribe to specific event types.
- 🌐 **Distributed** - Built on Phoenix.PubSub for cluster-wide events.
- 📊 **Telemetry** - Comprehensive observability with telemetry events.
- 🔄 **Built-in Invalidation** - Automatic cache invalidation for distributed
  consistency.

## Installation

Add `nebulex_streams` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nebulex_streams, "~> 0.1"}
  ]
end
```

See the [online documentation](https://hexdocs.pm/nebulex_streams)
for more information.

## Quick Start

### 1. Define Your Cache

Add streaming support to your Nebulex cache:

```elixir
defmodule MyApp.Cache do
  use Nebulex.Cache,
    otp_app: :my_app,
    adapter: Nebulex.Adapters.Local

  use Nebulex.Streams
end
```

### 2. Configure Your Application

Add the cache and stream to your supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Cache,
    {Nebulex.Streams, cache: MyApp.Cache}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 3. Subscribe to Events

Create an event handler:

```elixir
defmodule MyApp.EventHandler do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    # Subscribe to all cache events
    :ok = MyApp.Cache.subscribe()

    {:ok, %{}}
  end

  def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
    IO.puts("Cache event: #{event.type} for key #{inspect(event.target)}")

    {:noreply, state}
  end
end
```

### 4. Start Processing Events

```elixir
# Start your event handler
{:ok, _pid} = MyApp.EventHandler.start_link([])

# Perform cache operations
MyApp.Cache.put("user:123", %{name: "Alice", age: 30})
#=> Cache event: inserted for key {:key, "user:123"}

MyApp.Cache.put("user:123", %{name: "Alice", age: 31})
#=> Cache event: updated for key {:key, "user:123"}

MyApp.Cache.delete("user:123")
#=> Cache event: deleted for key {:key, "user:123"}
```

## Usage Examples

### Event Filtering

Subscribe to specific event types:

```elixir
# Only listen for insertions and deletions
MyApp.Cache.subscribe(events: [:inserted, :deleted])
```

### Partitioned Processing

Scale event processing across multiple processes:

```elixir
# In your application.ex
def start(_type, _args) do
  partitions = System.schedulers_online()

  children = [
    MyApp.Cache,
    {Nebulex.Streams, cache: MyApp.Cache, partitions: partitions},
    {MyApp.EventHandler.Supervisor, partitions}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

```elixir
# Event handler supervisor
defmodule MyApp.EventHandler.Supervisor do
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
```

```elixir
# Partition-aware event handler
defmodule MyApp.EventHandler do
  use GenServer

  def start_link(partition) do
    GenServer.start_link(__MODULE__, partition)
  end

  def init(partition) do
    # Subscribe to a specific partition
    :ok = MyApp.Cache.subscribe(partition: partition)

    {:ok, %{partition: partition}}
  end

  def handle_info(%Nebulex.Event.CacheEntryEvent{} = event, state) do
    IO.puts("Partition #{state.partition}: #{event.type} for #{inspect(event.target)}")

    {:noreply, state}
  end
end
```

### Custom Hash Functions

Route events to specific partitions based on your logic:

```elixir
def custom_hash(%Nebulex.Event.CacheEntryEvent{target: {:key, key}}) do
  cond do
    String.starts_with?(key, "user:") -> 0    # User events to partition 0
    String.starts_with?(key, "session:") -> 1 # Session events to partition 1
    true -> 2                                 # Everything else to partition 2
  end
end

# Configure with custom hash
{Nebulex.Streams,
 cache: MyApp.Cache,
 partitions: 3,
 hash: &MyApp.custom_hash/1}
```

### Event Aggregation

Collect and analyze event patterns:

```elixir
defmodule MyApp.EventAggregator do
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ok = MyApp.Cache.subscribe()
    # Send stats every 10 seconds
    :timer.send_interval(10_000, :report_stats)

    {:ok, %{inserted: 0, updated: 0, deleted: 0}}
  end

  def handle_info(%Nebulex.Event.CacheEntryEvent{type: type}, state) do
    new_state = Map.update(state, type, 1, &(&1 + 1))

    {:noreply, new_state}
  end

  def handle_info(:report_stats, state) do
    Logger.info("Cache activity: #{inspect(state)}")

    {:noreply, %{inserted: 0, updated: 0, deleted: 0}}
  end
end
```

## Monitoring and Observability

### Telemetry Events

Nebulex Streams emits telemetry events for monitoring:

```elixir
# Listen for broadcast errors
:telemetry.attach(
  "stream-errors",
  [:nebulex, :streams, :broadcast],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)

defmodule MyApp.TelemetryHandler do
  require Logger

  def handle_event(_event, _measurements, %{status: :error, reason: reason}, _config) do
    Logger.error("Stream broadcast failed: #{inspect(reason)}")
  end

  def handle_event(_event, _measurements, _metadata, _config_) do
    :ignore
  end
end
```

## Dynamic Caches

Nebulex Streams supports dynamic caches:

```elixir
# Start a dynamic cache
{:ok, _pid} = MyApp.Cache.start_link(name: :my_dynamic_cache)

# Start streams for the dynamic cache
{:ok, _pid} = Nebulex.Streams.start_link(
  cache: MyApp.Cache,
  name: :my_dynamic_cache
)

# Subscribe to the dynamic cache
MyApp.Cache.subscribe(:my_dynamic_cache, [])
```

## Automatic Cache Invalidation

For distributed cache scenarios, Nebulex Streams includes a built-in
[`Nebulex.Streams.Invalidator`](https://hexdocs.pm/nebulex_streams/Nebulex.Streams.Invalidator.html)
that automatically removes stale entries when they change on other nodes. This
implements a "fail-safe" approach to cache consistency.

```elixir
# Add to your supervision tree after the stream
children = [
  MyApp.Cache,
  {Nebulex.Streams, cache: MyApp.Cache},
  {Nebulex.Streams.Invalidator, cache: MyApp.Cache}  # Watch for changes
]

Supervisor.start_link(children, strategy: :rest_for_one)
```

For detailed options and patterns, see the
[Invalidator documentation](https://hexdocs.pm/nebulex_streams/Nebulex.Streams.Invalidator.html).

## Contributing

Contributions to Nebulex are very welcome and appreciated!

Use the [issue tracker](https://github.com/elixir-nebulex/nebulex_streams)
for bug reports or feature requests. Open a
[pull request](https://github.com/elixir-nebulex/nebulex_streams/pulls)
when you are ready to contribute.

When submitting a pull request you should not update the
[CHANGELOG.md](CHANGELOG.md), and also make sure you test your changes
thoroughly, include unit tests alongside new or changed code.

Before to submit a PR it is highly recommended to run `mix test.ci` and ensure
all checks run successfully.

## Copyright and License

Copyright (c) 2025, Carlos Bolaños.

`Nebulex.Streams` source code is licensed under the [MIT License](LICENSE.md).
