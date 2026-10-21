const toastEl = document.getElementById("toast");
const catWrap = document.getElementById("cat-wrap");
const catArt = document.getElementById("cat-art");
const feedBtn = null;
const playBtn = document.getElementById("play-btn");
const newBtn = null;
const settingsBtn = document.getElementById("settings-btn");
const settingsCard = document.getElementById("settings-card");
const panelEl = document.getElementById("panel");
const speechEl = document.getElementById("speech");
const speechStack = document.getElementById("speech-stack");
const TASK_MARK = {
  running: '<img class="speech-mark" src="status/spinner.gif?v=35" alt="">',
  wait: '<img class="speech-mark" src="status/warning.gif?v=35" alt="">',
  done: '<img class="speech-mark" src="status/check.gif?v=35" alt="">',
  fail: '<img class="speech-mark" src="status/cross.gif?v=35" alt="">',
};
const KIND_LABEL = {
  choice: "Choice",
  plan: "Plan",
  mode: "Mode",
  permission: "Permission",
};
const collapsedByUser = new Set();
const choiceOverlay = new Map();
let latestTasks = [];
const fillInput = document.getElementById("bubble-fill");
const textColorInput = document.getElementById("bubble-text-color");
const strokeInput = document.getElementById("bubble-stroke");
const cardFillInput = document.getElementById("card-fill");
const cardStrokeInput = document.getElementById("card-stroke");
const petSizeInput = document.getElementById("pet-size");
const bubbleSizeInput = document.getElementById("bubble-size");
const defaultCare = "Let's take care of Mochi!";
let lastMessage = "";
let lastMood = "happy";
let petWasAlive = true;
const REFRESH_MS = 5000;
let taskPushEpoch = 0;
const HEX = /^#[0-9a-fA-F]{6}$/;
const PALETTE = [
  "#ffffff",
  "#fff6e8",
  "#241f1c",
  "#e97868",
  "#efd36a",
  "#7dcb8d",
  "#3d6ea8",
  "#f4b6c2",
];
let SLIDER_MAX_X = 900;
let SLIDER_MAX_Y = 700;
let closeTimer = 0;
let settingsTimer = 0;
let saveTimer = 0;
const SOUND_PICKS = [
  { id: "boop", label: "Boop" },
  { id: "chirp", label: "Chirp" },
  { id: "mew", label: "Mew" },
  { id: "pop", label: "Pop" },
  { id: "twinkle", label: "Twinkle" },
];
const SOUND_IDS = new Set(SOUND_PICKS.map((item) => item.id));
let currentSound = "boop";
const PET_LOOKS = [
  { id: "mochi", label: "Mochi", preview: "pets/happy.png" },
];
const LOOK_IDS = new Set(PET_LOOKS.map((item) => item.id));
const LOOK_SLOT_COUNT = 16;
let currentLook = "mochi";
let audioCtx = null;

function islandMessage(payload) {
  const handler = window.webkit?.messageHandlers?.island;
  if (handler) {
    handler.postMessage(payload);
  }
}

const pendingCalls = new Map();
let callSeq = 0;

function islandCall(action, extra = {}) {
  return new Promise((resolve, reject) => {
    const rpc = String(++callSeq);
    const timer = setTimeout(() => {
      if (!pendingCalls.has(rpc)) {
        return;
      }
      pendingCalls.delete(rpc);
      reject(new Error("request failed"));
    }, 8000);
    pendingCalls.set(rpc, { resolve, reject, timer });
    islandMessage({ ...extra, action, rpc });
  });
}

window.mochiReply = (rpc, payload) => {
  const item = pendingCalls.get(String(rpc));
  if (!item) {
    return;
  }
  clearTimeout(item.timer);
  pendingCalls.delete(String(rpc));
  item.resolve(payload);
};

window.pushTasks = (tasks, state) => {
  taskPushEpoch += 1;
  if (state && typeof state === "object") {
    render(state);
  }
  renderCursorTasks(tasks);
  requestAnimationFrame(reportHotRects);
};

window.__mochiClearChoices = () => {
  choiceOverlay.clear();
};

function fillSoundPicks() {
  const row = document.getElementById("sound-picks");
  row.innerHTML = SOUND_PICKS.map(
    (item) =>
      `<button type="button" data-sound="${item.id}" class="${item.id === currentSound ? "active" : ""}">${item.label}</button>`
  ).join("");
}

function lookSrc(mood) {
  const look = PET_LOOKS.find((item) => item.id === currentLook) || PET_LOOKS[0];
  return look.file || `pets/${mood || lastMood}.png`;
}

function fillLookPicks() {
  const row = document.getElementById("look-picks");
  const real = PET_LOOKS.map(
    (item) =>
      `<button type="button" data-look="${item.id}" class="${item.id === currentLook ? "active" : ""}" aria-label="${item.label}"><img src="${item.preview}" alt="" /></button>`
  ).join("");
  const empty = Array.from(
    { length: Math.max(0, LOOK_SLOT_COUNT - PET_LOOKS.length) },
    () => `<button type="button" class="placeholder" aria-label="Coming soon">?</button>`
  ).join("");
  row.innerHTML = real + empty;
}

