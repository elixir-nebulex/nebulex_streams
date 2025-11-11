defmodule Nebulex.Streams.InvalidatorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams
  alias Nebulex.Streams.Invalidator
  alias Nebulex.Streams.TestCache.{Cache, NilCache}

  import Nebulex.Utils, only: [wrap_error: 2]
  import Nebulex.Streams.TestUtils

  @moduletag capture_log: true

  # Telemetry events
  @prefix [:nebulex, :streams, :invalidator]
  @started_event @prefix ++ [:started]
  @stopped_event @prefix ++ [:stopped]
  @invalidate_event @prefix ++ [:invalidate, :stop]

  setup_all do
    cache_pid = start_supervised!({Cache, []})
    stream_pid = start_supervised!({Streams, cache: Cache, partitions: 1})

    {:ok, cache: Cache, cache_pid: cache_pid, stream_pid: stream_pid}
  end

  describe "start_link/1" do
    test "starts invalidator with valid metadata", %{cache: cache} do
      pid = start_supervised!({Invalidator, cache: cache, event_scope: :local})
      assert Process.alive?(pid)
    end

    test "sets up process correctly and subscribes", %{cache: cache} do
      pid = start_supervised!({Invalidator, cache: cache, event_scope: :local})

      # Verify the process is alive and properly configured
      assert Process.alive?(pid)

      # Test that it's subscribed by triggering an event
      :ok = cache.put!("test:key", "value")

      # The invalidator should receive and process the event
      wait_until(fn ->
        refute cache.get!("test:key")
      end)
    end
  end

  describe "integration with dynamic caches" do
    test "works with named cache instances", %{cache: cache} do
      # Start a named cache instance
      name = :invalidator_test_cache
      {:ok, dynamic_cache_pid} = cache.start_link(name: name)
      {:ok, dynamic_stream_pid} = Streams.start_link(cache: cache, name: name)
      {:ok, invalidator_pid} = Invalidator.start_link(cache: cache, name: name)

      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, fn _ -> false end)
      |> allow(self(), get_worker(invalidator_pid))

      # Test invalidation with named cache
      :ok = cache.put!(name, "dynamic:key", "value", [])

      wait_until(fn ->
        refute cache.get!(name, "dynamic:key", nil, [])
      end)

      safe_stop(invalidator_pid)
      safe_stop(dynamic_stream_pid)
      safe_stop(dynamic_cache_pid)
    end
  end

  describe "event handling" do
    setup %{cache: cache} do
      invalidator_pid = start_supervised!({Invalidator, cache: cache})

      {:ok, invalidator_pid: invalidator_pid}
    end

    test "invalidates key on insert event", %{cache: cache, invalidator_pid: pid} do
      # Put a key - this should trigger an insert event
      :ok = cache.put!("user:123", %{name: "Alice"})

      # Make sure the key is present
      assert cache.get!("user:123") == %{name: "Alice"}

      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, fn _ -> false end)
      |> allow(self(), get_worker(pid))

      # Put a key - this should trigger an insert event
      :ok = cache.put!("user:123", %{name: "Bob"})

      # The invalidator should delete it immediately
      wait_until(fn ->
        refute cache.get!("user:123")
      end)
    end

    test "invalidates key on update event", %{cache: cache, invalidator_pid: pid} do
      # First put a key (will be invalidated)
      :ok = cache.put!("user:456", %{name: "Bob"})

      # Make sure the key is present
      assert cache.get!("user:456") == %{name: "Bob"}

      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, fn _ -> false end)
      |> allow(self(), get_worker(pid))

      # Update it (replace) - should trigger update event
      assert cache.replace!("user:456", %{name: "Robert"}) == true

      # Should be invalidated again
      wait_until(fn ->
        refute cache.get!("user:456")
      end)
    end

    test "invalidates multiple keys", %{cache: cache, invalidator_pid: pid} do
      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, 3, fn _ -> false end)
      |> allow(self(), get_worker(pid))

      # Put some keys
      :ok = cache.put!("prefix:1", "value1")
      :ok = cache.put!("prefix:2", "value2")
      :ok = cache.put!("other:1", "value3")

      # Wait for initial invalidation from inserts
      wait_until(fn ->
        refute cache.get!("prefix:1")
        refute cache.get!("prefix:2")
        refute cache.get!("other:1")
      end)
    end

    test "invalidates key on delete event", %{cache: cache, invalidator_pid: pid} do
      # Put a key
      :ok = cache.put!("session:abc", %{user_id: 123})

      # Make sure the key is present
      assert cache.get!("session:abc") == %{user_id: 123}

      # Get the worker PID
      worker_pid = get_worker(pid)

      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, fn _ -> false end)
      |> allow(self(), worker_pid)

      # Trigger a delete_all event
      send(worker_pid, %CacheEntryEvent{
        cache: cache,
        command: :delete,
        pid: self(),
        target: {:key, "session:abc"},
        type: :deleted
      })

      # Wait for the invalidation to complete
      wait_until(fn ->
        refute cache.get!("session:abc")
      end)
    end

    test "invalidates multiple keys on delete_all event", %{cache: cache, invalidator_pid: pid} do
      # Put some keys
      :ok = cache.put!("key1", "value1")
      :ok = cache.put!("key2", "value2")
      :ok = cache.put!("key3", "value3")

      # Get the worker PID
      worker_pid = get_worker(pid)

      # Simulate the event coming from a remote node
      Nebulex.Streams.Helpers
      |> expect(:current_node?, fn _ -> false end)
      |> allow(self(), worker_pid)

      # Trigger a delete_all event
      send(worker_pid, %CacheEntryEvent{
        cache: cache,
        command: :delete_all,
        pid: self(),
        target: {:query, nil},
        type: :deleted
      })

      # Wait for the invalidation to complete
      wait_until(fn ->
        refute cache.get!("key1")
        refute cache.get!("key2")
        refute cache.get!("key3")
      end)
    end
  end

  describe "telemetry events" do
    test "emits started event on init", %{cache: cache} do
      with_telemetry_handler([@started_event], fn ->
        start_supervised!({Invalidator, cache: cache})

        assert_receive {@started_event, %{system_time: _}, telemetry_metadata}

        assert telemetry_metadata.cache == cache
        assert telemetry_metadata.partition in [0, 1]
        assert is_struct(telemetry_metadata.started_at, DateTime)
      end)
    end

    test "emits stopped event on termination", %{cache: cache} do
      with_telemetry_handler([@stopped_event], fn ->
        invalidator_pid = start_supervised!({Invalidator, cache: cache})

        # Stop the process
        :ok = GenServer.stop(invalidator_pid, :normal)

        assert_receive {@stopped_event, %{duration: _}, telemetry_metadata}

        assert telemetry_metadata.cache == cache
        assert telemetry_metadata.partition in [0, 1]
        assert is_struct(telemetry_metadata.stopped_at, DateTime)
        assert telemetry_metadata.reason == :shutdown
      end)
    end

    test "emits invalidate events during processing", %{cache: cache} do
      with_telemetry_handler([@invalidate_event], fn ->
        pid = start_supervised!({Invalidator, cache: cache})

        # Simulate the event coming from a remote node
        Nebulex.Streams.Helpers
        |> expect(:current_node?, fn _ -> false end)
        |> allow(self(), get_worker(pid))

        # Trigger an event
        :ok = cache.put("telemetry:test", "value")

        # Should receive invalidate telemetry event
        assert_receive {@invalidate_event, measurements, telemetry_metadata}

        assert is_map(measurements)
        assert telemetry_metadata.cache == cache
        assert %CacheEntryEvent{} = telemetry_metadata.event
      end)
    end

    test "unhandled event", %{cache: cache} do
      event = @prefix ++ [:unhandled_event]

      with_telemetry_handler([event], fn ->
        pid = start_supervised!({Invalidator, cache: cache})
        worker_pid = get_worker(pid)

        # Trigger an event
        send(worker_pid, "unhandled event")

        # Wait for the unhandled event
        assert_receive {^event, %{system_time: _}, %{unhandled_event: "unhandled event"}}
      end)
    end
  end

  describe "error handling" do
    setup do
      cache_pid = start_supervised!({NilCache, []})
      stream_pid = start_supervised!({Streams, cache: NilCache, partitions: 1})

      {:ok, cache: NilCache, cache_pid: cache_pid, stream_pid: stream_pid}
    end

    test "command error", %{cache: cache} do
      with_telemetry_handler([@invalidate_event], fn ->
        pid = start_supervised!({Invalidator, cache: cache})
        worker_pid = get_worker(pid)

        # Simulate the event coming from a remote node
        Nebulex.Streams.Helpers
        |> expect(:current_node?, fn _ -> false end)
        |> allow(self(), worker_pid)

        {:error, reason} = error = wrap_error Nebulex.Error, reason: :error

        # Simulate the cache command returning an error
        NilCache
        |> expect(:delete, fn _, _, _ -> error end)
        |> allow(self(), worker_pid)

        # Trigger an event
        :ok = cache.put("error:test", "value")

        # Wait for the stop event with the error reason
        assert_receive {@invalidate_event, %{}, %{status: :error, reason: ^reason}}
      end)
    end

    test "cache command exit", %{cache: cache} do
      with_telemetry_handler([@invalidate_event], fn ->
        Process.flag(:trap_exit, true)

        pid = start_supervised!({Invalidator, cache: cache})
        worker_pid = get_worker(pid)

        # Simulate the event coming from a remote node
        Nebulex.Streams.Helpers
        |> expect(:current_node?, fn _ -> false end)
        |> allow(self(), worker_pid)

        # {:error, reason} = error = wrap_error Nebulex.Error, reason: :error

        # Simulate the cache command returning an error
        NilCache
        |> expect(:delete, fn _, _, _ -> exit(:error) end)
        |> allow(self(), worker_pid)

        # Trigger an event
        :ok = cache.put("error:test", "value")

        # Wait for the stop event with the error reason
        assert_receive {@invalidate_event, %{}, %{status: :exit, reason: :error}}
      end)
    end
  end

  ## Private functions

  defp get_worker(sup_pid) do
    [{_id, pid, _type, _modules} | _] = Supervisor.which_children(sup_pid)

    pid
  end
end
