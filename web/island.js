const popup = document.getElementById("popup");
const popupApp = popup.querySelector(".popup-app");
const popupTitle = popup.querySelector(".popup-title");
const popupSummary = popup.querySelector(".popup-summary");

const APP_NAME = { cursor: "Cursor", codex: "Codex", "grok-bot": "Grok Bot", mochi: "小猫" };
const FACE_SRC = {
  cursor: {
    wake: "pets/cursor-wake.svg",
    work: "pets/cursor-work.svg",
    wait: "pets/cursor-wait.svg",
    done: "pets/cursor-done.svg",
  },
  "grok-bot": {
    wake: "pets/grok-wake.svg",
    work: "pets/grok-work.svg",
    wait: "pets/grok-wait.svg",
    done: "pets/grok-done.svg",
  },
  mochi: {
    wake: "pets/kitten-wake.svg",
    work: "pets/kitten-work.svg",
    wait: "pets/kitten-wait.svg",
    done: "pets/kitten-done.svg",
  },
};
const STATUS_MARK = {
  running: "status/spinner.gif?v=41",
  wait: "status/warning.gif?v=41",
  done: "status/check.gif?v=41",
  fail: "status/cross.gif?v=41",
};
const STATUS_LABEL = { running: "Running", wait: "Waiting", done: "Done", fail: "Failed" };
const KIND_LABEL = { choice: "Choice", plan: "Plan", mode: "Mode", permission: "Permission" };
const PALETTE = ["#ffffff", "#fff6e8", "#241f1c", "#e97868", "#efd36a", "#7dcb8d", "#3d6ea8", "#f4b6c2"];
const SOUND_PICKS = [
  { id: "boop", label: "Boop" },
  { id: "chirp", label: "Chirp" },
  { id: "mew", label: "Mew" },
  { id: "pop", label: "Pop" },
  { id: "twinkle", label: "Twinkle" },
];
const SOUND_IDS = new Set(SOUND_PICKS.map((item) => item.id));
const PET_LOOKS = [{ id: "mochi", label: "Mochi", preview: "pets/happy.png" }];
const LOOK_IDS = new Set(PET_LOOKS.map((item) => item.id));
const LOOK_SLOT_COUNT = 16;
const HEX = /^#[0-9a-fA-F]{6}$/;
const REFRESH_MS = 5000;

let currentSound = "boop";
let currentLook = "mochi";
let audioCtx = null;
let cursorLinked = false;
let taskPushEpoch = 0;
let saveTimer = 0;
let slotRecords = [];
let liveTasks = [];
let selectedId = "";
let popupOpen = false;
let waitIDs = new Set();
let chromeBox = { left: 0, top: 0, right: 56, bottom: 200, w: 56, h: 200, x: 0, y: 0 };
let chromeSlots = {};
let chromeAdd = { left: 0, top: 0, w: 36, h: 36 };
let chromeSettings = { left: 0, top: 0, w: 36, h: 36 };
let chromeMeta = {
  material: "glassEffect.clear",
  menuCount: 3,
  capsuleW: 56,
  slotW: 56,
  slotH: 36,
  faceW: 36,
  faceH: 36,
  slotGap: 8,
  addW: 36,
  gearW: 36,
  addSymbol: "plus",
  gearSymbol: "gearshape",
  caret: 8,
  selected: "",
};
const choiceOverlay = new Map();
const colors = {
  fill: "#ffffff",
  text: "#241f1c",
  stroke: "#2c2926",
  card_fill: "#111111",
  card_stroke: "#2c2926",
};
const stored = {
  dx: 0,
  dy: 0,
  bubble_dx: 0,
  bubble_dy: 0,
  pet_scale: 1,
  bubble_scale: 1,
};

function islandMessage(payload) {
  const handler = window.webkit?.messageHandlers?.island;
  if (handler) handler.postMessage(payload);
}

const pendingCalls = new Map();
let callSeq = 0;

function islandCall(action, extra = {}) {
  return new Promise((resolve, reject) => {
    const rpc = String(++callSeq);
    const timer = setTimeout(() => {
      if (!pendingCalls.has(rpc)) return;
      pendingCalls.delete(rpc);
      reject(new Error("request failed"));
    }, 8000);
    pendingCalls.set(rpc, { resolve, reject, timer });
    islandMessage({ ...extra, action, rpc });
  });
}

