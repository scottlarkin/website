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

const STUCK_SUBMIT_MS = 12_000
const RELOAD_FALLBACK_MS = 5_000

let Hooks = {
  AutoScroll: {
    mounted() {
      this.observer = new MutationObserver(() => this.scrollToBottom())
      this.observer.observe(this.el, {childList: true, subtree: true, characterData: true})
      this.scrollToBottom()
    },
    updated() {
      this.scrollToBottom()
    },
    destroyed() {
      this.observer?.disconnect()
    },
    scrollToBottom() {
      requestAnimationFrame(() => {
        this.el.scrollTop = this.el.scrollHeight
      })
    }
  },

  ConnectionStatus: {
    mounted() {
      this.banner = this.el.querySelector("[data-reconnect-banner]")
    },
    disconnected() {
      this.banner?.classList.remove("hidden")
    },
    reconnected() {
      this.banner?.classList.add("hidden")
      this.pushEvent("sync_state", {})
    }
  },

  RevisionCrossfade: {
    mounted() {
      this.hadHeldDraft = !!this.el.querySelector("[data-held-draft]")
    },
    updated() {
      const held = this.el.querySelector("[data-held-draft]")
      const live = this.el.querySelector("[data-live-content]")

      if (this.hadHeldDraft && !held && live) {
        live.style.opacity = "0"
        requestAnimationFrame(() => {
          live.style.transition = "opacity 200ms ease-out"
          live.style.opacity = "1"
        })
      }

      this.hadHeldDraft = !!held
    }
  },

  ChatForm: {
    mounted() {
      this.watchdog = null
      this.reloadTimer = null
      this.shouldRefocus = false
      this.onSubmit = () => {
        this.shouldRefocus = true
        this.startWatchdog()
      }
      this.el.addEventListener("submit", this.onSubmit)
    },
    destroyed() {
      this.clearTimers()
      this.el.removeEventListener("submit", this.onSubmit)
    },
    updated() {
      if (!this.el.classList.contains("phx-submit-loading")) {
        this.clearTimers()
      }
      if (this.shouldRefocus) {
        const input = this.el.querySelector("#chat-input")
        if (input && !this.el.classList.contains("phx-submit-loading")) {
          requestAnimationFrame(() => input.focus())
          this.shouldRefocus = false
        }
      }
    },
    startWatchdog() {
      this.clearTimers()
      const baselineCount = document.querySelectorAll("#messages [id^='msg-']").length

      this.watchdog = setTimeout(() => {
        if (!this.isStuck(baselineCount)) return
        window.liveSocket.reconnect()
        this.reloadTimer = setTimeout(() => {
          if (this.isStuck(baselineCount)) {
            window.location.reload()
          }
        }, RELOAD_FALLBACK_MS)
      }, STUCK_SUBMIT_MS)
    },
    isStuck(baselineCount) {
      if (!this.el.classList.contains("phx-submit-loading")) return false
      const msgCount = document.querySelectorAll("#messages [id^='msg-']").length
      return msgCount <= baselineCount
    },
    clearTimers() {
      if (this.watchdog) {
        clearTimeout(this.watchdog)
        this.watchdog = null
      }
      if (this.reloadTimer) {
        clearTimeout(this.reloadTimer)
        this.reloadTimer = null
      }
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

liveSocket.connect()

liveSocket.getSocket().onClose(() => {
  console.debug("ws closed")
})

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && !liveSocket.isConnected()) {
    liveSocket.reconnect()
  }
})

window.addEventListener("focus", () => {
  if (!liveSocket.isConnected()) {
    liveSocket.reconnect()
  }
})

window.liveSocket = liveSocket