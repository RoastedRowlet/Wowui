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

local lookup = {'Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','DeathKnight-Blood','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','Warlock-Demonology','Druid-Feral','Mage-Frost','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow',}
local provider = {region='US',realm='Tortheldrin',name='US',type='weekly',zone=46,date='2026-05-24',data={Ac='Acquinus:BAAALgAECgEJAQAAAA==.',
Ad='Adonis:BAAALgAECgcJDAAAAA==.',
Ag='Agatha:BAAALgAECgUJCgAAAA==.',
Al='Altreyuzz:BAAALgADCgUJBQAAAA==.',
An='Anastarya:BAAALgADCgYJCgAAAA==.Anmor:BAAALgAECgQJBAABLgAFFAIJBQABAO8fAA==.Antiserum:BAAALgAECgMJAwAAAA==.',
Ap='Apocalypse:BAABLgAECn8XAAICAAkJYwayXwAxAQACAAkJYwayXwAxAQAAAA==.',
Ar='Armageddon:BAAALgAECgkJCQAAAA==.Arockoner:BAAALgADCgEJAQAAAA==.',
As='Astrozerg:BAAALgAECggJCAABLgAFFAYJHgADAKYmAA==.',
Az='Azeroth:BAAALgADCgYJBgAAAA==.Azin:BAABLgAFFH8HAAIEAAQJoxT3EwANAQAEAAQJoxT3EwANAQAAAA==.',
Ba='Baen:BAAALgAECgYJCgAAAA==.',
Be='Bearju:BAAALgAECgIJBAAAAA==.Bet:BAAALgADCgMJAwABLgAECgUJCgAFAAAAAA==.',
Br='Braxticus:BAAALgADCgYJDQAAAA==.Bruceyuu:BAAALgAECgYJDQAAAA==.',
Bu='Bubble:BAAALgAECgcJEgAAAA==.',
Ca='Cassidin:BAACLgAFFH8FAAIBAAIJ7x/XYACyAAABAAIJ7x/XYACyAAAuAAQKfxkAAgEACQmCHagvAGQCAAEACQmCHagvAGQCAAAA.Cataclysm:BAAALgAECgkJAgAAAA==.',
Ch='Chammick:BAAALgADCgIJAgAAAA==.Chooch:BAAALgAECgYJEgAAAA==.',
Ci='Cidril:BAABLgAECn8aAAIBAAgJ1BOGXQCZAQABAAgJ1BOGXQCZAQAAAA==.',
Cr='Creating:BAABLgAECn8fAAIBAAgJ1R25OABAAgABAAgJ1R25OABAAgABLgAFFAMJBQAGAJoEAA==.Creep:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Crk:BAAALgAECgQJBQABLgAFFAMJBQAGAJoEAA==.Crkgetd:BAAALgAECgEJAQABLgAFFAMJBQAGAJoEAA==.Cryptik:BAAALgADCgEJAQAAAA==.Cryptoprocta:BAAALgADCgUJCAAAAA==.',
De='Deathslip:BAAALgAECgEJAQABLgAECgUJCQAFAAAAAA==.Devilneroo:BAABLgAECn8bAAIHAAgJlRtdDwD/AQAHAAgJlRtdDwD/AQAAAA==.',
Do='Doobiesnibs:BAAALgAECgYJDAAAAA==.Doomzilla:BAAALgAECgcJBgAAAA==.Doth:BAABLgAECn8WAAIGAAYJESI2UQD+AQAGAAYJESI2UQD+AQAAAA==.Dovregubben:BAAALgAECgUJCgAAAA==.',
Dr='Drakknar:BAAALgAECgcJBwAAAA==.Drogyn:BAAALgAECgEJAgAAAA==.',
Dv='Dvlock:BAAALgAECgUJCQAAAA==.',
['Dò']='Dòóm:BAAALgAECgQJBwAAAA==.',
['Dó']='Dóóm:BAAALgADCgUJBQAAAA==.',
Ek='Ekrizdis:BAAALgADCgEJAgAAAA==.',
Em='Emryss:BAAALgAFFAEJAQAAAA==.',
Ex='Exile:BAAALgAECgUJBgAAAA==.',
Fu='Furfoxsake:BAAALgADCgIJAgAAAA==.',
Gi='Gigilong:BAACLgAFFH8GAAIIAAMJdhu7GwAXAQAIAAMJdhu7GwAXAQAuAAQKfx0AAggABwmcI5EWAM0CAAgABwmcI5EWAM0CAAAA.Gihon:BAAALgADCgkJGQAAAA==.',
Go='Gorrdain:BAAALgADCgEJAQAAAA==.Gorrgath:BAAALgAECgYJCgAAAA==.',
Gr='Grandeur:BAAALgADCgkJDwAAAA==.Greencrayon:BAAALgAECgIJAgAAAA==.Gristlezerg:BAAALgAECgIJAgABLgAFFAYJHgADAKYmAA==.',
Hi='Hippopotamus:BAAALgAECgYJDQAAAA==.',
Ho='Holyhealz:BAAALgAECgMJAwAAAA==.',
Id='Idiotdk:BAAALgAFFAIJAwABLgAFFAMJCAAJAH0XAA==.',
Il='Illyria:BAAALgADCgUJAQAAAA==.',
Ir='Ironheart:BAABLgAECn8aAAIBAAgJKxJDXACcAQABAAgJKxJDXACcAQAAAA==.',
Ja='Jackmerious:BAABLgAECn8eAAIKAAgJdBJMYgCgAQAKAAgJdBJMYgCgAQAAAA==.Jadefire:BAAALgAECgIJAQAAAA==.Jasnah:BAABLgAECn8uAAICAAkJFBVtFwAQAgACAAkJFBVtFwAQAgAAAA==.',
Je='Jefry:BAAALgADCgYJBgAAAA==.Jermomu:BAAALgAECgQJBQAAAA==.',
Ji='Jinai:BAAALgAECgYJEwABLgAECggJGwAHAJUbAA==.',
Jo='Johnnysalami:BAAALgADCgQJBAAAAA==.',
Ju='Julita:BAAALgAECgQJBQAAAA==.',
Ka='Kaggar:BAAALgAFFAEJAQAAAA==.Karadesh:BAAALgAECgcJBwAAAA==.',
Ke='Keytosuccess:BAAALgAECgUJCQAAAA==.',
Ki='Killwhat:BAACLgAFFH8QAAMKAAQJYh4hLwBsAQAKAAQJYh4hLwBsAQALAAEJCANKBAA4AAAuAAQKfzYAAgoACQlUI+0JABgDAAoACQlUI+0JABgDAAAA.',
Kl='Klint:BAABLgAFFH8FAAIGAAMJmgRJigDCAAAGAAMJmgRJigDCAAAAAA==.',
Ko='Korthyn:BAABLgAECn8eAAQMAAkJgR3JBAACAgAMAAkJgR3JBAACAgANAAQJpBK0HAD2AAAOAAEJhhOwewA4AAAAAA==.',
Ku='Kurnoth:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.',
Lo='Lothus:BAAALgADCgMJAwAAAA==.',
Ma='Magely:BAAALgADCggJCAAAAA==.',
Me='Merkules:BAAALgAECgYJDAAAAA==.',
Mo='Moxie:BAACLgAFFH8XAAIPAAYJtxU3DwDKAQAPAAYJtxU3DwDKAQAuAAQKfyUAAg8ACAk1JL8CAEkDAA8ACAk1JL8CAEkDAAAA.',
Ms='Msdranderson:BAABLgAECn8tAAIQAAcJigpmMgAdAQAQAAcJigpmMgAdAQAAAA==.',
Ne='Nero:BAAALgAECgUJCwABLgAECggJGwAHAJUbAA==.',
Ni='Nipps:BAAALgADCgQJCgAAAA==.',
On='Onatoe:BAAALgAECgMJAwAAAA==.',
Oo='Oo:BAAALgAECgUJBQAAAA==.',
Op='Op:BAAALgADCgcJAgAAAA==.',
Or='Orius:BAAALgAECgMJBAAAAA==.',
Pa='Parsimony:BAAALgADCgUJBQAAAA==.',
Pe='Pestilent:BAAALgAECgIJAgAAAA==.',
Po='Poj:BAAALgAECgMJBgAAAA==.Pojins:BAAALgAECgIJAgAAAA==.',
Pr='Pratt:BAAALgADCgcJBwAAAA==.',
Pu='Purple:BAABLgAECn8tAAIBAAkJVB2mGQCNAgABAAkJVB2mGQCNAgAAAA==.',
Ra='Raviel:BAAALgADCgQJBAAAAA==.',
Re='Regret:BAABLgAECn8XAAIRAAcJsCKjDgBMAgARAAcJsCKjDgBMAgABLgAFFAcJGwARAMsbAA==.',
Ro='Rogué:BAAALgADCgQJBAAAAA==.',
Ru='Rueal:BAAALgADCgEJAQAAAA==.Rukar:BAAALgAECgQJCgAAAA==.',
Sa='Sabra:BAAALgAECgQJBQABLgAECgUJCgAFAAAAAA==.Saia:BAAALgAECgUJEAAAAA==.Samanosuke:BAAALgAECgEJAQAAAA==.',
Se='Seleren:BAAALgADCgEJAQAAAA==.Serapphina:BAAALgAECgIJAgAAAA==.',
Si='Silverfangz:BAAALgADCgEJAQAAAA==.',
Sn='Snipedbaby:BAAALgAECgMJAgAAAA==.',
Su='Superfist:BAACLgAFFH8XAAMSAAYJPBxtCwBEAQASAAUJDxxtCwBEAQATAAEJ7RDCPABNAAAuAAQKfyYAAxIACAnIIkMGABwDABIACAnIIkMGABwDABMABwmUHlsRAGMCAAAA.',
['Så']='Såbra:BAAALgADCgEJAQAAAA==.',
Ta='Tavitusk:BAAALgAECgQJBgAAAA==.Tayonhands:BAAALgAECgYJCwABLgAECgkJLgACABQVAA==.',
Te='Tehgimp:BAABLgAECn8vAAIUAAkJsAx/DQClAQAUAAkJsAx/DQClAQAAAA==.',
Ti='Tinder:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgMJAwAAAA==.',
Tr='Trakanon:BAABLgAECn8uAAQMAAgJchxYBQDtAQAMAAgJchxYBQDtAQAOAAUJQhNMPAD9AAANAAYJEgrQHAD1AAAAAA==.Treezus:BAAALgAECgEJAQAAAA==.Trouthunter:BAAALgAECggJDwAAAA==.',
Ts='Tsuyoikuma:BAAALgADCgkJGQAAAA==.',
Ug='Ugornargol:BAAALgADCgEJAQABLgAECgcJBwAFAAAAAA==.',
Uu='Uu:BAABLgAECn8ZAAIRAAkJYhwzDABvAgARAAkJYhwzDABvAgAAAA==.',
Uw='Uwu:BAAALgADCgcJDgAAAA==.',
Va='Valicore:BAABLgAECn8aAAIVAAgJNxOYQgDqAQAVAAgJNxOYQgDqAQAAAA==.Vansftw:BAAALgAECggJDwAAAA==.Varithak:BAAALgADCgYJBgAAAA==.',
Ve='Vent:BAAALgAECgIJAgAAAA==.Vestrevus:BAAALgAECgUJEQAAAA==.',
Vg='Vginny:BAAALgADCgUJBQAAAA==.',
Vi='Violetta:BAAALgAECgYJEwABLgADCgYJCgAFAAAAAA==.',
Vo='Vonix:BAAALgADCgMJAwAAAA==.Vorcthal:BAABLgAECn8fAAMPAAkJOhtTCADMAgAPAAkJOhtTCADMAgAWAAgJGg1EKgBZAQAAAA==.Voren:BAAALgADCgQJBAAAAA==.Vorenormu:BAABLgAECn8dAAQOAAgJixNyJQCUAQAOAAgJ3BJyJQCUAQANAAMJVgOnPgB1AAAMAAIJ4hCSNABwAAABLgAECgkJHwAPADobAA==.',
Vy='Vyre:BAAALgADCgYJCgABLgAECggJHgAKAHQSAA==.',
Wa='Waste:BAAALgAECgIJAgAAAA==.',
Wi='Wingzero:BAAALgAECgIJAgAAAA==.',
Xe='Xero:BAAALgADCgUJBQAAAA==.',
Xo='Xoloteku:BAAALgADCgIJAgAAAA==.',
Xx='Xxz:BAAALgAECgcJBgAAAA==.',
Ya='Yaoi:BAAALgADCgUJBQABLgADCgYJCgAFAAAAAA==.',
Za='Zaelor:BAAALgAECgcJBgABLgAECgkJGgAVADcTAA==.Zandros:BAAALgAECgcJBwAAAA==.',
Ze='Zen:BAAALgADCgQJBAABLgAECgcJBwAFAAAAAA==.Zergdh:BAAALgADCgcJBwABLgAFFAYJHgADAKYmAA==.Zergkin:BAAALgAECggJCAABLgAFFAYJHgADAKYmAA==.',
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
