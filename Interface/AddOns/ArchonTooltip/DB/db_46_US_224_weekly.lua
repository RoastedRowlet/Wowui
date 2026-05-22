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

local lookup = {'Warrior-Fury','Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Druid-Feral','Mage-Frost','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow',}
local provider = {region='US',realm='Tortheldrin',name='US',type='weekly',zone=46,date='2026-05-17',data={Ac='Acquinus:BAAALgAECgEJAQAAAA==.',
Ad='Adonis:BAAALgAECgMJBQAAAA==.',
Ag='Agatha:BAAALgAECgQJCAAAAA==.',
Al='Altreyuzz:BAAALgADCgUJBQAAAA==.',
An='Anastarya:BAAALgADCgYJCgAAAA==.',
Ap='Apocalypse:BAABLgAECn8XAAIBAAkJYwayXwAxAQABAAkJYwayXwAxAQAAAA==.',
Ar='Armageddon:BAAALgAECgkJCQAAAA==.Arockoner:BAAALgADCgEJAQAAAA==.',
As='Astrozerg:BAAALgAECggJCAABLgAFFAUJGAACAM8mAA==.',
Az='Azeroth:BAAALgADCgYJBgAAAA==.Azin:BAAALgAFFAQJBAAAAA==.',
Ba='Baen:BAAALgAECgYJCgAAAA==.',
Be='Bearju:BAAALgAECgIJBAAAAA==.Bet:BAAALgADCgMJAwABLgAECgUJCgADAAAAAA==.',
Br='Braxticus:BAAALgADCgYJDQAAAA==.Bruceyuu:BAAALgAECgYJDQAAAA==.',
Bu='Bubble:BAAALgAECgYJDAAAAA==.',
Ca='Cassidin:BAACLgAFFH8FAAIEAAIJ7x/uTgC8AAAEAAIJ7x/uTgC8AAAuAAQKfxcAAgQACAniHKgvAGQCAAQACAniHKgvAGQCAAAA.Cataclysm:BAAALgAECgkJAgAAAA==.',
Ch='Chammick:BAAALgADCgIJAgAAAA==.Chooch:BAAALgAECgYJEgAAAA==.',
Ci='Cidril:BAAALgAECgYJEwAAAA==.',
Cr='Creating:BAABLgAECn8fAAIEAAgJ1R25OABAAgAEAAgJ1R25OABAAgABLgAFFAIJAgADAAAAAA==.Creep:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Crk:BAAALgAECgQJBQABLgAFFAIJAgADAAAAAA==.Crkgetd:BAAALgAECgEJAQABLgAFFAIJAgADAAAAAA==.Cryptik:BAAALgADCgEJAQAAAA==.Cryptoprocta:BAAALgADCgUJCAAAAA==.',
De='Deathslip:BAAALgAECgEJAQABLgAECgUJCAADAAAAAA==.Devilneroo:BAAALgAECgYJEgAAAA==.',
Do='Doobiesnibs:BAAALgAECgYJDAAAAA==.Doomzilla:BAAALgAECgcJBgAAAA==.Doth:BAABLgAECn8WAAIFAAYJESI2UQD+AQAFAAYJESI2UQD+AQAAAA==.',
Dr='Drakknar:BAAALgAECgcJBwAAAA==.Drogyn:BAAALgAECgEJAQAAAA==.',
Dv='Dvlock:BAAALgAECgUJCQAAAA==.',
['Dò']='Dòóm:BAAALgAECgQJBwAAAA==.',
['Dó']='Dóóm:BAAALgADCgUJBQAAAA==.',
Ek='Ekrizdis:BAAALgADCgEJAgAAAA==.',
Em='Emryss:BAAALgAECgQJBAAAAA==.',
Ex='Exile:BAAALgAECgUJBgAAAA==.',
Fu='Furfoxsake:BAAALgADCgIJAgAAAA==.',
Gi='Gigilong:BAACLgAFFH8GAAIGAAMJdhu7GwAXAQAGAAMJdhu7GwAXAQAuAAQKfx0AAgYABwmcI5EWAM0CAAYABwmcI5EWAM0CAAAA.Gihon:BAAALgADCgcJFwAAAA==.',
Go='Gorrdain:BAAALgADCgEJAQAAAA==.Gorrgath:BAAALgAECgYJCgAAAA==.',
Gr='Grandeur:BAAALgADCgkJCQAAAA==.Greencrayon:BAAALgAECgIJAgAAAA==.Gristlezerg:BAAALgAECgIJAgABLgAFFAUJGAACAM8mAA==.',
Hi='Hippopotamus:BAAALgAECgYJDQAAAA==.',
Ho='Holyhealz:BAAALgAECgMJAwAAAA==.',
Id='Idiotdk:BAAALgAFFAIJAwABLgAFFAMJCAAHAH0XAA==.',
Il='Illyria:BAAALgADCgUJAQAAAA==.',
Ir='Ironheart:BAABLgAECn8WAAIEAAgJ9BASUwCUAQAEAAgJ9BASUwCUAQAAAA==.',
Ja='Jackmerious:BAABLgAECn8cAAIIAAgJZxLiWgCVAQAIAAgJZxLiWgCVAQAAAA==.Jadefire:BAAALgAECgIJAQAAAA==.Jasnah:BAABLgAECn8lAAIBAAgJvBVQHwC0AQABAAgJvBVQHwC0AQAAAA==.',
Je='Jefry:BAAALgADCgYJBgAAAA==.Jermomu:BAAALgAECgQJBQAAAA==.',
Ji='Jinai:BAAALgAECgYJDwABLgAECgYJEgADAAAAAA==.',
Jo='Johnnysalami:BAAALgADCgQJBAAAAA==.',
Ju='Julita:BAAALgAECgQJBQAAAA==.',
Ka='Kaggar:BAAALgAECgcJDQAAAA==.',
Ke='Keytosuccess:BAAALgAECgUJCAAAAA==.',
Ki='Killwhat:BAACLgAFFH8MAAIIAAMJMh1bTwARAQAIAAMJMh1bTwARAQAuAAQKfzMAAggACAk0JL8QAMcCAAgACAk0JL8QAMcCAAAA.',
Kl='Klint:BAAALgAFFAIJAgAAAA==.',
Ko='Korthyn:BAABLgAECn8bAAQJAAkJZxkRCQBRAgAJAAgJsBwRCQBRAgAKAAQJpBJLGgD3AAALAAEJhhOTbwA4AAAAAA==.',
Ku='Kurnoth:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.',
Lo='Lothus:BAAALgADCgMJAwAAAA==.',
Ma='Magely:BAAALgADCggJCAAAAA==.',
Me='Merkules:BAAALgAECgYJDAAAAA==.',
Mo='Moxie:BAACLgAFFH8WAAIMAAYJtxV9CwDOAQAMAAYJtxV9CwDOAQAuAAQKfyUAAgwACAk1JL8CAEkDAAwACAk1JL8CAEkDAAAA.',
Ms='Msdranderson:BAABLgAECn8tAAINAAcJigpbLQAkAQANAAcJigpbLQAkAQAAAA==.',
Ne='Nero:BAAALgAECgUJCwABLgAECgYJEgADAAAAAA==.',
Ni='Nipps:BAAALgADCgQJCgAAAA==.',
On='Onatoe:BAAALgAECgMJAwAAAA==.',
Oo='Oo:BAAALgAECgUJBQAAAA==.',
Op='Op:BAAALgADCgcJAgAAAA==.',
Or='Orius:BAAALgAECgMJBAAAAA==.',
Pa='Parsimony:BAAALgADCgUJBQAAAA==.',
Pe='Pestilent:BAAALgAECgIJAgAAAA==.',
Po='Poj:BAAALgAECgMJBgAAAA==.Pojins:BAAALgAECgIJAgAAAA==.',
Pr='Pratt:BAAALgADCgcJBwAAAA==.',
Pu='Purple:BAABLgAECn8lAAIEAAkJEhg8KAAjAgAEAAkJEhg8KAAjAgAAAA==.',
Ra='Raviel:BAAALgADCgQJBAAAAA==.',
Re='Regret:BAABLgAECn8XAAIOAAcJsiI+DABQAgAOAAcJsiI+DABQAgABLgAFFAYJGgAOAGggAA==.',
Ro='Rogué:BAAALgADCgQJBAAAAA==.',
Ru='Rueal:BAAALgADCgEJAQAAAA==.Rukar:BAAALgAECgQJBwAAAA==.',
Sa='Sabra:BAAALgAECgQJBQABLgAECgUJCgADAAAAAA==.Saia:BAAALgAECgUJEAAAAA==.Samanosuke:BAAALgAECgEJAQAAAA==.',
Se='Seleren:BAAALgADCgEJAQAAAA==.Serapphina:BAAALgAECgIJAgAAAA==.',
Si='Silverfangz:BAAALgADCgEJAQAAAA==.',
Sn='Snipedbaby:BAAALgAECgMJAgAAAA==.',
Su='Superfist:BAACLgAFFH8VAAIPAAUJbxtCCQBDAQAPAAUJbxtCCQBDAQAuAAQKfyYAAw8ACAnGIkMGABwDAA8ACAnGIkMGABwDABAABwmUHhcOAGUCAAAA.',
['Så']='Såbra:BAAALgADCgEJAQAAAA==.',
Ta='Tavitusk:BAAALgAECgMJAwAAAA==.Tayonhands:BAAALgAECgYJCwAAAA==.',
Te='Tehgimp:BAABLgAECn8sAAIRAAkJggxNCwCoAQARAAkJggxNCwCoAQAAAA==.',
Ti='Tinder:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgMJAwAAAA==.',
Tr='Trakanon:BAABLgAECn8uAAQJAAgJcBxuBAD5AQAJAAgJcBxuBAD5AQALAAUJQhNMPAD9AAAKAAYJEQoXGgD6AAAAAA==.Treezus:BAAALgAECgEJAQAAAA==.Trouthunter:BAAALgAECggJDwAAAA==.',
Ts='Tsuyoikuma:BAAALgADCgkJGQAAAA==.',
Ug='Ugornargol:BAAALgADCgEJAQABLgAECgcJBwADAAAAAA==.',
Uu='Uu:BAAALgAECgkJEwAAAA==.',
Uw='Uwu:BAAALgADCgcJDgAAAA==.',
Va='Valicore:BAABLgAECn8aAAISAAgJNxOYQgDqAQASAAgJNxOYQgDqAQAAAA==.Vansftw:BAAALgAECggJDwAAAA==.Varithak:BAAALgADCgYJBgAAAA==.',
Ve='Vestrevus:BAAALgAECgUJEAAAAA==.',
Vg='Vginny:BAAALgADCgUJBQAAAA==.',
Vi='Violetta:BAAALgAECgYJDAABLgADCgYJCgADAAAAAA==.',
Vo='Vonix:BAAALgADCgMJAwAAAA==.Vorcthal:BAABLgAECn8aAAMMAAkJFxfuCgB6AgAMAAkJFxfuCgB6AgATAAgJGg06JgBRAQAAAA==.Voren:BAAALgADCgQJBAAAAA==.Vorenormu:BAABLgAECn8dAAQLAAgJhxMpIQCMAQALAAgJ2BIpIQCMAQAKAAMJVgOnPgB1AAAJAAIJ4hCSNABwAAABLgAECgkJGgAMABcXAA==.',
Vy='Vyre:BAAALgADCgYJCgABLgAECggJHAAIAGcSAA==.',
Wa='Waste:BAAALgAECgIJAgAAAA==.',
Wi='Wingzero:BAAALgAECgIJAgAAAA==.',
Xe='Xero:BAAALgADCgUJBQAAAA==.',
Xo='Xoloteku:BAAALgADCgIJAgAAAA==.',
Xx='Xxz:BAAALgAECgcJBgAAAA==.',
Za='Zaelor:BAAALgAECgcJBgABLgAECgkJGgASADcTAA==.Zandros:BAAALgAECgcJBwAAAA==.',
Ze='Zen:BAAALgADCgQJBAABLgAECgYJBgADAAAAAA==.Zergdh:BAAALgADCgcJBwABLgAFFAUJGAACAM8mAA==.Zergkin:BAAALgAECggJCAABLgAFFAUJGAACAM8mAA==.',
Zu='Zuggernautt:BAAALgAECgcJBwAAAA==.Zuryea:BAAALgAECgUJCgAAAA==.',
['Zü']='Zülly:BAAALgADCgcJCQAAAA==.',
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
