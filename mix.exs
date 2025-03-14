defmodule Dantex.MixProject do
  use Mix.Project

  def project do
    [
      app: :dantex,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:httpoison, "~> 2.0"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Gemini
      {:goth, "~> 1.4"},
      {:uuid, "~> 1.1"},

      # Open AI
      {:openai_ex, "~> 0.8.6"},
      {:kino, "~> 0.14.2"},

      # Testing
      {:mock, "~> 0.3.0", only: :test}
    ]
  end
end
