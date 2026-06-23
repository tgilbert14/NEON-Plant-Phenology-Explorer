/* =========================================================================
   app.js — count-up stat counters, the loading overlay, popover dismissal,
   and the Shiny custom-message handlers for the Plant Phenology Explorer.
   (Mammal-app leftovers — guided tour, dossier-card export, confetti — removed.)
   ========================================================================= */

// ---- animated count-up for the hero stat band ----------------------------
function animateCount(el) {
  if (el.dataset.animated === "1") return;
  el.dataset.animated = "1";
  // A freshly-rendered hero counter means a site just finished loading — the
  // most reliable signal to dismiss the loading overlay.
  if (typeof smtLoadDone === "function") smtLoadDone();
  const target = parseFloat(el.getAttribute("data-target")) || 0;
  const suffix = el.dataset.suffix || "";
  const isFloat = !Number.isInteger(target);
  const fmt = (v) => (isFloat ? v.toFixed(1) : Math.round(v).toLocaleString()) + suffix;
  if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    el.textContent = fmt(target); return;
  }
  const dur = 900, start = performance.now();
  function tick(now) {
    const t = Math.min(1, (now - start) / dur);
    const eased = 1 - Math.pow(1 - t, 3);
    el.textContent = fmt(target * eased);
    if (t < 1) requestAnimationFrame(tick); else el.textContent = fmt(target);
  }
  requestAnimationFrame(tick);
}
function runCounters() { document.querySelectorAll(".count-up").forEach(animateCount); }

const heroObserver = new MutationObserver(() => runCounters());
document.addEventListener("DOMContentLoaded", function () {
  heroObserver.observe(document.body, { childList: true, subtree: true });
  runCounters();
});

// ---- loading overlay (opaque, indeterminate) -----------------------------
// A site load is one blocking call whose duration we can't know, so show an
// INDETERMINATE animated bar on an opaque backdrop — no fake %, no half-drawn
// data peeking through; it just spins until the server signals done.
var smtSafetyTimer = null;
function smtLoadStart(label) {
  var ov = document.getElementById("loadOverlay");
  if (!ov) return;
  var siteText = label || "";
  if (!siteText) {
    var sel = document.getElementById("site");
    if (sel && sel.options && sel.selectedIndex >= 0) siteText = sel.options[sel.selectedIndex].text;
  }
  var siteEl = document.getElementById("loadSite");
  if (siteEl) siteEl.textContent = siteText;
  ov.style.display = "flex";
  if (navigator.vibrate) { try { navigator.vibrate(12); } catch (e) {} }
  clearTimeout(smtSafetyTimer);
  smtSafetyTimer = setTimeout(function () {  // safety net so it can never stick
    var note = document.querySelector(".load-note");
    if (note) note.textContent = "Still working — a large site or a slow NEON Portal can take a bit. You can close this and try again.";
    setTimeout(smtLoadDone, 5000);
  }, 90000);
}
function smtLoadDone() {
  clearTimeout(smtSafetyTimer);
  var ov = document.getElementById("loadOverlay");
  if (ov) ov.style.display = "none";
}

// ---- dismiss any open info popover (click-outside + Esc) ------------------
function smtClosePopovers() {
  document.querySelectorAll(".popover").forEach(function (pop) {
    var trig = pop.id ? document.querySelector('[aria-describedby="' + pop.id + '"]') : null;
    if (trig && window.bootstrap && bootstrap.Popover) {
      var inst = bootstrap.Popover.getInstance(trig);
      if (inst) { inst.hide(); return; }
    }
    pop.remove();
  });
}
document.addEventListener("click", function (e) {
  if (e.target.closest(".popover") || e.target.closest(".info-dot") ||
      e.target.closest("bslib-popover")) return;
  if (document.querySelector(".popover")) smtClosePopovers();
});
document.addEventListener("keydown", function (e) { if (e.key === "Escape") smtClosePopovers(); });

// ---- Shiny custom message handlers ---------------------------------------
document.addEventListener("DOMContentLoaded", function () {
  if (!window.Shiny) return;
  Shiny.addCustomMessageHandler("countUp", function () { setTimeout(runCounters, 60); });
  Shiny.addCustomMessageHandler("loadDone", function () { smtLoadDone(); });
  // server-triggered overlay (e.g. a click on the national picker map / search)
  Shiny.addCustomMessageHandler("smtLoadStart", function (msg) { smtLoadStart(msg && msg.label); });
  // current site code, used to stamp export filenames (pincards.js)
  Shiny.addCustomMessageHandler("pheSite", function (msg) { window.__pheSite = (msg && msg.site) || ""; });
  // "Change site" re-shows the picker-map splash. The page_fillable layout (and
  // the relocated select panel) needs a moment to settle its width before
  // Leaflet measures, or the national map captures a half-width and paints
  // narrow. Dispatch resize across several frames to catch the settled layout.
  Shiny.addCustomMessageHandler("kickMaps", function () {
    var kick = function () { try { window.dispatchEvent(new Event("resize")); } catch (e) {} };
    requestAnimationFrame(kick);
    [80, 250, 500, 900].forEach(function (t) { setTimeout(kick, t); });
  });
});

// ---- mascot celebration: the sprout hops up + fades on a special moment ----
// This app has no confetti (the mammal-app's rarity confetti was removed), so
// mascotCheer ships ready-to-wire: call mascotCheer(true) from any future
// celebration hook and the loader sprout will pop up and fade.
function mascotCheer(big) {
  try {
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    var src = document.querySelector("#loadOverlay .mascot");
    if (!src) return;
    var wrap = document.createElement("div");
    wrap.className = "mascot-cheer";
    wrap.appendChild(src.cloneNode(true));
    document.body.appendChild(wrap);
    setTimeout(function () { if (wrap.parentNode) wrap.parentNode.removeChild(wrap); }, 1700);
  } catch (e) {}
}

// ---- first-visit: the splash mascot waves hello once (localStorage-gated) ----
document.addEventListener("DOMContentLoaded", function () {
  try {
    if (localStorage.getItem("smtMascotSeen") === "1") return;
    var g = document.querySelector(".splash-guide");
    if (g) {
      g.classList.add("wave");
      localStorage.setItem("smtMascotSeen", "1");
      setTimeout(function () { g.classList.remove("wave"); }, 3300);
    }
  } catch (e) {}
});

// Re-fit any Leaflet map the moment its tab becomes visible (hidden-init blank fix).
document.addEventListener("shown.bs.tab", function () {
  setTimeout(function () { try { window.dispatchEvent(new Event("resize")); } catch (e) {} }, 60);
});
