defmodule AgentBackendWeb.Components do
  use Phoenix.Component

  attr :message, :map, required: true
  attr :index, :integer, required: true
  
  def message_bubble(assigns) do
    assigns = assign(assigns, :is_user, assigns.message.role == "user")
    ~H"""
    <div class={"flex gap-3 #{if @is_user, do: "justify-end", else: ""}"}>
      <div class={"flex gap-2 max-w-3xl #{if @is_user, do: "flex-row-reverse", else: ""}"}>
        <.avatar type={if @is_user, do: :user, else: :assistant} />
        <div class={"rounded-2xl px-4 py-2 #{if @is_user, do: "bg-blue-600 text-white", else: "bg-gray-800 text-gray-100"}"}>
          <pre class="whitespace-pre-wrap text-sm"><%= @message.content %></pre>
        </div>
      </div>
    </div>
    """
  end

  def avatar(assigns) do
    assigns = assign_new(assigns, :type, fn -> :assistant end)
    ~H"""
    <div class={"w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 #{if @type == :user, do: "bg-blue-600", else: "bg-purple-600"}"}>
      <.icon name={if @type == :user, do: :user, else: :bot} class="w-5 h-5 text-white" />
    </div>
    """
  end

  def icon(assigns) do
    name = assigns[:name] || :bot
    class = assigns[:class] || ""
    
    {:safe, icon_svg(name, class)}
  end

  defp icon_svg(:user, class) do
    "<svg class=\"" <> class <> "\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z\"/></svg>"
  end

  defp icon_svg(:bot, class) do
    "<svg class=\"" <> class <> "\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z\"/></svg>"
  end

  defp icon_svg(:send, class) do
    "<svg class=\"" <> class <> "\" fill=\"none\" stroke=\"currentColor\" viewBox=\"0 0 24 24\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M12 19l9 2-9-18-9 18 9-2zm0 0v-18\"/></svg>"
  end
end