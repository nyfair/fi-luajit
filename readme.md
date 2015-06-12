fi-luajit
========

A LuaJIT interface to FreeImage

*Note*: this FreeImage interface supports handling unicode filenames on Windows.  
In order to use this feature, make sure your lua script files are UTF-8 encoded.

# Usage #

```lua
require 'fi'

---
# convert image format
convert('*.webp', 'tiff')
# convert image format and bpp
convbpp('*.png', 32, 'bmp')
# convert image format with quality setting
convert('1.png', '1.jpg', 90)

# alpha composite with 24bpp background 8bpp foreground
back = open('rgb24.bmp')
front = open('alpha8.bmp')
back_resized = scale(back, getw(front), geth(front))
back_rgba = to32(back_resized)
save(back_resized, 'resized.png', 9)
save(back_rgba, 'back.tiff')
out = composite(back_rgba, front)
save(out, 'composite.png')
freeAll({back_resized, front, out, back_rgba})
free(back)
...
```

CLI interface
```bash
# windows cmd with TrueType font
copy test\conv.lua to the same directory of luajit.exe
chcp 65001
# unix-like system
alias conv="noglob luajit test/conv.lua"

# convert image format
conv *.png jpg
conv 民逗Σ.dds 二マビ.webp
# convert image format and bpp
conv abc.jpg 32 abc.tiff
# convert image format with quality setting
conv 汉字.bmp 漢字.jpg 75 
```
