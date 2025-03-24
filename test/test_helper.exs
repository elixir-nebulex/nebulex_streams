[
  Phoenix.PubSub
]
|> Enum.each(&Mimic.copy/1)

ExUnit.start()