window.mochiReply = (rpc, payload) => {
  const item = pendingCalls.get(String(rpc));
  if (!item) return;
  clearTimeout(item.timer);
  pendingCalls.delete(String(rpc));
  item.resolve(payload);
};

window.__mochiClearChoices = () => {
  choiceOverlay.clear();
};

window.__mochiSlots = () =>
  slotRecords.map((slot) => ({
    id: slot.id,
    source: slot.source,
    app: APP_NAME[slot.source] || "Cursor",
    selected: slot.id === selectedId,
    face: faceFile(slot),
    popupApp: popupApp.textContent || "",
  }));

window.__capsuleChrome = () => ({
  ...chromeMeta,
  capsule: chromeBox,
  slots: chromeSlots,
  add: chromeAdd,
  settings: chromeSettings,
  dock: document.body.dataset.dock === "left" ? "left" : "right",
  selected: selectedId,
  popupOpen,
});

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function taskSource(task) {
  const value = String((task && task.source) || "").trim().toLowerCase();
  if (value === "codex") return "codex";
  if (value === "grok-bot" || value === "grok" || value === "grokbot" || value === "grok bot") return "grok-bot";
  if (value === "mochi" || value === "cat" || value === "小猫") return "mochi";
  return "cursor";
}

function faceSkin(source) {
  if (source === "grok-bot" || source === "mochi" || source === "codex") return source;
  return "cursor";
}

function faceState(status) {
  if (status === "running") return "work";
  if (status === "wait" || status === "fail") return "wait";
  if (status === "done") return "done";
  return "wake";
}

function faceFile(slot) {
  const source = faceSkin(slot.source);
  const task = liveTask(slot.id);
  const state = faceState(task && task.status);
  const pack = FACE_SRC[source];
  return pack ? pack[state] || pack.wake : "";
}

function normalizeSlot(raw) {
  const id = String((raw && raw.id) || "").trim();
  if (!id) return null;
  const source = taskSource(raw);
  return {
    id,
    source,
    title: String((raw && raw.title) || "").trim() || "New chat",
    skin: faceSkin(source),
    created: Number(raw && raw.created) || 0,
  };
}

function ensureSlotFromTask(task) {
  const id = String((task && task.id) || "");
  if (!id || slotRecords.some((slot) => slot.id === id)) return;
  const source = taskSource(task);
  slotRecords.push({
    id,
    source,
    title: String(task.title || "").trim() || "New chat",
    skin: faceSkin(source),
    created: Number(task.updated) || 0,
  });
}

function liveTask(id) {
  return liveTasks.find((task) => String(task.id || "") === id) || null;
}

function taskOptions(task) {
  if (!task || task.status !== "wait") return [];
  const list = Array.isArray(task.options) ? task.options.filter((item) => item && item.label) : [];
  if (list.length) return list;
  if (task.kind === "permission") {
    return [
      { id: "allow", label: "Allow" },
      { id: "deny", label: "Deny" },
    ];
  }
  return [];
}

function applySnapshot(tasks, state) {
  const list = Array.isArray(tasks) ? tasks : [];
  if (state && Array.isArray(state.slots)) {
    slotRecords = state.slots.map(normalizeSlot).filter(Boolean);
  }
  if (state && (state.dock === "left" || state.dock === "right")) {
    setDock(state.dock, false);
  }
  if (state && typeof state.selected === "string" && state.selected) {
    selectedId = state.selected;
  }
  liveTasks = list;
  list.forEach(ensureSlotFromTask);
  const fresh = list.filter((task) => task.status === "wait" && !waitIDs.has(String(task.id || "")));
  if (fresh.length) {
    selectedId = String(fresh[fresh.length - 1].id || "");
    popupOpen = true;
  }
  waitIDs = new Set(list.filter((task) => task.status === "wait").map((task) => String(task.id || "")));
  for (const id of choiceOverlay.keys()) {
    const task = liveTask(id);
    if (!task || task.status !== "wait") choiceOverlay.delete(id);
  }
  if (!slotRecords.some((slot) => slot.id === selectedId)) {
    selectedId = slotRecords[0] ? slotRecords[0].id : "";
  }
  paint();
}

window.pushTasks = (tasks, state) => {
  taskPushEpoch += 1;
  applySnapshot(tasks, state || {});
};

