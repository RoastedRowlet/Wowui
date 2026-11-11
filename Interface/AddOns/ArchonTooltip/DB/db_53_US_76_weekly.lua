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

local lookup = {'Paladin-Retribution','Shaman-Enhancement','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-BeastMastery','Unknown-Unknown','Paladin-Holy','Paladin-Protection','Priest-Holy','Shaman-Restoration','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Evoker-Devastation','Mage-Frost','Mage-Fire','Warrior-Arms','Evoker-Preservation','Monk-Mistweaver','Rogue-Outlaw','Priest-Discipline','Monk-Windwalker',}
local provider = {region='US',realm='Draka',name='US',type='weekly',zone=53,date='2026-11-10',data={Ab='Aberaht:BAABNQAECn88AAIBAAoKHCOjFAAMAwABAAoKHCOjFAAMAwAAAA==.Abercrombie:BAAANQAECgEIAQAAAA==.Absolution:BAABNQAECn8WAAICAAgKUQm+IQBCAQACAAgKUQm+IQBCAQAAAA==.',
Ac='Ackianae:BAAANQAECgYIEwAAAA==.',
Ad='Adenwey:BAABNQAECn8kAAIDAAoKcB/WBQB7AwADAAoKcB/WBQB7AwABNQAECgoKSAAEADskAA==.Adewey:BAAANQAECgUIDQAAAA==.Adorabull:BAAANQADCgIIAgAAAA==.',
Ae='Aenastian:BAAANQADCgUIDwABNQAECgoKSAAEADskAA==.Aerynsun:BAAANQABCggIDgABNQAECgkJMQAFAMEVAA==.',
Ai='Airreona:BAAANQAECgIIAgAAAA==.',
Ak='Akhalla:BAAANQAECgQIBAABNQAECgkJFgAGAOIOAA==.Akre:BAAANQAECgEIAQABNQAECggIHgAHAMwNAQ==.Akumä:BAAANQADCgcIEQAAAA==.',
Al='Alarmclock:BAAANQABCgcIDQABNQAECgkJMQAFAMEVAA==.Aleannia:BAAANQAECgEIAwAAAA==.Alekz:BAAANQADCgYIBgAAAA==.Alestria:BAABNQAECn8rAAIBAAoK8RphdgBAAgABAAoK8RphdgBAAgAAAA==.Algodón:BAAANQADCgEIAgABNQAFFAMIBQAIAKodAA==.Alibrexia:BAABNQAECn8rAAIFAAoKuwr8DgB0AQAFAAoKuwr8DgB0AQAAAA==.Allus:BAAANQABCgUICQAAAA==.Alphaomega:BAAANQAECggIDwAAAA==.',
An='Anarcy:BAAANQAECgIIAwAAAA==.Anastaysha:BAAANQAECgQIBgABNQAECggIDwAJAAAAAA==.Anathema:BAAANQAECgUIBwAAAA==.Ankan:BAABNQAECn8sAAIKAAoK2iBtJACQAgAKAAoK2iBtJACQAgABNQAECgoKSAAEADskAA==.Annalese:BAAANQADCgcIBwABNQAECggIDwAJAAAAAA==.',
Ap='Ape:BAAANQAECgQIBAAAAA==.Apoc:BAAANQADCgUIBQAAAA==.',
Ar='Arcticplague:BAAANQAECgEIAQAAAA==.Ardatha:BAAANQADCgIIAgAAAA==.Arduka:BAAANQAECgEIAQAAAA==.Ariêz:BAAANQADCgQIBAAAAA==.Arlor:BAAANQADCgYIDAAAAA==.',
As='Ashkada:BAAANQADCgQIBAAAAA==.Astrocakes:BAAANQADCgYICgABNQAFFAEIAgAJAAAAAA==.',
At='Athenä:BAACNQAFFH8aAAILAAcKuRlzAgBtAQALAAcKuRlzAgBtAQA1AAQKfzIAAgsACgoGH4ELAOECAAsACgoGH4ELAOECAAAA.Atsuma:BAAANQAECgEIAQAAAA==.Atthel:BAAANQAECgYIDQAAAA==.Attunement:BAAANQAECgQIBwABNQAECggIEwAJAAAAAA==.',
Ay='Aylah:BAAANQABCgIIAgABNQAECgYICgAJAAAAAA==.Aylli:BAAANQADCgcIBwABNQAECgkJJAAMAK8dAA==.',
Az='Azei:BAAANQADCgMIAwAAAA==.',
['Aí']='Aísling:BAABNQAECn8VAAIKAAYKzhh2bABcAQAKAAYKzhh2bABcAQAAAA==.',
Ba='Baconmecrazy:BAAANQADCgMIAwAAAA==.Baela:BAAANQAECgMIBAABNQAFFAcIHAANAPcdAA==.Baelthemar:BAAANQADCgUIBQAAAA==.Bajafresh:BAAANQADCgMIAwAAAA==.Bambita:BAAANQAECggIDwAAAA==.Battleshaman:BAAANQAECgEIAQAAAA==.',
Be='Benjinana:BAABNQAECn8UAAIMAAUK2xNYqgAXAQAMAAUK2xNYqgAXAQAAAA==.',
Bi='Bittybombom:BAAANQAECgUIDQAAAA==.Bixibonxle:BAAANQAECgEIAQAAAA==.',
Bk='Bkunstopabl:BAAANQADCgIIAgAAAA==.',
Bl='Blackened:BAABNQAECn8iAAIOAAkKIxjvBQAHAgAOAAkKIxjvBQAHAgAAAA==.Bloodbraid:BAAANQADCgMIAwAAAA==.',
Bo='Bohde:BAAANQAFFAEIAQAAAA==.Boricua:BAAANQAECgIIAgAAAA==.Bountty:BAAANQADCgYIBgAAAA==.',
Br='Brightbane:BAAANQAECgEIBAAAAA==.',
Bu='Buddie:BAAANQADCggICAAAAA==.Buffaloseven:BAABNQAECn8WAAIKAAgK6gxmbwBTAQAKAAgK6gxmbwBTAQABNQAFFAYIDwAPAFIVAA==.Bulleitrye:BAAANQADCgYIBgAAAA==.Burninate:BAAANQABCggIEQABNQAECgkJMQAFAMEVAA==.',
By='Byorn:BAABNQAECn8YAAMQAAkKcBMwZgBaAQAQAAcKew4wZgBaAQARAAcKgBMlVQApAQABNQAFFAQICgAIAPwSAA==.',
Ca='Cairdamane:BAABNQAECn8vAAMSAAoKohDzcgDIAQASAAoKohDzcgDIAQANAAMKPAai3ABQAAAAAA==.Calidrina:BAABNQAECn86AAIHAAoKQxMaFwDsAQAHAAoKQxMaFwDsAQAAAA==.Caness:BAAANQADCgEIAQAAAA==.',
Ce='Celldrassil:BAABNQAECn8aAAIDAAgKwgoqOQAZAQADAAgKwgoqOQAZAQAAAA==.Cellerunn:BAAANQADCgYIBgAAAA==.Cereel:BAABNQAECn8ZAAMTAAkK6hxKMgAVAgATAAcKdBtKMgAVAgAUAAUK8RmbUgCdAQABNQAFFAEIAgAJAAAAAA==.',
Ch='Charayi:BAAANQADCggICAABNQAECggIDwAJAAAAAA==.Chardaney:BAAANQAECggIDwAAAA==.Cheery:BAAANQAECgYIBgABNQAECgkJMQAFAMEVAA==.Chickennuggi:BAABNQAECn8aAAIVAAcKwyAzEAAfAgAVAAcKwyAzEAAfAgABNQAECgkJJQAQAIgjAA==.',
Ci='Cii:BAABNQAECn8yAAMLAAoKTxLhIwA6AQALAAcKwxXhIwA6AQABAAgKIgff3wAIAQAAAA==.Ciine:BAAANQADCgYICAABNQAECgoKMgALAE8SAA==.Ciinelock:BAAANQADCgIIAgABNQAECgoKMgALAE8SAA==.Ciruzita:BAAANQAECgEIAgAAAA==.',
Cl='Clampz:BAEANQAECgUICAABNQAFFAcIFAAUAD0eAA==.',
Co='Colabrn:BAAANQADCggIFwAAAA==.Colandros:BAAANQADCgEIAQAAAA==.Colara:BAABNQAECn8sAAIHAAoKogzJHgCYAQAHAAoKogzJHgCYAQAAAA==.Colbear:BAAANQABCgUICQAAAA==.Coldspace:BAABNQAECn9ZAAIBAAoKbCHdGQBdAwABAAoKbCHdGQBdAwAAAA==.Corlock:BAAANQABCgUIBQAAAA==.Corrupt:BAAANQAECgEIAwAAAA==.Covidgirl:BAAANQAECgEIAQAAAA==.',
Cr='Crassberry:BAACNQAFFH8MAAIWAAcKMxUCDABNAQAWAAcKMxUCDABNAQA1AAQKfykAAhYACgoSJUkkALACABYACgoSJUkkALACAAAA.Creepindeath:BAAANQAECgEIAwAAAA==.',
Cu='Cucaracha:BAABNQAECn8XAAMXAAgK9RCTFQBVAQAXAAgK9RCTFQBVAQAYAAEKAAD+ywAVAAAAAA==.',
Cy='Cyndal:BAAANQAECgEIAwABNQAECgYICgAJAAAAAA==.Cyndle:BAAANQAECgEIAQABNQAECgYICgAJAAAAAA==.Cyntu:BAAANQAECgEIAQABNQAECgYICgAJAAAAAA==.',
Da='Dagrathon:BAAANQADCgEIAQAAAA==.Dankbuds:BAAANQAECggIEQAAAA==.Dankothy:BAAANQAECgQICgABNQAECggIEQAJAAAAAA==.Dankreaper:BAAANQAECgEIAQABNQAECggIEQAJAAAAAA==.Dankshot:BAAANQAECgYIBgABNQAECggIEQAJAAAAAA==.Dantes:BAAANQAECgEJAwAAAA==.Darkryu:BAAANQADCgYIEAAAAA==.Darkspace:BAABNQAECn8XAAQZAAoKcRUnBQCWAQAZAAcKkBcnBQCWAQAOAAQKFhBBFQD2AAAaAAYKigl+twDQAAABNQAECgoKWQABAGwhAA==.Darthsix:BAAANQADCgEIAQAAAA==.Dazex:BAAANQAECgUIEQAAAA==.',
De='Deadbolt:BAABNQAECn8VAAMZAAcKkAdCGgCGAAAaAAYKTQQhwwC4AAAZAAUKTwtCGgCGAAAAAA==.Deathforever:BAAANQAECgQICQAAAA==.Deathskys:BAAANQAECgEIAQAAAA==.Deaus:BAAANQADCggIFQAAAA==.Delrus:BAABNQAECn85AAQDAAoKdh6qCgANAwADAAoKdh6qCgANAwAVAAgKIxDBKQAlAQAYAAUKMBCPWACsAAAAAA==.Demon:BAABNQAECn9DAAMEAAoKlCACDQBBAwAEAAoKlCACDQBBAwAGAAMK0RpbHQCOAAABNQAFFAgIIQAUAGgRAA==.Demoniec:BAAANQAECgQIBQAAAA==.Demowneege:BAAANQADCggICAABNQAFFAcIGAAFAJYeAA==.Denzvic:BAAANQAECgYICwAAAA==.Destro:BAAANQADCggICAAAAA==.Devil:BAAANQABCgQIBAAAAA==.',
Di='Diddyjr:BAABNQAECn8mAAIPAAoK0Ru7fACFAgAPAAoK0Ru7fACFAgABNQAFFAEIAQAJAAAAAA==.Disowneege:BAAANQAECggIEAABNQAFFAcIGAAFAJYeAA==.Diyos:BAAANQADCggICAAAAA==.',
Do='Doodu:BAAANQAFFAEIAQAAAA==.',
Dr='Draculla:BAAANQAECgEIAQAAAA==.Dragnas:BAABNQAECn9EAAQCAAoKaBJhDgAbAgACAAoKaBJhDgAbAgANAAQKuxJrvADyAAASAAEKHg5NLgE6AAAAAA==.Dragonisa:BAAANQAECgMIBAAAAA==.Draiocht:BAAANQADCgQIBwABNQAECgkJJAAMAK8dAA==.Drakass:BAAANQAECgMIAwAAAA==.Dramakiller:BAAANQAECgUIEQAAAA==.Drcornbread:BAABNQAECn8UAAMXAAUK8w7dIAAOAQAXAAUKhQ7dIAAOAQAVAAQKCAy5QwCmAAAAAA==.Drcornellia:BAAANQADCgYIBwABNQAECgUIFAAXAPMOAA==.Drdreggs:BAABNQAECn8kAAMaAAoK2hEzhADbAQAaAAkKixEzhADbAQAZAAEKBhTVcQA9AAAAAA==.Drop:BAAANQADCgQIBAABNQAECgoKQAABAF0fAA==.Druduwolf:BAAANQAECgcIEwAAAA==.',
Du='Durden:BAAANQADCgIIAgABNQAECgYIEgAJAAAAAA==.Dustyhunter:BAAANQAECgEIAQAAAA==.Duthalemar:BAAANQADCggICgABNQAECgoKSAAEADskAA==.',
Ea='Eatbuttforpi:BAAANQADCgUIBwABNQAFFAEIAgAJAAAAAA==.',
El='Elastar:BAABNQAECn8+AAIbAAoK9xlXCABHAgAbAAoK9xlXCABHAgAAAA==.Ellimist:BAEANQAECgcIDgAAAA==.Elsan:BAAANQADCgQIBAAAAA==.Elycee:BAABNQAECn8jAAMIAAoKoSOyEAAGAwAIAAoKoSOyEAAGAwAcAAoK9RCVFwC+AQAAAA==.',
Em='Emura:BAAANQAECgMIBAAAAA==.',
En='Enveliria:BAAANQAECgYIEgABNQAECgoKSAAEADskAA==.',
Er='Eraser:BAABNQAECn9CAAMMAAoKCBQ/ZADzAQAMAAoKCBQ/ZADzAQAdAAgK0g57IgBZAQAAAA==.Erazar:BAABNQAECn8fAAIeAAkKLAh2DwA0AQAeAAkKLAh2DwA0AQAAAA==.Erickk:BAABNQAECn88AAIPAAoKYxugTgDkAgAPAAoKYxugTgDkAgAAAA==.Eristela:BAAANQAECgUIBwAAAA==.',
Es='Escanorlion:BAAANQAECgUIBwAAAA==.Essense:BAABNQAECn88AAIMAAoKSyXGAwDuAwAMAAoKSyXGAwDuAwAAAA==.',
Ev='Evokedcat:BAAANQAECgcIDwAAAA==.',
Ex='Exodari:BAABNQAECn89AAICAAoKzA+7EQDjAQACAAoKzA+7EQDjAQAAAA==.Extro:BAAANQAECgcICQAAAA==.',
Fa='Fabbioh:BAAANQADCgEIAQAAAA==.Fadeddh:BAAANQAECgUIBwABNQAFFAEIAgAJAAAAAA==.Faeliendra:BAAANQADCggICAAAAA==.Fangloria:BAAANQABCggIEwABNQAECgkJMQAFAMEVAA==.Fatalgrip:BAAANQADCgUIBgAAAA==.',
Fe='Fel:BAABNQAECn9YAAMEAAoKFCS8BgCLAwAEAAoKrCO8BgCLAwAHAAoKOyKvCQCvAgAAAA==.Fellius:BAAANQADCgQIBAAAAA==.Fellkarras:BAAANQAECgUICAABNQAECgkJJQAQAIgjAA==.Felprincess:BAAANQABCgYICgAAAA==.',
Fi='Fibitz:BAAANQAECgcIDQABNQAECgoKMwAIAJohAA==.Fiddich:BAAANQAECgQIBQAAAA==.Findstewie:BAAANQABCgYICgABNQABCggIFgAJAAAAAA==.Fiofio:BAABNQAECn86AAIPAAoKVRwtOABZAgAPAAoKVRwtOABZAgAAAA==.Fizban:BAABNQAECn8eAAMfAAkK/QvxDwCoAQAfAAkK/QvxDwCoAQAPAAQK+AEimwGQAAAAAA==.',
Fl='Flik:BAAANQAECgUICQABNQAECgoKXgAMAGUdAA==.',
Fo='Foringojr:BAAANQAECgIIAgAAAA==.',
Fr='Fragglelock:BAAANQABCggIFQABNQAECgkJMQAFAMEVAA==.Frigidheart:BAAANQAECgUIDQABNQAECgoKIQABAHYLAA==.Frostetute:BAABNQAECn8fAAIPAAoK/gz2ZwDTAQAPAAoK/gz2ZwDTAQAAAA==.',
Fu='Furrybawlz:BAAANQADCggICAABNQAECgQIBAAJAAAAAA==.',
['Fà']='Fàllén:BAAANQAECgEIAwABNQAFFAQICgAIAPwSAA==.',
Ga='Gadogear:BAABNQAECn8iAAIfAAgKNhcADwCEAQAfAAgKNhcADwCEAQAAAA==.Galabren:BAAANQAECgYJDgAAAA==.Garlik:BAAANQADCgUIDQAAAA==.',
Ge='Gertra:BAABNQAECn8XAAMBAAkKmhHSZQD0AQABAAkKmhHSZQD0AQALAAEK4QYcaQAlAAAAAA==.',
Gf='Gfr:BAABNQAECn8ZAAMZAAcKQhsWDgAYAgAZAAcKQhsWDgAYAgAaAAEKAADbKAEAAAAAAA==.',
Gi='Giddoo:BAAANQAECgYIDgAAAA==.Gilnean:BAAANQABCgUIBgAAAA==.',
Gn='Gnomeanator:BAAANQAECgEIAgAAAA==.Gnowanceyi:BAAANQAECgIIAwABNQAECgoKPAAPAGMbAA==.',
Go='Goatcheeze:BAAANQAECggIEQAAAA==.Gohlemsaurus:BAAANQADCggIJAAAAA==.',
Gu='Gulen:BAAANQADCggIGwAAAA==.Gullee:BAAANQABCggIEwAAAA==.',
Gw='Gwennevier:BAAANQAECgEIAQAAAA==.',
['Gí']='Gíga:BAAANQAECgMIBAAAAA==.',
Ha='Halsten:BAABNQAECn8oAAQfAAgKvgZ+GAAEAQAfAAgKvgZ+GAAEAQAPAAUKswFwmgGRAAAgAAEKAACYDwAhAAAAAA==.Hamish:BAAANQAECgEIAQAAAA==.',
He='Hellenkeller:BAEANQAFFAEIAQABNQAFFAcIFAAUAD0eAA==.Heloisa:BAAANQADCgYIBgAAAA==.Helrazor:BAAANQADCgUIBQABNQAECgoKKQAXAIgZAA==.',
Hi='Hila:BAAANQAECgEIAQAAAA==.Hitt:BAAANQAECgYICgAAAA==.',
Ho='Hogwortsfun:BAAANQADCggICAAAAA==.Holysudz:BAAANQADCgIIAgAAAA==.Hoofingit:BAAANQAECgcIDQAAAA==.',
Hr='Hroc:BAABNQAECn8XAAITAAkKhgkZRQCyAQATAAkKhgkZRQCyAQAAAA==.',
Hu='Hunterboi:BAAANQAECgEIAQAAAA==.',
Ic='Icedlatte:BAAANQADCgUIDQAAAA==.Icywolfy:BAAANQAECgIIAgAAAA==.',
Ig='Igreetyou:BAAANQAECgQICQAAAA==.',
Il='Illune:BAABNQAECn80AAIPAAoK9hb8QAA8AgAPAAoK9hb8QAA8AgAAAA==.',
Im='Imleapingit:BAABNQAECn8mAAIhAAkKbRrCMQBqAgAhAAkKbRrCMQBqAgAAAA==.Imrelentless:BAAANQABCgYICwAAAA==.',
In='Inaurian:BAAANQAECgEIAQAAAA==.Intoodeep:BAABNQAECn9QAAITAAoKNR5YBQC6AgATAAoKNR5YBQC6AgAAAA==.Intoodemons:BAAANQAECgIIAgABNQAECgoKUAATADUeAA==.',
Ir='Ir:BAABNQAECn9gAAIPAAoKnR0fPQAMAwAPAAoKnR0fPQAMAwAAAA==.Ironfoot:BAAANQAECgQIBAAAAA==.Irrlvntgobbo:BAAANQAECgYICwAAAA==.',
Is='Isasham:BAAANQAECgIIAgAAAA==.Isawarriorr:BAABNQAECn8eAAMhAAkKshkqXgByAgAhAAkKmRcqXgByAgAbAAIK0Rv1NACOAAAAAA==.Ishdo:BAABNQAECn8iAAIQAAkKggswYQBtAQAQAAkKggswYQBtAQAAAA==.Ishdu:BAAANQADCgYIBgABNQAECgkJIgAQAIILAA==.Ishlok:BAAANQADCgUIBQABNQAECgkJIgAQAIILAA==.Ishmael:BAAANQAECgQIBQABNQAFFAQICgAIAPwSAA==.Ishwar:BAAANQADCggIGAABNQAECgkJIgAQAIILAA==.',
Iv='Ivanhöe:BAAANQAECgUIBwAAAA==.',
Ja='Jakytreehorn:BAABNQAECn8UAAISAAgKZBDVZwDpAQASAAgKZBDVZwDpAQAAAA==.Jaydm:BAAANQAECggIEAABNQAFFAYIDwAPAFIVAA==.',
Je='Jenevelle:BAAANQAECgMJAwAAAA==.Jerisil:BAAANQAECgEIAgAAAA==.Jessiel:BAAANQAECgUIBQAAAA==.Jet:BAABNQAECn9AAAIBAAoKXR+ZKgCqAgABAAoKXR+ZKgCqAgAAAA==.',
Ji='Jibbajabba:BAAANQAECgEIAQAAAA==.',
Ju='Judgiah:BAAANQAECgIIAgAAAA==.Julthaenia:BAABNQAECn8wAAIOAAkKaRjVAwCwAgAOAAkKaRjVAwCwAgABNQAECgoKSAAEADskAA==.Junjia:BAAANQADCgUIBQAAAA==.',
Ka='Kagebushin:BAAANQAECgEIAQAAAA==.Kagome:BAAANQADCggIDQABNQAECggIDwAJAAAAAA==.Kalofelement:BAAANQADCgEIAQAAAA==.Kalysy:BAAANQAECgEIAgABNQAECgoKSAAEADskAA==.Karash:BAAANQAECgYIEgAAAA==.Kargush:BAAANQADCgQIBAABNQADCggIFgAJAAAAAA==.Karmaisab:BAAANQAECggIAQAAAA==.Karnrae:BAABNQAECn8vAAIBAAoKiRbIUgAjAgABAAoKiRbIUgAjAgAAAA==.Karynos:BAABNQAECn85AAIaAAoK5RCsUgDJAQAaAAoK5RCsUgDJAQAAAA==.Katwolf:BAABNQAECn8bAAIIAAgKywy3gQCbAQAIAAgKywy3gQCbAQAAAA==.Katyah:BAABNQAECn8XAAINAAgKCAfIlgBOAQANAAgKCAfIlgBOAQAAAA==.Kavourkaa:BAAANQABCggIHQAAAA==.',
Ke='Keynivas:BAAANQAECgIIAwAAAA==.',
Ki='Killiua:BAAANQAECgcICwAAAA==.',
Ko='Kobayashi:BAAANQAECgUIBQABNQAECgkJMQAFAMEVAA==.Konspiracy:BAABNQAECn8eAAMZAAkK3BMCBwBUAQAZAAkK3BMCBwBUAQAaAAEKAAAfTAErAAAAAA==.',
Kr='Kraguva:BAAANQAECgQIBAAAAA==.Krataar:BAAANQAECgEIAQABNQAECgYIDwAJAAAAAA==.Kroot:BAABNQAECn8zAAIIAAoKmiHqFQDmAgAIAAoKmiHqFQDmAgAAAA==.Krous:BAACNQAFFH8UAAIhAAcKOxvmCgACAgAhAAcKOxvmCgACAgA1AAQKfy4AAiEACgrEHxBPAJwCACEACgrEHxBPAJwCAAAA.Kryph:BAAANQAECgcIEwAAAA==.',
['Kä']='Kämpfer:BAAANQAECgcIDAABNQAECgoKMgAiALsUAA==.',
La='Lafiel:BAABNQAECn81AAIMAAoKohEuSQD+AQAMAAoKohEuSQD+AQAAAA==.Landiedoo:BAAANQAECggIAQAAAA==.Latrank:BAAANQAECgYIBwAAAA==.Laurandre:BAABNQAECn8sAAMDAAkKpAd2NQAwAQADAAkKpAd2NQAwAQAYAAIK3APXjwAgAAAAAA==.Lazeras:BAAANQAECgUICAABNQAECgoKKQAXAIgZAA==.',
Le='Letsgetwet:BAAANQAECgQIBgAAAA==.',
Li='Liefic:BAABNQAECn83AAIIAAoKuSEhEAAJAwAIAAoKuSEhEAAJAwAAAA==.Lilibeth:BAAANQADCggICgAAAA==.Lilienne:BAAANQAECgEIAQAAAA==.Lilstooge:BAAANQABCgYIBwABNQABCggIFgAJAAAAAA==.Limon:BAAANQAECgcICQAAAA==.',
Ll='Llylith:BAAANQAECgEIAwAAAA==.',
Lo='Locke:BAAANQAECgcICwABNQAECgoKQAABAF0fAA==.',
Lu='Luckykilla:BAABNQAECn81AAITAAoKwxhXCwANAgATAAoKwxhXCwANAgAAAA==.Lucÿ:BAACNQAFFH8OAAINAAQKgRhMEQArAQANAAQKgRhMEQArAQA1AAQKfy0AAw0ACgqzHuQjANcCAA0ACgqzHuQjANcCABIABgp7EmyYAGgBAAAA.Lune:BAAANQADCgUICwAAAA==.Lurith:BAABNQAECn9PAAMQAAkKtRgzLgCKAQAQAAkKzBMzLgCKAQAWAAcKyxhfNQA3AQAAAA==.Luxtyrannica:BAAANQAECgcIEQAAAA==.',
Ly='Lydrain:BAAANQAECgQIBQAAAA==.Lylia:BAAANQADCggIGAAAAA==.',
Ma='Malcolm:BAAANQABCgYIDQABNQAECgkJMQAFAMEVAA==.Marahh:BAAANQABCgIIAgAAAA==.Matt:BAAANQAECgQIBQABNQAFFAgIIQAUAGgRAA==.Mattbolt:BAABNQAECn8ZAAICAAkKNiEDDwB6AgACAAkKNiEDDwB6AgAAAA==.Maximoose:BAACNQAFFH8KAAIIAAQK/BKDEQBIAQAIAAQK/BKDEQBIAQA1AAQKfyMAAggACgq6GXhHAJYCAAgACgq6GXhHAJYCAAAA.Mayu:BAAANQAECgEIBgAAAA==.Mayumey:BAAANQADCgUIBQAAAA==.Mazigos:BAAANQAECgUIBwAAAA==.',
Me='Medjrab:BAACNQAFFH8GAAIWAAIKtxc/CgClAAAWAAIKtxc/CgClAAA1AAQKf0cAAhYACgpkI3wJAHIDABYACgpkI3wJAHIDAAAA.Mefi:BAAANQADCgcIFgAAAA==.Melyria:BAABNQAECn8eAAIHAAgKzA1EMwCoAQAHAAgKzA1EMwCoAQAAAA==.Meristem:BAABNQAECn8mAAIYAAgKVA1KOgAyAQAYAAgKVA1KOgAyAQAAAA==.Merko:BAAANQADCggICQABNQAECgoKMwAIAJohAA==.',
Mi='Mignius:BAAANQADCgYIBgAAAA==.Mihonk:BAAANQAECgUICAAAAA==.Millesfavdom:BAABNQAECn8bAAIEAAkKaRLaIADvAQAEAAkKaRLaIADvAQABNQAFFAgIFAAVAHAQAA==.Misafarm:BAAANQADCgIIAgAAAA==.Mistified:BAAANQABCgIIBAAAAA==.',
Mo='Moedorai:BAAANQAECggIEgAAAA==.Mogma:BAAANQAECgUICgAAAA==.Mogsarren:BAAANQAECgEIAQABNQAECgoKUQAQAL8lAA==.Momentomori:BAAANQADCgUICwAAAA==.Mondgrille:BAAANQAECgQIBAAAAA==.Monora:BAAANQADCggICQAAAA==.Moonbounds:BAACNQAFFH8VAAINAAgKHhsGBgAIAgANAAgKHhsGBgAIAgA1AAQKf1oAAg0ACgrSI5kFAJoDAA0ACgrSI5kFAJoDAAAA.Moondoggey:BAAANQADCgUIBQAAAA==.Morgana:BAAANQADCgYICAAAAA==.Mousechief:BAABNQAECn8kAAISAAcKFAMdoQCwAAASAAcKFAMdoQCwAAAAAA==.Moxxzi:BAABNQAECn8rAAIWAAgK2BFdJwCTAQAWAAgK2BFdJwCTAQAAAA==.',
Mu='Muhfookinbak:BAABNQAECn8oAAQSAAoKEyIRIgABAwASAAoKEyIRIgABAwACAAEKixMpMgBBAAANAAEKUxD2FwE7AAAAAA==.',
Na='Naksu:BAAANQADCgYJFgABNQAECgoKMgAMAAMgAA==.Naksù:BAAANQADCgUIBQABNQAECgoKMgAMAAMgAA==.Naksû:BAAANQAECgIIAQABNQAECgoKMgAMAAMgAA==.Naksü:BAABNQAECn8yAAIMAAoKAyDfEwAnAwAMAAoKAyDfEwAnAwAAAA==.',
Ne='Neifeb:BAABNQAECn8qAAIIAAkKcxHxggAGAgAIAAkKcxHxggAGAgAAAA==.Nerfherder:BAAANQABCgcIDwABNQAECgkJMQAFAMEVAA==.',
Ni='Niallivdam:BAAANQAECgQIDwAAAA==.Nights:BAAANQAECggICwABNQAFFAgIIQAUAGgRAA==.Ninh:BAABNQAECn9gAAIjAAoKZg9OEgDMAQAjAAoKZg9OEgDMAQAAAA==.Nintendopsp:BAAANQAECgIIAgAAAA==.Ninthgate:BAABNQAECn8cAAIaAAgKuAWZ4QAGAQAaAAgKuAWZ4QAGAQAAAA==.',
No='Noble:BAABNQAECn89AAMHAAoK0hZREgAoAgAHAAoK0hZREgAoAgAEAAEKuQZXgQAvAAAAAA==.Nogood:BAABNQAECn8ZAAIhAAoKRRYzaQBVAgAhAAoKRRYzaQBVAgAAAA==.Northwest:BAAANQAECgEIAgAAAA==.Notsodemon:BAAANQAECgQICQABNQAECgcIFQAPAJsLAA==.Notsomage:BAABNQAECn8VAAIPAAcKmwsDAwGJAQAPAAcKmwsDAwGJAQAAAA==.',
Ny='Nyorai:BAAANQABCgQIAwAAAA==.Nyxwing:BAAANQAECgYICgAAAA==.',
['Nå']='Nåld:BAAANQAECgEIAQAAAA==.',
['Në']='Nëao:BAAANQADCgYIBgAAAA==.',
Ob='Obvinotagirl:BAABNQAECn84AAMDAAoKICKAAwC9AwADAAoKICKAAwC9AwAYAAEKAAC3xwAaAAAAAA==.',
Od='Oddone:BAAANQAECgQIBgAAAA==.Oddpocalypse:BAAANQADCgQIBAAAAA==.Odelina:BAAANQADCggIDgAAAA==.Odinheâthen:BAAANQAECgEIAgAAAA==.',
Ol='Olydwarf:BAAANQAECgEIAgAAAA==.',
On='Onebadmutha:BAABNQAECn8WAAIaAAgK9AhwigA0AQAaAAgK9AhwigA0AQAAAA==.Ontop:BAABNQAECn9gAAIIAAoK6x4kKAD3AgAIAAoK6x4kKAD3AgAAAA==.',
Or='Orb:BAAANQAECgEIAQAAAA==.Ortinks:BAABNQAECn8oAAMfAAgKqxUuDQDgAQAfAAgKqxUuDQDgAQAPAAMK1wV1swFaAAAAAA==.',
Ow='Owneege:BAACNQAFFH8YAAMFAAcKlh4qAAC6AQAFAAcKCRsqAAC6AQAhAAUKYRo7EgCeAQA1AAQKfzkAAyEACgooJGgjAKkCACEACgr1ImgjAKkCAAUACQq0IncKANEBAAAA.',
Pa='Paapaa:BAABNQAECn8UAAIUAAoK6BVgKQBJAgAUAAoK6BVgKQBJAgAAAA==.Pallideaus:BAABNQAECn8fAAIKAAgKLSCTLwCoAgAKAAgKLSCTLwCoAgAAAA==.Pallinar:BAABNQAECn8VAAIBAAgKcAk36ABLAQABAAgKcAk36ABLAQAAAA==.Pandamak:BAAANQADCggICAAAAA==.Paradoxx:BAAANQADCgIIBAAAAA==.Pasquale:BAAANQAECgUICgAAAA==.Pauzhaan:BAAANQAECgUICQABNQAECgkJMQAFAMEVAA==.',
Pe='Pebbles:BAABNQAECn9FAAIBAAoKJhY2ZQD1AQABAAoKJhY2ZQD1AQAAAA==.Pedorus:BAAANQABCgYIBwABNQAFFAQIDgANAIEYAA==.Penjerman:BAAANQAFFAEIAgAAAA==.',
Pi='Picklericky:BAAANQADCggIEQAAAA==.Pilgrimm:BAECNQAFFH8UAAIUAAcKPR7uAQA4AgAUAAcKPR7uAQA4AgA1AAQKfzIABBQACgq0JZ4DAGUDABQACgq0JZ4DAGUDACQAAQq5G4YZAEwAABMAAQpBC42gADoAAAAA.Pinxyl:BAAANQABCgcIBwAAAA==.Pistola:BAAANQAECgQIBAAAAA==.Pix:BAAANQABCgQIBwAAAA==.Pixyl:BAAANQAECgEIBAAAAA==.',
Pl='Plaguerott:BAABNQAECn8YAAIRAAcKsgVSYgAbAQARAAcKsgVSYgAbAQAAAA==.Plaguewind:BAAANQAECgUICAAAAA==.',
Po='Polydh:BAABNQAECn8yAAIGAAoKYSQJAQC1AwAGAAoKYSQJAQC1AwAAAA==.Poobah:BAABNQAECn8iAAMSAAgKkQfrwgAMAQASAAcKTQjrwgAMAQANAAIKrgLn5QBAAAAAAA==.Popsicles:BAABNQAECn8lAAMlAAkKixYqBgAyAgAlAAkKixYqBgAyAgAdAAEKAADjigAfAAAAAA==.Potrat:BAAANQAECgMJBAAAAA==.Pouffant:BAAANQAECgcIDgAAAA==.',
Pr='Praddagy:BAAANQADCgUIBQAAAA==.Prayoncè:BAAANQADCggIDwAAAA==.Pronoz:BAAANQAECggIEAAAAA==.',
Pu='Puffr:BAAANQADCgQIBAAAAA==.Purpyl:BAABNQAECn8WAAIGAAkK4g5fDwA5AQAGAAkK4g5fDwA5AQAAAA==.',
Pw='Pwnageddon:BAAANQAECgMIAwAAAA==.Pwnjitsu:BAABNQAECn88AAImAAoKBx4/CwCdAgAmAAoKBx4/CwCdAgAAAA==.',
Py='Pyrothermia:BAACNQAFFH8PAAIPAAYKUhWIDgADAgAPAAYKUhWIDgADAgA1AAQKfzYAAw8ACgquIm4VAOsCAA8ACgquIm4VAOsCAB8AAwr+BIsyAHEAAAAA.',
Qt='Qtkillz:BAAANQAECgEIAQAAAA==.',
Ra='Rakugan:BAAANQABCgMIAwAAAA==.Rawhoof:BAABNQAECn9gAAIhAAoK8CJIFQD0AgAhAAoK8CJIFQD0AgAAAA==.Razak:BAABNQAECn9DAAICAAoK2iJMBQDaAgACAAoK2iJMBQDaAgAAAA==.',
Rd='Rdnckromeo:BAAANQAECgQIBAAAAA==.',
Re='Redlock:BAABNQAECn8nAAIZAAgKlAvgCQAUAQAZAAgKlAvgCQAUAQAAAA==.Redrum:BAABNQAECn8lAAIQAAkKiCMZCwBbAwAQAAkKiCMZCwBbAwAAAA==.Reineken:BAAANQADCggIEwAAAA==.Renarin:BAABNQAECn9eAAIMAAoKZR19IADtAgAMAAoKZR19IADtAgAAAA==.Renisa:BAABNQAECn8pAAQHAAoKvxRcGADeAQAHAAoKvxRcGADeAQAEAAEKMwb6nAAlAAAGAAEKAAB2NwAAAAAAAA==.Renobagem:BAAANQADCgUIBgAAAA==.Retman:BAAANQADCggIDgAAAA==.Reu:BAAANQAECgcICgAAAA==.Revlyk:BAABNQAECn80AAMCAAoKqR1jCACRAgACAAoKqR1jCACRAgANAAIKtxMSxwB3AAABNQAECgoKSAAEADskAA==.',
Rh='Rhoanna:BAAANQAECgQIBAAAAA==.Rhoupert:BAABNQAECn8WAAIBAAgK6xVhmQDwAQABAAgK6xVhmQDwAQAAAA==.',
Ri='Rimastus:BAAANQAECgEIAQAAAA==.',
Ro='Roccot:BAABNQAECn8/AAIQAAoKrSHLCAD4AgAQAAoKrSHLCAD4AgAAAA==.Rotfather:BAAANQADCgcICAAAAA==.Rotjaw:BAAANQAECgEIAgAAAA==.Roughedge:BAAANQADCgIIAgAAAA==.',
Rv='Rvn:BAAANQAECgUICgAAAA==.',
Ry='Ryppyr:BAAANQADCggICAAAAA==.',
['Rè']='Rèjuva:BAAANQADCgEIAQAAAA==.',
Sa='Saintess:BAAANQABCgYIDAAAAA==.Sallanu:BAAANQAECgEIAQAAAA==.Sardencreian:BAAANQAFFAEIAQAAAA==.Sauron:BAAANQAECggICQAAAA==.',
Sc='Scalycat:BAAANQAECgcIEQAAAA==.Scum:BAAANQADCgcIDQABNQAECgQIBAAJAAAAAA==.',
Se='Senaeda:BAAANQAECgEIAwAAAA==.Senate:BAABNQAECn8/AAMSAAoKwBOaNgDmAQASAAoKwBOaNgDmAQANAAEKqgFVMQEfAAAAAA==.Servenslay:BAAANQADCggIDgAAAA==.',
Sh='Shaamazing:BAAANQAECgEIAQAAAA==.Shablaam:BAAANQAECgIIAwAAAA==.Shadowbear:BAABNQAECn8pAAIdAAkK/xUaFwDcAQAdAAkK/xUaFwDcAQAAAA==.Sherrilyn:BAAANQAECgEIAQAAAA==.Shifdiah:BAAANQAECgUIDAAAAA==.Shocktherapi:BAAANQAECgcIDAAAAA==.Shrimpback:BAAANQAECgIIAgAAAA==.',
Si='Silentwoman:BAAANQAECgEIAQAAAA==.Singularity:BAAANQAECgQJBQAAAA==.',
Sk='Skelli:BAECNQAFFH8bAAIMAAcKlRKXCgDfAQAMAAcKlRKXCgDfAQA1AAQKfyYAAgwACgo/HI47AHsCAAwACgo/HI47AHsCAAE1AAQKBwgOAAkAAAAA.Skittlesdan:BAABNQAECn8mAAQaAAoKYhLSfgDpAQAaAAoKYhLSfgDpAQAOAAEKAAB/MgAvAAAZAAEKxQQWgwAoAAAAAA==.',
Sl='Slaykween:BAABNQAECn8dAAILAAgKxATKSADKAAALAAgKxATKSADKAAAAAA==.Slaynesh:BAAANQADCgcIBwAAAA==.',
Sm='Smallz:BAAANQAECgUIBQABNQAECgkJHgAfAP0LAA==.',
Sn='Sneakin:BAAANQADCgIIAgAAAA==.Snooptrogg:BAABNQAECn8xAAQFAAkKwRURDwC8AQAFAAYK6xgRDwC8AQAhAAgKAw++ugCKAQAbAAUK8A+EKgCXAAAAAA==.',
So='Something:BAAANQABCggIEwABNQAECgkJMQAFAMEVAA==.Soryu:BAAANQAECgIIAgAAAA==.',
Sp='Spacelaser:BAAANQADCgMIAwAAAA==.Specialtwo:BAAANQADCgEIAQAAAA==.',
Sq='Sqwurl:BAAANQADCgUIBQAAAA==.',
St='Steakhaus:BAAANQAECgIIAwAAAA==.Stonedragon:BAECNQAFFH8PAAIIAAUKMxd8EQDxAAAIAAUKMxd8EQDxAAA1AAQKf1YAAggACgqNJaoFALQDAAgACgqNJaoFALQDAAAA.Stormfang:BAAANQADCgcIFAABNQAECgYIFQAKAM4YAA==.Stormfist:BAAANQADCgQIBgAAAA==.Stormhaven:BAAANQADCgQJBAABNQAECgYIFQAKAM4YAA==.Stormrender:BAAANQAECgUICgAAAA==.Stormriders:BAABNQAECn84AAISAAkKVBH0TQCJAQASAAkKVBH0TQCJAQAAAA==.Stouty:BAAANQADCgQIAQAAAA==.Stubz:BAAANQABCgYICAAAAA==.',
Su='Sugi:BAAANQAECgcIDQABNQAFFAQIBwAHALkQAA==.Sukonamí:BAABNQAECn8iAAIhAAoKFBStTQAEAgAhAAoKFBStTQAEAgAAAA==.Suzhou:BAABNQAECn8aAAIZAAgKrQZIDgDXAAAZAAgKrQZIDgDXAAAAAA==.Suzoomies:BAAANQAECgEIAQAAAA==.',
Sw='Swisscheese:BAABNQAECn8eAAMaAAkKqBomXABDAgAaAAkKqBomXABDAgAZAAEKLwpLewAyAAAAAA==.Swoopyboop:BAAANQADCgQIBAAAAA==.',
Sy='Sybaek:BAAANQAECggIDgAAAA==.Sycò:BAABNQAECn8sAAMIAAkKGyOaEgBVAwAIAAkKGyOaEgBVAwAcAAEKkQF3ngAgAAAAAA==.Syraxa:BAAANQAECgMIBgABNQAECgoKTAADAKMbAA==.',
['Sú']='Súbzerø:BAAANQAECgEIAgABNQAFFAQICwAIAJcTAA==.',
Ta='Taedish:BAAANQAECgEIAQAAAA==.Tahzdingle:BAAANQADCgYICwAAAA==.Talorien:BAAANQADCgIIAgABNQAECgoKNAAPAPYWAA==.Tayy:BAAANQADCgYICwAAAA==.',
Te='Teknobutts:BAAANQADCgUIBQAAAA==.Telan:BAAANQADCgUIBQAAAA==.Tempertotems:BAAANQADCggIDQAAAA==.Tenastin:BAAANQAECgEIAQAAAA==.Terragosa:BAABNQAECn8kAAMPAAgKRBYKiwB+AQAPAAgKchQKiwB+AQAfAAIKFwwBNwBgAAAAAA==.Tetchybono:BAABNQAECn8UAAQZAAcK7AxrNQDtAAAZAAQKTQxrNQDtAAAOAAQKfgzSGQC4AAAaAAMKeAYh7wBlAAAAAA==.Tettra:BAAANQADCggIEgABNQAECgYICgAJAAAAAA==.',
Th='Thaeleon:BAAANQAECgMIAwABNQAFFAQICgAIAPwSAA==.Thahawtz:BAAANQADCgYIDAAAAA==.Thirinis:BAABNQAECn8eAAIKAAgKNQpjewAwAQAKAAgKNQpjewAwAQAAAA==.Thope:BAAANQADCgYIFgAAAA==.Thrivia:BAAANQAECggIDAAAAA==.Thundergirl:BAAANQAECggIDwAAAA==.',
Ti='Ticklemychin:BAAANQADCgcIBwAAAA==.Tictacc:BAAANQADCgEIAQAAAA==.',
Tl='Tlàchtga:BAAANQAECgUIBgAAAA==.',
To='Toughasnails:BAAANQAECgEIAwAAAA==.',
Tr='Traesdyne:BAAANQADCgQIBQAAAA==.Trailwalkur:BAAANQADCgYIDAABNQAECgoKKQAXAIgZAA==.Trainar:BAAANQAECgUIEgABNQAECgcIGgAEADEaAA==.Triggs:BAAANQAECggIBwAAAA==.Trollbear:BAAANQADCgcIBwAAAA==.Trooze:BAABNQAECn8aAAIKAAcKHyGBKAB4AgAKAAcKHyGBKAB4AgAAAA==.Truckz:BAABNQAECn8lAAISAAoKFRe1JwAyAgASAAoKFRe1JwAyAgAAAA==.Truckzbrr:BAAANQAECgEIAQABNQAECgoKJQASABUXAA==.Trõnlight:BAAANQAECgEIAQAAAA==.',
Ts='Tsunah:BAAANQADCgYIBgAAAA==.',
Tu='Tuba:BAAANQAECgEIAQAAAA==.Turim:BAAANQAECgEIAgAAAA==.',
Ty='Tyrawick:BAAANQAECgYIBgAAAA==.Tyrlidd:BAABNQAECn8nAAIIAAgKNAgVqABHAQAIAAgKNAgVqABHAQAAAA==.',
Un='Unavoidable:BAAANQADCgMIAwAAAA==.Unlikelytale:BAABNQAECn8yAAMNAAoKcxzFKQC8AgANAAoKcxzFKQC8AgASAAEKRxbRJgFEAAAAAA==.',
Ur='Urbanmeyer:BAAANQAECgMIBQAAAA==.Uricash:BAABNQAECn9RAAIPAAoKjh/OGADaAgAPAAoKjh/OGADaAgAAAA==.Urrax:BAAANQADCgEIAQABNQADCgIIAgAJAAAAAA==.Urzual:BAABNQAECn8uAAMCAAkK6R2BDACoAgACAAkK6R2BDACoAgANAAYKbhSCigBvAQAAAA==.',
Ut='Utini:BAAANQAECgEIAQABNQAECgEIAQAJAAAAAA==.',
Va='Vandreynna:BAABNQAECn9IAAIEAAoKOyRbBgCQAwAEAAoKOyRbBgCQAwAAAA==.',
Ve='Vehlrine:BAAANQADCgIIAgAAAA==.Velsiana:BAAANQAECgMIAwAAAA==.Velveetah:BAAANQADCgYIBwABNQAECgUIFAAMANsTAA==.Venasia:BAAANQADCgYIBgABNQAECgoKSAAEADskAA==.Verbren:BAAANQAECgcICAABNQAECgoKMgAiALsUAA==.Verbrennen:BAABNQAECn8yAAIiAAoKuxQeGgAhAgAiAAoKuxQeGgAhAgAAAA==.Verita:BAAANQAECgQIBwAAAA==.Verlynne:BAAANQADCgcIBwAAAA==.Vetinari:BAAANQABCggIGwABNQAECgkJMQAFAMEVAA==.',
Vi='Viviann:BAABNQAECn85AAMiAAoKUgusEgC4AQAiAAoKUgusEgC4AQAeAAYKPAlEIwArAQAAAA==.',
Vo='Von:BAAANQADCgEIAQAAAA==.',
Wa='Walee:BAAANQADCgIIAgAAAA==.Walfred:BAAANQAECgQIBwABNQAECgkJTwAQALUYAA==.Warraxe:BAAANQADCgYIBwAAAA==.Waukeen:BAAANQAECgEIAQAAAA==.Wayloren:BAABNQAECn8qAAIBAAkKQAkx0gB3AQABAAkKQAkx0gB3AQAAAA==.Wayverly:BAAANQAECgEIAQABNQAECggIDwAJAAAAAA==.',
We='Wetboycaird:BAAANQADCgMIAwAAAA==.',
Wi='Wickathy:BAABNQAECn8xAAMGAAoKfCNwAQCTAwAGAAoKfCNwAQCTAwAEAAEKJgJgiwAXAAAAAA==.Wickcreu:BAAANQAECgQIBAAAAA==.',
Wo='Woodson:BAAANQADCggICAABNQAECgkJFgAGAOIOAA==.Worstdps:BAACNQAFFH8MAAIEAAQK3QSOEACtAAAEAAQK3QSOEACtAAA1AAQKf0oAAgQACgp0HNoPAKACAAQACgp0HNoPAKACAAAA.',
Wu='Wuldorr:BAACNQAFFH8JAAIBAAQKAAfYFQAAAQABAAQKAAfYFQAAAQA1AAQKfywAAgEACgqHEgxxANkBAAEACgqHEgxxANkBAAAA.',
Wy='Wynnifred:BAABNQAECn8bAAMiAAUK8RQ3HQAXAQAiAAUK8RQ3HQAXAQAeAAQKFgQ2HgBiAAAAAA==.',
Xa='Xaltheris:BAAANQAECgYICQAAAA==.',
Xe='Xenothor:BAAANQAECgEIAgAAAA==.Xethreal:BAABNQAECn8nAAINAAgKfRy+RABOAgANAAgKfRy+RABOAgAAAA==.',
Xy='Xype:BAAANQAECggICAAAAA==.',
Xz='Xzara:BAAANQAECgYICgAAAA==.',
Ya='Yaanu:BAAANQADCgMIAwAAAA==.',
Yu='Yura:BAAANQADCggICAAAAA==.',
Yv='Yvvee:BAAANQAECgMIBAAAAA==.',
Za='Zapbranigan:BAAANQADCggIDQAAAA==.Zasko:BAAANQAECggIDwAAAA==.',
Zi='Zifao:BAABNQAECn8vAAIPAAoKZCMTKQA/AwAPAAoKZCMTKQA/AwAAAA==.',
Zo='Zonora:BAABNQAECn8uAAIKAAoKzxGFRgDnAQAKAAoKzxGFRgDnAQAAAA==.',
['Äz']='Äzrael:BAABNQAECn8kAAIMAAkKrx0OJwCgAgAMAAkKrx0OJwCgAgAAAA==.',
['Çr']='Çréwüsæðèr:BAABNQAECn8dAAIbAAgKpR7dDgA+AgAbAAgKpR7dDgA+AgAAAA==.',
['Ðì']='Ðìaßlo:BAACNQAFFH8LAAIIAAQKlxPuEQBDAQAIAAQKlxPuEQBDAQA1AAQKf0gAAggACgrtIbESAPkCAAgACgrtIbESAPkCAAAA.',
['Òd']='Òdinn:BAAANQADCgcIBwAAAA==.',
['Ød']='Ødin:BAAANQADCggIFAABNQAECgYIFQAKAM4YAA==.',
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
