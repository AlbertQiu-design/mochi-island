const capsule = document.getElementById("capsule");
const slotList = document.getElementById("slot-list");
const addBtn = document.getElementById("add-btn");
const settingsBtn = document.getElementById("settings-btn");
const settingsCard = document.getElementById("settings-card");
const sourceMenu = document.getElementById("source-menu");
const popup = document.getElementById("popup");
const popupApp = popup.querySelector(".popup-app");
const popupTitle = popup.querySelector(".popup-title");
const popupSummary = popup.querySelector(".popup-summary");
const fillInput = document.getElementById("bubble-fill");
const textColorInput = document.getElementById("bubble-text-color");
const strokeInput = document.getElementById("bubble-stroke");
const cardFillInput = document.getElementById("card-fill");
const cardStrokeInput = document.getElementById("card-stroke");

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
    wake: "pets/mochi-wake.png",
    work: "pets/mochi-wake.png",
    wait: "pets/mochi-wake.png",
    done: "pets/mochi-wake.png",
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
const choiceOverlay = new Map();
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

function slotFaceHTML(slot) {
  const source = faceSkin(slot.source);
  const task = liveTask(slot.id);
  const state = faceState(task && task.status);
  const pack = FACE_SRC[source];
  const src = pack ? pack[state] || pack.wake : "";
  const img = src ? `<img src="${src}" alt="">` : "";
  return `<span class="slot-face face-${source}" aria-hidden="true">${img}</span>`;
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

function renderSlots() {
  slotList.innerHTML = slotRecords
    .map((slot) => {
      const selected = slot.id === selectedId ? " selected" : "";
      const label = escapeHtml(slot.title || "New chat");
      return `<button type="button" class="slot${selected}" data-task-id="${escapeHtml(slot.id)}" data-source="${slot.source}" data-app="${escapeHtml(APP_NAME[slot.source] || "Cursor")}" aria-label="${label}">${slotFaceHTML(slot)}</button>`;
    })
    .join("");
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
  renderSlots();
  renderPopup();
  placeFloating();
  requestAnimationFrame(reportHotRects);
}

function placeFloating() {
  const dock = document.body.dataset.dock === "left" ? "left" : "right";
  const capsuleBox = capsule.getBoundingClientRect();
  const gap = 8;
  if (!popup.hidden) {
    const width = 200;
    const slotEl = selectedId ? slotList.querySelector(`.slot[data-task-id="${CSS.escape(selectedId)}"]`) : null;
    const slotBox = slotEl ? slotEl.getBoundingClientRect() : null;
    const height = popup.offsetHeight || 120;
    const anchorMid = slotBox ? slotBox.top + slotBox.height / 2 : capsuleBox.top + capsuleBox.height / 2;
    let left = dock === "right" ? capsuleBox.left - gap - width : capsuleBox.right + gap;
    let top = anchorMid - height / 2;
    top = clamp(top, 8, Math.max(8, window.innerHeight - 8 - height));
    left = clamp(left, 8, Math.max(8, window.innerWidth - 8 - width));
    popup.style.left = `${left}px`;
    popup.style.top = `${top}px`;
  }
  if (!sourceMenu.hidden) {
    const width = sourceMenu.offsetWidth || 148;
    const height = sourceMenu.offsetHeight || 120;
    const addBox = addBtn.getBoundingClientRect();
    let left = dock === "right" ? capsuleBox.left - gap - width : capsuleBox.right + gap;
    let top = addBox.top - height - gap;
    top = clamp(top, 8, Math.max(8, window.innerHeight - 8 - height));
    left = clamp(left, 8, Math.max(8, window.innerWidth - 8 - width));
    sourceMenu.style.left = `${left}px`;
    sourceMenu.style.top = `${top}px`;
  }
  if (document.body.classList.contains("settings-open")) {
    const width = Math.min(540, Math.max(280, window.innerWidth - 56 - 32));
    settingsCard.style.width = `${width}px`;
    const height = settingsCard.offsetHeight || 280;
    const gearBox = settingsBtn.getBoundingClientRect();
    let left = dock === "right" ? capsuleBox.left - gap - width : capsuleBox.right + gap;
    let top = gearBox.bottom - height;
    top = clamp(top, 8, Math.max(8, window.innerHeight - 8 - height));
    left = clamp(left, 8, Math.max(8, window.innerWidth - 8 - width));
    settingsCard.style.left = `${left}px`;
    settingsCard.style.top = `${top}px`;
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
  const nodes = [capsule];
  if (!popup.hidden) nodes.push(popup);
  if (!sourceMenu.hidden) nodes.push(sourceMenu);
  if (document.body.classList.contains("settings-open")) nodes.push(settingsCard);
  const rects = nodes
    .map((el) => {
      const box = el.getBoundingClientRect();
      return { x: box.left, y: box.top, w: box.width, h: box.height };
    })
    .filter((rect) => rect.w > 1 && rect.h > 1);
  islandMessage({ action: "hotRects", rects: JSON.stringify(rects) });
  const glass = [];
  if (document.body.classList.contains("settings-open") || document.body.classList.contains("settings-closing")) {
    const shape = glassShape(settingsCard);
    if (shape) glass.push(shape);
  }
  islandMessage({ action: "glass", rects: JSON.stringify(glass) });
}

function setDock(side, persist) {
  const next = side === "left" ? "left" : "right";
  document.body.dataset.dock = next;
  document.querySelectorAll("#dock-picks button").forEach((button) => {
    button.classList.toggle("active", button.dataset.dock === next);
  });
  placeFloating();
  if (persist) persistPrefs();
  requestAnimationFrame(reportHotRects);
}

function setSettingsOpen(open) {
  document.body.classList.toggle("settings-open", open);
  if (open) sourceMenu.hidden = true;
  placeFloating();
  requestAnimationFrame(reportHotRects);
}

function currentPrefs() {
  return {
    dx: stored.dx,
    dy: stored.dy,
    bubble_dx: stored.bubble_dx,
    bubble_dy: stored.bubble_dy,
    fill: normalizeHex(fillInput.value, "#ffffff"),
    text: normalizeHex(textColorInput.value, "#241f1c"),
    stroke: normalizeHex(strokeInput.value, "#2c2926"),
    card_fill: normalizeHex(cardFillInput.value, "#111111"),
    card_stroke: normalizeHex(cardStrokeInput.value, "#2c2926"),
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
  const nextFill = normalizeHex(fill, "#ffffff");
  const nextText = normalizeHex(text, "#241f1c");
  const nextStroke = normalizeHex(stroke, "#2c2926");
  document.documentElement.style.setProperty("--bubble-fill", nextFill);
  document.documentElement.style.setProperty("--bubble-text", nextText);
  document.documentElement.style.setProperty("--bubble-stroke", nextStroke);
  fillInput.value = nextFill;
  textColorInput.value = nextText;
  strokeInput.value = nextStroke;
}

function applyCardColors(fill, stroke) {
  const nextFill = normalizeHex(fill, "#111111");
  const nextStroke = normalizeHex(stroke, "#2c2926");
  document.documentElement.style.setProperty("--card-fill", nextFill);
  document.documentElement.style.setProperty("--card-stroke", nextStroke);
  cardFillInput.value = nextFill;
  cardStrokeInput.value = nextStroke;
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

fillSwatches();
fillSoundPicks();
fillLookPicks();

slotList.addEventListener("click", (event) => {
  const button = event.target.closest(".slot");
  if (!button) return;
  event.stopPropagation();
  const id = button.dataset.taskId || "";
  if (id === selectedId && popupOpen) popupOpen = false;
  else {
    selectedId = id;
    popupOpen = true;
  }
  sourceMenu.hidden = true;
  paint();
  persistPrefs();
});

addBtn.addEventListener("click", (event) => {
  event.stopPropagation();
  sourceMenu.hidden = !sourceMenu.hidden;
  if (!sourceMenu.hidden) setSettingsOpen(false);
  placeFloating();
  requestAnimationFrame(reportHotRects);
});

sourceMenu.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-source]");
  if (!button) return;
  event.stopPropagation();
  sourceMenu.hidden = true;
  if (!window.webkit?.messageHandlers?.island) {
    const source = taskSource({ source: button.dataset.source });
    const slot = {
      id: `preview-${source}-${Date.now()}`,
      source,
      title: "New chat",
      skin: faceSkin(source),
      created: Date.now(),
    };
    slotRecords.push(slot);
    selectedId = slot.id;
    popupOpen = true;
    paint();
    return;
  }
  try {
    const result = await islandCall("createSlot", { source: button.dataset.source || "cursor" });
    if (result && Array.isArray(result.slots)) {
      slotRecords = result.slots.map(normalizeSlot).filter(Boolean);
      selectedId = result.selected || selectedId;
      popupOpen = true;
      paint();
      persistPrefs();
    }
  } catch (error) {
    requestAnimationFrame(reportHotRects);
  }
});

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

settingsBtn.addEventListener("click", (event) => {
  event.stopPropagation();
  setSettingsOpen(!document.body.classList.contains("settings-open"));
});

settingsCard.addEventListener("click", (event) => event.stopPropagation());

document.getElementById("settings-nav").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-pane]");
  if (!button) return;
  document.querySelectorAll(".settings-nav button").forEach((item) => {
    item.classList.toggle("active", item === button);
  });
  document.querySelectorAll(".settings-pane").forEach((section) => {
    section.classList.toggle("active", section.dataset.pane === button.dataset.pane);
  });
  placeFloating();
  requestAnimationFrame(reportHotRects);
});

