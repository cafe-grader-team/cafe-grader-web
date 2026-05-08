import { Controller } from "@hotwired/stimulus"

// Polls the refresh endpoint while a viva turn is processing.
//
// Previously this used outerHTML to replace the entire #viva-session
// element on each tick. That destroys the browser's scroll anchor and
// can cause window.scrollY to reset to 0 between the swap and the
// new controller's connect. We now parse the response, find the
// matching #viva-session in it, and replace just the *inner* content
// — preserving the outer element (and all browser scroll bookkeeping
// it carries) entirely.
//
// The chat .card-body inside still gets replaced, so its internal
// scrollTop is captured and re-applied in the same synchronous JS turn.
//
// Data attributes:
//   data-viva-session-pending-value      (Boolean) whether a turn is currently processing
//   data-viva-session-refresh-url-value  (String)  URL that returns the replacement partial
//   data-viva-session-interval-ms-value  (Number)  poll interval in ms

const NEAR_BOTTOM_PX = 50

export default class extends Controller {
  static values = {
    pending:    Boolean,
    refreshUrl: String,
    intervalMs: { type: Number, default: 3000 }
  }

  connect() {
    console.log('[viva-session] controller connected; pending=', this.pendingValue)
    // Initial page load: scroll the chat to bottom (latest turn).
    const body = this.cardBody
    if (body) body.scrollTop = body.scrollHeight

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
    // Snapshot only the chat body's internal scroll. Window scroll is
    // preserved naturally since we never replace this.element itself —
    // only its children — so the browser's scroll anchor stays stable.
    const body = this.cardBody
    const beforeBodyTop = body ? body.scrollTop : 0
    const wasAtBottom = body
      ? (body.scrollHeight - body.scrollTop - body.clientHeight) < NEAR_BOTTOM_PX
      : false

    try {
      const res = await fetch(this.refreshUrlValue, { headers: { Accept: "text/html" } })
      if (!res.ok) return this.scheduleRefresh()
      const html = await res.text()

      // Parse the response and pull out the new #viva-session, then
      // copy ITS children into our existing element. This keeps our
      // outer element (this.element) in place — same DOM node, same
      // scroll anchor, same Stimulus controller instance.
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, 'text/html')
      const incoming = doc.getElementById('viva-session')
      if (!incoming) {
        console.warn('[viva-session] refresh response had no #viva-session element')
        return this.scheduleRefresh()
      }

      // Sync the data attributes so the controller picks up the new
      // pending state for its next-poll decision.
      for (const attr of incoming.getAttributeNames()) {
        if (attr.startsWith('data-viva-session-')) {
          this.element.setAttribute(attr, incoming.getAttribute(attr))
        }
      }

      // Swap inner content. Same JS turn — no microtask between this
      // and the body.scrollTop restore below.
      this.element.innerHTML = incoming.innerHTML

      // Restore chat body scroll synchronously.
      const newBody = this.cardBody
      if (newBody) {
        newBody.scrollTop = wasAtBottom ? newBody.scrollHeight : beforeBodyTop
      }

      console.log('[viva-session] refresh applied; pendingNow=%s body.scrollTop=%d',
                  this.pendingValue, newBody ? newBody.scrollTop : -1)

      if (this.pendingValue) {
        this.scheduleRefresh()
      }
    } catch (e) {
      console.warn('[viva-session] refresh failed', e)
      this.scheduleRefresh()
    }
  }

  get cardBody() {
    return this.element.querySelector('.card-body')
  }
}
