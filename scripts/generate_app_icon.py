from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math
OUT="/tmp/icons"; FONT="/mnt/skills/examples/canvas-design/canvas-fonts/Outfit-Bold.ttf"

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
        a=math.acos(R/dist); L=math.sqrt(dist*dist-R*R)
        th=-math.pi/2
        t1=(cx+math.cos(th+a)*L, tip_y+math.sin(th+a)*L)
        t2=(cx+math.cos(th-a)*L, tip_y+math.sin(th-a)*L)
        d.polygon([(cx,tip_y),t1,t2],fill=255)
    d.ellipse([cx-hole_r,cy-hole_r,cx+hole_r,cy+hole_r],fill=0)
    return m
def centered(d,S,text,cy,size,fill,stroke=0,sfill=None):
    f=ImageFont.truetype(FONT,int(size))
    d.text((S/2,cy),text,font=f,fill=fill,anchor="mm",stroke_width=stroke,stroke_fill=sfill)

def pin_o(d,cx,cy,r,color,w):
    d.ellipse([cx-r,cy-r,cx+r,cy+r],outline=color,width=int(w))
    d.polygon([(cx,cy+r*1.55),(cx-r*0.58,cy+r*0.40),(cx+r*0.58,cy+r*0.40)],fill=color)

def middle_line(d,S,cy,size,color,sfill=None):
    f=ImageFont.truetype(FONT,int(size))
    t1="ut "; t2="f"
    w1=d.textlength(t1,font=f); w2=d.textlength(t2,font=f)
    od=size*0.98; r=od/2
    total=od+w1+od+w2
    x=(S-total)/2
    sw=int(size*0.045)
    pin_o(d,x+r,cy,r*0.86,color,r*0.40); x+=od
    d.text((x,cy),t1,font=f,fill=color,anchor="lm",stroke_width=sw,stroke_fill=sfill); x+=w1
    pin_o(d,x+r,cy,r*0.86,color,r*0.40); x+=od
    d.text((x,cy),t2,font=f,fill=color,anchor="lm",stroke_width=sw,stroke_fill=sfill)

def make(path,size=1024):
    S=size*SS
    top,bottom=(255,150,58),(255,74,122)
    bg=vgrad(S,top,bottom).convert("RGBA")
    cx=S//2
    # pin lowered slightly
    pin_cy,pin_R,pin_tip,hole=0.435,0.145,0.63,0.055
    mask=pin_mask(S,cx,int(S*pin_cy),int(S*pin_R),int(S*pin_tip),int(S*hole))
    sh=Image.new("RGBA",(S,S),(90,20,45,255))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(S*0.016)).point(lambda v:int(v*0.28)))
    bg.alpha_composite(sh,(int(S*0.01),int(S*0.012)))
    white=Image.new("RGBA",(S,S),(255,255,255,255))
    bg=Image.composite(white,bg,mask)
    d=ImageDraw.Draw(bg)
    centered(d,S,"Days",int(S*0.135),int(S*0.20),(255,255,255),int(S*0.004),(200,60,80))
    middle_line(d,S,int(S*0.745),int(S*0.078),(255,255,255),(200,60,80))  # white, below pin
    centered(d,S,"NY",int(S*0.855),int(S*0.185),(255,255,255),int(S*0.004),(200,60,80))
    bg=bg.resize((size,size),Image.LANCZOS).convert("RGB")
    bg.save(path); print("wrote",path)

SS=4
make(f"{OUT}/text_pin2.png")
