#!/usr/bin/env python3
#
# KUL_FWT_bundle_report.py
#
# Collects every bundle's screenshots into a single self-contained HTML contact
# sheet for the subject, so reviewing a run means opening one file instead of
# clicking through 22 bundle directories (or paging a stitched PDF that cannot
# be filtered).
#
# KUL_FWT_make_TCKs.sh's screenshot step writes 12 PNGs per bundle -- three
# orientations (axial, coronal, sagittal) x four renderings (tract alone or over
# anatomy, as 3D streamlines or as a glass-brain projection). This assembles all
# of them, one row per bundle, with the rendering switchable for every bundle at
# once so like can be compared with like down the page.
#
# Images are re-encoded rather than embedded as-is: the source PNGs are 1920x1080
# RGBA and total ~32 MB per subject, which base64s to a page no browser opens
# happily. Downscaled and JPEG'd they come to ~9 MB, which does open, and at
# contact-sheet size the difference is not visible. The page stays fully
# self-contained (data: URIs, no sibling files needed) so it can be copied into
# REPORT/ on its own.
#
# Run once per subject, after the per-bundle screenshot work has finished.

import argparse
import base64
import glob
import io
import json
import os
import re

from PIL import Image

# Contact-sheet size. 800px wide at JPEG q82 measured ~26 KB/image on real
# KUL_FWT renders -- ~9 MB of base64 for a 22-bundle subject.
IMG_MAX_PX = 800
IMG_QUALITY = 82

# The four renderings the screenshot step produces, in the order they should
# appear in the switcher. Keys are the filename fragments that identify them;
# note "+anat_3d" must be tested before "_3d" since the former contains the
# latter's suffix pattern once the +anat prefix is stripped.
VARIANTS = [
    ("+anat_3d", "tract + anatomy (3D)"),
    ("_3d", "tract only (3D)"),
    ("+anat_glass", "tract + anatomy (glass)"),
    ("_glass", "tract only (glass)"),
]

VIEWS = ["sagittal", "coronal", "axial"]

INK_PRIMARY = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRIDLINE = "#e1e0d9"
SURFACE = "#fcfcfb"
SERIES_COLOR = "#2a78d6"


def classify(filename):
    """Return (view, variant_key) for a screenshot, or None if it is not one.

    Names look like `sagittal_CST_LT_fin_BT_iFOD2+anat_3d.png`. Variants are
    matched longest-first so `+anat_3d` is not mistaken for `_3d`.
    """
    base = os.path.basename(filename)
    view = next((v for v in VIEWS if base.startswith(v + "_")), None)
    if view is None:
        return None
    stem = base[: -len(".png")]
    for key, _ in VARIANTS:
        if stem.endswith(key):
            return view, key
    return None


def encode_image(path):
    """Downscale, flatten and JPEG-encode one screenshot as a data: URI."""
    with Image.open(path) as im:
        # RGBA over a white ground: the renders carry transparency, and JPEG has
        # no alpha -- compositing explicitly avoids the black background that a
        # bare .convert("RGB") would leave behind.
        if im.mode in ("RGBA", "LA"):
            ground = Image.new("RGB", im.size, "white")
            ground.paste(im, mask=im.split()[-1])
            im = ground
        else:
            im = im.convert("RGB")

        im = im.crop(trim_box(im))
        im.thumbnail((IMG_MAX_PX, IMG_MAX_PX), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=IMG_QUALITY, optimize=True)

    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def trim_box(im):
    """Bounding box of the non-background content.

    The renders sit in a lot of empty ground; trimming it before downscaling
    means the tract itself gets more of the pixel budget. Falls back to the full
    frame if the image is uniform (nothing to trim, and getbbox would return
    None).
    """
    from PIL import ImageChops
    ground = Image.new(im.mode, im.size, im.getpixel((0, 0)))
    box = ImageChops.difference(im, ground).convert("L").point(
        lambda p: 255 if p > 8 else 0).getbbox()
    return box or (0, 0, im.size[0], im.size[1])


def collect_bundles(tcks_output_dir, subj, ses_str):
    """Return [{name, images:{variant:{view:datauri}}, spider, connectivity}]."""
    bundles = []
    for out_dir in sorted(glob.glob(os.path.join(tcks_output_dir, "*_output"))):
        name = os.path.basename(out_dir)[: -len("_output")]
        shots = glob.glob(os.path.join(out_dir, "Screenshots", "*.png"))
        images = {}
        for shot in sorted(shots):
            hit = classify(shot)
            if hit is None:
                continue
            view, variant = hit
            images.setdefault(variant, {})[view] = encode_image(shot)
        if not images:
            continue

        # link out to the interactive per-bundle page, if the -Q spider step ran
        spider = glob.glob(os.path.join(
            out_dir, "QQ", f"sub-{subj}{ses_str}_spider3d_{name}.html"))

        bundles.append({
            "name": name,
            "images": images,
            "spider": os.path.basename(spider[0]) if spider else None,
            "connectivity": top_connection(out_dir),
        })
    return bundles