function boxRect(box, fallbackW, fallbackH) {
  if (!box) return { left: 0, top: 0, right: fallbackW, bottom: fallbackH, w: fallbackW, h: fallbackH };
  const left = Number(box.left ?? box.x) || 0;
  const top = Number(box.top ?? box.y) || 0;
  const width = Number(box.w) || fallbackW;
  const height = Number(box.h) || fallbackH;
  return { left, top, right: left + width, bottom: top + height, w: width, h: height };
}

function summaryHTML(slot, task) {
  const picked = choiceOverlay.get(slot.id);
  const view = picked && task && task.status === "wait"
    ? { ...task, status: "running", title: picked, options: [], prompt: "", detail: "" }
    : task;
  const bits = [];
  const status = view && STATUS_MARK[view.status] ? view.status : "";
  if (status) {
    bits.push(
      `<div class="summary-status">${STATUS_MARK[status] ? `<img class="speech-mark" src="${STATUS_MARK[status]}" alt="">` : ""}<span>${STATUS_LABEL[status] || ""}</span></div>`
    );
  }
  const kind = view ? KIND_LABEL[view.kind] || "" : "";
  if (kind) bits.push(`<p class="speech-kind">${escapeHtml(kind)}</p>`);
  const prompt = String((view && view.prompt) || "").trim();
  const extra = String((view && view.detail) || "").trim();
  const title = String((view && view.title) || slot.title || "").trim();
  if (prompt) bits.push(`<p class="speech-prompt">${escapeHtml(prompt)}</p>`);
  if (extra && extra !== prompt && extra !== title) bits.push(`<p class="speech-extra">${escapeHtml(extra)}</p>`);
  if (!prompt && !extra) bits.push('<p class="summary-empty">No summary yet</p>');
  const options = picked ? [] : taskOptions(view || {});
  if (options.length) {
    bits.push(
      `<div class="speech-options">${options
        .map(
          (item) =>
            `<button type="button" class="speech-option" data-option-id="${escapeHtml(item.id)}" data-label="${escapeHtml(item.label)}">${escapeHtml(item.label)}</button>`
        )
        .join("")}</div>`
    );
  }
  bits.push('<p class="speech-choice-error hidden"></p>');
  return { title: String((view && view.title) || slot.title || "New chat"), html: bits.join("") };
}

function renderPopup() {
  const slot = slotRecords.find((item) => item.id === selectedId);
  if (!slot) {
    popup.hidden = true;
    return;
  }
  const task = liveTask(slot.id);
  const view = summaryHTML(slot, task);
  popup.hidden = !popupOpen;
  popup.dataset.taskId = slot.id;
  popup.dataset.source = (task && taskSource(task)) || slot.source;
  popup.dataset.kind = (task && task.kind) || "";
  popup.dataset.requestId = (task && task.request_id) || "";
  popup.dataset.questionId = (task && task.question_id) || "";
  popupApp.textContent = APP_NAME[popup.dataset.source] || "Cursor";
  popupTitle.textContent = view.title;
  popupSummary.innerHTML = view.html;
}

function paint() {
  renderPopup();
  placeFloating();
  requestAnimationFrame(reportHotRects);
}

function placeFloating() {
  const dock = document.body.dataset.dock === "left" ? "left" : "right";
  const capsuleBox = boxRect(chromeBox, 56, 200);
  const gap = 8;
  if (!popup.hidden) {
    const width = 200;
    const slotBox = boxRect(chromeSlots[selectedId], 56, 36);
    const height = popup.offsetHeight || 120;
    const anchorMid = chromeSlots[selectedId] ? slotBox.top + slotBox.h / 2 : capsuleBox.top + capsuleBox.h / 2;
    let left = dock === "right" ? capsuleBox.left - gap - width : capsuleBox.right + gap;
    let top = anchorMid - height / 2;
    top = clamp(top, 8, Math.max(8, window.innerHeight - 8 - height));
    left = clamp(left, 8, Math.max(8, window.innerWidth - 8 - width));
    popup.style.left = `${left}px`;
    popup.style.top = `${top}px`;
  }
}

function glassShape(el) {
  const box = el.getBoundingClientRect();
  if (box.width < 2 || box.height < 2) return null;
  const style = getComputedStyle(el);
  if (style.display === "none" || style.visibility === "hidden") return null;
  return {
    x: box.left,
    y: box.top,
    w: box.width,
    h: box.height,
    r: parseFloat(style.borderTopLeftRadius) || 16,
    a: 1,
    kind: "card",
    text: "",
    cover: false,
  };
}

