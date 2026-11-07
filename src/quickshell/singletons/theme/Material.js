// Material 3 dynamic colour for Meander's "Material" preset.
//
// Ported from Omacale's core/Colours.qml: a Material 3 scheme seeded with the
// Omarchy theme's accent, so the shell recolours itself on `omarchy theme
// set`. HCT tone == CIELAB L*, so tonal palettes are built in CIELAB LCh with
// the seed's hue, then chroma-reduced until each colour fits in sRGB.
//
// Meander's palette has Catppuccin-style roles (base, surfaces, overlays,
// text, named accents) rather than M3's, so each role takes the M3 tone that
// matches its job: surfaces from the neutral palette at Catppuccin's
// lightness steps, the primary/tertiary accents from the scheme, and the named
// accents (red, green, ...) at their own hue, harmonised towards the seed.
.pragma library

function lin(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function gam(c) { return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055; }
function fLab(t) { return t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116; }
function fLabInv(t) { return t * t * t > 216 / 24389 ? t * t * t : (116 * t - 16) / (24389 / 27); }

function parseHex(hex) {
    let h = String(hex || "").replace("#", "");
    if (h.length === 8) h = h.substring(2);
    if (h.length !== 6) return { r: 0.5, g: 0.5, b: 0.5 };
    return {
        r: parseInt(h.substring(0, 2), 16) / 255,
        g: parseInt(h.substring(2, 4), 16) / 255,
        b: parseInt(h.substring(4, 6), 16) / 255
    };
}

function toLch(c) {
    const r = lin(c.r), g = lin(c.g), b = lin(c.b);
    const x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    const y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b);
    const z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
    const fx = fLab(x), fy = fLab(y), fz = fLab(z);
    const L = 116 * fy - 16, A = 500 * (fx - fy), B = 200 * (fy - fz);
    return { l: L, c: Math.sqrt(A * A + B * B), h: (Math.atan2(B, A) * 180 / Math.PI + 360) % 360 };
}

function lchToRgb(L, C, h) {
    const hr = h * Math.PI / 180;
    const A = C * Math.cos(hr), B = C * Math.sin(hr);
    const fy = (L + 16) / 116, fx = fy + A / 500, fz = fy - B / 200;
    const x = fLabInv(fx) * 0.95047, y = L > 8 ? fy * fy * fy : L / (24389 / 27), z = fLabInv(fz) * 1.08883;
    return [
        3.2404542 * x - 1.5371385 * y - 0.4985314 * z,
        -0.9692660 * x + 1.8760108 * y + 0.0415560 * z,
        0.0556434 * x - 0.2040259 * y + 1.0572252 * z
    ];
}

function inGamut(v) {
    return v[0] >= -1e-4 && v[0] <= 1.0001 && v[1] >= -1e-4 && v[1] <= 1.0001 && v[2] >= -1e-4 && v[2] <= 1.0001;
}

function toHex(v) {
    const cl = x => Math.max(0, Math.min(1, gam(Math.max(0, x))));
    const h = x => { const s = Math.round(cl(x) * 255).toString(16); return s.length < 2 ? "0" + s : s; };
    return "#" + h(v[0]) + h(v[1]) + h(v[2]);
}

// The colour at tone t of a {h, c} palette, as "#rrggbb".
function tone(pal, t) {
    if (t <= 0) return "#000000";
    if (t >= 100) return "#ffffff";
    let lo = 0, hi = pal.c, v = lchToRgb(t, hi, pal.h);
    if (!inGamut(v)) {
        for (let i = 0; i < 18; i++) {
            const mid = (lo + hi) / 2;
            if (inGamut(lchToRgb(t, mid, pal.h))) lo = mid; else hi = mid;
        }
        v = lchToRgb(t, lo, pal.h);
    }
    return toHex(v);
}

// LCh chroma runs ~10% hotter than HCT chroma; scale the M3 targets down.
const K = 0.9;

const VARIANTS = ["tonalspot", "vibrant", "expressive", "fidelity", "content", "neutral", "monochrome", "rainbow", "fruitsalad"];

