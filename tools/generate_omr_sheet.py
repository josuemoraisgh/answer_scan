"""
Generate a high-contrast, camera-optimised OMR answer sheet (A4 landscape, SVG).

All dimensions in millimetres; the SVG uses mm as native units so it can be
printed at true size from any vector viewer (Inkscape, browsers, etc.).
"""

page_w, page_h = 297, 210          # A4 landscape mm

# ── Corner markers ────────────────────────────────────────────────────────────
M  = 13          # marker side length (mm)
MO = 10          # marker offset from page edge (mm)

# top-left corner of each marker
markers = {
    "tl": (MO,              MO),
    "tr": (page_w - MO - M, MO),
    "bl": (MO,              page_h - MO - M),
    "br": (page_w - MO - M, page_h - MO - M),
}

# Inner edges of the markers (= usable grid area boundary)
inner_left   = markers["tl"][0] + M        # 23 mm
inner_right  = markers["tr"][0]            # 284 - 13 = 271... recalc below
inner_top    = markers["tl"][1] + M        # 23 mm
inner_bottom = markers["bl"][1]            # page_h - MO - M

inner_left   = MO + M                          # 23
inner_right  = page_w - MO - M                 # 274
inner_top    = MO + M                          # 23
inner_bottom = page_h - MO - M                 # 187

avail_w = inner_right  - inner_left            # 251 mm
avail_h = inner_bottom - inner_top             # 164 mm

# ── Grid parameters ───────────────────────────────────────────────────────────
N_COLS      = 20
N_ROWS      = 5
BOX         = 7.0          # answer box side (mm)
COL_PITCH   = 11.8         # centre-to-centre column spacing (mm)
ROW_PITCH   = 20.0         # centre-to-centre row spacing (mm)
LABEL_W     = 14.0         # width of the A–E label column (mm)
HEADER_H    = 13.0         # height of the 1–20 header row (mm)
BOX_STROKE  = 0.5          # box border width (pt / mm — treated as mm in SVG)

# Total grid footprint
grid_w = LABEL_W + (N_COLS - 1) * COL_PITCH + BOX
grid_h = HEADER_H + (N_ROWS - 1) * ROW_PITCH + BOX

# Centre the grid within the inner rectangle
ox = inner_left + (avail_w - grid_w) / 2     # grid origin x
oy = inner_top  + (avail_h - grid_h) / 2     # grid origin y

# Centre of the first answer box (row 0, col 0)
first_cx = ox + LABEL_W + BOX / 2
first_cy = oy + HEADER_H + BOX / 2

# ── SVG helpers ───────────────────────────────────────────────────────────────
def f(v):
    """Format float to 3 dp, drop trailing zeros."""
    return f"{v:.3f}".rstrip("0").rstrip(".")

def rect(x, y, w, h, fill="black", stroke="none", sw=0, rx=0):
    parts = [f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}"']
    parts.append(f' fill="{fill}"')
    if stroke != "none":
        parts.append(f' stroke="{stroke}" stroke-width="{f(sw)}"')
    if rx:
        parts.append(f' rx="{f(rx)}"')
    parts.append('/>')
    return "".join(parts)

def text(x, y, content, size=3.5, anchor="middle", weight="normal"):
    return (f'<text x="{f(x)}" y="{f(y)}" '
            f'font-family="Arial,Helvetica,sans-serif" '
            f'font-size="{f(size)}" font-weight="{weight}" '
            f'text-anchor="{anchor}" dominant-baseline="central" '
            f'fill="black">{content}</text>')

# ── Build SVG ─────────────────────────────────────────────────────────────────
lines = [
    f'<?xml version="1.0" encoding="UTF-8"?>',
    f'<svg xmlns="http://www.w3.org/2000/svg"',
    f'     width="{page_w}mm" height="{page_h}mm"',
    f'     viewBox="0 0 {page_w} {page_h}">',
    '',
    '  <!-- White background -->',
    f'  {rect(0, 0, page_w, page_h, fill="white")}',
    '',
    '  <!-- Corner markers -->',
]

for key, (mx, my) in markers.items():
    lines.append(f'  {rect(mx, my, M, M)}  <!-- {key} -->')

lines += [
    '',
    '  <!-- Column headers: 1–20 -->',
]
for col in range(N_COLS):
    cx = first_cx + col * COL_PITCH
    cy = oy + HEADER_H / 2
    lines.append(f'  {text(cx, cy, str(col + 1), size=3.8, weight="bold")}')

lines += [
    '',
    '  <!-- Row labels: A–E -->',
]
row_labels = ["A", "B", "C", "D", "E"]
for row in range(N_ROWS):
    cy = first_cy + row * ROW_PITCH
    cx = ox + LABEL_W / 2
    lines.append(f'  {text(cx, cy, row_labels[row], size=4.0, weight="bold")}')

lines += [
    '',
    '  <!-- Answer boxes -->',
]
for row in range(N_ROWS):
    for col in range(N_COLS):
        cx = first_cx + col * COL_PITCH
        cy = first_cy + row * ROW_PITCH
        bx = cx - BOX / 2
        by = cy - BOX / 2
        lines.append(f'  {rect(bx, by, BOX, BOX, fill="white", stroke="black", sw=BOX_STROKE)}')

lines += [
    '',
    '  <!-- Optional instruction line -->',
]
instr_y = oy + HEADER_H / 4          # just above the header numbers
lines.append(
    f'  {text(page_w/2, instr_y - 4, "Fill only one box per question using a dark pen. Completely fill the square.", size=2.4)}'
)

lines += [
    '',
    '</svg>',
]

svg_content = "\n".join(lines)

out_path = "assets/omr_sheet.svg"
import os, pathlib
pathlib.Path(out_path).parent.mkdir(parents=True, exist_ok=True)
pathlib.Path(out_path).write_text(svg_content, encoding="utf-8")
print(f"Written: {out_path}")

# Print key dimensions for verification
print(f"\nLayout summary:")
print(f"  Page       : {page_w} × {page_h} mm (A4 landscape)")
print(f"  Markers    : {M}×{M} mm at {MO} mm from edges")
print(f"  Inner rect : x={inner_left}–{inner_right}  y={inner_top}–{inner_bottom}  ({avail_w}×{avail_h} mm)")
print(f"  Grid origin: ({f(ox)}, {f(oy)}) mm")
print(f"  Grid size  : {f(grid_w)} × {f(grid_h)} mm")
print(f"  Col pitch  : {COL_PITCH} mm   Row pitch: {ROW_PITCH} mm")
print(f"  Box size   : {BOX} mm   Stroke: {BOX_STROKE} mm")
print(f"  First box  : centre ({f(first_cx)}, {f(first_cy)}) mm")
