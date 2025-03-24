defmodule Nebulex.Streams.TestUtils do
  @moduledoc false

  @doc false
  def safe_stop(pid) do
    if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 5000)
  catch
    # Perhaps the `pid` has terminated already (race-condition),
    # so we don't want to crash the test
    :exit, _ -> :ok
  end

  @doc false
  def wait_until(retries \\ 50, delay \\ 100, fun)

  def wait_until(1, _delay, fun), do: fun.()

  def wait_until(retries, delay, fun) when retries > 1 do
    fun.()
  rescue
    _ ->
      :ok = Process.sleep(delay)

      wait_until(retries - 1, delay, fun)
  end

  @doc false
  def with_telemetry_handler(handler_id \\ self(), events, fun) do
    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        %{pid: self()}
      )

    fun.()
  after
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event(event, measurements, metadata, %{pid: pid}) do
    send(pid, {event, measurements, metadata})
  end
end
