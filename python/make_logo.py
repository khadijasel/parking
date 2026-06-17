# -*- coding: utf-8 -*-
"""
Genere des PNG du logo SpotHna (voiture en degrade bleu, comme le splash).
Sorties dans ../logo/ :
  - logo_spothna_icon.png         (fond blanc, 1024x1024)
  - logo_spothna_icon_transp.png  (fond transparent, 1024x1024)
  - logo_spothna_full.png         (icone + texte "SpotHna", fond blanc)
"""
import os
from PIL import Image, ImageDraw, ImageFont

# ---- Parametres ----
SS = 2                      # su-echantillonnage (anti-crenelage)
OUT = 1024                  # taille finale icone
W = OUT * SS
C0 = (37, 99, 235)          # #2563EB
C1 = (96, 165, 250)         # #60A5FA

# Logo "voiture" dans un espace 0..100 (identique au splash)
BODY = [
    ((30, 35), (30, 25), (70, 20), (75, 35)),
    ((75, 35), (78, 45), (60, 50), (50, 50)),
    ((50, 50), (35, 50), (22, 55), (25, 70)),
    ((25, 70), (28, 85), (70, 80), (75, 70)),
]
PLUG = [((75, 70), (85, 70)), ((82, 65), (82, 75)), ((88, 65), (88, 75))]
WHEELS = [(38, 72), (62, 72)]
SQUARES = [(75, 64), (79, 64), (75, 74)]
STROKE = 6.5

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "logo")
os.makedirs(OUT_DIR, exist_ok=True)


def cubic(p0, p1, p2, p3, n=80):
    pts = []
    for i in range(n + 1):
        t = i / n
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def make_gradient(size):
    g = 128
    small = Image.new("RGB", (g, g))
    px = small.load()
    for j in range(g):
        for i in range(g):
            t = ((i / (g - 1)) + (j / (g - 1))) / 2.0
            px[i, j] = (
                int(C0[0] + (C1[0] - C0[0]) * t),
                int(C0[1] + (C1[1] - C0[1]) * t),
                int(C0[2] + (C1[2] - C0[2]) * t),
            )
    return small.resize(size, Image.BILINEAR)


def build_car_mask(size, scale, ox, oy):
    """Masque (L) de la voiture : blanc = trace.

    On dessine le trait en TAMPONNANT des disques le long du chemin (au lieu de
    ImageDraw.line epais qui produit des epines) -> trait lisse, bouts ronds.
    """
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    sw = STROKE * scale
    r = sw / 2.0

    def T(p):
        return (p[0] * scale + ox, p[1] * scale + oy)

    def stamp(pts):
        for x, y in pts:
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)

    def lerp_line(a, b, n=60):
        return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
                for i in range(n + 1)]

    # Carrosserie : echantillonnage dense des beziers, puis tamponnage
    body = []
    for seg in BODY:
        body += cubic(*seg, n=220)
    stamp([T(p) for p in body])

    # Prise de recharge
    for a, b in PLUG:
        stamp([T(p) for p in lerp_line(a, b)])

    # Roues (disques pleins)
    for c in WHEELS:
        cx, cy = T(c)
        rr = 3 * scale
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)

    # Details prise (petits carres)
    for s in SQUARES:
        x, y = T(s)
        d.rectangle([x, y, x + 2 * scale, y + 2 * scale], fill=255)

    return mask


def render_icon(transparent=False):
    # Voiture centree, ~68% du canvas
    scale = (W * 0.68) / 100.0
    bbox_cx, bbox_cy = 55.0, 52.5
    ox = W / 2.0 - bbox_cx * scale
    oy = W / 2.0 - bbox_cy * scale

    mask = build_car_mask((W, W), scale, ox, oy)
    grad = make_gradient((W, W))

    if transparent:
        base = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        car = grad.convert("RGBA")
        base.paste(car, (0, 0), mask)
        out = base
    else:
        base = Image.new("RGB", (W, W), (255, 255, 255))
        base.paste(grad, (0, 0), mask)
        out = base

    return out.resize((OUT, OUT), Image.LANCZOS)


def load_font(size):
    for name in ("arialbd.ttf", "Arialbd.ttf", "arial.ttf", "segoeuib.ttf"):
        try:
            return ImageFont.truetype("C:/Windows/Fonts/" + name, size)
        except Exception:
            pass
    return ImageFont.load_default()


def render_full():
    icon = render_icon(transparent=True)  # voiture transparente
    Wf, Hf = 1024, 1280
    canvas = Image.new("RGB", (Wf, Hf), (255, 255, 255))
    # icone centree en haut
    isz = 560
    ic = icon.resize((isz, isz), Image.LANCZOS)
    canvas.paste(ic, ((Wf - isz) // 2, 120), ic)

    d = ImageDraw.Draw(canvas)
    title_font = load_font(150)
    sub_font = load_font(46)

    title = "SpotHna"
    try:
        tb = d.textbbox((0, 0), title, font=title_font)
        tw = tb[2] - tb[0]
    except Exception:
        tw = d.textlength(title, font=title_font)
    d.text(((Wf - tw) / 2, 760), title, font=title_font, fill=C0)

    sub = "A L G E R I A"
    try:
        sb = d.textbbox((0, 0), sub, font=sub_font)
        sw = sb[2] - sb[0]
    except Exception:
        sw = d.textlength(sub, font=sub_font)
    d.text(((Wf - sw) / 2, 960), sub, font=sub_font, fill=(148, 163, 184))

    return canvas


def main():
    render_icon(False).save(os.path.join(OUT_DIR, "logo_spothna_icon.png"))
    render_icon(True).save(os.path.join(OUT_DIR, "logo_spothna_icon_transp.png"))
    render_full().save(os.path.join(OUT_DIR, "logo_spothna_full.png"))
    print("OK ->", os.path.abspath(OUT_DIR))


if __name__ == "__main__":
    main()
