-- Format conversion only. Public arguments: input, output, [save flag].
local ffi = require 'ffi'
local script = arg[0]
local directory = script:match('^(.*[/\\])') or './'
package.path = directory..'?.lua;'..directory..'../?.lua;'..package.path

if ffi.os == 'Windows' then
	local fs = require 'fswin'
	local argv = fs.argv()
	-- The last #arg arguments are script arguments, even with interpreter options.
	script = argv[#argv - #arg]
	for i = 1, #arg do arg[i] = argv[#argv - #arg + i] end
end

-- Also work from another directory, without requiring a LUA_PATH adjustment.
directory = script:match('^(.*[/\\])') or './'
package.path = directory..'?.lua;'..directory..'../?.lua;'..package.path
require 'fi'

local function report(message)
	io.stderr:write(tostring(message), '\n')
end

local function usage()
	report('Usage: luajit conv.lua input output [save_flag]')
	report('       luajit conv.lua "*.bmp" png [save_flag]')
	report('save_flag: decimal or hex integer; metadata is always stripped.')
	report('Defaults: JPEG quality 90; PNG level 9; WebP/JXL lossless.')
	report('Explicit WebP flags also enable SharpYUV. FI_JOBS overrides worker count.')
	return 2
end

local function convert_tasks(tasks, flag)
	local failures = 0
	for _, task in ipairs(tasks) do
		local ok, result, err = pcall(convert, task[1], task[2], flag)
		if not ok or not result then
			failures = failures + 1
			report(task[1]..': '..tostring(ok and err or result))
		else
			print(task[1]..' -> '..task[2])
		end
	end
	return failures == 0 and 0 or 1
end

-- Length-prefixed data, not executable Lua; handles quotes and newlines in paths.
local function pack(tasks, flag)
	local parts = {tostring(flag), '\n'}
	for _, task in ipairs(tasks) do
		for _, name in ipairs(task) do
			parts[#parts + 1] = tostring(#name)..'\n'..name
		end
	end
	return table.concat(parts)
end

local function unpack_tasks(data)
	local pos = 1
	local function number()
		local first, last, text = data:find('(%-?%d+)\n', pos)
		assert(first == pos, 'Invalid worker manifest')
		pos = last + 1
		return assert(tonumber(text))
	end
	local flag, tasks = number(), {}
	while pos <= #data do
		local task = {}
		for i = 1, 2 do
			local length = number()
			assert(length > 0 and pos + length - 1 <= #data, 'Invalid worker path')
			task[i] = data:sub(pos, pos + length - 1)
			pos = pos + length
		end
		tasks[#tasks + 1] = task
	end
	return tasks, flag
end

local function main()
	if #arg == 2 and arg[1] == '--worker' then
		local process = require 'process'
		local data, err = process.readfile(arg[2])
		assert(data, err)
		local tasks, flag = unpack_tasks(data)
		return convert_tasks(tasks, flag)
	end
	if #arg ~= 2 and #arg ~= 3 then return usage() end
	local input, output, flag = arg[1], arg[2], nil
	if arg[3] then
		flag = tonumber(arg[3])
		if not flag or flag ~= math.floor(flag) or flag < -2147483648 or flag > 4294967295 then
			report('save_flag must be a 32-bit decimal or hexadecimal integer.')
			return 2
		end
	end
	local wildcard = input:find('[*?]') ~= nil
	local tasks = {}
	if wildcard then
		if not output:match('^%.?[%w]+$') then
			report('Wildcard output must be a format/extension, e.g. png or jxl.')
			return 2
		end
		output = output:gsub('^%.', ''):lower()
		for _, name in ipairs(ls(input)) do
			tasks[#tasks + 1] = {name, stripext(name)..'.'..output}
		end
		if #tasks == 0 then report('No files matched: '..input); return 1 end
	else
		tasks[1] = {input, output}
	end
	if not cansave(getoutputfmt(tasks[1][2])) then
		report('Unsupported output format: '..output)
		return 2
	end
	flag = saveflag(tasks[1][2], flag)
	-- Refuse ambiguous batches instead of letting workers race to overwrite a file.
	local destinations = {}
	for _, task in ipairs(tasks) do
		local key = ffi.os == 'Windows' and task[2]:lower() or task[2]
		if destinations[key] then
			report('Multiple inputs have the same output: '..task[2])
			return 2
		end
		destinations[key] = true
	end
	local process = require 'process'
	local override = os.getenv('FI_JOBS')
	local jobs
	if override then jobs = tonumber(override) else jobs = process.cpu_count() end
	if not jobs or jobs < 1 or jobs == math.huge or jobs ~= math.floor(jobs) then
		report('FI_JOBS must be a positive integer.'); return 2
	end
	jobs = math.min(jobs, #tasks)
	if jobs == 1 then return convert_tasks(tasks, flag) end

	-- Snapshot the inputs once; one persistent process per round-robin partition.
	local groups, paths, commands = {}, {}, {}
	for i = 1, jobs do groups[i] = {} end
	for i, task in ipairs(tasks) do
		local group = groups[(i - 1) % jobs + 1]
		group[#group + 1] = task
	end
	local ok, result = pcall(function()
		local executable = process.executable(arg)
		for i, group in ipairs(groups) do
			local path = process.tmpname()
			paths[#paths + 1] = path
			local written, err = process.writefile(path, pack(group, flag))
			assert(written, err)
			commands[i] = {executable, script, '--worker', path}
		end
		print(string.format('Converting %d files with %d workers', #tasks, jobs))
		io.stdout:flush()
		local statuses, err = process.run(commands)
		assert(statuses, err)
		for _, status in ipairs(statuses) do if status ~= 0 then return 1 end end
		return 0
	end)
	for _, path in ipairs(paths) do process.remove(path) end
	if not ok then report(result); return 1 end
	return result
end

local ok, status = pcall(main)
if not ok then report(status); status = 1 end
os.exit(status)
