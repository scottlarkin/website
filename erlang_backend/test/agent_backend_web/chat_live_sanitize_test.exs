defmodule AgentBackendWeb.ChatLiveSanitizeTest do
  use ExUnit.Case, async: true

  test "sanitize_html strips script and event handlers" do
    dirty =
      "<p onclick=\"alert(1)\">hi</p><script>evil()</script><a href=\"javascript:void(0)\">x</a>"

    clean = AgentBackendWeb.ChatLive.sanitize_html(dirty)

    refute clean =~ "<script"
    refute clean =~ "onclick"
    refute clean =~ "javascript"
    assert clean =~ "hi"
  end
end
