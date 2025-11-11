defmodule Nebulex.Streams.Helpers do
  @moduledoc false

  ## API

  @doc """
  Returns `true` if the given PID is on the current node, `false` otherwise.
  """
  @spec current_node?(pid()) :: boolean()
  def current_node?(pid) do
    node(pid) == node()
  end
end
