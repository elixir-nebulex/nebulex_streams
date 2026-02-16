defmodule Nebulex.Streams.Invalidator.Options do
  @moduledoc false

  # Start options
  start_opts = [
    cache: [
      type: :atom,
      required: false,
      doc: """
      The Nebulex cache module to watch for invalidation.

      Use this option for static caches defined in your supervision tree. If
      both `:cache` and `:name` are provided, `:name` takes precedence.
      """
    ],
    name: [
      type: :atom,
      required: false,
      doc: """
      The instance name of a dynamic cache.

      Use this option when you started a dynamic cache with
      `MyApp.Cache.start_link(name: :my_cache)`. If both `:cache` and `:name`
      are provided, this option takes precedence.
      """
    ],
    event_scope: [
      type: {:in, [:remote, :local, :all]},
      required: false,
      default: :remote,
      doc: """
      Which cache events to process for invalidation.

      Controls whether invalidation happens for events from remote nodes,
      the local node, or both.

        - `:remote` (default) - Only invalidate when events come from remote
          nodes. Recommended for distributed scenarios to avoid redundant
          invalidations. Example: Node B invalidates entries when Node A
          changes them.

        - `:local` - Only invalidate when events come from the local node.
          Useful for keeping related caches in sync within a single process
          or node. Example: When PrimaryCache changes, invalidate DerivedCache.

        - `:all` - Invalidate for any event, regardless of origin.
          Rarely needed; can cause cache thrashing if used unnecessarily.
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
    opts = NimbleOptions.validate!(opts, @start_opts_schema)

    if !Keyword.has_key?(opts, :cache) and !Keyword.has_key?(opts, :name) do
      raise NimbleOptions.ValidationError,
            "invalid options: expected either :cache or :name option, got neither"
    else
      opts
    end
  end
end
