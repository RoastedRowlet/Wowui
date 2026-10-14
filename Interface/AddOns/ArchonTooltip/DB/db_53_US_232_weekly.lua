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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','Warrior-Fury','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','DemonHunter-Havoc','Rogue-Subtlety','Monk-Mistweaver','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-10-13',data={Ae='Aelithsong:BAEANQAECgUICAABNQAECgEIAQABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8fAAICAAkKRw/+EwAMAgACAAkKRw/+EwAMAgAAAA==.',
Al='Alderok:BAAANQAECgYIBgABNQAECgcIEgABAAAAAA==.Aliancia:BAABNQAECn8ZAAIDAAcKzRIWGwCDAQADAAcKzRIWGwCDAQAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgQIBQAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECn8rAAIEAAkKGR6yHgDzAgAEAAkKGR6yHgDzAgAAAA==.Antherina:BAAANQADCgEIAQAAAA==.Antonious:BAAANQAECgMIBAAAAA==.',
Ap='Apollyon:BAABNQAECn8tAAMFAAkKDiFUJwAmAwAFAAgK/CNUJwAmAwAGAAUKAhUlkwBiAQAAAA==.',
Ar='Ari:BAABNQAECn8bAAIHAAYKFyQApQA2AgAHAAYKFyQApQA2AgAAAA==.Ariioch:BAAANQAECgUIBgAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgEIAgAAAA==.Assclapiuss:BAABNQAECn8rAAMFAAkKjCMCHABSAwAFAAkKjCMCHABSAwAGAAQKSxDiywDfAAAAAA==.Asterchades:BAABNQAECn8xAAIIAAkKDBOyFAAVAgAIAAkKDBOyFAAVAgAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn8rAAIJAAgKCwe4EwBrAQAJAAgKCwe4EwBrAQAAAA==.Atuan:BAAANQAECgYIBwAAAA==.',
Au='Auralass:BAAANQAECgMIBQAAAA==.Autauga:BAAANQAECgcICwAAAA==.',
Av='Avatard:BAAANQAECgQIBgABNQAECgkJIAAHAOwPAA==.Avilla:BAABNQAECn8dAAIEAAgK3RwTMAClAgAEAAgK3RwTMAClAgAAAA==.',
Ax='Axem:BAABNQAECn8cAAIKAAgKoRYsCgAoAgAKAAgKoRYsCgAoAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAAANQAECgUIDQAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.',
Be='Bechett:BAABNQAECn8fAAILAAgKoBNfKgDGAQALAAgKoBNfKgDGAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgIIAgAAAA==.Behemothe:BAABNQAECn8zAAIMAAkKChgwCgDOAgAMAAkKChgwCgDOAgAAAA==.Berníesandrs:BAAANQAECgUICgAAAA==.Beryllos:BAAANQADCggIFwAAAA==.Bewzey:BAAANQAECgcIEwAAAA==.',
Bh='Bhadabing:BAAANQADCgIIAgAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgMIAwAAAA==.',
Bl='Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8aAAINAAYK7CLCOwAvAgANAAYK7CLCOwAvAgAAAA==.Bloodytoutii:BAAANQAECgMIBgAAAA==.',
Bo='Bortman:BAABNQAECn8iAAIOAAgK8SEhDgAEAwAOAAgK8SEhDgAEAwAAAA==.Boukz:BAAANQADCgcIBgAAAA==.Bowowner:BAAANQAECgYIDQAAAA==.',
Br='Brazken:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIFAAYKOhpgnADlAQAFAAYKOhpgnADlAQAAAA==.Buzzball:BAAANQAECgUIEAAAAA==.',
Bw='Bwicked:BAABNQAECn8rAAMJAAgKSRGRFABeAQAHAAgKaQ6fygDuAQAJAAcKQhGRFABeAQAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAECgkJLAAJAJwmAA==.',
Ce='Celonge:BAAANQAECgQIBQABNQAECgkJMQAGACkXAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAHAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Chimpnzthat:BAAANQAECgMICQAAAA==.Chookicookie:BAABNQAECn8qAAMPAAkKDCJpEgAzAwAPAAkKDCJpEgAzAwAQAAcKWxPHcADKAQAAAA==.Chrome:BAABNQAECn8xAAMRAAkK1B2fFgCKAgARAAgKyByfFgCKAgASAAgKaBotLAB3AgAAAA==.',
Ci='Cici:BAAANQABCggIDQAAAA==.Cindyy:BAABNQAECn8YAAILAAgKWBgXHgA+AgALAAgKWBgXHgA+AgAAAA==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn8jAAITAAgKPSDkGQDdAgATAAgKPSDkGQDdAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgcIDwABAAAAAA==.Coresh:BAABNQAECn8tAAIMAAkKkhsLCgDRAgAMAAkKkhsLCgDRAgAAAA==.Cornpuff:BAAANQAECgYIBgAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAAANQAECgUIEAAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgQIDAABNQAECgkJKwAFAIwjAA==.Daemonbane:BAAANQADCgYIBgAAAA==.Damessiah:BAAANQAECgUIBQAAAA==.Dark:BAABNQAECn8rAAIUAAkK1iEQEABPAwAUAAkK1iEQEABPAwAAAA==.Darkphyre:BAAANQAECgYIBwAAAA==.Darthtree:BAAANQAECgUIBQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn8xAAMUAAkKaSSVBQCiAwAUAAkKaSSVBQCiAwAVAAEK+h0EbABGAAAAAA==.Deathtike:BAABNQAECn8pAAITAAgKsB/nHQDAAgATAAgKsB/nHQDAAgABNQAECgkJMQAWANcjAA==.Decius:BAAANQAECgYIBwAAAA==.Deltairlines:BAACNQAFFH8OAAMXAAUK8SBbAwDYAQAXAAUK8SBbAwDYAQAYAAEKXgBIGwAiAAA1AAQKfyAABBcACQp6Id0CABwDABcACQp6Id0CABwDABgACQo2ET0bABICAAIAAQqBDXw8ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUIDgAXAPEgAA==.Demagorgin:BAAANQAECgcIEAAAAA==.Deqlyn:BAABNQAECn8gAAIFAAgKShyRYgBuAgAFAAgKShyRYgBuAgAAAA==.Desmus:BAAANQAECgMICQAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn8pAAIZAAgKuhs2GAA0AgAZAAgKuhs2GAA0AgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAABNQAECn8hAAIUAAgKNRx9RQB/AgAUAAgKNRx9RQB/AgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doublehungus:BAAANQABCgQIBAAAAA==.Doxophil:BAAANQADCgQIBAABNQAECgcIEgABAAAAAA==.',
Dr='Droax:BAAANQADCgYIBQAAAA==.Dronin:BAABNQAECn8fAAIaAAcKmBbdLQDaAQAaAAcKmBbdLQDaAQAAAA==.Drpatan:BAAANQAECgQICQAAAA==.Druni:BAAANQAECgYIBwAAAA==.Drâkenhân:BAAANQAECgUIBgAAAA==.',
Du='Dumpling:BAAANQADCgQIBAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMICAAAAA==.',
Ed='Edinburger:BAAANQADCgcIFQAAAA==.',
Eh='Ehdawg:BAAANQAECgQICQAAAA==.',
Ei='Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQABCgMIAwAAAA==.',
El='Elguezo:BAAANQAECgEIAgAAAA==.',
Em='Emokillaz:BAAANQAECgQIBgAAAA==.',
Ep='Epictaxes:BAAANQAECgUICQAAAA==.Epsilón:BAEANQAECgEIAQAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAABNQAECn8eAAIbAAgKtRuGSwCJAgAbAAgKtRuGSwCJAgAAAA==.',
Fe='Feronnia:BAAANQADCggIFwAAAA==.',
Fi='Fibot:BAABNQAECn8xAAIMAAkKVhZ+CwC3AgAMAAkKVhZ+CwC3AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQICAAAAA==.',
Fl='Florasol:BAAANQAECgQIBgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAAANQAECgYIBgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAAANQAECgQIDgABNQAFFAUIDwAcANclAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIHAAgKaQ7wxAD5AQAHAAgKaQ7wxAD5AQAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgkJIQAOAAARAA==.',
Gh='Ghomertin:BAAANQAECgMIBQAAAA==.',
Gi='Gipsydanger:BAABNQAECn8uAAMEAAkKyCAuEABDAwAEAAkKyCAuEABDAwAdAAIKKw0HIABfAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECggIEQABAAAAAA==.',
Go='Gonnjass:BAAANQADCgYIEgAAAA==.Goragar:BAAANQAECgQIBAAAAA==.Gorlokk:BAEANQADCgcICAAAAA==.',
Gr='Grakonys:BAABNQAECn8mAAICAAkKyQhHGADCAQACAAkKyQhHGADCAQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQICgAAAA==.Grunch:BAAANQADCgUICQAAAA==.Grunnck:BAAANQADCggIKQAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAYIFgABAAAAAA==.Guidosarduci:BAAANQADCggICAAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQADCggIEAAAAA==.Harnix:BAAANQAECgMIBwAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn8jAAIEAAgKwh+GIwDcAgAEAAgKwh+GIwDcAgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgUIEAABAAAAAA==.',
He='Hellreines:BAABNQAECn8tAAIeAAkKUyLNCQBMAwAeAAkKUyLNCQBMAwAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgMICQAAAA==.Him:BAAANQAECgUJDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8pAAIEAAgKKCSDEQA6AwAEAAgKKCSDEQA6AwAAAA==.Holyscales:BAAANQAECgQICgAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Id='Idarae:BAAANQAECgQIBAABNQAECggIIwATAD0gAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAAANQAECgMIBwAAAA==.',
Iv='Ivvy:BAAANQAECgUIBwAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAAANQAECggIEwABNQAFFAMIAwABAAAAAA==.Janntro:BAABNQAECn8gAAMfAAgK8xYIJwBhAgAfAAgK8xYIJwBhAgAWAAEKAAAsLQBKAAAAAA==.Jantra:BAAANQADCgQIBAABNQAECggIIAAfAPMWAA==.Jantro:BAABNQAECn8cAAIIAAgK5yF9BgAlAwAIAAgK5yF9BgAlAwABNQAECggIIAAfAPMWAA==.Janttro:BAAANQAECgUIDwABNQAECggIIAAfAPMWAA==.',
Je='Jebby:BAABNQAECn8fAAIHAAkKXRXxgQB6AgAHAAkKXRXxgQB6AgAAAA==.Jeebz:BAAANQAECgUICAABNQAECgkJHwAHAF0VAA==.Jelmarr:BAAANQADCggIFwAAAA==.Jerauld:BAAANQAECgMICQAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8cAAIeAAcKTBjJOADrAQAeAAcKTBjJOADrAQAAAA==.Joshc:BAABNQAECn8bAAIIAAYKeQctNgDtAAAIAAYKeQctNgDtAAAAAA==.',
Ju='Judgédred:BAAANQAECgIIAwAAAA==.',
['Já']='Ják:BAAANQAECgcIEgAAAA==.',
Ka='Kaaris:BAAANQAECgYIEwAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kairos:BAABNQAECn8sAAIHAAkKYw1ssQAeAgAHAAkKYw1ssQAeAgAAAA==.Kanofworms:BAAANQAECgYIDgAAAA==.Karkea:BAABNQAECn8XAAITAAgKBCLEEAAlAwATAAgKBCLEEAAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8eAAIDAAcKnRgeFwC1AQADAAcKnRgeFwC1AQAAAA==.',
Ki='Kibil:BAABNQAECn8dAAIFAAgKWBEBjQAHAgAFAAgKWBEBjQAHAgAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8bAAIYAAYKPxYBJQCVAQAYAAYKPxYBJQCVAQAAAA==.Kos:BAACNQAFFH8PAAIcAAUK1yV0BAD/AQAcAAUK1yV0BAD/AQA1AAQKfx8AAhwACQrkJWIGAHADABwACQrkJWIGAHADAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECggIIAAfAPMWAA==.',
Ku='Kujiera:BAABNQAECn8ZAAMVAAgKdgYyJgBCAQAVAAcKzwUyJgBCAQAUAAYKTQXi5wD0AAAAAA==.Kurick:BAAANQAECgUIDAAAAA==.Kurrenter:BAABNQAECn8dAAIGAAgKTB5YKgC8AgAGAAgKTB5YKgC8AgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn8mAAIZAAkKgw/zIwC9AQAZAAkKgw/zIwC9AQAAAA==.',
La='Laiyth:BAABNQAECn8gAAIUAAkKTA+6XQA6AgAUAAkKTA+6XQA6AgAAAA==.Larryfish:BAABNQAECn8cAAMNAAgKhSKJKACVAgANAAcKACGJKACVAgAeAAcKeSF7IgB3AgAAAA==.Lavos:BAABNQAECn8iAAIVAAgKqwvxFQC8AQAVAAgKqwvxFQC8AQAAAA==.',
Le='Levitikus:BAAANQAFFAEIAQAAAA==.',
Li='Lisster:BAABNQAECn8bAAIbAAYK/iG7awA5AgAbAAYK/iG7awA5AgAAAA==.Liyra:BAAANQAECgcIEQAAAA==.',
Lo='Loafe:BAABNQAECn8gAAIFAAkK+xQGhAAbAgAFAAkK+xQGhAAbAgAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgYIBwAAAA==.Luxury:BAABNQAECn8cAAIDAAcK7wMnKAD3AAADAAcK7wMnKAD3AAAAAA==.',
Ly='Lykanthropos:BAAANQAECgIIAgAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn8bAAIgAAgKwg1EHgDcAQAgAAgKwg1EHgDcAQAAAA==.Mako:BAABNQAECn8nAAIYAAkKch68CQAGAwAYAAkKch68CQAGAwAAAA==.Malevian:BAAANQADCgYILQAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn8wAAIhAAkK7AtkHgCfAQAhAAkK7AtkHgCfAQAAAA==.Marc:BAAANQAECgUIBQAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAAANQAECgUIDAAAAA==.Mazz:BAAANQAECgYIEQAAAA==.',
Me='Megaterium:BAAANQAECgYIEwAAAA==.Meláni:BAAANQAECgIIAwAAAA==.Menethil:BAAANQAECgYIEAAAAA==.',
Mi='Milei:BAAANQAECgIIAgAAAA==.Misie:BAAANQABCgIIAQAAAA==.Missmisery:BAABNQAECn8bAAMbAAgK2g8LcwAnAgAbAAgK2g8LcwAnAgAiAAQK2gj5DQDMAAAAAA==.Mistaya:BAABNQAECn8bAAIPAAcKHQd8rwAMAQAPAAcKHQd8rwAMAQAAAA==.Mithdraug:BAAANQAECgYIBwAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAABNQAECn8aAAIjAAcKWQfS2wAuAQAjAAcKWQfS2wAuAQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECgIIAgAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgMIAwAAAA==.',
['Mà']='Màtch:BAAANQADCgYICAABNQAECgkJIQAGAO0aAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAUIEwACABwiAA==.',
Ni='Nightparade:BAAANQAECgYIBwAAAA==.Nishgrail:BAABNQAECn8lAAIIAAgK3SMtBgAtAwAIAAgK3SMtBgAtAwAAAA==.',
No='Nohkal:BAAANQADCgcIEgAAAA==.',
Nu='Nukusmaximus:BAAANQAECgMICQAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAAANQAECgcIEgAAAA==.',
On='Onex:BAAANQAECgYIBwAAAA==.',
Or='Orangethanos:BAAANQADCggICAAAAA==.Orgrím:BAAANQAECgIIAQAAAA==.Ori:BAAANQAECgMIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAIhAAcKBAySJgA+AQAhAAcKBAySJgA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8gAAIQAAcK4ApzkAB3AQAQAAcK4ApzkAB3AQAAAA==.Persefini:BAAANQAECgUIBQAAAA==.Petrodaear:BAAANQADCgEJAQABNQADCggIGwABAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAAANQAECgYIBwAAAA==.Philidox:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAABNQAECn8aAAIbAAgKChxnOAC/AgAbAAgKChxnOAC/AgAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Popita:BAAANQAECgQIBAAAAA==.Portal:BAAANQADCgIIAgABNQAECgcIGgAEALEVAA==.Potatobear:BAABNQAECn8kAAMbAAgKUiSbGwAoAwAbAAgKUiSbGwAoAwAaAAMKwRKzWgC2AAAAAA==.',
Pr='Praytwothee:BAABNQAECn8bAAIcAAkK2x3wDAAaAwAcAAkK2x3wDAAaAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn8uAAQfAAgKXhXqMQAWAgAfAAgKXhXqMQAWAgAOAAYK7ggIRwAVAQAWAAEK1AkhNAAoAAAAAA==.',
Ra='Ragedh:BAABNQAECn8oAAIOAAkKIiVgAQDZAwAOAAkKIiVgAQDZAwAAAA==.Ragequit:BAAANQAECgYICQAAAA==.Ragna:BAAANQADCggICAAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAAANQAECgYIEAAAAA==.Ravensblood:BAAANQAECgYIBgAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECgcICAAAAA==.Reeses:BAEANQADCgYIDwABNQADCgcICAABAAAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDAAAAA==.Roglof:BAAANQAECggIEQAAAA==.Rowlah:BAAANQAECgMIBwAAAA==.Rozy:BAABNQAECn8zAAMGAAkK1hbhQABfAgAGAAkK1hbhQABfAgAFAAcKoRRbrADBAQAAAA==.',
Ru='Ruiizu:BAABNQAECn8bAAIFAAYK4SAjfwAmAgAFAAYK4SAjfwAmAgAAAA==.Rushuna:BAABNQAECn8kAAIdAAkK3hfIAwCiAgAdAAkK3hfIAwCiAgAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAIbAAcKDRLYnADJAQAbAAcKDRLYnADJAQAAAA==.Sairicck:BAABNQAECn8iAAIbAAcKHRZpjQDrAQAbAAcKHRZpjQDrAQAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgYIBwAAAA==.',
Se='Selinora:BAAANQAECggIDQAAAA==.Serhalatath:BAAANQAECgUIBgAAAA==.',
Sh='Shade:BAABNQAECn8aAAMEAAcKsRXxawDWAQAEAAcKsRXxawDWAQAdAAEKQBInJwA3AAAAAA==.Shadonymph:BAAANQAECgQIBAAAAA==.Shadowsbane:BAABNQAECn8fAAMGAAcKUBP2cwC4AQAGAAcKUBP2cwC4AQAFAAQKCQuSJAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIFAAcKriKcWgCEAgAFAAcKriKcWgCEAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Shamwow:BAABNQAECn8gAAIQAAkKNSH1FQBDAwAQAAkKNSH1FQBDAwAAAA==.Shaolinsnake:BAAANQAECgUIBQAAAA==.Sharpspoon:BAAANQAECgMIAwABNQAECgkJLAAJAJwmAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgcIDwAAAA==.Shiiva:BAAANQAECgUIBQAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQAECgYIBgAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8gAAIHAAkK7A/vtAAYAgAHAAkK7A/vtAAYAgAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.Skolmoon:BAAANQADCgYIBgAAAA==.',
Sl='Sloppyjo:BAABNQAECn8iAAIEAAcKJSEiNACUAgAEAAcKJSEiNACUAgAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgkJMQAGACkXAA==.Solsti:BAABNQAECn8xAAIGAAkKKReaOACAAgAGAAkKKReaOACAAgAAAA==.Soulhunter:BAABNQAECn8iAAMTAAgKOyJMGwDSAgATAAgKOyJMGwDSAgANAAIKiSK1oAC3AAAAAA==.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgEIAQAAAA==.Spoondot:BAAANQAECgUIBQABNQAECgkJLAAJAJwmAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIAwAAAA==.Stillthorny:BAAANQAECgIIAgAAAA==.Stinjaga:BAABNQAECn8bAAIHAAYKMRtvxwD0AQAHAAYKMRtvxwD0AQAAAA==.Stormyknight:BAAANQAECgQIBAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAAANQAFFAMIAwAAAA==.',
Su='Sunrae:BAAANQAECgMICQAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgcIEwAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAHAGkOAA==.Taryen:BAABNQAECn8dAAITAAgKtwtNWgCHAQATAAgKtwtNWgCHAQABNQAECgkJKAAOACIlAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAECgkJIQAGAO0aAA==.Telaari:BAAANQAECgUIBwAAAA==.Teriyl:BAABNQAECn8pAAMDAAkKTxXcGQCTAQAjAAkKjg4YgwAQAgADAAUKXRvcGQCTAQAAAA==.',
Th='Thalenia:BAABNQAECn8lAAIbAAkKmg0UbgAzAgAbAAkKmg0UbgAzAgAAAA==.Thallenia:BAAANQADCgcIEwAAAA==.Thalpura:BAAANQABCgYIBgAAAA==.Thalron:BAAANQAECgUIBgAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCgQIBAAAAA==.',
Ti='Tikeidari:BAABNQAECn8xAAIWAAkK1yMYAQCtAwAWAAkK1yMYAQCtAwAAAA==.Tiltedtroll:BAABNQAECn8bAAIQAAcKNQminABaAQAQAAcKNQminABaAQAAAA==.',
To='Tonofcron:BAAANQADCgcIFAAAAA==.Totemeri:BAABNQAECn8jAAMPAAgKLhHPdgCjAQAPAAgKLhHPdgCjAQAQAAYKlQ1AoQBPAQAAAA==.',
Tr='Trappydk:BAAANQAECgcIEwAAAA==.Trappydruid:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQADCggIDgAAAA==.',
Ug='Uglyplug:BAAANQAECgIIAgAAAA==.',
Un='Unagi:BAAANQAECgYIEgAAAA==.',
Va='Vak:BAAANQAECgYIBgAAAA==.Vaks:BAAANQAECgYICwAAAA==.Valezeal:BAAANQAECgMIBgAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8ZAAMPAAkKdhQwdQCoAQAPAAYK7xYwdQCoAQAQAAUKzhNDxAAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYJBgAAAA==.Venan:BAAANQAECgQICwAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgIIAgAAAA==.Venev:BAAANQAECgUICgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAAANQAECgcIDwABNQAECgkJTQASAK4dAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8fAAIeAAgK2RI0PQDTAQAeAAgK2RI0PQDTAQAAAA==.',
Wa='Wanji:BAABNQAECn8bAAINAAYK5QXHigD0AAANAAYK5QXHigD0AAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGQAPAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgcIEwAAAA==.',
Xa='Xaharst:BAABNQAECn8dAAITAAcKJBFMWwCCAQATAAcKJBFMWwCCAQAAAA==.Xandris:BAAANQAECgQIBAAAAA==.Xaya:BAABNQAECn8fAAIUAAkKtQ8IcwADAgAUAAkKtQ8IcwADAgAAAA==.',
Xe='Xenophorge:BAAANQAECgQIBQAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgYIBwAAAA==.',
Xt='Xtayse:BAABNQAECn8cAAICAAgK9B1wCQDZAgACAAgK9B1wCQDZAgAAAA==.',
Yi='Yirya:BAABNQAECn8hAAMRAAgKXgzMMACQAQARAAgKXgzMMACQAQASAAEK2gG2vQAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn8fAAIIAAgK9CL2BgAZAwAIAAgK9CL2BgAZAwAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBAAAAA==.',
Za='Zahel:BAABNQAECn8uAAIFAAkKwSCAJQAtAwAFAAkKwSCAJQAtAwAAAA==.Zavier:BAAANQAECgcIEgAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAAANQAECgQICAAAAA==.',
Zh='Zhee:BAAANQAECgYIBwAAAA==.',
Zo='Zobi:BAAANQADCgYJEgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.',
Zy='Zyde:BAAANQADCgQIBAAAAA==.',
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
