defmodule Nebulex.Streams.TestCache do
  @moduledoc false

  defmodule Cache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_streams,
      adapter: Nebulex.Adapters.Local

    use Nebulex.Streams
  end

  defmodule NilCache do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_streams,
      adapter: Nebulex.Adapters.Nil

    use Nebulex.Streams
  end
end
