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

// Touch / narrow viewport — relax "always focus" so iOS Done can dismiss the KB.
function isMobileUi() {
  if (typeof window === "undefined") return false
  if (window.matchMedia("(max-width: 767px)").matches) return true
  if (window.matchMedia("(pointer: coarse)").matches && window.innerWidth < 1024) return true
  return false
}

function isIOS() {
  if (typeof navigator === "undefined") return false
  const ua = navigator.userAgent || ""
  if (/iPad|iPhone|iPod/.test(ua)) return true
  // iPadOS 13+ reports as Mac with touch
  return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1
}

// Keep scale locked on iOS/mobile. Do NOT toggle this on blur — that caused zoom jumps.
function lockIOSViewport() {
  if (!isIOS() && !isMobileUi()) return
  const meta = document.querySelector('meta[name="viewport"]')
  if (!meta) return
  meta.setAttribute(
    "content",
    "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover"
  )
}

lockIOSViewport()

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
      this.blurTimer = null
      this.caretTimer = null
      this.shouldRefocus = false
      this.holdBlur = false
      this.getInput = () => this.el.querySelector("#chat-input")
      this.focusInput = () => {
        const input = this.getInput()
        if (!input) return
        if (document.activeElement !== input) input.focus({preventScroll: true})
        syncBlockCaret()
      }
      this.syncCaret = () => syncBlockCaret()
      this.onSubmit = () => {
        this.shouldRefocus = true
        this.startWatchdog()
      }
      this.onPointerDown = (e) => {
        const interactive = e.target.closest(
          "a, button, textarea, select, [contenteditable='true']"
        )
        const input = this.getInput()
        this.holdBlur = !!(interactive && interactive !== input)
        if (!this.holdBlur) {
          // Don't preventDefault on mobile — it can break keyboard / focus timing
          if (!isMobileUi() && e.target !== input) e.preventDefault()
          this.focusInput()
        }
      }
      this.onPointerUp = () => {
        if (this.holdBlur) {
          this.holdBlur = false
          // Desktop: reclaim after button click. Mobile: leave focus alone.
          if (!isMobileUi()) this.focusInput()
        }
      }
      this.onBlur = () => {
        if (this.blurTimer) clearTimeout(this.blurTimer)
        this.blurTimer = setTimeout(() => {
          this.blurTimer = null
          if (this.holdBlur) return

          // Mobile: honor Done — stay blurred (desktop keeps always-focus).
          if (isMobileUi() || isIOS()) {
            lockIOSViewport()
            window.scrollTo(0, 0)
            return
          }

          this.focusInput()
        }, 50)
      }
      this.onKeyDown = (e) => {
        const input = this.getInput()
        if (!input) return
        if (e.metaKey || e.ctrlKey || e.altKey) return
        if (e.key === "Tab") return
        if (e.isComposing) return

        const focused = document.activeElement === input
        const printable = e.key.length === 1
        const editKey =
          printable ||
          e.key === "Backspace" ||
          e.key === "Delete" ||
          e.key === "Enter" ||
          e.key === "ArrowLeft" ||
          e.key === "ArrowRight" ||
          e.key === "Home" ||
          e.key === "End"

        if (!editKey) return

        // Desktop-only: steal keystrokes into the composer when unfocused
        if (!focused && !isMobileUi()) {
          input.focus({preventScroll: true})
          if (printable) {
            e.preventDefault()
            const start = input.selectionStart ?? input.value.length
            const end = input.selectionEnd ?? input.value.length
            input.value = input.value.slice(0, start) + e.key + input.value.slice(end)
            const next = start + e.key.length
            input.setSelectionRange(next, next)
            input.dispatchEvent(new Event("input", {bubbles: true}))
          }
        }
        requestAnimationFrame(() => this.syncCaret())
      }
      this.onCaretSync = () => this.syncCaret()
      this.el.addEventListener("submit", this.onSubmit)
      document.addEventListener("pointerdown", this.onPointerDown, true)
      document.addEventListener("pointerup", this.onPointerUp, true)
      document.addEventListener("keydown", this.onKeyDown, true)

      const input = this.getInput()
      if (input) {
        input.addEventListener("blur", this.onBlur)
        for (const ev of ["input", "keyup", "keydown", "click", "select", "focus", "scroll"]) {
          input.addEventListener(ev, this.onCaretSync)
        }
      }
      this.caretTimer = setInterval(() => this.syncCaret(), 50)
      // Desktop: always focused. Mobile: wait for tap.
      if (!isMobileUi()) this.focusInput()
      this.syncCaret()
    },
    destroyed() {
      this.clearTimers()
      if (this.blurTimer) clearTimeout(this.blurTimer)
      if (this.caretTimer) clearInterval(this.caretTimer)
      this.el.removeEventListener("submit", this.onSubmit)
      document.removeEventListener("pointerdown", this.onPointerDown, true)
      document.removeEventListener("pointerup", this.onPointerUp, true)
      document.removeEventListener("keydown", this.onKeyDown, true)
      const input = this.getInput()
      if (input) {
        input.removeEventListener("blur", this.onBlur)
        for (const ev of ["input", "keyup", "keydown", "click", "select", "focus", "scroll"]) {
          input.removeEventListener(ev, this.onCaretSync)
        }
      }
    },
    updated() {
      if (!this.el.classList.contains("phx-submit-loading")) {
        this.clearTimers()
      }
      const afterSubmit = this.shouldRefocus
      this.shouldRefocus = false

      if (isMobileUi()) {
        // After send, refocus so the user can keep typing.
        // Never force-focus on stream ticks if they dismissed the keyboard.
        if (afterSubmit) this.focusInput()
      } else {
        this.focusInput()
      }
      this.syncCaret()
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

// Caret mirror removed — native visible input + caret-color/shape in CSS.
function syncBlockCaret() {
  // no-op (kept so ChatForm hook calls stay safe)
}

// --- Button glow: fixed spotlight that follows the mouse over .btn-glow ---
let mouseGlowEl = null
function ensureMouseGlow() {
  if (mouseGlowEl && mouseGlowEl.isConnected) return mouseGlowEl
  mouseGlowEl = document.createElement("div")
  mouseGlowEl.id = "mouse-glow"
  mouseGlowEl.setAttribute("aria-hidden", "true")
  mouseGlowEl.style.cssText = [
    "position:fixed",
    "width:96px",
    "height:96px",
    "margin:0",
    "padding:0",
    "border-radius:50%",
    "pointer-events:none",
    "z-index:99999",
    "transform:translate(-50%,-50%)",
    "display:none",
    "background:radial-gradient(circle,rgba(56,189,248,0.9) 0%,rgba(56,189,248,0.35) 40%,transparent 70%)",
    "mix-blend-mode:screen"
  ].join(";")
  document.body.appendChild(mouseGlowEl)
  return mouseGlowEl
}

function trackBtnGlow(e) {
  const mx = e.clientX
  const my = e.clientY
  const spot = ensureMouseGlow()
  let overBtn = null

  document.querySelectorAll(".btn-glow").forEach((btn) => {
    const rect = btn.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) return
    const lx = mx - rect.left
    const ly = my - rect.top
    const inside = lx >= 0 && ly >= 0 && lx <= rect.width && ly <= rect.height

    if (inside) {
      overBtn = btn
      const danger = btn.classList.contains("btn-glow-danger")
      const rgb = danger ? "251,113,133" : "56,189,248"
      // In-button fill (above Tailwind background-color)
      btn.style.backgroundImage =
        `radial-gradient(circle 18px at ${lx}px ${ly}px, rgba(255,255,255,0.95), transparent 65%),` +
        `radial-gradient(circle 44px at ${lx}px ${ly}px, rgba(${rgb},0.85), transparent 70%)`
    } else {
      btn.style.removeProperty("background-image")
    }
  })

  if (overBtn) {
    const danger = overBtn.classList.contains("btn-glow-danger")
    spot.style.background = danger
      ? "radial-gradient(circle,rgba(251,113,133,0.95) 0%,rgba(251,113,133,0.35) 40%,transparent 70%)"
      : "radial-gradient(circle,rgba(56,189,248,0.95) 0%,rgba(56,189,248,0.35) 40%,transparent 70%)"
    spot.style.left = `${mx}px`
    spot.style.top = `${my}px`
    spot.style.display = "block"
  } else {
    spot.style.display = "none"
  }
}

document.addEventListener("pointermove", trackBtnGlow, {passive: true})
document.addEventListener("mousemove", trackBtnGlow, {passive: true})

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
// build 1784235473
