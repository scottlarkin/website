defmodule AgentBackendWeb.SEO do
  @moduledoc false

  @site_name "scott"
  @home_title @site_name
  @home_description "Chat with an AI assistant about Scott's skills, experience, projects, and contact."
  @chat_title "Chat — scott"
  @chat_description "Private chat session."

  def assigns(socket, chat_id) do
    seo = assigns_for(chat_id)
    Phoenix.Component.assign(socket, seo)
  end

  defp assigns_for(nil) do
    %{
      page_title: @home_title,
      meta_description: @home_description,
      robots: "index,follow",
      canonical_url: absolute_url("/")
    }
  end

  defp assigns_for(chat_id) when is_binary(chat_id) do
    %{
      page_title: @chat_title,
      meta_description: @chat_description,
      robots: "noindex,nofollow",
      canonical_url: absolute_url("/c/#{chat_id}")
    }
  end

  defp absolute_url(path) when is_binary(path) do
    AgentBackendWeb.Endpoint.url() <> path
  end
end