# Architecture

This guide covers what the code and the module docs do not: how the modules
split responsibility and the non-negotiable rules for every change. Read the
"Non-Negotiables" section at session start; read the rest before structural
changes.

For how the library works and how to configure it, read the module docs:

- `Nebulex.Streams` - concepts, event types, partitions, usage patterns, and
  the telemetry events.
- `Nebulex.Streams.Invalidator` - automatic invalidation of distributed
  caches.

For the broader Nebulex context (the adapter pattern, behaviour contracts,
and shared non-negotiables), read the
[core Nebulex architecture guide][core-arch].

[core-arch]: https://hexdocs.pm/nebulex/architecture.html

---

## Purpose

`nebulex_streams` turns the cache entry events of a Nebulex cache into a
stream that processes on any node can subscribe to, through
`Phoenix.PubSub`. On top of it, the invalidator keeps the local caches of a
cluster consistent by removing entries that changed elsewhere. It is a
companion library, not an adapter: it works with any adapter that supports
the Observable API.

---

## Module Boundaries

This section covers how the modules split responsibility; the file layout
is in `lib/` and `test/`.

- `Nebulex.Streams` is the public API. `use Nebulex.Streams` in a cache
  module adds `subscribe/1` and `subscribe!/1`, `start_link/1` and
  `child_spec/1` delegate to `Server`, and `broadcast_event/1` is the
  listener the server registers on the cache.
- `Server` is the GenServer that registers `broadcast_event/1` as the
  cache's event listener, holds the PubSub and partition settings, and
  unregisters the listener when it stops.
- `Invalidator` is the public entry point for automatic invalidation;
  `Invalidator.Worker` is the GenServer, one per partition, that subscribes
  to the stream and deletes the affected entries from the local cache.
- `Application` starts the `Nebulex.Streams.Registry` and the
  `Nebulex.Streams.PubSub`; `Options` and `Invalidator.Options` hold the
  NimbleOptions schemas; `Helpers` holds the shared helpers.

---

## Non-Negotiables

These rules apply in addition to the shared non-negotiables in the core
Nebulex architecture guide.

### 1. Invalidation must not echo

The invalidator deletes entries with
`telemetry_metadata: %{source: :nebulex_streams}`, and `broadcast_event/1`
drops the events that carry that marker. This is what stops a delete on one
node from being broadcast again by every node that applies it. Keep the
marker on every command the invalidator runs, keep the filter in the
listener, and do not replace them with `telemetry: false`: the marker keeps
stats and the other telemetry consumers working during invalidation.

### 2. Keep this document up to date

After any structural change (changing the module boundaries, how events
are routed, or adding a non-negotiable), review this document and update
it if needed. Do not copy here what the module docs already say; link to
them. A stale architecture guide is worse than no guide.

### 3. `mix precommit` must pass

```bash
mix precommit
```

It includes the docs build with warnings as errors; fix the root cause of a
docs warning, do not suppress it.

### 4. Read why before changing subtle behavior

The reasons behind the subtle behavior (the echo filter, partition routing,
and the listener lifecycle) are in the module docs, the code comments, the
CHANGELOG, and the tests. Read them, and the history (`git log -S`), before
changing that code. Do not reverse such behavior without a test that covers
the original problem.

---

## Further Reading

- [Core Nebulex Architecture](https://hexdocs.pm/nebulex/architecture.html)
- [Phoenix.PubSub](https://hexdocs.pm/phoenix_pubsub)
- [nebulex_streams HexDocs](https://hexdocs.pm/nebulex_streams)
