defmodule Nebulex.Streams.Invalidator.Worker do
  @moduledoc false

  use GenServer

  alias Nebulex.Event.CacheEntryEvent

  import Nebulex.Streams.Helpers

  # Internal state
  defstruct cache: nil,
            name: nil,
            partition: nil,
            partitions: nil,
            start_time: nil,
            event_scope: nil

  # Telemetry event prefix
  @telemetry_prefix ~w(nebulex streams invalidator)a

  ## API

  @doc """
  Starts a sync server.
  """
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(metadata) do
    GenServer.start_link(__MODULE__, metadata)
  end

  ## GenServer callbacks

  @impl true
  def init(%{partition: partition, cache: cache, name: name} = metadata) do
    # Trap exits
    Process.flag(:trap_exit, true)

    # Subscribe the invalidator to the cache events
    :ok = cache.subscribe!(name, partition: partition)

    # Build the state
    state = %{
      struct(__MODULE__, metadata)
      | start_time: System.monotonic_time()
    }

    # Continue to the started state
    {:ok, state, {:continue, :started}}
  end

  @impl true
  def handle_continue(:started, %__MODULE__{start_time: start_time} = state) do
    :ok =
      :telemetry.execute(
        @telemetry_prefix ++ [:started],
        %{system_time: start_time},
        state |> Map.from_struct() |> Map.put(:started_at, DateTime.utc_now())
      )

    {:noreply, %{state | start_time: start_time}}
  end

  @impl true
  def handle_info(event, state)

  def handle_info(%CacheEntryEvent{pid: pid} = event, %__MODULE__{event_scope: scope} = state) do
    current_node? = current_node?(pid)

    if scope == :all or (scope == :remote and not current_node?) or
         (scope == :local and current_node?) do
      :ok = invalidate(state, event)
    end

    {:noreply, state}
  end

  def handle_info(event, state) do
    :telemetry.execute(
      @telemetry_prefix ++ [:unhandled_event],
      %{system_time: System.system_time()},
      state |> Map.from_struct() |> Map.put(:unhandled_event, event)
    )

    {:noreply, state}
  end

  @impl true
  def terminate(reason, %__MODULE__{start_time: start_time} = state) do
    :telemetry.execute(
      @telemetry_prefix ++ [:stopped],
      %{duration: System.monotonic_time() - start_time},
      state |> Map.from_struct() |> Map.merge(%{stopped_at: DateTime.utc_now(), reason: reason})
    )
  end

  ## Private functions

  defp invalidate(%__MODULE__{cache: cache, name: name} = state, event) do
    metadata =
      state
      |> Map.from_struct()
      |> Map.put(:event, event)

    :telemetry.span(@telemetry_prefix ++ [:invalidate], metadata, fn ->
      try do
        cache
        |> invalidate_cache(name, event.target)
        |> handle_error(metadata)
      catch
        :exit, reason ->
          handle_error({:exit, reason}, metadata)
      end
    end)
  end

  defp invalidate_cache(cache, name, {:key, key}) do
    # Disable telemetry to avoid echoing the event back to the sender
    cache.delete(name, key, telemetry: false)
  end

  defp invalidate_cache(cache, name, {:in, keys}) do
    # Disable telemetry to avoid echoing the event back to the sender
    cache.delete_all(name, [in: keys], telemetry: false)
  end

  defp invalidate_cache(cache, name, {:q, query}) do
    # Disable telemetry to avoid echoing the event back to the sender
    cache.delete_all(name, [query: query], telemetry: false)
  end

  defp handle_error(:ok, metadata) do
    {:ok, Map.merge(metadata, %{status: :ok, reason: nil, deleted: 1})}
  end

  defp handle_error({:ok, count}, metadata) do
    {:ok, Map.merge(metadata, %{status: :ok, reason: nil, deleted: count})}
  end

  defp handle_error({status, reason}, metadata) when status in [:error, :exit] do
    {:ok, Map.merge(metadata, %{status: status, reason: reason, deleted: 0})}
  end
end
