-- Small process pool for LuaJIT. Native spawning avoids shell filename quoting.
local ffi = require 'ffi'
local bit = require 'bit'
local M = {}

if ffi.os == 'Windows' then
	local fs = require 'fswin'
	ffi.cdef[[
		typedef struct {
			uint32_t cb;
			uint16_t *lpReserved, *lpDesktop, *lpTitle;
			uint32_t dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars;
			uint32_t dwFillAttribute, dwFlags;
			uint16_t wShowWindow, cbReserved2;
			uint8_t *lpReserved2;
			void *hStdInput, *hStdOutput, *hStdError;
		} FI_STARTUPINFOW;
		typedef struct {
			void *hProcess, *hThread;
			uint32_t dwProcessId, dwThreadId;
		} FI_PROCESS_INFORMATION;
		int __stdcall CreateProcessW(const uint16_t*, uint16_t*, void*, void*, int,
			uint32_t, void*, const uint16_t*, FI_STARTUPINFOW*, FI_PROCESS_INFORMATION*);
		uint32_t __stdcall WaitForSingleObject(void*, uint32_t);
		int __stdcall GetExitCodeProcess(void*, uint32_t*);
		int __stdcall CloseHandle(void*);
		uint32_t __stdcall GetLastError(void);
		uint32_t __stdcall GetModuleFileNameW(void*, uint16_t*, uint32_t);
		uint32_t __stdcall GetActiveProcessorCount(uint16_t);
		void* __stdcall GetStdHandle(uint32_t);
	]]

	function M.executable()
		local buf = ffi.new('uint16_t[32768]')
		local n = ffi.C.GetModuleFileNameW(nil, buf, 32768)
		assert(n > 0 and n < 32768, 'Cannot find the LuaJIT executable')
		return w2u(buf)
	end

	function M.cpu_count()
		return math.max(1, tonumber(ffi.C.GetActiveProcessorCount(0xffff)))
	end

	local function quote(s)
		return '"'..s:gsub('(\\*)"', '%1%1\\"'):gsub('(\\+)$', '%1%1')..'"'
	end
	M.quote = quote

	local function spawn(args)
		local command = {}
		for i, value in ipairs(args) do command[i] = quote(value) end
		local startup = ffi.new('FI_STARTUPINFOW')
		startup.cb = ffi.sizeof(startup)
		startup.dwFlags = 0x100 -- STARTF_USESTDHANDLES
		startup.hStdInput = ffi.C.GetStdHandle(0xfffffff6)
		startup.hStdOutput = ffi.C.GetStdHandle(0xfffffff5)
		startup.hStdError = ffi.C.GetStdHandle(0xfffffff4)
		local info = ffi.new('FI_PROCESS_INFORMATION')
		if ffi.C.CreateProcessW(u2w(args[1]), u2w(table.concat(command, ' ')), nil,
			nil, 1, 0, nil, nil, startup, info) == 0 then
			return nil, 'CreateProcessW failed: '..tonumber(ffi.C.GetLastError())
		end
		ffi.C.CloseHandle(info.hThread)
		return info.hProcess
	end

	local function wait(handle)
		local code = ffi.new('uint32_t[1]')
		local waited = ffi.C.WaitForSingleObject(handle, 0xffffffff)
		local gotcode = ffi.C.GetExitCodeProcess(handle, code)
		ffi.C.CloseHandle(handle)
		if waited ~= 0 or gotcode == 0 then return 1 end
		return tonumber(code[0])
	end
	M.spawn, M.wait = spawn, wait
	M.readfile, M.writefile = fs.readfile, fs.writefile
	function M.tmpname() return a2u(os.tmpname()) end
	function M.remove(path) rm(path) end
else
	ffi.cdef[[
		int fork(void);
		int execvp(const char*, const char* const*);
		int waitpid(int, int*, int);
		void _exit(int);
	]]
	function M.executable(args)
		local first = 0
		for index in pairs(args) do
			if type(index) == 'number' and index < first then first = index end
		end
		assert(first < 0, 'Cannot find the LuaJIT executable in arg')
		return args[first]
	end

	function M.cpu_count()
		local ok, pipe = pcall(io.popen, 'getconf _NPROCESSORS_ONLN 2>/dev/null', 'r')
		if not ok or not pipe then return 1 end
		local count = tonumber(pipe:read('*a')) or 1
		pipe:close()
		return math.max(1, count)
	end

	function M.spawn(args)
		local argv = ffi.new('const char*[?]', #args + 1)
		for i, value in ipairs(args) do argv[i - 1] = value end
		local pid = ffi.C.fork()
		if pid < 0 then return nil, 'fork failed: '..ffi.errno() end
		if pid == 0 then
			ffi.C.execvp(args[1], argv)
			ffi.C._exit(127)
		end
		return tonumber(pid)
	end

	function M.wait(pid)
		local status = ffi.new('int[1]')
		local result
		repeat result = ffi.C.waitpid(pid, status, 0)
		until result >= 0 or ffi.errno() ~= 4 -- EINTR
		if result < 0 or bit.band(status[0], 0x7f) ~= 0 then return 1 end
		return bit.band(bit.rshift(status[0], 8), 0xff)
	end

	function M.readfile(path)
		local file, err = io.open(path, 'rb')
		if not file then return nil, err end
		local data = file:read('*a')
		file:close()
		return data
	end

	function M.writefile(path, data)
		local file, err = io.open(path, 'wb')
		if not file then return nil, err end
		local ok, message = file:write(data)
		local closed, closeerr = file:close()
		if not ok or not closed then return nil, message or closeerr end
		return true
	end
	M.tmpname, M.remove = os.tmpname, os.remove
end

-- Launch first, then wait: waiting in launch order does not serialize the work.
function M.run(commands)
	local handles, statuses, err = {}, {}, nil
	for _, command in ipairs(commands) do
		local handle, message = M.spawn(command)
		if not handle then err = message; break end
		handles[#handles + 1] = handle
	end
	for i, handle in ipairs(handles) do statuses[i] = M.wait(handle) end
	if err then return nil, err end
	return statuses
end

return M
