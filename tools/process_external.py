"""Обработка внешних ассетов (CC0-звуки BigSoundBank, PD-картины Wikimedia) и процедурная генерация
горрор-текстур и звуков для уровня «Догорающая свеча».

Запуск (нужны numpy и ffmpeg в PATH; numpy есть в Python из Blender):
  "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/process_external.py [audio] [textures] [refs] [stage3] [stage4] [stage5] [stage6]

Вход:  assets/external/{audio,paintings}  (исходники, см. assets/external/LICENSES.md)
Выход: assets/horror/{audio,textures}     (перезаписывается)
"""

import math
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_A = os.path.join(ROOT, "assets", "external", "audio")
SRC_P = os.path.join(ROOT, "assets", "external", "paintings")
OUT_A = os.path.join(ROOT, "assets", "horror", "audio")
OUT_T = os.path.join(ROOT, "assets", "horror", "textures")
SR = 44100
TAU = math.tau


def log(msg):
    print("[horror] " + msg, flush=True)


# ---------------------------------------------------------------------------
# Ввод-вывод через ffmpeg
# ---------------------------------------------------------------------------

def ff(args, data=None):
    r = subprocess.run(["ffmpeg", "-loglevel", "error", "-y"] + args, input=data, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("ffmpeg: " + r.stderr.decode("utf-8", "replace"))
    return r.stdout


def load_audio(name):
    raw = ff(["-i", os.path.join(SRC_A, name + ".ogg"), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"])
    return np.frombuffer(raw, np.float32).astype(np.float64)


def save_audio(name, x, peak_db=-3.0):
    """Нормализация по пику и запись в OGG Vorbis (моно, 44.1 кГц)."""
    x = np.asarray(x, np.float64)
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    ff(["-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "libvorbis", "-q:a", "6",
        os.path.join(OUT_A, name + ".ogg")], x.astype(np.float32).tobytes())


def load_img(path, w=None, h=None, crop=None):
    """Картинка → массив RGB 0..1. crop = (x0, y0, ширина) в долях исходника, высота — по пропорции w:h."""
    vf = []
    if crop:
        x0, y0, cw = crop
        vf.append(f"crop=iw*{cw}:iw*{cw}*{h}/{w}:iw*{x0}:ih*{y0}")
    if w:
        vf.append(f"scale={w}:{h}:flags=lanczos")
    if not w:
        probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                "stream=width,height", "-of", "csv=p=0", path], capture_output=True, text=True)
        w, h = map(int, probe.stdout.strip().split(","))
    args = ["-i", path] + (["-vf", ",".join(vf)] if vf else []) + ["-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    raw = ff(args)
    return np.frombuffer(raw, np.uint8).reshape(h, w, 3).astype(np.float64) / 255.0


def save_img(name, arr, quality=3):
    """RGB → .jpg, RGBA → .png."""
    arr = np.clip(arr, 0, 1)
    if arr.ndim == 2:
        arr = np.dstack([arr] * 3)
    h, w, c = arr.shape
    fmt = "rgba" if c == 4 else "rgb24"
    ext = ".png" if c == 4 else ".jpg"
    extra = [] if c == 4 else ["-q:v", str(quality)]
    ff(["-f", "rawvideo", "-pix_fmt", fmt, "-s", f"{w}x{h}", "-i", "-"] + extra + [os.path.join(OUT_T, name + ext)],
       (arr * 255 + .5).astype(np.uint8).tobytes())


# ---------------------------------------------------------------------------
# Обработка сигналов
# ---------------------------------------------------------------------------

def smooth(x, n):
    return np.convolve(x, np.ones(n) / n, mode="same")


def lowpass(x, hz):
    """Однополюсный ФНЧ через свёртку с экспонентой."""
    tau = SR / (TAU * hz)
    k = np.exp(-np.arange(int(tau * 6) + 1) / tau)
    return np.convolve(x, k / k.sum())[:len(x)]


def highpass(x, hz):
    return x - lowpass(x, hz)


def onsets(x, min_gap=0.25, rel=0.3):
    """Начала ударов (шагов, тиков): пересечения огибающей порога снизу вверх."""
    env = smooth(np.abs(x), int(SR * 0.008))
    above = env > env.max() * rel
    out, last = [], -1e9
    for i in np.flatnonzero(above[1:] & ~above[:-1]):
        if i - last > min_gap * SR:
            out.append(int(i))
            last = i
    return out, env


def slice_hits(x, length, count, min_gap=0.25, rel=0.3, pre=0.012):
    """Нарезка отдельных ударов: окно от атаки с затуханием; берём ближайшие к медиане по громкости."""
    pos, _ = onsets(x, min_gap, rel)
    n = int(length * SR)
    fade, att = int(0.08 * SR), int(0.003 * SR)
    hits = []
    for p in pos:
        a = max(0, p - int(pre * SR))
        seg = x[a:a + n].copy()
        if len(seg) < n:
            continue
        seg[-fade:] *= np.linspace(1, 0, fade) ** 2
        seg[:att] *= np.linspace(0, 1, att)
        hits.append((np.abs(seg).max(), seg))
    if not hits:
        return [], len(pos)
    med = np.median([h[0] for h in hits])
    hits.sort(key=lambda h: abs(h[0] - med))
    return [h[1] for h in hits[:count]], len(pos)


def loop_crossfade(x, cf):
    n = int(cf * SR)
    y = x[:-n].copy()
    t = np.linspace(0, 1, n)
    y[:n] = x[:n] * np.sqrt(t) + x[-n:] * np.sqrt(1 - t)
    return y


def reverb_tail(x, seconds=2.5, mix=0.35, seed=1):
    """Простая свёртка с затухающим шумом — «зал» для стингеров."""
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    ir = lowpass(rng.standard_normal(n) * np.exp(-np.arange(n) / (SR * seconds / 6)), 3500)
    wet = np.convolve(x, ir)
    out = np.zeros(len(wet))
    out[:len(x)] += x * (1 - mix)
    out += wet / (np.abs(wet).max() + 1e-9) * np.abs(x).max() * mix
    return out


# ---------------------------------------------------------------------------
# Звук
# ---------------------------------------------------------------------------

def audio_steps():
    for src, prefix, length, count, gap, rel in (("steps_stone", "step_stone", .38, 6, .3, .25),
                                                  ("steps_wood_a", "step_wood", .5, 4, .3, .25),
                                                  ("steps_wood_b", "step_wood_b", .5, 3, .3, .3),
                                                  ("run_concrete_a", "run", .3, 6, .15, .3)):
        x = highpass(load_audio(src), 70)
        hits, found = slice_hits(x, length, count, gap, rel)
        for i, h in enumerate(hits):
            save_audio(f"{prefix}_{i + 1:02d}", h, -2.0)
        log(f"{src}: найдено ударов {found}, сохранено {len(hits)}")


def audio_clock():
    """Петля тиканья ровно по чётному числу ударов (тик-так), без двойных щелчков на стыке."""
    x = load_audio("clock_tick")
    pos, _ = onsets(x, .4, .35)
    if len(pos) < 6:
        raise RuntimeError(f"часы: слишком мало ударов ({len(pos)})")
    a, b = pos[1], pos[1 + 2 * ((len(pos) - 3) // 2)]
    pre = int(.01 * SR)
    seg = x[a - pre:b - pre]
    save_audio("clock_tick_loop", seg, -3.0)
    log(f"часы: ударов {len(pos)}, петля {len(seg) / SR:.2f} с")


def audio_loops():
    for src, name, cf, hp, cut in (("wind_whistle", "wind_loop", 3.0, 120, None), ("fireplace", "fire_loop", 1.5, 40, None),
                                   ("heartbeat", "heartbeat_loop", .3, 30, 12.0)):
        x = highpass(load_audio(src), hp)
        if cut:
            x = x[:int(cut * SR)]
        save_audio(name, loop_crossfade(x, cf), -4.0)
        log(f"петля {name}: {len(x) / SR:.1f} с")


def audio_oneshots():
    # Скрип балок: самые «активные» отрезки каната (контактный микрофон звучит как старое дерево)
    x = highpass(load_audio("beam_creak"), 90)
    env = smooth(np.abs(x), int(SR * .05))
    taken = 0
    for _ in range(40):
        i = int(np.argmax(env))
        a, b = max(0, i - int(.6 * SR)), min(len(x), i + int(1.4 * SR))
        seg = x[a:b].copy()
        env[max(0, a - SR):b + SR] = 0
        if len(seg) < SR:
            continue
        ramp = np.minimum(np.arange(len(seg)), np.arange(len(seg))[::-1]) / (.15 * SR)
        taken += 1
        save_audio(f"creak_beam_{taken:02d}", lowpass(seg * np.minimum(1, ramp), 2500), -6.0)
        if taken == 4:
            break
    x = highpass(load_audio("floor_squeak"), 90)
    hits, _ = slice_hits(x, 1.2, 3, .8, .25)
    for i, h in enumerate(hits):
        save_audio(f"creak_floor_{i + 1:02d}", h, -6.0)
    save_audio("door_creak", highpass(load_audio("door_creak"), 60), -3.0)
    # Порыв сквозняка в арке: самый плотный участок свиста + вибрация деревянной двери
    w = highpass(load_audio("wind_whistle"), 150)
    env = smooth(np.abs(w), int(SR * .5))
    i = max(int(np.argmax(env)), 2 * SR)
    g = w[i - 2 * SR:i + 2 * SR].copy()
    g *= np.sin(np.linspace(0, np.pi, len(g))) ** 1.5
    v = highpass(load_audio("wood_vibration"), 60)[:len(g)]
    g[:len(v)] += v / (np.abs(v).max() + 1e-9) * np.abs(g).max() * .5 * np.sin(np.linspace(0, np.pi, len(v)))
    save_audio("draft_gust", g, -3.0)
    for k in (1, 2):
        save_audio(f"whisper_{k}", highpass(load_audio(f"whisper_{k}"), 180), -3.0)
    log(f"разовые звуки: балки {taken}, пол {len(hits)}, дверь, сквозняк, шёпот")


def synth_drone():
    """Фоновый гул дома: биения низких тонов (целое число периодов в петле) + «дыхание» шума."""
    T = 24.0
    t = np.arange(int(T * SR)) / SR
    rng = np.random.default_rng(7)

    def tone(f, amp, lfo):
        f = round(f * T) / T       # целое число периодов — бесшовная петля
        return amp * np.sin(TAU * f * t) * (0.75 + 0.25 * np.sin(TAU * t / T * lfo))

    x = tone(41.2, .5, 1) + tone(43.65, .35, 2) + tone(61.7, .18, 3) + tone(82.4, .08, 1) + tone(116.5, .04, 2)
    noise = loop_crossfade(lowpass(rng.standard_normal(len(t) + SR * 4), 240), 4.0)[:len(t)]
    x += noise / np.abs(noise).max() * .22 * (0.6 + 0.4 * np.sin(TAU * t / T * 2 + 1))
    save_audio("drone_loop", x, -6.0)
    log("синтез: гул")


def _cluster(t, freqs, vib=5.0, depth=.006):
    """Кластер «смычковых» тонов: пила из гармоник с вибрато."""
    out = np.zeros_like(t)
    for k, f in enumerate(freqs):
        ph = TAU * f * t + depth * f / vib * np.sin(TAU * vib * t + k)
        out += sum(np.sin(ph * h) / h for h in range(1, 7))
    return out / len(freqs)


def synth_stingers():
    rng = np.random.default_rng(11)
    # Окно: резкий диссонансный «визг» струнных + низкий удар
    t = np.arange(int(2.2 * SR)) / SR
    s = _cluster(t, [740, 784, 831, 880, 932], 7, .01) * np.exp(-t / .6) * np.minimum(1, t / .004)
    s += np.sin(TAU * (60 - 20 * t) * t) * np.exp(-t / .35) * 1.2
    s += lowpass(rng.standard_normal(len(t)), 2000) * np.exp(-t / .08) * .8
    save_audio("stinger_window", reverb_tail(s, 2.5, .4, 1), -1.0)
    # Зеркало: медленное нарастание (как обратная реверберация) с обрывом в тишину
    t = np.arange(int(3.2 * SR)) / SR
    s = (_cluster(t, [196, 207.7, 277.2, 293.7], 4, .008) + lowpass(rng.standard_normal(len(t)), 900) * .6) * (t / t[-1]) ** 3
    s[-int(.02 * SR):] *= np.linspace(1, 0, int(.02 * SR))
    save_audio("stinger_mirror", s, -2.0)
    # Низкий «бум» — акцент для шагов во тьме
    t = np.arange(int(1.6 * SR)) / SR
    s = np.sin(TAU * (48 - 14 * t) * t) * np.exp(-t / .5) + lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t / .2) * .5
    save_audio("stinger_low", reverb_tail(s, 3.0, .5, 2), -1.0)
    # Скрежет камня (статуя): зернистый отфильтрованный шум
    t = np.arange(int(1.4 * SR)) / SR
    grains = np.convolve((rng.random(len(t)) < .004).astype(float), np.exp(-np.arange(400) / 60))[:len(t)]
    s = (lowpass(rng.standard_normal(len(t)), 700) * .5 + grains * rng.standard_normal(len(t))) * np.sin(np.pi * t / t[-1])
    save_audio("stone_grind", highpass(s, 80), -4.0)
    log("синтез: стингеры, скрежет камня")


# ---------------------------------------------------------------------------
# Текстуры: общие шумы (как в GothicManorAssets/scripts/build_assets.py)
# ---------------------------------------------------------------------------

def pnoise(w, h, sigma, seed):
    """Бесшовный шум: белый шум, сглаженный гауссом в частотной области."""
    r = np.random.default_rng(seed).standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    n = np.real(np.fft.ifft2(np.fft.fft2(r) * np.exp(-2 * (np.pi * sigma) ** 2 * (fx ** 2 + fy ** 2))))
    return (n - n.min()) / (n.max() - n.min() + 1e-9)


def fbm(w, h, seed, sigmas=(48, 20, 8, 3), weights=(.5, .25, .15, .1)):
    return sum(wt * pnoise(w, h, s, seed + i) for i, (s, wt) in enumerate(zip(sigmas, weights)))


def lum(a):
    return a[..., 0] * .2126 + a[..., 1] * .7152 + a[..., 2] * .0722


def h2n(h, strength):
    """Карта высот → карта нормалей (OpenGL, как ждёт Godot)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * .5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * .5 * strength
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * .5 + .5


def blur(a, r):
    """Размытие прямоугольником по обеим осям (через накопленные суммы)."""
    for axis in (0, 1):
        c = np.cumsum(np.pad(a, [(r + 1, r) if ax == axis else (0, 0) for ax in (0, 1)], mode="edge"), axis=axis)
        hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
        lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
        a = (hi - lo) / (2 * r + 1)
    return a


def sample(img, sx, sy):
    """Билинейная выборка img в дробных координатах (для искажений)."""
    h, w = img.shape[:2]
    sx = np.clip(sx, 0, w - 1.001)
    sy = np.clip(sy, 0, h - 1.001)
    x0, y0 = sx.astype(int), sy.astype(int)
    fx, fy = (sx - x0)[..., None], (sy - y0)[..., None]
    a = img[y0, x0] * (1 - fx) + img[y0, x0 + 1] * fx
    b = img[y0 + 1, x0] * (1 - fx) + img[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def grid(w, h):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    return x, y


# ---------------------------------------------------------------------------
# Картины
# ---------------------------------------------------------------------------

PW, PH = 1024, 1410
## Кадрирование (x0, y0, ширина в долях исходника) и «оплывание» лица (u, v, радиус, сила) в долях кадра.
## Координаты глаз следящих портретов — в scripts/portrait.gd (под эти же кадры).
PAINTINGS = {
    "rembrandt": ((.12, .05, .62), None),
    "innocent": ((.22, .12, .36), None),
    "lady_blue": ((.17, .05, .60), None),
    "bocklin": ((.15, .0, .85), None),
    "saturn": ((.0, .0, 1.0), (.36, .16, .09, .5)),
    "leocadia": ((.0, .0, .62), (.27, .17, .075, 1.0)),
    "witches": ((.05, .04, .75), (.62, .3, .12, .6)),
    "nightmare": ((.1, .03, .85), (.57, .14, .08, .8)),
    "tetschen": ((.18, .15, .64), None),
}


def melt(img, cu, cv, r, k):
    """«Оплывшее» лицо: закрутка и стекание вниз внутри круга (cu, cv, r)."""
    x, y = grid(PW, PH)
    dx, dy = x / PW - cu, (y - cv * PH) / PW
    f = np.clip(1 - np.hypot(dx, dy) / r, 0, 1) ** 2 * k
    ang = f * 1.6
    sx = cu * PW + (dx * np.cos(ang) - dy * np.sin(ang)) * PW
    sy = cv * PH + (dx * np.sin(ang) + dy * np.cos(ang)) * PW - f * r * PW * .55 * (pnoise(PW, PH, 6, 9) + .3)
    return sample(img, sx, sy)


def tex_canvas_common():
    """Общие для всех полотен рельеф холста с кракелюром и шероховатость."""
    x, y = grid(PW, PH)
    crack = (np.abs(pnoise(PW, PH, 5, 52) - .5) < .0045) | (np.abs(pnoise(PW, PH, 14, 56) - .5) < .003)
    weave = np.sin(TAU * x / 5) * np.sin(TAU * y / 5) * .25
    save_img("canvas_normal", h2n(weave + pnoise(PW, PH, 3, 57) * .8 - crack * .7, 2.5))
    save_img("canvas_rough", np.clip(.32 + .2 * pnoise(PW, PH, 40, 55) + crack * .4, 0, 1))
    return crack


def tex_paintings():
    crack = tex_canvas_common()
    x, y = grid(PW, PH)
    u, v = x / PW, y / PH
    vign = np.clip(1.25 - np.hypot(u - .5, (v - .45) * 1.1) * 1.25, .25, 1)
    for i, (name, (crop, distort)) in enumerate(PAINTINGS.items()):
        img = load_img(os.path.join(SRC_P, name + ".jpg"), PW, PH, crop)
        if distort:
            img = melt(img, *distort)
        # Тёмный пожелтевший лак, приглушённые цвета, копоть по краям, кракелюр
        img = img * .7 + lum(img)[..., None] * .3
        img = np.clip(img, 0, 1) ** 1.18 * .92
        img *= np.array([1, .93, .78]) * (.8 + .32 * fbm(PW, PH, 60 + i, sigmas=(120, 50, 12, 4)))[..., None]
        img *= vign[..., None]
        img[crack] *= .5
        save_img("painting_" + name, img, 2)
    log(f"картины: {len(PAINTINGS)}")


# ---------------------------------------------------------------------------
# Паутина
# ---------------------------------------------------------------------------

def web_layer(S, cx, cy, scale, seed, spokes=19, rings=24):
    """Одна сеть: радиальные нити и провисающая ловчая спираль, с разрывами."""
    rr = np.random.default_rng(seed)
    x, y = grid(S, S)
    dx, dy = (x - cx * S) / (S * scale), (y - cy * S) / (S * scale)
    r = np.hypot(dx, dy)
    th = np.arctan2(dy, dx) % TAU
    angs = np.sort((np.arange(spokes) + rr.uniform(-.3, .3, spokes)) * TAU / spokes % TAU)
    w = .9 / (S * scale)
    rad = np.zeros_like(r)
    for a in angs:
        dist = r * np.abs(np.sin(th - a))
        rad = np.maximum(rad, np.clip(1 - dist / w, 0, 1) * (np.cos(th - a) > 0) * rr.uniform(.6, 1))
    idx = np.searchsorted(angs, th)
    a0, a1 = angs[(idx - 1) % spokes], angs[idx % spokes]
    frac = ((th - a0) % TAU) / ((a1 - a0) % TAU + 1e-9)
    sag = 1 - .12 * np.sin(np.pi * frac) - .03 * np.sin(th)
    spiral = np.zeros_like(r)
    for j in range(1, rings):
        rj = .03 + j * .019 + rr.uniform(-.003, .003)
        spiral = np.maximum(spiral, np.clip(1 - np.abs(r - rj * sag) / w, 0, 1) * rr.uniform(.5, 1))
    web = np.maximum(rad * np.clip(1 - r / .6, 0, 1) ** .4, spiral * (r < .46))
    return web * (pnoise(S, S, 22, seed + 1) > .36)


def strands(S, count, seed):
    """Провисающие одиночные нити (цепные линии)."""
    rr = np.random.default_rng(seed)
    out = np.zeros((S, S))
    for _ in range(count):
        x0, x1 = sorted(rr.uniform(0, S, 2))
        y0, y1 = rr.uniform(0, S * .5, 2)
        sag = rr.uniform(.02, .2) * S
        t = np.linspace(0, 1, int((x1 - x0) * 2) + 2)
        xi = (x0 + (x1 - x0) * t).astype(int).clip(0, S - 1)
        yi = (y0 + (y1 - y0) * t + sag * 4 * t * (1 - t)).astype(int).clip(0, S - 1)
        out[yi, xi] = np.maximum(out[yi, xi], rr.uniform(.4, .9))
    return blur(out, 1) * 2.2


def tex_cobweb():
    """Паутина: две перекрывающиеся сети, провисающие нити и пыль; альфа-маска + карта нормалей нитей."""
    S = 1024
    web = np.maximum(web_layer(S, .5, .38, 1.0, 71), web_layer(S, .22, .2, .55, 75, 13, 16) * .8)
    web = np.maximum(web, np.clip(strands(S, 26, 77), 0, 1))
    x, y = grid(S, S)
    r = np.hypot(x / S - .5, y / S - .38)
    dust = np.clip((fbm(S, S, 79, sigmas=(40, 16, 5, 2)) - .45) * 1.6, 0, 1) * np.clip(1 - r / .45, 0, 1) * .35
    clumps = np.clip((pnoise(S, S, 4, 81) - .82) * 6, 0, 1) * (web > .2)
    border = np.clip(np.minimum(np.minimum(x, S - 1 - x), np.minimum(y, S - 1 - y)) / 10, 0, 1)
    alpha = np.clip(web * .9 + dust * .5 + clumps, 0, 1) * border
    tone = .78 + .2 * pnoise(S, S, 30, 83)
    rgb = np.dstack([tone * .95, tone * .93, tone * .88]) * (1 - dust[..., None] * .5)
    save_img("cobweb_albedo", np.dstack([rgb, alpha]))
    save_img("cobweb_normal", h2n(blur(web, 1) + clumps * .6, 6))
    log("паутина: альфа + нормали")


# ---------------------------------------------------------------------------
# Вид из окон
# ---------------------------------------------------------------------------

def night_grade(img, moon_uv=None, seed=0):
    """Картина → ночь: холодный лунный свет, глубокие тени, туман у земли, луна с ореолом."""
    h, w = img.shape[:2]
    x, y = grid(w, h)
    u, v = x / w, y / h
    l = lum(img)
    night = np.dstack([l * .55, l * .68, l * .95]) ** 1.35 * .75
    fog = np.clip((v - .62) * 2.4, 0, 1) * (.5 + .5 * pnoise(w, h, 60, seed)) * .12
    night += np.array([.10, .12, .16]) * fog[..., None]
    if moon_uv:
        d = np.hypot((u - moon_uv[0]) * w / h, v - moon_uv[1])
        halo = np.exp(-d / .09) * .35 + np.clip(1 - d / .028, 0, 1) ** .5 * .9
        night += np.array([.75, .8, .9]) * (halo * np.clip(1.4 - l * 1.6, 0, 1))[..., None]
    return np.clip(night, 0, 1)


def branch(canvas, x, y, ang, length, width, depth, rr):
    """Рекурсивное голое дерево: отрезки «штампуются» дисками."""
    H, W = canvas.shape
    x1 = x + math.cos(ang) * length
    y1 = y - math.sin(ang) * length
    n = int(length / max(width * .5, .7)) + 2
    for t in np.linspace(0, 1, n):
        px, py = x + (x1 - x) * t, y + (y1 - y) * t
        wr = max(width * (1 - .35 * t), .6)
        x0, x2 = int(max(px - wr - 1, 0)), int(min(px + wr + 2, W))
        y0, y2 = int(max(py - wr - 1, 0)), int(min(py + wr + 2, H))
        if x0 >= x2 or y0 >= y2:
            continue
        yy, xx = np.mgrid[y0:y2, x0:x2]
        canvas[y0:y2, x0:x2] = np.maximum(canvas[y0:y2, x0:x2], np.clip(wr + .5 - np.hypot(xx - px, yy - py), 0, 1))
    if depth == 0 or width < .7:
        return
    for _ in range(rr.integers(2, 4)):
        branch(canvas, x1, y1, ang + rr.uniform(-.75, .75), length * rr.uniform(.58, .78), width * .62, depth - 1, rr)


def tex_tree_layer(name, W, H, trees, seed, graves=0):
    """Слой силуэтов деревьев и надгробий с альфой — ближние планы диорамы за окном."""
    rr = np.random.default_rng(seed)
    a = np.zeros((H, W))
    for _ in range(trees):
        branch(a, rr.uniform(0, W), H + 5, math.pi / 2 + rr.uniform(-.12, .12), rr.uniform(.28, .45) * H,
               rr.uniform(6, 16), 6, rr)
    x, y = grid(W, H)
    for _ in range(graves):
        gx, gw, gh = rr.uniform(0, W), rr.uniform(14, 30), rr.uniform(26, 60)
        lx = (x - gx) + (y - H) * rr.uniform(-.15, .15)
        if rr.random() < .35:      # крест
            shape = ((np.abs(lx) < gw * .12) & (y > H - gh * 1.4)) | ((np.abs(y - (H - gh * 1.05)) < gw * .12) & (np.abs(lx) < gw * .45))
        else:                      # плита со скруглённым верхом
            shape = ((np.abs(lx) < gw / 2) & (y > H - gh)) | (np.hypot(lx, y - (H - gh)) < gw / 2)
        a = np.maximum(a, shape.astype(float))
    ground = np.clip((y - H * .93) / (H * .05), 0, 1)
    a = np.maximum(a, ground * (pnoise(W, H, 30, seed) > .3))
    save_img(name, np.dstack([np.ones((H, W, 3)) * np.array([.012, .014, .02]), a]))


def tex_windows():
    save_img("view_abbey", night_grade(load_img(os.path.join(SRC_P, "abbey.jpg")), (.72, .18), 3), 3)
    save_img("view_graveyard", night_grade(load_img(os.path.join(SRC_P, "graveyard.jpg")) * .7, (.2, .12), 4), 3)
    tex_tree_layer("view_trees_far", 2048, 512, 26, 91, graves=10)
    tex_tree_layer("view_trees_near", 2048, 768, 9, 93, graves=4)
    log("вид из окон: 2 фона, 2 слоя силуэтов")


# ---------------------------------------------------------------------------
# Силуэты (призраки, бегущая фигура)
# ---------------------------------------------------------------------------

def capsules_sdf(W, H, caps):
    x, y = grid(W, H)
    d = np.full((H, W), 1e9)
    for (ax, ay, bx, by, r) in caps:
        ax, ay, bx, by, r = ax * W, ay * H, bx * W, by * H, r * W
        px, py, vx, vy = x - ax, y - ay, bx - ax, by - ay
        t = np.clip((px * vx + py * vy) / (vx * vx + vy * vy + 1e-9), 0, 1)
        d = np.minimum(d, np.hypot(px - vx * t, py - vy * t) - r)
    return d


def silhouette(name, W, H, caps, seed):
    d = capsules_sdf(W, H, caps)
    ragged = (pnoise(W, H, 3, seed) - .5) * 9 + (pnoise(W, H, 10, seed + 1) - .5) * 14
    a = np.clip(.5 - (d + ragged) / 3.0, 0, 1)
    _, y = grid(W, H)
    a *= np.clip((1 - y / H) * 7, 0, 1) ** .7      # низ расплывается дымкой — фигура проступает из тьмы
    save_img(name, np.dstack([np.ones((H, W, 3)) * np.array([.015, .013, .014]), a]))


def tex_silhouettes():
    # Высокая худая фигура: длинные руки ниже колен, чуть склонённая голова
    standing = [(.5, .085, .51, .1, .07), (.5, .17, .5, .5, .082), (.36, .175, .64, .175, .04),
                (.36, .19, .31, .5, .036), (.31, .5, .3, .79, .03), (.64, .19, .69, .5, .036), (.69, .5, .71, .79, .03),
                (.47, .5, .45, .98, .05), (.53, .5, .55, .98, .05), (.5, .14, .5, .17, .045)]
    silhouette("ghost_standing", 256, 640, standing, 101)
    # Бегущая фигура: наклон вперёд, широкий шаг, руки в стороны
    running = [(.56, .1, .56, .1, .075), (.55, .17, .47, .52, .1), (.53, .2, .72, .38, .04), (.72, .38, .82, .3, .033),
               (.5, .21, .3, .42, .04), (.3, .42, .22, .55, .033), (.47, .52, .66, .74, .055), (.66, .74, .62, .98, .045),
               (.47, .52, .33, .72, .055), (.33, .72, .16, .8, .045)]
    silhouette("ghost_running", 384, 640, running, 103)
    log("силуэты: стоящий, бегущий")


# ---------------------------------------------------------------------------
# Референсы пользователя (assets/reference/user_refs, права подтверждены владельцем проекта)
# ---------------------------------------------------------------------------

REFS = os.path.join(ROOT, "assets", "reference", "user_refs")


def shift_reduce(a, r, fn):
    """Минимум/максимум по окну (2r+1)^2 — морфология для оценки фона под тонкими нитями."""
    out = a.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out = fn(out, np.roll(np.roll(a, dy, 0), dx, 1))
    return out


def key_threads(img, r=4, gain=2.2):
    """Светлые нити на шахматке → альфа: фон оценивается морфологическим «открытием» (нити тоньше окна)."""
    l = lum(img)
    bg = shift_reduce(shift_reduce(l, r, np.minimum), r, np.maximum)
    bg = blur(bg, 2)
    return np.clip((l - bg - .02) / np.maximum(1 - bg, .2) * gain, 0, 1)


def tex_cobweb_photo():
    """Паутина из рефов 12 (сети), 11 (спутанные нити) и 10 (угловая сеть); альфа — по нитям."""
    S = 1024
    tone = .82 + .15 * pnoise(S, S, 30, 801)
    rgb = np.dstack([tone * .96, tone * .94, tone * .9])
    x, y = grid(S, S)
    border = np.clip(np.minimum(np.minimum(x, S - 1 - x), np.minimum(y, S - 1 - y)) / 12, 0, 1)
    # Полотно (Cobweb_Sheet, верх текстуры — у потолка): провисающие сети справа сверху + нити из 11
    sheet = key_threads(load_img(os.path.join(REFS, "12.jpg"), S, S, (.33, 0.0, .67)))
    fibres = key_threads(load_img(os.path.join(REFS, "11.png"), S, S), r=5, gain=1.6) * .55
    a = np.maximum(sheet, fibres) * border
    save_img("cobweb_sheet_albedo", np.dstack([rgb, a]))
    save_img("cobweb_sheet_normal", h2n(blur(a, 1), 5))
    # Угол (Cobweb_Corner, низ текстуры — у потолка): висящая сеть из центра 12 + угловая сеть из 10
    corner = key_threads(load_img(os.path.join(REFS, "12.jpg"), S, S, (.18, .33, .7)))[::-1]
    web10 = key_threads(load_img(os.path.join(REFS, "10.png"), S, S))[::-1, ::-1] * .7
    a = np.maximum(corner, web10) * border
    save_img("cobweb_corner_albedo", np.dstack([rgb, a]))
    save_img("cobweb_corner_normal", h2n(blur(a, 1), 5))
    log("паутина из рефов 10-12: альфа по нитям")


def grade_photo(img, gain=.75, fog=0.0, seed=0):
    """Фото кладбища → ночной вид из окна: холоднее, темнее, лёгкий туман у земли."""
    h, w = img.shape[:2]
    v = grid(w, h)[1] / h
    out = img * gain * np.array([.82, .9, 1.08])
    if fog:
        f = np.clip((v - .55) * 2.2, 0, 1) * (.5 + .5 * pnoise(w, h, 40, seed)) * fog
        out = out + np.array([.08, .1, .14]) * f[..., None]
    return np.clip(out, 0, 1) ** 1.12


def tex_windows_photo():
    """Вид из окон бельэтажа — фото из рефов: север — 2 (ночное кладбище), запад — 4 (кресты в тумане)."""
    save_img("view_photo_north", grade_photo(load_img(os.path.join(REFS, "2.png"), 1224, 802), .95, .5, 811), 2)
    save_img("view_photo_west", grade_photo(load_img(os.path.join(REFS, "4.png"), 1152, 576), .8, .3, 812), 2)
    log("вид из окон: фото 2 и 4")


def tex_handprint():
    """Рука за матовым стеклом (реф 6): тёмный силуэт ладони → маска; из неё — «удар» и жирный отпечаток."""
    img = load_img(os.path.join(REFS, "6.png"), 512, 512)
    l = lum(img)
    bg = blur(l, 40)
    hand = blur(np.clip((bg - l - .04) * 4.0, 0, 1), 1)
    x, y = grid(512, 512)
    hand *= np.clip(1 - np.hypot(x / 512 - .5, y / 512 - .45) / .55, 0, 1) ** .6
    # Удар: бледная влажная ладонь, размытая «матовым стеклом» (ловит свет свечи сквозь переплёт)
    tone = np.dstack([np.full((512, 512), .62), np.full((512, 512), .58), np.full((512, 512), .55)])
    save_img("hand_slam", np.dstack([tone * (.8 + .3 * hand)[..., None], np.clip(blur(hand, 3) * 1.3, 0, 1)]))
    # Отпечаток: контур ладони, жирные пятна и разводы — светлый налёт на стекле
    edge = np.clip(hand - blur(hand, 6), 0, 1) * 2 + hand * .35
    smear = np.clip((pnoise(512, 512, 3, 821) - .4) * 3, 0, 1)
    save_img("hand_print", np.dstack([np.full((512, 512, 3), .75), np.clip(edge * (.5 + .5 * smear), 0, 1) * .8]))
    log("рука за стеклом: удар и отпечаток (реф 6)")


def tex_nav_decals():
    """Навигация: капли застывшего воска и потёртая полоса на ковре (альфа-декали)."""
    S = 256
    x, y = grid(S, S)
    rr = np.random.default_rng(831)
    wax = np.zeros((S, S))
    for _ in range(5):
        cx, cy = rr.uniform(.3, .7, 2) * S
        r = rr.uniform(.06, .16) * S
        d = np.hypot(x - cx, (y - cy) * rr.uniform(.8, 1.2)) / r
        wax = np.maximum(wax, np.clip(1 - d ** 3, 0, 1))
    alpha = np.clip(wax * (.8 + .4 * pnoise(S, S, 6, 832)) * 1.4 - .15, 0, 1)
    tone = np.dstack([np.full((S, S), .86), np.full((S, S), .8), np.full((S, S), .66)]) * (.85 + .2 * wax)[..., None]
    save_img("wax_drops_albedo", np.dstack([tone, alpha]))
    save_img("wax_drops_normal", h2n(blur(wax, 2) * 3, 4))
    # Потёртость ковра: вытоптанная полоса вдоль середины, ворс сбит, ткань светлее и грязнее
    W, H = 256, 1024
    x, y = grid(W, H)
    band = np.exp(-((x / W - .5 - .06 * np.sin(y / H * 9)) / .18) ** 2)
    worn = np.clip(band * (.6 + .6 * pnoise(W, H, 8, 833)) - .1, 0, 1)
    rgb = np.dstack([np.full((H, W), .55), np.full((H, W), .48), np.full((H, W), .4)])
    rgb = rgb * (.8 + .3 * pnoise(W, H, 2, 834))[..., None]
    save_img("carpet_wear_albedo", np.dstack([rgb, worn * .65]))
    log("навигация: воск, потёртости")


def tex_particles():
    """Частицы: мягкий клуб пыли и хлопья пепла."""
    S = 128
    x, y = grid(S, S)
    d = np.hypot(x / S - .5, y / S - .5) * 2
    puff = np.clip(1 - d, 0, 1) ** 2 * (.6 + .4 * pnoise(S, S, 6, 841))
    save_img("dust_puff", np.dstack([np.full((S, S, 3), .62), puff]))
    flake = (np.clip(1 - d * (1 + .6 * pnoise(S, S, 3, 842)), 0, 1) > .25).astype(float)
    flake *= .7 + .3 * pnoise(S, S, 2, 843)
    save_img("ash_flake", np.dstack([np.full((S, S, 3), .08), blur(flake, 1)]))
    log("частицы: пыль, пепел")


def synth_scare_sfx():
    """Звуки шести гарантированных скримеров (синтез + записи из assets/external/audio)."""
    rng = np.random.default_rng(31)
    # 1. Картина: удар рамы об пол, треск и шорох пыли
    t = np.arange(int(1.6 * SR)) / SR
    s = np.sin(TAU * (90 - 40 * t) * t) * np.exp(-t / .12) * 1.2
    s += lowpass(rng.standard_normal(len(t)), 3500) * np.exp(-t / .05)
    s += lowpass(rng.standard_normal(len(t)), 1200) * np.exp(-((t - .25) / .5) ** 2) * .15
    wood = highpass(load_audio("wood_vibration"), 80)[:len(t)]
    s[:len(wood)] += wood / (np.abs(wood).max() + 1e-9) * np.exp(-t[:len(wood)] / .2) * .6
    save_audio("painting_fall", reverb_tail(s, 1.6, .3, 31), -1.0)
    # 2. Ладонь бьёт в стекло: глухой удар + дребезг свинцового переплёта
    t = np.arange(int(1.4 * SR)) / SR
    s = np.sin(TAU * 110 * t) * np.exp(-t / .06) * 1.4 + lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t / .03)
    for f in (1830, 2410, 3170, 4020):
        s += np.sin(TAU * f * t + rng.uniform(0, TAU)) * np.exp(-t / .35) * .08
    save_audio("glass_slam", s, -1.0)
    # 3. Дверь захлопнулась: низкий удар створки, звон петель; затем вдох у самого уха
    t = np.arange(int(2.0 * SR)) / SR
    s = np.sin(TAU * (70 - 25 * t) * t) * np.exp(-t / .18) * 1.3
    s += lowpass(rng.standard_normal(len(t)), 600) * np.exp(-t / .07)
    s += np.sin(TAU * 1240 * t) * np.exp(-t / .25) * .05
    save_audio("door_slam", reverb_tail(s, 2.2, .45, 32), -1.0)
    t = np.arange(int(1.3 * SR)) / SR
    env = np.sin(np.pi * np.clip(t / 1.1, 0, 1)) ** 2 * np.minimum(1, (1.3 - t) / .15)
    breath = highpass(lowpass(rng.standard_normal(len(t)), 2600), 500) * env
    breath += lowpass(rng.standard_normal(len(t)), 1100) * env * .5 * (t / 1.3)
    save_audio("inhale_ear", breath, -2.0)
    # 6. Рывок тени: нарастающий свист воздуха и сухой шорох рассыпающегося пепла
    t = np.arange(int(1.5 * SR)) / SR
    s = highpass(lowpass(rng.standard_normal(len(t)), 1800), 200) * np.clip(t / .45, 0, 1) ** 2 * (t < .5)
    crumble = (rng.random(len(t)) < .01).astype(float) * (t > .48) * np.exp(-(t - .48) / .5)
    s += np.convolve(crumble, np.exp(-np.arange(200) / 25))[:len(t)] * rng.standard_normal(len(t)) * .7
    save_audio("shadow_rush", s, -1.0)
    log("синтез: картина, стекло, дверь, вдох, рывок тени")


# ---------------------------------------------------------------------------
# Этап 3: удар по стеклу (CC0), глубокие часы, тень из фото 3, жуткие варианты портретов (из PD)
# ---------------------------------------------------------------------------

def audio_glass_hit():
    """Удар ладонью снаружи по стеклу: самый сильный стук из «Knock on a Glass Door #2» (CC0)
    + первый треск из «Broken glass» (CC0) + низкий удар рамы. Атака — с первого сэмпла (синхрон с кадром)."""
    knock = highpass(load_audio("glass_knock"), 70)
    pos, env = onsets(knock, .15, .3)
    i = max(pos, key=lambda p: env[p:p + int(.05 * SR)].max()) if pos else int(np.argmax(np.abs(knock)))
    hit = knock[max(0, i - int(.002 * SR)):i + int(.7 * SR)].copy()
    crack = highpass(load_audio("glass_broken"), 1800)
    cp, cenv = onsets(crack, .2, .25)
    j = cp[0] if cp else int(np.argmax(np.abs(crack)))
    cr = crack[j:j + int(.35 * SR)].copy()
    cr *= np.exp(-np.arange(len(cr)) / (.09 * SR))
    t = np.arange(len(hit)) / SR
    thump = np.sin(TAU * (95 - 30 * t) * t) * np.exp(-t / .07)
    out = hit / (np.abs(hit).max() + 1e-9) + thump * .6
    k0 = int(.008 * SR)
    n = min(len(cr), len(out) - k0)
    out[k0:k0 + n] += cr[:n] / (np.abs(cr).max() + 1e-9) * .45
    fade = int(.1 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    save_audio("glass_slam", out, -0.5)
    log("стекло: удар (CC0 #0320) + треск (CC0 #0771)")


def audio_clock_deep():
    """Часы «Своей комнаты» глубже и отчётливее: усилены низы корпуса и атака каждого удара,
    мягкая компрессия — тиканье читается издалека и сквозь стены."""
    x = load_audio("clock_tick")
    pos, _ = onsets(x, .4, .35)
    a, b = pos[1], pos[1 + 2 * ((len(pos) - 3) // 2)]
    pre = int(.01 * SR)
    seg = x[a - pre:b - pre].copy()
    body = lowpass(seg, 380) * 3.2
    click = highpass(seg, 2500) * 1.4
    thump = np.zeros_like(seg)
    tt = np.arange(int(.12 * SR)) / SR
    th = np.sin(TAU * 140 * tt) * np.exp(-tt / .03)
    for p in pos:
        if a <= p < b:
            q = p - a
            n = min(len(th), len(thump) - q)
            thump[q:q + n] += th[:n] * .5
    out = np.tanh((seg + body + click + thump) * 1.6)
    save_audio("clock_tick_loop", out, -2.0)
    log(f"часы: глубже, петля {len(out) / SR:.2f} с")


def load_user(name):
    """Запись пользователя (mp3, assets/external/audio/user) → моно 44.1 кГц."""
    raw = ff(["-i", os.path.join(SRC_A, "user", name), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"])
    return np.frombuffer(raw, np.float32).astype(np.float64)


def audio_user():
    """Записи пользователя (Pixabay): часы, бег преследователя, его дыхание, дыхание в склепе.
    Все — моно (3D-источники в Godot), петли режутся по атакам, стык — короткий кроссфейд."""
    pre = int(.01 * SR)
    # Часы: тик-так через 0.978 / 1.022 с — петля из 8 ударов (ровно 8.0 с, маятник 2.0 с на два удара)
    x = load_user("dragon-studio-slow-cinematic-clock-ticking-357979.mp3")
    pos, _ = onsets(x, .3, .3)
    a = pos[0] - pre
    clock = x[a:a + int(8.0 * SR)].copy()
    save_audio("clock_user_loop", clock, -1.0)
    log(f"часы (польз.): ударов в записи {len(pos)}, петля {len(clock) / SR:.2f} с")
    # Бег: 10 шагов через ~0.27 с — петля от первого шага до места, где начался бы одиннадцатый
    x = load_user("soumages-running-363346.mp3")
    pos, _ = onsets(x, .12, .25)
    step = (pos[-1] - pos[0]) / (len(pos) - 1)
    a = pos[0] - pre
    run = loop_crossfade(x[a:a + int(len(pos) * step) + int(.02 * SR)], .02)
    save_audio("stalker_run_loop", run, -1.0)
    log(f"бег (польз.): шагов {len(pos)}, шаг {step / SR:.3f} с, петля {len(run) / SR:.2f} с")
    # Тяжёлое дыхание преследователя: с первого вдоха, хвост затухает
    x = load_user("ribhavagrawal-heavy-breathing-sound-effect-type-02-294195.mp3")
    pos, _ = onsets(x, .5, .3)
    a = max(0, pos[0] - int(.35 * SR))
    breath = x[a:].copy()
    fade = int(.4 * SR)
    breath[-fade:] *= np.linspace(1, 0, fade)
    save_audio("stalker_breath", breath, -1.0)
    log(f"дыхание преследователя (польз.): {len(breath) / SR:.2f} с")
    # Испуганное дыхание / мычание в склепе: тихая запись — нормализуется, петля с кроссфейдом 0.6 с
    x = highpass(load_user("freesound_community-respiracion-baja-asustada-31479.mp3"), 60)
    crypt = loop_crossfade(x[int(.3 * SR):], .6)
    save_audio("crypt_breath_loop", crypt, -3.0)
    log(f"склеп (польз.): петля {len(crypt) / SR:.2f} с")


# ---------------------------------------------------------------------------
# Этап 5: двери — записи пользователя (Pixabay); удар по стеклу — резче и громче
# ---------------------------------------------------------------------------

def audio_doors_user():
    """Скрип открывания двери «Своей комнаты» — участок «wooden walls creaking» с плотной серией
    трущихся щелчков (1.15–3.75 с, под 2.4 с анимации створок; остановку по концу анимации делает
    safe_door.gd). Захлопнутая дверь (скример 3) — «door closing»: удар с первого сэмпла,
    добавлен низкий удар створки и хвост зала."""
    x = highpass(load_user("dragon-studio-wooden-walls-creaking-474057.mp3"), 60)
    creak = x[int(1.15 * SR):int(3.75 * SR)].copy()
    fi, fo = int(.02 * SR), int(.25 * SR)
    creak[:fi] *= np.linspace(0, 1, fi)
    creak[-fo:] *= np.linspace(1, 0, fo)
    save_audio("door_creak", creak, -2.0)
    log(f"скрип двери (польз.): {len(creak) / SR:.2f} с")
    x = highpass(load_user("freesound_community-door-closing-41414.mp3"), 40)
    pos, _ = onsets(x, .3, .3)
    a = max(0, pos[0] - int(.004 * SR))
    hit = x[a:].copy()
    t = np.arange(len(hit)) / SR
    thump = np.sin(TAU * (62 - 18 * t) * t) * np.exp(-t / .16)
    slam = hit / (np.abs(hit).max() + 1e-9) + thump * .55
    save_audio("door_slam", reverb_tail(slam, 2.0, .3, 52), -0.5)
    log(f"дверь захлопнулась (польз.): удар с {a / SR:.2f} с, {len(hit) / SR:.2f} с + хвост")


def audio_glass_hit_sharp():
    """Удар ладонью по стеклу — резкий и пугающий. Основа прежняя (CC0 #0320 стук + #0771 треск), но:
    атака подчёркнута (первые 12 мс x2.2, остальное сжато), гул ниже 120 Гц убран, добавлены
    «щелчок» стекла 2–6 кГц, дребезг свинцового переплёта (резонансы рамы 0.05–0.4 с),
    короткий низкий удар для веса; мягкое насыщение — громче без клиппинга. Атака — с первого сэмпла."""
    rng = np.random.default_rng(77)
    knock = highpass(load_audio("glass_knock"), 120)
    pos, env = onsets(knock, .15, .3)
    i = max(pos, key=lambda p: env[p:p + int(.05 * SR)].max()) if pos else int(np.argmax(np.abs(knock)))
    hit = knock[max(0, i - int(.001 * SR)):i + int(.9 * SR)].copy()
    hit /= np.abs(hit).max() + 1e-9
    n = len(hit)
    t = np.arange(n) / SR
    shape = np.where(t < .012, 2.2, 1.0 + 1.2 * np.exp(-(t - .012) / .04))      # транзиент-шейпер
    out = hit * shape
    click = highpass(lowpass(rng.standard_normal(n), 6500), 2000) * np.exp(-t / .012)
    out += click * 1.1
    rattle = np.zeros(n)
    for f, d in ((1830, .3), (2410, .22), (3170, .18), (4020, .12), (5210, .08)):
        rattle += np.sin(TAU * f * t + rng.uniform(0, TAU)) * np.exp(-t / d)
    buzz = (1 + np.sign(np.sin(TAU * 31 * t))) * .5                              # переплёт дребезжит
    out += rattle * (.18 + .1 * buzz) * np.clip((t - .01) / .02, 0, 1)
    out += np.sin(TAU * (88 - 35 * t) * t) * np.exp(-t / .06) * .9
    crack = highpass(load_audio("glass_broken"), 2200)
    cp, _ = onsets(crack, .2, .25)
    j = cp[0] if cp else int(np.argmax(np.abs(crack)))
    cr = crack[j:j + int(.25 * SR)].copy()
    cr *= np.exp(-np.arange(len(cr)) / (.06 * SR)) / (np.abs(cr).max() + 1e-9)
    k0 = int(.004 * SR)
    m = min(len(cr), n - k0)
    out[k0:k0 + m] += cr[:m] * .6
    out = np.tanh(out / np.abs(out).max() * 2.4)
    fade = int(.12 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    save_audio("glass_slam", out, -0.3)
    log(f"стекло: резкий удар {n / SR:.2f} с (атака x2.2, щелчок, дребезг переплёта, низкий удар)")


# ---------------------------------------------------------------------------
# Этап 6: силуэт за матовым стеклом (реф 17) и настоящий удар по стеклу
# ---------------------------------------------------------------------------

PIXABAY_BANG = "freesound_community-window_knocking_door_interior-perspective_exterior_bang_aggressive-32615.mp3"


def tex_glass_silhouette():
    """Фигура за матовым стеклом (реф 17 пользователя): тёмный силуэт головы, плеч и прижатых ладоней →
    альфа по яркости (фон фото почти белый). Цвет — холодный тёмно-серый; края мягкие, как на фото."""
    img = load_img(os.path.join(REFS, "17_glass_silhouette.png"), 512, 768)
    l = lum(img)
    a = np.clip((0.9 - l) / 0.5, 0, 1) ** 0.7          # контрастнее рефа: голова и плечи читаются в игре
    x, y = grid(512, 768)
    a *= np.clip((768 - y) / 60.0, 0, 1)                     # низ фото (торс) — мягко в ноль
    tone = np.dstack([.05 + .12 * l, .055 + .12 * l, .065 + .13 * l])
    save_img("glass_silhouette", np.dstack([tone, a]))
    log("силуэт за стеклом (реф 17): 512x768")


def audio_glass_real():
    """Удар ладонью по оконному стеклу — настоящая запись: самый резкий удар из «Window knocking ...
    bang aggressive» (Pixabay, если файл есть) и/или «Striking at a Glass Door» (BigSoundBank #0198, CC0).
    Атака с первого сэмпла, низкий удар рамы для веса, короткий хвост комнаты."""
    hits = []
    sources = [("strike", highpass(load_audio("glass_strike_door"), 60))]
    if os.path.exists(os.path.join(SRC_A, "user", PIXABAY_BANG)):
        sources.append(("bang", highpass(load_user(PIXABAY_BANG), 60)))
    for tag, x in sources:
        pos, env = onsets(x, .12, .3)
        for p in pos:
            seg = x[max(0, p - int(.002 * SR)):p + int(.9 * SR)]
            if len(seg) < int(.5 * SR):
                continue
            # резкость: пик первых 15 мс к среднему уровню хвоста — чем выше, тем «щелчок» чище
            punch = np.abs(seg[:int(.015 * SR)]).max()
            tail = np.sqrt(np.mean(seg[int(.15 * SR):] ** 2)) + 1e-6
            hits.append((punch * min(punch / tail, 12.0), tag, p, seg.copy()))
    score, tag, p, hit = max(hits, key=lambda h: h[0])
    hit /= np.abs(hit).max() + 1e-9
    t = np.arange(len(hit)) / SR
    out = hit + np.sin(TAU * (85 - 30 * t) * t) * np.exp(-t / .07) * .45
    fade = int(.15 * SR)
    out[-fade:] *= np.linspace(1, 0, fade)
    save_audio("glass_slam", reverb_tail(out, 1.2, .18, 61), -0.3)
    log(f"стекло: удар из записи «{tag}» на {p / SR:.2f} с ({len(hits)} кандидатов)")


def tex_shadow_photo():
    """Тень для рывка — силуэт из рефа 15: тёмная фигура (альфа) и туманный ореол вокруг
    (rgb светлее — фигура читается тёмной на сероватой дымке даже в темноте)."""
    W, H = 320, 762
    img = load_img(os.path.join(REFS, "15_shadow_figure.png"), W, H, (.29, 0.0, .42))
    l = lum(img)
    bg = blur(l, 30)
    fig = np.clip((bg - l - .03) * 5, 0, 1)
    fig = np.maximum(fig, np.clip((.3 - l) * 4, 0, 1))
    _, y = grid(W, H)
    halo = np.clip(blur(fig, 18) * 1.4, 0, 1) * (1 - fig)
    a = np.clip(fig + halo * .45, 0, 1) * np.clip((1 - y / H) * 12, 0, 1)
    rgb = np.dstack([.012 + .2 * halo, .012 + .2 * halo, .014 + .22 * halo])
    save_img("shadow_photo", np.dstack([rgb, a]))
    log("тень: силуэт из рефа 15")


def _disc(W, H, cu, cv, rx, ry):
    x, y = grid(W, H)
    return np.clip(1 - np.hypot((x / W - cu) / rx, (y / H - cv) / ry), 0, 1)


def _paint(img, mask, color, k=1.0):
    m = (mask * k)[..., None]
    return img * (1 - m) + np.array(color) * m


def tex_creepy_portraits():
    """Жуткие двойники двух PD-полотен (по мотивам рефов 13–14, сами рефы не используются):
    «Иннокентий X» — крик в духе Бэкона (вертикальные мазки-завеса, распахнутый тёмный рот, пустые глаза,
    фиолетовый тон, золотая «клетка»); «Сатурн» — выпученные белые глаза, кровь, болезненная желтизна."""
    W, H = PW, PH
    x, y = grid(W, H)
    # Иннокентий X: крик
    src = load_img(os.path.join(OUT_T, "painting_innocent.jpg"))
    stripes = pnoise(W, 8, 1.2, 851)[0]
    smear = (stripes[None, :] - .5) * 36 * (.5 + pnoise(W, H, 40, 852))
    img = sample(src, x + (pnoise(W, H, 8, 853) - .5) * 6, y + smear)
    # Вертикальная «завеса»: полосы размыты сверху вниз, как мазки Бэкона
    vb = img.copy()
    for _ in range(3):
        vb = (np.roll(vb, 6, 0) + vb + np.roll(vb, -6, 0)) / 3
    veil = np.clip((stripes[None, :] - .45) * 4, 0, 1) * np.clip(1 - _disc(W, H, .63, .47, .2, .16) * 2, 0, 1)
    img = img * (1 - veil[..., None]) + vb * veil[..., None]
    face = _disc(W, H, .63, .47, .16, .13)
    img = img * (1 - face[..., None] * .5) + sample(src, x - 18 * face, y) * face[..., None] * .5
    gray = lum(img)[..., None]
    img = img * .35 + gray * np.array([.75, .55, .95]) * .9
    jaw = _disc(W, H, .63, .56, .07, .09)
    img = sample(img, x, y - jaw * 40)
    ragged = .75 + .5 * pnoise(W, H, 3, 854)
    mouth = np.clip(_disc(W, H, .63, .55, .05, .075) * 1.6 * ragged - .1, 0, 1) ** .7
    img = _paint(img, mouth, [.06, .0, .015], .95)
    teeth = np.clip(_disc(W, H, .63, .497, .036, .008) * 2 * ragged - .4, 0, 1)
    img = _paint(img, teeth, [.62, .58, .5], .6)
    for cu in (.585, .689):
        img = _paint(img, np.clip(_disc(W, H, cu, .44, .03, .024) * 1.8 * ragged - .2, 0, 1) ** .6, [.02, .0, .01])
        rim = np.clip(_disc(W, H, cu, .44, .042, .032) * 3 - 2.5, 0, 1) * ragged
        img = img + np.array([.45, .45, .42]) * rim[..., None] * .5
    cage = ((np.abs(x / W - .28) < .004) | (np.abs(x / W - .93) < .004)) & (y / H > .5)
    cage |= (np.abs(y / H - .62 - .05 * np.sin(x / W * 3)) < .003) & (x / W > .2)
    img[cage] = img[cage] * .3 + np.array([.7, .55, .15]) * .7
    save_img("painting_innocent_creep", np.clip(img, 0, 1), 2)
    # Сатурн: выпученные глаза, кровь, желтизна
    img = load_img(os.path.join(OUT_T, "painting_saturn.jpg"))
    mid = np.clip(1 - np.abs(lum(img) - .3) * 3, 0, 1)
    img = img * (1 - mid[..., None] * .55) + lum(img)[..., None] * np.array([1.4, 1.3, .35]) * mid[..., None] * .55
    rough = .7 + .6 * pnoise(W, H, 2.5, 862)
    veins = (np.abs(pnoise(W, H, 1.5, 863) - .5) < .02).astype(float)
    for cu, cv in ((.323, .258), (.415, .255)):
        white = np.clip(_disc(W, H, cu, cv, .036, .028) * 2.2 * rough - .3, 0, 1) ** .8
        img = _paint(img, white, [.82, .78, .66], .9)
        img = _paint(img, white * veins, [.5, .05, .04], .7)
        img = _paint(img, np.clip(_disc(W, H, cu + .007, cv + .006, .006, .005) * 3, 0, 1), [.03, .01, .01])
    img = _paint(img, np.clip(_disc(W, H, .376, .315, .05, .035) * 2, 0, 1), [.25, .01, .02])
    rr = np.random.default_rng(861)
    blood = np.zeros((H, W))
    for _ in range(14):
        cx = int((.33 + rr.uniform(0, .12)) * W)
        y0 = int((.32 + rr.uniform(0, .05)) * H)
        L = int(rr.uniform(.05, .3) * H)
        wd = int(rr.uniform(2, 6))
        blood[y0:y0 + L, cx - wd:cx + wd] = np.maximum(blood[y0:y0 + L, cx - wd:cx + wd],
                                                       np.linspace(1, .3, L)[:, None])
    img = _paint(img, blur(blood, 2), [.42, .02, .03], .8)
    save_img("painting_saturn_creep", np.clip(img, 0, 1), 2)
    log("картины: жуткие варианты (Иннокентий X, Сатурн)")


def synth_portrait_creep():
    """Превращение картины: быстро нарастающий диссонанс (0.9 с) и резкий удар в конце."""
    rng = np.random.default_rng(71)
    t = np.arange(int(1.6 * SR)) / SR
    rise = np.clip(t / .9, 0, 1) ** 2.5 * (t < .95)
    s = _cluster(t, [233, 247, 311, 330, 466], 9, .02) * rise
    s += lowpass(rng.standard_normal(len(t)), 1500) * rise * .5
    ht = np.clip(t - .9, 0, None)
    boom = np.sin(TAU * (55 - 15 * ht) * ht) * 1.4 + lowpass(rng.standard_normal(len(t)), 2500) * .8
    s += boom * np.exp(-ht / .25) * (t >= .9)
    save_audio("portrait_creep", reverb_tail(s, 2.0, .4, 72), -1.0)
    log("синтез: превращение картины")


def main():
    os.makedirs(OUT_A, exist_ok=True)
    os.makedirs(OUT_T, exist_ok=True)
    only = sys.argv[1:] or ["audio", "textures"]
    if "audio" in only:
        audio_steps()
        audio_clock()
        audio_loops()
        audio_oneshots()
        synth_drone()
        synth_stingers()
    if "textures" in only:
        tex_paintings()
        tex_cobweb()
        tex_windows()
        tex_silhouettes()
    if "refs" in only:
        tex_cobweb_photo()
        tex_windows_photo()
        tex_handprint()
        tex_nav_decals()
        tex_particles()
        synth_scare_sfx()
    if "stage3" in only:
        audio_glass_hit()
        audio_clock_deep()
        tex_shadow_photo()
        tex_creepy_portraits()
        synth_portrait_creep()
    if "stage4" in only:
        audio_user()
    if "stage5" in only:
        audio_doors_user()
        audio_glass_hit_sharp()
    if "stage6" in only:
        tex_glass_silhouette()
        audio_glass_real()
    log("Готово")


if __name__ == "__main__":
    main()
