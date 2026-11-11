-- The file is in public domain
-- nyfair (nyfair2012@gmail.com)

local ffi = require 'ffi'
ffi.cdef[[
	int mkdir(const char*, int);
]]

function ls(pattern)
	local files = {}
	if pattern == nil then
		pattern = './*'
	end
	-- Quote everything except * and ?: no command substitution, and no ls parsing.
	local glob = {}
	local pos = 1
	while true do
		local wildcard = pattern:find('[*?]', pos)
		local part = wildcard and pattern:sub(pos, wildcard - 1) or pattern:sub(pos)
		glob[#glob + 1] = "'"..part:gsub("'", "'\\''").."'"
		if not wildcard then break end
		glob[#glob + 1] = pattern:sub(wildcard, wildcard)
		pos = wildcard + 1
	end
	local output = assert(io.popen('for file in '..table.concat(glob)..
		'; do if [ -f "$file" ]; then printf "%s\\000" "$file"; fi; done', 'r'))
	local data = output:read('*a')
	output:close()
	for file in data:gmatch('([^%z]+)%z') do files[#files + 1] = file end
	table.sort(files)
	return files
end

function md(dst)
	ffi.C.mkdir(dst, 493) --0755
end

function rm(dst)
	os.remove(dst)
end

function mv(src, dst)
	os.rename(src, dst)
end
