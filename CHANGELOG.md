# Changelog

All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0](https://github.com/elixir-nebulex/nebulex_streams/tree/v0.1.0) (2025-11-11)
> [Full Changelog](https://github.com/elixir-nebulex/nebulex_streams/compare/52c4174d9835e0865e3518143ec9c9d2beb122af...v0.1.0)

### Features

- **Real-time Event Streaming**: Processes can subscribe to and react to cache
  entry events (inserted, updated, deleted, expired, evicted) as they happen.
- **Partitioned Streams**: Events can be divided into multiple independent
  sub-streams for parallel processing and scalability.
- **Event Filtering**: Subscribers can filter to specific event types to reduce
  message overhead.
- **Distributed by Design**: Built on Phoenix.PubSub for seamless cluster-wide
  event distribution.
- **Automatic Cache Invalidation**: Built-in `Nebulex.Streams.Invalidator`
  module for automatic entry removal when changes occur on other nodes.
- **Telemetry Integration**: Comprehensive observability with telemetry events
  for monitoring stream and invalidation behavior.
- **Dynamic Cache Support**: Works with both statically-defined and
  dynamically-created caches.
- **Custom Partition Routing**: Support for custom hash functions to route
  events to specific partitions based on business logic.

### Enhancements

- Comprehensive module documentation with examples and best practices.
- Detailed option documentation with inline examples.
- Troubleshooting guides and performance tuning recommendations.
- Support for event scopes (`:remote`, `:local`, `:all`) in invalidator for
  flexible consistency strategies.