function setCurrentLook(id) {
  currentLook = LOOK_IDS.has(id) ? id : "mochi";
  document.querySelectorAll(".look-picks button").forEach((button) => {
    button.classList.toggle("active", button.dataset.look === currentLook);
  });
  catArt.src = lookSrc(lastMood);
}

function setCurrentSound(id, preview) {
  currentSound = SOUND_IDS.has(id) ? id : "boop";
  document.querySelectorAll(".sound-picks button").forEach((button) => {
    button.classList.toggle("active", button.dataset.sound === currentSound);
  });
  if (preview) {
    playClickSound();
  }
}

function audioContext() {
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) {
    return null;
  }
  if (!audioCtx) {
    audioCtx = new AC();
  }
  if (audioCtx.state === "suspended") {
    audioCtx.resume();
  }
  return audioCtx;
}

function tone(ctx, type, freq, start, dur, gain, slideTo) {
  const osc = ctx.createOscillator();
  const amp = ctx.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(freq, start);
  if (slideTo) {
    osc.frequency.exponentialRampToValueAtTime(Math.max(40, slideTo), start + dur);
  }
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
    if (!ctx) {
      return;
    }
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
      tone(ctx, "square", 220, t, 0.04, 0.04);
      return;
    }
    if (currentSound === "twinkle") {
      tone(ctx, "sine", 1319, t, 0.16, 0.12);
      tone(ctx, "sine", 1976, t + 0.04, 0.18, 0.08);
      tone(ctx, "sine", 2637, t + 0.08, 0.2, 0.06);
      return;
    }
    tone(ctx, "sine", 880, t, 0.12, 0.16, 420);
  } catch (error) {
    return;
  }
}

function fillSwatches() {
  document.querySelectorAll(".swatches").forEach((row) => {
    row.innerHTML = PALETTE.map(
      (color) =>
        `<button type="button" data-color="${color}" style="background:${color}" aria-label="${color}"></button>`
    ).join("");
  });
}

function visibleSpeechNodes() {
  return Array.from(speechStack.querySelectorAll(".speech")).filter((el) => !el.classList.contains("hidden"));
}

function glassShape(el, kind) {
  const box = el.getBoundingClientRect();
  if (box.width < 2 || box.height < 2) {
    return null;
  }
  const style = window.getComputedStyle(el);
  if (style.visibility === "hidden" || style.display === "none") {
    return null;
  }
  const opacity = Number(style.opacity);
  if (Number.isFinite(opacity) && opacity < 0.04) {
    return null;
  }
  const scale = el.offsetWidth ? box.width / el.offsetWidth : 1;
  const radius = (parseFloat(style.borderTopLeftRadius) || (kind === "settings" ? 30 : 22)) * scale;
  const task = Boolean(el.closest(".speech.task"));
  const textNode = el.querySelector(".speech-text");
  return {
    x: box.left,
    y: box.top,
    w: box.width,
    h: box.height,
    r: radius,
    a: Number.isFinite(opacity) ? opacity : 1,
    kind,
    text: task ? "" : (textNode ? textNode.innerText : ""),
    cover: kind === "speech" && !task,
  };
}

let speechEdgeX = 0;
let speechEdgeY = 0;

function fitSpeechEdges() {
  if (speechStack.classList.contains("dragging")) {
    return;
  }
  const parent = speechStack.offsetParent || document.body;
  const parentRect = parent.getBoundingClientRect();
  const style = getComputedStyle(speechStack);
  const bubbleX = parseFloat(style.getPropertyValue("--bubble-x")) || 0;
  const bubbleY = parseFloat(style.getPropertyValue("--bubble-y")) || 0;
  const scale = parseFloat(style.getPropertyValue("--bubble-scale")) || 1;
  const margin = 12;
  const baseLeft = parentRect.left + speechStack.offsetLeft + bubbleX;
  const baseTop = parentRect.top + speechStack.offsetTop + bubbleY;
  const baseRight = baseLeft + speechStack.offsetWidth * scale;
  const baseBottom = baseTop + speechStack.offsetHeight * scale;
  let nextX = 0;
  let nextY = 0;
  if (baseRight > window.innerWidth - margin) {
    nextX = window.innerWidth - margin - baseRight;
  }
  if (baseLeft + nextX < margin) {
    nextX = margin - baseLeft;
  }
  if (baseBottom > window.innerHeight - margin) {
    nextY = window.innerHeight - margin - baseBottom;
  }
  if (baseTop + nextY < margin) {
    nextY = margin - baseTop;
  }
  if (Math.abs(nextX - speechEdgeX) < 0.5 && Math.abs(nextY - speechEdgeY) < 0.5) {
    return;
  }
  speechEdgeX = nextX;
  speechEdgeY = nextY;
  speechStack.style.setProperty("--edge-x", `${nextX}px`);
  speechStack.style.setProperty("--edge-y", `${nextY}px`);
}

