# Tile every PNG in a folder into one contact sheet: python scratch/tile_dir.py <dir> <out> [cols]
import sys, glob, os
from PIL import Image
d, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 3
files = sorted(glob.glob(os.path.join(d, "*.png")))
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows), (40, 40, 40))
for i, im in enumerate(ims):
    sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.thumbnail((1800, 1800))
sheet.save(out)
print(len(ims), [os.path.basename(f) for f in files])
