defmodule AgentBackend.Tools.OutputValidator do
  @behaviour AgentBackend.Tools.Behaviour

  @validator_system """
  You are a lenient fact-checker for a personal portfolio AI assistant.
  Default to PASS. The system prompt is the source of truth, but answers do not need to quote it.

  Always PASS for:
  - Paraphrasing, summarising, or synthesising facts from the system prompt
  - Concise answers that cover the question without listing everything
  - Reasonable grouping of skills, technologies, or experience
  - Minor wording differences, synonyms, or implied details that fit the source
  - Technologies or tools that are closely related to ones in the system prompt

  FAIL only when highly confident of an egregious error:
  - A completely invented employer or company not in the system prompt
  - A direct contradiction of stated facts (wrong current role, wrong company, wrong timeline)
  - Fabricated contact details, metrics, or projects with no basis in the source

  If unsure, borderline, or only mildly stretched — PASS.

  Reply with compact JSON only — no markdown, no prose.
  Pass: {"passed": true}
  Fail: {"passed": false, "issues": ["brief issue"]} — at most 2 short issues, only for egregious errors.
  """

  @impl true
  def name, do: "output_validator"

  @impl true
  def status_label, do: "Checking accuracy…"

  @impl true
  def schema do
    %{
      type: "function",
      function: %{
        name: name(),
        description:
          "Validate a draft assistant reply for hallucinations or factual errors before sending it to the user. Call this with your full draft when ready to finalize.",
        parameters: %{
          type: "object",
          properties: %{
            draft: %{
              type: "string",
              description: "The complete draft assistant reply to validate"
            }
          },
          required: ["draft"]
        }
      }
    }
  end

  @impl true
  def execute(arguments, ctx) do
    draft = Map.get(arguments, "draft", Map.get(arguments, :draft, ""))
    system_prompt = Map.get(ctx, :system_prompt, "")

    user_question = Map.get(ctx, :user_question, "")

    user_content = """
    System prompt (source of truth):
    #{system_prompt}

    User question:
    #{user_question}

    Draft to validate:
    #{draft}
    """

    messages = [
      %{role: "system", content: @validator_system},
      %{role: "user", content: user_content}
    ]

    started_at = System.monotonic_time(:millisecond)

    result =
      AgentBackend.OpenRouter.complete(messages,
        model: AgentBackend.OpenRouter.validator_model(),
        temperature: 0.1,
        max_tokens: 512
      )

    case result do
      {:ok, content} ->
        require Logger
        elapsed = System.monotonic_time(:millisecond) - started_at
        Logger.info("OutputValidator completed in #{elapsed}ms")
        normalize_result(content)

      {:error, reason} ->
        require Logger
        elapsed = System.monotonic_time(:millisecond) - started_at
        Logger.warning("OutputValidator API error in #{elapsed}ms, defaulting to pass: #{reason}")
        Jason.encode!(%{passed: true})
    end
  end

  defp normalize_result(content) do
    case decode_validation_json(content) do
      {:ok, %{"passed" => passed} = map} ->
        if validation_failed?(passed) do
          issues =
            (Map.get(map, "issues") || Map.get(map, "issue") || ["Validation failed"])
            |> List.wrap()
            |> Enum.map(&to_string/1)
            |> Enum.reject(&(&1 == ""))

          Jason.encode!(%{passed: false, issues: if(issues == [], do: ["Validation failed"], else: issues)})
        else
          Jason.encode!(%{passed: true})
        end

      :error ->
        require Logger
        Logger.warning("OutputValidator unparseable response, defaulting to pass: #{String.slice(content, 0, 300)}")

        Jason.encode!(%{passed: true})
    end
  end

  defp decode_validation_json(content) do
    trimmed =
      content
      |> String.trim()
      |> strip_code_fence()

    case Jason.decode(trimmed) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      _ ->
        case Regex.run(~r/\{.*\}/s, trimmed) do
          [json] ->
            case Jason.decode(json) do
              {:ok, map} when is_map(map) -> {:ok, map}
              _ -> :error
            end

          _ ->
            :error
        end
    end
  end

  defp validation_failed?(false), do: true
  defp validation_failed?("false"), do: true
  defp validation_failed?(_), do: false

  defp strip_code_fence(text) do
    text
    |> String.replace(~r/^```(?:json)?\s*/i, "")
    |> String.replace(~r/\s*```\s*$/i, "")
    |> String.trim()
  end
end