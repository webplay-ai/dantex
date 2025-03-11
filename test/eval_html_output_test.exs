defmodule Dantex.EvalHtmlOutputTest do
  use ExUnit.Case
  import Mock
  alias Dantex.Eval
  alias Dantex.Agent
  alias Dantex.Eval.{TestCase}
  alias Dantex.Message

  # Mock model for testing
  defmodule MockModel do
    defstruct [:provider, :model]
  end

  describe "print_html_results/4 with mocked file operations" do
    setup do
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
        }
      ]

      %{agent: agent, metric: metric, test_cases: test_cases}
    end

    test "successfully writes HTML file with mocked File operations", %{
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      with_mocks([
        {File, [], [
          mkdir_p!: fn _path -> :ok end,
          write: fn _path, content ->
            # Verify content has expected HTML elements
            assert content =~ "<!DOCTYPE html>"
            assert content =~ "<title>Evaluation Results</title>"
            assert content =~ "openai/gpt-4"
            :ok
          end
        ]}
      ]) do
        result = Eval.print_html_results("/mock/path", agent, metric, test_cases)
        assert result == {:ok}

        # Verify File.mkdir_p! was called
        assert called File.mkdir_p!("/mock/path")

        # Verify File.write was called with a path that includes the timestamp and model
        assert called File.write(:_, :_)
      end
    end

    test "handles file write errors with mocked File operations", %{
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      with_mocks([
        {File, [], [
          mkdir_p!: fn _path -> :ok end,
          write: fn _path, _content -> {:error, :eacces} end
        ]}
      ]) do
        result = Eval.print_html_results("/mock/path", agent, metric, test_cases)
        assert result == {:error, :eacces}
      end
    end

    test "handles exceptions during HTML generation", %{
      agent: agent,
      metric: metric,
      test_cases: test_cases
    } do
      with_mocks([
        {File, [], [
          mkdir_p!: fn _path -> raise "Simulated error" end
        ]}
      ]) do
        result = Eval.print_html_results("/mock/path", agent, metric, test_cases)
        assert match?({:error, _}, result)
      end
    end
  end
end
