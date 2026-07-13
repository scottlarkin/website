// CSS is built separately by Tailwind (npm run build) and linked in root.html.heex.

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./socket"

// Include phoenix_html to handle form submission and UJS in forms.
// Imported directly from the Phoenix dependency's shipped JS file (no npm
// package required) so esbuild can bundle it instead of leaving an external
// `require("phoenix_html")` that browsers cannot resolve.
import "../../deps/phoenix_html/priv/static/phoenix_html.js"

// Establish Phoenix Socket and LiveView configuration
import {Socket} from "../vendor/phoenix.mjs"
import {LiveSocket} from "../vendor/phoenix_live_view.esm.js"
// topbar.js is a plain script (no ES exports) that sets `window.topbar` as a
// side effect, so we import it for that side effect and use the global.
import "../vendor/topbar.js"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {
  AutoScroll: {
    mounted() {
      this.scrollToBottom()
    },
    updated() {
      this.scrollToBottom()
    },
    scrollToBottom() {
      // Use requestAnimationFrame for smooth after render
      requestAnimationFrame(() => {
        this.el.scrollTop = this.el.scrollHeight
      })
    }
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
window.topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => window.topbar.show())
window.addEventListener("phx:page-loading-stop", _info => window.topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket