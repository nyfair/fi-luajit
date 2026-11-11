-- The file is in public domain
-- nyfair (nyfair2012@gmail.com)

local ffi = require 'ffi'
local bit = require 'bit'
ffi.cdef[[
	struct WIN32_FIND_DATAW {
		uint32_t dwFileAttributes;
		uint32_t fileTimes[6];
		uint32_t nFileSizeHigh, nFileSizeLow, dwReserved0, dwReserved1;
		uint16_t cFileName[260];
		uint16_t cAlternateFileName[14];
	};
	
	void* __stdcall FindFirstFileW(const uint16_t* pattern, struct WIN32_FIND_DATAW* fd);
	int __stdcall FindNextFileW(void* ff, struct WIN32_FIND_DATAW* fd);
	int __stdcall FindClose(void* ff);
	int __stdcall CreateDirectoryW(const uint16_t* dst, void*);
	int __stdcall MoveFileW(const uint16_t* src, const uint16_t* dst);
	int __stdcall DeleteFileW(const uint16_t* dst);
	
	int __stdcall MultiByteToWideChar(unsigned int CodePage, uint32_t dwFlags, const char* lpMultiByteStr,
				int cbMultiByte, uint16_t* lpWideCharStr, int cchWideChar);
	int __stdcall WideCharToMultiByte(unsigned int CodePage, uint32_t dwFlags, const uint16_t* lpWideCharStr,
				int cchWideChar, char* lpMultiByteStr, int cchMultiByte,
				const char* default, int* used);
	uint16_t* __stdcall GetCommandLineW(void);
	uint16_t** __stdcall CommandLineToArgvW(const uint16_t*, int*);
	void* __stdcall LocalFree(void*);
	void* _wfopen(const uint16_t*, const uint16_t*);
	size_t fread(void*, size_t, size_t, void*);
	size_t fwrite(const void*, size_t, size_t, void*);
	int ferror(void*);
	int fclose(void*);
]]

local WIN32_FIND_DATA = ffi.typeof('struct WIN32_FIND_DATAW')
local INVALID_HANDLE = ffi.cast('void*', -1)

function u2w(str, code)
	local size = ffi.C.MultiByteToWideChar(code or 65001, 0, str, #str, nil, 0)
	assert(size > 0 or #str == 0, 'Invalid multibyte filename')
	local buf = ffi.new('uint16_t[?]', size + 1)
	if size > 0 then
		assert(ffi.C.MultiByteToWideChar(code or 65001, 0, str, #str, buf, size) > 0)
	end
	return buf
end

function w2u(wstr, code)
	local size = ffi.C.WideCharToMultiByte(code or 65001, 0, wstr, -1, nil, 0, nil, nil)
	assert(size > 0, 'Invalid UTF-16 filename')
	local buf = ffi.new("char[?]", size + 1)
	size = ffi.C.WideCharToMultiByte(code or 65001, 0, wstr, -1, buf, size, nil, nil)
	return ffi.string(buf)
end

function ls(pattern)
	local fd = ffi.new(WIN32_FIND_DATA)
	local tFiles = {}
	if pattern == nil then
		pattern = './*'
	end
	local path = pattern:match('^(.*[/\\])') or pattern:match('^(%a:)') or ''
	local hFile = ffi.C.FindFirstFileW(u2w(pattern), fd)
	if hFile ~= INVALID_HANDLE then
		ffi.gc(hFile, ffi.C.FindClose)
		repeat
			local fn = w2u(fd.cFileName)
			if bit.band(fd.dwFileAttributes, 0x10) == 0 then
				table.insert(tFiles, path..fn)
			end
		until ffi.C.FindNextFileW(hFile, fd) == 0
		ffi.C.FindClose(ffi.gc(hFile, nil))
	end
	table.sort(tFiles)
	return tFiles
end

function md(dst)
	ffi.C.CreateDirectoryW(u2w(dst), nil)
end

function rm(dst)
	ffi.C.DeleteFileW(u2w(dst))
end

function mv(src, dst)
	ffi.C.MoveFileW(u2w(src), u2w(dst))
end

function a2u(src, code)
	return w2u(u2w(src, code or 0))
end

-- Read the real Unicode command line rather than guessing the console code page.
local shell32 = ffi.load('shell32')
local function argv()
	local count = ffi.new('int[1]')
	local values = shell32.CommandLineToArgvW(ffi.C.GetCommandLineW(), count)
	assert(values ~= nil, 'Cannot read command line')
	local args = {}
	for i = 0, count[0] - 1 do args[#args + 1] = w2u(values[i]) end
	ffi.C.LocalFree(values)
	return args
end

local function readfile(path)
	local file = ffi.C._wfopen(u2w(path), u2w('rb'))
	if file == nil then return nil, 'Cannot read: '..path end
	local parts, buf = {}, ffi.new('char[8192]')
	while true do
		local n = tonumber(ffi.C.fread(buf, 1, 8192, file))
		if n == 0 then break end
		parts[#parts + 1] = ffi.string(buf, n)
	end
	local failed = ffi.C.ferror(file) ~= 0
	local result = ffi.C.fclose(file)
	if failed or result ~= 0 then return nil, 'Cannot read: '..path end
	return table.concat(parts)
end

local function writefile(path, data)
	local file = ffi.C._wfopen(u2w(path), u2w('wb'))
	if file == nil then return nil, 'Cannot write: '..path end
	local n = tonumber(ffi.C.fwrite(data, 1, #data, file))
	local result = ffi.C.fclose(file)
	if n ~= #data or result ~= 0 then return nil, 'Cannot write: '..path end
	return true
end

return {argv = argv, readfile = readfile, writefile = writefile}