function reportHotRects() {
  fitSpeechEdges();
  const nodes = [catWrap, ...visibleSpeechNodes()];
  if (newBtn && !newBtn.classList.contains("hidden")) {
    nodes.push(newBtn);
  }
  if (document.body.classList.contains("expanded")) {
    nodes.push(panelEl);
  }
  if (document.body.classList.contains("settings-open")) {
    nodes.push(settingsCard);
  }
  const rects = nodes.map((el) => {
    const box = el.getBoundingClientRect();
    return { x: box.left, y: box.top, w: box.width, h: box.height };
  });
  islandMessage({ action: "hotRects", rects: JSON.stringify(rects) });
  const glass = [];
  visibleSpeechNodes().forEach((node) => {
    const shape = glassShape(node.querySelector(".speech-inner") || node, "speech");
    if (shape) {
      glass.push(shape);
    }
  });
  const settingsShape = glassShape(settingsCard, "card");
  if (settingsShape && (document.body.classList.contains("settings-open") || document.body.classList.contains("settings-closing"))) {
    glass.push(settingsShape);
  }
  const panelShape = glassShape(panelEl, "card");
  if (panelShape && (document.body.classList.contains("expanded") || document.body.classList.contains("closing"))) {
    glass.push(panelShape);
  }
  islandMessage({ action: "glass", rects: JSON.stringify(glass) });
}