function reportHotRects() {
  const nodes = [];
  if (!popup.hidden) nodes.push(popup);
  const rects = nodes
    .map((el) => {
      const box = el.getBoundingClientRect();
      return { x: box.left, y: box.top, w: box.width, h: box.height };
    })
    .filter((rect) => rect.w > 1 && rect.h > 1);
  islandMessage({ action: "hotRects", rects: JSON.stringify(rects) });
  islandMessage({ action: "glass", rects: JSON.stringify([]) });
}

function setDock(side, persist) {
  const next = side === "left" ? "left" : "right";
  document.body.dataset.dock = next;
  placeFloating();
  if (persist) persistPrefs();
  requestAnimationFrame(reportHotRects);
}

function setSettingsOpen() {}

window.applyCapsuleChrome = function applyCapsuleChrome(info) {
  if (!info || typeof info !== "object") return;
  if (info.dock === "left" || info.dock === "right") setDock(info.dock, false);
  chromeBox = boxRect(info.capsule, 56, Number(info.capsule && info.capsule.h) || 200);
  chromeSlots = info.slots && typeof info.slots === "object" ? info.slots : {};
  chromeAdd = boxRect(info.add, 36, 36);
  chromeSettings = boxRect(info.settings, 36, 36);
  chromeMeta = {
    material: info.material || chromeMeta.material,
    menuCount: Number(info.menuCount) || 3,
    capsuleW: Number(info.capsuleW) || 56,
    slotW: Number(info.slotW) || 56,
    slotH: Number(info.slotH) || 36,
    faceW: Number(info.faceW) || 36,
    faceH: Number(info.faceH) || 36,
    slotGap: Number(info.slotGap) || 8,
    addW: Number(info.addW) || 36,
    gearW: Number(info.gearW) || 36,
    addSymbol: info.addSymbol || "plus",
    gearSymbol: info.gearSymbol || "gearshape",
    caret: Number(info.caret) || 8,
    selected: info.selected || selectedId,
  };
  if (typeof info.selected === "string" && info.selected) selectedId = info.selected;
  placeFloating();
  requestAnimationFrame(reportHotRects);
};

window.applyCapsuleEvent = function applyCapsuleEvent(event) {
  if (!event || typeof event !== "object") return;
  if (event.kind === "select") {
    selectedId = event.id || selectedId;
    popupOpen = event.open !== false;
    paint();
    return;
  }
  if (event.kind === "settings") {
    return;
  }
  if (event.kind === "created") {
    if (Array.isArray(event.slots)) {
      slotRecords = event.slots.map(normalizeSlot).filter(Boolean);
    }
    selectedId = event.selected || selectedId;
    popupOpen = true;
    paint();
  }
};

function currentPrefs() {
  return {
    dx: stored.dx,
    dy: stored.dy,
    bubble_dx: stored.bubble_dx,
    bubble_dy: stored.bubble_dy,
    fill: colors.fill,
    text: colors.text,
    stroke: colors.stroke,
    card_fill: colors.card_fill,
    card_stroke: colors.card_stroke,
    sound: currentSound,
    look: currentLook,
    pet_scale: stored.pet_scale,
    bubble_scale: stored.bubble_scale,
    dock: document.body.dataset.dock === "left" ? "left" : "right",
    selected: selectedId,
  };
}

function persistPrefs() {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    islandMessage({ action: "savePrefs", ...currentPrefs() });
  }, 180);
}

function normalizeHex(value, fallback) {
  const raw = String(value || "").trim();
  if (HEX.test(raw)) return raw.toLowerCase();
  if (/^[0-9a-fA-F]{6}$/.test(raw)) return `#${raw.toLowerCase()}`;
  return fallback;
}

function applyBubbleColors(fill, text, stroke) {
  colors.fill = normalizeHex(fill, "#ffffff");
  colors.text = normalizeHex(text, "#241f1c");
  colors.stroke = normalizeHex(stroke, "#2c2926");
  document.documentElement.style.setProperty("--bubble-fill", colors.fill);
  document.documentElement.style.setProperty("--bubble-text", colors.text);
  document.documentElement.style.setProperty("--bubble-stroke", colors.stroke);
}

