defmodule Mix.Tasks.Evals.Gen do
  @moduledoc """
  Generates a new evaluation with a template eval.ex file.

  ## Usage

      $ mix evals.gen eval_name

  This task creates a new directory for the evaluation and generates a template eval.ex file.
  """
  use Mix.Task

  @shortdoc "Generates a new evaluation"

  @impl Mix.Task
  def run(args) do
    case args do
      [eval_name] ->
        generate_evaluation(eval_name)

      _ ->
        IO.puts("""
        ERROR: Missing evaluation name

        Usage: mix evals.gen EVAL_NAME

        Example:
          mix evals.gen my_evaluation
        """)

        System.halt(1)
    end
  end

  defp generate_evaluation(eval_name) do
    IO.puts("Generating evaluation: #{eval_name}")

    # Create the evaluation directory
    eval_dir = Path.join("evals", eval_name)

    if File.exists?(eval_dir) do
      IO.puts("ERROR: Evaluation '#{eval_name}' already exists at #{eval_dir}")
      System.halt(1)
    end

    File.mkdir_p!(eval_dir)
    IO.puts("Created directory: #{eval_dir}")

    # Create the eval.ex file
    eval_file = Path.join(eval_dir, "eval.ex")
    module_name = Macro.camelize(eval_name)

    eval_content = """
    defmodule Dantex.Eval.#{module_name} do
      @moduledoc \"\"\"
      Evaluation: #{eval_name}

      This module defines an evaluation that can be run using `mix evals.run #{eval_name}`.
      Customize this file to implement your specific evaluation logic.
      \"\"\"

      alias Dantex.{Agent, Message}
      alias Dantex.Eval.{TestCase, RegexMatchMetric, Metric}

      @doc \"\"\"
      Runs the evaluation and returns the results.

      This function is called by the `mix evals.run #{eval_name}` task.

      ## Parameters
        * `agent` - Optional agent to use for the evaluation. If provided, this will override the agent defined in this function.
      \"\"\"
      @spec run(Agent.t() | nil) :: {:ok, Agent.t(), Metric.t(), [TestCase.t()]} | {:error, term()}
      def run(agent \\\\ nil) do
        # Define your test cases
        test_cases = [
          # Example test case:
          TestCase.new(
            [Message.user("What is 2+2?")],
            "4"  # Expected output
          )
          # Add more test cases as needed
        ]

        # Define your metric
        metric = RegexMatchMetric.new(~r/4/)

        # Define your agent/model if not provided
        final_agent = if agent do
          agent
        else
          Agent.new(provider: :openai, model: "gpt-4o-mini")
        end

        # Just return the setup; it will be run and results will be printed to html
        {:ok, final_agent, metric, test_cases}
      end
    end
    """

    File.write!(eval_file, eval_content)
    IO.puts("Created file: #{eval_file}")

    # Create a README.md file with instructions
    readme_file = Path.join(eval_dir, "README.md")

    readme_content = """
    # #{module_name} Evaluation

    This directory contains the evaluation for `#{eval_name}`.

    ## Running the Evaluation

    To run this evaluation:

    ```
    mix evals.run #{eval_name}
    ```

    You can also specify a provider and model to use:

    ```
    mix evals.run #{eval_name} --provider openai --model gpt-4
    ```

    ## Customizing the Evaluation

    Edit the `eval.ex` file to customize:

    1. Test cases
    2. Metrics
    3. Agent/model configuration

    ## Additional Files

    You can add additional files to this directory as needed for your evaluation:

    - Data files
    - Configuration files
    - Helper modules
    """

    File.write!(readme_file, readme_content)
    IO.puts("Created file: #{readme_file}")

    IO.puts("""

    Evaluation '#{eval_name}' generated successfully!

    To run this evaluation:
      mix evals.run #{eval_name}

    Or with a specific provider and model:
      mix evals.run #{eval_name} --provider openai --model gpt-4

    Edit #{eval_file} to customize your evaluation.
    """)
  end
end
