defmodule Nebulex.Streams.Invalidator do
  @moduledoc """
  Cache invalidation handler that removes local cache entries when events occur.

  The `Invalidator` ensures cache consistency by removing potentially stale
  entries from the local cache whenever events are received from other nodes.
  This forces the application to fetch fresh data from the System-Of-Record
  (SoR) on the next access, preventing inconsistent reads.

  This is particularly useful in distributed scenarios where you want to ensure
  data freshness over performance, implementing a "fail-safe" approach to cache
  consistency.
  """

  use Supervisor

  alias Nebulex.Streams
  alias Nebulex.Streams.Invalidator.{Options, Worker}

  import Nebulex.Utils, only: [camelize_and_concat: 1]

  ## API

  @doc """
  Starts a invalidator supervisor.

  ## Options

  #{Nebulex.Streams.Invalidator.Options.options_docs()}

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
