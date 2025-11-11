[
  Phoenix.PubSub,
  Nebulex.Streams.Helpers,
  Nebulex.Streams.TestCache.NilCache
]
|> Enum.each(&Mimic.copy/1)

ExUnit.start()
