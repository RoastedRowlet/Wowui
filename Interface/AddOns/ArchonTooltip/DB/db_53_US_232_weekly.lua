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

local lookup = {'Paladin-Protection','Unknown-Unknown','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Priest-Holy','Priest-Shadow','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Priest-Discipline','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Havoc','Druid-Feral','Warlock-Affliction','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-11-03',data={Ae='Aelithsong:BAABNQAECn8YAAIBAAgKpQS0MADIAAABAAgKpQS0MADIAAABNQAECgYIBwACAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8sAAIDAAoKkRItFAALAgADAAoKkRItFAALAgAAAA==.',
Al='Alakthon:BAAANQABCgMIBAAAAA==.Alderok:BAAANQAECgYIBgABNQAECgoKJAAEAAYXAA==.Aliancia:BAABNQAECn8zAAIFAAkKsBMbEAB7AQAFAAkKsBMbEAB7AQAAAA==.Allusive:BAAANQADCgYIAwABNQAECggIEgACAAAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgUICAAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECn81AAMGAAoKnx1YHwDzAgAGAAoKnx1YHwDzAgAHAAEKPAm2VAA3AAAAAA==.Annorca:BAAANQADCgQIBAABNQAECgoKNQAGAJ8dAA==.Antherina:BAAANQAECgMIAgAAAA==.Antonious:BAAANQAECgYIDQAAAA==.',
Ap='Apollyon:BAABNQAECn9UAAMIAAoK8yRjDgAfAwAIAAoK8yRjDgAfAwAJAAkK7R2XHgCYAgAAAA==.',
Ar='Ari:BAABNQAECn8pAAIKAAcKRyNVpgA1AgAKAAcKRyNVpgA1AgAAAA==.Ariioch:BAAANQAECgcIDQAAAA==.Arodar:BAAANQADCgMIAwAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgIIAgAAAA==.Assclapiuss:BAABNQAECn88AAMIAAoKpyTCHABQAwAIAAoKpyTCHABQAwAJAAQKSxAEzgDfAAAAAA==.Asterchades:BAABNQAECn9OAAILAAoKwRVzDwAFAgALAAoKwRVzDwAFAgAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn9EAAIMAAoK+wbtEwBrAQAMAAoK+wbtEwBrAQAAAA==.Atuan:BAAANQAECgcIDQAAAA==.',
Au='Auralass:BAAANQAECgMICAAAAA==.Autauga:BAABNQAECn8aAAINAAoKNwzvQgCpAQANAAoKNwzvQgCpAQAAAA==.',
Av='Avatard:BAAANQAECgcICwABNQAECgoKLQAKAP8PAA==.Avilla:BAABNQAECn8oAAIGAAoKIB/AGgDUAgAGAAoKIB/AGgDUAgAAAA==.',
Ax='Axem:BAABNQAECn8rAAIOAAoKmRgoBgAsAgAOAAoKmRgoBgAsAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAABNQAECn8mAAMPAAkKqxNiHgB6AQAPAAgK8RJiHgB6AQAQAAIKAxh/JQBFAAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.Batryxamat:BAAANQAECggICAAAAA==.',
Be='Bechett:BAABNQAECn8gAAIRAAkKaBLXKgDFAQARAAkKaBLXKgDFAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgQICAAAAA==.Behemothe:BAABNQAECn9RAAISAAoKRRoiCQBgAgASAAoKRRoiCQBgAgAAAA==.Berníesandrs:BAABNQAECn8cAAIKAAkK4AcNrgAeAQAKAAkK4AcNrgAeAQAAAA==.Beryllos:BAAANQAECgIIAgAAAA==.Bewzey:BAABNQAECn8mAAIKAAoKQREJTAAEAgAKAAoKQREJTAAEAgAAAA==.',
Bh='Bhadabing:BAAANQAECgEIAwAAAA==.',
Bi='Bifbafbouf:BAAANQAECggICwAAAA==.Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgQIBAAAAA==.',
Bl='Bleaugro:BAAANQADCggICAAAAA==.Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8pAAITAAcK+yCDHQDFAQATAAcK+yCDHQDFAQAAAA==.Bloodytoutii:BAAANQAECgQIDgAAAA==.',
Bo='Bortman:BAABNQAECn8yAAIPAAoK8CFnDgADAwAPAAoK8CFnDgADAwAAAA==.Boukz:BAAANQADCgcICQAAAA==.Bowowner:BAABNQAECn8dAAIUAAkKSBTFZACzAQAUAAkKSBTFZACzAQAAAA==.',
Br='Brazken:BAAANQADCgUICgAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIIAAYKOho9nwDjAQAIAAYKOho9nwDjAQAAAA==.Buzzball:BAABNQAECn8UAAIIAAYK8RLszwB7AQAIAAYK8RLszwB7AQAAAA==.',
Bw='Bwicked:BAABNQAECn9HAAMKAAoK5RH8TgD8AQAKAAoK/hD8TgD8AQAMAAcKQhHCFABeAQAAAA==.',
Ca='Caroline:BAAANQADCgQIBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAFFAQIBgAMAM0YAA==.Catie:BAAANQAECgIIAgAAAA==.',
Ce='Celonge:BAAANQAECgcICwABNQAECgoKPAAJADUaAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAKAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAACAAAAAA==.Chimpnzthat:BAAANQAECgQIDAAAAA==.Chookicookie:BAABNQAECn9HAAMVAAoKeyG+EgAzAwAVAAoKeyG+EgAzAwAWAAoKoxYGIwAvAgAAAA==.Chrome:BAABNQAECn9EAAMXAAoKSh7sFgCLAgAXAAgKyBzsFgCLAgAYAAoKKhsDEwBdAgAAAA==.',
Ci='Cindyy:BAAANQAFFAEIAQAAAQ==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn8sAAIZAAoKSB9DGgDcAgAZAAoKSB9DGgDcAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgoKIQAXAGQbAA==.Coresh:BAABNQAECn8+AAISAAoKzBxECgDPAgASAAoKzBxECgDPAgAAAA==.Cornpuff:BAAANQAECgcIDgAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAABNQAECn8VAAIKAAYKlwqaJAFOAQAKAAYKlwqaJAFOAQAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgYIDwABNQAECgoKPAAIAKckAA==.Daemonbane:BAAANQAECgQIBAAAAA==.Damessiah:BAAANQAECgcIEAAAAA==.Dark:BAABNQAECn9CAAIaAAoK9yHvDADpAgAaAAoK9yHvDADpAgAAAA==.Darkphyre:BAAANQAECgcIDwAAAA==.Darthtree:BAAANQAECgYIBgAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn87AAMaAAoKeCTGBQChAwAaAAoKeCTGBQChAwAbAAEK+h2XbABGAAAAAA==.Deathtike:BAABNQAECn9AAAIZAAoKpB9mEgBgAgAZAAoKpB9mEgBgAgABNQAECgoKTgAQAMYkAA==.Decius:BAAANQAECgcIDwAAAA==.Deltairlines:BAACNQAFFH8OAAMcAAUK8SBzAwDYAQAcAAUK8SBzAwDYAQAdAAEKXgCjGwAiAAA1AAQKfyAABBwACQp6IeMCABwDABwACQp6IeMCABwDAB0ACQo2EXAbABICAAMAAQqBDQw9ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUIDgAcAPEgAA==.Demagorgin:BAAANQAECgcIEgAAAA==.Deqlyn:BAABNQAECn8hAAIIAAkKjxyHZABtAgAIAAkKjxyHZABtAgAAAA==.Desmus:BAAANQAECgMIDAAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn8/AAIBAAoKehrZDQAYAgABAAoKehrZDQAYAgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAACAAAAAA==.',
Do='Domwarlock:BAABNQAECn8yAAIaAAkK5B5ZMgAYAgAaAAkK5B5ZMgAYAgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doxophil:BAAANQAECgQIBwABNQAECgoKJAAJAJYXAA==.',
Dr='Dragonfloss:BAAANQAECggICAAAAA==.Droax:BAAANQADCgYIBQAAAA==.Droh:BAAANQADCgcIBwAAAA==.Dronin:BAABNQAECn8yAAIeAAoKDxW1EgDfAQAeAAoKDxW1EgDfAQAAAA==.Drpatan:BAAANQAECgQICgAAAA==.Druni:BAAANQAECggIDwAAAA==.Drâkenhân:BAAANQAECgcIDgAAAA==.',
Du='Dumpling:BAAANQAECgYIBgAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMICwAAAA==.',
Ed='Edinburger:BAAANQADCggIIwAAAA==.',
Eh='Ehdawg:BAAANQAECgQICgAAAA==.',
Ei='Eiduartrawr:BAAANQAECggIDwABNQAFFAQICAAUAGoXAA==.Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQAECgUIBAAAAA==.',
El='Elguezo:BAAANQAECgMIBwAAAA==.Ellynna:BAAANQAECgQIBQAAAA==.',
Em='Emokillaz:BAAANQAFFAEIAQAAAA==.',
Ep='Epictaxes:BAAANQAECgYIDwAAAA==.Epsilón:BAAANQAECgYIBwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAABNQAECn8xAAIUAAoKkxxuJQB/AgAUAAoKkxxuJQB/AgAAAA==.Faylan:BAAANQABCgYIBgAAAA==.',
Fe='Feronnia:BAAANQAECgIIAgAAAA==.',
Fi='Fibot:BAABNQAECn9OAAISAAoKSxa2CwC1AgASAAoKSxa2CwC1AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQICAAAAA==.Fistavus:BAAANQABCgQIBAAAAA==.',
Fl='Florasol:BAAANQAECgQIBgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAABNQAECn8bAAIUAAkKXxScOwAsAgAUAAkKXxScOwAsAgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAABNQAECn8bAAIKAAkKrx8CJACTAgAKAAkKrx8CJACTAgABNQAFFAYIEgAHABcmAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIKAAgKaQ6cxgD3AQAKAAgKaQ6cxgD3AQAAAA==.Ganggangx:BAAANQAECgQIBwAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECgoKPgAPAC8VAA==.',
Gh='Ghomertin:BAAANQAECgMICAAAAA==.Ghostpepper:BAAANQABCggIFAAAAA==.',
Gi='Gipsydanger:BAABNQAECn89AAMGAAoKEiOHEABDAwAGAAoKEiOHEABDAwAfAAIKKw1YIABfAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.',
Go='Goldenspoon:BAAANQADCgIIAgABNQAFFAQIBgAMAM0YAA==.Gonnjass:BAAANQADCgYIEwAAAA==.Goragar:BAAANQAECgQIBAAAAA==.Gorlokk:BAEANQAECggICAAAAA==.',
Gr='Grakonys:BAABNQAECn9DAAIDAAoKnAmJCgCJAQADAAoKnAmJCgCJAQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgUIDgAAAA==.Grolof:BAAANQABCgQIBAABNQAECgoKHwAKAMUFAA==.Grunch:BAAANQADCgcIFgAAAA==.Grunnck:BAAANQADCggIMgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAYIGQACAAAAAA==.Guidosarduci:BAAANQADCggICgAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQAECggIBgAAAA==.Harnix:BAAANQAECgQIDAAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn84AAIGAAoKpyDFEAAqAwAGAAoKpyDFEAAqAwAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgYIFAAIAPESAA==.',
He='Hellreines:BAACNQAFFH8MAAIgAAQK9hjjCQDzAAAgAAQK9hjjCQDzAAA1AAQKf0cAAiAACgqrI0UHAB4DACAACgqrI0UHAB4DAAAA.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgQIDgAAAA==.Him:BAAANQAECgUIDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8uAAIGAAkK9CTdEQA6AwAGAAkK9CTdEQA6AwAAAA==.Holyscales:BAAANQAECgYIEgAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Id='Idarae:BAAANQAECgUICAABNQAECgoKLAAZAEgfAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAABNQAECn8fAAIIAAoK/hQjUwD9AQAIAAoK/hQjUwD9AQAAAA==.',
Iv='Ivvy:BAABNQAECn8XAAIYAAoKJQfpNwAfAQAYAAoKJQfpNwAfAQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECn8VAAIhAAkKvwguQQDHAQAhAAkKvwguQQDHAQABNQAECgoKLgAUACEaAA==.Janntro:BAABNQAECn8oAAMiAAkK2RevJwBhAgAiAAkK2RevJwBhAgAQAAEKAADPLQBKAAABNQAECgoKKwALAJUiAA==.Jantra:BAAANQADCgQIBAABNQAECgoKKwALAJUiAA==.Jantro:BAABNQAECn8rAAILAAoKlSJ3BQDiAgALAAoKlSJ3BQDiAgAAAA==.Janttro:BAAANQAECgUIDwABNQAECgoKKwALAJUiAA==.',
Je='Jebby:BAABNQAECn8xAAIKAAoKHxiWUgDxAQAKAAoKHxiWUgDxAQAAAA==.Jeebz:BAAANQAECgUICAABNQAECgoKMQAKAB8YAA==.Jelmarr:BAAANQAECgIIAgAAAA==.Jerauld:BAABNQAECn8VAAIjAAQKKBJLIwD1AAAjAAQKKBJLIwD1AAAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8uAAIgAAkKhRkKKgDQAQAgAAkKhRkKKgDQAQAAAA==.Joshc:BAABNQAECn8qAAILAAcKXAikMQDRAAALAAcKXAikMQDRAAAAAA==.',
Jt='Jt:BAACNQAFFH89AAQaAAoKxyMKAABmAwAaAAoKxyMKAABmAwAbAAIKEyMvBwC4AAAkAAIKCBmwAwC3AAA1AAQKfysAAxsACgobJnIFAMECABoACAogJlwqANsCABsACAqYH3IFAMECAAAA.',
Ju='Judgédred:BAABNQAECn8XAAIIAAgKnhl4TAAQAgAIAAgKnhl4TAAQAgAAAA==.',
['Já']='Ják:BAABNQAECn8kAAMJAAoKlhfpLwAvAgAJAAoKlhfpLwAvAgAIAAEK/gthfQEoAAAAAA==.',
Ka='Kaaris:BAABNQAECn8fAAIbAAgKAQk+CgD0AAAbAAgKAQk+CgD0AAAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kaippe:BAAANQAECgEIAQAAAA==.Kairos:BAABNQAECn9GAAIKAAoKdhELTQABAgAKAAoKdhELTQABAgAAAA==.Kalasta:BAAANQADCgMIAwAAAA==.Kanofworms:BAABNQAECn8gAAINAAoKsAmMaQAZAQANAAoKsAmMaQAZAQAAAA==.Karkea:BAABNQAECn8YAAIZAAgKBCICEQAlAwAZAAgKBCICEQAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8tAAIFAAgKWRdvEQBmAQAFAAgKWRdvEQBmAQAAAA==.Kenner:BAAANQAECggICAAAAA==.',
Ki='Kibil:BAABNQAECn8rAAMIAAoKKg+ZjwAGAgAIAAkKdBCZjwAGAgABAAEKJga8YQAkAAAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8qAAIdAAcKzBzJCwAtAgAdAAcKzBzJCwAtAgAAAA==.Kos:BAACNQAFFH8SAAIHAAYKFyajBAD+AQAHAAYKFyajBAD+AQA1AAQKfzMAAgcACgqLJkIBAHQDAAcACgqLJkIBAHQDAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgoKKwALAJUiAA==.',
Ku='Kujiera:BAABNQAECn8nAAMbAAoK0wjBDQDNAAAbAAoKJAfBDQDNAAAaAAgKtwYorwDBAAAAAA==.Kurick:BAAANQAECggIEgAAAA==.Kurrenter:BAABNQAECn8rAAIJAAoKjx4qIACNAgAJAAoKjx4qIACNAgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn88AAIBAAoK/Q5qJAC9AQABAAoK/Q5qJAC9AQAAAA==.',
La='Laiyth:BAABNQAECn85AAIaAAoKiRLzQQDbAQAaAAoKiRLzQQDbAQAAAA==.Larryfish:BAABNQAECn8tAAMTAAoKKCJFEgA9AgAgAAkKAiAyIwB2AgATAAkKXR5FEgA9AgAAAA==.Lavos:BAABNQAECn8xAAIbAAoKZw6IBACNAQAbAAoKZw6IBACNAQAAAA==.',
Le='Lepracy:BAAANQABCgQICAAAAA==.Levitikus:BAAANQAFFAEIAQAAAA==.Levìtikus:BAAANQAECgUIBQAAAA==.',
Li='Lisster:BAABNQAECn8sAAIUAAoK8h1ZIgCNAgAUAAoK8h1ZIgCNAgAAAA==.Liyra:BAAANQAECgcIEQAAAA==.',
Lo='Loafe:BAABNQAECn8zAAIIAAoKOhZzYQDUAQAIAAoKOhZzYQDUAQAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgcIDwAAAA==.Luxury:BAABNQAECn8zAAIFAAkKlwTFGwDrAAAFAAkKlwTFGwDrAAAAAA==.',
Ly='Lykanthropos:BAAANQAECgYICgAAAA==.Lynster:BAAANQABCgEIAQAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn8qAAINAAoKbA+yOADXAQANAAoKbA+yOADXAQAAAA==.Mako:BAABNQAECn86AAIdAAoKuB/hCQAFAwAdAAoKuB/hCQAFAwAAAA==.Malevian:BAAANQADCgcINgAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn81AAIlAAkKZAy2HgCfAQAlAAkKZAy2HgCfAQAAAA==.Marc:BAABNQAECn8cAAIWAAkK7w8PQACZAQAWAAkK7w8PQACZAQAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAABNQAECn8VAAIHAAkKrQWXLQDhAAAHAAkKrQWXLQDhAAAAAA==.Marvellous:BAAANQADCgUIBQAAAA==.Mazz:BAABNQAECn8VAAIbAAkKRxP3EgDbAQAbAAkKRxP3EgDbAQAAAA==.',
Me='Megana:BAAANQADCgYICwAAAA==.Megaterium:BAABNQAECn8oAAMGAAgKHwxoegAuAQAGAAgKHwxoegAuAQAHAAUK9AfzLwDRAAAAAA==.Meláni:BAAANQAECgQIBgAAAA==.Menethil:BAABNQAECn8aAAIJAAkKyxogUgAkAgAJAAkKyxogUgAkAgAAAA==.',
Mi='Milei:BAAANQAECgYICQAAAA==.Misie:BAAANQABCgIIAQAAAA==.Mispell:BAAANQABCgMIAwAAAA==.Missmisery:BAABNQAECn8oAAMUAAoKNRDxRwAFAgAUAAoKNRDxRwAFAgAmAAQK2ggaDgDMAAAAAA==.Mistaya:BAABNQAECn8rAAIVAAcK0g+kZABWAQAVAAcK0g+kZABWAQAAAA==.Mithdraug:BAAANQAECgcIDgAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAABNQAECn8mAAIEAAkKXAfJiwA0AQAEAAkKXAfJiwA0AQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECggIEgAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
Mu='Mugzee:BAAANQAECgIIAQAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgQIBAAAAA==.',
['Mà']='Màtch:BAAANQADCgcICQABNQAFFAIIBQAJAK4XAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAcIGwADADciAA==.',
Ni='Nightparade:BAABNQAECn8UAAITAAkKVBl6GgDjAQATAAkKVBl6GgDjAQAAAA==.Nishgrail:BAABNQAECn8xAAMLAAoKuyJKBgAtAwALAAoKuyJKBgAtAwAYAAEKbQxLdwA7AAAAAA==.',
No='Nohkal:BAAANQAECgQIBAAAAA==.',
Nu='Nukusmaximus:BAABNQAECn8VAAIKAAQKGQNBCwF7AAAKAAQKGQNBCwF7AAAAAA==.',
Ny='Nyxiie:BAAANQADCgQIBAAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAABNQAECn8VAAIIAAcK+RhLrQDFAQAIAAcK+RhLrQDFAQAAAA==.',
Ok='Oktharun:BAAANQAECggICAAAAA==.',
On='Onex:BAAANQAECgcIDwAAAA==.',
Or='Orangethanos:BAAANQADCggICAAAAA==.Orgrím:BAAANQAECgQIAgAAAA==.Ori:BAAANQAECgQIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAIlAAcKBAwBJwA+AQAlAAcKBAwBJwA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8rAAMWAAgKlg1EkgB3AQAWAAcKhgtEkgB3AQAVAAMKnAEv0QBNAAAAAA==.Persefini:BAABNQAECn8YAAIXAAkKXxSnFgAaAgAXAAkKXxSnFgAaAgAAAA==.Petrodaear:BAAANQADCgYICQABNQADCggIGwACAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAAANQAECgcIDwAAAA==.Philidox:BAAANQADCgYIBgABNQAECgoKJAAJAJYXAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQAECgQIBgAAAA==.Plugugly:BAABNQAECn8rAAIUAAoKbCF5HACrAgAUAAoKbCF5HACrAgAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Popita:BAAANQAECgQICgAAAA==.Popos:BAAANQADCgQIBAAAAA==.Portal:BAAANQADCgIIAgABNQAECgkJHgAGAEYSAA==.Potatobear:BAABNQAECn83AAMUAAoKHCU1HAAnAwAUAAoKHCU1HAAnAwAeAAMKwRK4WwC2AAAAAA==.Powerbeard:BAAANQAECgUICAAAAA==.',
Pr='Praytwothee:BAABNQAECn8lAAIHAAoKJR8WDQAaAwAHAAoKJR8WDQAaAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn83AAQiAAoKxxWhMgAWAgAiAAoKxxWhMgAWAgAPAAYK7gj2RwAVAQAQAAIKUQiVJABJAAAAAA==.',
Ra='Ragedh:BAABNQAECn83AAIPAAoK2iRpAQDZAwAPAAoK2iRpAQDZAwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragna:BAAANQAECgYICgAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAABNQAECn8qAAIUAAkKGRnVKwBkAgAUAAkKGRnVKwBkAgAAAA==.Ravensblood:BAAANQAECgcIDQAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECggICgAAAA==.Reeses:BAEANQADCgcIGwABNQAECggICAACAAAAAA==.Relm:BAAANQADCgYICQAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDgAAAA==.Roglof:BAABNQAECn8fAAIKAAoKxQV+NwEwAQAKAAoKxQV+NwEwAQAAAA==.Rowlah:BAAANQAECgQIDAAAAA==.Rozy:BAABNQAECn9KAAMJAAoKcx+dCgBZAwAJAAoKcx+dCgBZAwAIAAgKlBRfrwDAAQAAAA==.',
Ru='Ruiizu:BAABNQAECn8qAAIIAAcKch6+gQAlAgAIAAcKch6+gQAlAgAAAA==.Ruldas:BAAANQADCgYICQAAAA==.Rushuna:BAABNQAECn9CAAIfAAoKUh+BAACLAwAfAAoKUh+BAACLAwAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAIUAAcKDRLjngDJAQAUAAcKDRLjngDJAQAAAA==.Sairicck:BAABNQAECn80AAIUAAoKxBUyQgAXAgAUAAoKxBUyQgAXAgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgcIDwAAAA==.',
Se='Selenar:BAAANQAECgQIAQAAAA==.Selinora:BAAANQAECggIDQAAAA==.Senaria:BAAANQADCgIIAQAAAA==.Senjia:BAAANQADCgUIBQAAAA==.Serhalatath:BAAANQAECgUIBgAAAA==.',
Sh='Shade:BAABNQAECn8eAAMGAAkKRhJxbQDWAQAGAAkKRhJxbQDWAQAfAAEKQBKaJwA3AAAAAA==.Shadonymph:BAAANQAECgQIDAAAAA==.Shadowsbane:BAABNQAECn8uAAMJAAoKbRVHKABbAgAJAAoKbRVHKABbAgAIAAQKCQvTKAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIIAAcKriKdXACCAgAIAAcKriKdXACCAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwACAAAAAA==.Shamwow:BAABNQAECn80AAIWAAoK3CNpBgA8AwAWAAoK3CNpBgA8AwAAAA==.Shaolinsnake:BAABNQAECn8YAAIEAAkKVRaDUwDQAQAEAAkKVRaDUwDQAQAAAA==.Sharpspoon:BAAANQAECgYICQABNQAFFAQIBgAMAM0YAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAABNQAECn8hAAMXAAoKZBtzDgCcAgAXAAoKZBtzDgCcAgAYAAMK+BYkfADbAAAAAA==.Shiiva:BAAANQAECgUIBQAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQAECggIDQAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8tAAIKAAoK/w9qtwAVAgAKAAoK/w9qtwAVAgAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.Skimm:BAAANQAECggICAAAAA==.Skolmoon:BAAANQADCgYIBwAAAA==.',
Sl='Sloppyjo:BAABNQAECn8zAAIGAAgKwCOMFwDuAgAGAAgKwCOMFwDuAgAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgoKPAAJADUaAA==.Solsti:BAABNQAECn88AAIJAAoKNRpZOQB/AgAJAAoKNRpZOQB/AgAAAA==.Soulhunter:BAACNQAFFH8IAAIZAAQK0REJEQC7AAAZAAQK0REJEQC7AAA1AAQKfyIAAxkACAo7IqMbANICABkACAo7IqMbANICABMAAgqJIlGiALcAAAAA.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgYIBwAAAA==.Spoonbrew:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.Spoondot:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIAwAAAA==.Stillthorny:BAAANQAECgYICQAAAA==.Stinjaga:BAABNQAECn8qAAMMAAcKuRoQGADkAAAKAAcK2hiSyQDyAQAMAAMKjxkQGADkAAAAAA==.Stormyknight:BAAANQAECgUICAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAABNQAECn8uAAIUAAoKIRoTLQBfAgAUAAoKIRoTLQBfAgAAAA==.',
Su='Sunlite:BAAANQABCgYICQAAAA==.Sunrae:BAAANQAECgQIDgAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQAECgIIAgAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAKAGkOAA==.Taryen:BAABNQAECn8qAAMZAAoKUwwLMwBTAQAZAAkKbQ0LMwBTAQATAAEKmwTxgwAnAAABNQAECgoKNwAPANokAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAFFAIIBQAJAK4XAA==.Telaari:BAAANQAECgUIBwAAAA==.Telrander:BAAANQAECgIIAQAAAA==.Teriyl:BAABNQAECn80AAMFAAoK5hQXFwAcAQAEAAoKRQ7DhAAQAgAFAAUKzhwXFwAcAQAAAA==.',
Th='Thalenia:BAABNQAECn88AAIUAAoKIg9mUQDqAQAUAAoKIg9mUQDqAQAAAA==.Thallenia:BAAANQADCggIIQAAAA==.Thalpura:BAAANQADCgYIBwAAAA==.Thalron:BAAANQAECgYICwAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCggIEgAAAA==.Thriller:BAAANQAECgUIBQABNQAFFAIIBQAJAK4XAA==.',
Ti='Tikeidari:BAABNQAECn9OAAIQAAoKxiQaAQCtAwAQAAoKxiQaAQCtAwAAAA==.Tiltedtroll:BAABNQAECn8rAAIWAAkKNgt9WQA/AQAWAAkKNgt9WQA/AQAAAA==.',
To='Tonofcron:BAAANQADCgcIFwAAAA==.Totemeri:BAABNQAECn8yAAMVAAoKOBEieACjAQAVAAoKOBEieACjAQAWAAYKlQ1YowBPAQAAAA==.Toytrux:BAAANQAECgIIAwAAAA==.',
Tr='Trappydk:BAABNQAECn8dAAITAAoKexl9LgB3AgATAAoKexl9LgB3AgAAAA==.Trappydruid:BAAANQAECgYIBwABNQAECgoKHQATAHsZAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQADCggIDgAAAA==.',
Ug='Uglyplug:BAAANQAECgUIBwAAAA==.',
Un='Unagi:BAABNQAECn8aAAIUAAcK/A8qtgCYAQAUAAcK/A8qtgCYAQAAAA==.',
Va='Vak:BAAANQAECgYICQAAAA==.Vaks:BAABNQAECn8ZAAIBAAgKFQ/lIAAzAQABAAgKFQ/lIAAzAQAAAA==.Valezeal:BAAANQAECgQIDAAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8bAAMVAAkKdhSQdgCoAQAVAAYK7xaQdgCoAQAWAAUKzhPSxgAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYIBgAAAA==.Venan:BAAANQAECgYIDgAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgUIBwAAAA==.Venev:BAAANQAECgYICgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAABNQAECn8jAAIIAAoKEBQJZwDGAQAIAAoKEBQJZwDGAQABNQAFFAIIBwAYAD8QAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8qAAIgAAkK1RI0PgDTAQAgAAkK1RI0PgDTAQAAAA==.',
Wa='Wanji:BAABNQAECn8qAAITAAcK0wfGPAD0AAATAAcK0wfGPAD0AAAAAA==.',
We='Wenesday:BAAANQABCgQIBAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGwAVAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQAECgEIAQAAAA==.',
Xa='Xaharst:BAABNQAECn8pAAIZAAgKzxAjXACCAQAZAAgKzxAjXACCAQAAAA==.Xandris:BAAANQAECgYICwAAAA==.Xaya:BAABNQAECn8yAAIaAAoKAhHpXQCBAQAaAAoKAhHpXQCBAQAAAA==.',
Xe='Xenophorge:BAAANQAECgUIDQAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgcIDwAAAA==.',
Xt='Xtayse:BAABNQAECn8zAAIDAAoK6hwOBAB7AgADAAoK6hwOBAB7AgAAAA==.',
Yi='Yirya:BAABNQAECn8yAAMXAAgKdA/bJwBlAQAXAAgKdA/bJwBlAQAYAAEK2gHkvwAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn8xAAILAAkKHiMQBwAZAwALAAkKHiMQBwAZAwAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBQAAAA==.',
Za='Zahel:BAABNQAECn9AAAIIAAoKGCBWJgAsAwAIAAoKGCBWJgAsAwAAAA==.Zandruu:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Zavier:BAABNQAECn8kAAMEAAoKBhdhPwAYAgAEAAoKShZhPwAYAgAOAAUKfhivEgB2AQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAABNQAECn8ZAAIgAAgK5Q0URABJAQAgAAgK5Q0URABJAQAAAA==.',
Zh='Zhee:BAAANQAECgcIDwAAAA==.',
Zo='Zobi:BAAANQAECgIIAgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.',
Zy='Zyde:BAAANQADCgQIBQAAAA==.',
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
