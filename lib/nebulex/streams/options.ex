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
      The defined cache module.
      """
    ],
    name: [
      type: :atom,
      required: false,
      doc: """
      The name of the cache (in case of dynamic caches).
      """
    ],
    pubsub: [
      type: :atom,
      required: false,
      default: Nebulex.Streams.PubSub,
      doc: """
      The name of `Phoenix.PubSub` system to use.
      """
    ],
    broadcast_fun: [
      type: {:in, [:broadcast, :broadcast_from]},
      required: false,
      default: :broadcast,
      doc: """
      The broadcast function to use.
      """
    ],
    backoff_initial: [
      type: :non_neg_integer,
      required: false,
      default: :timer.seconds(1),
      doc: """
      The initial backoff time (in milliseconds) is the time that the stream
      server process will wait before attempting to re-register the event
      listener after a failure to broadcast an event.
      """
    ],
    backoff_max: [
      type: :timeout,
      required: false,
      default: :timer.seconds(30),
      doc: """
      the maximum length (in milliseconds) of the time interval used between
      re-register attempts.
      """
    ],
    partitions: [
      type: :pos_integer,
      required: false,
      doc: """
      The number of partitions to dispatch to.
      """
    ],
    hash: [
      type: {:fun, 1},
      type_doc: "`t:Nebulex.Streams.hash/0`",
      required: false,
      default: &Streams.default_hash/1,
      doc: """
      The hashing algorithm. It's a function which receives the event and
      returns the partition to dispatch the event to. The function can also
      return `:none`, in which case the event is discarded.

      > #### `:hash` option {: .info}
      >
      > The hash function is invoked only if the option `:partitions` is
      > configured, otherwise, it is ignored.
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
      The events to subscribe to. By default, it subscribes to all cache entry
      events.
      """
    ],
    partition: [
      type: :non_neg_integer,
      required: false,
      doc: """
      The partition to subscribe to. When the `:partition` option is not
      provided and you have the `:partitions` option configured, the caller
      process is subscribed to a random partition.
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
    NimbleOptions.validate!(opts, @subscribe_opts_schema)
  end
end