def top_connection(out_dir):
    """One-line 'strongest endpoint pair' summary, for the bundle's caption.

    Read straight from the connectivity CSV rather than re-deriving it, so this
    and the per-bundle spider page cannot disagree. Returns None when the run had
    no connectivity step.
    """
    hits = sorted(glob.glob(os.path.join(out_dir, "QQ", "*_connectivity_matrix.csv")))
    if not hits:
        return None
    try:
        import numpy as np
        matrix = np.loadtxt(hits[0], delimiter=",", ndmin=2)
    except (OSError, ValueError, ImportError):
        return None
    if matrix.size == 0:
        return None
    folded = np.triu(matrix) + np.tril(matrix, -1).T
    folded[0, :] = 0
    folded[:, 0] = 0
    if folded.max() <= 0:
        return None
    i, j = np.unravel_index(int(folded.argmax()), folded.shape)
    total = folded.sum()
    return {
        "a": int(i), "b": int(j),
        "pct": round(100.0 * folded[i, j] / total, 1),
        "n": int(folded.sum()),
    }


def load_parcel_labels():
    """Index -> parcel name, from the fs_default LUT shipped beside this script."""
    lut = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fs_default.txt")
    labels = {}
    try:
        with open(lut) as fh:
            for line in fh:
                fields = line.split()
                if len(fields) >= 3 and fields[0].isdigit():
                    labels[int(fields[0])] = fields[2]
    except OSError:
        pass
    return labels


TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>
  body {{ margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
        background: {surface}; color: {ink_primary}; }}
  header {{ position: sticky; top: 0; background: {surface};
           border-bottom: 1px solid {gridline}; padding: 12px 20px 10px; z-index: 5; }}
  h1 {{ font-size: 15px; font-weight: 600; margin: 0 0 2px; }}
  #sub {{ font-size: 11px; color: {ink_muted}; }}
  #controls {{ margin-top: 8px; display: flex; gap: 6px; flex-wrap: wrap;
              align-items: center; }}
  button {{ font: inherit; font-size: 11px; padding: 3px 10px; cursor: pointer;
           background: {surface}; color: {ink_secondary};
           border: 1px solid {gridline}; border-radius: 3px; }}
  button.on {{ background: {series}; border-color: {series}; color: #fff; }}
  #filter {{ font: inherit; font-size: 11px; padding: 3px 8px; margin-left: auto;
            border: 1px solid {gridline}; border-radius: 3px; background: {surface};
            color: {ink_primary}; }}
  .bundle {{ border-bottom: 1px solid {gridline}; padding: 14px 20px; }}
  .bhead {{ display: flex; align-items: baseline; gap: 10px; margin-bottom: 6px; }}
  .bname {{ font-size: 13px; font-weight: 600; }}
  .bmeta {{ font-size: 11px; color: {ink_muted}; }}
  .bmeta a {{ color: {series}; text-decoration: none; }}
  .bmeta a:hover {{ text-decoration: underline; }}
  .views {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px;
           max-width: 1500px; }}
  .view {{ text-align: center; }}
  /* Fixed height + contain: autocrop leaves each orientation a different aspect
     ratio, so free-flowing images made every row ragged and floated the captions
     to different heights. Black ground matches the renders' own background, so
     the letterboxing is invisible rather than a white bar. */
  .view img {{ width: 100%; height: 340px; object-fit: contain; display: block;
              border-radius: 2px; background: #000; }}
  .view span {{ font-size: 10px; color: {ink_muted}; display: block;
               margin-top: 3px; }}
  .missing {{ font-size: 11px; color: {ink_muted}; padding: 20px 0; }}
  #empty {{ padding: 40px 20px; font-size: 12px; color: {ink_muted}; }}
</style></head>
<body>
<header>
  <h1>{title}</h1>
  <div id="sub">{n_bundles} bundles &bull; drag-to-rotate detail pages linked per bundle</div>
  <div id="controls">
    <span style="font-size:11px;color:{ink_muted}">rendering:</span>
    <span id="variant-buttons"></span>
    <input id="filter" type="search" placeholder="filter bundles, e.g. CST or _LT">
  </div>
</header>
<div id="bundles"></div>
<div id="empty" hidden>no bundle matches that filter</div>
<script>
const BUNDLES = {bundles_json};
const VARIANTS = {variants_json};
const VIEWS = {views_json};
const LABELS = {labels_json};
let variant = VARIANTS[0][0];

function connText(c) {{
  if (!c) return "";
  const a = LABELS[c.a] || ("label " + c.a), b = LABELS[c.b] || ("label " + c.b);
  return "strongest: " + a + " \\u2194 " + b + " (" + c.pct + "% of " + c.n + ")";
}}

function render() {{
  const host = document.getElementById("bundles");
  const q = document.getElementById("filter").value.trim().toLowerCase();
  host.textContent = "";
  let shown = 0;

  BUNDLES.forEach(b => {{
    if (q && !b.name.toLowerCase().includes(q)) return;
    shown++;
    const sec = document.createElement("div");
    sec.className = "bundle";

    const head = document.createElement("div");
    head.className = "bhead";
    const nm = document.createElement("span");
    nm.className = "bname"; nm.textContent = b.name;
    head.appendChild(nm);
    const meta = document.createElement("span");
    meta.className = "bmeta";
    meta.textContent = connText(b.connectivity);
    if (b.spider) {{
      if (meta.textContent) meta.appendChild(document.createTextNode(" \\u2022 "));
      const a = document.createElement("a");
      a.href = b.spider; a.textContent = "metrics \\u2192";
      meta.appendChild(a);
    }}
    head.appendChild(meta);
    sec.appendChild(head);

    // a bundle can be missing the selected rendering (a failed screenshot pass)
    // while still having the others -- say so rather than showing a blank row
    const set = b.images[variant];
    if (!set) {{
      const note = document.createElement("div");
      note.className = "missing";
      note.textContent = "no " + variant + " renders for this bundle";
      sec.appendChild(note);
    }} else {{
      const grid = document.createElement("div");
      grid.className = "views";
      VIEWS.forEach(v => {{
        if (!set[v]) return;
        const cell = document.createElement("div");
        cell.className = "view";
        const img = document.createElement("img");
        img.loading = "lazy";
        img.src = set[v];
        img.alt = b.name + " " + v;
        const cap = document.createElement("span");
        cap.textContent = v;
        cell.appendChild(img); cell.appendChild(cap);
        grid.appendChild(cell);
      }});
      sec.appendChild(grid);
    }}
    host.appendChild(sec);
  }});

  document.getElementById("empty").hidden = shown > 0;
}}

function buildButtons() {{
  const host = document.getElementById("variant-buttons");
  VARIANTS.forEach(([key, label]) => {{
    const btn = document.createElement("button");
    btn.textContent = label;
    btn.className = key === variant ? "on" : "";
    btn.onclick = () => {{
      variant = key;
      host.querySelectorAll("button").forEach(x => x.className = "");
      btn.className = "on";
      render();
    }};
    host.appendChild(btn);
  }});
}}

document.getElementById("filter").addEventListener("input", render);
buildButtons();
render();
</script>
</body></html>
"""


def main():
    parser = argparse.ArgumentParser(
        description="Assemble every bundle's screenshots into one self-contained "
                    "HTML contact sheet for the subject."
    )
    parser.add_argument("tcks_output_dir", type=str,
                        help="sub-<subj><ses_str>_TCKs_output directory.")
    parser.add_argument("subj", type=str)
    parser.add_argument("ses_str", type=str, nargs="?", default="")
    parser.add_argument("-o", "--output", type=str, default=None,
                        help="output .html (default: <tcks_output_dir>/"
                             "sub-<subj><ses_str>_FWT_report.html)")
    args = parser.parse_args()

    bundles = collect_bundles(args.tcks_output_dir, args.subj, args.ses_str)
    if not bundles:
        print("no bundle screenshots found, not writing a report")
        return

    # keep only the variants that at least one bundle actually has, so the
    # switcher never offers a button that shows nothing anywhere
    present = {v for b in bundles for v in b["images"]}
    variants = [[k, lab] for k, lab in VARIANTS if k in present]

    out = args.output or os.path.join(
        args.tcks_output_dir, f"sub-{args.subj}{args.ses_str}_FWT_report.html")

    html = TEMPLATE.format(
        title=f"sub-{args.subj}{args.ses_str} — FWT bundles",
        n_bundles=len(bundles),
        bundles_json=json.dumps(bundles),
        variants_json=json.dumps(variants),
        views_json=json.dumps(VIEWS),
        labels_json=json.dumps(load_parcel_labels()),
        surface=SURFACE, ink_primary=INK_PRIMARY, ink_secondary=INK_SECONDARY,
        ink_muted=INK_MUTED, gridline=GRIDLINE, series=SERIES_COLOR,
    )
    with open(out, "w") as fh:
        fh.write(html)
    print(f"wrote {out} ({os.path.getsize(out) / 1048576:.1f} MB, "
          f"{len(bundles)} bundles)")


if __name__ == "__main__":
    main()
