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

local lookup = {'Paladin-Retribution','Shaman-Enhancement','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DemonHunter-Devourer','Hunter-BeastMastery','Paladin-Holy','Warrior-Arms','Paladin-Protection','Priest-Holy','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','DeathKnight-Frost','DeathKnight-Blood','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DeathKnight-Unholy','Druid-Balance','DemonHunter-Vengeance','Druid-Feral','Warlock-Demonology','Warlock-Destruction','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Evoker-Devastation','Mage-Frost','Mage-Fire','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','Priest-Discipline','Monk-Windwalker',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-10-27',data={Ab='Aberaht:BAABNQAECn8yAAIBAAoKGyIKEgDoAgABAAoKGyIKEgDoAgAAAA==.Abercrombie:BAAANQAECgEIAQAAAA==.Absolution:BAABNQAECn8WAAICAAgKUQm+IQBCAQACAAgKUQm+IQBCAQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEwAAAA==.',
Ad='Adenwey:BAABNQAECn8UAAIDAAoK3Rd2CADJAgADAAoK3Rd2CADJAgABNQAECgoKOwAEAJ4iAA==.Adewey:BAAANQAECgUIDQAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgoKOwAEAJ4iAA==.Aerynsun:BAAANQABCggIDgABNQAECggIKAAFALQWAA==.',
Ai='Airreona:BAAANQAECgIIBQAAAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgUIDQAGAAAAAA==.Akre:BAAANQAECgEIAQABNQAECggIHgAHAMwNAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Alarmclock:BAAANQABCgcIDAABNQAECggIKAAFALQWAA==.Aleannia:BAAANQAECgIIBAAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8iAAIBAAoKARhhdgBAAgABAAoKARhhdgBAAgAAAA==.Algodón:BAAANQADCgEIAgABNQAFFAMIBQAIAKodAA==.Alibrexia:BAABNQAECn8aAAIFAAcK1QdeFgA1AQAFAAcK1QdeFgA1AQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQAECgcIDgAAAA==.',
An='Anarcy:BAAANQAECgIIAwAAAA==.Anastaysha:BAAANQAECgEIAgABNQAECgYIDAAGAAAAAA==.Anathema:BAAANQAECgIIAgAAAA==.Ankan:BAABNQAECn8gAAIJAAoKkxwhLgCuAgAJAAoKkxwhLgCuAgABNQAECgoKOwAEAJ4iAA==.',
Ap='Ape:BAAANQAECgQIBAAAAA==.',
Ar='Arcticplague:BAAANQAECgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Arduka:BAAANQAECgEIAQAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAECggIJQAKAIUcAA==.',
At='Athenä:BAACNQAFFH8ZAAILAAYKiRokAgAyAQALAAYKiRokAgAyAQA1AAQKfywAAgsACgr9HoELAOECAAsACgr9HoELAOECAAAA.Atsuma:BAAANQAECgEIAQAAAA==.Atthel:BAAANQAECgYIDQAAAA==.Attunement:BAAANQAECgQIBQABNQAECggIEwAGAAAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgcICwAGAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECggIGgAMAI4ZAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAAANQAECgYIEAAAAA==.',
Ba='Baconmecrazy:BAAANQADCgMIAwAAAA==.Baela:BAAANQAECgMIBAABNQAFFAcIHAANAPcdAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQAECgYICgAAAA==.Battleshaman:BAAANQAECgEIAQAAAA==.',
Be='Benjinana:BAABNQAECn8UAAIMAAUK2xP+fgDcAAAMAAUK2xP+fgDcAAAAAA==.',
Bi='Bittybombom:BAAANQAECgMIBAAAAA==.Bixibonxle:BAAANQAECgEIAQAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAABNQAECn8bAAIOAAcKlRoEBwA0AgAOAAcKlRoEBwA0AgAAAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Bohde:BAAANQAFFAEIAQAAAA==.Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIBAAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAAANQAECgQICwABNQAFFAYIDwAPAFIVAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.Burninate:BAAANQABCggIEQABNQAECggIKAAFALQWAA==.',
By='Byorn:BAABNQAECn8YAAMQAAkKcBPTOgAvAQARAAcKew4wZgBaAQAQAAcKgBPTOgAvAQABNQAFFAQICgAIAPwSAA==.',
Ca='Cairdamane:BAABNQAECn8pAAMSAAoK3g7zcgDIAQASAAoK3g7zcgDIAQANAAMKPAamtQBQAAAAAA==.Calidrina:BAABNQAECn8wAAIHAAoK2xFzEADhAQAHAAoK2xFzEADhAQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAAANQAECgcIEgAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAABNQAECn8UAAMTAAkKFBxKMgAVAgATAAcKdBtKMgAVAgAUAAUKnBgCOwB4AQABNQAECggIJQAKAIUcAA==.',
Ch='Charayi:BAAANQADCggICAABNQAECgYIDAAGAAAAAA==.Chardaney:BAAANQAECgYIDAAAAA==.Cheery:BAAANQABCgcIFQABNQAECggIKAAFALQWAA==.Chickennuggi:BAABNQAECn8UAAIVAAcKwyCDCQA0AgAVAAcKwyCDCQA0AgABNQAECgkJJQARAIgjAA==.',
Ci='Cii:BAABNQAECn8sAAMLAAkKtRMgFwBJAQALAAcKwxUgFwBJAQABAAIKXgfESwEvAAAAAA==.Ciine:BAAANQADCgYICAABNQAECgkJLAALALUTAA==.Ciruzita:BAAANQAECgEIBAAAAA==.',
Cl='Clampz:BAEANQAECgUICAABNQAFFAYIEwAUAGAeAA==.',
Co='Colabrn:BAAANQADCggIFAAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAABNQAECn8iAAIHAAgKYg0nIAAoAQAHAAgKYg0nIAAoAQAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECn9FAAIBAAoKdSDdGQBdAwABAAoKdSDdGQBdAwAAAA==.Corlock:BAAANQABCgUIBQAAAA==.Corrupt:BAAANQAECgEIBAAAAA==.Covidgirl:BAAANQAECgEIAQAAAA==.',
Cr='Crassberry:BAACNQAFFH8LAAIWAAYKIRYCDABNAQAWAAYKIRYCDABNAQA1AAQKfyMAAhYACgqOJEkkALACABYACgqOJEkkALACAAAA.Creepindeath:BAAANQAECgEIAwAAAA==.',
Cu='Cucaracha:BAAANQAECgYIDQAAAA==.',
Cy='Cyndal:BAAANQAECgEIBAABNQAECgcICwAGAAAAAA==.Cyndle:BAAANQAECgEIAQABNQAECgcICwAGAAAAAA==.Cyntu:BAAANQAECgEIAgABNQAECgcICwAGAAAAAA==.',
Da='Dankbuds:BAAANQAECggIDwAAAA==.Dankothy:BAAANQAECgMICAABNQAECggIDwAGAAAAAA==.Dankreaper:BAAANQAECgEIAQABNQAECggIDwAGAAAAAA==.Dantes:BAAANQAECgEJAwAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAAANQAECggIEwABNQAECgoKRQABAHUgAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgQIDgAAAA==.',
De='Deadbolt:BAAANQAECgYICgAAAA==.Deathforever:BAAANQAECgYICwAAAA==.Deathskys:BAAANQAECgEIAQAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECn8sAAMDAAoKOh5/BQAeAwADAAoKOh5/BQAeAwAXAAUKMBCxRACxAAAAAA==.Demon:BAABNQAECn9DAAMEAAoKlCD7CADEAgAEAAoKlCD7CADEAgAYAAMK0RoFFQCVAAABNQAFFAcIHwAUAIMTAA==.Demoniec:BAAANQAECgIIAwAAAA==.Demowneege:BAAANQADCggICAABNQAFFAYIFwAFABEfAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECn8jAAIPAAoKGBq7fACFAgAPAAoKGBq7fACFAgAAAA==.Disowneege:BAAANQAECgYIDQABNQAFFAYIFwAFABEfAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Draculla:BAAANQAECgEIAQAAAA==.Dragnas:BAABNQAECn83AAQCAAoK3w9fDADRAQACAAoK3w9fDADRAQANAAQKuxJrvADyAAASAAEKHg5NLgE6AAAAAA==.Dragonisa:BAAANQAECgMIBAAAAA==.Draiocht:BAAANQADCgQIBwABNQAECggIGgAMAI4ZAA==.Drakass:BAAANQAECgEIAQAAAA==.Dramakiller:BAAANQAECgUIDAAAAA==.Drcornbread:BAABNQAECn8UAAMZAAUK8w6pGAC+AAAZAAUKhQ6pGAC+AAAVAAQKCAy5QwCmAAAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIFAAZAPMOAA==.Drdreggs:BAABNQAECn8gAAMaAAoK2hEzhADbAQAaAAkKixEzhADbAQAbAAEKBhTVcQA9AAAAAA==.Drop:BAAANQADCgQIBAABNQAECgoKNgABALIeAA==.Druduwolf:BAAANQAECgcIEwAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgUIDAAGAAAAAA==.Dustyhunter:BAAANQAECgEIAQAAAA==.Duthalemar:BAAANQADCgIIAgABNQAECgoKOwAEAJ4iAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAECggIJQAKAIUcAA==.',
El='Elastar:BAABNQAECn8yAAIcAAoKihWHBwDsAQAcAAoKihWHBwDsAQAAAA==.Ellimist:BAEANQAECgcIDgAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAABNQAECn8iAAMIAAoKQiOLBgApAwAIAAoKQiOLBgApAwAdAAoK9RBlDwDTAQAAAA==.',
Em='Emura:BAAANQAECgEIAQAAAA==.',
En='Enveliria:BAAANQAECgUIEQABNQAECgoKOwAEAJ4iAA==.',
Er='Eraser:BAABNQAECn86AAMMAAoKeRM/ZADzAQAMAAoKeRM/ZADzAQAeAAgK4g2cGABPAQAAAA==.Erazar:BAABNQAECn8WAAIfAAcKGwhqEQC7AAAfAAcKGwhqEQC7AAAAAA==.Erickk:BAABNQAECn81AAIPAAoK8hmgTgDkAgAPAAoK8hmgTgDkAgAAAA==.Eristela:BAAANQAECgEIAgAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn8yAAIMAAoKRSXEAQD6AwAMAAoKRSXEAQD6AwAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDwAAAA==.',
Ex='Exodari:BAABNQAECn83AAICAAoKoA+FCwDnAQACAAoKoA+FCwDnAQAAAA==.Extro:BAAANQAECgQIBAAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgIIAgABNQAECggIJQAKAIUcAA==.Faeliendra:BAAANQADCggICAAAAA==.Fangloria:BAAANQABCggIEwABNQAECggIKAAFALQWAA==.Fatalgrip:BAAANQADCgUIBgAAAA==.',
Fe='Fel:BAABNQAECn9KAAMEAAoKxyPeBAATAwAEAAoKrCPeBAATAwAHAAgKcxwDGACdAgAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUICAABNQAECgkJJQARAIgjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcICwABNQAECgoKIgAIADIgAA==.Fiddich:BAAANQAECgQIBAAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIFgAGAAAAAA==.Fiofio:BAABNQAECn8wAAIPAAoKSRybLwAzAgAPAAoKSRybLwAzAgAAAA==.Fizban:BAABNQAECn8WAAMgAAgKtQzxDwCoAQAgAAgKtQzxDwCoAQAPAAQK+AEimwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICQABNQAECgoKSgAMAGUdAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Fragglelock:BAAANQABCggIFQABNQAECggIKAAFALQWAA==.Frigidheart:BAAANQAECgUIDQABNQAECgcIEAAGAAAAAA==.Frostetute:BAABNQAECn8WAAIPAAgKugzlbgBpAQAPAAgKugzlbgBpAQAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAABNQAECgQIBAAGAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAQICgAIAPwSAA==.',
Ga='Gadogear:BAABNQAECn8aAAIgAAcK5hYBFABqAQAgAAcK5hYBFABqAQAAAA==.Galabren:BAAANQAECgYJDgAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Ge='Gertra:BAAANQAECgYIBwAAAA==.',
Gf='Gfr:BAABNQAECn8ZAAMbAAcKQhs0BABnAQAbAAcKQhs0BABnAQAaAAEKAABdAAEAAAAAAA==.',
Gi='Giddoo:BAAANQAECgQICQAAAA==.Gilnean:BAAANQABCgMIBAAAAA==.',
Gn='Gnomeanator:BAAANQAECgEIAwAAAA==.Gnowanceyi:BAAANQAECgIIAwABNQAECgoKNQAPAPIZAA==.',
Go='Goatcheeze:BAAANQAECgcIEAAAAA==.Gohlemsaurus:BAAANQADCggIJAAAAA==.',
Gu='Gulen:BAAANQADCggIGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
Gw='Gwennevier:BAAANQAECgEIAgAAAA==.',
['Gí']='Gíga:BAAANQAECgMIBAAAAA==.',
Ha='Halsten:BAABNQAECn8UAAQgAAcKKAJeNQBmAAAPAAUKswFwmgGRAAAgAAQK1wJeNQBmAAAhAAEKAACYDwAhAAAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAYIEwAUAGAeAA==.Heloisa:BAAANQADCgYIBgAAAA==.Helrazor:BAAANQADCgUIBQABNQAECgoKHwAZAAwWAA==.',
Hi='Hila:BAAANQAECgEIAQAAAA==.Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Hoofingit:BAAANQAECgEIAgAAAA==.',
Hr='Hroc:BAABNQAECn8VAAITAAkKHAkZRQCyAQATAAkKHAkZRQCyAQAAAA==.',
Hu='Hunterboi:BAAANQAECgEIAQAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDQAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgUICwAAAA==.',
Il='Illune:BAABNQAECn8nAAIPAAoKwRJZQQDxAQAPAAoKwRJZQQDxAQAAAA==.',
Im='Imleapingit:BAABNQAECn8cAAIKAAcK/hhvTwCWAQAKAAcK/hhvTwCWAQAAAA==.Imrelentless:BAAANQABCgYICwAAAA==.',
In='Inaurian:BAAANQAECgEIAQAAAA==.Intoodeep:BAABNQAECn88AAITAAoKhxlrBQBlAgATAAoKhxlrBQBlAgAAAA==.',
Ir='Ir:BAABNQAECn9MAAIPAAoKgRweJwBZAgAPAAoKgRweJwBZAgAAAA==.Ironfoot:BAAANQAECgQIBAAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMKAAkKshkqXgByAgAKAAkKmRcqXgByAgAcAAIK0Rv1NACOAAAAAA==.Ishdo:BAABNQAECn8aAAIRAAgKPAwwYQBtAQARAAgKPAwwYQBtAQAAAA==.Ishdu:BAAANQADCgYIBgABNQAECggIGgARADwMAA==.Ishlok:BAAANQADCgUIBQABNQAECggIGgARADwMAA==.Ishmael:BAAANQAECgQIBQABNQAFFAQICgAIAPwSAA==.Ishwar:BAAANQADCggIGAABNQAECggIGgARADwMAA==.',
Iv='Ivanhöe:BAAANQAECgEIAQAAAA==.',
Ja='Jakytreehorn:BAABNQAECn8UAAISAAgKZBDVZwDpAQASAAgKZBDVZwDpAQAAAA==.Jaydm:BAAANQAECgYICgABNQAFFAYIDwAPAFIVAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQAECgEIAgAAAA==.Jessiel:BAAANQAECgUIBgAAAA==.Jet:BAABNQAECn82AAIBAAoKsh52GgCuAgABAAoKsh52GgCuAgAAAA==.',
Ju='Julthaenia:BAABNQAECn8pAAIOAAgKMhrVAwCwAgAOAAgKMhrVAwCwAgABNQAECgoKOwAEAJ4iAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQAECgEIAQAAAA==.Kagome:BAAANQADCggIDQABNQAECgYIDAAGAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQAECgEIAgABNQAECgoKOwAEAJ4iAA==.Karash:BAAANQAECgUIDAAAAA==.Kargush:BAAANQADCgQIBAABNQADCggIFgAGAAAAAA==.Karmaisab:BAAANQAECggIAgAAAA==.Karnrae:BAABNQAECn8eAAIBAAkKWBPmaQCCAQABAAkKWBPmaQCCAQAAAA==.Karynos:BAABNQAECn8uAAIaAAoKVRCHgADlAQAaAAoKVRCHgADlAQAAAA==.Katwolf:BAABNQAECn8WAAIIAAYKSg7fvgCFAQAIAAYKSg7fvgCFAQAAAA==.Katyah:BAABNQAECn8XAAINAAgKCAfIlgBOAQANAAgKCAfIlgBOAQAAAA==.Kavourkaa:BAAANQABCggIHQAAAA==.',
Ke='Keynivas:BAAANQAECgIJAwAAAA==.',
Ki='Killiua:BAAANQAECgcIDAAAAA==.',
Ko='Kobayashi:BAAANQABCggIFgABNQAECggIKAAFALQWAA==.Konspiracy:BAABNQAECn8WAAMbAAgK4xBADwAHAgAbAAgK4xBADwAHAgAaAAEKAAAfTAErAAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBgAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDwAGAAAAAA==.Kroot:BAABNQAECn8iAAIIAAoKMiDYDQDgAgAIAAoKMiDYDQDgAgAAAA==.Krous:BAACNQAFFH8TAAIKAAYKSSDmCgACAgAKAAYKSSDmCgACAgA1AAQKfygAAgoACgrEHxBPAJwCAAoACgrEHxBPAJwCAAAA.Kryph:BAAANQAECgUIEAAAAA==.',
['Kä']='Kämpfer:BAAANQAECgcIDAABNQAECgoKLQAiAMwTAA==.',
La='Lafiel:BAABNQAECn8rAAIMAAoKohGFLQANAgAMAAoKohGFLQANAgAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Latrank:BAAANQAECgYIBwAAAA==.Laurandre:BAABNQAECn8lAAMDAAkKDgdvJQAyAQADAAkKDgdvJQAyAQAXAAEKAABHyQAZAAAAAA==.Lazeras:BAAANQAECgQICQABNQAECgoKHwAZAAwWAA==.',
Le='Letsgetwet:BAAANQAECgMIAwAAAA==.',
Li='Liefic:BAABNQAECn8oAAIIAAoKJxv1GwB/AgAIAAoKJxv1GwB/AgAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQAECgEIAQAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIFgAGAAAAAA==.Limon:BAAANQAECgcIBwAAAA==.',
Ll='Llylith:BAAANQAECgEIAwAAAA==.',
Lo='Locke:BAAANQAECgUICgABNQAECgoKNgABALIeAA==.',
Lu='Luckykilla:BAABNQAECn8tAAITAAkKkhfVKQBFAgATAAkKkhfVKQBFAgAAAA==.Lucÿ:BAACNQAFFH8GAAINAAMKKRofEQDMAAANAAMKKRofEQDMAAA1AAQKfy0AAw0ACgqzHuQjANcCAA0ACgqzHuQjANcCABIABgp7EmyYAGgBAAAA.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECn87AAMWAAkKdhRVMQABAQAWAAcKBBZVMQABAQARAAcKLQ0cSwC4AAAAAA==.Luxtyrannica:BAAANQAECgcIDQAAAA==.',
Ly='Lydrain:BAAANQAECgQIBQAAAA==.Lylia:BAAANQADCggIGAAAAA==.',
Ma='Malcolm:BAAANQABCgYICwABNQAECggIKAAFALQWAA==.Marahh:BAAANQABCgIIAgAAAA==.Matt:BAAANQAECgQIBQABNQAFFAcIHwAUAIMTAA==.Mattbolt:BAABNQAECn8YAAICAAkK5CADDwB6AgACAAkK5CADDwB6AgAAAA==.Maximoose:BAACNQAFFH8KAAIIAAQK/BKDEQBIAQAIAAQK/BKDEQBIAQA1AAQKfx0AAggACgo/GXhHAJYCAAgACgo/GXhHAJYCAAAA.Mayu:BAAANQAECgEIBwAAAA==.Mayumey:BAAANQADCgUIBQAAAA==.Mazigos:BAAANQAECgYIBwAAAA==.',
Me='Medjrab:BAABNQAECn8/AAIWAAoKCCJ8CQByAwAWAAoKCCJ8CQByAwAAAA==.Mefi:BAAANQADCgcIFgAAAA==.Melyria:BAABNQAECn8eAAIHAAgKzA1EMwCoAQAHAAgKzA1EMwCoAQAAAA==.Meristem:BAABNQAECn8eAAIXAAcKCg2jNQD2AAAXAAcKCg2jNQD2AAAAAA==.Merko:BAAANQADCggICQABNQAECgoKIgAIADIgAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Misafarm:BAAANQADCgIIAgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECggIEQAAAA==.Mogma:BAAANQAECgUICgAAAA==.Mogsarren:BAAANQAECgEIAQABNQAECgoKRwARAL8lAA==.Momentomori:BAAANQADCgUICwAAAA==.Mondgrille:BAAANQAECgQIBAAAAA==.Monora:BAAANQADCggICQAAAA==.Moonbounds:BAACNQAFFH8TAAINAAcKSxoGBgAIAgANAAcKSxoGBgAIAgA1AAQKf0gAAg0ACgrSI5kFAJoDAA0ACgrSI5kFAJoDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Moonshift:BAAANQAECgEIAQAAAA==.Morgana:BAAANQADCgYICAAAAA==.Mousechief:BAABNQAECn8ZAAISAAcK4AK8fQCjAAASAAcK4AK8fQCjAAAAAA==.Moxxzi:BAABNQAECn8pAAIWAAcK9hGJIABwAQAWAAcK9hGJIABwAQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8hAAQSAAoKFSARIgABAwASAAoKFSARIgABAwACAAEKixNKKABBAAANAAEKUxD2FwE7AAAAAA==.Muvahmedicin:BAAANQADCggIDwAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgkJJwAMAB4eAA==.Naksù:BAAANQADCgUIBQABNQAECgkJJwAMAB4eAA==.Naksû:BAAANQAECgIIAwABNQAECgkJJwAMAB4eAA==.Naksü:BAABNQAECn8nAAIMAAkKHh43GQCXAgAMAAkKHh43GQCXAgAAAA==.',
Ne='Neifeb:BAABNQAECn8jAAIIAAgKLxLxggAGAgAIAAgKLxLxggAGAgAAAA==.Nerfherder:BAAANQABCgcIDwABNQAECggIKAAFALQWAA==.',
Ni='Niallivdam:BAAANQAECgUICgAAAA==.Nights:BAAANQAECgIIAwABNQAFFAcIHwAUAIMTAA==.Ninh:BAABNQAECn9MAAIjAAoKYg3iDQCpAQAjAAoKYg3iDQCpAQAAAA==.Nintendopsp:BAAANQAECgIIAgAAAA==.Ninthgate:BAABNQAECn8aAAIaAAYKcAWZ4QAGAQAaAAYKcAWZ4QAGAQAAAA==.',
No='Noble:BAABNQAECn8lAAMHAAoKuxBNFwCBAQAHAAoKuxBNFwCBAQAEAAEKuQY0agAzAAAAAA==.Nogood:BAABNQAECn8ZAAIKAAoKRRYzaQBVAgAKAAoKRRYzaQBVAgAAAA==.Northwest:BAAANQAECgEIAgAAAA==.Notsodemon:BAAANQAECgQICQABNQAECgcIFQAPAJsLAA==.Notsomage:BAABNQAECn8VAAIPAAcKmwsDAwGJAQAPAAcKmwsDAwGJAQAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgYICwAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECn8sAAMDAAgKwB3fCgCNAgADAAgKwB3fCgCNAgAXAAEKAAC3xwAaAAAAAA==.',
Od='Oddone:BAAANQAECgEIAgAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odelina:BAAANQADCgUIBAAAAA==.Odinheâthen:BAAANQAECgEIAgAAAA==.',
Ok='Okrawindfury:BAAANQABCggIFgABNQAECggIKAAFALQWAA==.',
Ol='Olydwarf:BAAANQAECgEIAgAAAA==.',
On='Onebadmutha:BAAANQAECgcIEwAAAA==.Ontop:BAABNQAECn9MAAIIAAoK6x4JFwCcAgAIAAoK6x4JFwCcAgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8nAAMgAAcKtBcuDQDgAQAgAAcKtBcuDQDgAQAPAAMK1wV1swFaAAAAAA==.',
Ow='Owneege:BAACNQAFFH8XAAMFAAYKER8yAAB3AQAKAAUKYRo7EgCeAQAFAAYKoRoyAAB3AQA1AAQKfy8AAwUACgriI+MFAOsBAAoACQpDIgtGALgCAAUACQq0IuMFAOsBAAAA.',
Pa='Paapaa:BAAANQAECggICwAAAA==.Pallideaus:BAABNQAECn8ZAAIJAAcKayGTLwCoAgAJAAcKayGTLwCoAgAAAA==.Pallinar:BAAANQAECgcIDQAAAA==.Pandamak:BAAANQADCggICAAAAA==.Paradoxx:BAAANQADCgIIBAAAAA==.Pasquale:BAAANQAECgUICgAAAA==.Pauzhaan:BAAANQAECgUICQABNQAECggIKAAFALQWAA==.',
Pe='Pebbles:BAABNQAECn89AAIBAAoKJhYfOgARAgABAAoKJhYfOgARAgAAAA==.Pedorus:BAAANQABCgYIBwABNQAFFAMIBgANACkaAA==.Penjerman:BAAANQAECggICgABNQAECggIJQAKAIUcAA==.',
Pi='Picklericky:BAAANQADCggIEQAAAA==.Pilgrimm:BAECNQAFFH8TAAIUAAYKYB7uAQA4AgAUAAYKYB7uAQA4AgA1AAQKfygABBQACgoTJZ4DAGUDABQACgoTJZ4DAGUDACQAAQq5G4YZAEwAABMAAQpBC42gADoAAAAA.Pinxyl:BAAANQAECgEIAQAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pix:BAAANQABCgQIBwAAAA==.Pixyl:BAAANQAECgEIBQAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAIQAAcKsgVSYgAbAQAQAAcKsgVSYgAbAQAAAA==.Plaguewind:BAAANQAECgEIAgAAAA==.',
Po='Polydh:BAABNQAECn8yAAIYAAoKYSS4AAA9AwAYAAoKYSS4AAA9AwAAAA==.Poobah:BAABNQAECn8hAAMSAAcKLwbrwgAMAQASAAYKwQbrwgAMAQANAAIKrgKUuQBJAAAAAA==.Popsicles:BAABNQAECn8lAAMlAAkKixYqBgAyAgAlAAkKixYqBgAyAgAeAAEKAADjigAfAAAAAA==.Potrat:BAAANQAECgMJBAAAAA==.Pouffant:BAAANQAECgUIDQAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Pronoz:BAAANQAECggIEAAAAA==.',
Pu='Purpyl:BAAANQAECgUIDQAAAA==.',
Pw='Pwnageddon:BAAANQADCgcIHAAAAA==.Pwnjitsu:BAABNQAECn8xAAImAAoKARwSCQB6AgAmAAoKARwSCQB6AgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8PAAIPAAYKUhWIDgADAgAPAAYKUhWIDgADAgA1AAQKfy4AAw8ACgopIGoRANACAA8ACgopIGoRANACACAAAwr+BIsyAHEAAAAA.',
Qt='Qtkillz:BAAANQAECgEIAQAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECn9MAAIKAAoKiyKIEQDZAgAKAAoKiyKIEQDZAgAAAA==.Razak:BAABNQAECn87AAICAAoK7B0UBgAlAwACAAoK7B0UBgAlAwAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8fAAIbAAcKegc3DQC1AAAbAAcKegc3DQC1AAAAAA==.Redrum:BAABNQAECn8lAAIRAAkKiCMZCwBbAwARAAkKiCMZCwBbAwAAAA==.Reineken:BAAANQADCgMIAwAAAA==.Renarin:BAABNQAECn9KAAIMAAoKZR19IADtAgAMAAoKZR19IADtAgAAAA==.Renisa:BAABNQAECn8dAAMHAAgKvxX6JgANAgAHAAgKvxX6JgANAgAEAAEKMwb6nAAlAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQAECgcIDAAAAA==.Revlyk:BAABNQAECn8lAAICAAoKKhdBDwB1AgACAAoKKhdBDwB1AgABNQAECgoKOwAEAJ4iAA==.',
Rh='Rhoanna:BAAANQAECgQIBAAAAA==.Rhoupert:BAABNQAECn8UAAIBAAcKXBZhmQDwAQABAAcKXBZhmQDwAQAAAA==.',
Ri='Rimastus:BAAANQAECgEIAQAAAA==.',
Ro='Roccot:BAABNQAECn81AAIRAAoKoSC0BwDYAgARAAoKoSC0BwDYAgAAAA==.Rotfather:BAAANQADCgcICAAAAA==.Rotjaw:BAAANQAECgEIAgAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgUICwAAAA==.',
Ry='Ryppyr:BAAANQADCggICAAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.Sauron:BAAANQAECgUICQAAAA==.',
Sc='Scalycat:BAAANQAECgcIEgAAAA==.Schuey:BAAANQAECgEIAQAAAA==.Scum:BAAANQADCgcIDQABNQAECgQIBAAGAAAAAA==.',
Se='Senaeda:BAAANQAECgEIBAAAAA==.Senate:BAABNQAECn81AAMSAAoKqxErKQC/AQASAAoKqxErKQC/AQANAAEKqgFVMQEfAAAAAA==.Servenslay:BAAANQADCggIDgAAAA==.',
Sh='Shaamazing:BAAANQAECgEIAQAAAA==.Shablaam:BAAANQAECgIIAgAAAA==.Shadowbear:BAABNQAECn8dAAIeAAgK+xRJFACHAQAeAAgK+xRJFACHAQAAAA==.Sherrilyn:BAAANQAECgEIAQAAAA==.Shifdiah:BAAANQAECgUIDAAAAA==.Shocktherapi:BAAANQAECgcIDAAAAA==.Shrimpback:BAAANQAECgIIAgAAAA==.',
Si='Silentwoman:BAAANQAECgEIAQAAAA==.Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8aAAIMAAYKehSXCgDfAQAMAAYKehSXCgDfAQA1AAQKfyAAAgwACgowHI47AHsCAAwACgowHI47AHsCAAE1AAQKBwgOAAYAAAAA.Skittlesdan:BAABNQAECn8mAAQaAAoKYhJXVwBdAQAaAAoKYhJXVwBdAQAOAAEKAAB/MgAvAAAbAAEKxQQWgwAoAAAAAA==.',
Sl='Slaykween:BAABNQAECn8XAAILAAYK0gTKSADKAAALAAYK0gTKSADKAAAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECggIFgAgALUMAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8oAAQFAAgKtBYRDwC8AQAFAAYK6xgRDwC8AQAKAAcK1w6+ugCKAQAcAAIKMhpPOQBmAAAAAA==.',
So='Something:BAAANQABCggIEwABNQAECggIKAAFALQWAA==.Soryu:BAAANQAECgIIAgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAwAAAA==.Stonedragon:BAECNQAFFH8OAAIIAAQKMxdBCgAAAQAIAAQKMxdBCgAAAQA1AAQKf1EAAggACgqAJaoFALQDAAgACgqAJaoFALQDAAAA.Stormfang:BAAANQADCgcIFAABNQAECgYIEAAGAAAAAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgYIEAAGAAAAAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn8sAAISAAkKYg0SQQBQAQASAAkKYg0SQQBQAQAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Streea:BAAANQAECgEIAQABNQAECgcICwAGAAAAAA==.Stubz:BAAANQABCgYICAAAAA==.',
Su='Sugi:BAAANQAECgMICAABNQAFFAQIBwAHALkQAA==.Sukonamí:BAABNQAECn8iAAIKAAoKFBQdMAAYAgAKAAoKFBQdMAAYAgAAAA==.Suzhou:BAABNQAECn8ZAAIbAAcKmQZUDAC9AAAbAAcKmQZUDAC9AAAAAA==.Suzoomies:BAAANQAECgEIAQAAAA==.',
Sw='Swisscheese:BAABNQAECn8eAAMaAAkKqBomXABDAgAaAAkKqBomXABDAgAbAAEKLwpLewAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECggIDwAAAA==.Sycò:BAABNQAECn8sAAMIAAkKGyOaEgBVAwAIAAkKGyOaEgBVAwAdAAEKkQF3ngAgAAAAAA==.Syraxa:BAAANQAECgMIBgABNQAECgQIBwAGAAAAAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAgABNQAFFAQICwAIAJcTAA==.',
Ta='Taedish:BAAANQAECgEIAQAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Talorien:BAAANQAECgEIAQABNQAECgoKJwAPAMESAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQAECgEIAQAAAA==.Terragosa:BAABNQAECn8cAAMPAAcKYBYLhQA4AQAPAAcKMRQLhQA4AQAgAAIKFwwBNwBgAAAAAA==.Tetchybono:BAAANQAECgcIDwAAAA==.Tettra:BAAANQADCggICgABNQAECgcICwAGAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAQICgAIAPwSAA==.Thahawtz:BAAANQADCgYJDAAAAA==.Thirinis:BAABNQAECn8UAAIJAAYKVgnTuAALAQAJAAYKVgnTuAALAQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thundergirl:BAAANQAECgQIEAAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIBwAAAA==.',
Tl='Tlàchtga:BAAANQAECgIIAwAAAA==.',
To='Toughasnails:BAAANQAECgIIAwAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgoKHwAZAAwWAA==.Trainar:BAAANQAECgUIEwABNQAECgcIGgAEADEaAA==.Triggs:BAAANQAECggIBwAAAA==.Trinnitty:BAAANQAECgEIAgAAAA==.Troggdor:BAAANQABCggIDgABNQAECggIKAAFALQWAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAAANQAECgYIDgAAAA==.Truckz:BAABNQAECn8WAAISAAoKHBIsIgDtAQASAAoKHBIsIgDtAQAAAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAgAAAA==.',
Ty='Tyrawick:BAAANQAECgYIBgAAAA==.Tyrlidd:BAABNQAECn8fAAIIAAcKJgeMvwCEAQAIAAcKJgeMvwCEAQAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8yAAMNAAoKcxzFKQC8AgANAAoKcxzFKQC8AgASAAEKRxbRJgFEAAAAAA==.',
Ur='Urbanmeyer:BAAANQAECgIIAgAAAA==.Uricash:BAABNQAECn9AAAIPAAoK8h0CHACPAgAPAAoK8h0CHACPAgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.Urzual:BAABNQAECn8oAAMCAAgKsR2BDACoAgACAAgKsR2BDACoAgANAAYKbhSCigBvAQAAAA==.',
Ut='Utiniócast:BAAANQAECgEIAQAAAA==.',
Va='Vandreynna:BAABNQAECn87AAIEAAoKniJbBgCQAwAEAAoKniJbBgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIFAAMANsTAA==.Venasia:BAAANQADCgYIBgABNQAECgoKOwAEAJ4iAA==.Verbren:BAAANQAECgcIBwABNQAECgoKLQAiAMwTAA==.Verbrennen:BAABNQAECn8tAAIiAAoKzBMeGgAhAgAiAAoKzBMeGgAhAgAAAA==.Verita:BAAANQAECgQIBwAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.Vetinari:BAAANQABCggIGgABNQAECggIKAAFALQWAA==.',
Vi='Viviann:BAABNQAECn8vAAMiAAoK1QoCDQCxAQAiAAoK1QoCDQCxAQAfAAYKPAlEIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAECgkJOwAWAHYUAA==.Warraxe:BAAANQADCgYIBgAAAA==.Waukeen:BAAANQAECgEIAQAAAA==.Wayloren:BAABNQAECn8nAAIBAAgKhwgx0gB3AQABAAgKhwgx0gB3AQAAAA==.Wayverly:BAAANQAECgEIAQABNQAECgYIDAAGAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECn8wAAIYAAoKfCNwAQCTAwAYAAoKfCNwAQCTAwAAAA==.Wickcreu:BAAANQAECgMIAwAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgUIDQAGAAAAAA==.Worstdps:BAACNQAFFH8IAAIEAAQKiQNDDACaAAAEAAQKiQNDDACaAAA1AAQKfzgAAgQACgrjFkoqAE8CAAQACgrjFkoqAE8CAAAA.',
Wu='Wuldorr:BAACNQAFFH8JAAIBAAQKAAfYFQAAAQABAAQKAAfYFQAAAQA1AAQKfyIAAgEACgp6EQOcAOsBAAEACgp6EQOcAOsBAAAA.',
Wy='Wynnifred:BAABNQAECn8WAAMiAAUKehq9FwD1AAAiAAQKWhe9FwD1AAAfAAQKFgR9FwBoAAAAAA==.',
Xa='Xaltheris:BAAANQAECgUICQAAAA==.',
Xe='Xenothor:BAAANQAECgEIAgAAAA==.Xethreal:BAABNQAECn8fAAINAAcKnx2+RABOAgANAAcKnx2+RABOAgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgcICwAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIBAAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.Zasko:BAAANQAECgYIBgAAAA==.',
Zi='Zifao:BAABNQAECn8rAAIPAAoKmyITKQA/AwAPAAoKmyITKQA/AwAAAA==.',
Zo='Zonora:BAABNQAECn8gAAIJAAkKFBC0QwCHAQAJAAkKFBC0QwCHAQAAAA==.',
['Âr']='Ârduous:BAAANQAECgEIAQAAAA==.',
['Äz']='Äzrael:BAABNQAECn8aAAIMAAgKjhlHSABNAgAMAAgKjhlHSABNAgAAAA==.',
['Çr']='Çréwüsæðèr:BAABNQAECn8cAAIcAAcKXR7dDgA+AgAcAAcKXR7dDgA+AgAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIIAAQKlxPuEQBDAQAIAAQKlxPuEQBDAQA1AAQKfzYAAggACgriICMOAN4CAAgACgriICMOAN4CAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECgYIEAAGAAAAAA==.',
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
