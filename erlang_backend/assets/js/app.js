// CSS is built separately by Tailwind (npm run build) and linked in root.html.heex.

import "../../deps/phoenix_html/priv/static/phoenix_html.js"
import {Socket} from "../vendor/phoenix.mjs"
import {LiveSocket} from "../vendor/phoenix_live_view.esm.js"
import "../vendor/topbar.js"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

const STUCK_SUBMIT_MS = 12_000
const RELOAD_FALLBACK_MS = 5_000

function decodeAttrValue(raw) {
  if (!raw) return ""
  const ta = document.createElement("textarea")
  ta.innerHTML = raw
  return ta.value
}

function parseJsonAttr(el, name) {
  const raw = el.getAttribute(name)
  if (!raw) return []

  for (const candidate of [raw, decodeAttrValue(raw)]) {
    try {
      const parsed = JSON.parse(candidate)
      if (Array.isArray(parsed)) return parsed
    } catch (_e) {
      // try next decode strategy
    }
  }

  return []
}

function copyToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    return navigator.clipboard.writeText(text).catch(() => legacyCopy(text))
  }
  return legacyCopy(text)
}

function legacyCopy(text) {
  return new Promise((resolve, reject) => {
    const ta = document.createElement("textarea")
    ta.value = text
    ta.style.position = "fixed"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    try {
      document.execCommand("copy") ? resolve() : reject()
    } catch (e) {
      reject(e)
    } finally {
      document.body.removeChild(ta)
    }
  })
}

function stopTypewriter(el) {
  const state = el._typewriterState
  if (!state) return
  clearTimeout(state.timer)
  delete el._typewriterState
  delete el.dataset.uxInit
}

function startTypewriter(el) {
  if (el.dataset.uxInit === "typewriter") return

  const textEl = el.querySelector("[data-typewriter]")
  if (!textEl) return

  const suggestions = parseJsonAttr(el, "data-suggestions")
  if (suggestions.length === 0) return

  stopTypewriter(el)

  const state = {
    suggestionIndex: 0,
    charIndex: 0,
    deleting: false,
    currentText: "",
    timer: null
  }
  el._typewriterState = state
  el.dataset.uxInit = "typewriter"

  const tick = () => {
    const target = suggestions[state.suggestionIndex]

    if (!state.deleting && state.charIndex < target.length) {
      state.charIndex++
      state.currentText = target.slice(0, state.charIndex)
      textEl.textContent = state.currentText
      state.timer = setTimeout(tick, 40)
    } else if (!state.deleting) {
      state.timer = setTimeout(() => {
        state.deleting = true
        tick()
      }, 2000)
    } else if (state.charIndex > 0) {
      state.charIndex--
      state.currentText = target.slice(0, state.charIndex)
      textEl.textContent = state.currentText
      state.timer = setTimeout(tick, 20)
    } else {
      state.deleting = false
      state.suggestionIndex = (state.suggestionIndex + 1) % suggestions.length
      state.timer = setTimeout(tick, 400)
    }
  }

  tick()
}

function flashCopyLabel(label, text, resetMs = 1500) {
  if (!label) return
  const defaultLabel = label.dataset.defaultLabel || label.textContent || "Share"
  if (!label.dataset.defaultLabel) label.dataset.defaultLabel = defaultLabel
  label.textContent = text
  setTimeout(() => {
    label.textContent = defaultLabel
  }, resetMs)
}

function handleCopyLink(btn) {
  const url = btn.dataset.copyUrl || window.location.href
  const label = btn.querySelector("[data-copy-label]")
  copyToClipboard(url)
    .then(() => flashCopyLabel(label, "Copied"))
    .catch(() => flashCopyLabel(label, "Failed"))
}

function initChatUx(root = document) {
  root.querySelectorAll("[data-suggestion-typewriter]").forEach((el) => startTypewriter(el))
}

function showReconnectBanner() {
  document.querySelector("[data-reconnect-banner]")?.classList.remove("hidden")
}

function hideReconnectBanner() {
  document.querySelector("[data-reconnect-banner]")?.classList.add("hidden")
}

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
    disconnected() {
      showReconnectBanner()
    },
    reconnected() {
      hideReconnectBanner()
      this.pushEvent("sync_state", {})
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

window.topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => window.topbar.show())
window.addEventListener("phx:page-loading-stop", _info => {
  window.topbar.hide()
  observeChatUx()
})

liveSocket.connect()

document.addEventListener("click", (e) => {
  const copyBtn = e.target.closest("#copy-link-btn, [data-copy-link]")
  if (!copyBtn) return
  e.preventDefault()
  handleCopyLink(copyBtn)
}, true)

document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    document.getElementById("chat-input")?.focus()
    return
  }

  const mod = e.metaKey || e.ctrlKey
  if (mod && e.key.toLowerCase() === "k") {
    e.preventDefault()
    document.getElementById("new-chat-btn")?.click()
  }
}, true)

function observeChatUx() {
  const messages = document.getElementById("messages")
  if (!messages || messages.dataset.uxObserved === "1") return
  messages.dataset.uxObserved = "1"
  const uxObserver = new MutationObserver(() => initChatUx(messages))
  uxObserver.observe(messages, {childList: true, subtree: true})
  initChatUx(messages)
}

observeChatUx()

liveSocket.getSocket().onClose(() => {
  console.debug("ws closed")
  showReconnectBanner()
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