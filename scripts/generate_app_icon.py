from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

SS=4; OUT="/tmp/icons"
FONT="/mnt/skills/examples/canvas-design/canvas-fonts/Outfit-Bold.ttf"

def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def vgrad(S, top, bot):
    img=Image.new("RGB",(S,S)); px=img.load()
    for y in range(S):
        c=lerp(top,bot,y/(S-1))
        for x in range(S): px[x,y]=c
    return img

def pin_mask(S,cx,cy,R,tip_y,hole_r):
    m=Image.new("L",(S,S),0); d=ImageDraw.Draw(m)
    d.ellipse([cx-R,cy-R,cx+R,cy+R],fill=255)
    dist=tip_y-cy
    if dist>R:
        a=math.acos(R/dist); th=math.atan2(cy-tip_y,0)
        L=math.sqrt(dist*dist-R*R)
        t1=(cx+math.cos(th+a)*L, tip_y+math.sin(th+a)*L)
        t2=(cx+math.cos(th-a)*L, tip_y+math.sin(th-a)*L)
        d.polygon([(cx,tip_y),t1,t2],fill=255)
    d.ellipse([cx-hole_r,cy-hole_r,cx+hole_r,cy+hole_r],fill=0)
    return m

def fit_font(text, target_px):
    return ImageFont.truetype(FONT, int(target_px))

def draw_centered(d, S, text, cy, size, fill, stroke=0, stroke_fill=None):
    f=fit_font(text,size)
    bb=d.textbbox((0,0),text,font=f,stroke_width=stroke)
    w=bb[2]-bb[0]; h=bb[3]-bb[1]
    x=(S-w)/2 - bb[0]
    y=cy - h/2 - bb[1]
    d.text((x,y),text,font=f,fill=fill,stroke_width=stroke,stroke_fill=stroke_fill)

def make(path,size=1024,
         days_y=0.135, oo_y=0.485, ny_y=0.815,
         days_s=0.20, oo_s=0.085, ny_s=0.235,
         pin_cy=0.40, pin_R=0.150, pin_tip=0.605, hole=0.055,
         oo_color=(233,66,110)):
    S=size*SS
    top,bottom=(255,150,58),(255,74,122)
    bg=vgrad(S,top,bottom).convert("RGBA")
    cx=S//2
    mask=pin_mask(S,cx,int(S*pin_cy),int(S*pin_R),int(S*pin_tip),int(S*hole))
    # shadow
    sh=Image.new("RGBA",(S,S),(90,20,45,255))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(S*0.016)).point(lambda v:int(v*0.28)))
    bg.alpha_composite(sh,(int(S*0.01),int(S*0.012)))
    white=Image.new("RGBA",(S,S),(255,255,255,255))
    bg=Image.composite(white,bg,mask)
    d=ImageDraw.Draw(bg)
    draw_centered(d,S,"Days",int(S*days_y),int(S*days_s),(255,255,255),
                  stroke=int(S*0.004),stroke_fill=(200,60,80))
    draw_centered(d,S,"out of",int(S*oo_y),int(S*oo_s),oo_color)
    draw_centered(d,S,"NY",int(S*ny_y),int(S*ny_s),(255,255,255),
                  stroke=int(S*0.004),stroke_fill=(200,60,80))
    bg=bg.resize((size,size),Image.LANCZOS).convert("RGB")
    bg.save(path); print("wrote",path)

make(f"{OUT}/text_pin.png")
