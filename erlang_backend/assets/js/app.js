// CSS is built separately by Tailwind (npm run build) and linked in root.html.heex.

import "../../deps/phoenix_html/priv/static/phoenix_html.js"
import {Socket} from "../vendor/phoenix.mjs"
import {LiveSocket} from "../vendor/phoenix_live_view.esm.js"
import "../vendor/topbar.js"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

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

function handleCopyMessage(btn) {
  const text = btn.dataset.copyText || ""
  if (!text) return
  const label = btn.querySelector("[data-copy-label]")
  copyToClipboard(text)
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

// ~8 lines at 16px / 1.4 line-height + vertical padding
const COMPOSER_MAX_HEIGHT_PX = Math.round(16 * 1.4 * 8 + 20)

let Hooks = {
  // Stick #messages to the bottom while the user is following the tail.
  // During active generation (data-loading="true") always follow.
  // Never gate on composer focus — the textarea stays focused during streams.
  AutoScroll: {
    mounted() {
      this.stickToBottom = true
      this.thresholdPx = 120
      this.programmatic = false
      this.msgCount = this.countMessages()

      this.onScroll = () => {
        if (this.programmatic) return
        const el = this.el
        const distance = el.scrollHeight - el.scrollTop - el.clientHeight
        this.stickToBottom = distance <= this.thresholdPx
      }
      this.el.addEventListener("scroll", this.onScroll, {passive: true})

      this.observer = new MutationObserver(() => {
        const n = this.countMessages()
        // New user/assistant bubble → always snap to bottom
        if (n !== this.msgCount) {
          this.msgCount = n
          this.stickToBottom = true
        }
        this.maybeScroll()
      })
      this.observer.observe(this.el, {
        childList: true,
        subtree: true,
        characterData: true
      })

      this.scrollToBottom()
    },
    updated() {
      // Server patches while streaming: keep following if loading or stuck to bottom
      if (this.el.dataset.loading === "true") this.stickToBottom = true
      this.maybeScroll()
    },
    destroyed() {
      this.observer?.disconnect()
      this.el.removeEventListener("scroll", this.onScroll)
      if (this._releaseTimer) clearTimeout(this._releaseTimer)
    },
    countMessages() {
      return this.el.querySelectorAll("[id^='msg-']").length
    },
    maybeScroll() {
      if (this.stickToBottom || this.el.dataset.loading === "true") {
        this.scrollToBottom()
      }
    },
    scrollToBottom() {
      const el = this.el
      this.programmatic = true
      if (this._releaseTimer) clearTimeout(this._releaseTimer)

      const apply = () => {
        // Direct assignment — do not use scrollIntoView (it can scroll the window)
        el.scrollTop = el.scrollHeight
      }

      apply()
      // Layout may lag one or two frames behind morphdom / markdown paint
      requestAnimationFrame(() => {
        apply()
        requestAnimationFrame(() => {
          apply()
          this._releaseTimer = setTimeout(() => {
            this.programmatic = false
            this.stickToBottom = true
          }, 50)
        })
      })
    }
  },

  // Enter sends; Shift+Enter inserts a newline. Auto-grows up to COMPOSER_MAX_HEIGHT_PX.
  Composer: {
    mounted() {
      this.onKeyDown = (e) => {
        if (e.key !== "Enter" || e.shiftKey) return
        if (e.isComposing || e.keyCode === 229) return
        e.preventDefault()
        const form = this.el.form
        if (!form) return
        if (typeof form.requestSubmit === "function") {
          form.requestSubmit()
        } else {
          form.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
        }
      }
      this.onInput = () => this.resize()
      this.el.addEventListener("keydown", this.onKeyDown)
      this.el.addEventListener("input", this.onInput)
      this.resize()
    },
    updated() {
      this.resize()
    },
    destroyed() {
      this.el.removeEventListener("keydown", this.onKeyDown)
      this.el.removeEventListener("input", this.onInput)
    },
    resize() {
      const el = this.el
      el.style.height = "auto"
      const next = Math.min(el.scrollHeight, COMPOSER_MAX_HEIGHT_PX)
      el.style.height = `${next}px`
      el.style.overflowY = el.scrollHeight > COMPOSER_MAX_HEIGHT_PX ? "auto" : "hidden"
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

// Copy buttons only — never touch the composer.
document.addEventListener("click", (e) => {
  const copyMsg = e.target.closest("[data-copy-message]")
  if (copyMsg) {
    e.preventDefault()
    handleCopyMessage(copyMsg)
    return
  }

  const copyBtn = e.target.closest("#copy-link-btn, [data-copy-link]")
  if (!copyBtn) return
  e.preventDefault()
  handleCopyLink(copyBtn)
})

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

window.liveSocket = liveSocket
