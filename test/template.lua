require 'fi'

local out = 'out/'
md(out)
for _, v in ipairs(ls('*.bmp')) do
	print(v)
	local i, err = open(v)
	assert(i, err)
	
	--[[
	do something
	]]--
	
	--[[
	free unused cache
	save(o,out..stripext(v)..'.bmp')
	free(o)
	]]--
	free(i)
end
