defmodule AgentBackendWeb.CoreComponents do
  use Phoenix.Component

  @doc """
  Renders a message bubble
  """
  def message_bubble(assigns) do
    message = assigns[:message]
    role = message.role
    content = message.content
    
    ~H"""
    <div class={message_wrapper_class(role)}>
      <%= if role != "user" do %>
        <.avatar type={:assistant} />
      <% end %>
      <div class={message_content_class(role)}>
        <div class={message_bubble_class(role)}>
          <pre class="whitespace-pre-wrap font-mono text-sm"><%= content %></pre>
        </div>
      </div>
      <%= if role == "user" do %>
        <.avatar type={:user} />
      <% end %>
    </div>
    """
  end

  defp message_wrapper_class("user"), do: "flex gap-3 justify-end"
  defp message_wrapper_class(_), do: "flex gap-3 justify-start"

  defp message_content_class("user"), do: "max-w-[70%] order-2"
  defp message_content_class(_), do: "max-w-[70%] order-1"

  defp message_bubble_class("user") do
    "rounded-2xl px-4 py-2.5 bg-blue-600 text-white rounded-br-md"
  end
  defp message_bubble_class(_) do
    "rounded-2xl px-4 py-2.5 bg-gray-800 border border-gray-700 text-gray-100 rounded-bl-md"
  end

  @doc """
  Renders an avatar
  """
  def avatar(assigns) do
    type = assigns[:type] || :assistant
    ~H"""
    <div class={avatar_classes(type)}>
      <%= if type == :assistant do %>
        <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"/></svg>
      <% else %>
        <svg class="w-5 h-5 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>
      <% end %>
    </div>
    """
  end

  defp avatar_classes(:assistant), do: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 bg-gray-800 border border-gray-700"
  defp avatar_classes(:user), do: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 bg-gray-700"
  defp avatar_classes(_), do: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 bg-gray-700"

  @doc """
  Renders an icon
  """
  def icon(assigns) do
    name = assigns[:name]
    class = assigns[:class] || ""
    
    case name do
      :terminal ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"/></svg>
        """
      :send ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-18"/></svg>
        """
      :stop ->
        ~H"""
        <svg class={class} fill="currentColor" viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
        """
      :x ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>
        """
      :menu ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/></svg>
        """
      :chevron_left ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/></svg>
        """
      :settings ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"/><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"/></svg>
        """
      :plus ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>
        """
      :trash ->
        ~H"""
        <svg class={class} fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
        """
      _ ->
        ~H"""
        """
    end
  end
end