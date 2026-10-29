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

local lookup = {'Paladin-Retribution','Mage-Arcane','Warrior-Arms','Warrior-Fury','Mage-Frost','Paladin-Protection','Shaman-Restoration','Unknown-Unknown','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Paladin-Holy','Druid-Feral','Druid-Balance','Druid-Guardian','Rogue-Assassination','Warlock-Demonology','Druid-Restoration','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','DeathKnight-Blood','Mage-Fire','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship','Priest-Discipline','Monk-Mistweaver','Warrior-Protection',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Abadar:BAABNQAECn85AAIBAAoKQCVgEQCDAwABAAoKQCVgEQCDAwAAAA==.Abug:BAAANQADCgQIBAAAAA==.',
An='Angelcaitlin:BAABNQAECn8UAAICAAgKvxEKdwBWAQACAAgKvxEKdwBWAQAAAA==.',
Ar='Argorok:BAABNQAECn8wAAMDAAoKaRCbVQCBAQADAAoKaRCbVQCBAQAEAAIKohJoLgBIAAAAAA==.',
As='Asakira:BAAANQADCgYIBgAAAA==.Asayis:BAAANQAECgEIAQAAAA==.',
Ay='Ayda:BAABNQAECn86AAMCAAoKJR5aWwDJAgACAAoKJR5aWwDJAgAFAAIKjx1OLQCTAAAAAA==.Aylla:BAAANQADCggICwAAAA==.',
Be='Belinara:BAAANQABCgUJCQAAAA==.Beloc:BAAANQAECggIAQAAAA==.',
Bl='Blesskrek:BAAANQADCgYIBwAAAA==.',
Bo='Boochili:BAABNQAECn85AAIGAAoK+iZpAAD7AwAGAAoK+iZpAAD7AwAAAA==.',
Ca='Cattle:BAAANQAECggIDAAAAA==.',
Ce='Cerulean:BAACNQAFFH8IAAIHAAMKxBzHDQAFAQAHAAMKxBzHDQAFAQA1AAQKfx8AAgcACgraI9UTAC0DAAcACgraI9UTAC0DAAAA.',
Ch='Chad:BAAANQAECgYIBgABNQAECggIDAAIAAAAAA==.Charlie:BAAANQAECgYIEgAAAA==.',
Cr='Creep:BAAANQAECgQIBAAAAA==.',
Cu='Cupid:BAAANQADCgEIAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABNQAECn9ZAAMHAAoKjiBQEgA2AwAHAAoKjiBQEgA2AwAJAAIKrx9o+ACjAAAAAA==.',
Da='Dagron:BAAANQAECgQIBAAAAA==.Dangers:BAAANQADCgcIBwAAAA==.Daniedk:BAABNQAECn8fAAMKAAkKPAhGdQBDAQAKAAkKcQdGdQBDAQALAAYK/Af7aQD3AAAAAA==.Darctotem:BAAANQAECgYIDwAAAA==.Darktemplar:BAABNQAECn8VAAIMAAgKjg+KswCdAQAMAAgKjg+KswCdAQAAAA==.',
De='Deadcontent:BAAANQAECgQIAwAAAA==.Demodara:BAAANQAECggIDQAAAA==.Devona:BAABNQAECn8dAAINAAYKQheZTQBgAQANAAYKQheZTQBgAQAAAA==.Deyasth:BAAANQAECgEIAQAAAA==.',
Di='Dingledangle:BAABNQAECn8pAAQOAAkKgw0CFwCJAQAOAAgKZQwCFwCJAQAPAAcKWgqWXgBWAQAQAAEK5RDjXAA8AAAAAA==.',
Do='Dogs:BAAANQAECggIDgABNQAFFAcIHQAMAHIhAA==.Dontmove:BAAANQAECgQIBQAAAA==.',
Dr='Dragoonnick:BAABNQAECn8vAAIRAAoK2hcnBwAtAgARAAoK2hcnBwAtAgAAAA==.',
Eu='Euphal:BAABNQAECn8/AAISAAoK/xW9JAAlAgASAAoK/xW9JAAlAgAAAA==.',
Ev='Evilpanda:BAAANQAECgcICgAAAA==.',
Fa='Faenghorn:BAABNQAECn8bAAQQAAoKjCKGAAD4AwAQAAkKACaGAAD4AwAOAAUKQB1ECQCwAQATAAIKAgDtiQADAAABNQAFFAMICgAQADMlAA==.',
Fe='Felangel:BAAANQADCgUIBgAAAA==.',
Fl='Flexicus:BAAANQAECgIIBAABNQAFFAYIFAACANYcAA==.',
Fr='Friesian:BAAANQABCgIIAwAAAA==.',
Ga='Gankstar:BAAANQADCggIDQAAAA==.',
Gh='Ghun:BAAANQAECgYIBgAAAA==.',
Gr='Gramsnatcher:BAAANQAECgIIAgAAAA==.Graycieden:BAABNQAECn8aAAIUAAYKJw1qJgDTAAAUAAYKJw1qJgDTAAAAAA==.',
Gu='Guldangit:BAACNQAFFH8gAAQVAAgKhiJrAQBEAQASAAUK4CEfCwC5AQAVAAQKCyNrAQBEAQAWAAIKCBVhCgClAAA1AAQKfzMABBUACgp5JnwAACUDABUACgqiIXwAACUDABIABwqSHqtUAFcCABYABgrGI+QMACkCAAAA.',
Ha='Hanora:BAAANQAECgIIAQAAAA==.',
He='Hellspawn:BAABNQAECn84AAIXAAoKZhD2MQAaAgAXAAoKZhD2MQAaAgAAAA==.Hermes:BAAANQADCgMJAwAAAA==.',
Ho='Hod:BAAANQADCgIIAgAAAA==.Holygrim:BAACNQAFFH8bAAIYAAgKxxyRAQDCAgAYAAgKxxyRAQDCAgA1AAQKfzYAAxgACgoiIyYLAC4DABgACgoiIyYLAC4DABQABAp0GLEmANEAAAAA.Holyloa:BAAANQADCgEIAQAAAA==.Holypablo:BAABNQAECn8oAAMYAAoKBBYVPwBuAgAYAAoKBBYVPwBuAgAUAAYKHRSwIQD6AAAAAA==.Howii:BAABNQAECn86AAMZAAoK5yXmAQDWAwAZAAoK5yXmAQDWAwAKAAEKAADr4QAyAAAAAA==.',
Is='Isabellaah:BAABNQAECn8bAAIMAAYKOgy5nwDvAAAMAAYKOgy5nwDvAAAAAA==.',
Je='Jeraziah:BAAANQADCggICgAAAA==.',
Jo='Johnnysins:BAABNQAECn84AAMEAAoKBCEGBABDAgAEAAgKriEGBABDAgADAAkK9RyMPgDWAQAAAA==.',
Ku='Kurama:BAAANQAECgMIAwAAAA==.',
La='Lainarning:BAAANQAECgEIAQAAAA==.Lapaladina:BAAANQAECgMIAwAAAA==.',
Li='Lift:BAAANQAECgYIBwABNQAFFAYIFAACANYcAA==.Litbit:BAAANQAECgIIAgAAAA==.Litbitonme:BAAANQAECgQIBAAAAA==.Litllit:BAABNQAECn8oAAISAAgKzwgahADsAAASAAgKzwgahADsAAAAAA==.',
Lo='Loharsh:BAAANQABCgQIBAABNQADCgYIBwAIAAAAAA==.Lostmoo:BAABNQAECn8WAAMPAAcKERXXTwCfAQAPAAcKERXXTwCfAQATAAMKOgbNXwCHAAAAAA==.Lostunholy:BAAANQADCgMIAwAAAA==.',
Lu='Lustypablo:BAAANQADCggJCAAAAA==.',
Mi='Mirant:BAAANQAECgQIBAAAAA==.',
['Mâ']='Mâchine:BAAANQAFFAIIBAABNQAFFAUIBgACAMwIAA==.',
Ni='Nickwilde:BAAANQAECggIAgAAAA==.',
No='Norstraum:BAAANQAECgQICQAAAA==.Noteveo:BAAANQADCgYIBgABNQAECgoKLgAWAFkTAA==.',
Op='Opallea:BAAANQAECgQIBAAAAA==.',
Ow='Owl:BAAANQAECgIIAwABNQAECggIDAAIAAAAAA==.',
Pa='Panixs:BAAANQAECgEIAQAAAA==.',
Pb='Pballs:BAAANQADCgQJBAABNQAECgoKKAAYAAQWAA==.',
Pe='Pendragon:BAABNQAECn8nAAIBAAoKGxFLSwDVAQABAAoKGxFLSwDVAQAAAA==.Periodic:BAABNQAECn8xAAIHAAkKUiKJEwAvAwAHAAkKUiKJEwAvAwAAAA==.',
Ph='Phoênîx:BAAANQADCgQJBwAAAA==.',
Po='Potter:BAABNQAECn8uAAICAAoK/xFcZwB6AQACAAoK/xFcZwB6AQAAAA==.',
Ra='Rahara:BAAANQABCgMIAwABNQAECgoKOgACACUeAA==.Raptor:BAACNQAFFH8UAAMCAAYK1hxbEAD0AQACAAYKYRxbEAD0AQAFAAEKxCHTDwBQAAA1AAQKfywABAIACgosJOgvACwDAAIACgosJOgvACwDAAUAAgo8F74hAGUAABoAAgrbFroFAEoAAAAA.',
Re='Renne:BAABNQAECn8cAAMHAAgKUxfBtAAEAQAHAAUK9hDBtAAEAQAJAAgKvA2EWgD9AAAAAA==.',
Ri='Rinni:BAABNQAECn8wAAIOAAkKEyPEAQAOAwAOAAkKEyPEAQAOAwAAAA==.',
Ro='Rovintis:BAABNQAECn8mAAIDAAcKWRTacQA1AQADAAcKWRTacQA1AQAAAA==.',
Ry='Rynne:BAABNQAECn8lAAIHAAoKiBphEQDFAgAHAAoKiBphEQDFAgAAAA==.',
Sa='Sansundertal:BAABNQAECn8zAAMbAAkKESJfBQBVAwAbAAkKESJfBQBVAwAcAAEKywrgOQBAAAAAAA==.',
Se='Sebei:BAABNQAECn8ZAAIBAAkKmBDnaACFAQABAAkKmBDnaACFAQAAAA==.Secksyest:BAAANQAECgUIBQAAAA==.Semirhaige:BAAANQAECgIIAgAAAA==.Sentinal:BAAANQAECgYIEAAAAA==.',
Sh='Shamu:BAAANQADCgQIBAAAAA==.',
Si='Silvertiger:BAABNQAECn85AAMdAAoK8RoSEADFAQAdAAoKlxoSEADFAQAMAAUKJRxT0gBcAQAAAA==.',
Sk='Skrump:BAAANQADCgMIAwABNQAECgcIDwAIAAAAAA==.',
Sl='Slabbydabby:BAAANQAECgQICgAAAA==.Slow:BAAANQADCgQIBAAAAA==.',
Sn='Snackyfraps:BAAANQADCggIEAABNQAECgoKKAAYAAQWAA==.',
So='Soleronys:BAAANQADCgUIBQABNQADCgYICAAIAAAAAA==.Sorynia:BAABNQAECn8pAAIMAAkKdwdSpgC5AQAMAAkKdwdSpgC5AQAAAA==.',
Su='Sukii:BAAANQADCggIDgAAAA==.Sully:BAAANQAECgQIBQABNQAECgYIDgAIAAAAAA==.',
Te='Teach:BAACNQAFFH8HAAQUAAMKWw3zEgCXAAAUAAMKWw3zEgCXAAAYAAIK+wzwNABGAAAeAAEKWQF4BQAsAAA1AAQKfysAAxQACgqMGXEaAHgCABQACQo+GHEaAHgCABgACgryExBTACoCAAAA.Terahealz:BAAANQAECgYIEwAAAA==.',
Th='Thunder:BAABNQAECn8eAAIJAAgKOAxgbwDSAQAJAAgKOAxgbwDSAQAAAA==.Thundrcheeks:BAABNQAECn8YAAIDAAgKQyNsKwAOAwADAAgKQyNsKwAOAwAAAA==.Thurbrew:BAABNQAECn8gAAIfAAkKkBCdFAAvAQAfAAkKkBCdFAAvAQAAAA==.',
Tr='Trankentree:BAAANQADCgYIBgAAAA==.',
Tu='Turnleft:BAABNQAECn8jAAITAAcKLSAoGAB+AgATAAcKLSAoGAB+AgAAAA==.',
Un='Unpuntable:BAABNQAECn8WAAIDAAcKfgT+pADCAAADAAcKfgT+pADCAAAAAA==.',
Va='Valerïan:BAAANQAECggICgAAAA==.Vauntdk:BAAANQADCgYIBgABNQAECgkJKAAgAFYlAA==.',
Ve='Vendetta:BAAANQAECgEIAQABNQAECggIDAAIAAAAAA==.Vercyv:BAAANQAECgcICAAAAA==.',
Vi='Viishnu:BAABNQAECn8XAAIPAAkKUw5zGQDHAQAPAAkKUw5zGQDHAQAAAA==.Violet:BAABNQAECn8nAAIKAAkKHCD5IgC5AgAKAAkKHCD5IgC5AgAAAA==.Vishlock:BAABNQAECn8kAAMVAAkKdBb1BQBWAgAVAAkKTBT1BQBWAgASAAgKMBMVaQAgAgABNQAECgkJFwAPAFMOAA==.',
Vo='Voida:BAAANQABCgIIAgABNQAECgoKOgACACUeAA==.',
Vp='Vpd:BAAANQAECggIDwAAAA==.',
Wa='Waban:BAAANQAECgUICQAAAA==.Waptor:BAAANQAECgMJAwAAAA==.',
Yi='Yipzdh:BAAANQAECggIBgAAAA==.',
Ze='Zenithmage:BAABNQAECn8uAAICAAoK6R6PGgCXAgACAAoK6R6PGgCXAgAAAA==.',
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
