defmodule Nebulex.Streams.Invalidator.Options do
  @moduledoc false

  # Start options
  start_opts = [
    cache: [
      type: :atom,
      required: false,
      doc: """
      The cache module. Required when not using dynamic caches.

      This option is mutually exclusive with `:name`.
      """
    ],
    name: [
      type: :atom,
      required: false,
      doc: """
      The name of the dynamic cache instance. Required when using dynamic
      caches.

      This option is mutually exclusive with `:cache`.
      """
    ],
    event_scope: [
      type: {:in, [:remote, :local, :all]},
      required: false,
      default: :remote,
      doc: """
      The scope of events the invalidator should process.

      - `:remote` - Only invalidate entries when events come from remote nodes
      - `:local` - Only invalidate entries when events come from the local node
      - `:all` - Invalidate entries for both local and remote events

      Defaults to `:remote` to ensure consistency in distributed scenarios.
      """
    ]
  ]

  # Start options schema
  @start_opts_schema NimbleOptions.new!(start_opts)

  ## Docs API

  # coveralls-ignore-start

  @spec options_docs() :: binary()
  def options_docs do
    NimbleOptions.docs(@start_opts_schema)
  end

  # coveralls-ignore-stop

  ## Validation API

  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    NimbleOptions.validate!(opts, @start_opts_schema)
  end
end
