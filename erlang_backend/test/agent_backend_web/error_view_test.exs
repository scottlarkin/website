defmodule AgentBackendWeb.ErrorViewTest do
  use ExUnit.Case, async: true

  alias AgentBackendWeb.ErrorView

  test "404 render" do
    html =
      ErrorView.render("404.html", %{})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "Dead end"
    assert html =~ "404"
  end

  test "500 render" do
    html =
      ErrorView.render("500.html", %{})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "My bad"
    assert html =~ "500"
  end
end
