(() => {
  "use strict";

  function query() {
    return new URLSearchParams(window.location.search);
  }

  function getParam(params, key, fallback = "") {
    const value = params.get(key);
    return value === null ? fallback : value;
  }

  function toNumber(value, fallback = 0) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
  }

  function toPercentText(value) {
    return `${toNumber(value, 0).toFixed(2)}%`;
  }

  function decodeMaybeJson(value, fallback = null) {
    if (!value) return fallback;
    try {
      return JSON.parse(value);
    } catch (_err) {
      return fallback;
    }
  }

  function setText(id, text) {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  }

  function setAttr(id, attr, value) {
    const el = document.getElementById(id);
    if (el) el.setAttribute(attr, value);
  }

  function hashSeed(input) {
    let h = 0;
    for (let i = 0; i < input.length; i += 1) {
      h = (h << 5) - h + input.charCodeAt(i);
      h |= 0;
    }
    return Math.abs(h);
  }

  function applyThemeSeed(seedText) {
    const hue = hashSeed(seedText || "sldr") % 360;
    const root = document.documentElement;
    root.style.setProperty("--accent-a", `hsl(${hue} 95% 60%)`);
    root.style.setProperty("--accent-b", `hsl(${(hue + 42) % 360} 95% 64%)`);
    root.style.setProperty("--accent-c", `hsl(${(hue + 312) % 360} 95% 62%)`);
  }

  function radarNormalize(values, length = 5) {
    const out = [];
    for (let i = 0; i < length; i += 1) {
      const raw = Array.isArray(values) ? values[i] : 0;
      const v = Number(raw);
      out.push(Math.max(0, Math.min(1, Number.isFinite(v) ? v : 0)));
    }
    return out;
  }

  function drawRadar(canvas, options) {
    if (!canvas || !canvas.getContext) return;
    const ctx = canvas.getContext("2d");
    const dpr = window.devicePixelRatio || 1;
    const size = Math.min(canvas.clientWidth || 420, 420);
    canvas.width = Math.floor(size * dpr);
    canvas.height = Math.floor(size * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const w = size;
    const h = size;
    const cx = w / 2;
    const cy = h / 2;
    const radius = w * 0.35;
    const labels = options.labels || ["Stream", "Voltage", "Air", "Freeze", "Chaos"];
    const rings = 5;

    ctx.clearRect(0, 0, w, h);
    ctx.lineWidth = 1;
    ctx.strokeStyle = "rgba(236,243,250,0.20)";

    for (let ring = 1; ring <= rings; ring += 1) {
      const r = (radius * ring) / rings;
      ctx.beginPath();
      for (let i = 0; i < labels.length; i += 1) {
        const angle = -Math.PI / 2 + (Math.PI * 2 * i) / labels.length;
        const x = cx + Math.cos(angle) * r;
        const y = cy + Math.sin(angle) * r;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.stroke();
    }

    for (let i = 0; i < labels.length; i += 1) {
      const angle = -Math.PI / 2 + (Math.PI * 2 * i) / labels.length;
      const x = cx + Math.cos(angle) * radius;
      const y = cy + Math.sin(angle) * radius;

      ctx.beginPath();
      ctx.moveTo(cx, cy);
      ctx.lineTo(x, y);
      ctx.stroke();

      const lx = cx + Math.cos(angle) * (radius + 22);
      const ly = cy + Math.sin(angle) * (radius + 22);
      ctx.fillStyle = "rgba(236,243,250,0.82)";
      ctx.font = '600 12px "Rajdhani", sans-serif';
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(labels[i], lx, ly);
    }

    (options.datasets || []).forEach((set) => {
      const values = radarNormalize(set.values, labels.length);
      ctx.beginPath();
      for (let i = 0; i < labels.length; i += 1) {
        const angle = -Math.PI / 2 + (Math.PI * 2 * i) / labels.length;
        const r = values[i] * radius;
        const x = cx + Math.cos(angle) * r;
        const y = cy + Math.sin(angle) * r;
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.strokeStyle = set.stroke || "#15d7ff";
      ctx.fillStyle = set.fill || "rgba(21,215,255,0.2)";
      ctx.lineWidth = 2;
      ctx.fill();
      ctx.stroke();
    });
  }

  window.SLDR = {
    query,
    getParam,
    toNumber,
    toPercentText,
    decodeMaybeJson,
    setText,
    setAttr,
    applyThemeSeed,
    drawRadar
  };
})();
