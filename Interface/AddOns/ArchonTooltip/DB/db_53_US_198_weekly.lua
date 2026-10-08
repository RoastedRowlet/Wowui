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

local lookup = {'Mage-Arcane','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Warrior-Fury','Shaman-Enhancement','DeathKnight-Frost','Hunter-Survival','Warrior-Arms','Warrior-Protection','Paladin-Protection','Druid-Guardian','Druid-Feral','Rogue-Subtlety','Shaman-Elemental','Hunter-Marksmanship','Priest-Discipline','Shaman-Restoration','Druid-Restoration','Druid-Balance','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','DeathKnight-Unholy','Rogue-Assassination','Mage-Frost','Warlock-Affliction',}
local provider = {region='US',realm='Skullcrusher',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Absolute:BAAANQAECggICAAAAA==.Abzclap:BAAANQAECgYIBgABNQAECgkJJAABAOAjAA==.Abzdh:BAAANQAECgMIAwABNQAECgkJJAABAOAjAA==.Abzlock:BAAANQAECgQICAABNQAECgkJJAABAOAjAA==.Abzmage:BAABNQAECoEkAAIBAAkK4CM9DgCWAwABAAkK4CM9DgCWAwAAAA==.Abzp:BAAANQAECgMIBQABNQAECgkJJAABAOAjAA==.Abzrogue:BAAANQAECgIIBAABNQAECgkJJAABAOAjAA==.Abzsh:BAAANQAECgQIBAAAAA==.',
Ac='Acoreüs:BAEBNQAECoEiAAICAAcKOw+chQCqAQACAAcKOw+chQCqAQAAAA==.',
Ad='Adramelk:BAAANQAECgIIBAABNQAECggIFwADALoaAA==.',
Ae='Aed:BAAANQABCgEIAQAAAA==.Aeiay:BAAANQAECgUICwAAAA==.',
Ai='Aibh:BAAANQADCgUIBwAAAA==.',
Al='Alastorias:BAAANQAECgIIAgAAAA==.Alethice:BAAANQADCgcIBwAAAA==.Alexandrap:BAAANQAECgIIAgAAAA==.Allmighto:BAECNQAFFIEZAAMDAAYKDB3TAwAsAgADAAYKDB3TAwAsAgAEAAEKGAUPLQBAAAA1AAQKgSoAAgMACQp9I00EAKYDAAMACQp9I00EAKYDAAAA.Alyssaxoo:BAABNQAECoEgAAMDAAkKtBPIPQBPAgADAAkKtBPIPQBPAgAEAAEKVAohgQEuAAAAAA==.',
An='Androstraz:BAAANQADCggICAAAAA==.Anjkh:BAAANQADCgYIBgAAAA==.Anniesthesia:BAAANQAECgUIBwAAAA==.Anoobyss:BAABNQAECoEVAAIFAAUKaQ6cQQAPAQAFAAUKaQ6cQQAPAQAAAA==.Anorexorcist:BAAANQABCgEIAQABNQAFFAIICAAGAMoOAA==.Anorxorcist:BAAANQAECgIIAgABNQAFFAIICAAGAMoOAA==.Anorxxorcist:BAACNQAFFIEIAAIGAAIKyg7eHwBsAAAGAAIKyg7eHwBsAAA1AAQKgRsAAgYACQpIEi8/AOMBAAYACQpIEi8/AOMBAAAA.Ansky:BAAANQADCggICAAAAA==.Anthraxx:BAAANQADCggJDwABNQAECgYIEwAHAAAAAA==.Anyone:BAAANQAECgUICgABNQAECgYIEwAHAAAAAA==.',
Ap='Aporkchop:BAAANQAECgEIAgAAAA==.Applebottom:BAABNQAECoElAAIIAAkK5iHCFgAoAwAIAAkK5iHCFgAoAwAAAA==.',
Ar='Archenemyy:BAAANQAECgYIDgAAAA==.Arda:BAABNQAECoEkAAIIAAgKqiGsHgABAwAIAAgKqiGsHgABAwAAAA==.Arelina:BAAANQAECgIIBAAAAA==.Arune:BAAANQAECgYICQAAAA==.',
As='Aspyrx:BAABNQAECoEfAAIGAAgKyRF+RADKAQAGAAgKyRF+RADKAQAAAA==.Assol:BAAANQADCgUIDgAAAA==.Astelan:BAEBNQAECoEoAAIJAAkK3SD6BgBZAwAJAAkK3SD6BgBZAwAAAA==.Astärea:BAABNQAECoEYAAMKAAcKNg7dEQBfAQAKAAcKNg7dEQBfAQALAAYKnQZ+UQAUAQAAAA==.',
Au='Aurorä:BAAANQAECgYIDQAAAA==.',
Ay='Ayeola:BAAANQADCgEIAQAAAA==.',
Az='Aztëk:BAAANQAECgIIAgAAAA==.',
Ba='Bachaterah:BAAANQADCgEIAQAAAA==.Baddawg:BAAANQAECgEIAgABNQAECgkJJgABAMMWAA==.Baeldaeg:BAAANQAECgYICwAAAA==.Bahahahamut:BAABNQAECoEYAAIMAAkKMBnGIQDLAgAMAAkKMBnGIQDLAgABNQAECgYICwAHAAAAAA==.Bannett:BAAANQAECgUIBwAAAA==.Baoboi:BAAANQADCgQIBAAAAA==.Bashing:BAAANQAECgYIBgABNQAECgkJIwAGAE8cAA==.Bauce:BAAANQADCgQIBAAAAA==.Baxterevo:BAAANQAECgYIDQAAAA==.Baybx:BAAANQABCgUIBgAAAA==.',
Be='Beardgrim:BAAANQADCggICAAAAA==.Beefyweefy:BAAANQADCggIDQABNQAECgcIDgAHAAAAAA==.Bella:BAAANQAECgUIEQAAAA==.',
Bi='Bianchi:BAAANQAECggIDwAAAA==.Bibleman:BAAANQADCggICAAAAA==.Biddy:BAAANQADCgYIBgAAAA==.Bienfrosty:BAAANQAECgUIBQAAAA==.Bigbowlp:BAEANQAECgQIBAABNQAFFAcIGAANANklAA==.Bigchungus:BAAANQADCgYIBgAAAA==.Bigguns:BAAANQAECgEJAQAAAA==.Bigmonk:BAAANQADCgIIAgAAAA==.Bigpumpa:BAAANQAECgQICAAAAA==.Billygoatgrf:BAAANQAECgcIEgAAAA==.',
Bl='Blackvomit:BAAANQAECgIIAgAAAA==.Blakkbeard:BAABNQAECoEkAAIOAAkKBSCkBgALAwAOAAkKBSCkBgALAwAAAA==.Blazefort:BAABNQAFFIEFAAIPAAQKrwrECAAQAQAPAAQKrwrECAAQAQAAAA==.Blightmommie:BAAANQAECgUIBgAAAA==.Blitzeye:BAABNQAECoElAAIQAAgK3BZQBAB/AgAQAAgK3BZQBAB/AgAAAA==.Bludskal:BAAANQADCgYIBgABNQAECgkJIwAGAE8cAA==.Bløod:BAAANQABCgUIBQAAAA==.',
Bo='Bolger:BAAANQADCgMIAwAAAA==.Bonix:BAAANQADCgIIBAAAAA==.Boosteddots:BAAANQAECgEIAQAAAA==.Boozeftw:BAAANQADCgUIBQAAAA==.Bowjobdamage:BAAANQADCgMIAwAAAA==.',
Br='Braincell:BAAANQAECgUIEgABNQAECgYICwAHAAAAAA==.Breemonic:BAAANQAECggIEwAAAA==.Brewdie:BAAANQADCgUIBgAAAA==.Britannican:BAAANQAECgEIAQAAAA==.Brrooks:BAAANQADCggICAAAAA==.Bruce:BAACNQAFFIEIAAMNAAUKuR1bAADzAQANAAUKuR1bAADzAQARAAEK/RmmMgBMAAA1AAQKgR8ABBIACQqjHnkQAPIBABEACQrXG7FSAHYCABIACAqCFnkQAPIBAA0ABAr5HSkQAH8BAAAA.',
Bu='Bubblekush:BAAANQAECgIIAgAAAA==.Bubbleøseven:BAAANQADCgQIBAAAAA==.Bullshifter:BAAANQAECgQIBAAAAA==.Bullshoc:BAAANQADCgIIAgAAAA==.Burgleslight:BAAANQABCgEIAQAAAA==.Butturz:BAAANQAECgQICwAAAA==.',
['Bø']='Bønecrusher:BAAANQABCgEIAQAAAA==.',
Ca='Cabala:BAAANQAECgIIAgAAAA==.Cailleach:BAAANQAECgIJAgAAAA==.Cainz:BAAANQAECgYICgAAAA==.',
Ce='Celeryman:BAABNQAECoEXAAQEAAcKJRuUfgD8AQAEAAcKJRuUfgD8AQADAAMKWQUY4wCIAAATAAIKPQv5WABPAAAAAA==.Centuro:BAAANQAECgEIAQAAAA==.',
Ch='Chobi:BAABNQAECoEaAAMUAAkKDyV7AQC+AwAUAAkKDyV7AQC+AwAVAAEKcRxLLwBVAAAAAA==.',
Ci='Cinnamen:BAABNQAECoEfAAIWAAgK0h2XCgC+AgAWAAgK0h2XCgC+AgAAAA==.',
Cl='Claudine:BAAANQAECgUIDwABNQAECgcIEQAHAAAAAA==.Clearstoned:BAAANQADCgUIBQABNQAECgkJKAABAAwfAA==.',
Co='Coaa:BAAANQAECgYIEQAAAA==.Colossus:BAAANQAECgUIEAAAAA==.Contrap:BAABNQAECoEiAAIIAAgKwBvvRgBxAgAIAAgKwBvvRgBxAgAAAA==.Coolbreeze:BAAANQAECgYIDgAAAA==.Corpsgrinder:BAAANQAFFAEIAwAAAA==.',
Cr='Crashöut:BAAANQADCgIIAgAAAA==.Crysix:BAAANQABCgQIBAAAAA==.',
Cz='Cz:BAAANQADCgQIBAAAAA==.Czera:BAAANQADCgMIAwAAAA==.',
Da='Dahialkahina:BAAANQAECgQIBQAAAA==.Damagenpayne:BAAANQABCgEIAQAAAA==.Darkmeadow:BAAANQAECgUIDgAAAA==.Dastard:BAABNQAECoEeAAIXAAkK2hp8JwDEAgAXAAkK2hp8JwDEAgAAAA==.',
De='Deadlock:BAAANQAECgEIAgAAAA==.Deadplank:BAAANQAECgYIEQAAAA==.Deathlyfrost:BAAANQADCggICAAAAA==.Deftonia:BAAANQAECgcIDQAAAA==.Degenerate:BAAANQADCgYICAAAAA==.Dementïa:BAABNQAECoEeAAMIAAgKph1JOACfAgAIAAgKph1JOACfAgAYAAEKsAESiQAjAAAAAA==.Demonbläde:BAAANQAECgUIBQAAAA==.Dethany:BAAANQAECgUIDQABNQAECgcIEQAHAAAAAA==.Devondric:BAABNQAECoEtAAMMAAgKrx+xIQDLAgAMAAgKrx+xIQDLAgAZAAEKeQZaKgApAAAAAA==.Devotion:BAAANQADCgUIBQABNQAFFAQICwADAGYSAA==.Devotional:BAACNQAFFIELAAIDAAQKZhI5DgBGAQADAAQKZhI5DgBGAQA1AAQKgTEAAwMACQpUHkIUAB8DAAMACQpUHkIUAB8DAAQAAwqDEcUbAbgAAAAA.',
Di='Diekuh:BAAANQAECgEIAQAAAA==.Diivinity:BAAANQADCggICAABNQAECgkJJAAEADcYAA==.Dimepiece:BAAANQADCgUIBwAAAA==.Dithi:BAAANQADCgQIBAAAAA==.Divinaputits:BAAANQAECgcJCgAAAA==.',
Dm='Dmatch:BAAANQAECgYIDAAAAA==.',
Do='Docholigay:BAAANQAECgIIAgAAAA==.Dojoh:BAAANQADCgMIAwAAAA==.Dommiemommie:BAAANQAECgQICgABNQAECgUIBgAHAAAAAA==.Doozpal:BAABNQAECoEtAAIDAAkKVBYgKwChAgADAAkKVBYgKwChAgAAAA==.Dorinspins:BAEBNQAECoEeAAIRAAkKEhlDRQChAgARAAkKEhlDRQChAgAAAA==.Downset:BAAANQADCgcIBwABNQAECgkJJgABAMMWAA==.',
Dr='Drakonman:BAAANQAECgIIAgAAAA==.Draynen:BAABNQAECoEkAAMOAAkKoh/lBAA3AwAOAAkKoh/lBAA3AwAaAAIKfAtC5gBuAAABNQAFFAMIAwAHAAAAAA==.Drbanner:BAAANQADCgUIBQAAAA==.Drboom:BAAANQAECgUIBwAAAA==.Drezd:BAABNQAECoEuAAIYAAkKbw/7IwANAgAYAAkKbw/7IwANAgAAAA==.',
Du='Duck:BAAANQADCgcIFAABNQAECgMIBAAHAAAAAA==.Duckduck:BAAANQABCgIIAgABNQAECgMIBAAHAAAAAA==.Dulcïnea:BAAANQAECgEIAQABNQAECggIHgAIAKYdAA==.Dumpymilk:BAAANQADCggIGQABNQAECgYICwAHAAAAAA==.',
Ea='Eao:BAABNQAECoEkAAIIAAgKAgydcwD7AQAIAAgKAgydcwD7AQAAAA==.',
Ed='Edrana:BAAANQADCgYIBgABNQAECgIIAgAHAAAAAA==.',
Eh='Ehvyn:BAAANQADCggICgABNQAECgQICAAHAAAAAA==.',
El='Elblaize:BAAANQABCgUIBQAAAA==.Elitistjerk:BAAANQADCgEIAQAAAA==.Ellisis:BAAANQAECgYIDwAAAA==.',
Em='Emriq:BAABNQAECoEcAAIEAAcKRRgOggDzAQAEAAcKRRgOggDzAQAAAA==.',
En='Enmai:BAABNQAECoEbAAICAAcKywyjkQCLAQACAAcKywyjkQCLAQAAAA==.',
Ep='Epiphany:BAAANQAECgcIEQAAAA==.',
Er='Eraylina:BAAANQAECgYIEwAAAA==.Ertivoker:BAAANQADCggICAABNQAECgcIEgAHAAAAAA==.',
Eu='Eugima:BAAANQADCgUIBQAAAA==.Eulogy:BAABNQAECoEkAAIJAAgKPBubFgCCAgAJAAgKPBubFgCCAgAAAA==.',
Ev='Evangelise:BAAANQADCgEIAQAAAA==.Eveille:BAAANQABCgIIAgAAAA==.',
Ex='Exxitus:BAAANQAECgUIBwAAAA==.',
Fa='Faerielana:BAEANQAECgcIDQABNQAECggIGQAbAKEWAA==.Faith:BAAANQAECgMIBgAAAA==.Falsoqt:BAAANQAECgYIDgAAAA==.Fatblackcow:BAAANQADCgEIAQAAAA==.Fatgum:BAEANQADCgQIBAABNQAFFAYIGQADAAwdAA==.',
Fe='Fecalmatters:BAAANQAECgEIAQAAAA==.Felachio:BAABNQAECoEeAAIIAAcKihqNYgAmAgAIAAcKihqNYgAmAgAAAA==.',
Fj='Fjörgyn:BAACNQAFFIEYAAIXAAcKRh+0AADVAgAXAAcKRh+0AADVAgA1AAQKgSUAAhcACQrWI2gLAIADABcACQrWI2gLAIADAAAA.',
Fl='Flankster:BAAANQAECgMIBQAAAA==.Flanksterr:BAAANQAECgQIBwAAAA==.',
Fo='Fork:BAABNQAECoEmAAIPAAkK+CS0AgCvAwAPAAkK+CS0AgCvAwAAAA==.Forsetí:BAAANQAECgEIAQAAAA==.Fozziedaburr:BAABNQAECoEjAAMbAAkKcx6hCwD2AgAbAAkKcx6hCwD2AgAcAAUKixSSVwBNAQAAAA==.',
Fr='Frasierkrane:BAAANQADCgQIBwAAAA==.Frontmage:BAABNQAECoEWAAIBAAgKNB1+XgCvAgABAAgKNB1+XgCvAgAAAA==.',
Ft='Ftfk:BAAANQADCggIFgABNQAECggIHQAdAOAfAA==.',
Ga='Galie:BAABNQAECoEhAAMcAAkK8RH0LwA8AgAcAAkK8RH0LwA8AgAUAAUK0wtFMADRAAAAAA==.Galiè:BAAANQADCgUICwAAAA==.Garrahoth:BAAANQAECgcIDgAAAA==.',
Ge='Gekk:BAABNQAECoEfAAMdAAgKTQv5IACpAQAdAAgKTQv5IACpAQAeAAUK+gqTJAD7AAAAAA==.',
Gi='Giaus:BAABNQAECoEeAAIBAAgKgByKbQCOAgABAAgKgByKbQCOAgAAAA==.Girby:BAAANQADCgcIBwAAAA==.',
Gl='Glaaive:BAAANQADCgEIAQAAAA==.Glimmerwisp:BAABNQAECoEZAAIBAAgK9QkZ0gC8AQABAAgK9QkZ0gC8AQAAAA==.',
Go='Gobzilla:BAABNQAECoEWAAIaAAgKWBEBYwC1AQAaAAgKWBEBYwC1AQAAAA==.Gonn:BAAANQADCgUIBQAAAA==.Goub:BAAANQAECgUIDQAAAA==.',
Gr='Grapefantuh:BAAANQAECgMIBQAAAA==.Grapeinator:BAAANQAECgYIEQAAAA==.Grasseater:BAAANQADCgYIBgABNQAFFAIIBQADALYYAA==.Grimreapr:BAAANQAECgIIAwAAAA==.Grimrieber:BAABNQAECoEcAAMSAAkKCBrODAA7AgASAAgKDhrODAA7AgARAAEK1xlzJQFNAAAAAA==.Gromn:BAABNQAECoEtAAIQAAkKdh+WAQBDAwAQAAkKdh+WAQBDAwAAAA==.',
Ha='Hanb:BAAANQADCggIDAABNQAECgIIAgAHAAAAAA==.Happywoodz:BAAANQAECgEIAQABNQAECgcIGAAaAC4jAA==.Hashed:BAABNQAECoEVAAIEAAgKTh1GQwClAgAEAAgKTh1GQwClAgAAAA==.Hays:BAAANQAECgcICwAAAA==.Haysevoker:BAACNQAFFIETAAQfAAYKTRWvBgC0AAAfAAIKnRuvBgC0AAAdAAIKmw6SEQCTAAAeAAIKcRZ2CgCTAAA1AAQKgSAABB8ACQpUHZwFAGACAB8ACAr0HpwFAGACAB4ACAoZElAXALQBAB0AAwrEDd83ALgAAAAA.',
He='Heebb:BAAANQADCggICAAAAA==.Henn:BAAANQAECgIIAgAAAA==.',
Ho='Hobb:BAAANQADCgUIBQAAAA==.Holemilk:BAAANQADCggIEAAAAA==.Holycopter:BAAANQADCggIGgAAAA==.Holymojo:BAABNQAECoEXAAMMAAgKqyI2EgAjAwAMAAgKqyI2EgAjAwAZAAEKOQ+gJAA3AAAAAA==.Hoodler:BAECNQAFFIELAAIbAAYKUB09AgAdAgAbAAYKUB09AgAdAgA1AAQKgS0AAhsACQrPJcQBAK8DABsACQrPJcQBAK8DAAAA.Hoodlery:BAECNQAFFIEKAAIgAAUKbyHPAgDLAQAgAAUKbyHPAgDLAQA1AAQKgR0AAiAACQpTHqcHAPwCACAACQpTHqcHAPwCAAE1AAUUBggLABsAUB0A.Hoofjob:BAACNQAFFIELAAIhAAYKVAvdBACvAQAhAAYKVAvdBACvAQA1AAQKgSUAAiEACQrIHZ0VAH0CACEACQrIHZ0VAH0CAAAA.',
Hu='Huskydots:BAABNQAECoEjAAMCAAkKkBXsXAAfAgACAAgKhRXsXAAfAgAiAAMKKw6hRACoAAAAAA==.',
['Hé']='Hércules:BAAANQADCgIIAgAAAA==.',
Ia='Iaell:BAAANQADCgIIAgABNQAECgcIHgAIAIoaAA==.',
Ib='Iblastpants:BAAANQAECgUICwAAAA==.',
Id='Idd:BAAANQAECgIIAgAAAA==.',
Ig='Iggyy:BAAANQAECgUIEQAAAA==.',
Im='Imshaman:BAAANQAECgEIAQAAAA==.',
In='Inflammo:BAAANQABCgIIAgAAAA==.Insaneness:BAAANQAECgUICQAAAA==.',
Ir='Irila:BAAANQAECgMJBAAAAA==.',
It='Ithrein:BAAANQADCgYICwAAAA==.Its:BAAANQAECgUIDQABNQAECgYIEwAHAAAAAA==.',
Iz='Izumî:BAAANQADCggJEwAAAA==.',
Ja='Jackdáripper:BAAANQABCgYIBgAAAA==.Jakè:BAAANQAECgIIAgAAAA==.Jangosan:BAAANQAECgIIAgABNQAECgkJHQAWAF0OAA==.Jaslen:BAAANQADCgYIBgAAAA==.Jasono:BAAANQADCgYICgAAAA==.Jaspy:BAABNQAECoEkAAIUAAgKWRxiCwB6AgAUAAgKWRxiCwB6AgAAAA==.',
Je='Jeffdennis:BAABNQAECoEZAAIRAAkKLxNfaAA3AgARAAkKLxNfaAA3AgAAAA==.',
Ji='Jimmybuffler:BAABNQAECoEXAAIDAAgKBRvqMQCCAgADAAgKBRvqMQCCAgAAAA==.',
Jo='Jomgpallie:BAAANQAECgcIEwAAAA==.Jonra:BAAANQADCgMIBAAAAA==.Josefbugman:BAAANQAECgQIBgAAAA==.',
Ju='Judykiki:BAAANQAECgQIBQABNQAECgUIDwAHAAAAAA==.Juecy:BAAANQAECgcIBwAAAA==.Juju:BAAANQAECgYIDQAAAA==.Juktal:BAAANQAECgYIDgAAAA==.Justyn:BAAANQAECgYIEQAAAA==.',
Ka='Kaeden:BAAANQADCgQJBAAAAA==.Kahlán:BAAANQABCgcICQAAAA==.Kainz:BAAANQAECgIIAwAAAA==.Kaoscontrol:BAAANQADCgUIDgAAAA==.Kazaju:BAABNQAECoEZAAMiAAkKEh/UKgAaAQACAAYKmR0YcgDhAQAiAAMKBSLUKgAaAQAAAA==.',
Ki='Kialorstus:BAABNQAECoEgAAQPAAgKAhhNJwAqAgAPAAgKAhhNJwAqAgAjAAQKUQrFlgCwAAAGAAEK5gQkwgAqAAAAAA==.Kinzington:BAAANQAECgUIBAABNQAECgkJJgABAMMWAA==.Kirbo:BAAANQAECgQICAAAAA==.Kitagawa:BAABNQAECoEjAAIGAAkKTxzsGADPAgAGAAkKTxzsGADPAgAAAA==.Kitten:BAAANQAECgYIDwAAAA==.',
Kl='Klondikecow:BAAANQABCgMIBAAAAA==.',
Ko='Kolakua:BAAANQADCgQIBAAAAA==.Korianth:BAAANQAECgUIBwAAAA==.Korlon:BAAANQADCgYICwAAAA==.Kouw:BAAANQAECgcIEQAAAA==.',
Kr='Kradyn:BAAANQAECgUJBgAAAA==.Kragfoerend:BAABNQAECoEYAAIRAAcK+wKC3AD7AAARAAcK+wKC3AD7AAAAAA==.Kramx:BAAANQAECgMIAwAAAA==.Krankenstein:BAABNQAECoEfAAIGAAgK5hi8LQBCAgAGAAgK5hi8LQBCAgAAAA==.Krankson:BAAANQADCgIIAgAAAA==.Kriix:BAABNQAECoEWAAIkAAYKwyPpHgBfAgAkAAYKwyPpHgBfAgAAAA==.Krusnik:BAAANQADCgUICAAAAA==.Kruurk:BAAANQADCgQIBAAAAA==.',
Ks='Ksubii:BAAANQAECgYIBwAAAA==.',
Ku='Kuhtta:BAAANQAECgUIDAAAAA==.Kumdobeast:BAAANQAECgQIDQAAAA==.Kuothe:BAAANQAECgUIDwAAAA==.',
Ky='Kyina:BAAANQADCgcIBwAAAA==.Kyotpal:BAAANQADCgYIDAAAAA==.Kyotsas:BAAANQAECggIBAAAAA==.',
La='Lazyriver:BAAANQAECgUIEAABNQADCgUIJwAHAAAAAA==.',
Le='Legoland:BAAANQAECggIAQAAAA==.Leonphelps:BAAANQADCgYIBwAAAA==.Lesnichii:BAABNQAECoEWAAIcAAcKRRCIRQCtAQAcAAcKRRCIRQCtAQAAAA==.Lewakex:BAAANQAECggIEQAAAA==.Leyninade:BAAANQAECgYIEgAAAA==.',
Li='Lightbrngr:BAABNQAECoEiAAIEAAkKgRwINgDUAgAEAAkKgRwINgDUAgAAAA==.Lihuai:BAAANQADCggIDAAAAA==.Liilpeep:BAAANQAECggICwAAAA==.Lilbertha:BAAANQAECgIIAgAAAA==.Lilchigirl:BAAANQADCgYIBgAAAA==.Lildipster:BAAANQADCggIGAABNQAECgYICwAHAAAAAA==.Lildump:BAAANQAECgYICwABNQAECggIDgAHAAAAAA==.Limitlessone:BAABNQAECoEVAAIBAAYKUx7VsQD9AQABAAYKUx7VsQD9AQAAAA==.Lionescanor:BAAANQADCgEIAQAAAA==.Liptonaysti:BAAANQAECgQIBwAAAA==.Lissandine:BAABNQAECoEgAAMKAAkKrhRHCQAnAgAKAAkKrhRHCQAnAgALAAUKQQQSYgDAAAAAAA==.Liya:BAAANQAECgEIAgABNQAFFAQICAAGALwfAA==.Lizzywizzy:BAAANQADCgYIBgABNQAECgYICwAHAAAAAA==.',
Lo='Locrian:BAAANQABCgQIBAAAAA==.Lokikillz:BAAANQAECgYIDAAAAA==.Lotharn:BAAANQADCgMIAQAAAA==.Lowdy:BAABNQAECoEjAAMRAAgKXRP3dQASAgARAAgKoRL3dQASAgANAAIK5xe9IQB+AAAAAA==.',
Lu='Luulk:BAAANQAECgUIDwAAAA==.',
Ly='Lych:BAAANQAECgQIBgAAAA==.Lyclaw:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìllith:BAAANQAECgYIDgAAAA==.Lìvíd:BAAANQADCgIIAgAAAA==.',
Ma='Madoris:BAAANQAECgUIDQAAAA==.Magemagerson:BAABNQAECoEXAAIBAAgKdSDkZACgAgABAAgKdSDkZACgAgAAAA==.Magnuss:BAAANQAECggIDwAAAA==.Mahini:BAAANQADCgYIBgAAAA==.Mahnion:BAAANQADCggICAAAAA==.Malleus:BAAANQAECgYIDwAAAA==.Mammutos:BAAANQAECgYIEQAAAA==.Manifred:BAAANQADCgYIEAAAAA==.Manion:BAABNQAECoEkAAMaAAgKyCDAGQDvAgAaAAgKyCDAGQDvAgAXAAYK6xNkeQCGAQAAAA==.Manipepper:BAAANQAECgYIEgAAAA==.Manippiez:BAAANQAECgMIBAAAAA==.Manipulation:BAAANQADCggICgAAAA==.Mannarchy:BAAANQADCgQIBAAAAA==.Mantrà:BAAANQADCggIFAAAAA==.Maplemaga:BAAANQAECggIDAAAAA==.Margot:BAAANQADCgYIDAABNQAECgIIAgAHAAAAAA==.Masochista:BAACNQAFFIEIAAIGAAQKvB9GCwB1AQAGAAQKvB9GCwB1AQA1AAQKgRgAAgYACQpXJQEGAIsDAAYACQpXJQEGAIsDAAAA.Mastric:BAEBNQAECoEjAAICAAgKkQZOmAB5AQACAAgKkQZOmAB5AQAAAA==.',
Mc='Mccaffrey:BAABNQAECoEfAAIRAAgKLRZkcQAfAgARAAgKLRZkcQAfAgAAAA==.',
Me='Meetch:BAABNQAECoEfAAIjAAgKih0nJgCEAgAjAAgKih0nJgCEAgAAAA==.Megdar:BAAANQAECgYIEgAAAA==.Melledreu:BAABNQAECoFYAAMlAAkKZQwjDgCdAQABAAkKsQS94QCeAQAlAAkKDAwjDgCdAQAAAA==.Mellessan:BAAANQADCggICAAAAA==.Merix:BAABNQAECoEmAAMkAAkKsR1lNwC6AQAkAAUK8h9lNwC6AQAWAAUK3xo9IwCbAQAAAA==.Mestea:BAAANQAECgYIDgAAAA==.Mewing:BAAANQAECgQIBAABNQAECggIHwAEAI4iAA==.',
Mi='Miraclemill:BAAANQADCgcIFQAAAA==.Mirra:BAAANQAECgUIEQAAAA==.',
Mo='Mojobtw:BAAANQADCgcIBwAAAA==.Momoshirow:BAAANQADCgQIBwAAAA==.Momø:BAAANQADCgUJBQAAAA==.Monsterboy:BAAANQADCgIIAgAAAA==.Mortamur:BAABNQAECoEbAAIBAAgKehdnmgAuAgABAAgKehdnmgAuAgAAAA==.Mortelinnos:BAABNQAECoEkAAILAAgKpSTSCwA4AwALAAgKpSTSCwA4AwAAAA==.',
My='Mysticguru:BAABNQAECoEcAAIaAAYKVh18XQDIAQAaAAYKVh18XQDIAQAAAA==.Mythrax:BAABNQAECoEeAAMQAAkKtRtnAgD9AgAQAAkKtRtnAgD9AgAYAAIKxweiaABlAAAAAA==.',
Na='Naradrae:BAAANQAECgQICAAAAA==.Narodaran:BAAANQAECggIAwAAAA==.Naughtyrawr:BAAANQAECgUIDAAAAA==.',
Ne='Necropete:BAAANQAECgIIAgABNQAFFAEIAQAHAAAAAA==.Neondemon:BAAANQAECgEIAQAAAA==.Nevets:BAABNQAECoElAAIYAAkK7x/oCAA2AwAYAAkK7x/oCAA2AwAAAA==.Nevrs:BAAANQAECgUICwAAAA==.Newworld:BAAANQADCgUIEAAAAA==.',
Ni='Nikolajokic:BAAANQAECgEIAQAAAA==.Nimit:BAABNQAECoEbAAIIAAgKpho9RQB2AgAIAAgKpho9RQB2AgAAAA==.',
No='Noughtsee:BAAANQAECgQIDQAAAA==.Novic:BAABNQAECoEfAAIMAAgKChMTYwDEAQAMAAgKChMTYwDEAQAAAA==.Noxinox:BAAANQADCgYIBwAAAA==.Nozom:BAAANQADCgEIAQABNQAECgcIDgAHAAAAAA==.',
Nu='Nualia:BAABNQAECoEYAAIEAAgKsBy9TgCBAgAEAAgKsBy9TgCBAgAAAA==.',
['Né']='Némésis:BAAANQAECgMIBwAAAA==.',
Oc='Oceaná:BAAANQADCggICAAAAA==.',
Oj='Ojacks:BAAANQAECgMIAwAAAA==.Ojaks:BAAANQAECgcIEwAAAA==.',
Op='Operendi:BAAANQADCgYIBgAAAA==.',
Or='Orbian:BAAANQADCgcIBwAAAA==.Orobus:BAABNQAECoEXAAMNAAkKSR4xBQCpAgANAAgKHh4xBQCpAgASAAEKoB8fNQBUAAAAAA==.',
Os='Oscassey:BAABNQAECoEfAAIkAAgKBAseNQDJAQAkAAgKBAseNQDJAQAAAA==.',
Ox='Oxley:BAABNQAECoEaAAIVAAgKYhoJCQCJAgAVAAgKYhoJCQCJAgAAAA==.',
Pa='Paladingus:BAABNQAECoEaAAMEAAcKKR7YhgDmAQAEAAcKjxrYhgDmAQATAAQKGyCiKABsAQAAAA==.Pandidin:BAABNQAECoEhAAMgAAgKcRaZFAAGAgAgAAgKcRaZFAAGAgAhAAIKOg9ZVABhAAAAAA==.Pauldrons:BAACNQAFFIEGAAMjAAIKzgn8FgCGAAAjAAIKzgn8FgCGAAAPAAEKowJdGgA6AAA1AAQKgUYAAyMACQpbE3E6ABQCACMACQpUE3E6ABQCAA8ABwpkBvZOAC0BAAAA.',
Pe='Peenar:BAABNQAECoEZAAMYAAgKciFfFACmAgAYAAcK+yFfFACmAgAIAAIK0SC7AgG+AAAAAA==.Peenpikmin:BAAANQADCgQJBAAAAA==.Pejorative:BAAANQADCgYIBgAAAA==.',
Ph='Pharlock:BAAANQAECgYIEAAAAA==.Pharlòck:BAAANQADCgUIBgABNQAECgYIEAAHAAAAAA==.Phobia:BAAANQADCggICAABNQAECggIJAAJADwbAA==.',
Pi='Picklelips:BAAANQADCgQIBQAAAA==.',
Pl='Plankie:BAAANQADCgUICAAAAA==.Plankreaver:BAAANQADCgIIAgAAAA==.Planks:BAAANQAECgIIAgAAAA==.Plankz:BAAANQADCgMIAwAAAA==.',
Po='Pooterdiddle:BAAANQAECgUIBgAAAA==.',
Pr='Priesttess:BAAANQADCgcICgAAAA==.Prohealin:BAABNQAECoEdAAIMAAgK+gURegBzAQAMAAgK+gURegBzAQAAAA==.',
Ps='Psarahdactyl:BAAANQADCgIIAgAAAA==.',
Pt='Ptiteagacee:BAABNQAECoEXAAQJAAcK/xroKwCeAQAJAAUKtBvoKwCeAQAZAAUKhBanDABXAQAMAAQK7A9xmwAHAQAAAA==.',
Pu='Pufdaddy:BAAANQAECgUIDQAAAA==.Puffymüffins:BAAANQADCgIIAgABNQAECgEIEwAHAAAAAA==.Pumpkinq:BAABNQAECoE9AAMWAAkKmCK5AgB9AwAWAAkKiyK5AgB9AwAkAAQKWxS8VAAaAQAAAA==.',
Py='Pyre:BAAANQABCgIJAgAAAA==.',
['Pì']='Pìkachu:BAABNQAECoEjAAMBAAgKZx7NWQC6AgABAAgKUB7NWQC6AgAlAAMKphyDHwDLAAAAAA==.',
Ra='Raby:BAAANQADCgYIBgAAAA==.Ragemommie:BAAANQAECgMIBAABNQAECgUIBgAHAAAAAA==.Rainer:BAAANQAECgEIAQAAAA==.Rasmus:BAABNQAECoEYAAITAAgKWxRVGwDpAQATAAgKWxRVGwDpAQAAAA==.Raykwan:BAAANQADCgUIBQAAAA==.Rayquaza:BAABNQAECoEdAAIdAAgK4B+sCwDZAgAdAAgK4B+sCwDZAgAAAA==.Razzahola:BAAANQADCgIIAgABNQAECgQIBAAHAAAAAA==.Razzmatazz:BAABNQAECoEdAAIBAAgK/xcPiABVAgABAAgK/xcPiABVAgAAAA==.',
Re='Reddeyes:BAAANQAECgYIEQAAAA==.Regulüs:BAAANQAECgcICgAAAA==.Rescue:BAABNQAECoEmAAIBAAkKwxb5ZQCeAgABAAkKwxb5ZQCeAgAAAA==.Reva:BAEANQAECgcICAABNQAECgkJKAAJAN0gAA==.',
Ri='Rising:BAAANQADCggIDgAAAA==.',
Ro='Roamin:BAAANQADCggJCAAAAA==.Roasted:BAABNQAECoEjAAIBAAkKIRl/WgC4AgABAAkKIRl/WgC4AgAAAA==.Rockma:BAAANQAECggIAQAAAA==.Rollandburn:BAAANQAECgQIDwAAAA==.Romantacykmc:BAAANQADCgUICAAAAA==.Roxymigurdia:BAABNQAECoEXAAIIAAgKsCSiFAA0AwAIAAgKsCSiFAA0AwAAAA==.',
Ru='Rufföaddy:BAABNQAECoEkAAIDAAgKniJ9FAAeAwADAAgKniJ9FAAeAwAAAA==.Rumproast:BAAANQAECgEIAQABNQAECgcIDgAHAAAAAA==.Runeesa:BAAANQAECgYIDwAAAA==.',
Ry='Rylena:BAABNQAECoEbAAMIAAcKFiHIPACQAgAIAAcKFiHIPACQAgAYAAUKjw7LRAD/AAAAAA==.Ryuke:BAAANQADCggICAAAAA==.Ryvalry:BAAANQABCgIIAgAAAA==.',
['Rà']='Ràvenn:BAAANQABCgIIAgABNQAECgUICAAHAAAAAA==.',
['Râ']='Râmên:BAAANQADCgEIAQAAAA==.',
Sa='Sagikos:BAEBNQAECoEZAAMbAAgKoRZNHQAdAgAbAAgKoRZNHQAdAgAcAAEKFAnlnAA7AAAAAA==.Sardras:BAABNQAECoEkAAIbAAgKrSQ4BgBMAwAbAAgKrSQ4BgBMAwAAAA==.Sark:BAAANQAECgYIBwAAAA==.Sathor:BAAANQAECgUICgAAAA==.Sauccyy:BAAANQAECgQIBQAAAA==.Saucecity:BAAANQAECgQIBAAAAA==.Saucyjenkins:BAAANQAECgQICQAAAA==.',
Sc='Scranton:BAAANQADCgcICQAAAA==.',
Se='Sean:BAAANQADCgYICwAAAA==.Selest:BAAANQADCgEIAQAAAA==.Sellout:BAAANQAECgEJAQAAAA==.Semprefi:BAAANQADCgcIBwAAAA==.',
Sh='Shaani:BAAANQAECgEIAQAAAA==.Shace:BAAANQAECggICAAAAA==.Shadowfoot:BAAANQADCgUIBQAAAA==.Shadowhut:BAAANQADCgQIBAAAAA==.Shalanot:BAEANQAECgUICgABNQAECggIGQAbAKEWAA==.Shamerific:BAAANQADCgcIBwAAAA==.Shamlus:BAAANQAECgEIAQABNQAECgYIEgAHAAAAAA==.Shammooz:BAABNQAECoFaAAIOAAkKSB+hBABAAwAOAAkKSB+hBABAAwAAAA==.Shinier:BAABNQAECoEnAAIDAAkKjSOnAwCvAwADAAkKjSOnAwCvAwAAAA==.Shockwoods:BAABNQAECoEYAAMaAAcKLiP1IwC3AgAaAAcKLiP1IwC3AgAXAAIK7A7A7gB0AAAAAA==.Shondo:BAAANQAECgYIBgAAAA==.',
Si='Silversmage:BAAANQAECgUIBwAAAA==.Simohayha:BAAANQADCgIIAgAAAA==.Sixseven:BAAANQAECgUJBQAAAA==.',
Sk='Skeeboo:BAAANQABCgYIBgAAAA==.Skülly:BAAANQAECgQIBAAAAA==.',
Sl='Slappywappy:BAABNQAECoEbAAIBAAYKth68rQAFAgABAAYKth68rQAFAgAAAA==.',
Sm='Smorcin:BAABNQAECoEZAAIRAAgK7x+sRACjAgARAAgK7x+sRACjAgAAAA==.',
So='Softdeath:BAAANQADCgcIBwAAAA==.Sosoh:BAAANQAECgIIAwABNQAECgUIDwAHAAAAAA==.',
Sp='Spellnchill:BAAANQAECgYIDgAAAA==.Spintor:BAAANQAECgYIDwAAAA==.Spookyy:BAAANQADCgMIAwAAAA==.',
Sq='Squidseye:BAAANQAECgYICgAAAA==.',
St='Stainn:BAAANQAECgMIAwAAAA==.Stalk:BAAANQABCgIIAgAAAA==.Steelwaves:BAAANQAECgEJAQAAAA==.Stevelock:BAAANQADCgMIAwABNQADCgcIBwAHAAAAAA==.Stoade:BAAANQADCgQIBAAAAA==.Stormfang:BAAANQADCgIIAgAAAA==.Stormrise:BAAANQAECgUIBQAAAA==.Stricker:BAABNQAECoEjAAMbAAkKRiFpBQBbAwAbAAkKRiFpBQBbAwAcAAMKaxp5cgDWAAAAAA==.',
Su='Sukuta:BAAANQAECgIIAgAAAA==.Surious:BAAANQADCgYIBgABNQAECgQIBgAHAAAAAA==.',
Sw='Sweettooth:BAAANQAECgIIAgAAAA==.',
Sy='Syphian:BAAANQADCgcIEQAAAA==.',
Ta='Taasdingo:BAAANQADCgYIBwABNQAECgYICwAHAAAAAA==.Tacoboat:BAABNQAECoEfAAIRAAcKBQkVsgBxAQARAAcKBQkVsgBxAQAAAA==.Taishigi:BAABNQAECoEbAAICAAkKyw8+XgAbAgACAAkKyw8+XgAbAgAAAA==.Tapewyrm:BAAANQAECgcIEwAAAA==.Tathfak:BAAANQADCgUIBQAAAA==.Tatter:BAAANQADCgEIAQAAAA==.',
Te='Tecknique:BAABNQAECoEbAAMGAAkKMQvrUQCMAQAGAAkKMQvrUQCMAQAjAAEKqAjx0gAtAAAAAA==.Teedge:BAACNQAFFIEGAAIeAAQKsQoDBwAHAQAeAAQKsQoDBwAHAQA1AAQKgS8AAx4ACQo6HxkIAOICAB4ACQrWHRkIAOICAB8ABArGGzwOADYBAAAA.Teefz:BAAANQAECgUICQAAAA==.Terraphy:BAAANQADCgUIBQABNQAECgUIBwAHAAAAAA==.',
Th='Thaldric:BAAANQABCgQIBgAAAA==.Thanos:BAAANQADCgMIAwAAAA==.Thatwhitekid:BAAANQAECgUIEwAAAA==.Thepaintrain:BAAANQAECgYIEwAAAA==.Theporkchop:BAAANQADCgIIAgAAAA==.Thomasa:BAAANQADCgQIBAAAAA==.Thorodron:BAAANQADCgEJAQAAAA==.Thundera:BAAANQAECgQIDgAAAA==.',
Ti='Tierjar:BAAANQADCgcIBwAAAA==.Timberdoc:BAAANQAECgUIDwAAAA==.Timmehh:BAAANQAECgYIBgABNQAFFAQIBgAeALEKAA==.Tindril:BAABNQAECoEjAAQbAAgKFyUDBgBQAwAbAAgKFyUDBgBQAwAUAAQKywu4OQCUAAAcAAEKhAymqAAmAAAAAA==.',
To='Tolan:BAABNQAECoEXAAIDAAgKuhriOABkAgADAAgKuhriOABkAgAAAA==.Toovok:BAAANQADCggICAAAAA==.Totemtartt:BAABNQAECoEmAAIaAAkKTByIJwClAgAaAAkKTByIJwClAgAAAA==.Toxcyurifeet:BAAANQADCggICAABNQAECgkJFwANAEkeAA==.Toxicai:BAABNQAECoEZAAIgAAgKRRMvFwDaAQAgAAgKRRMvFwDaAQAAAA==.',
Tr='Trakeus:BAAANQAECggIEgAAAA==.Treespriest:BAAANQAECgcIBwAAAA==.Treyman:BAABNQAECoEZAAIEAAcKwBOUlwC+AQAEAAcKwBOUlwC+AQAAAA==.Tribune:BAABNQAECoElAAIGAAgKTyBgGwC8AgAGAAgKTyBgGwC8AgABNQAECgkJGgAUAA8lAA==.Trinitree:BAAANQAECgQIBQAAAA==.Trinkler:BAAANQAECgUICwAAAA==.',
Tu='Tunka:BAAANQADCgcIEAAAAA==.',
Tw='Twist:BAAANQAECgYIEQAAAA==.',
Ty='Tychondris:BAABNQAECoEkAAIIAAgKPQrDhgDOAQAIAAgKPQrDhgDOAQAAAA==.Tyzonelfalas:BAAANQAECgYICQAAAA==.',
Ul='Ulsoga:BAABNQAECoEaAAImAAgKnw39BwDwAQAmAAgKnw39BwDwAQAAAA==.',
Un='Unbórn:BAAANQADCgQIBAAAAA==.Undeadbeast:BAAANQADCgYICgAAAA==.',
Ut='Utica:BAAANQADCgcJCQAAAA==.',
Va='Vaiko:BAAANQADCgMIAwAAAA==.Valkyries:BAAANQAECggIBAAAAA==.Varibash:BAAANQADCggICAABNQAECggIJAAJADwbAA==.Vaspara:BAACNQAFFIEFAAIDAAIKthjFFwCtAAADAAIKthjFFwCtAAA1AAQKgRcAAgMACQoTHW8aAPkCAAMACQoTHW8aAPkCAAAA.',
Ve='Vergalis:BAAANQAECgEIAQAAAA==.',
Vi='Vileknight:BAAANQAECgEIAQAAAA==.Visark:BAAANQADCggICAAAAA==.Visz:BAAANQADCgQIBAAAAA==.Vitlania:BAAANQAECgQIBAAAAA==.',
Vo='Voidlìlíth:BAABNQAECoEcAAIBAAgKBxcDkwA+AgABAAgKBxcDkwA+AgAAAA==.Voidwak:BAAANQAECgUICgAAAA==.Vorronni:BAABNQAECoEcAAIMAAgKiCC2HQDgAgAMAAgKiCC2HQDgAgAAAA==.',
Wa='Wardo:BAACNQAFFIEVAAMCAAYKIBsKBwDNAQACAAUKZRwKBwDNAQAiAAEKxhS7FgBTAAA1AAQKgTcABAIACQoiJRAMAFkDAAIACAoAJRAMAFkDACIABwr5HE4MACcCACYAAQrUG9krADUAAAAA.Warhelm:BAAANQADCgMIAwAAAA==.Warlok:BAAANQADCgEIAQAAAA==.Wastedraider:BAAANQAECgQIBAAAAA==.Wastedtank:BAAANQAECgEIAQAAAA==.',
We='Wellen:BAAANQADCgUICQAAAA==.Werewolf:BAAANQADCggILQAAAA==.',
Wh='Whitemist:BAAANQAECgQIBQAAAA==.Whitepikmin:BAABNQAECoEfAAMUAAgKkx6tCgCLAgAUAAcKOiCtCgCLAgAVAAEK/xKjMwA+AAAAAA==.',
Wi='Wilmer:BAABNQAECoEfAAIIAAgKfCC2LADGAgAIAAgKfCC2LADGAgAAAA==.Wily:BAAANQADCggIDgAAAA==.Windowsvista:BAAANQAECgUICQAAAA==.Winterlock:BAAANQADCgcJDQAAAA==.Wiseguy:BAAANQADCgcICQAAAA==.',
Wo='Wookieweener:BAAANQAECgQIBAABNQAECggIFQARACQXAA==.',
Wr='Wravc:BAAANQAECgQICAAAAQ==.',
Xa='Xaspen:BAAANQAECgUICAAAAA==.',
Xe='Xerukin:BAAANQADCgYJDAAAAA==.',
Xo='Xoroth:BAAANQAECgUICQAAAA==.',
Ya='Yargonz:BAAANQAECgcIDgAAAA==.Yargz:BAAANQAECgcIEwABNQAFFAYIFQAGAIwIAA==.Yargzdk:BAACNQAFFIEVAAIGAAYKjAjoDABWAQAGAAYKjAjoDABWAQA1AAQKgSIAAgYACQrODzlJALMBAAYACQrODzlJALMBAAAA.',
Ye='Yeyol:BAABNQAECoEcAAIkAAgK9xkQGgCEAgAkAAgK9xkQGgCEAgAAAA==.',
Yo='Yolius:BAAANQAECgQIEgAAAA==.Yoogi:BAAANQAECgEIAQABNQAECgcIDgAHAAAAAA==.',
Yu='Yungnetero:BAAANQAECgQIBwAAAA==.Yunikon:BAABNQAECoEqAAQEAAkKgh8hIwAfAwAEAAkKgh8hIwAfAwADAAcKwg8sbgCmAQATAAcK7hYbJACSAQABNQAECgYICwAHAAAAAA==.',
Za='Zabala:BAAANQABCgQIBAABNQAECgcIHAAEAEUYAA==.Zavorotnuk:BAAANQADCggICgAAAA==.',
Ze='Zell:BAAANQAECgUICAABNQAECgYIEgAHAAAAAA==.Zelluss:BAAANQAECgYIEgAAAA==.Zelrin:BAAANQADCgUIBwAAAA==.Zeltari:BAAANQADCgQIBQAAAA==.Zeothule:BAAANQAECgIIAgAAAA==.Zephyrex:BAAANQAECgEIAQAAAA==.Zerkerpete:BAAANQAFFAEIAQAAAA==.',
Zh='Zhaphiria:BAAANQAFFAMIAwAAAA==.Zhul:BAAANQAECgYIDgABNQAECgcIGgAEACkeAA==.',
Zi='Zimmy:BAAANQADCgYIBgAAAA==.',
Zo='Zoomies:BAAANQAECgUICQAAAA==.',
Zu='Zuldahn:BAAANQADCgYIBgAAAA==.',
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