function pulseGlass(ms = 680) {
  const end = performance.now() + ms;
  const step = (now) => {
    if (document.body.classList.contains("expanded") || document.body.classList.contains("settings-open")) {
      placeCards();
    }
    reportHotRects();
    if (now < end) {
      requestAnimationFrame(step);
    }
  };
  requestAnimationFrame(step);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function layoutBox(el) {
  const parent = el.offsetParent || document.body;
  const parentRect = parent.getBoundingClientRect();
  const style = window.getComputedStyle(el);
  let tx = 0;
  let ty = 0;
  let sx = 1;
  let sy = 1;
  if (style.transform && style.transform !== "none") {
    const matrix = new DOMMatrixReadOnly(style.transform);
    tx = matrix.m41;
    ty = matrix.m42;
    sx = matrix.a;
    sy = matrix.d;
  }
  const left = parentRect.left + el.offsetLeft + tx;
  const top = parentRect.top + el.offsetTop + ty;
  const width = el.offsetWidth * Math.abs(sx);
  const height = el.offsetHeight * Math.abs(sy);
  return { left, top, right: left + width, bottom: top + height, width, height };
}

function placeCards(options = {}) {
  const margin = 12;
  const gap = 12;
  const viewW = window.innerWidth;
  const viewH = window.innerHeight;
  const catBox = layoutBox(catWrap);
  const bubbleBox = layoutBox(speechStack);
  const showNew = Boolean(newBtn && !newBtn.classList.contains("hidden"));
  const showSettings = options.includeSettings ?? document.body.classList.contains("settings-open");
  const items = [];
  if (showNew) {
    items.push({ el: newBtn, w: newBtn.offsetWidth || 96, h: newBtn.offsetHeight || 34 });
  }
  items.push({ el: panelEl, w: panelEl.offsetWidth || 300, h: panelEl.offsetHeight || 140 });
  if (showSettings) {
    items.push({
      el: settingsCard,
      w: settingsCard.offsetWidth || 540,
      h: settingsCard.offsetHeight || 280,
    });
  }
  const stackW = Math.max(...items.map((item) => item.w));
  const stackH = items.reduce((sum, item) => sum + item.h, 0) + gap * Math.max(0, items.length - 1);
  const anchorTop = Math.min(catBox.top, bubbleBox.top);
  const anchorBottom = Math.max(catBox.bottom, bubbleBox.bottom);
  const anchorMid = (anchorTop + anchorBottom) / 2;
  const spaceBelow = viewH - margin - (anchorBottom + 10);
  const openUp = anchorMid > viewH * 0.55 || spaceBelow < stackH;
  document.body.classList.toggle("popup-up", openUp);
  let left = Math.min(catBox.left, bubbleBox.left);
  left = clamp(left, margin, Math.max(margin, viewW - margin - stackW));
  const slots = [];
  if (openUp) {
    let y = anchorTop - 12;
    items.forEach((item) => {
      y -= item.h;
      slots.push({ el: item.el, h: item.h, top: y });
      y -= gap;
    });
  } else {
    let y = anchorBottom + 12;
    items.forEach((item) => {
      slots.push({ el: item.el, h: item.h, top: y });
      y += item.h + gap;
    });
  }
  const minTop = Math.min(...slots.map((slot) => slot.top));
  const maxBottom = Math.max(...slots.map((slot) => slot.top + slot.h));
  let shift = 0;
  if (minTop < margin) {
    shift = margin - minTop;
  }
  if (maxBottom + shift > viewH - margin) {
    shift -= maxBottom + shift - (viewH - margin);
  }
  if (minTop + shift < margin) {
    shift += margin - (minTop + shift);
  }
  slots.forEach((slot) => {
    slot.el.style.left = `${left}px`;
    slot.el.style.top = `${slot.top + shift}px`;
  });
}

function setExpanded(expanded) {
  const next = Boolean(expanded);
  const open = document.body.classList.contains("expanded");
  if (open === next) {
    reportHotRects();
    return;
  }
  window.clearTimeout(closeTimer);
  document.body.classList.remove("closing");
  if (next) {
    placeCards();
    document.body.classList.add("expanded");
    pulseGlass();
    requestAnimationFrame(reportHotRects);
    return;
  }
  setSettingsOpen(false);
  speechEl.classList.remove("dragging");
  speechStack.classList.remove("dragging");
  catWrap.classList.remove("dragging");
  document.body.classList.add("closing");
  document.body.classList.remove("expanded");
  closeTimer = window.setTimeout(() => {
    document.body.classList.remove("closing");
    reportHotRects();
  }, 300);
  pulseGlass(360);
}

function setSettingsOpen(open) {
  window.clearTimeout(settingsTimer);
  document.body.classList.remove("settings-closing");
  if (open) {
    placeCards({ includeSettings: true });
    document.body.classList.add("settings-open");
    if (!document.body.classList.contains("expanded")) {
      document.body.classList.add("expanded");
    }
    pulseGlass();
    requestAnimationFrame(reportHotRects);
    return;
  }
  if (!document.body.classList.contains("settings-open")) {
    return;
  }
  speechEl.classList.remove("dragging", "pop");
  speechStack.classList.remove("dragging");
  catWrap.classList.remove("dragging");
  document.body.classList.add("settings-closing");
  document.body.classList.remove("settings-open");
  settingsTimer = window.setTimeout(() => {
    document.body.classList.remove("settings-closing");
    reportHotRects();
  }, 300);
  pulseGlass(360);
}

function closePopup() {
  setExpanded(false);
}

function setBar(id, value) {
  document.getElementById(`${id}-value`).textContent = value;
  document.getElementById(`${id}-bar`).style.width = `${value}%`;
}

function popSpeech() {
  speechEl.classList.remove("pop");
  void speechEl.offsetWidth;
  speechEl.classList.add("pop");
}

function setSettingsPane(name) {
  const pane = name || "looks";
  document.querySelectorAll(".settings-nav button").forEach((button) => {
    button.classList.toggle("active", button.dataset.pane === pane);
  });
  document.querySelectorAll(".settings-pane").forEach((section) => {
    section.classList.toggle("active", section.dataset.pane === pane);
  });
  if (document.body.classList.contains("expanded") || document.body.classList.contains("settings-open")) {
    placeCards();
  }
  requestAnimationFrame(reportHotRects);
}

function render(state) {
  lastMood = state.mood;
  catArt.src = lookSrc(state.mood);
  const message = state.message || defaultCare;
  if (message !== lastMessage) {
    lastMessage = message;
    toastEl.textContent = message;
    popSpeech();
    pulseGlass(480);
  }
  setBar("hunger", state.hunger);
  setBar("energy", state.energy);
  setBar("happiness", state.happiness);
  if (playBtn) {
    playBtn.classList.toggle("hidden", Boolean(state.asleep));
  }
  requestAnimationFrame(reportHotRects);
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function truncateTitle(text) {
  const next = String(text || "").replace(/\s+/g, " ").trim();
  return next.length > 36 ? `${next.slice(0, 35)}…` : next;
}

function taskSource(task) {
  const value = String((task && task.source) || "").trim().toLowerCase();
  if (value === "codex") {
    return "codex";
  }
  if (value === "grok-bot" || value === "grok" || value === "grokbot" || value === "grok bot") {
    return "grok-bot";
  }
  return "cursor";
}

function taskOptions(task) {
  if (task.kind && task.kind !== "permission") {
    return [{ id: "open", label: "Open Cursor" }];
  }
  const list = Array.isArray(task.options) ? task.options.filter((item) => item && item.label) : [];
  if (list.length) {
    return list;
  }
  if (task.kind === "permission") {
    return [
      { id: "allow", label: "Allow" },
      { id: "deny", label: "Deny" },
    ];
  }
  return [];
}

function waitToken(task) {
  if (task.status !== "wait") {
    return "";
  }
  return `${task.kind || ""}:${task.request_id || ""}:${task.prompt || ""}`;
}

function fillTaskBubble(node, task, status, title) {
  const text = node.querySelector(".speech-text");
  text.removeAttribute("id");
  text.innerHTML = `${TASK_MARK[status] || TASK_MARK.running}<span class="speech-title">${escapeHtml(title)}</span>`;
  let detail = node.querySelector(".speech-detail");
  if (!detail) {
    detail = document.createElement("div");
    detail.className = "speech-detail";
    node.querySelector(".speech-inner").appendChild(detail);
  }
  const options = status === "wait" ? taskOptions(task) : [];
  const kind = KIND_LABEL[task.kind] || "";
  const prompt = String(task.prompt || "").trim();
  const extra = String(task.detail || "").trim();
  const bits = [];
  if (kind) {
    bits.push(`<span class="speech-kind">${escapeHtml(kind)}</span>`);
  }
  if (prompt) {
    bits.push(`<p class="speech-prompt">${escapeHtml(prompt)}</p>`);
  }
  if (extra && extra !== prompt && extra !== title) {
    bits.push(`<p class="speech-extra">${escapeHtml(extra)}</p>`);
  }
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
  detail.innerHTML = bits.join("");
}

function openAgentWindow(source, taskId) {
  return islandCall("openAgent", {
    source: source || "cursor",
    id: taskId || "",
  });
}

function onTaskSurfaceClick(event) {
  if (event.target.closest(".speech-option")) {
    event.stopPropagation();
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  const node = event.currentTarget;
  openAgentWindow(node.dataset.source || "cursor", node.dataset.taskId || "").catch(() => {});
}

function applyChoiceBubble(node, label) {
  const id = node.dataset.taskId || "";
  const picked = String(label || "").trim() || "Chosen";
  if (id) {
    choiceOverlay.set(id, picked);
  }
  node.dataset.wait = "0";
  node.classList.remove("is-open");
  node.dataset.taskKey = `choice:${picked}`;
  const title = node.querySelector(".speech-title");
  if (title) {
    title.textContent = picked;
  }
  const detail = node.querySelector(".speech-detail");
  if (detail) {
    detail.innerHTML = '<p class="speech-choice-error hidden"></p>';
  }
}

function showChoiceError(node, message) {
  const error = node.querySelector(".speech-choice-error");
  if (!error) {
    return;
  }
  error.textContent = message;
  error.classList.remove("hidden");
}

async function chooseTaskOption(event) {
  const button = event.target.closest(".speech-option");
  if (!button) {
    return;
  }
  event.preventDefault();
  event.stopPropagation();
  const node = button.closest(".speech.task");
  if (!node) {
    return;
  }
  const started = performance.now();
  const optionId = button.dataset.optionId || "";
  const label = button.dataset.label || button.textContent || "";
  const id = node.dataset.taskId || "";
  applyChoiceBubble(node, label);
  if (window.__mochiMeasure) {
      window.__mochiMeasure.choiceBubbleMs = performance.now() - started;
    window.__mochiMeasure.choiceBubbleDone = true;
  }
  try {
    const result = await islandCall("cursorChoice", {
      id,
      kind: node.dataset.kind || "",
      request_id: node.dataset.requestId || "",
      question_id: node.dataset.questionId || "",
      option_id: optionId,
      label,
    });
    if (window.__mochiMeasure) {
      window.__mochiMeasure.choiceReplyMs = performance.now() - started;
      window.__mochiMeasure.choiceReplyDone = true;
    }
    const ok = Boolean(result && result.ok);
    if (!ok) {
      choiceOverlay.delete(id);
      node.dataset.taskKey = "";
      renderCursorTasks(latestTasks);
      const fresh = speechStack.querySelector(`.speech.task[data-task-id="${CSS.escape(id)}"]`);
      if (fresh) {
        showChoiceError(fresh, (result && result.error) || "未能点到 Cursor，请在对话里选");
      }
    }
  } catch (err) {
    if (window.__mochiMeasure) {
      window.__mochiMeasure.choiceReplyMs = performance.now() - started;
      window.__mochiMeasure.choiceReplyDone = true;
    }
    choiceOverlay.delete(id);
    node.dataset.taskKey = "";
    renderCursorTasks(latestTasks);
    const fresh = speechStack.querySelector(`.speech.task[data-task-id="${CSS.escape(id)}"]`);
    if (fresh) {
      showChoiceError(fresh, "未能点到 Cursor，请在对话里选");
    }
  }
  requestAnimationFrame(reportHotRects);
}

function renderCursorTasks(tasks) {
  const list = Array.isArray(tasks) ? tasks : [];
  latestTasks = list;
  const existing = new Map();
  speechStack.querySelectorAll(".speech.task").forEach((el) => {
    existing.set(el.dataset.taskId, el);
  });
  if (!list.length) {
    existing.forEach((el) => el.remove());
    collapsedByUser.clear();
    speechEl.classList.remove("hidden");
    return;
  }
  speechEl.classList.add("hidden");
  const seen = new Set();
  let resized = false;
  list.forEach((task, index) => {
    const id = String(task.id || index);
    let view = task;
    const picked = choiceOverlay.get(id);
    if (picked && task.status === "wait") {
      view = {
        ...task,
        status: "running",
        title: picked,
        options: [],
        prompt: "",
        detail: "",
      };
    } else if (picked) {
      choiceOverlay.delete(id);
    }
    const status = TASK_MARK[view.status] ? view.status : "running";
    const title = truncateTitle(view.title);
    const source = taskSource(view);
    const token = waitToken(view);
    const contentKey = `${status}:${title}:${source}:${view.kind || ""}:${view.prompt || ""}:${view.request_id || ""}:${JSON.stringify(view.options || [])}`;
    seen.add(id);
    if (status !== "wait") {
      collapsedByUser.delete(id);
    } else {
      const prev = existing.get(id);
      if (prev && prev.dataset.waitToken !== token) {
        collapsedByUser.delete(id);
      }
    }
    const shouldOpen = status === "wait" && !collapsedByUser.has(id);
    let node = existing.get(id);
    if (!node) {
      resized = true;
      node = speechEl.cloneNode(true);
      node.id = "";
      node.dataset.taskId = id;
      node.classList.add("task");
      node.classList.remove("hidden", "pop", "dragging");
      node.addEventListener("click", onTaskSurfaceClick);
      node.addEventListener("pointerenter", () => requestAnimationFrame(reportHotRects));
      node.addEventListener("pointerleave", () => requestAnimationFrame(reportHotRects));
      node.querySelector(".speech-inner").addEventListener("click", chooseTaskOption);
    }
    node.dataset.wait = status === "wait" ? "1" : "0";
    node.dataset.waitToken = token;
    node.dataset.source = source;
    node.dataset.kind = view.kind || "";
    node.dataset.requestId = view.request_id || "";
    node.dataset.questionId = view.question_id || "";
    if (node.classList.contains("is-open") !== shouldOpen) {
      resized = true;
    }
    node.classList.toggle("is-open", shouldOpen);
    if (node.dataset.taskKey !== contentKey) {
      resized = true;
      node.dataset.taskKey = contentKey;
      fillTaskBubble(node, view, status, title);
    }
    speechStack.appendChild(node);
  });
  existing.forEach((el, id) => {
    if (!seen.has(id)) {
      resized = true;
      collapsedByUser.delete(id);
      el.remove();
    }
  });
  if (resized) {
    pulseGlass(560);
  }
}

async function request(name, extra = {}) {
  return islandCall(name, extra);
}

let cursorLinked = false;

function setCursorLinkUI(link) {
  cursorLinked = Boolean(link && link.connected);
  const status = document.getElementById("cursor-link-status");
  const button = document.getElementById("cursor-link-btn");
  const scan = document.getElementById("cursor-scan");
  if (status) {
    status.textContent = cursorLinked ? "Connected" : "Not connected";
  }
  if (button && document.body.dataset.cursorPrivacy !== "shown") {
    button.textContent = cursorLinked ? "Disconnect" : "Connect Cursor";
    button.classList.toggle("connected", cursorLinked);
  }
  if (scan && link && typeof link.scanTranscripts === "boolean") {
    scan.checked = link.scanTranscripts;
  }
}

async function refresh() {
  const epoch = taskPushEpoch;
  const [state, link] = await Promise.all([
    request("getState"),
    request("cursorLink", { linkAction: "status" }).catch(() => ({ connected: false })),
  ]);
  setCursorLinkUI(link);
  if (epoch !== taskPushEpoch) {
    requestAnimationFrame(reportHotRects);
    return;
  }
  render(state);
  const tasks = cursorLinked ? await request("getTasks").catch(() => []) : [];
  if (epoch !== taskPushEpoch) {
    requestAnimationFrame(reportHotRects);
    return;
  }
  renderCursorTasks(tasks);
  requestAnimationFrame(reportHotRects);
}

async function send(action) {
  if (action !== "play") {
    return;
  }
  render(await request("play"));
}

function sliderGroup(prefix) {
  return {
    x: document.getElementById(`${prefix}-x`),
    y: document.getElementById(`${prefix}-y`),
  };
}

function readOffset(group) {
  return {
    dx: Number(group.x.value) || 0,
    dy: Number(group.y.value) || 0,
  };
}

function writeOffset(group, dx, dy) {
  group.x.min = String(-SLIDER_MAX_X);
  group.x.max = String(SLIDER_MAX_X);
  group.y.min = String(-SLIDER_MAX_Y);
  group.y.max = String(SLIDER_MAX_Y);
  group.x.value = String(clamp(Math.round(Number(dx) || 0), -SLIDER_MAX_X, SLIDER_MAX_X));
  group.y.value = String(clamp(Math.round(Number(dy) || 0), -SLIDER_MAX_Y, SLIDER_MAX_Y));
}

function normalizeHex(value, fallback) {
  const raw = String(value || "").trim();
  if (HEX.test(raw)) {
    return raw.toLowerCase();
  }
  if (/^[0-9a-fA-F]{6}$/.test(raw)) {
    return `#${raw.toLowerCase()}`;
  }
  return fallback;
}

function applyOffset(el, xName, yName, dx, dy) {
  el.style.setProperty(xName, `${dx}px`);
  el.style.setProperty(yName, `${-dy}px`);
  requestAnimationFrame(reportHotRects);
}

function applyPetCSS(dx, dy) {
  applyOffset(catWrap, "--pet-x", "--pet-y", dx, dy);
}

function applyBubbleCSS(dx, dy) {
  applyOffset(speechStack, "--bubble-x", "--bubble-y", dx, dy);
}

function scaleFromInput(value) {
  return clamp(Number(value) || 100, 50, 200) / 100;
}

function applySize(el, varName, input, percent) {
  const pct = clamp(Math.round(Number(percent) || 100), 50, 200);
  el.style.setProperty(varName, String(pct / 100));
  input.value = String(pct);
  requestAnimationFrame(reportHotRects);
}

function applyPetSize(percent) {
  applySize(catWrap, "--pet-scale", petSizeInput, percent);
}

function applyBubbleSize(percent) {
  applySize(speechStack, "--bubble-scale", bubbleSizeInput, percent);
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
  const nextFill = normalizeHex(fill, "#fffdf8");
  const nextStroke = normalizeHex(stroke, "#2c2926");
  document.documentElement.style.setProperty("--card-fill", nextFill);
  document.documentElement.style.setProperty("--card-stroke", nextStroke);
  cardFillInput.value = nextFill;
  cardStrokeInput.value = nextStroke;
}

function currentPrefs() {
  const pet = readOffset(petSliders);
  const bubble = readOffset(bubbleSliders);
  return {
    dx: pet.dx,
    dy: pet.dy,
    bubble_dx: bubble.dx,
    bubble_dy: bubble.dy,
    fill: normalizeHex(fillInput.value, "#ffffff"),
    text: normalizeHex(textColorInput.value, "#241f1c"),
    stroke: normalizeHex(strokeInput.value, "#2c2926"),
    card_fill: normalizeHex(cardFillInput.value, "#fffdf8"),
    card_stroke: normalizeHex(cardStrokeInput.value, "#2c2926"),
    sound: currentSound,
    look: currentLook,
    pet_scale: scaleFromInput(petSizeInput.value),
    bubble_scale: scaleFromInput(bubbleSizeInput.value),
  };
}

function persistPrefs() {
  window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    islandMessage({ action: "savePrefs", ...currentPrefs() });
  }, 180);
}

function bindLive(sliders, onInput, kind) {
  sliders.forEach((slider) => {
    slider.addEventListener("input", onInput);
    slider.addEventListener("pointerdown", () => {
      if (kind === "bubble") {
        speechEl.classList.add("dragging");
        speechStack.classList.add("dragging");
      }
      if (kind === "pet") {
        catWrap.classList.add("dragging");
      }
    });
    slider.addEventListener("pointerup", () => {
      speechEl.classList.remove("dragging");
      speechStack.classList.remove("dragging");
      catWrap.classList.remove("dragging");
      persistPrefs();
    });
  });
}

const petSliders = sliderGroup("pet");
const bubbleSliders = sliderGroup("bubble");

function onPetInput() {
  const { dx, dy } = readOffset(petSliders);
  applyPetCSS(dx, dy);
  persistPrefs();
}

function onBubbleInput() {
  const { dx, dy } = readOffset(bubbleSliders);
  applyBubbleCSS(dx, dy);
  persistPrefs();
}

function onColorInput() {
  applyBubbleColors(fillInput.value, textColorInput.value, strokeInput.value);
  persistPrefs();
}

function onCardColorInput() {
  applyCardColors(cardFillInput.value, cardStrokeInput.value);
  persistPrefs();
}

function onPetSizeInput() {
  applyPetSize(petSizeInput.value);
  persistPrefs();
}

function onBubbleSizeInput() {
  applyBubbleSize(bubbleSizeInput.value);
  persistPrefs();
}

window.applyScreenLayout = function applyScreenLayout(layout) {
  const width = Number(layout.width) || window.innerWidth;
  const height = Number(layout.height) || window.innerHeight;
  const notchLeft = Number(layout.notchLeft);
  SLIDER_MAX_X = Math.max(400, Math.round(width));
  SLIDER_MAX_Y = Math.max(300, Math.round(height));
  [petSliders, bubbleSliders].forEach((group) => {
    group.x.min = String(-SLIDER_MAX_X);
    group.x.max = String(SLIDER_MAX_X);
    group.y.min = String(-SLIDER_MAX_Y);
    group.y.max = String(SLIDER_MAX_Y);
  });
  const petScale = parseFloat(getComputedStyle(catWrap).getPropertyValue("--pet-scale")) || 1;
  const petSize = 86 * petScale;
  const gap = 8;
  const petTop = 6;
  const chip = 28;
  const bubbleLeft = Number.isFinite(notchLeft) ? notchLeft : width / 2 - 90;
  const catLeft = Math.max(8, bubbleLeft - petSize - gap);
  catWrap.style.left = `${catLeft}px`;
  catWrap.style.top = `${petTop}px`;
  speechStack.style.left = `${catLeft + petSize + gap}px`;
  speechStack.style.top = `${petTop + Math.max(0, (petSize - chip) * 0.38)}px`;
  reportHotRects();
};

window.applyPrefs = function applyPrefs(prefs) {
  writeOffset(petSliders, prefs.dx, prefs.dy);
  writeOffset(bubbleSliders, prefs.bubble_dx, prefs.bubble_dy);
  applyPetCSS(prefs.dx, prefs.dy);
  applyBubbleCSS(prefs.bubble_dx, prefs.bubble_dy);
  applyPetSize((Number(prefs.pet_scale) || 1) * 100);
  applyBubbleSize((Number(prefs.bubble_scale) || 1) * 100);
  applyBubbleColors(prefs.fill, prefs.text, prefs.stroke);
  applyCardColors(prefs.card_fill, prefs.card_stroke);
  setCurrentSound(prefs.sound || "boop", false);
  setCurrentLook(prefs.look || "mochi");
};

function togglePopup() {
  if (document.body.classList.contains("expanded")) {
    closePopup();
    return;
  }
  setExpanded(true);
}

fillSwatches();
fillSoundPicks();
fillLookPicks();
catArt.addEventListener("click", togglePopup);
speechEl.addEventListener("click", togglePopup);
catWrap.addEventListener("pointerenter", () => requestAnimationFrame(reportHotRects));
catWrap.addEventListener("pointerleave", () => requestAnimationFrame(reportHotRects));
speechStack.addEventListener("pointerenter", () => {
  pulseGlass(420);
});
speechStack.addEventListener("pointerleave", () => requestAnimationFrame(reportHotRects));

speechEl.addEventListener("animationend", (event) => {
  if (event.animationName === "speech-pop") {
    speechEl.classList.remove("pop");
  }
});
window.addEventListener("resize", () => {
  if (document.body.classList.contains("expanded") || document.body.classList.contains("settings-open")) {
    placeCards();
  }
  reportHotRects();
});

window.addEventListener("pointerup", () => {
  speechEl.classList.remove("dragging");
  speechStack.classList.remove("dragging");
  catWrap.classList.remove("dragging");
});
window.addEventListener("pointercancel", () => {
  speechEl.classList.remove("dragging");
  speechStack.classList.remove("dragging");
  catWrap.classList.remove("dragging");
});

document.getElementById("island").addEventListener(
  "click",
  (event) => {
    if (event.target.closest("input[type='range']") || event.target.closest(".sound-picks") || event.target.closest(".look-picks")) {
      return;
    }
    playClickSound();
  },
  true
);

playBtn.addEventListener("click", (event) => {
  event.stopPropagation();
  send("play");
});
settingsBtn.addEventListener("click", (event) => {
  event.stopPropagation();
  const open = document.body.classList.contains("settings-open");
  setSettingsOpen(!open);
});
panelEl.addEventListener("click", (event) => event.stopPropagation());
settingsCard.addEventListener("click", (event) => event.stopPropagation());

bindLive(Object.values(petSliders), onPetInput, "pet");
bindLive(Object.values(bubbleSliders), onBubbleInput, "bubble");
petSizeInput.addEventListener("input", onPetSizeInput);
bubbleSizeInput.addEventListener("input", onBubbleSizeInput);
[fillInput, textColorInput, strokeInput].forEach((input) => {
  input.addEventListener("change", onColorInput);
});
[cardFillInput, cardStrokeInput].forEach((input) => {
  input.addEventListener("change", onCardColorInput);
});
document.getElementById("settings-nav").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-pane]");
  if (!button) {
    return;
  }
  setSettingsPane(button.dataset.pane);
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
    if (!button || !input) {
      return;
    }
    input.value = button.dataset.color;
    if (row.dataset.target.startsWith("card")) {
      applyCardColors(cardFillInput.value, cardStrokeInput.value);
    } else {
      applyBubbleColors(fillInput.value, textColorInput.value, strokeInput.value);
      popSpeech();
    }
    persistPrefs();
  });
});

