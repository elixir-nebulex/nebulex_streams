defmodule Nebulex.Streams.MixProject do
  use Mix.Project

  @source_url "https://github.com/elixir-nebulex/nebulex_streams"
  @version "0.2.1"

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

      # Dialyzer
      dialyzer: dialyzer(),

      # Usage Rules
      usage_rules: usage_rules(),

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

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        precommit: :test
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
      {:nebulex, "~> 3.0 and >= 3.0.1"},
      {:nimble_options, "~> 0.5 or ~> 1.0"},
      {:phoenix_pubsub, "~> 2.4"},
      {:telemetry, "~> 0.4 or ~> 1.0"},

      # Test & Code Analysis
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.4", only: :test},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:nebulex_local, "~> 3.1", only: :test},

      # Benchmark Test
      {:benchee, "~> 1.5", only: [:dev, :test]},
      {:benchee_html, "~> 1.0", only: [:dev, :test]},

      # Usage Rules
      {:usage_rules, "~> 1.0", only: [:dev]},

      # Docs
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      precommit: [
        "deps.unlock --check-unused",
        "deps.audit",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "coveralls.html",
        "sobelow --skip --exit Low",
        "dialyzer --format short",
        "docs --warnings-as-errors"
      ],
      "ur.sync": ["usage_rules.sync"]
    ]
  end

  defp package do
    [
      name: :nebulex_streams,
      maintainers: ["Carlos Bolanos"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*)
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:nebulex],
      plt_file: {:no_warn, "priv/plts/" <> plt_file_name()},
      flags: [
        :unmatched_returns,
        :error_handling,
        :extra_return,
        :no_opaque,
        :no_return
      ]
    ]
  end

  defp plt_file_name do
    "dialyzer-#{Mix.env()}-Elixir-#{System.version()}-OTP-#{System.otp_release()}.plt"
  end

  defp usage_rules do
    [
      # The file to write usage rules into (required for usage_rules syncing)
      file: "AGENTS.md",

      # Rules linked from AGENTS.md into deps/, read on demand. The entry
      # point (nebulex:workflow) is imported eagerly by the AGENTS.md preface.
      usage_rules: [
        {:nebulex, [sub_rules: ["nebulex", "elixir-style"], link: :markdown]},
        {:usage_rules, [sub_rules: [], link: :markdown]}
      ]
    ]
  end
end