function applyCardColors(fill, stroke) {
  colors.card_fill = normalizeHex(fill, "#111111");
  colors.card_stroke = normalizeHex(stroke, "#2c2926");
  document.documentElement.style.setProperty("--card-fill", colors.card_fill);
  document.documentElement.style.setProperty("--card-stroke", colors.card_stroke);
}

window.applyPrefs = function applyPrefs(prefs) {
  stored.dx = Number(prefs.dx) || 0;
  stored.dy = Number(prefs.dy) || 0;
  stored.bubble_dx = Number(prefs.bubble_dx) || 0;
  stored.bubble_dy = Number(prefs.bubble_dy) || 0;
  stored.pet_scale = Number(prefs.pet_scale) || 1;
  stored.bubble_scale = Number(prefs.bubble_scale) || 1;
  applyBubbleColors(prefs.fill, prefs.text, prefs.stroke);
  applyCardColors(prefs.card_fill, prefs.card_stroke);
  setCurrentSound(prefs.sound || "boop", false);
  setCurrentLook(prefs.look || "mochi");
  if (prefs.dock === "left" || prefs.dock === "right") setDock(prefs.dock, false);
};

window.applyScreenLayout = function applyScreenLayout() {
  placeFloating();
  reportHotRects();
};

function fillSwatches() {
  document.querySelectorAll(".swatches").forEach((row) => {
    row.innerHTML = PALETTE.map(
      (color) => `<button type="button" data-color="${color}" style="background:${color}" aria-label="${color}"></button>`
    ).join("");
  });
}

function fillSoundPicks() {
  document.getElementById("sound-picks").innerHTML = SOUND_PICKS.map(
    (item) => `<button type="button" data-sound="${item.id}" class="${item.id === currentSound ? "active" : ""}">${item.label}</button>`
  ).join("");
}

function fillLookPicks() {
  const real = PET_LOOKS.map(
    (item) =>
      `<button type="button" data-look="${item.id}" class="${item.id === currentLook ? "active" : ""}" aria-label="${item.label}"><img src="${item.preview}" alt="" /></button>`
  ).join("");
  const empty = Array.from({ length: Math.max(0, LOOK_SLOT_COUNT - PET_LOOKS.length) }, () =>
    `<button type="button" class="placeholder" aria-label="Coming soon">?</button>`
  ).join("");
  document.getElementById("look-picks").innerHTML = real + empty;
}

function setCurrentLook(id) {
  currentLook = LOOK_IDS.has(id) ? id : "mochi";
  document.querySelectorAll(".look-picks button").forEach((button) => {
    button.classList.toggle("active", button.dataset.look === currentLook);
  });
}

function setCurrentSound(id, preview) {
  currentSound = SOUND_IDS.has(id) ? id : "boop";
  document.querySelectorAll(".sound-picks button").forEach((button) => {
    button.classList.toggle("active", button.dataset.sound === currentSound);
  });
  if (preview) playClickSound();
}

function audioContext() {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return null;
  if (!audioCtx) audioCtx = new AC();
  if (audioCtx.state === "suspended") audioCtx.resume();
  return audioCtx;
}

function tone(ctx, type, freq, start, dur, gain, slideTo) {
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, start);
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(Math.max(40, slideTo), start + dur);
  amp.gain.setValueAtTime(0.0001, start);
  amp.gain.exponentialRampToValueAtTime(gain, start + 0.012);
  amp.gain.exponentialRampToValueAtTime(0.0001, start + dur);
  osc.connect(amp);
  amp.connect(ctx.destination);
  osc.start(start);
  osc.stop(start + dur + 0.02);
}

function playClickSound() {
  try {
    const ctx = audioContext();
    if (!ctx) return;
    const t = ctx.currentTime;
    if (currentSound === "chirp") {
      tone(ctx, "triangle", 988, t, 0.07, 0.16);
      tone(ctx, "triangle", 1319, t + 0.07, 0.09, 0.14);
      return;
    }
    if (currentSound === "mew") {
      tone(ctx, "sine", 620, t, 0.18, 0.15, 980);
      tone(ctx, "sine", 980, t + 0.12, 0.16, 0.1, 540);
      return;
    }
    if (currentSound === "pop") {
      tone(ctx, "sine", 420, t, 0.09, 0.14, 180);
      return;
    }
    if (currentSound === "twinkle") {
      tone(ctx, "sine", 1319, t, 0.16, 0.12);
      tone(ctx, "sine", 1976, t + 0.04, 0.18, 0.08);
      return;
    }
    tone(ctx, "sine", 880, t, 0.12, 0.16, 420);
  } catch (error) {
    return;
  }
}