document.getElementById("dock-picks").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-dock]");
  if (!button) return;
  setDock(button.dataset.dock, true);
});

document.getElementById("sound-picks").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-sound]");
  if (!button) return;
  setCurrentSound(button.dataset.sound, true);
  persistPrefs();
});

document.getElementById("look-picks").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-look]");
  if (!button || button.classList.contains("placeholder")) return;
  setCurrentLook(button.dataset.look);
  playClickSound();
  persistPrefs();
});

const COLOR_TARGETS = {
  fill: fillInput,
  text: textColorInput,
  stroke: strokeInput,
  "card-fill": cardFillInput,
  "card-stroke": cardStrokeInput,
};
document.querySelectorAll(".swatches").forEach((row) => {
  row.addEventListener("click", (event) => {
    const button = event.target.closest("button[data-color]");
    const input = COLOR_TARGETS[row.dataset.target];
    if (!button || !input) return;
    input.value = button.dataset.color;
    if (String(row.dataset.target).startsWith("card")) applyCardColors(cardFillInput.value, cardStrokeInput.value);
    else applyBubbleColors(fillInput.value, textColorInput.value, strokeInput.value);
    persistPrefs();
  });
});
[fillInput, textColorInput, strokeInput].forEach((input) => {
  input.addEventListener("change", () => {
    applyBubbleColors(fillInput.value, textColorInput.value, strokeInput.value);
    persistPrefs();
  });
});
[cardFillInput, cardStrokeInput].forEach((input) => {
  input.addEventListener("change", () => {
    applyCardColors(cardFillInput.value, cardStrokeInput.value);
    persistPrefs();
  });
});

