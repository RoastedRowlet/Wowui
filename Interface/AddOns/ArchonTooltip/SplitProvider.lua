---@class Private
local Private = select(2, ...)

---@alias SplitType 'none'|'fnv'

local FNV_PRIME = 16231
local FNV_OFFSET_BASIS = 9348

---Implements FNV-1a modified to 14-bit on the bytes of `str`. The result is modulo'd by `modulo`.
---@param str string
---@param modulo number
---@return number
local function hashFnv(str, modulo)
	local hash = FNV_OFFSET_BASIS
	for i = 1, #str do
		local byte = string.byte(str, i)
		hash = bit.bxor(hash, byte)
		hash = bit.band(hash * FNV_PRIME, 0x3fff)
	end

	return math.fmod(hash, modulo)
end

---@param provider Provider
---@param characterName string
---@param realmName string
---@return number
function Private.GetSplitProviderIndex(provider, characterName, realmName)
	if provider.splitType == "fnv" then
		return hashFnv(characterName, provider.splitCount)
	else
		return 0
	end
end
