defmodule AgentBackend.Tools.OutputValidatorTest do
  use ExUnit.Case, async: true

  alias AgentBackend.Tools.OutputValidator

  test "normalize_result defaults unparseable content to pass" do
    assert Jason.decode!(OutputValidator.normalize_result("lol not json")) == %{"passed" => true}
  end

  test "normalize_result defaults missing passed key to pass" do
    assert Jason.decode!(OutputValidator.normalize_result(~s({"ok": true}))) == %{"passed" => true}
  end

  test "normalize_result preserves explicit fail" do
    raw = ~s({"passed": false, "issues": ["invented employer"]})
    assert %{"passed" => false, "issues" => ["invented employer"]} = Jason.decode!(OutputValidator.normalize_result(raw))
  end

  test "normalize_result preserves explicit pass" do
    assert Jason.decode!(OutputValidator.normalize_result(~s({"passed": true}))) == %{"passed" => true}
  end
end
