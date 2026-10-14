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

local lookup = {'Warrior-Arms','Druid-Balance','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Paladin-Protection','DeathKnight-Blood','Priest-Shadow','Priest-Holy','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Evoker-Preservation','DeathKnight-Unholy','Druid-Feral','Shaman-Enhancement','DeathKnight-Frost','Mage-Frost','Hunter-Marksmanship','Mage-Fire',}
local provider = {region='US',realm='Kalecgos',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abraxos:BAAANQABCgYICwAAAA==.',
Ar='Arcanejel:BAAANQABCgEIAQAAAA==.',
Az='Azrielle:BAAANQADCgEIAQAAAA==.',
Ba='Barlartwo:BAAANQAECgUICwAAAA==.Bazts:BAAANQADCgQIBAAAAA==.Baztt:BAAANQAECgQIBwAAAA==.Bazty:BAAANQADCgEIAQAAAA==.',
Be='Belthazaar:BAAANQAECgIIAwAAAA==.',
Bi='Biller:BAAANQADCgcIFgAAAA==.',
Bl='Blade:BAABNQAECn8nAAIBAAkKECOKGQBRAwABAAkKECOKGQBRAwAAAA==.Blarneystone:BAAANQAECgQIBgAAAA==.Blitzed:BAAANQAECgYICAABNQAECgkJJwABABAjAA==.Bluemoon:BAAANQADCgQJBwAAAA==.',
Bo='Bootybleaps:BAACNQAFFH8PAAIBAAUKdhgQEQCmAQABAAUKdhgQEQCmAQA1AAQKfzcAAgEACQoBJeUIAKsDAAEACQoBJeUIAKsDAAAA.Bootybsneaks:BAAANQAECgYIBgAAAA==.',
Br='Breadth:BAAANQADCgUIBQAAAA==.Breakingwind:BAAANQADCgcIBwAAAA==.Brynhild:BAAANQAECgEIAQAAAA==.',
Bu='Bullievit:BAABNQAECn8nAAICAAkK/RzTGwDoAgACAAkK/RzTGwDoAgAAAA==.',
Ch='Chistery:BAAANQAECgIIBAAAAA==.',
Cm='Cmoobones:BAAANQAECgUICQAAAA==.',
Co='Cordi:BAAANQADCgcICwAAAA==.',
Cr='Cropop:BAABNQAECn8dAAMDAAkK5RntBgChAgADAAkK5RntBgChAgAEAAEK8wCKpgAEAAAAAA==.Crow:BAAANQAECgQIBAAAAA==.',
Da='Darallyn:BAAANQAECgIIAgAAAA==.Davik:BAAANQAECgEIAQAAAA==.',
De='Delmair:BAAANQADCgYICQAAAA==.Demonicaxe:BAAANQADCgEIAQAAAA==.Deucalion:BAAANQADCgUICgAAAA==.',
Dr='Dracene:BAAANQAECgUICgAAAA==.Dragosa:BAAANQADCgEIAQABNQAECgQIBAAFAAAAAA==.',
Du='Duf:BAAANQADCgEIAQAAAA==.',
Fa='Fafnir:BAABNQAECn8eAAIGAAgKJiT5BwAeAwAGAAgKJiT5BwAeAwAAAA==.',
Fl='Flaymignon:BAAANQADCgQIBAAAAA==.Fleshsicle:BAABNQAECn8aAAIHAAYKUga+ggDtAAAHAAYKUga+ggDtAAAAAA==.Flixs:BAAANQADCgEIAQABNQADCggIAgAFAAAAAA==.',
Ga='Gamera:BAAANQAECgUIBQAAAA==.Gankadin:BAAANQAECggIEwAAAA==.',
Gb='Gb:BAABNQAECn8UAAMIAAcKHh29JAAHAgAIAAcKHh29JAAHAgAJAAcK/RKHfACfAQAAAA==.',
Ge='Gentile:BAAANQAECgMIBAAAAA==.',
Gl='Glassnops:BAABNQAECn8ZAAIKAAkKSRG/oQA9AgAKAAkKSRG/oQA9AgAAAA==.',
Gr='Groobs:BAAANQADCgEIAQAAAA==.',
Ic='Icewolff:BAAANQABCgMIBQAAAA==.',
Ik='Ikinokoru:BAABNQAECn87AAILAAkKASQEBQC7AwALAAkKASQEBQC7AwAAAA==.',
Ir='Irene:BAAANQADCgYICgAAAA==.',
Je='Jeffren:BAAANQADCggIAgAAAA==.',
Ji='Jinsho:BAABNQAECn83AAIBAAkKdyMwCACxAwABAAkKdyMwCACxAwAAAA==.',
Ju='Julie:BAAANQAECgUIBwAAAA==.',
Ko='Kovo:BAAANQAECgQIBAABNQAECgkJOQAMAEUgAA==.Kovowolf:BAABNQAECn85AAMMAAkKRSBrCwAQAwAMAAkKRSBrCwAQAwACAAEKAAANswAuAAAAAA==.',
La='Laoch:BAAANQADCgIIAgAAAA==.',
Le='Leatherpapi:BAAANQADCgMIAwAAAA==.Lemonhead:BAAANQADCgMIAwAAAA==.',
Li='Linsay:BAACNQAFFH8VAAIIAAcKVhcjAgB0AgAIAAcKVhcjAgB0AgA1AAQKfzEAAggACQrpJOIHAFsDAAgACQrpJOIHAFsDAAAA.',
Ll='Llara:BAAANQAECgEIAQAAAA==.',
Lo='Lotieos:BAAANQAECgcICQAAAA==.Lovelypwr:BAABNQAECn8ZAAQIAAkKEhb+GQB7AgAIAAkKEhb+GQB7AgAJAAEKbAYH9QA8AAANAAEKfQSYLwAkAAAAAA==.',
Lu='Luçidity:BAABNQAECn8cAAMOAAYKjQvVrQAQAQAOAAYKjQvVrQAQAQAPAAIKtgOBBAF8AAAAAA==.',
Ma='Mannera:BAABNQAECn8ZAAIJAAkK6xmxLQCvAgAJAAkK6xmxLQCvAgAAAA==.Marcus:BAAANQAECgQIAwABNQAECgQIBAAFAAAAAA==.Matheris:BAAANQAECgcIEAAAAA==.Mawiyah:BAAANQAECgIIAgAAAA==.Max:BAAANQAECgIIAgABNQAECgkJNgAHACggAA==.',
Mi='Minibow:BAAANQADCgcIBwAAAA==.Ministry:BAAANQADCgEIAQAAAA==.',
Mo='Moonchai:BAAANQADCgYIBgABNQAECgQIBAAFAAAAAA==.',
Mu='Murdrmittens:BAAANQADCgUIBwABNQADCgYIBgAFAAAAAA==.Muth:BAAANQAECgUIBQAAAA==.Muthunter:BAAANQAECgUIDQABNQAECgUIBQAFAAAAAA==.',
Ne='Neceob:BAAANQABCgMIAwAAAA==.Nehemia:BAAANQABCgQIBQAAAA==.Never:BAACNQAFFH8jAAIQAAgKrBq3AQCwAgAQAAgKrBq3AQCwAgA1AAQKfxkAAhAACQrvIZAKAPoCABAACQrvIZAKAPoCAAAA.Nezukokamado:BAAANQAECgUIDwAAAA==.',
Ni='Nikallnight:BAAANQAECgIIAgAAAA==.Nitalzit:BAAANQAECgMIAwAAAA==.',
No='Nolan:BAAANQAECgQIBAAAAA==.',
Ob='Oblivionpwr:BAAANQAECgMIAwABNQAECgkJGQAIABIWAA==.',
Ok='Ok:BAAANQADCgEIAQAAAA==.',
Or='Oriah:BAAANQADCgMIAwAAAA==.',
Pa='Paliatarii:BAABNQAECn8ZAAIRAAcKhRUrSwDlAQARAAcKhRUrSwDlAQAAAA==.',
Ra='Rabioso:BAAANQABCggIEAAAAA==.Ragamon:BAAANQADCgUIAgAAAA==.',
Re='Reimu:BAAANQADCgUIBQAAAA==.Repentia:BAAANQAECgUICQAAAA==.',
Ro='Rockaden:BAAANQADCggICQABNQAECgUIBQAFAAAAAA==.Roksharuwolf:BAAANQAECgcIDQAAAA==.Ronnie:BAABNQAECn8fAAIRAAgK0wi8ZwBuAQARAAgK0wi8ZwBuAQAAAA==.',
Ru='Runa:BAAANQAECgIIAgABNQAECgkJOQAMAEUgAA==.',
Sa='Sadie:BAAANQAECgQIAwAAAA==.Sahlberg:BAAANQADCggIEQAAAA==.Salebrah:BAAANQABCgUIBwAAAA==.',
Sc='Schnief:BAAANQADCgUIBQAAAA==.',
Se='Senkestsu:BAAANQADCgYICwAAAA==.',
Sn='Sncak:BAAANQADCgcIBwAAAA==.',
So='Soren:BAAANQABCgYIBwAAAA==.',
Sp='Spiritwolf:BAABNQAECn8tAAISAAgKkB7cBwDbAgASAAgKkB7cBwDbAgAAAA==.Spiroheals:BAAANQADCgEIAQAAAA==.',
Sw='Swagcity:BAABNQAECn8nAAMPAAkKQBiWPQB8AgAPAAkKChiWPQB8AgATAAUKZxNgHgB1AQAAAA==.Swagsauce:BAAANQAECgIIAgAAAA==.',
Sy='Symphony:BAAANQADCggIGgAAAA==.Syrax:BAAANQAECgQIDAABNQAECgkJNgAHACggAA==.Syrieal:BAABNQAECn82AAMHAAkKKCDKDgA3AwAHAAkKKCDKDgA3AwAUAAEKXhF1qAA2AAAAAA==.',
Ta='Taiyla:BAABNQAECn8wAAMVAAkKeg+VEACaAQAKAAkKMAwgvAAKAgAVAAgKfQ2VEACaAQAAAA==.Talithiala:BAAANQAECgYIDQAAAA==.Tallai:BAAANQADCgYICQAAAA==.Taurentastic:BAAANQADCgcIBwABNQAECgkJNwABAHcjAA==.',
Te='Tejano:BAAANQADCgIIAgAAAA==.',
Th='Therionwolf:BAAANQADCggIDAAAAA==.Thorgrazer:BAAANQADCgYIBgABNQAECggIEAAFAAAAAA==.Thorin:BAAANQADCgIIAgAAAA==.',
To='Toomuchpwr:BAAANQADCgQIBAABNQAECgkJGQAIABIWAA==.',
Tr='Trip:BAABNQAECn8aAAMOAAgKsRoVnwA0AQAOAAUKERQVnwA0AQATAAUKyA7mIgAnAQAAAA==.Tristran:BAAANQAECgQIBAAAAA==.',
Ts='Tsabotavok:BAAANQADCgYIBgAAAA==.',
Tu='Tubbybuddy:BAABNQAECn8ZAAITAAgKSBPtEgA2AgATAAgKSBPtEgA2AgAAAA==.Tunafish:BAAANQADCgQIBAAAAA==.',
Un='Uniblue:BAACNQAFFH8QAAMOAAcKnRRgBAA0AgAOAAcKnRRgBAA0AgAPAAIKDhc6IQClAAA1AAQKfycAAw4ACQpjHhE3AIACAA4ACQpjHhE3AIACAA8ACArnIK08AIACAAAA.',
Va='Vamperella:BAAANQAECgEIAgAAAA==.Varashai:BAAANQAECgYIDQAAAA==.',
Wa='Wanye:BAABNQAECn8kAAMLAAkKoBzPQACmAgALAAkKaRvPQACmAgAWAAYKURYCMwCyAQAAAA==.',
We='Wenzr:BAAANQADCgYIBgAAAA==.',
Wh='Whisperdeath:BAAANQABCgUIBQAAAA==.',
Yi='Yiumi:BAABNQAECn8YAAIXAAkKUw2fAgAOAgAXAAkKUw2fAgAOAgAAAA==.',
Yl='Ylvis:BAABNQAECn8oAAILAAkKKRFSYgBPAgALAAkKKRFSYgBPAgAAAA==.',
Yo='You:BAAANQAECgcIEwAAAA==.',
Yu='Yulogee:BAAANQAECggICgAAAA==.',
Za='Zabrozo:BAAANQADCgEIAQAAAA==.',
Ze='Zemzelett:BAAANQAECgUIDgAAAA==.Zephy:BAAANQAECgQIBAAAAA==.Zerofuntion:BAAANQAECgIIAgAAAA==.Zerokillz:BAAANQADCgEIAQAAAA==.',
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
