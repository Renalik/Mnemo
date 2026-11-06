"""Render the original Mnemo card-stack icon; no external image inputs."""
import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools' / 'python_packages'))
from PIL import Image, ImageDraw, ImageFilter

size = 1024
image = Image.new('RGB', (size, size))
pixels = image.load()
for y in range(size):
    for x in range(size):
        glow = max(0, 1 - math.dist((x, y), (220, 160)) / 1050)
        pixels[x, y] = (255, int(78 + 97 * glow), int(5 + 74 * glow))
for box, alpha, radius in [((235, 240, 705, 690), 105, 83), ((280, 300, 750, 750), 135, 83), ((295, 365, 765, 815), 195, 83)]:
    layer = Image.new('RGBA', (size, size)); draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(box, radius=radius, fill=(255, 255, 255, alpha//3), outline=(255, 255, 255, alpha), width=4)
    image = Image.alpha_composite(image.convert('RGBA'), layer)
image = image.convert('RGB')
folder = ROOT / 'Resources/Assets.xcassets/AppIcon.appiconset'; folder.mkdir(parents=True, exist_ok=True)
image.save(folder / 'AppIcon.png')
(folder / 'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info':{'author':'xcode','version':1}}, indent=2), encoding='utf-8')
(folder.parent / 'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}), encoding='utf-8')
print('Created original 1024px Mnemo icon')
