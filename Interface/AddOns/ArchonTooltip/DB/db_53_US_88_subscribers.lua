local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Druid-Guardian','Druid-Feral','Druid-Balance','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Warrior-Arms','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Affliction','Shaman-Elemental','Priest-Discipline','Hunter-BeastMastery','Evoker-Devastation','Shaman-Restoration','Mage-Arcane','Mage-Frost','Evoker-Preservation','Warlock-Destruction','Unknown-Unknown','DeathKnight-Unholy','Priest-Shadow','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood',}
local provider = {region='US',realm='EmeraldDream',name='US',type='subscribers',zone=53,date='2026-10-27',data={Ad='Adleymoon:BAECNQAFFH8gAAIBAAcKRCIcAADxAgeODQAABQBkAHUNAAAEAGIAfw0AAAUAYACpDQAABQBgAFwNAAAEAFwApA0AAAIAMwAzDQAABwBkAAEABwpEIhwAAPECB44NAAAFAGQAdQ0AAAQAYgB/DQAABQBgAKkNAAAFAGAAXA0AAAQAXACkDQAAAgAzADMNAAAHAGQANQAECn8yAAUBAAoKFybkAQC7AwABAAkK5SXkAQC7AwACAAgKCCUWCQC7AgADAAQKaiJjVgB+AQAEAAQKGiBKJwAjAQABNQAFFAgIEAAFADsgAA==.Adleytoll:BAEBNQAFFH8QAAIFAAgKOyDLAACpAgiODQAAAQBYAHUNAAABAFQAfw0AAAEAXgCpDQAAAQBTAFwNAAABADYAXQ0AAAUAWwBlDQAAAwBdADMNAAADAFwABQAICjsgywAAqQIIjg0AAAEAWAB1DQAAAQBUAH8NAAABAF4AqQ0AAAEAUwBcDQAAAQA2AF0NAAAFAFsAZQ0AAAMAXQAzDQAAAwBcAAAA.',
Al='Aldrasya:BAEBNQAECn8rAAMGAAoKayBKJABmAgqODQAACgBeAHUNAAAEAF8Afw0AAAUAWQCpDQAABgBYAFwNAAABAFwAXQ0AAAQAWwBlDQAABABGAKQNAAAFAEcAMw0AAAIATgC5DQAAAgA6AAYACAr8HkokAGYCCI4NAAAFAF4AdQ0AAAIAXQB/DQAAAQBJAKkNAAADAFgAXA0AAAEAXABdDQAAAgAtAGUNAAACAEQApA0AAAMARwAHAAkKcB4dFQA9AgmODQAABQBRAHUNAAACAF8Afw0AAAQAWQCpDQAAAwBUAF0NAAACAFsAZQ0AAAIARgCkDQAAAgA+ADMNAAACAE4AuQ0AAAIAOgAAAA==.Alleryia:BAEANQAECgIIAgABNQAFFAIIBQAIABYHAA==.',
Cj='Cjk:BAECNQAFFH8ZAAIJAAcKVw5JDQDdAQeODQAABQBDAHUNAAADABQAfw0AAAMAIgCpDQAABQAjAFwNAAACADEAXQ0AAAEACgAzDQAABgA5AAkABwpXDkkNAN0BB44NAAAFAEMAdQ0AAAMAFAB/DQAAAwAiAKkNAAAFACMAXA0AAAIAMQBdDQAAAQAKADMNAAAGADkANQAECn8lAAMJAAoKJxszZABiAgAJAAoKJxszZABiAgAKAAEKAAA0OgAAAAAAAA==.',
Da='Damio:BAEANQAECgYICwABNQAFFAgIHQALAF8OAA==.',
De='Dechu:BAEBNQAECn8mAAQMAAoKgRl3JgASAgqODQAABQBJAHUNAAADADwAfw0AAAMALACpDQAABABKAFwNAAAEAEgAXQ0AAAMAFQBlDQAABgBRAKQNAAAGAEsAMw0AAAIAIAC5DQAAAgA9AAwACQpKE3cmABICCY4NAAADAEUAdQ0AAAMAPAB/DQAAAwAsAKkNAAAEAEoAXA0AAAQASABdDQAAAwAVAGUNAAADABwApA0AAAMAEQAzDQAAAgAgAA0ABAonFzBsAMgABI4NAAACAEkAZQ0AAAIALgCkDQAAAgA3ALkNAAACAD0ADgACCsceViIArwACZQ0AAAEAUQCkDQAAAQBLAAE1AAUUBggaAAYA6iIA.',
Et='Etheryia:BAECNQAFFH8FAAIIAAIKFgf3HACAAAKODQAAAwATAKkNAAACABAACAACChYH9xwAgAACjg0AAAMAEwCpDQAAAgAQADUABAp/MQADDwAKCuAbJwcAMAIACAAJCrQaAVgATgIADwAICsscJwcAMAIAAAA=.',
Fr='Frostsprit:BAEANQAECgcIEQAAAA==.',
Ga='Gaping:BAEANQAECgYICwAAAA==.',
Ho='Holonna:BAEANQAECgIIAgABNQAFFAYIEwAQALoNAA==.Holymolio:BAECNQAFFH8dAAMLAAgKXw5NBgA1AgiODQAABQBQAHUNAAAEABQAfw0AAAQAUwCpDQAABAAlAFwNAAADAAwAXQ0AAAIADwBlDQAAAQACADMNAAAGACkACwAICl8OTQYANQIIjg0AAAUAUAB1DQAAAwAUAH8NAAAEAFMAqQ0AAAMAJQBcDQAAAwAMAF0NAAACAA8AZQ0AAAEAAgAzDQAABQApABEAAwqXBEECAL8AA3UNAAABABEAqQ0AAAEADwAzDQAAAQABADUABAp/PgADCwAKCiAknggAUwMACwAKCiAknggAUwMAEQAICuEMyQsAgQEAAAA=.Hossidan:BAEANQADCgEIAQABNQAFFAcIEQASAFIcAA==.',
Jb='Jbg:BAEANQADCgUIBQABNQAECgkJKQATAGIXAA==.',
Ke='Ketu:BAEANQAECggIDwAAAA==.',
Ki='Kifka:BAEANQAECgUIBQABNQAECgkJIQAHAJ4YAA==.Kirumar:BAEANQAECgcICAAAAA==.',
Kl='Klarth:BAEANQAECgcIEwABNQAFFAMIDwAUACcaAA==.',
Le='Levitoc:BAECNQAFFH8cAAMVAAgKcyFbBwBOAgiODQAABABgAHUNAAAEAE8Afw0AAAQAWwCpDQAABABbAFwNAAADAGAAXQ0AAAIAYQBlDQAAAQAzADMNAAAGAGIAFQAHCoUgWwcATgIHjg0AAAQAYAB1DQAABABPAH8NAAAEAFsAqQ0AAAQAWwBcDQAAAwBgAGUNAAABADMAMw0AAAYAYgAWAAEKHCaHCgBqAAFdDQAAAgBhADUABAp/KAACFQAKCnslHwMAVgMAFQAKCnslHwMAVgMAAAA=.',
Li='Liothen:BAEBNQAECn8UAAIXAAkK0QDpQQCSAAmODQAAAwADAHUNAAADAAAAfw0AAAMABACpDQAAAgAAAFwNAAACAAIAXQ0AAAIAAABlDQAAAgAAAKQNAAABAAEAMw0AAAIAAwAXAAkK0QDpQQCSAAmODQAAAwADAHUNAAADAAAAfw0AAAMABACpDQAAAgAAAFwNAAACAAIAXQ0AAAIAAABlDQAAAgAAAKQNAAABAAEAMw0AAAIAAwAAAA==.',
Ma='Maniacul:BAEBNQAECn8hAAMHAAkKnhhZDQCfAgmODQAABwBSAHUNAAAGAEoAfw0AAAQATACpDQAABgBRAFwNAAABAD4AXQ0AAAEABwBlDQAABABLAKQNAAACADoAMw0AAAIAPgAHAAkKnhhZDQCfAgmODQAABwBSAHUNAAAGAEoAfw0AAAQATACpDQAABQBRAFwNAAABAD4AXQ0AAAEABwBlDQAABABLAKQNAAACADoAMw0AAAIAPgAGAAEK1AWuqAArAAGpDQAAAQAOAAAA.',
Mo='Moodist:BAEANQAECgMIAwABNQAFFAYIGgAGAOoiAA==.',
Nu='Nurak:BAEANQADCgYIBgAAAA==.',
Og='Og:BAEBNQAECn8cAAMIAAgKvBxHWwBFAgiODQAABQBUAHUNAAAEAE0Afw0AAAQASwCpDQAABABJAFwNAAADAEUAXQ0AAAIAVAAzDQAABQBgALkNAAABADQACAAICmocR1sARQIIjg0AAAUAVAB1DQAAAwBIAH8NAAAEAEsAqQ0AAAQASQBcDQAAAwBFAF0NAAACAFQAMw0AAAUAYAC5DQAAAQA0ABgAAQpNHmNmAFYAAXUNAAABAE0AATUABAoICA8AGQAAAAA=.',
Op='Op:BAEANQAECgcIEgABNQAECggIDwAZAAAAAA==.',
Ph='Pharyngitis:BAEBNQAECn9GAAIaAAoK5RwmHADjAgqODQAADABVAHUNAAAKAFgAfw0AAAkAVwCpDQAACgBPAFwNAAAHAFQAXQ0AAAUAVABlDQAABQBLAKQNAAAEAD8AMw0AAAYAWAC5DQAAAgAeABoACgrlHCYcAOMCCo4NAAAMAFUAdQ0AAAoAWAB/DQAACQBXAKkNAAAKAE8AXA0AAAcAVABdDQAABQBUAGUNAAAFAEsApA0AAAQAPwAzDQAABgBYALkNAAACAB4AAAA=.',
Pw='Pwrdpando:BAECNQAFFH8yAAQLAAkKFxuhAAAnAwmODQAABwBZAHUNAAAGAB4Afw0AAAcAWQCpDQAABgApAFwNAAAFAFkAXQ0AAAQANQBlDQAAAwBNAKQNAAADAEEAMw0AAAkAWQALAAkKFxuhAAAnAwmODQAABQBZAHUNAAAGAB4Afw0AAAcAWQCpDQAABgApAFwNAAAFAFkAXQ0AAAQANQBlDQAAAQBNAKQNAAADAEEAMw0AAAkAWQARAAEKcAKoAwBUAAFlDQAAAgAGABsAAQpTF7MPAEoAAY4NAAACADsANQAECn8rAAQLAAoKTSJrFQAlAwALAAoKUSFrFQAlAwARAAMKOyYRDgBPAQAbAAIKByGBUwDAAAABNQABCgIIAgAZAAAAAA==.',
Ra='Rayocchi:BAEANQAECgEIAQABNQAECgoKJwAcAEYeAA==.Rayocell:BAEBNQAECn8nAAMcAAoKRh74MgCZAgqODQAABgBcAHUNAAAEAEUAfw0AAAMAWwCpDQAABABOAFwNAAAEAFMAXQ0AAAQAVwBlDQAABQAoAKQNAAADAE8AMw0AAAQAPgC5DQAAAgBaABwACgpGHvgyAJkCCo4NAAAFAFwAdQ0AAAMARQB/DQAAAwBbAKkNAAADAE4AXA0AAAMAUwBdDQAAAwBXAGUNAAACACgApA0AAAEATwAzDQAAAwA+ALkNAAACAFoAHQAICj8a37kAqQEIjg0AAAEAPwB1DQAAAQBIAKkNAAABADAAXA0AAAEAUABdDQAAAQBHAGUNAAADAFIApA0AAAIANAAzDQAAAQA6AAAA.Rayogizer:BAEBNQAECn8XAAILAAoKeB7pGwADAwqODQAAAwBPAHUNAAADAE0Afw0AAAMAYQCpDQAAAwBdAFwNAAACAD0AXQ0AAAIAVwBlDQAAAgBPAKQNAAADAEsAMw0AAAEAMQC5DQAAAQBNAAsACgp4HukbAAMDCo4NAAADAE8AdQ0AAAMATQB/DQAAAwBhAKkNAAADAF0AXA0AAAIAPQBdDQAAAgBXAGUNAAACAE8ApA0AAAMASwAzDQAAAQAxALkNAAABAE0AATUABAoKCicAHABGHgA=.',
Sn='Snigmorder:BAECNQAFFH8aAAMGAAYK6iIQAgB5AgaODQAABgBhAHUNAAAFAFsAfw0AAAUAUgCpDQAABgBhAFwNAAADAD8AXQ0AAAEAYAAGAAYK6iIQAgB5AgaODQAABQBhAHUNAAAFAFsAfw0AAAQAUgCpDQAABgBhAFwNAAADAD8AXQ0AAAEAYAAHAAIKkg8hDwCZAAKODQAAAQAnAH8NAAABACQANQAECn8xAAMHAAoKrSUuBABAAwAHAAoKBSQuBABAAwAGAAkKPSQ9EQDzAgAAAA==.',
Sp='Splashofray:BAEANQAECgQIBAABNQAECgoKJwAcAEYeAA==.',
Th='Thwonknchad:BAECNQAFFH8dAAIFAAgKHSWEAADTAgiODQAABQBhAHUNAAAEAGAAfw0AAAQARQCpDQAABABiAFwNAAADAGIAXQ0AAAIAYgBlDQAAAQBQADMNAAAGAGQABQAICh0lhAAA0wIIjg0AAAUAYQB1DQAABABgAH8NAAAEAEUAqQ0AAAQAYgBcDQAAAwBiAF0NAAACAGIAZQ0AAAEAUAAzDQAABgBkADUABAp/QwACBQAKCsAmQgAAkgMABQAKCsAmQgAAkgMAAAA=.',
Vh='Vhader:BAEBNQAECn8vAAIeAAoKDxy1EQAfAwqODQAACABhAHUNAAAGAFkAfw0AAAUAVACpDQAABgBbAFwNAAAFAF8AXQ0AAAUAGgBlDQAABQBGAKQNAAACAEoAMw0AAAQAWgC5DQAAAQAcAB4ACgoPHLURAB8DCo4NAAAIAGEAdQ0AAAYAWQB/DQAABQBUAKkNAAAGAFsAXA0AAAUAXwBdDQAABQAaAGUNAAAFAEYApA0AAAIASgAzDQAABABaALkNAAABABwAAAA=.',
['Wú']='Wú:BAEANQAECgUIBwABNQAECgcICAAZAAAAAA==.',
Zo='Zogado:BAEBNQAECn8kAAMUAAgKeSBpJwAUAgiODQAABgBjAHUNAAAGAFgAfw0AAAYAXACpDQAABQBgAFwNAAAFAFoAXQ0AAAMAPwBlDQAAAgBYADMNAAADAC4AFAAICnkgaScAFAIIjg0AAAQAYwB1DQAABgBYAH8NAAAGAFwAqQ0AAAMAYABcDQAABQBaAF0NAAADAD8AZQ0AAAIAWAAzDQAAAgAuABAAAwoAHVPZAOIAA44NAAACAEAAqQ0AAAIAUwAzDQAAAQBBAAAA.',
['Øg']='Øg:BAEANQAECgMIAwABNQAECggIDwAZAAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
