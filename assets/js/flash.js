// Flash lines close on a tap and leave on their own after a few seconds.
export function initFlash() {
  for (const el of document.querySelectorAll("[data-flash]")) {
    const close = () => el.remove()
    el.addEventListener("click", close)
    setTimeout(close, 7000)
  }
}
