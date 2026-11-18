// Webhukhs admin - copy buttons, the body viewer tabs and the index auto-refresh. No framework, the CSP only allows this file.

const flash = (element) => {
  element.classList.add("copied");
  setTimeout(() => element.classList.remove("copied"), 1200);
};

const tabsOf = (tablist) => Array.from(tablist.querySelectorAll("[role=tab]"));

const selectTab = (tab) => {
  for (const other of tabsOf(tab.closest("[role=tablist]"))) {
    const selected = other === tab;
    other.setAttribute("aria-selected", String(selected));
    other.tabIndex = selected ? 0 : -1;
    document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
  }
};

document.addEventListener("click", (event) => {
  const copy = event.target.closest(".btn-copy");
  if (copy) {
    navigator.clipboard.writeText(copy.dataset.copy).then(() => flash(copy));
    return;
  }

  const tab = event.target.closest("[role=tab]");
  if (tab) {
    selectTab(tab);
    return;
  }

  const copyPanel = event.target.closest(".btn-copy-panel");
  if (copyPanel) {
    const panel = copyPanel.closest(".tabs").querySelector("[role=tabpanel]:not([hidden])");
    navigator.clipboard.writeText(panel.querySelector("code").textContent).then(() => flash(copyPanel));
    return;
  }

  // A click anywhere on a listing row opens the webhook - except on something that is clickable in
  // its own right, which is the id link and the retry button. The row used to be covered by the id
  // link's ::after instead, which meant the button underneath it could not be pressed at all.
  const row = event.target.closest("tr[data-href]");
  if (row && !event.target.closest("a, button, input, label, select")) {
    if (event.metaKey || event.ctrlKey) {
      window.open(row.dataset.href, "_blank", "noopener");
    } else {
      location.assign(row.dataset.href);
    }
  }
});

// Retrying from the listing answers with the row alone, which goes in place of the one that was
// there - the status and the button come back changed, and the page stays where it is. Without
// JavaScript the same form submits normally and lands on the webhook, see the controller.
document.addEventListener("submit", async (event) => {
  const form = event.target.closest("tr[data-href] form.button_to");
  if (!form) return;

  event.preventDefault();
  const row = form.closest("tr");
  const button = form.querySelector("button");
  button.disabled = true;

  try {
    const response = await fetch(form.action, {
      method: "POST",
      body: new FormData(form),
      headers: {Accept: "text/html", "X-Webhukhs-Row": "1"}
    });
    // Parsed inside a tbody, not with DOMParser: parsing a bare <tr> as a document throws the row
    // away, since it is not in a table there
    const tbody = document.createElement("tbody");
    tbody.innerHTML = await response.text();
    const fresh = tbody.firstElementChild;
    if (response.ok && fresh) {
      row.replaceWith(fresh);
      return;
    }
  } catch (error) {
    // Left to the finally below - the button comes back and the row is as it was, so it can be pressed again
  }
  button.disabled = false;
});

// Arrow keys move between tabs, as the ARIA tabs pattern expects
document.addEventListener("keydown", (event) => {
  const tab = event.target.closest("[role=tab]");
  if (!tab || !["ArrowLeft", "ArrowRight"].includes(event.key)) return;

  const tabs = tabsOf(tab.closest("[role=tablist]"));
  const step = event.key === "ArrowRight" ? 1 : -1;
  const next = tabs[(tabs.indexOf(tab) + step + tabs.length) % tabs.length];
  selectTab(next);
  next.focus();
});

// Auto-refresh of the index. Polls rather than holding an EventSource open: a forgotten tab with
// an SSE stream pins a server thread forever, a forgotten tab polling costs one request now and then.
const POLL_INTERVAL_MS = 5000;
const POLL_STORAGE_KEY = "webhukhs.autoRefresh";

const autoRefresh = document.getElementById("auto-refresh");
let pollTimer = null;
let pollAbort = null;

const stopPolling = () => {
  clearTimeout(pollTimer);
  pollTimer = null;
  pollAbort?.abort();
  pollAbort = null;
};

const schedulePoll = () => {
  pollTimer = setTimeout(refreshListing, POLL_INTERVAL_MS);
};

const refreshListing = async () => {
  // Nobody is looking, so check again later instead
  if (document.hidden) return schedulePoll();

  const abort = (pollAbort = new AbortController());
  try {
    const response = await fetch(location.href, {signal: abort.signal, headers: {Accept: "text/html"}});
    const html = await response.text();
    // Swapped synchronously after the last await, so a switch turned off meanwhile has aborted us
    const fresh = new DOMParser().parseFromString(html, "text/html").getElementById("received-webhooks");
    if (response.ok && fresh) document.getElementById("received-webhooks").replaceWith(fresh);
  } catch (error) {
    if (abort.signal.aborted) return;
  }
  if (pollAbort === abort) schedulePoll();
};

const rememberAutoRefresh = (enabled) => {
  try {
    localStorage.setItem(POLL_STORAGE_KEY, enabled ? "1" : "");
  } catch {}
};

const recallAutoRefresh = () => {
  try {
    return localStorage.getItem(POLL_STORAGE_KEY) === "1";
  } catch {
    return false;
  }
};

if (autoRefresh) {
  autoRefresh.checked = recallAutoRefresh();
  if (autoRefresh.checked) schedulePoll();

  autoRefresh.addEventListener("change", () => {
    stopPolling();
    rememberAutoRefresh(autoRefresh.checked);
    if (autoRefresh.checked) refreshListing();
  });
}
