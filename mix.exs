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
        "test.ci": :test
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
      {:nebulex, "~> 3.0"},
      {:nimble_options, "~> 0.5 or ~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 0.4 or ~> 1.0"},

      # Test & Code Analysis
      {:excoveralls, "~> 0.18", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},
      {:mimic, "~> 2.0", only: :test},
      {:nebulex_local, "~> 3.0", only: :test},

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
      "test.ci": [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "coveralls.html",
        "sobelow --exit --skip",
        "dialyzer --format short"
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

      # rules to include directly in AGENTS.md
      usage_rules: [
        {:nebulex,
         [
           sub_rules: [
             "workflow",
             "nebulex",
             "elixir-style",
             "elixir"
           ]
         ]},
        :otp
      ],

      # Agent skills configuration
      skills: [
        # Auto-build a "use-<pkg>" skill per dependency
        deps: [:nebulex]
      ]
    ]
  end
end
