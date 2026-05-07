import { Controller } from "@hotwired/stimulus"

// Polls the refresh endpoint while a viva turn is processing, replacing
// this entire element with the freshly-rendered partial. Because outerHTML
// replacement recreates the scrollable .card-body, naive polling resets
// the user's scroll position to the top on every tick. We hand off the
// scroll state through sessionStorage so the new controller instance can
// restore it.
//
// Data attributes:
//   data-viva-session-pending-value      (Boolean) whether a turn is currently processing
//   data-viva-session-refresh-url-value  (String)  URL that returns the replacement partial
//   data-viva-session-interval-ms-value  (Number)  poll interval in ms
const SCROLL_KEY = 'viva-session-scroll-state'
const NEAR_BOTTOM_PX = 50

export default class extends Controller {
  static values = {
    pending:    Boolean,
    refreshUrl: String,
    intervalMs: { type: Number, default: 3000 }
  }

  connect() {
    this.restoreScroll()
    if (this.pendingValue && this.refreshUrlValue) {
      this.scheduleRefresh()
    }
  }

  disconnect() {
    if (this.refreshTimer) clearTimeout(this.refreshTimer)
  }

  scheduleRefresh() {
    this.refreshTimer = setTimeout(() => this.fetchRefresh(), this.intervalMsValue)
  }

  async fetchRefresh() {
    this.saveScroll()
    try {
      const res = await fetch(this.refreshUrlValue, { headers: { Accept: "text/html" } })
      if (!res.ok) return this.scheduleRefresh()
      const html = await res.text()
      // The refresh partial renders the same #viva-session element, so we replace outerHTML.
      this.element.outerHTML = html
    } catch (e) {
      console.warn("viva refresh failed", e)
      this.scheduleRefresh()
    }
  }

  // --- scroll handling ---

  get cardBody() {
    return this.element.querySelector('.card-body')
  }

  saveScroll() {
    const body = this.cardBody
    if (!body) return
    const atBottom = (body.scrollHeight - body.scrollTop - body.clientHeight) < NEAR_BOTTOM_PX
    sessionStorage.setItem(SCROLL_KEY, JSON.stringify({ atBottom, scrollTop: body.scrollTop }))
  }

  restoreScroll() {
    const body = this.cardBody
    if (!body) return
    const raw = sessionStorage.getItem(SCROLL_KEY)
    requestAnimationFrame(() => {
      if (raw) {
        // Post-refresh: respect saved state.
        sessionStorage.removeItem(SCROLL_KEY)
        const { atBottom, scrollTop } = JSON.parse(raw)
        body.scrollTop = atBottom ? body.scrollHeight : scrollTop
      } else {
        // Initial page load: scroll to bottom so the user sees the most
        // recent turn (chat convention). They can scroll up to read history.
        body.scrollTop = body.scrollHeight
      }
    })
  }
}
