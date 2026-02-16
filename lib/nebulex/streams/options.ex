defmodule Nebulex.Streams.Options do
  @moduledoc false

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams

  # Event types
  @events CacheEntryEvent.__types__()

  # Start options
  start_opts = [
    cache: [
      type: :atom,
      required: true,
      doc: """
      The Nebulex cache module to stream events from (required).

      This is the cache module that has already been defined with
      `use Nebulex.Cache`. The stream server will register itself
      as an event listener with this cache.
      """
    ],
    name: [
      type: :atom,
      required: false,
      doc: """
      The instance name for dynamic caches (optional).

      Use this when you have started a dynamic cache with
      `MyApp.Cache.start_link(name: :my_instance)`. For static caches defined
      in the supervision tree, this should be omitted.
      """
    ],
    pubsub: [
      type: :atom,
      required: false,
      default: Nebulex.Streams.PubSub,
      doc: """
      The `Phoenix.PubSub` instance to use for event broadcasting (optional).

      Defaults to `Nebulex.Streams.PubSub`. You can provide a custom PubSub
      instance if you want to use your application's existing PubSub instead
      of the one provided by Nebulex.Streams. The specified PubSub must be
      started in your supervision tree.
      """
    ],
    broadcast_fun: [
      type: {:in, [:broadcast, :broadcast_from]},
      required: false,
      default: :broadcast,
      doc: """
      Which broadcast function to use (`:broadcast` or `:broadcast_from`).

      - `:broadcast` (default): All subscribers including the broadcaster
        receive events.
      - `:broadcast_from`: Excludes the broadcaster from receiving its own
        events, reducing message overhead if your handler doesn't need
        self-messages.
      """
    ],
    backoff_initial: [
      type: :non_neg_integer,
      required: false,
      default: :timer.seconds(1),
      doc: """
      Initial backoff time in milliseconds for listener re-registration.

      When the stream server fails to register the event listener, it will wait
      this amount of time before retrying. The backoff time increases
      exponentially up to `:backoff_max`.
      """
    ],
    backoff_max: [
      type: :timeout,
      required: false,
      default: :timer.seconds(30),
      doc: """
      Maximum backoff time in milliseconds for listener re-registration.

      When retrying failed listener registration, the backoff time will not
      exceed this value.
      """
    ],
    partitions: [
      type: :pos_integer,
      required: false,
      doc: """
      Number of partitions for parallel event processing.

      When provided, events are divided into this many independent sub-streams,
      allowing multiple processes to handle events in parallel. Each partition
      has its own topic. Without partitions, all events go to a single topic.

      Typical values:

      - Omit or 1: Low event volume, simple processing (all events to one topic).
      - `System.schedulers_online()`: CPU-bound event processing.
      - `System.schedulers_online() * 2`: I/O-bound event processing.

      """
    ],
    hash: [
      type: {:fun, 1},
      type_doc: "`t:Nebulex.Streams.hash/0`",
      required: false,
      default: &Streams.default_hash/1,
      doc: """
      Custom hash function for routing events to partitions.

      This function receives a `Nebulex.Event.CacheEntryEvent` and returns
      either:

      - A partition number (0 to partitions-1): routes the event to that
        partition.
      - `:none`: discards the event entirely

      Defaults to `Nebulex.Streams.default_hash/1` which uses `phash2` for even
      distribution.

      The hash function is only used when `:partitions` is configured. Without
      partitions, it is ignored.

      Example: Custom hash that routes "user:" events to partition 0:

          def custom_hash(%Nebulex.Event.CacheEntryEvent{target: {:key, key}}) do
            if String.starts_with?(key, "user:"), do: 0, else: 1
          end

      """
    ]
  ]

  # Subscribe options
  sub_opts = [
    events: [
      type: {:list, {:in, @events}},
      type_doc: "`t:Nebulex.Event.CacheEntryEvent.type/0`",
      required: false,
      default: @events,
      doc: """
      List of event types to subscribe to (optional).

      Possible event types are: `:inserted`, `:updated`, `:deleted`, `:expired`,
      `:evicted`.

      When omitted, the subscriber receives all event types (default). When
      provided, it must be a non-empty list; `[]` raises
      `NimbleOptions.ValidationError`.

      Filtering to specific event types reduces message overhead by avoiding
      unnecessary messages to your handler.

      Example: `events: [:inserted, :deleted]` - only subscribe to insertions
      and deletions.
      """
    ],
    partition: [
      type: :non_neg_integer,
      required: false,
      doc: """
      The specific partition to subscribe to (optional).

      Use this only when the stream is configured with `:partitions`. By
      subscribing to a specific partition, you receive only events routed to
      that partition by the hash function.

      When `:partition` is omitted but the stream has `:partitions` configured,
      the caller process is assigned to a random partition automatically.

      Raises `NimbleOptions.ValidationError` if the partition number is >= the
      total number of partitions configured in the stream.

      Example: `partition: 0` - subscribe only to partition 0 (if stream has
      multiple partitions).
      """
    ]
  ]

  # Start options schema
  @start_opts_schema NimbleOptions.new!(start_opts)

  # Subscribe options schema
  @subscribe_opts_schema NimbleOptions.new!(sub_opts)

  ## Docs API

  # coveralls-ignore-start

  @spec start_options_docs() :: binary()
  def start_options_docs do
    NimbleOptions.docs(@start_opts_schema)
  end

  @spec subscribe_options_docs() :: binary()
  def subscribe_options_docs do
    NimbleOptions.docs(@subscribe_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate_start_opts!(keyword()) :: keyword()
  def validate_start_opts!(opts) do
    NimbleOptions.validate!(opts, @start_opts_schema)
  end

  @spec validate_subscribe_opts!(keyword()) :: keyword()
  def validate_subscribe_opts!(opts) do
    opts = NimbleOptions.validate!(opts, @subscribe_opts_schema)

    if Keyword.fetch!(opts, :events) == [] do
      raise NimbleOptions.ValidationError,
            "invalid value for :events option: expected a non-empty list, got: []"
    else
      opts
    end
  end
end