document.getElementById("cursor-scan").addEventListener("change", (event) => {
  islandCall("setScan", { enabled: event.target.checked }).catch(() => {});
});
function bindFileSource(buttonId, statusId, readyLabel) {
  const button = document.getElementById(buttonId);
  if (!button) {
    return;
  }
  button.addEventListener("click", (event) => {
    event.stopPropagation();
    button.classList.add("connected");
    button.textContent = readyLabel;
    const status = document.getElementById(statusId);
    if (status) {
      status.textContent = "Listening for tasks";
    }
  });
}

bindFileSource("codex-link-btn", "codex-link-status", "Codex ready");
bindFileSource("grok-link-btn", "grok-link-status", "Grok Bot ready");

document.getElementById("cursor-link-btn").addEventListener("click", async (event) => {
  event.stopPropagation();
  const action = cursorLinked ? "disconnect" : "connect";
  try {
    const link = await request("cursorLink", {
      linkAction: action,
      acknowledged: cursorLinked || document.body.dataset.cursorPrivacy === "shown",
    });
    if (link && link.needsPrivacy) {
      document.body.dataset.cursorPrivacy = "shown";
      const note = document.getElementById("cursor-privacy");
      if (note) {
        note.classList.remove("hidden");
      }
      const button = document.getElementById("cursor-link-btn");
      if (button) {
        button.textContent = "Continue";
      }
      return;
    }
    setCursorLinkUI(link);
    await refresh();
  } catch (error) {
    return;
  }
});
document.getElementById("sound-picks").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-sound]");
  if (!button) {
    return;
  }
  setCurrentSound(button.dataset.sound, true);
  persistPrefs();
});
document.getElementById("look-picks").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-look]");
  if (!button || button.classList.contains("placeholder")) {
    return;
  }
  setCurrentLook(button.dataset.look);
  playClickSound();
  persistPrefs();
});
document.getElementById("reset-pet").addEventListener("click", () => {
  writeOffset(petSliders, 0, 0);
  applyPetCSS(0, 0);
  applyPetSize(100);
  persistPrefs();
});
document.getElementById("reset-bubble").addEventListener("click", () => {
  writeOffset(bubbleSliders, 0, 0);
  applyBubbleCSS(0, 0);
  applyBubbleSize(100);
  popSpeech();
  persistPrefs();
});

document.addEventListener("keydown", (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) {
    return;
  }
  const tag = event.target && event.target.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA") {
    return;
  }
  const key = event.key.toLowerCase();
  if (key === "d" || key === "p") {
    event.preventDefault();
    send("play");
    playClickSound();
  }
  if (key === "escape") {
    closePopup();
  }
});

refresh();
setInterval(refresh, REFRESH_MS);
window.applyScreenLayout({
  width: window.innerWidth,
  height: window.innerHeight,
  notchLeft: window.innerWidth / 2 - 110,
});
requestAnimationFrame(reportHotRects);
