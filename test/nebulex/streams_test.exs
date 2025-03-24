defmodule Nebulex.StreamsTest do
  use ExUnit.Case
  use Mimic

  import Nebulex.Streams.TestUtils

  alias Nebulex.Event.CacheEntryEvent
  alias Nebulex.Streams

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex_streams,
      adapter: Nebulex.Adapters.Nil

    use Nebulex.Streams
  end

  @moduletag capture_log: true

  describe "start_link/1" do
    test "error: missing :cache option" do
      assert_raise NimbleOptions.ValidationError, ~r"required :cache option not found", fn ->
        Streams.start_link()
      end
    end

    for opt <- [:name, :pubsub, :broadcast_fun, :partitions, :hash] do
      test "error: #{inspect(opt)} option" do
        assert_raise NimbleOptions.ValidationError,
                     ~r"invalid value for #{inspect(unquote(opt))} option",
                     fn ->
                       Streams.start_link([{:cache, Cache}, {unquote(opt), "invalid"}])
                     end
      end
    end
  end

  describe "child_spec/1" do
    test "ok: returns child spec" do
      assert Streams.child_spec(cache: Cache) == %{
               id: Nebulex.Streams,
               start: {Nebulex.Streams, :start_link, [[cache: Cache]]}
             }
    end
  end

  describe "subscribe/1" do
    setup do
      {:ok, cache_pid} = Cache.start_link()

      on_exit(fn -> safe_stop(cache_pid) end)

      {:ok, cache: Cache, cache_pid: cache_pid}
    end

    test "ok: subscribes caller with defaults", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache)

      assert cache.subscribe() == :ok

      :ok = cache.put("foo", "bar")

      expected_event = event_fixture()

      assert_receive ^expected_event

      safe_stop(stream_pid)
    end

    test "ok: subscribes caller [broadcast_fun: :broadcast_from]", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache, broadcast_fun: :broadcast_from)

      assert cache.subscribe() == :ok

      :ok = cache.put("foo", "bar")

      expected_event = event_fixture()

      refute_receive ^expected_event

      safe_stop(stream_pid)
    end

    test "ok: subscribes a process [broadcast_fun: :broadcast_from]", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache, broadcast_fun: :broadcast_from)

      parent = self()

      expected_event = event_fixture()

      pid =
        spawn_link(fn ->
          assert cache.subscribe() == :ok

          send(parent, {self(), :subscribed})

          assert_receive event, 5000

          send(parent, {self(), event})
        end)

      assert_receive {^pid, :subscribed}, 5000

      :ok = cache.put("foo", "bar")

      assert_receive {^pid, ^expected_event}, 5000

      safe_stop(stream_pid)
    end

    test "error: subscribe error", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache)

      Phoenix.PubSub
      |> expect(:subscribe, fn _, _ -> {:error, :error} end)

      msg =
        "Nebulex.Streams.subscribe(Nebulex.StreamsTest.Cache, " <>
          "[events: [:deleted]]) failed with reason: :error"

      assert_raise Nebulex.Error, "#{msg}", fn ->
        cache.subscribe!(events: [:deleted])
      end

      safe_stop(stream_pid)
    end

    test "error: broadcast error", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache)

      Phoenix.PubSub
      |> expect(:broadcast, fn _, _, _ -> {:error, :error} end)

      event = [:nebulex, :streams, :broadcast_error]

      with_telemetry_handler([event], fn ->
        :ok = cache.subscribe!()
        :ok = cache.put("foo", "bar")

        assert_receive {^event, %{},
                        %{
                          pubsub: Nebulex.Streams.PubSub,
                          topic: "Elixir.Nebulex.StreamsTest.Cache:inserted",
                          event: %CacheEntryEvent{}
                        }}
      end)

      safe_stop(stream_pid)
    end
  end

  describe "subscribe/1 (dynamic cache)" do
    setup do
      {:ok, cache_pid} = Cache.start_link(name: __MODULE__)

      on_exit(fn -> safe_stop(cache_pid) end)

      {:ok, cache: Cache, cache_pid: cache_pid}
    end

    test "ok: subscribes caller to a partition with custom hash", %{cache: cache} do
      {:ok, stream_pid} =
        Streams.start_link(
          cache: Cache,
          name: __MODULE__,
          partitions: 2,
          hash: &__MODULE__.hash/1
        )

      assert cache.subscribe(__MODULE__, partition: 0) == :ok

      expected_event =
        event_fixture(
          name: __MODULE__,
          metadata: %{
            topic: "#{__MODULE__}:0:inserted",
            partition: 0,
            partitions: 2,
            node: node(),
            pid: self()
          }
        )

      assert cache.put!(__MODULE__, "foo", "bar", []) == :ok
      assert_receive ^expected_event

      updated = %{
        expected_event
        | type: :updated,
          command: :replace,
          metadata: %{expected_event.metadata | topic: "#{__MODULE__}:1:updated", partition: 1}
      }

      assert cache.replace!(__MODULE__, "foo", "bar bar", [])
      refute_receive ^updated

      assert cache.subscribe(__MODULE__, partition: 1) == :ok

      assert cache.replace!(__MODULE__, "foo", "bar bar bar", [])
      assert_receive ^updated

      safe_stop(stream_pid)
    end

    test "ok: subscribes caller to a partition with default hash", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache, name: __MODULE__, partitions: 1)

      assert cache.subscribe(__MODULE__, []) == :ok

      expected_event =
        event_fixture(
          name: __MODULE__,
          metadata: %{
            topic: "#{__MODULE__}:0:inserted",
            partition: 0,
            partitions: 1,
            node: node(),
            pid: self()
          }
        )

      assert cache.put!(__MODULE__, "foo", "bar", []) == :ok
      assert_receive ^expected_event

      safe_stop(stream_pid)
    end

    test "ok: subscribes caller to a partition but event is discarded", %{cache: cache} do
      {:ok, stream_pid} =
        Streams.start_link(
          cache: Cache,
          name: __MODULE__,
          partitions: 1,
          hash: &__MODULE__.hash_none/1
        )

      assert cache.subscribe(__MODULE__, partition: 0) == :ok

      expected_event =
        event_fixture(
          name: __MODULE__,
          metadata: %{
            topic: "#{__MODULE__}:0:inserted",
            partition: 0,
            partitions: 1,
            node: node(),
            pid: self()
          }
        )

      assert cache.put!(__MODULE__, "foo", "bar", []) == :ok
      refute_receive ^expected_event

      safe_stop(stream_pid)
    end

    test "error: invalid partition", %{cache: cache} do
      {:ok, stream_pid} = Streams.start_link(cache: Cache, name: __MODULE__, partitions: 1)

      assert_raise NimbleOptions.ValidationError,
                   ~r"invalid value for :partition option: expected integer >= 0 and < 1",
                   fn ->
                     cache.subscribe(__MODULE__, partition: 10)
                   end

      safe_stop(stream_pid)
    end
  end

  ## Private functions

  def hash(%CacheEntryEvent{type: :inserted}), do: 0
  def hash(%CacheEntryEvent{}), do: 1

  def hash_none(%CacheEntryEvent{}), do: :none

  defp event_fixture(opts \\ []) do
    opts
    |> Enum.into(%{
      type: :inserted,
      cache: Cache,
      command: :put,
      metadata: %{
        topic: "#{Cache}:inserted",
        partition: nil,
        partitions: nil,
        node: node(),
        pid: self()
      },
      name: Cache,
      target: {:key, "foo"}
    })
    |> CacheEntryEvent.new()
  end
end
