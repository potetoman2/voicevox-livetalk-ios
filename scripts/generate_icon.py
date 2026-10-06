"""Create the original LiveTalk icon from geometric shapes; no character artwork."""
from pathlib import Path
import json
from PIL import Image, ImageDraw
scale = 3
image = Image.new('RGB', (1024*scale, 1024*scale), '#4969c5')
draw = ImageDraw.Draw(image)
def rect(box, radius, fill):
    draw.rounded_rectangle(tuple(int(x*scale) for x in box), radius=int(radius*scale), fill=fill)
rect((170, 235, 850, 735), 125, '#fcfaf7')
draw.polygon([(285*scale, 690*scale), (285*scale, 840*scale), (455*scale, 710*scale)], fill='#fcfaf7')
for x,height in [(320,120),(415,225),(510,330),(605,225),(700,120)]:
    rect((x-23, 485-height/2, x+23, 485+height/2),23,'#4969c5')
draw.ellipse((750*scale, 155*scale, 870*scale, 275*scale), fill='#f5c8b5')
dest = Path('ios/LiveTalk/Assets.xcassets/AppIcon.appiconset')
dest.mkdir(parents=True, exist_ok=True)
image.resize((1024,1024), Image.Resampling.LANCZOS).save(dest/'AppIcon.png')
(dest/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
(dest.parent/'Contents.json').write_text('{"info":{"author":"xcode","version":1}}\n')
