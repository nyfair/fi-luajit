fi-luajit
========

A LuaJIT interface to FreeImage

# Usage #

```lua
require 'fi'

convert('*.webp', 'bmp')
convbpp('*.png', 32, 'bmp')

b = open('back.bmp')
f = open('front.bmp')
out = composite(b, f)
save(out, 'composite.png')
...
```

*Note*: this FreeImage interface supports handling unicode filenames on Windows.  
In order to use this feature, make sure your lua script files are UTF-8 encoded.
