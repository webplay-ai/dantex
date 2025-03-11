defmodule Dantex.EvalTest do
  use ExUnit.Case
  alias Dantex.Eval
  alias Dantex.Agent
  alias Dantex.Eval.{TestCase}
  alias Dantex.Message
  require Logger

  # Mock model for testing
  defmodule MockModel do
    defstruct [:provider, :model]
  end

  describe "print_html_results/4" do
    setup do
      # Create a temporary directory for test output
      tmp_dir = System.tmp_dir!() |> Path.join("dantex_test_#{:rand.uniform(1000)}")
      File.mkdir_p!(tmp_dir)

      # Create test data
      model = %MockModel{provider: :openai, model: "gpt-4"}
      agent = %Agent{model: model, messages: []}
      metric = Dantex.Eval.RegexMatchMetric

      # Create some test cases
      test_cases = [
        %TestCase{
          input: [Message.user("What is 2+2?")],
          expected_output: "4",
          actual_output: "4",
          score: 1.0,
          pass: true,
          tokens: 10
        },
        %TestCase{
          input: [Message.user("What is 3+3?")],
          expected_output: "6",
          actual_output: "The answer is 6",
          score: 0.8,
          pass: true,
          tokens: 15
        },
        %TestCase{
          input: [Message.user("What is 4+4?")],
          expected_output: "8",
          actual_output: "The sum is 10",
          score: 0.0,
          pass: false,
          tokens: 12
        }
      ]

      on_exit(fn ->
        # Clean up the temporary directory after tests
        File.rm_rf!(tmp_dir)
      end)

      %{tmp_dir: tmp_dir, agent: agent, metric: metric, test_cases: test_cases}
    end

    test "successfully generates HTML results file", %{
      tmp_dir: tmp_dir,
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      result = Eval.print_html_results(tmp_dir, agent, metric, test_cases)
      assert result == {:ok}

      # Verify that a file was created
      files = File.ls!(tmp_dir)
      assert length(files) == 1

      # Verify file has HTML content
      file_path = Path.join(tmp_dir, List.first(files))
      content = File.read!(file_path)

      # Check for expected content in the HTML
      assert content =~ "<!DOCTYPE html>"
      assert content =~ "<title>Evaluation Results</title>"
      assert content =~ "openai/gpt-4"
      assert content =~ "66.67% (2/3 tests passed)"
      assert content =~ "Total Tokens Used:</strong> 37"
    end

    test "handles empty test cases list", %{tmp_dir: tmp_dir, agent: agent, metric: metric} do
      result = Eval.print_html_results(tmp_dir, agent, metric, [])
      assert result == {:ok}

      # Verify that a file was created
      files = File.ls!(tmp_dir)
      assert length(files) == 1

      # Verify file has HTML content with 0% score
      file_path = Path.join(tmp_dir, List.first(files))
      content = File.read!(file_path)

      assert content =~ "0.0% (0/0 tests passed)"
      assert content =~ "Total Tokens Used:</strong> 0"
    end

    test "returns error when directory doesn't exist", %{
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      # Use a non-existent path without creating directories
      invalid_path = "/non/existent/path/that/should/not/exist"

      result = Eval.print_html_results(invalid_path, agent, metric, test_cases)
      assert match?({:error, _}, result)
    end

    test "handles file write errors", %{
      tmp_dir: tmp_dir,
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      # Make the directory read-only to cause a write error
      # Note: This test may not work on all systems depending on permissions
      :ok = File.chmod(tmp_dir, 0o444)

      result = Eval.print_html_results(tmp_dir, agent, metric, test_cases)

      # Reset permissions for cleanup
      :ok = File.chmod(tmp_dir, 0o755)

      # The result might be {:error, reason} or it might raise an exception
      # that gets caught in the rescue block, returning {:error, exception}
      assert match?({:error, _}, result)
    end
  end
end
