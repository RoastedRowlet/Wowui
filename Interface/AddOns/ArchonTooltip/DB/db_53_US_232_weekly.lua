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

local lookup = {'Paladin-Protection','Unknown-Unknown','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','Warrior-Fury','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Havoc','Warlock-Affliction','Rogue-Subtlety','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-10-27',data={Ae='Aelithsong:BAEBNQAECn8WAAIBAAcKEgRxLQCmAAABAAcKEgRxLQCmAAABNQAECgYIBgACAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8oAAIDAAoKOhEtFAALAgADAAoKOhEtFAALAgAAAA==.',
Al='Alakthon:BAAANQABCgMIBAAAAA==.Alderok:BAAANQAECgYIBgABNQAECgoKIwAEAAYXAA==.Aliancia:BAABNQAECn8qAAIFAAkKsBN1CwCIAQAFAAkKsBN1CwCIAQAAAA==.Allusive:BAAANQADCgYIAwABNQAECgYIEQACAAAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgUICAAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECn8sAAIGAAkKth9YHwDzAgAGAAkKth9YHwDzAgAAAA==.Annorca:BAAANQADCgQIBAABNQAECgkJLAAGALYfAA==.Antherina:BAAANQAECgEIAQAAAA==.Antonious:BAAANQAECgYICgAAAA==.',
Ap='Apollyon:BAABNQAECn9KAAMHAAoKTySeCgAhAwAHAAoKTySeCgAhAwAIAAgKXh1PIgA2AgAAAA==.',
Ar='Ari:BAABNQAECn8iAAIJAAcKRyNVpgA1AgAJAAcKRyNVpgA1AgAAAA==.Ariioch:BAAANQAECgcIDAAAAA==.Arodar:BAAANQADCgMIAwAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgIIAgAAAA==.Assclapiuss:BAABNQAECn84AAMHAAoKpySyFADVAgAHAAoKpySyFADVAgAIAAQKSxAEzgDfAAAAAA==.Asterchades:BAABNQAECn9EAAIKAAoKLRTEDQDTAQAKAAoKLRTEDQDTAQAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn86AAILAAoK+wbzCgBaAQALAAoK+wbzCgBaAQAAAA==.Atuan:BAAANQAECgYICwAAAA==.',
Au='Auralass:BAAANQAECgMICAAAAA==.Autauga:BAAANQAECggIEwAAAA==.',
Av='Avatard:BAAANQAECgQIBgABNQAECgoKLAAJAEEPAA==.Avilla:BAABNQAECn8oAAIGAAoKIB+WEADrAgAGAAoKIB+WEADrAgAAAA==.',
Ax='Axem:BAABNQAECn8qAAIMAAoKmRj5AwBFAgAMAAoKmRj5AwBFAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAABNQAECn8fAAMNAAgKnxSGHwAtAQANAAcK8hOGHwAtAQAOAAIKAxgRHwBHAAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.Batryxamat:BAAANQAECggICAAAAA==.',
Be='Bechett:BAABNQAECn8gAAIPAAkKaBLXKgDFAQAPAAkKaBLXKgDFAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgQICAAAAA==.Behemothe:BAABNQAECn9HAAIQAAoKpRmtBgBmAgAQAAoKpRmtBgBmAgAAAA==.Berníesandrs:BAABNQAECn8WAAIJAAgK+gYesADnAAAJAAgK+gYesADnAAAAAA==.Beryllos:BAAANQAECgIIAgAAAA==.Bewzey:BAABNQAECn8jAAIJAAoKQRFSNgAZAgAJAAoKQRFSNgAZAgAAAA==.',
Bh='Bhadabing:BAAANQAECgEIAgAAAA==.',
Bi='Bifbafbouf:BAAANQAECggICQAAAA==.Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgMIBAAAAA==.',
Bl='Bleaugro:BAAANQADCggICAAAAA==.Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8nAAIRAAcK+yBPFQDaAQARAAcK+yBPFQDaAQAAAA==.Bloodytoutii:BAAANQAECgQIDgAAAA==.',
Bo='Bortman:BAABNQAECn8vAAINAAoK8CFnDgADAwANAAoK8CFnDgADAwAAAA==.Boukz:BAAANQADCgcIBgAAAA==.Bowowner:BAABNQAECn8aAAISAAcKjRlBUwCjAQASAAcKjRlBUwCjAQAAAA==.',
Br='Brazken:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIHAAYKOho9nwDjAQAHAAYKOho9nwDjAQAAAA==.Buzzball:BAABNQAECn8UAAIHAAYK8RLszwB7AQAHAAYK8RLszwB7AQAAAA==.',
Bw='Bwicked:BAABNQAECn89AAMJAAoKahHJQADzAQAJAAoKvg/JQADzAQALAAcKQhHCFABeAQAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAECgoKOAALAIcmAA==.Catie:BAAANQAECgEIAQAAAA==.',
Ce='Celonge:BAAANQAECgYICwABNQAECgoKOwAIADUaAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAJAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAACAAAAAA==.Chimpnzthat:BAAANQAECgQIDAAAAA==.Chookicookie:BAABNQAECn89AAMTAAoKeyG+EgAzAwATAAoKeyG+EgAzAwAUAAcK+xdPcgDKAQAAAA==.Chrome:BAABNQAECn9EAAMVAAoKSh7sFgCLAgAVAAgKyBzsFgCLAgAWAAoKKhtGDQB2AgAAAA==.',
Ci='Cici:BAAANQABCggIDQAAAA==.Cindyy:BAAANQAECggIIgAAAQ==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn8qAAIXAAoKSB9DGgDcAgAXAAoKSB9DGgDcAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgoKHgAVAAMbAA==.Coresh:BAABNQAECn81AAIQAAoKfxxECgDPAgAQAAoKfxxECgDPAgAAAA==.Cornpuff:BAAANQAECgcIDAAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAABNQAECn8VAAIJAAYKlwqaJAFOAQAJAAYKlwqaJAFOAQAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgYIDwABNQAECgoKOAAHAKckAA==.Daemonbane:BAAANQADCgYIBgAAAA==.Damessiah:BAAANQAECgYIDwAAAA==.Dark:BAABNQAECn85AAIYAAoK9yGMEABPAwAYAAoK9yGMEABPAwAAAA==.Darkphyre:BAAANQAECgcIDQAAAA==.Darthtree:BAAANQAECgUIBQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn85AAMYAAoK+CPGBQChAwAYAAoK+CPGBQChAwAZAAEK+h2XbABGAAAAAA==.Deathtike:BAABNQAECn82AAIXAAkKnR9SHgC/AgAXAAkKnR9SHgC/AgABNQAECgoKRAAOAEskAA==.Decius:BAAANQAECgcIDQAAAA==.Deltairlines:BAACNQAFFH8OAAMaAAUK8SBzAwDYAQAaAAUK8SBzAwDYAQAbAAEKXgCjGwAiAAA1AAQKfyAABBoACQp6IeMCABwDABoACQp6IeMCABwDABsACQo2EXAbABICAAMAAQqBDQw9ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUIDgAaAPEgAA==.Demagorgin:BAAANQAECgcIEgAAAA==.Deqlyn:BAABNQAECn8gAAIHAAgKShyHZABtAgAHAAgKShyHZABtAgAAAA==.Desmus:BAAANQAECgMIDAAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn81AAIBAAoKfhl9DwCnAQABAAoKfhl9DwCnAQAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAACAAAAAA==.',
Do='Domwarlock:BAABNQAECn8sAAIYAAkKiBvPRgB+AgAYAAkKiBvPRgB+AgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doxophil:BAAANQAECgMIAwABNQAECgkJHgAIAH4XAA==.',
Dr='Dragonfloss:BAAANQAECggICAAAAA==.Droax:BAAANQADCgYIBQAAAA==.Droh:BAAANQADCgcIBwAAAA==.Dronin:BAABNQAECn8uAAIcAAkK5BXHEQCmAQAcAAkK5BXHEQCmAQAAAA==.Drpatan:BAAANQAECgQICgAAAA==.Druni:BAAANQAECgYIDQAAAA==.Drâkenhân:BAAANQAECgYIDAAAAA==.',
Du='Dumpling:BAAANQADCgQIBAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMICwAAAA==.',
Ed='Edinburger:BAAANQADCgcIIQAAAA==.',
Eh='Ehdawg:BAAANQAECgQICQAAAA==.',
Ei='Eiduartrawr:BAAANQAECggIDwAAAA==.Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQAECgMIBAAAAA==.',
El='Elguezo:BAAANQAECgMIBwAAAA==.Ellynna:BAAANQADCgcICAAAAA==.',
Em='Emokillaz:BAAANQAECgUICQAAAA==.',
Ep='Epictaxes:BAAANQAECgUICQAAAA==.Epsilón:BAEANQAECgYIBgAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAABNQAECn8pAAISAAoKdBlaJQBOAgASAAoKdBlaJQBOAgAAAA==.Faylan:BAAANQABCgYIBgAAAA==.',
Fe='Feronnia:BAAANQAECgIIAgAAAA==.',
Fi='Fibot:BAABNQAECn9EAAIQAAoK5xUlCAA6AgAQAAoK5xUlCAA6AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQICAAAAA==.Fistavus:BAAANQABCgQIBAAAAA==.',
Fl='Florasol:BAAANQAECgQIBgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAABNQAECn8VAAISAAkK0xI3PQDtAQASAAkK0xI3PQDtAQAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAABNQAECn8XAAIJAAcKxx4ESgDTAQAJAAcKxx4ESgDTAQABNQAFFAYIEQAdABcmAA==.',
Fy='Fyrebrand:BAAANQABCgIIAgABNQAECgcIDgACAAAAAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIJAAgKaQ6cxgD3AQAJAAgKaQ6cxgD3AQAAAA==.Ganggangx:BAAANQAECgQIBwAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgoKNQANALcTAA==.',
Gh='Ghomertin:BAAANQAECgMICAAAAA==.',
Gi='Gipsydanger:BAABNQAECn85AAMGAAoKEiOHEABDAwAGAAoKEiOHEABDAwAeAAIKKw1YIABfAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.',
Go='Gonnjass:BAAANQADCgYIEwAAAA==.Goragar:BAAANQAECgQIBAAAAA==.Gorlokk:BAEANQAECggICAAAAA==.',
Gr='Grakonys:BAABNQAECn85AAIDAAoKKgnICAB1AQADAAoKKgnICAB1AQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQIDQAAAA==.Grolof:BAAANQABCgQIBAABNQAECgoKHAAJAMQFAA==.Grunch:BAAANQADCgYIDwAAAA==.Grunnck:BAAANQADCggIKgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAcIGQACAAAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQAECgUIBQAAAA==.Harnix:BAAANQAECgMICgAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn8yAAIGAAoKNCASEgDZAgAGAAoKNCASEgDZAgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgYIFAAHAPESAA==.',
He='Hellreines:BAACNQAFFH8JAAIfAAQK9hhTBwD4AAAfAAQK9hhTBwD4AAA1AAQKf0EAAh8ACgp3IvgEAB0DAB8ACgp3IvgEAB0DAAAA.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgMIDAAAAA==.Him:BAAANQAECgUIDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8uAAIGAAkK9CTdEQA6AwAGAAkK9CTdEQA6AwAAAA==.Holyscales:BAAANQAECgQIEAAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Id='Idarae:BAAANQAECgUICAABNQAECgoKKgAXAEgfAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAABNQAECn8eAAIHAAoK/hTmOgAOAgAHAAoK/hTmOgAOAgAAAA==.',
Iv='Ivvy:BAAANQAECggIEQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECn8VAAIgAAkKvwguQQDHAQAgAAkKvwguQQDHAQABNQAECgoKHgASAPIXAA==.Janntro:BAABNQAECn8oAAMhAAkK2RevJwBhAgAhAAkK2RevJwBhAgAOAAEKAADPLQBKAAABNQAECgoKKAAKAJUiAA==.Jantra:BAAANQADCgQIBAABNQAECgoKKAAKAJUiAA==.Jantro:BAABNQAECn8oAAIKAAoKlSKUAwD1AgAKAAoKlSKUAwD1AgAAAA==.Janttro:BAAANQAECgUIDwABNQAECgoKKAAKAJUiAA==.',
Je='Jebby:BAABNQAECn8rAAIJAAoKsRU0gwB4AgAJAAoKsRU0gwB4AgAAAA==.Jeebz:BAAANQAECgUICAABNQAECgoKKwAJALEVAA==.Jelmarr:BAAANQAECgIIAgAAAA==.Jerauld:BAAANQAECgMIDAAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8rAAIfAAgKOBjAHwDNAQAfAAgKOBjAHwDNAQAAAA==.Joshc:BAABNQAECn8oAAIKAAcK7QfOJwDRAAAKAAcK7QfOJwDRAAAAAA==.',
Jt='Jt:BAACNQAFFH8zAAQYAAkKViIrAACtAgAYAAkKPyIrAACtAgAZAAIKEyMvBwC4AAAiAAIKCBmwAwC3AAA1AAQKfyoAAxkACgoXJnIFAMECABgACAobJlwqANsCABkACAqYH3IFAMECAAAA.',
Ju='Judgédred:BAAANQAECggIEAAAAA==.',
['Já']='Ják:BAABNQAECn8eAAMIAAkKfhe6LQDxAQAIAAkKfhe6LQDxAQAHAAEK/gs9TwEsAAAAAA==.',
Ka='Kaaris:BAABNQAECn8fAAIZAAgKAQmvBwD5AAAZAAgKAQmvBwD5AAAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kaippe:BAAANQAECgEIAQAAAA==.Kairos:BAABNQAECn88AAIJAAoKiA9NRQDjAQAJAAoKiA9NRQDjAQAAAA==.Kanofworms:BAABNQAECn8cAAIjAAoKsAk2TwAgAQAjAAoKsAk2TwAgAQAAAA==.Karkea:BAABNQAECn8YAAIXAAgKBCICEQAlAwAXAAgKBCICEQAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8rAAIFAAgKmRZ/DAByAQAFAAgKmRZ/DAByAQAAAA==.',
Ki='Kibil:BAABNQAECn8oAAMHAAoKJQ+pbgB3AQAHAAkKbxCpbgB3AQABAAEKJgbZUgAmAAAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8oAAIbAAcKqhy+CAAzAgAbAAcKqhy+CAAzAgAAAA==.Kos:BAACNQAFFH8RAAIdAAYKFyajBAD+AQAdAAYKFyajBAD+AQA1AAQKfzAAAh0ACgp2JssAAHMDAB0ACgp2JssAAHMDAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgoKKAAKAJUiAA==.',
Ku='Kujiera:BAABNQAECn8nAAMZAAoK0wgoCgDSAAAZAAoKJAcoCgDSAAAYAAgKtwavlQDEAAAAAA==.Kurick:BAAANQAECgYIEQAAAA==.Kurrenter:BAABNQAECn8oAAIIAAoKjx6DFAChAgAIAAoKjx6DFAChAgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn82AAIBAAoKqw5qJAC9AQABAAoKqw5qJAC9AQAAAA==.',
La='Laiyth:BAABNQAECn8vAAIYAAoK6RBiNgDRAQAYAAoK6RBiNgDRAQAAAA==.Larryfish:BAABNQAECn8qAAMRAAoKKCL0KACVAgARAAgKUCD0KACVAgAfAAkKAiAyIwB2AgAAAA==.Lavos:BAABNQAECn8wAAIZAAoKuw18AwCLAQAZAAoKuw18AwCLAQAAAA==.',
Le='Levitikus:BAAANQAFFAEIAQAAAA==.Levìtikus:BAAANQAECgUIBQAAAA==.',
Li='Lisster:BAABNQAECn8nAAISAAYKmCJVRwDJAQASAAYKmCJVRwDJAQAAAA==.Liyra:BAAANQAECgcIEQAAAA==.',
Lo='Loafe:BAABNQAECn8sAAIHAAoK2xQrhgAbAgAHAAoK2xQrhgAbAgAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgYIDQAAAA==.Luxury:BAABNQAECn8rAAIFAAkKYwTgFQDqAAAFAAkKYwTgFQDqAAAAAA==.',
Ly='Lykanthropos:BAAANQAECgYICgAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn8pAAIjAAoKbA/IKADiAQAjAAoKbA/IKADiAQAAAA==.Mako:BAABNQAECn80AAIbAAoKrB/hCQAFAwAbAAoKrB/hCQAFAwAAAA==.Malevian:BAAANQADCgcINgAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn8zAAIkAAkK7Au2HgCfAQAkAAkK7Au2HgCfAQAAAA==.Marc:BAABNQAECn8UAAIUAAkKsQ2yOQBuAQAUAAkKsQ2yOQBuAQAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAAANQAECgYIEAAAAA==.Mazz:BAABNQAECn8VAAIZAAkKRxP3EgDbAQAZAAkKRxP3EgDbAQAAAA==.',
Me='Megana:BAAANQADCgYICwAAAA==.Megaterium:BAABNQAECn8hAAMGAAgKHwzsjgBpAQAGAAgKHwzsjgBpAQAdAAUK9AfnJQDXAAAAAA==.Meláni:BAAANQAECgIIBAAAAA==.Menethil:BAABNQAECn8aAAIIAAkKyxogUgAkAgAIAAkKyxogUgAkAgAAAA==.',
Mi='Milei:BAAANQAECgcICAAAAA==.Misie:BAAANQABCgIIAQAAAA==.Mispell:BAAANQABCgMIAwAAAA==.Missmisery:BAABNQAECn8lAAMSAAoKJBAhMQAbAgASAAoKJBAhMQAbAgAlAAQK2ggaDgDMAAAAAA==.Mistaya:BAABNQAECn8mAAITAAcK0g/FTQBeAQATAAcK0g/FTQBeAQAAAA==.Mithdraug:BAAANQAECgcIDQAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAABNQAECn8lAAIEAAkKXAfucAA3AQAEAAkKXAfucAA3AQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECggICwAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
Mu='Mugzee:BAAANQAECgIIAQAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgQIBAAAAA==.',
['Mà']='Màtch:BAAANQADCgcICQABNQAECgoKLwAIAIgiAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAYIGgADAI4jAA==.',
Ni='Nightparade:BAAANQAECgcIDgAAAA==.Nishgrail:BAABNQAECn8wAAMKAAoKuyKeBADLAgAKAAoKuyKeBADLAgAWAAEKbQwZaQA7AAAAAA==.',
Nu='Nukusmaximus:BAAANQAECgMIDAAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAABNQAECn8VAAIHAAcK+RhLrQDFAQAHAAcK+RhLrQDFAQAAAA==.',
On='Onex:BAAANQAECgcIDQAAAA==.',
Or='Orangethanos:BAAANQADCggICAAAAA==.Orgrím:BAAANQAECgMIAgAAAA==.Ori:BAAANQAECgQIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAIkAAcKBAwBJwA+AQAkAAcKBAwBJwA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8nAAMUAAgKCw1EkgB3AQAUAAcK4ApEkgB3AQATAAMKnAHCtgBOAAAAAA==.Persefini:BAAANQAECggIEQAAAA==.Petrodaear:BAAANQADCgQIBAABNQADCggIGwACAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAAANQAECgcIDQAAAA==.Philidox:BAAANQADCgYIBgABNQAECgkJHgAIAH4XAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQAECgQIBgAAAA==.Plugugly:BAABNQAECn8pAAISAAoKbCGeDwDSAgASAAoKbCGeDwDSAgAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Popita:BAAANQAECgQICgAAAA==.Portal:BAAANQADCgIIAgABNQAECgkJHgAGAEYSAA==.Potatobear:BAABNQAECn82AAMSAAoKHCU1HAAnAwASAAoKHCU1HAAnAwAcAAMKwRK4WwC2AAAAAA==.Powerbeard:BAAANQAECgUIBQAAAA==.',
Pr='Praytwothee:BAABNQAECn8hAAIdAAoKVB4WDQAaAwAdAAoKVB4WDQAaAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn80AAQhAAkKdhOhMgAWAgAhAAkKdhOhMgAWAgANAAYK7gj2RwAVAQAOAAIKUQijHgBKAAAAAA==.',
Ra='Ragedh:BAABNQAECn80AAINAAoKwyRpAQDZAwANAAoKwyRpAQDZAwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragna:BAAANQADCggICAAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAABNQAECn8dAAISAAcKHBoIRgDNAQASAAcKHBoIRgDNAQAAAA==.Ravensblood:BAAANQAECgYIDAAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECggICQAAAA==.Reeses:BAEANQADCgcIFgABNQAECggICAACAAAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDgAAAA==.Roglof:BAABNQAECn8cAAIJAAoKxAV+NwEwAQAJAAoKxAV+NwEwAQAAAA==.Rowlah:BAAANQAECgMICgAAAA==.Rozy:BAABNQAECn9EAAMIAAoK5R5NBwBWAwAIAAoK5R5NBwBWAwAHAAgKbBRfrwDAAQAAAA==.',
Ru='Ruiizu:BAABNQAECn8oAAIHAAcKch6LUQDBAQAHAAcKch6LUQDBAQAAAA==.Ruldas:BAAANQADCgYIBgAAAA==.Rushuna:BAABNQAECn84AAIeAAoKIxvIAAAAAwAeAAoKIxvIAAAAAwAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAISAAcKDRLjngDJAQASAAcKDRLjngDJAQAAAA==.Sairicck:BAABNQAECn8xAAISAAoKPhWMLQAqAgASAAoKPhWMLQAqAgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgcIDQAAAA==.',
Se='Selenar:BAAANQAECgIIAQAAAA==.Selinora:BAAANQAECggIDQAAAA==.Senaria:BAAANQADCgIIAQAAAA==.Senjia:BAAANQADCgUIBQAAAA==.Serhalatath:BAAANQAECgUIBgAAAA==.',
Sh='Shade:BAABNQAECn8eAAMGAAkKRhJxbQDWAQAGAAkKRhJxbQDWAQAeAAEKQBKaJwA3AAAAAA==.Shadonymph:BAAANQAECgUICAAAAA==.Shadowsbane:BAABNQAECn8rAAMIAAoKQxRnHABgAgAIAAoKQxRnHABgAgAHAAQKCQvTKAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIHAAcKriKdXACCAgAHAAcKriKdXACCAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwACAAAAAA==.Shamwow:BAABNQAECn8sAAIUAAoKPSJgFgBCAwAUAAoKPSJgFgBCAwAAAA==.Shaolinsnake:BAAANQAECggIEQAAAA==.Sharpspoon:BAAANQAECgYICQABNQAECgoKOAALAIcmAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAABNQAECn8eAAMVAAoKAxvvCQCjAgAVAAoKAxvvCQCjAgAWAAMK+BYkfADbAAAAAA==.Shiiva:BAAANQAECgUIBQAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQAECgcIDQAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8sAAIJAAoKQQ+5bwBmAQAJAAoKQQ+5bwBmAQAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.Skimm:BAAANQAECgcIBwAAAA==.',
Sl='Sloppyjo:BAABNQAECn8vAAIGAAgKuCM9FADEAgAGAAgKuCM9FADEAgAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgoKOwAIADUaAA==.Solsti:BAABNQAECn87AAIIAAoKNRpZOQB/AgAIAAoKNRpZOQB/AgAAAA==.Soulhunter:BAACNQAFFH8IAAIXAAQK0RG2DADIAAAXAAQK0RG2DADIAAA1AAQKfyIAAxcACAo7IqMbANICABcACAo7IqMbANICABEAAgqJIlGiALcAAAAA.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgcIBwAAAA==.Spoonbrew:BAAANQAECgUIBQABNQAECgoKOAALAIcmAA==.Spoondot:BAAANQAECgUIBQABNQAECgoKOAALAIcmAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIAwAAAA==.Stillthorny:BAAANQAECgcICQAAAA==.Stinjaga:BAABNQAECn8oAAMLAAcKuRohEgDrAAAJAAYKSBuSyQDyAQALAAMKjxkhEgDrAAAAAA==.Stormyknight:BAAANQAECgQIBAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAABNQAECn8eAAISAAoK8hfAKQA6AgASAAoK8hfAKQA6AgAAAA==.',
Su='Sunrae:BAAANQAECgMIDAAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQAECgIIAgAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAJAGkOAA==.Taryen:BAABNQAECn8nAAMXAAoK7QvjKABUAQAXAAkK+AzjKABUAQARAAEKmwQpdAAoAAABNQAECgoKNAANAMMkAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAECgoKLwAIAIgiAA==.Telaari:BAAANQAECgUIBwAAAA==.Telrander:BAAANQAECgIIAQAAAA==.Teriyl:BAABNQAECn8yAAMFAAoK5hTlEAAqAQAEAAoKRQ7DhAAQAgAFAAUKzhzlEAAqAQAAAA==.',
Th='Thalenia:BAABNQAECn81AAISAAoK7w5COQD8AQASAAoK7w5COQD8AQAAAA==.Thallenia:BAAANQADCggIIQAAAA==.Thalpura:BAAANQADCgYIBwAAAA==.Thalron:BAAANQAECgYICwAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCggIEgAAAA==.Thriller:BAAANQAECgUIBQABNQAECgoKLwAIAIgiAA==.',
Ti='Tikeidari:BAABNQAECn9EAAIOAAoKSyQaAQCtAwAOAAoKSyQaAQCtAwAAAA==.Tiltedtroll:BAABNQAECn8oAAIUAAgK6wv8RgA6AQAUAAgK6wv8RgA6AQAAAA==.',
To='Totemeri:BAABNQAECn8xAAMTAAoKtxAieACjAQATAAoKtxAieACjAQAUAAYKlQ1YowBPAQAAAA==.Toytrux:BAAANQAECgIIAgAAAA==.',
Tr='Trappydk:BAABNQAECn8YAAIRAAoKJhl9LgB3AgARAAoKJhl9LgB3AgAAAA==.Trappydruid:BAAANQAECgQIBQABNQAECgoKGAARACYZAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQADCggIDgAAAA==.',
Ug='Uglyplug:BAAANQAECgUIBwAAAA==.',
Un='Unagi:BAABNQAECn8XAAISAAcKTQ4qtgCYAQASAAcKTQ4qtgCYAQAAAA==.',
Va='Vak:BAAANQAECgYICQAAAA==.Vaks:BAAANQAECggIEQAAAA==.Valezeal:BAAANQAECgMICQAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8bAAMTAAkKdhSQdgCoAQATAAYK7xaQdgCoAQAUAAUKzhPSxgAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYIBgAAAA==.Venan:BAAANQAECgQIDAAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgMIAwAAAA==.Venev:BAAANQAECgUICgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAABNQAECn8dAAIHAAoKIhHRZwCHAQAHAAoKIhHRZwCHAQAAAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8kAAIfAAkKKRI0PgDTAQAfAAkKKRI0PgDTAQAAAA==.',
Wa='Wanji:BAABNQAECn8oAAIRAAcKQgcoNQDtAAARAAcKQgcoNQDtAAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGwATAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQAECgEIAQAAAA==.',
Xa='Xaharst:BAABNQAECn8nAAIXAAcKJBEjXACCAQAXAAcKJBEjXACCAQAAAA==.Xandris:BAAANQAECgYICwAAAA==.Xaya:BAABNQAECn8rAAIYAAoK5xDDdAADAgAYAAoK5xDDdAADAgAAAA==.',
Xe='Xenophorge:BAAANQAECgUIDQAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgYIDQAAAA==.',
Xt='Xtayse:BAABNQAECn8rAAIDAAoKjBwdAwB2AgADAAoKjBwdAwB2AgAAAA==.',
Yi='Yirya:BAABNQAECn8vAAMVAAgK+Q7YHgBpAQAVAAgK+Q7YHgBpAQAWAAEK2gHkvwAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn8rAAIKAAkKGSMQBwAZAwAKAAkKGSMQBwAZAwAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBAAAAA==.',
Za='Zahel:BAABNQAECn8/AAIHAAoKGCAvFgDLAgAHAAoKGCAvFgDLAgAAAA==.Zandruu:BAAANQADCgUIBQABNQAECgIIBAACAAAAAA==.Zavier:BAABNQAECn8jAAMEAAoKBheALQAlAgAEAAoKShaALQAlAgAMAAUKfhivEgB2AQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAABNQAECn8XAAIfAAgK5Q2hMwBSAQAfAAgK5Q2hMwBSAQAAAA==.',
Zh='Zhee:BAAANQAECgYIDQAAAA==.',
Zo='Zobi:BAAANQAECgIIAgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.',
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