// [primary, secondary, tertiary, neutral, neutralVariant] per Material's
// dynamic scheme variants, plus the chroma for the named accents.
function palettes(seed, variant) {
    const h = seed.h, c = seed.c;
    const hue = d => ((h + d) % 360 + 360) % 360;
    const P = (dh, ch) => ({ h: hue(dh), c: ch * K });
    switch (variant) {
    case "vibrant": return { p: [P(0, 200), P(15, 24), P(60, 32), P(0, 10), P(0, 12)], accent: 60 };
    case "expressive": return { p: [P(240, 40), P(15, 24), P(90, 32), P(15, 8), P(15, 12)], accent: 44 };
    case "fidelity": return { p: [P(0, Math.max(c, 36)), P(0, Math.max(c - 32, c * 0.5)), P(60, Math.max(c * 0.6, 24)), P(0, c / 8), P(0, c / 8 + 4)], accent: 40 };
    case "content": return { p: [P(0, c), P(0, Math.max(c - 32, c * 0.5)), P(60, Math.max(c * 0.6, 24)), P(0, c / 8), P(0, c / 8 + 4)], accent: 40 };
    case "neutral": return { p: [P(0, 12), P(0, 8), P(0, 16), P(0, 2), P(0, 2)], accent: 16 };
    case "monochrome": return { p: [P(0, 0), P(0, 0), P(0, 0), P(0, 0), P(0, 0)], accent: 0 };
    case "rainbow": return { p: [P(0, 48), P(0, 16), P(60, 24), P(0, 0), P(0, 0)], accent: 44 };
    case "fruitsalad": return { p: [P(-50, 48), P(-50, 36), P(0, 36), P(0, 10), P(0, 16)], accent: 44 };
    default: return { p: [P(0, Math.max(36, c)), P(0, 16), P(60, 24), P(0, 6), P(0, 8)], accent: 40 };
    }
}

// Material's harmonize: turn a fixed hue up to 15° towards the seed.
function harmonize(fixedHue, seedHue) {
    let d = ((seedHue - fixedHue + 540) % 360) - 180;
    return ((fixedHue + Math.max(-15, Math.min(15, d * 0.5))) % 360 + 360) % 360;
}

// Meander's 22 palette roles from a seed colour.
function scheme(seedHex, variant, light) {
    const seed = toLch(parseHex(seedHex));
    const v = VARIANTS.indexOf(variant) >= 0 ? variant : "tonalspot";
    const pp = palettes(seed, v);
    const [pP, pS, pT, pN, pNV] = pp.p;
    // Catppuccin's lightness steps (Mocha for dark, Latte for light).
    const T = light
        ? { base: 96, mantle: 93, crust: 90, s0: 86, s1: 81, s2: 75, o0: 66, o1: 60, o2: 54, st0: 44, st1: 36, text: 18, accent: 42, pink: 50 }
        : { base: 8, mantle: 6, crust: 4, s0: 16, s1: 22, s2: 28, o0: 44, o1: 52, o2: 60, st0: 70, st1: 78, text: 90, accent: 80, pink: 86 };
    const named = h => tone({ h: harmonize(h, seed.h), c: pp.accent * K }, T.accent);
    return {
        "base": tone(pN, T.base),
        "mantle": tone(pN, T.mantle),
        "crust": tone(pN, T.crust),
        "surface0": tone(pN, T.s0),
        "surface1": tone(pN, T.s1),
        "surface2": tone(pNV, T.s2),
        "overlay0": tone(pNV, T.o0),
        "overlay1": tone(pNV, T.o1),
        "overlay2": tone(pNV, T.o2),
        "subtext0": tone(pNV, T.st0),
        "subtext1": tone(pNV, T.st1),
        "text": tone(pN, T.text),
        // Meander's primary colour role is "blue".
        "blue": tone(pP, T.accent),
        "sapphire": tone(pS, T.accent),
        "mauve": tone(pT, T.accent),
        "pink": tone(pT, T.pink),
        "red": tone({ h: 25, c: 84 * K }, T.accent),
        "maroon": named(10),
        "peach": named(55),
        "yellow": named(90),
        "green": named(145),
        "teal": named(185)
    };
}

// Settings › Theme › Pure black: dark palettes only. Base, mantle and crust go
// to #000 and the surface steps to neutral greys just above it, so cards and
// hover states still read on black.
function pureBlack(palette) {
    const b = parseHex(palette.base);
    const lum = 0.2126 * b.r + 0.7152 * b.g + 0.0722 * b.b;
    if (lum > 0.4) return palette;
    const out = {};
    for (const k in palette) out[k] = palette[k];
    out.base = "#000000";
    out.mantle = "#000000";
    out.crust = "#000000";
    out.surface0 = "#141414";
    out.surface1 = "#1f1f1f";
    out.surface2 = "#2a2a2a";
    return out;
}
