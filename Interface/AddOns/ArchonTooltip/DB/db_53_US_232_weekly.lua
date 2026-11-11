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

local lookup = {'Paladin-Protection','Unknown-Unknown','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Priest-Holy','Priest-Shadow','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Priest-Discipline','Rogue-Assassination','DemonHunter-Havoc','Druid-Feral','Warlock-Affliction','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-11-10',data={Ae='Aelithsong:BAABNQAECn8YAAIBAAgKpQQ1NwDAAAABAAgKpQQ1NwDAAAABNQAECgYICgACAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8xAAIDAAoKkRItFAALAgADAAoKkRItFAALAgAAAA==.',
Al='Alakthon:BAAANQABCgMIBAAAAA==.Alderok:BAAANQAECgYIBwABNQAECgoKJQAEAKEXAA==.Aliancia:BAABNQAECn89AAIFAAoKgRLADwCiAQAFAAoKgRLADwCiAQAAAA==.Allusive:BAAANQADCgYIAwABNQAECggIEwACAAAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBwAAAA==.Amynle:BAAANQAECgUICQAAAA==.',
An='Anerius:BAAANQAECgEIAQAAAA==.Annora:BAABNQAECn85AAMGAAoKuh1YHwDzAgAGAAoKuh1YHwDzAgAHAAEKPAnmXAA3AAAAAA==.Annorca:BAAANQADCgQIBAABNQAECgoKOQAGALodAA==.Antherina:BAAANQAECgMIAgAAAA==.Antonious:BAAANQAECgYIDgAAAA==.',
Ap='Apollyon:BAABNQAECn9bAAMIAAoK8yTODwAmAwAIAAoK8yTODwAmAwAJAAkKFh48JACRAgAAAA==.',
Ar='Ari:BAABNQAECn8pAAIKAAcKRyNVpgA1AgAKAAcKRyNVpgA1AgAAAA==.Ariioch:BAAANQAECgcIEAAAAA==.Arodar:BAAANQADCgMIAwAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgIIBQAAAA==.Assclapiuss:BAABNQAECn9AAAMIAAoKpyQdEQAfAwAIAAoKpyQdEQAfAwAJAAQKSxAEzgDfAAAAAA==.Asterchades:BAABNQAECn9YAAILAAoKjhb9EAASAgALAAoKjhb9EAASAgAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn9OAAIMAAoKGQftEwBrAQAMAAoKGQftEwBrAQAAAA==.Atuan:BAAANQAECgcIEQAAAA==.',
Au='Auralass:BAAANQAECgMICwAAAA==.Autauga:BAABNQAECn8aAAINAAoKNwzUTACzAQANAAoKNwzUTACzAQAAAA==.',
Av='Avatard:BAAANQAECgcIEgABNQAECgoKLgAKAEEQAA==.Avilla:BAABNQAECn8oAAIGAAoKIB/QIADGAgAGAAoKIB/QIADGAgAAAA==.',
Ax='Axem:BAABNQAECn81AAIOAAoKTRn8BQBZAgAOAAoKTRn8BQBZAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAABNQAECn8nAAMPAAkKKxQKIgB4AQAPAAgKhxMKIgB4AQAQAAIKAxg+KQBCAAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.Batryxamat:BAAANQAECgYICAAAAA==.',
Be='Bechett:BAABNQAECn8gAAIRAAkKaBLXKgDFAQARAAkKaBLXKgDFAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgUIDwAAAA==.Behemothe:BAABNQAECn9RAAISAAoKRRplCgDNAgASAAoKRRplCgDNAgAAAA==.Berníesandrs:BAABNQAECn8fAAIKAAkK4AdguwAdAQAKAAkK4AdguwAdAQAAAA==.Beryllos:BAAANQAECgIIAgAAAA==.Bewzey:BAABNQAECn8mAAIKAAoKQRHOVQACAgAKAAoKQRHOVQACAgAAAA==.',
Bh='Bhadabing:BAAANQAECgQICAAAAA==.',
Bi='Bifbafbouf:BAAANQAECggICwAAAA==.Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgQIBAAAAA==.',
Bl='Bleaugro:BAAANQADCggICAAAAA==.Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8sAAMTAAgKLB+2IQC/AQATAAcK+yC2IQC/AQAUAAMK7RA3dQC5AAAAAA==.Bloodytoutii:BAABNQAECn8ZAAMKAAkKRxq/TwASAgAKAAkKSxm/TwASAgAVAAUKrhyLBQDdAAAAAA==.',
Bo='Bortman:BAABNQAECn8+AAIPAAoKhSRGAwA5AwAPAAoKhSRGAwA5AwAAAA==.Boukz:BAAANQADCgcICQAAAA==.Bowowner:BAABNQAECn8gAAIWAAkKhxmRRwAvAgAWAAkKhxmRRwAvAgAAAA==.',
Br='Brazken:BAAANQADCgUICgAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIIAAYKOho9nwDjAQAIAAYKOho9nwDjAQAAAA==.Buzzball:BAABNQAECn8UAAIIAAYK8RLszwB7AQAIAAYK8RLszwB7AQAAAA==.',
Bw='Bwicked:BAABNQAECn9SAAMKAAoKNRMUUgAMAgAKAAoKTRIUUgAMAgAMAAcKQhHCFABeAQAAAA==.',
Ca='Caroline:BAAANQADCgQIBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAFFAQIBgAMAM0YAA==.Catie:BAAANQAECgIIAgAAAA==.',
Ce='Celonge:BAAANQAECggIEwABNQAECgoKRgAJAAIbAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAKAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDwACAAAAAA==.Chimpnzthat:BAAANQAECgQIEQAAAA==.Chookicookie:BAABNQAECn9RAAMXAAoKeyG+EgAzAwAXAAoKeyG+EgAzAwAYAAoKoxaGKQAnAgAAAA==.Chrome:BAABNQAECn9EAAMZAAoKSh7sFgCLAgAZAAgKyBzsFgCLAgAaAAoKKhvNFQBXAgAAAA==.',
Ci='Cici:BAAANQAECgEIAQAAAA==.Cindyy:BAAANQAFFAEIAgAAAQ==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn8wAAIbAAoKSB9DGgDcAgAbAAoKSB9DGgDcAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAgABNQAECgoKIQAZAGQbAA==.Coresh:BAABNQAECn8/AAISAAoKzBxECgDPAgASAAoKzBxECgDPAgAAAA==.Cornpuff:BAAANQAECgcIEAAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAABNQAECn8VAAIKAAYKlwqaJAFOAQAKAAYKlwqaJAFOAQAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgYIEgABNQAECgoKQAAIAKckAA==.Daemonbane:BAAANQAECgMIBAAAAA==.Damessiah:BAABNQAECn8VAAIGAAgKpxAJZgCVAQAGAAgKpxAJZgCVAQAAAA==.Dark:BAABNQAECn9IAAIcAAoKWiIVCwAJAwAcAAoKWiIVCwAJAwAAAA==.Darkphyre:BAAANQAECgcIEgAAAA==.Darthtree:BAAANQAECgYIBgAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn87AAMcAAoKeCTGBQChAwAcAAoKeCTGBQChAwAdAAEK+h2XbABGAAAAAA==.Deathtike:BAABNQAECn9JAAIbAAoK9SGKBwALAwAbAAoK9SGKBwALAwABNQAECgoKWAAQAPYkAA==.Decius:BAAANQAECgcIEgAAAA==.Deltairlines:BAACNQAFFH8OAAMeAAUK8SBzAwDYAQAeAAUK8SBzAwDYAQAfAAEKXgCjGwAiAAA1AAQKfyIABB4ACQp6IeMCABwDAB4ACQp6IeMCABwDAB8ACQo2EXAbABICAAMAAQqBDQw9ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUIDgAeAPEgAA==.Demagorgin:BAAANQAECgcIEwAAAA==.Deqlyn:BAABNQAECn8rAAIIAAoKJRuVRQBKAgAIAAoKJRuVRQBKAgAAAA==.Desmus:BAAANQAECgMIEQAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn9GAAIBAAoKehqEDwAcAgABAAoKehqEDwAcAgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAACAAAAAA==.',
Do='Domwarlock:BAABNQAECn80AAIcAAkK5B7PRgB+AgAcAAkK5B7PRgB+AgAAAA==.Dots:BAAANQAECgQIBwAAAA==.Doublehungus:BAAANQAECggIAgAAAA==.Doxophil:BAAANQAECgQICAABNQAECgoKMAAJAJYXAA==.',
Dr='Dragonfloss:BAAANQAECggICAAAAA==.Droax:BAAANQADCgYIBQAAAA==.Droh:BAAANQADCgcIBwAAAA==.Dronin:BAABNQAECn8yAAIgAAoKDxX7FADjAQAgAAoKDxX7FADjAQAAAA==.Drpatan:BAAANQAECgUIEgAAAA==.Druni:BAAANQAECgcIEgAAAA==.Drâkenhân:BAAANQAECgcIEQAAAA==.',
Du='Dumpling:BAAANQAECggICAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMIDwAAAA==.',
Ed='Edinburger:BAAANQADCggIIwAAAA==.',
Eh='Ehdawg:BAAANQAECggIEAAAAA==.',
Ei='Eiduartrawr:BAABNQAECn8WAAMEAAoKJBKMVgDoAQAEAAkKJBKMVgDoAQAFAAEKAAB9TgAAAAABNQAFFAQICAAWAGoXAA==.Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQAECgUIBQAAAA==.',
El='Elguezo:BAAANQAECgMICQAAAA==.Ellynna:BAAANQAECgQICgAAAA==.',
Em='Emokillaz:BAAANQAFFAEIAQAAAA==.',
Ep='Epictaxes:BAAANQAECgYIEAAAAA==.Epsilón:BAAANQAECgYICgAAAA==.',
Es='Esmerr:BAAANQAECgEIAwAAAA==.',
Fa='Faxon:BAABNQAECn8yAAIWAAoKkxzWLQB8AgAWAAoKkxzWLQB8AgAAAA==.Faylan:BAAANQABCgYIBgAAAA==.',
Fe='Felshadow:BAAANQAECgEIAgAAAA==.Feronnia:BAAANQAECgIIAgAAAA==.',
Fi='Fibot:BAABNQAECn9YAAISAAoKOxe2CwC1AgASAAoKOxe2CwC1AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQIDAAAAA==.Fistavus:BAAANQABCgQIBAAAAA==.',
Fl='Florasol:BAAANQAECgQICQAAAA==.',
Fr='Fraeyah:BAAANQAECgEIAQAAAA==.Frahaad:BAABNQAECn8hAAIWAAkKxBa5OABYAgAWAAkKxBa5OABYAgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAABNQAECn8bAAIKAAkKrx9nLACCAgAKAAkKrx9nLACCAgABNQAFFAYIEgAHABcmAA==.',
Fu='Furryfury:BAAANQAECgEIAQAAAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIKAAgKaQ6cxgD3AQAKAAgKaQ6cxgD3AQAAAA==.Ganggangx:BAAANQAECgQIBwAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.Gastrophos:BAAANQAECgEIAQAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAFFAQICAAPAAoIAA==.',
Gh='Ghomertin:BAAANQAECgMICwAAAA==.Ghostpepper:BAAANQABCggIFAAAAA==.',
Gi='Gipsydanger:BAABNQAECn9BAAMGAAoKEiOHEABDAwAGAAoKEiOHEABDAwAhAAIKKw1YIABfAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.',
Go='Goldenspoon:BAAANQADCgIIAgABNQAFFAQIBgAMAM0YAA==.Gonnjass:BAAANQAECgEIAQAAAA==.Goragar:BAAANQAECgQIBQAAAA==.Gorlokk:BAEANQAECggICAAAAA==.',
Gr='Grakonys:BAABNQAECn9IAAIDAAoK/AvuCgCkAQADAAoK/AvuCgCkAQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgUIDgAAAA==.Grolof:BAAANQABCgQIBAABNQAECgoKHwAKAMUFAA==.Grunch:BAAANQADCgcIHAAAAA==.Grunnck:BAAANQADCggIOgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAwABNQAFFAgIHAAEACwbAA==.Guidosarduci:BAAANQADCggICgAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQAECggIBwAAAA==.Harnix:BAAANQAECgQIEAAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn84AAIGAAoKpyDUFQAXAwAGAAoKpyDUFQAXAwAAAA==.Hazuul:BAAANQAECgEIAQABNQAECgYIFAAIAPESAA==.',
He='Heavenslight:BAAANQAECgUIBQAAAA==.Hellreines:BAACNQAFFH8PAAIUAAQKFBn8CwDwAAAUAAQKFBn8CwDwAAA1AAQKf0gAAhQACgrcIwQIACEDABQACgrcIwQIACEDAAAA.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgQIEwAAAA==.Him:BAAANQAECgUIEAAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8xAAIGAAkK9CTdEQA6AwAGAAkK9CTdEQA6AwAAAA==.Holyscales:BAAANQAECgYIEwAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQAECgEIAQAAAA==.',
Ic='Icespirit:BAAANQAECgEIAQAAAA==.',
Id='Idarae:BAAANQAECgUICQABNQAECgoKMAAbAEgfAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMICQAAAA==.',
It='Itslevi:BAABNQAECn8pAAIIAAoKbxYXTgAwAgAIAAoKbxYXTgAwAgAAAA==.',
Iv='Ivvy:BAABNQAECn8XAAIaAAoKJQccPgAeAQAaAAoKJQccPgAeAQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECn8VAAIiAAkKvwguQQDHAQAiAAkKvwguQQDHAQABNQAFFAQICAAWAJMMAA==.Janntro:BAABNQAECn8oAAMjAAkK2RevJwBhAgAjAAkK2RevJwBhAgAQAAEKAADPLQBKAAABNQAECgoKKwALAJUiAA==.Jantra:BAAANQADCgQIBAABNQAECgoKKwALAJUiAA==.Jantro:BAABNQAECn8rAAILAAoKlSKSBgDcAgALAAoKlSKSBgDcAgAAAA==.Janttro:BAAANQAECgUIEQABNQAECgoKKwALAJUiAA==.',
Je='Jebby:BAABNQAECn8xAAIKAAoKHxjeXwDoAQAKAAoKHxjeXwDoAQAAAA==.Jeebz:BAAANQAECgUICgABNQAECgoKMQAKAB8YAA==.Jelmarr:BAAANQAECgIIAgAAAA==.Jerauld:BAABNQAECn8VAAIkAAQKKBJLIwD1AAAkAAQKKBJLIwD1AAAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAgAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8xAAIUAAkKgRvjKQD6AQAUAAkKgRvjKQD6AQAAAA==.Joshc:BAABNQAECn8tAAILAAgKvwhEMQD3AAALAAgKvwhEMQD3AAAAAA==.',
Jt='Jt:BAACNQAFFH9BAAQcAAoKMSQPAABiAwAcAAoKMSQPAABiAwAdAAIKEyMvBwC4AAAlAAIKDxqwAwC3AAA1AAQKfywAAx0ACgobJnIFAMECABwACAogJlwqANsCAB0ACAqYH3IFAMECAAAA.',
Ju='Judgédred:BAABNQAECn8bAAMIAAkKZhluRgBHAgAIAAgK+BxuRgBHAgABAAEKbgBQdQACAAAAAA==.',
['Já']='Ják:BAABNQAECn8wAAMJAAoKlhfWLwBQAgAJAAoKlhfWLwBQAgAIAAQKLwuZJwGcAAAAAA==.',
Ka='Kaaris:BAABNQAECn8fAAIdAAgKAQnJCwDwAAAdAAgKAQnJCwDwAAAAAA==.Kaiarie:BAAANQAECgIIBgAAAA==.Kainraziel:BAAANQAECgUIDwAAAA==.Kaippe:BAAANQAECgEIAwAAAA==.Kairos:BAABNQAECn9QAAIKAAoKOhSeRgArAgAKAAoKOhSeRgArAgAAAA==.Kalasta:BAAANQADCgMIAwAAAA==.Kanofworms:BAABNQAECn8gAAINAAoKsAnYdgAjAQANAAoKsAnYdgAjAQAAAA==.Karkea:BAABNQAECn8YAAIbAAgKBCICEQAlAwAbAAgKBCICEQAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8wAAIFAAkK7RXrEACRAQAFAAkK7RXrEACRAQAAAA==.Kenner:BAAANQAECggICAAAAA==.',
Ki='Kibil:BAABNQAECn8rAAMIAAoKKg+ZjwAGAgAIAAkKdBCZjwAGAgABAAEKJgbMaQAkAAAAAA==.',
Kn='Knocksteady:BAAANQAECgEIAgAAAA==.',
Ko='Koga:BAAANQAECgEIAQAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8tAAIfAAgKGRvMCgBuAgAfAAgKGRvMCgBuAgAAAA==.Kos:BAACNQAFFH8SAAIHAAYKFyajBAD+AQAHAAYKFyajBAD+AQA1AAQKfzQAAgcACgqOJnsBAHIDAAcACgqOJnsBAHIDAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgoKKwALAJUiAA==.',
Ku='Kujiera:BAABNQAECn8nAAMdAAoK0wgyEADJAAAdAAoKJAcyEADJAAAcAAgKtwY+wAC9AAAAAA==.Kurick:BAAANQAECggIEwAAAA==.Kurrenter:BAABNQAECn8rAAIJAAoKjx7XKgC8AgAJAAoKjx7XKgC8AgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn9CAAIBAAoKAhBqJAC9AQABAAoKAhBqJAC9AQAAAA==.',
La='Laiyth:BAABNQAECn86AAIcAAoKiRIOTADdAQAcAAoKiRIOTADdAQAAAA==.Larryfish:BAABNQAECn8tAAMTAAoKKCJjFQA0AgAUAAkKAiAyIwB2AgATAAkKXR5jFQA0AgAAAA==.Lavos:BAABNQAECn87AAIdAAoKPBBSBAC7AQAdAAoKPBBSBAC7AQAAAA==.',
Le='Lepracy:BAAANQABCgQICAAAAA==.Levitikus:BAABNQAECn8bAAIWAAoKthp3MQBvAgAWAAoKthp3MQBvAgAAAA==.Levìtikus:BAAANQAECgUIBQAAAA==.',
Li='Lisster:BAABNQAECn8wAAIWAAoKTiB6IgCoAgAWAAoKTiB6IgCoAgAAAA==.Liyra:BAABNQAECn8UAAMJAAkKNhZFjgByAQAJAAcKfxRFjgByAQABAAYKmRc1MABdAQAAAA==.',
Lo='Loafe:BAABNQAECn85AAIIAAoKfxfqXwACAgAIAAoKfxfqXwACAgAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAwAAAA==.Luthais:BAAANQAECgcIEgAAAA==.Luxury:BAABNQAECn84AAIFAAkKsgR1HwDqAAAFAAkKsgR1HwDqAAAAAA==.',
Ly='Lykanthropos:BAAANQAECgYICgAAAA==.Lynster:BAAANQABCgEIAQAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn80AAINAAoKbA+0QADiAQANAAoKbA+0QADiAQAAAA==.Mako:BAABNQAECn9AAAIfAAoKzB/hCQAFAwAfAAoKzB/hCQAFAwAAAA==.Malevian:BAAANQADCgcINgAAAA==.Malfuridan:BAAANQAECgQIBQAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn81AAImAAkKZAy2HgCfAQAmAAkKZAy2HgCfAQAAAA==.Marc:BAABNQAECn8jAAIYAAkKwhAQRACsAQAYAAkKwhAQRACsAQAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAABNQAECn8WAAIHAAoK3QVFLQAFAQAHAAoK3QVFLQAFAQAAAA==.Marvellous:BAAANQADCgUIBQAAAA==.Mazz:BAABNQAECn8VAAIdAAkKRxP3EgDbAQAdAAkKRxP3EgDbAQAAAA==.',
Me='Megana:BAAANQADCgYICwAAAA==.Megaterium:BAABNQAECn8qAAMGAAkKhwuWdgBeAQAGAAkKhwuWdgBeAQAHAAUK9Ae7NQDQAAAAAA==.Meláni:BAAANQAECgQIBgAAAA==.Menethil:BAABNQAECn8cAAIJAAoKFRsgUgAkAgAJAAoKFRsgUgAkAgAAAA==.',
Mi='Milei:BAAANQAECgcICwAAAA==.Misie:BAAANQAECgEIAQAAAA==.Mispell:BAAANQABCgMIAwAAAA==.Missmisery:BAABNQAECn8oAAMWAAoKNRCtUwAOAgAWAAoKNRCtUwAOAgAnAAQK2ggaDgDMAAAAAA==.Mistaya:BAABNQAECn8xAAIXAAgKSg7qZgBqAQAXAAgKSg7qZgBqAQAAAA==.Mithdraug:BAAANQAECgcIEQAAAA==.',
Mo='Modrem:BAAANQAECgEIAQAAAA==.Monache:BAABNQAECn8rAAIEAAkK8wgaigBaAQAEAAkK8wgaigBaAQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECggIEgAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
Mu='Mugzee:BAAANQAECgIIAQAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBQAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQAECgEIAQAAAA==.',
['Mà']='Màtch:BAAANQADCgcICQABNQAFFAIIBQAJAK4XAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAcIGwADADciAA==.',
Ni='Nightparade:BAABNQAECn8VAAITAAkKjRrwGwDyAQATAAkKjRrwGwDyAQAAAA==.Nishgrail:BAABNQAECn8+AAMLAAoKLyR/AwAwAwALAAoKLyR/AwAwAwAaAAEKbQynfwA7AAAAAA==.',
No='Nohkal:BAAANQAECgQICQAAAA==.',
Nu='Nukusmaximus:BAABNQAECn8VAAIKAAQKGQPeHAF1AAAKAAQKGQPeHAF1AAAAAA==.',
Ny='Nyxiie:BAAANQAECgEIAgAAAA==.Nyxofflimits:BAAANQAECgEIAQAAAA==.',
Od='Odioz:BAABNQAECn8VAAIIAAcK+RhLrQDFAQAIAAcK+RhLrQDFAQAAAA==.',
Ok='Oktharun:BAAANQAECggICAAAAA==.',
On='Onex:BAAANQAECgcIEQAAAA==.',
Or='Orangethanos:BAAANQAECgEIAQAAAA==.Orgrím:BAAANQAECgQIAgAAAA==.Ori:BAAANQAECgQIBQAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAImAAcKBAwBJwA+AQAmAAcKBAwBJwA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8uAAMYAAkKxwxEkgB3AQAYAAgK7QpEkgB3AQAXAAMKnAF94QBIAAAAAA==.Persefini:BAABNQAECn8ZAAIZAAkKXxSAGgAcAgAZAAkKXxSAGgAcAgAAAA==.Petrodaear:BAAANQADCgYICgABNQAECgEIAQACAAAAAA==.Petrodrak:BAAANQAECgEIAQAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBgAAAA==.Pheylan:BAAANQAECgcIEgAAAA==.Philidox:BAAANQADCgYIBgABNQAECgoKMAAJAJYXAA==.Phløw:BAAANQAECgEIAgAAAA==.',
Pl='Plugadin:BAAANQAECgQIBgAAAA==.Plugugly:BAABNQAECn8vAAIWAAoKXCKkHADDAgAWAAoKXCKkHADDAgAAAA==.',
Po='Polinemarois:BAAANQAECgEIAgAAAA==.Popita:BAAANQAECgQICgAAAA==.Popos:BAAANQADCgQIBAAAAA==.Portal:BAAANQADCgIIAgABNQAECgkJHgAGAEYSAA==.Potatobear:BAABNQAECn8/AAMWAAoKlSVMBwBLAwAWAAoKlSVMBwBLAwAgAAMKwRK4WwC2AAAAAA==.Powerbeard:BAAANQAECgYIDAAAAA==.',
Pr='Praytwothee:BAABNQAECn8lAAIHAAoKJR8WDQAaAwAHAAoKJR8WDQAaAwAAAA==.',
Qi='Qiursi:BAAANQAECgEIAQAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn89AAQQAAoKxxUcDgBPAQAjAAoKxxWhMgAWAgAQAAYKrxEcDgBPAQAPAAYK7gj2RwAVAQAAAA==.',
Ra='Ragedh:BAABNQAECn83AAIPAAoK2iRpAQDZAwAPAAoK2iRpAQDZAwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragna:BAAANQAECgYICgAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAABNQAECn8wAAIWAAkKCxoPLwB4AgAWAAkKCxoPLwB4AgAAAA==.Ravensblood:BAAANQAECgcIDwAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECggICwAAAA==.Reeses:BAEANQADCgcIGwABNQAECggICAACAAAAAA==.Relm:BAAANQADCgYIDwAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDgAAAA==.Roglof:BAABNQAECn8fAAIKAAoKxQV+NwEwAQAKAAoKxQV+NwEwAQAAAA==.Rowlah:BAAANQAECgQIEAAAAA==.Rozy:BAABNQAECn9NAAMJAAoKcx9RDQBOAwAJAAoKcx9RDQBOAwAIAAgKURVgoQB1AQAAAA==.',
Ru='Ruiizu:BAABNQAECn8tAAIIAAgK7B6jWwANAgAIAAgK7B6jWwANAgAAAA==.Ruldas:BAAANQADCgYICQAAAA==.Rushuna:BAABNQAECn9MAAIhAAoKUh+tAACJAwAhAAoKUh+tAACJAwAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAIWAAcKDRLjngDJAQAWAAcKDRLjngDJAQAAAA==.Sairicck:BAABNQAECn84AAIWAAoKFBc+RwAvAgAWAAoKFBc+RwAvAgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgcIEQAAAA==.',
Se='Selenar:BAAANQAECgIIAQAAAA==.Selinora:BAAANQAECggIEQAAAA==.Senaria:BAAANQADCgIIAQAAAA==.Senjia:BAAANQADCgUIBQAAAA==.Serhalatath:BAAANQAECgUIBwAAAA==.',
Sh='Shade:BAABNQAECn8eAAMGAAkKRhJxbQDWAQAGAAkKRhJxbQDWAQAhAAEKQBKaJwA3AAAAAA==.Shadonymph:BAAANQAECgQIEgAAAA==.Shadowsbane:BAABNQAECn8zAAMJAAoKYhlRHADGAgAJAAoKYhlRHADGAgAIAAYKtArTKAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIIAAcKriKdXACCAgAIAAcKriKdXACCAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcIDAACAAAAAA==.Shamwow:BAABNQAECn85AAIYAAoKWiTXBQBMAwAYAAoKWiTXBQBMAwAAAA==.Shaolinsnake:BAABNQAECn8ZAAIEAAkK5haPWwDYAQAEAAkK5haPWwDYAQAAAA==.Sharpspoon:BAAANQAECgYICQABNQAFFAQIBgAMAM0YAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAABNQAECn8hAAMZAAoKZBtVEQCZAgAZAAoKZBtVEQCZAgAaAAMK+BYkfADbAAAAAA==.Shiiva:BAAANQAECgUIBgAAAA==.Shinukagé:BAAANQAECgQIBwAAAA==.Shizzite:BAAANQAECggIDgAAAA==.',
Si='Siegfriedah:BAAANQAECgEIAQAAAA==.Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8uAAIKAAoKQRBqtwAVAgAKAAoKQRBqtwAVAgAAAA==.',
Sk='Skeetsurfin:BAAANQAECgEIAgAAAA==.Skimm:BAAANQAECggIEAAAAA==.Skolmoon:BAAANQAECgEIAQAAAA==.',
Sl='Sloppyjo:BAABNQAECn82AAIGAAkKFCTTDgBXAwAGAAkKFCTTDgBXAwAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgoKRgAJAAIbAA==.Solsti:BAABNQAECn9GAAIJAAoKAhseHQDBAgAJAAoKAhseHQDBAgAAAA==.Soulhunter:BAACNQAFFH8IAAIbAAQK0RGuFAC1AAAbAAQK0RGuFAC1AAA1AAQKfyIAAxsACAo7IqMbANICABsACAo7IqMbANICABMAAgqJIlGiALcAAAAA.',
Sp='Spears:BAAANQAECgQIBgAAAA==.Spoiledsoup:BAAANQAECgYIBwAAAA==.Spoonbrew:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.Spoondot:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.',
St='Staceyrella:BAAANQAECgEIAQAAAA==.Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIBgAAAA==.Stillthorny:BAAANQAECgYIDQAAAA==.Stinjaga:BAABNQAECn8rAAMMAAgKfBnzGwDgAAAKAAgK4ReSyQDyAQAMAAMKjxnzGwDgAAAAAA==.Stormyknight:BAAANQAECgUIDgAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAACNQAFFH8IAAIWAAQKkwz1EwDhAAAWAAQKkwz1EwDhAAA1AAQKfzIAAhYACgoRG2wrAIUCABYACgoRG2wrAIUCAAAA.',
Su='Sunlite:BAAANQABCgYICQAAAA==.Sunrae:BAAANQAECgQIEwAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQAECgIIAgAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQAECgEIAQABNQAECggIHwAKAGkOAA==.Taryen:BAABNQAECn8qAAMbAAoKUwxNOQBQAQAbAAkKbQ1NOQBQAQATAAEKmwTXjAAnAAABNQAECgoKNwAPANokAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAFFAIIBQAJAK4XAA==.Telaari:BAAANQAECgUICAAAAA==.Telrander:BAAANQAECgIIAwAAAA==.Teriyl:BAABNQAECn84AAMFAAoKdxfsEQCCAQAEAAoKRQ7DhAAQAgAFAAYKRB7sEQCCAQAAAA==.',
Th='Thalenia:BAABNQAECn9DAAIWAAoKfA8wWgD9AQAWAAoKfA8wWgD9AQAAAA==.Thallenia:BAAANQAECgEIAgAAAA==.Thalpura:BAAANQADCgYIBwAAAA==.Thalron:BAAANQAECgcIDgAAAA==.Thargrim:BAAANQADCgMIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCggIEgAAAA==.Thriller:BAAANQAECgUIBQABNQAFFAIIBQAJAK4XAA==.',
Ti='Tikeidari:BAABNQAECn9YAAIQAAoK9iQaAQCtAwAQAAoK9iQaAQCtAwAAAA==.Tiltedtroll:BAABNQAECn8uAAIYAAkKfgyEVQBwAQAYAAkKfgyEVQBwAQAAAA==.',
To='Tonofcron:BAAANQAECgEIBAAAAA==.Totemeri:BAABNQAECn88AAMXAAoKuxMpPwACAgAXAAoKuxMpPwACAgAYAAcKqg2mgAD5AAAAAA==.Toytrux:BAAANQAECgIIAwAAAA==.',
Tr='Trappydk:BAABNQAECn8fAAITAAoKgBl9LgB3AgATAAoKgBl9LgB3AgAAAA==.Trappydruid:BAAANQAECgYIBwABNQAECgoKHwATAIAZAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQAECgEIAQAAAA==.',
Ug='Uglyplug:BAAANQAECgUICQAAAA==.',
Un='Unagi:BAABNQAECn8cAAIWAAgK9Q4qtgCYAQAWAAgK9Q4qtgCYAQAAAA==.',
Va='Vak:BAAANQAECgYICQAAAA==.Vaks:BAABNQAECn8gAAIBAAgKrBbUGACYAQABAAgKrBbUGACYAQAAAA==.Valezeal:BAAANQAECgQIEAAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8bAAMXAAkKdhSQdgCoAQAXAAYK7xaQdgCoAQAYAAUKzhPSxgAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYIBgAAAA==.Venan:BAAANQAECgYIEgAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgQICgAAAA==.Venev:BAAANQAECgYICgAAAA==.Ventana:BAAANQAECgQJCgAAAA==.Verdilac:BAABNQAECn8jAAIIAAoKEBR5fAC/AQAIAAoKEBR5fAC/AQABNQAFFAIICwAaAAoTAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8wAAIUAAkK1RIwNgCzAQAUAAkK1RIwNgCzAQAAAA==.',
Wa='Wanji:BAABNQAECn8tAAITAAgKdQhoOgAcAQATAAgKdQhoOgAcAQAAAA==.',
We='Wenesday:BAAANQABCgQIBAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGwAXAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAgAAAA==.Wintyr:BAAANQAECgEIAQAAAA==.',
Xa='Xaharst:BAABNQAECn8tAAIbAAgKzxAjXACCAQAbAAgKzxAjXACCAQAAAA==.Xandris:BAAANQAECgYIDQAAAA==.Xaya:BAABNQAECn84AAIcAAoKAhHDdAADAgAcAAoKAhHDdAADAgAAAA==.',
Xe='Xenophorge:BAAANQAECgUIEQAAAA==.',
Xi='Xiurong:BAAANQAECgEIAQAAAA==.',
Xo='Xovace:BAAANQAECgcIEgAAAA==.',
Xt='Xtayse:BAABNQAECn85AAIDAAoK6hy0BAB2AgADAAoK6hy0BAB2AgAAAA==.',
Yi='Yirya:BAABNQAECn84AAMZAAgKeg9dLQBnAQAZAAgKeg9dLQBnAQAaAAIK2gHkvwAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn83AAILAAkKTSOWBwDCAgALAAkKTSOWBwDCAgAAAA==.Youroverlord:BAAANQAECgEIAQAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBQAAAA==.',
Za='Zahel:BAABNQAECn9IAAIIAAoKVSCkIwDJAgAIAAoKVSCkIwDJAgAAAA==.Zandruu:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Zavier:BAABNQAECn8lAAMEAAoKoRdXRgAeAgAEAAoK5RZXRgAeAgAOAAUKfhivEgB2AQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBwAAAA==.Zefiryn:BAAANQAECgEIBQAAAA==.Zeppola:BAABNQAECn8bAAIUAAkKCA2bRABwAQAUAAkKCA2bRABwAQAAAA==.',
Zh='Zhee:BAAANQAECgcIEgAAAA==.',
Zo='Zobi:BAAANQAECgIIAgAAAA==.Zomboo:BAAANQAECgcJDQAAAA==.Zotress:BAAANQAECgEIAQAAAA==.',
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
