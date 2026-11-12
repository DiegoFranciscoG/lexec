// LiveView client, page-load progress bar and the cookie notice.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
})

const accent = getComputedStyle(document.documentElement).getPropertyValue("--color-accent").trim()
topbar.config({barColors: {0: accent || "currentColor"}, shadowColor: "transparent"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// The cookie notice is informative (only a strictly necessary session cookie exists).
// Its dismissal is remembered in localStorage, never in another cookie.
const COOKIE_ACK = "lexec:cookie-note"
const hideCookieNote = () => {
  const note = document.getElementById("cookie-note")
  if (note) note.hidden = true
}
const safeGet = key => { try { return localStorage.getItem(key) } catch (_e) { return null } }
const safeSet = (key, value) => { try { localStorage.setItem(key, value) } catch (_e) { /* private mode */ } }

const syncCookieNote = () => { if (safeGet(COOKIE_ACK) === "1") hideCookieNote() }
document.addEventListener("click", event => {
  if (event.target.closest("[data-cookie-ack]")) {
    safeSet(COOKIE_ACK, "1")
    hideCookieNote()
  }
})
syncCookieNote()
window.addEventListener("phx:page-loading-stop", syncCookieNote)

liveSocket.connect()
window.liveSocket = liveSocket
