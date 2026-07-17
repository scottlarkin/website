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

  test "sanitize_html keeps GFM table markup" do
    table =
      """
      <table>
        <thead><tr><th style="text-align: left;">Name</th></tr></thead>
        <tbody><tr><td style="text-align: left;">Alice</td></tr></tbody>
      </table>
      """

    clean = AgentBackendWeb.ChatLive.sanitize_html(table)

    assert clean =~ "<table>"
    assert clean =~ "<thead>"
    assert clean =~ "<th"
    assert clean =~ "<td"
    assert clean =~ "Alice"
  end

  test "wrap_markdown_tables adds horizontal scroll shell" do
    html = "<p>intro</p><table><tr><td>a</td></tr></table><p>out</p>"
    wrapped = AgentBackendWeb.ChatLive.wrap_markdown_tables(html)

    assert wrapped =~ ~s(<div class="term-table-wrap"><table>)
    assert wrapped =~ ~s(</table></div>)
    assert wrapped =~ "<p>intro</p>"
    assert wrapped =~ "<p>out</p>"
  end

  test "earmark converts pipe tables to html" do
    md = """
    | Name | Role |
    |------|------|
    | Alice | Eng |
    """

    assert {:ok, html, _} = Earmark.as_html(md, code_class_prefix: "language-")
    assert html =~ "<table>"
    assert html =~ "<th"
    assert html =~ "Alice"

    clean =
      html
      |> AgentBackendWeb.ChatLive.sanitize_html()
      |> AgentBackendWeb.ChatLive.wrap_markdown_tables()

    assert clean =~ ~s(<div class="term-table-wrap"><table>)
    assert clean =~ "Alice"
  end
end
