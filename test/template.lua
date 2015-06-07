require 'fi'

out='out/'
md(out)
for k,v in ipairs(ls('*.bmp')) do
	print(v)
	i=open(v)
	
	--[[
	do something
	]]--
	
	--[[
	free unused cache
	save(o,out..stripext(v)..'.bmp')
	freeAll({o, i})
	]]--
end