function openAgentWindow() {
  return islandCall("openAgent", {
    source: popup.dataset.source || "cursor",
    id: popup.dataset.taskId || "",
  });
}

function showChoiceError(message) {
  const error = popupSummary.querySelector(".speech-choice-error");
  if (!error) return;
  error.textContent = message;
  error.classList.remove("hidden");
}

async function chooseTaskOption(button) {
  const started = performance.now();
  const optionId = button.dataset.optionId || "";
  const label = button.dataset.label || button.textContent || "";
  const id = popup.dataset.taskId || "";
  choiceOverlay.set(id, label);
  renderPopup();
  if (window.__mochiMeasure) {
    window.__mochiMeasure.choiceBubbleMs = performance.now() - started;
    window.__mochiMeasure.choiceBubbleDone = true;
  }
  try {
    const result = await islandCall("cursorChoice", {
      id,
      kind: popup.dataset.kind || "",
      request_id: popup.dataset.requestId || "",
      question_id: popup.dataset.questionId || "",
      option_id: optionId,
      label,
    });
    if (window.__mochiMeasure) {
      window.__mochiMeasure.choiceReplyMs = performance.now() - started;
      window.__mochiMeasure.choiceReplyDone = true;
    }
    if (!result || !result.ok) {
      choiceOverlay.delete(id);
      renderPopup();
      showChoiceError((result && result.error) || "Could not save that choice.");
    }
  } catch (error) {
    if (window.__mochiMeasure) {
      window.__mochiMeasure.choiceReplyMs = performance.now() - started;
      window.__mochiMeasure.choiceReplyDone = true;
    }
    choiceOverlay.delete(id);
    renderPopup();
    showChoiceError("Could not save that choice.");
  }
  requestAnimationFrame(reportHotRects);
}

function setCursorLinkUI(link) {
  cursorLinked = Boolean(link && link.connected);
  const status = document.getElementById("cursor-link-status");
  const button = document.getElementById("cursor-link-btn");
  const scan = document.getElementById("cursor-scan");
  if (status) status.textContent = cursorLinked ? "Connected" : "Not connected";
  if (button && document.body.dataset.cursorPrivacy !== "shown") {
    button.textContent = cursorLinked ? "Disconnect" : "Connect Cursor";
    button.classList.toggle("connected", cursorLinked);
  }
  if (scan && link && typeof link.scanTranscripts === "boolean") scan.checked = link.scanTranscripts;
}

async function refresh() {
  const epoch = taskPushEpoch;
  const [state, link] = await Promise.all([
    islandCall("getState"),
    islandCall("cursorLink", { linkAction: "status" }).catch(() => ({ connected: false })),
  ]);
  setCursorLinkUI(link);
  if (epoch !== taskPushEpoch) {
    requestAnimationFrame(reportHotRects);
    return;
  }
  const tasks = await islandCall("getTasks").catch(() => []);
  if (epoch !== taskPushEpoch) {
    requestAnimationFrame(reportHotRects);
    return;
  }
  applySnapshot(Array.isArray(tasks) ? tasks : [], state || {});
}

popup.addEventListener("click", (event) => {
  const button = event.target.closest(".speech-option");
  if (button) {
    event.preventDefault();
    event.stopPropagation();
    chooseTaskOption(button);
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  openAgentWindow().catch(() => {});
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  popupOpen = false;
  popup.hidden = true;
  setSettingsOpen(false);
});

window.addEventListener("resize", () => {
  placeFloating();
  reportHotRects();
});

if (window.webkit?.messageHandlers?.island) {
  refresh();
  setInterval(refresh, REFRESH_MS);
} else {
  applySnapshot([], {
    slots: [
      { id: "seed-cursor", source: "cursor", title: "New chat", skin: "cursor", created: 1 },
      { id: "seed-grok-bot", source: "grok-bot", title: "New chat", skin: "grok-bot", created: 1 },
      { id: "seed-mochi", source: "mochi", title: "New chat", skin: "mochi", created: 1 },
    ],
    selected: "seed-cursor",
    dock: "right",
  });
}
requestAnimationFrame(reportHotRects);
