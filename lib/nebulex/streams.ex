defmodule Nebulex.Streams do
  @moduledoc """
  A Nebulex stream is a named logical channel (a.k.a "topic") where cache entry
  events are published and consumers or subscribers read them, acting as a
  undamental unit for streaming cache events.

  When a stream is started, it registers an event listener that broadcasts the
  events via `Phoenix.PubSub` system. It allows developers to consume events by
  subscribing the caller process to the cache event stream.

  ## Usage

  First of all, you define a Nebulex cache using `Nebulex.Streams`, like so:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :nebulex_streams,
          adapter: Nebulex.Adapters.Local

        use Nebulex.Streams
      end

  Then, you have to add the cache and the stream to your application's
  supervision tree, like this:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache}
        ]

        Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
      end

  The stream setup is ready, now processes can subscribe and listen for cache
  events. For example, you can use a `GenServer`, like so:

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

  Remember to add the new event handler to your application's supervision tree:

      # lib/my_app/application.ex
      def start(_type, _args) do
        children = [
          MyApp.Cache,
          {Nebulex.Streams, cache: MyApp.Cache},
          MyApp.Cache.EventHandler
        ]

        Supervisor.start_link(children, strategy: :rest_for_one, name: MyApp.Supervisor)
      end

  All the pieces are in place, you can run cache actions to see how the events
  are handled.

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
  would place a pretty radical limit on the system's scalability. It could
  manage many streams or topics across many machines (`Phonix.PubSub` is a
  distributed system after all), however, a single topic could not ever get too
  big or aspire to accommodate too many events. Fortunately, `Nebulex.Streams`
  does not leave us without options here: It gives us the ability to partition
  topics.

  Partitioning breaks a single topic into multiple ones, each of which can be
  consumed by a separate process. Therefore, the consumer workload to process
  existing messages can be split among many processes and nodes in the cluster;
  each process subscribes to a different partition.

  Considering the previous example, a single process to handle the entire
  workload may be a bottleneck. Hence, we can make it more scalable by having
  a pool of processes instead.

  First, we create a supervisor to set up the pool of processes, each of which
  will handle a partition:

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

  Then, we modify the event handler (the `GenServer`) to subscribe to a specific
  partition:

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

  The application's supervision tree:

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

  """

  import Nebulex.Utils, only: [wrap_error: 2]

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams.{Options, Server}
  alias Phoenix.PubSub

  @typedoc "The type used for the function passed to the `:hash` option."
  @type hash() :: (Nebulex.Event.t() -> non_neg_integer() | :none)

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
  Starts a stream server.

  ## Options

  #{Options.start_options_docs()}

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
    %{pubsub: pubsub, partitions: partitions} = Server.get_metadata(name)

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

  @doc """
  The event listener function broadcasts the events via `Phoenix.PubSub`.
  """
  @spec broadcast_event(Nebulex.Event.t()) :: :ok | {:error, any()}
  def broadcast_event(
        %CacheEntryEvent{
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
        topic = topic(name, type, partition)

        # Build new event metadata
        metadata = %{
          topic: topic,
          partition: partition,
          partitions: partitions,
          node: node(),
          pid: self()
        }

        # Broadcast the event
        do_broadcast!(broadcast_fun, pubsub, topic, %{event | metadata: metadata})
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

  # Inline common instructions
  @compile {:inline, topic: 3}

  # Determine the topic name
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

  defp do_broadcast!(:broadcast, pubsub, topic, event) do
    pubsub
    |> PubSub.broadcast(topic, event)
    |> handle_broadcast_response(pubsub, topic, event)
  end

  defp do_broadcast!(:broadcast_from, pubsub, topic, event) do
    pubsub
    |> PubSub.broadcast_from(self(), topic, event)
    |> handle_broadcast_response(pubsub, topic, event)
  end

  defp handle_broadcast_response({:error, reason}, pubsub, topic, event) do
    # Emit a Telemetry event to notify the error
    :telemetry.execute(
      [:nebulex, :streams, :broadcast_error],
      %{},
      %{pubsub: pubsub, topic: topic, event: event, reason: reason}
    )
  end

  defp handle_broadcast_response(:ok, _pubsub, _topic, _event) do
    :ok
  end
end
