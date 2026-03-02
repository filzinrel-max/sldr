(() => {
  "use strict";

  const LANE_NAMES = ["Left", "Down", "Up", "Right"];
  const LANE_COLORS = ["#7ac8ff", "#78f6a8", "#ffd977", "#ff99c7"];
  const LANE_ROTATIONS = [-Math.PI / 2, Math.PI, 0, Math.PI / 2];
  const EVENT_PREVIEW_LIMIT = 220;

  const state = {
    songs: [],
    currentSongId: "",
    chartIndex: null,
    events: [],
    notes: [],
    holds: [],
    durationSeconds: 0,
    scrollSpeed: 340,
    playing: false,
    playStartMs: 0,
    playStartSongSeconds: 0,
    currentSongSeconds: 0,
    rafId: 0,
    arrowImage: null,
    arrowLoaded: false
  };

  const ui = {
    songSelect: null,
    difficultySelect: null,
    chartPathInput: null,
    loadFromManifestBtn: null,
    loadByPathBtn: null,
    playPauseBtn: null,
    restartBtn: null,
    timeRange: null,
    speedRange: null,
    speedValue: null,
    statusText: null,
    durationValue: null,
    notesValue: null,
    holdsValue: null,
    eventsValue: null,
    timeValue: null,
    eventPreview: null,
    chartCanvas: null
  };

  function byId(id) {
    return document.getElementById(id);
  }

  function setStatus(text, isError) {
    if (!ui.statusText) {
      return;
    }
    ui.statusText.textContent = text;
    if (isError) {
      ui.statusText.classList.add("is-error");
    } else {
      ui.statusText.classList.remove("is-error");
    }
  }

  function formatSeconds(value) {
    return Number(value || 0).toFixed(2) + "s";
  }

  function clamp(value, minValue, maxValue) {
    if (value < minValue) {
      return minValue;
    }
    if (value > maxValue) {
      return maxValue;
    }
    return value;
  }

  function nowMs() {
    return performance.now();
  }

  function normalizePathToUrl(pathOrUrl) {
    const raw = String(pathOrUrl || "").trim();
    if (!raw) {
      return "";
    }
    if (/^https?:\/\//i.test(raw)) {
      return raw;
    }
    if (raw.indexOf("data:") === 0 || raw.indexOf("blob:") === 0) {
      return raw;
    }
    const normalized = raw.replace(/^\/+/, "").replace(/^\.\//, "");
    return new URL("../" + normalized, window.location.href).toString();
  }

  async function fetchJsonNoCache(url) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
      throw new Error("HTTP " + response.status + " for " + url);
    }
    return response.json();
  }

  async function fetchTextNoCache(url) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
      throw new Error("HTTP " + response.status + " for " + url);
    }
    return response.text();
  }

  function difficultySortKey(name) {
    const order = {
      beginner: 0,
      easy: 1,
      medium: 2,
      hard: 3,
      challenge: 4
    };
    const key = String(name || "").toLowerCase();
    if (Object.prototype.hasOwnProperty.call(order, key)) {
      return order[key];
    }
    return 99;
  }

  function sortedDifficultyKeys(chartMap) {
    return Object.keys(chartMap || {}).sort((a, b) => {
      const ai = difficultySortKey(a);
      const bi = difficultySortKey(b);
      if (ai !== bi) {
        return ai - bi;
      }
      return a.localeCompare(b);
    });
  }

  function songById(songId) {
    const target = String(songId || "");
    let i = 0;
    for (; i < state.songs.length; i += 1) {
      const song = state.songs[i];
      if (String(song.id || "") === target) {
        return song;
      }
    }
    return null;
  }

  function chartMapForSong(song) {
    if (!song || typeof song !== "object") {
      return {};
    }
    if (song.cj && typeof song.cj === "object") {
      return song.cj;
    }
    if (song.chartJsonByDifficulty && typeof song.chartJsonByDifficulty === "object") {
      return song.chartJsonByDifficulty;
    }
    return {};
  }

  function fillSongSelect() {
    ui.songSelect.innerHTML = "";
    state.songs.forEach((song) => {
      const option = document.createElement("option");
      option.value = String(song.id || "");
      option.textContent = String(song.t || song.id || "Unknown Song") + " - " + String(song.a || "Unknown Artist");
      ui.songSelect.appendChild(option);
    });

    if (state.songs.length > 0) {
      state.currentSongId = String(state.songs[0].id || "");
      ui.songSelect.value = state.currentSongId;
    } else {
      state.currentSongId = "";
    }
  }

  function fillDifficultySelect(songId) {
    const song = songById(songId);
    const map = chartMapForSong(song);
    const keys = sortedDifficultyKeys(map);
    ui.difficultySelect.innerHTML = "";
    keys.forEach((difficulty) => {
      const option = document.createElement("option");
      option.value = difficulty;
      option.textContent = difficulty;
      ui.difficultySelect.appendChild(option);
    });
    if (keys.length > 0) {
      ui.difficultySelect.value = keys[0];
    }
    updatePathFromManifestSelection();
  }

  function updatePathFromManifestSelection() {
    const song = songById(ui.songSelect.value);
    const difficulty = ui.difficultySelect.value;
    const map = chartMapForSong(song);
    const path = map[difficulty] || "";
    ui.chartPathInput.value = path;
  }

  function maskToLdur(mask) {
    const m = Number(mask) || 0;
    return (m & 1 ? "1" : "0") + (m & 2 ? "1" : "0") + (m & 4 ? "1" : "0") + (m & 8 ? "1" : "0");
  }

  function parseChunkRows(payloadText) {
    const rows = String(payloadText || "").split(";");
    const out = [];
    let i = 0;
    for (; i < rows.length; i += 1) {
      const row = rows[i].trim();
      if (!row) {
        continue;
      }
      const parts = row.split(",");
      if (parts.length < 4) {
        continue;
      }
      const deltaCs = parseInt(parts[0], 10);
      const pressMask = parseInt(parts[1], 10);
      const holdStartMask = parseInt(parts[2], 10);
      const holdEndMask = parseInt(parts[3], 10);
      if (!Number.isFinite(deltaCs) || !Number.isFinite(pressMask) || !Number.isFinite(holdStartMask) || !Number.isFinite(holdEndMask)) {
        continue;
      }
      out.push({
        deltaCs,
        pressMask,
        holdStartMask,
        holdEndMask
      });
    }
    return out;
  }

  function decodeCondensedEvents(rows, indexPayload) {
    const notes = [];
    const holds = [];
    const events = [];

    let cursorCs = 0;
    let latestNoteCs = 0;
    let nextHoldId = 1;
    const openHoldIds = [-1, -1, -1, -1];
    const openHoldStarts = [0, 0, 0, 0];

    function pushNote(timeCs, lane, holdId, isHoldHead) {
      notes.push({
        timeCs,
        lane,
        holdId,
        isHoldHead
      });
      if (timeCs > latestNoteCs) {
        latestNoteCs = timeCs;
      }
    }

    function closeOpenHoldAtLane(lane, endCs) {
      const holdId = openHoldIds[lane];
      if (holdId < 1) {
        return;
      }
      const startCs = openHoldStarts[lane];
      let finalEndCs = endCs;
      if (finalEndCs < startCs) {
        finalEndCs = startCs;
      }
      holds.push({
        holdId,
        lane,
        startCs,
        endCs: finalEndCs
      });
      openHoldIds[lane] = -1;
      openHoldStarts[lane] = 0;
    }

    rows.forEach((row) => {
      cursorCs += row.deltaCs;
      events.push({
        timeCs: cursorCs,
        deltaCs: row.deltaCs,
        pressMask: row.pressMask,
        holdStartMask: row.holdStartMask,
        holdEndMask: row.holdEndMask
      });

      let lane = 0;
      for (; lane < 4; lane += 1) {
        const bit = 1 << lane;
        if ((row.holdEndMask & bit) !== 0) {
          closeOpenHoldAtLane(lane, cursorCs);
        }
      }

      lane = 0;
      for (; lane < 4; lane += 1) {
        const bit = 1 << lane;
        if ((row.holdStartMask & bit) !== 0) {
          const holdId = nextHoldId;
          nextHoldId += 1;
          openHoldIds[lane] = holdId;
          openHoldStarts[lane] = cursorCs;
          pushNote(cursorCs, lane, holdId, true);
        }
      }

      lane = 0;
      for (; lane < 4; lane += 1) {
        const bit = 1 << lane;
        if ((row.pressMask & bit) !== 0 && (row.holdStartMask & bit) === 0) {
          pushNote(cursorCs, lane, -1, false);
        }
      }
    });

    const finalizeEndCs = latestNoteCs + 25;
    let lane = 0;
    for (; lane < 4; lane += 1) {
      if (openHoldIds[lane] > 0) {
        closeOpenHoldAtLane(lane, finalizeEndCs);
      }
    }

    let parsedDurationSeconds = Number(indexPayload && indexPayload.du) || 0;
    const parsedLatestSeconds = latestNoteCs / 100;
    if (parsedLatestSeconds > parsedDurationSeconds) {
      parsedDurationSeconds = parsedLatestSeconds;
    }
    holds.forEach((hold) => {
      const endSeconds = hold.endCs / 100;
      if (endSeconds > parsedDurationSeconds) {
        parsedDurationSeconds = endSeconds;
      }
    });
    if (parsedDurationSeconds < 0.01) {
      parsedDurationSeconds = 0.01;
    }

    return {
      notes,
      holds,
      events,
      durationSeconds: parsedDurationSeconds
    };
  }

  function resetPlayback(positionSeconds) {
    state.playing = false;
    state.playStartMs = 0;
    state.playStartSongSeconds = 0;
    state.currentSongSeconds = clamp(positionSeconds || 0, 0, state.durationSeconds);
    syncPlayButton();
    syncTimeSliderFromState();
  }

  function syncPlayButton() {
    ui.playPauseBtn.textContent = state.playing ? "Pause" : "Play";
  }

  function syncTimeSliderFromState() {
    if (!ui.timeRange) {
      return;
    }
    const max = Math.max(state.durationSeconds, 0.001);
    ui.timeRange.max = String(max);
    ui.timeRange.value = String(clamp(state.currentSongSeconds, 0, max));
    ui.timeValue.textContent = formatSeconds(state.currentSongSeconds);
  }

  function syncStats() {
    ui.durationValue.textContent = formatSeconds(state.durationSeconds);
    ui.notesValue.textContent = String(state.notes.length);
    ui.holdsValue.textContent = String(state.holds.length);
    ui.eventsValue.textContent = String(state.events.length);
    syncTimeSliderFromState();
  }

  function updateEventPreview() {
    if (!ui.eventPreview) {
      return;
    }
    if (state.events.length <= 0) {
      ui.eventPreview.textContent = "No events loaded.";
      return;
    }
    const lines = [];
    const limit = Math.min(state.events.length, EVENT_PREVIEW_LIMIT);
    let i = 0;
    for (; i < limit; i += 1) {
      const event = state.events[i];
      lines.push(
        String(i + 1).padStart(4, " ") +
          "  t=" +
          (event.timeCs / 100).toFixed(2).padStart(7, " ") +
          "s  d=" +
          String(event.deltaCs).padStart(4, " ") +
          "  p:" +
          maskToLdur(event.pressMask) +
          "  hs:" +
          maskToLdur(event.holdStartMask) +
          "  he:" +
          maskToLdur(event.holdEndMask)
      );
    }
    if (state.events.length > limit) {
      lines.push("... " + (state.events.length - limit) + " more rows");
    }
    ui.eventPreview.textContent = lines.join("\n");
  }

  async function loadManifest() {
    const manifestUrl = normalizePathToUrl("game-data/song-manifest.lsl.json");
    const payload = await fetchJsonNoCache(manifestUrl);
    const songs = Array.isArray(payload && payload.songs) ? payload.songs : [];
    state.songs = songs;
    fillSongSelect();
    fillDifficultySelect(state.currentSongId);
  }

  async function loadChartFromPath(path) {
    const indexUrl = normalizePathToUrl(path);
    if (!indexUrl) {
      throw new Error("Chart path is empty.");
    }

    const indexPayload = await fetchJsonNoCache(indexUrl);
    if (!indexPayload || indexPayload.fmt !== "sldr-chart-chunks-v1") {
      throw new Error("Unsupported chart index format.");
    }

    const chunkNames = Array.isArray(indexPayload.c) ? indexPayload.c : [];
    if (chunkNames.length <= 0) {
      throw new Error("Chart index contains no chunk files.");
    }

    const chunkPromises = chunkNames.map((chunkName) => {
      const chunkUrl = new URL(String(chunkName), indexUrl).toString();
      return fetchTextNoCache(chunkUrl);
    });
    const chunkBodies = await Promise.all(chunkPromises);
    const mergedChunkPayload = chunkBodies.join("");
    const rows = parseChunkRows(mergedChunkPayload);
    const decoded = decodeCondensedEvents(rows, indexPayload);

    state.chartIndex = indexPayload;
    state.events = decoded.events;
    state.notes = decoded.notes;
    state.holds = decoded.holds;
    state.durationSeconds = decoded.durationSeconds;
    resetPlayback(0);
    syncStats();
    updateEventPreview();

    setStatus(
      "Loaded " +
        String(indexPayload.id || "(unknown)") +
        " - " +
        String(indexPayload.d || "(difficulty)") +
        " | chunks=" +
        String(chunkNames.length)
    );
  }

  function beginPlayback() {
    if (state.durationSeconds <= 0) {
      return;
    }
    state.playing = true;
    state.playStartSongSeconds = state.currentSongSeconds;
    state.playStartMs = nowMs();
    syncPlayButton();
  }

  function pausePlayback() {
    if (!state.playing) {
      return;
    }
    state.playing = false;
    syncPlayButton();
  }

  function togglePlayback() {
    if (state.playing) {
      pausePlayback();
    } else {
      beginPlayback();
    }
  }

  function updatePlaybackClock(frameNowMs) {
    if (!state.playing) {
      return;
    }
    const elapsed = (frameNowMs - state.playStartMs) / 1000;
    state.currentSongSeconds = state.playStartSongSeconds + elapsed;
    if (state.currentSongSeconds >= state.durationSeconds) {
      state.currentSongSeconds = state.durationSeconds;
      pausePlayback();
    }
  }

  function laneX(lane, laneWidth) {
    return lane * laneWidth;
  }

  function drawArrow(ctx, x, y, size, lane) {
    if (state.arrowLoaded && state.arrowImage) {
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(LANE_ROTATIONS[lane]);
      ctx.drawImage(state.arrowImage, -size / 2, -size / 2, size, size);
      ctx.restore();
      return;
    }

    ctx.save();
    ctx.translate(x, y);
    ctx.rotate(LANE_ROTATIONS[lane]);
    ctx.beginPath();
    ctx.moveTo(0, -size * 0.48);
    ctx.lineTo(size * 0.42, size * 0.34);
    ctx.lineTo(size * 0.18, size * 0.34);
    ctx.lineTo(size * 0.18, size * 0.5);
    ctx.lineTo(-size * 0.18, size * 0.5);
    ctx.lineTo(-size * 0.18, size * 0.34);
    ctx.lineTo(-size * 0.42, size * 0.34);
    ctx.closePath();
    ctx.fillStyle = LANE_COLORS[lane];
    ctx.fill();
    ctx.restore();
  }

  function drawRoundedRect(ctx, x, y, width, height, radius) {
    const r = Math.min(radius, width * 0.5, height * 0.5);
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.lineTo(x + width - r, y);
    ctx.quadraticCurveTo(x + width, y, x + width, y + r);
    ctx.lineTo(x + width, y + height - r);
    ctx.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
    ctx.lineTo(x + r, y + height);
    ctx.quadraticCurveTo(x, y + height, x, y + height - r);
    ctx.lineTo(x, y + r);
    ctx.quadraticCurveTo(x, y, x + r, y);
    ctx.closePath();
  }

  function drawFrame() {
    const canvas = ui.chartCanvas;
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return;
    }

    const dpr = window.devicePixelRatio || 1;
    const cssWidth = Math.max(canvas.clientWidth, 320);
    const cssHeight = Math.max(canvas.clientHeight, 260);
    const pxWidth = Math.floor(cssWidth * dpr);
    const pxHeight = Math.floor(cssHeight * dpr);
    if (canvas.width !== pxWidth || canvas.height !== pxHeight) {
      canvas.width = pxWidth;
      canvas.height = pxHeight;
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const width = cssWidth;
    const height = cssHeight;
    const laneWidth = width / 4;
    const judgeY = Math.max(78, height * 0.19);
    const arrowSize = clamp(laneWidth * 0.44, 34, 86);
    const speed = state.scrollSpeed;
    const songTime = state.currentSongSeconds;
    const visibleAheadSeconds = (height - judgeY + arrowSize) / speed;
    const visibleBehindSeconds = (judgeY + arrowSize) / speed;
    const minTime = songTime - visibleBehindSeconds;
    const maxTime = songTime + visibleAheadSeconds;

    const bgGradient = ctx.createLinearGradient(0, 0, 0, height);
    bgGradient.addColorStop(0, "#051826");
    bgGradient.addColorStop(1, "#081320");
    ctx.fillStyle = bgGradient;
    ctx.fillRect(0, 0, width, height);

    let lane = 0;
    for (; lane < 4; lane += 1) {
      const x = laneX(lane, laneWidth);
      ctx.fillStyle = lane % 2 === 0 ? "rgba(255,255,255,0.03)" : "rgba(255,255,255,0.01)";
      ctx.fillRect(x, 0, laneWidth, height);
      ctx.strokeStyle = "rgba(255,255,255,0.12)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x + laneWidth, 0);
      ctx.lineTo(x + laneWidth, height);
      ctx.stroke();
    }

    const startGrid = Math.floor(minTime * 2) / 2;
    let gridTime = startGrid;
    for (; gridTime <= maxTime; gridTime += 0.5) {
      const y = judgeY + (gridTime - songTime) * speed;
      const isWholeSecond = Math.abs(gridTime - Math.round(gridTime)) < 0.01;
      ctx.strokeStyle = isWholeSecond ? "rgba(21,203,213,0.27)" : "rgba(255,255,255,0.09)";
      ctx.lineWidth = isWholeSecond ? 1.6 : 1;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(width, y);
      ctx.stroke();
    }

    state.holds.forEach((hold) => {
      const startSec = hold.startCs / 100;
      const endSec = hold.endCs / 100;
      if (endSec < minTime || startSec > maxTime) {
        return;
      }
      const yStart = judgeY + (startSec - songTime) * speed;
      const yEnd = judgeY + (endSec - songTime) * speed;
      const top = Math.min(yStart, yEnd);
      const bottom = Math.max(yStart, yEnd);
      const xCenter = laneX(hold.lane, laneWidth) + laneWidth * 0.5;
      const bodyWidth = laneWidth * 0.18;
      const bodyHeight = Math.max(bottom - top, 2);

      ctx.fillStyle = LANE_COLORS[hold.lane] + "88";
      drawRoundedRect(ctx, xCenter - bodyWidth * 0.5, top, bodyWidth, bodyHeight, 9);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.38)";
      ctx.lineWidth = 1;
      ctx.stroke();
    });

    state.notes.forEach((note) => {
      const noteSec = note.timeCs / 100;
      if (noteSec < minTime || noteSec > maxTime) {
        return;
      }
      const xCenter = laneX(note.lane, laneWidth) + laneWidth * 0.5;
      const y = judgeY + (noteSec - songTime) * speed;
      drawArrow(ctx, xCenter, y, arrowSize, note.lane);
    });

    ctx.strokeStyle = "#ffffff";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(0, judgeY);
    ctx.lineTo(width, judgeY);
    ctx.stroke();

    ctx.fillStyle = "rgba(255,255,255,0.88)";
    ctx.font = "700 14px Rajdhani, Segoe UI, sans-serif";
    lane = 0;
    for (; lane < 4; lane += 1) {
      const xCenter = laneX(lane, laneWidth) + laneWidth * 0.5;
      drawArrow(ctx, xCenter, judgeY, arrowSize * 0.78, lane);
      ctx.fillText(LANE_NAMES[lane], xCenter - 17, 22);
    }
  }

  function animationTick(tickNowMs) {
    state.rafId = window.requestAnimationFrame(animationTick);
    updatePlaybackClock(tickNowMs);
    if (ui.timeRange && !ui.timeRange.matches(":active")) {
      syncTimeSliderFromState();
    }
    drawFrame();
  }

  function bindEvents() {
    ui.songSelect.addEventListener("change", () => {
      state.currentSongId = ui.songSelect.value;
      fillDifficultySelect(state.currentSongId);
    });

    ui.difficultySelect.addEventListener("change", () => {
      updatePathFromManifestSelection();
    });

    ui.loadFromManifestBtn.addEventListener("click", async () => {
      try {
        const path = ui.chartPathInput.value;
        setStatus("Loading chart index + chunks...");
        await loadChartFromPath(path);
      } catch (error) {
        setStatus("Load failed: " + String(error && error.message ? error.message : error), true);
      }
    });

    ui.loadByPathBtn.addEventListener("click", async () => {
      try {
        setStatus("Loading chart index + chunks...");
        await loadChartFromPath(ui.chartPathInput.value);
      } catch (error) {
        setStatus("Load failed: " + String(error && error.message ? error.message : error), true);
      }
    });

    ui.playPauseBtn.addEventListener("click", () => {
      togglePlayback();
    });

    ui.restartBtn.addEventListener("click", () => {
      resetPlayback(0);
      drawFrame();
    });

    ui.timeRange.addEventListener("input", () => {
      const nextValue = parseFloat(ui.timeRange.value);
      if (Number.isFinite(nextValue)) {
        state.currentSongSeconds = clamp(nextValue, 0, state.durationSeconds);
        if (state.playing) {
          state.playStartSongSeconds = state.currentSongSeconds;
          state.playStartMs = nowMs();
        }
      }
      syncTimeSliderFromState();
    });

    ui.speedRange.addEventListener("input", () => {
      const nextSpeed = parseInt(ui.speedRange.value, 10);
      if (Number.isFinite(nextSpeed)) {
        state.scrollSpeed = clamp(nextSpeed, 120, 720);
        ui.speedValue.textContent = String(state.scrollSpeed) + " px/s";
      }
      drawFrame();
    });

    window.addEventListener("keydown", (event) => {
      if (event.key === " ") {
        event.preventDefault();
        togglePlayback();
      } else if (event.key === "r" || event.key === "R") {
        event.preventDefault();
        resetPlayback(0);
      }
    });
  }

  function bindUiRefs() {
    ui.songSelect = byId("songSelect");
    ui.difficultySelect = byId("difficultySelect");
    ui.chartPathInput = byId("chartPathInput");
    ui.loadFromManifestBtn = byId("loadFromManifestBtn");
    ui.loadByPathBtn = byId("loadByPathBtn");
    ui.playPauseBtn = byId("playPauseBtn");
    ui.restartBtn = byId("restartBtn");
    ui.timeRange = byId("timeRange");
    ui.speedRange = byId("speedRange");
    ui.speedValue = byId("speedValue");
    ui.statusText = byId("statusText");
    ui.durationValue = byId("durationValue");
    ui.notesValue = byId("notesValue");
    ui.holdsValue = byId("holdsValue");
    ui.eventsValue = byId("eventsValue");
    ui.timeValue = byId("timeValue");
    ui.eventPreview = byId("eventPreview");
    ui.chartCanvas = byId("chartCanvas");
  }

  function bootArrowImage() {
    const image = new Image();
    image.decoding = "async";
    image.src = "./assets/arrow.gif";
    image.addEventListener("load", () => {
      state.arrowLoaded = true;
      drawFrame();
    });
    image.addEventListener("error", () => {
      state.arrowLoaded = false;
      setStatus("Arrow image failed to load, using fallback vector arrows.", true);
    });
    state.arrowImage = image;
  }

  async function boot() {
    bindUiRefs();
    bindEvents();
    bootArrowImage();
    state.scrollSpeed = parseInt(ui.speedRange.value, 10);
    ui.speedValue.textContent = String(state.scrollSpeed) + " px/s";
    syncPlayButton();
    syncStats();
    updateEventPreview();
    drawFrame();

    try {
      setStatus("Loading manifest...");
      await loadManifest();
      setStatus("Manifest loaded. Pick a chart and click Load.");
    } catch (error) {
      setStatus(
        "Manifest load failed. Use Chart Index Path directly. Error: " +
          String(error && error.message ? error.message : error),
        true
      );
    }

    if (state.rafId === 0) {
      state.rafId = window.requestAnimationFrame(animationTick);
    }
  }

  window.addEventListener("DOMContentLoaded", () => {
    boot();
  });
})();
