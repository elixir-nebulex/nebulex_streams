defmodule Nebulex.Streams.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-nebulex/nebulex_streams"
  @version "0.1.0"

  def project do
    [
      app: :nebulex_streams,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "test.ci": :test
      ],

      # Dialyzer
      dialyzer: dialyzer(),

      # Hex
      package: package(),
      description: "Real-time event streaming for Nebulex caches",

      # Docs
      docs: [
        main: "Nebulex.Streams",
        source_ref: "v#{@version}",
        source_url: @source_url
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:eex],
      mod: {Nebulex.Streams.Application, []}
    ]
  end

  defp deps do
    [
      {:nebulex, github: "elixir-nebulex/nebulex", branch: "main"},
      {:nimble_options, "~> 0.5 or ~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 0.4 or ~> 1.0"},

      # Test & Code Analysis
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.11", only: :test},

      # Benchmark Test
      {:benchee, "~> 1.3", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Docs
      {:ex_doc, "~> 0.37", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "test.ci": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "coveralls.html",
        "sobelow --exit --skip",
        "dialyzer --format short"
      ]
    ]
  end

  defp package do
    [
      name: :nebulex_streams,
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:nebulex],
      plt_file: {:no_warn, "priv/plts/" <> plt_file_name()},
      flags: [
        :unmatched_returns,
        :error_handling,
        :no_opaque,
        :unknown,
        :no_return
      ]
    ]
  end

  defp plt_file_name do
    "dialyzer-#{Mix.env()}-#{System.version()}-#{System.otp_release()}.plt"
  end
end