document.getElementById("cursor-scan").addEventListener("change", (event) => {
  islandCall("setScan", { enabled: event.target.checked }).catch(() => {});
});

function bindFileSource(buttonId, statusId, readyLabel) {
  const button = document.getElementById(buttonId);
  if (!button) return;
  button.addEventListener("click", (event) => {
    event.stopPropagation();
    button.classList.add("connected");
    button.textContent = readyLabel;
    const status = document.getElementById(statusId);
    if (status) status.textContent = "Listening for tasks";
  });
}
bindFileSource("codex-link-btn", "codex-link-status", "Codex ready");
bindFileSource("grok-link-btn", "grok-link-status", "Grok Bot ready");

document.getElementById("cursor-link-btn").addEventListener("click", async (event) => {
  event.stopPropagation();
  const action = cursorLinked ? "disconnect" : "connect";
  try {
    const link = await islandCall("cursorLink", {
      linkAction: action,
      acknowledged: cursorLinked || document.body.dataset.cursorPrivacy === "shown",
    });
    if (link && link.needsPrivacy) {
      document.body.dataset.cursorPrivacy = "shown";
      const note = document.getElementById("cursor-privacy");
      if (note) note.classList.remove("hidden");
      const button = document.getElementById("cursor-link-btn");
      if (button) button.textContent = "Continue";
      return;
    }
    setCursorLinkUI(link);
    await refresh();
  } catch (error) {
    return;
  }
});

document.getElementById("island").addEventListener(
  "click",
  (event) => {
    if (event.target.closest(".sound-picks") || event.target.closest(".look-picks") || event.target.closest(".swatches")) return;
    playClickSound();
  },
  true
);

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  popupOpen = false;
  popup.hidden = true;
  sourceMenu.hidden = true;
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
