from PIL import Image, ImageDraw, ImageFont
SS=4; OUT="/tmp/icons"
MONO="/mnt/skills/examples/canvas-design/canvas-fonts/JetBrainsMono-Bold.ttf"

def make(path, size=1024, letter=(240,236,222)):
    S=size*SS
    bg=Image.new("RGB",(S,S),(12,12,14))
    # subtle vignette (lighter center)
    d=ImageDraw.Draw(bg,"RGBA")
    cxp,cyp=S/2,S/2
    import math
    # simple radial glow
    glow=Image.new("L",(S,S),0); gd=ImageDraw.Draw(glow)
    gd.ellipse([S*0.12,S*0.12,S*0.88,S*0.88],fill=60)
    from PIL import ImageFilter
    glow=glow.filter(ImageFilter.GaussianBlur(S*0.12))
    tint=Image.new("RGB",(S,S),(40,40,48))
    bg=Image.composite(tint,bg,glow)
    d=ImageDraw.Draw(bg)

    rows=["Days","Out Of","NY"]
    cols=max(len(r) for r in rows)   # 6
    margin_x=S*0.075
    avail=S-2*margin_x
    gap=0.0
    # tile width from cols with inter-tile gap = 0.11*tw
    g=0.11
    tw=avail/(cols+g*(cols-1))
    gapx=tw*g
    th=tw*1.34
    gapy=th*0.20
    total_h=3*th+2*gapy
    y0=(S-total_h)/2

    fsize=int(th*0.60)
    f=ImageFont.truetype(MONO,fsize)
    seam_w=max(2,int(S*0.0035))
    rad=int(tw*0.10)

    for ri,text in enumerate(rows):
        n=len(text)
        row_w=n*tw+(n-1)*gapx
        x0=(S-row_w)/2
        ty=y0+ri*(th+gapy)
        for ci,ch in enumerate(text):
            tx=x0+ci*(tw+gapx)
            box=[tx,ty,tx+tw,ty+th]
            # tile base
            d.rounded_rectangle(box,radius=rad,fill=(30,30,34))
            # top-half slightly lighter for 3D
            midy=ty+th/2
            d.rounded_rectangle([tx,ty,tx+tw,midy+rad],radius=rad,fill=(38,38,43))
            d.rectangle([tx,midy-1,tx+tw,midy+rad],fill=(38,38,43))
            d.rounded_rectangle([tx,midy,tx+tw,ty+th],radius=rad,fill=(26,26,30))
            d.rectangle([tx,midy,tx+tw,midy+2],fill=(26,26,30))
            # top edge highlight
            d.line([(tx+rad,ty+seam_w),(tx+tw-rad,ty+seam_w)],fill=(70,70,78),width=max(1,seam_w//2))
            # letter (skip space)
            if ch!=" ":
                d.text((tx+tw/2,ty+th/2),ch,font=f,fill=letter,anchor="mm")
            # split-flap seam across middle (over glyph)
            d.rectangle([tx,midy-seam_w//2,tx+tw,midy+seam_w//2],fill=(9,9,11))
            # tiny side pivots
            pr=max(2,int(tw*0.03))
            d.ellipse([tx-pr, midy-pr, tx+pr, midy+pr],fill=(70,70,76))
            d.ellipse([tx+tw-pr, midy-pr, tx+tw+pr, midy+pr],fill=(70,70,76))

    bg=bg.resize((size,size),Image.LANCZOS).convert("RGB")
    bg.save(path); print("wrote",path)

make(f"{OUT}/board_white.png", letter=(242,238,224))
make(f"{OUT}/board_amber.png", letter=(255,196,72))
