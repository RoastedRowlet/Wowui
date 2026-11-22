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

local lookup = {'Paladin-Protection','Unknown-Unknown','Evoker-Devastation','Warrior-Arms','Warrior-Protection','Priest-Holy','Priest-Shadow','Paladin-Retribution','Paladin-Holy','Mage-Arcane','Druid-Guardian','Mage-Frost','Rogue-Subtlety','Warrior-Fury','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','DeathKnight-Frost','Mage-Fire','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Rogue-Assassination','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','DemonHunter-Havoc','Priest-Discipline','Druid-Feral','Warlock-Affliction','Monk-Mistweaver','Hunter-Survival',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-11-17',data={Ae='Aelithsong:BAABNQAECn8YAAIBAAgKpQQFOwDAAAABAAgKpQQFOwDAAAABNQAECgYIBwACAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECn8xAAIDAAoKkRItFAALAgADAAoKkRItFAALAgAAAA==.',
Al='Alakthon:BAAANQABCgMIBAAAAA==.Alderok:BAAANQAECgYIBgABNQAECgoKJQAEAKEXAA==.Aliancia:BAABNQAECn9HAAIFAAoK5xILEQCnAQAFAAoK5xILEQCnAQAAAA==.Allusive:BAAANQADCgYIAwABNQAECggIEgACAAAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgUICAAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECn85AAMGAAoKuh1YHwDzAgAGAAoKuh1YHwDzAgAHAAEKPAm3YgA3AAAAAA==.Annorca:BAAANQADCgQIBAABNQAECgoKOQAGALodAA==.Antherina:BAAANQAECgMIAgAAAA==.Antonious:BAAANQAECgYIDQAAAA==.',
Ap='Apollyon:BAABNQAECn9dAAMIAAoK8yRtEgAdAwAIAAoK8yRtEgAdAwAJAAkKFh7zJwCMAgAAAA==.',
Ar='Ari:BAABNQAECn8pAAIKAAcKRyNVpgA1AgAKAAcKRyNVpgA1AgAAAA==.Ariioch:BAAANQAECgcIEgAAAA==.Arodar:BAAANQADCgMIAwAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgIIAgAAAA==.Assclapiuss:BAABNQAECn9GAAMIAAoK/iSIEQAiAwAIAAoK/iSIEQAiAwAJAAQKSxAEzgDfAAAAAA==.Asterchades:BAABNQAECn9eAAILAAoK0xhEDwBDAgALAAoK0xhEDwBDAgAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECn9UAAIMAAoKYAftEwBrAQAMAAoKYAftEwBrAQAAAA==.Atuan:BAAANQAECgcIEgAAAA==.',
Au='Auralass:BAAANQAECgMICAAAAA==.Autauga:BAABNQAECn8aAAINAAoKNwyrVACzAQANAAoKNwyrVACzAQAAAA==.',
Av='Avatard:BAAANQAECgcIEAABNQAECgoKLwAKAEEQAA==.Avilla:BAABNQAECn8oAAIGAAoKIB99JQC8AgAGAAoKIB99JQC8AgAAAA==.',
Ax='Axem:BAABNQAECn84AAIOAAoKTRncBgBOAgAOAAoKTRncBgBOAgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAABNQAECn8oAAMPAAoKohO/HgCuAQAPAAkKAhO/HgCuAQAQAAIKAxj4KwBCAAAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.Batryxamat:BAAANQAECgYICAAAAA==.',
Be='Bechett:BAABNQAECn8gAAIRAAkKaBLXKgDFAQARAAkKaBLXKgDFAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQAECgUIDQAAAA==.Behemothe:BAABNQAECn9RAAISAAoKRRplCgDNAgASAAoKRRplCgDNAgAAAA==.Berníesandrs:BAABNQAECn8hAAIKAAoKogeksQBBAQAKAAoKogeksQBBAQAAAA==.Beryllos:BAAANQAECgIIAgAAAA==.Bewzey:BAABNQAECn8mAAIKAAoKQRHCXAAAAgAKAAoKQRHCXAAAAgAAAA==.',
Bh='Bhadabing:BAAANQAECgQIBwAAAA==.',
Bi='Bifbafbouf:BAAANQAECggICwAAAA==.Bittiesxo:BAAANQABCgcICwAAAA==.',
Bj='Bjôrn:BAAANQAECgMIBAABNQAECgkJGwAIAGYZAA==.',
Bl='Bleaugro:BAAANQADCggICAAAAA==.Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECn8sAAMTAAgKLB+NJAC8AQATAAcK+yCNJAC8AQAUAAMK7RCIfQC2AAAAAA==.Bloodytoutii:BAABNQAECn8eAAMKAAkKexuyTAApAgAKAAkKfxqyTAApAgAVAAUKrhxRBgDcAAAAAA==.',
Bo='Bortman:BAABNQAECn8+AAIPAAoKhSS6AwAxAwAPAAoKhSS6AwAxAwAAAA==.Boukz:BAAANQADCgcICQAAAA==.Bowowner:BAABNQAECn8gAAIWAAkKhxlbUgAoAgAWAAkKhxlbUgAoAgAAAA==.',
Br='Brazken:BAAANQADCgUICgAAAA==.',
Bu='Buhbul:BAABNQAECn8aAAIIAAYKOho9nwDjAQAIAAYKOho9nwDjAQAAAA==.Buzzball:BAABNQAECn8UAAIIAAYK8RLszwB7AQAIAAYK8RLszwB7AQAAAA==.',
Bw='Bwicked:BAABNQAECn9aAAMKAAoKpxOjUgAZAgAKAAoK1hKjUgAZAgAMAAcKQhHCFABeAQAAAA==.',
Ca='Caroline:BAAANQADCgQIBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAFFAQIBgAMAM0YAA==.Catie:BAAANQAECgIIAgAAAA==.',
Ce='Celonge:BAABNQAECn8XAAIWAAoKiw5WYwD/AQAWAAoKiw5WYwD/AQABNQAECgoKRwAJAAIbAA==.Ceremony:BAEANQADCgUIBQABNQAECggIHwAKAGkOAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAACAAAAAA==.Chimpnzthat:BAAANQAECgMIDAAAAA==.Chookicookie:BAABNQAECn9XAAMXAAoKeyG+EgAzAwAXAAoKeyG+EgAzAwAYAAoKoxYuLgAhAgAAAA==.Chrome:BAABNQAECn9KAAMZAAoK9RjsFgCLAgAZAAoK9RjsFgCLAgAaAAoKKht9FwBVAgAAAA==.',
Ci='Cindyy:BAAANQAFFAEIAgAAAQ==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECn82AAIbAAoKSB9DGgDcAgAbAAoKSB9DGgDcAgAAAA==.',
Cl='Clutterbear:BAAANQADCggICAAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgoKIQAZAGQbAA==.Coresh:BAABNQAECn9HAAISAAoKzBxECgDPAgASAAoKzBxECgDPAgAAAA==.Cornpuff:BAABNQAECn8VAAMcAAgK8CApaAAjAgAcAAcKTyIpaAAjAgAdAAEKFBriLgBKAAAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAABNQAECn8VAAIKAAYKlwqaJAFOAQAKAAYKlwqaJAFOAQAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgYIDwABNQAECgoKRgAIAP4kAA==.Daemonbane:BAAANQAECgMIBAAAAA==.Damessiah:BAABNQAECn8VAAIGAAgKpxCIbACXAQAGAAgKpxCIbACXAQAAAA==.Dark:BAABNQAECn9NAAIcAAoKpSKWCQAfAwAcAAoKpSKWCQAfAwAAAA==.Darkphyre:BAABNQAECn8XAAMIAAgKchH6vQBXAQAIAAgKchH6vQBXAQABAAEKAAB+fgAAAAAAAA==.Darthtree:BAAANQAECgYICwAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECn87AAMcAAoKeCTGBQChAwAcAAoKeCTGBQChAwAdAAEK+h2XbABGAAAAAA==.Deathtike:BAABNQAECn9JAAIbAAoK9SFXCAAFAwAbAAoK9SFXCAAFAwABNQAECgoKXgAQAAMlAA==.Decius:BAABNQAECn8XAAIeAAgKnAttGwBJAQAeAAgKnAttGwBJAQAAAA==.Deltairlines:BAACNQAFFH8QAAMfAAYKrRlzAwDYAQAfAAYKrRlzAwDYAQAgAAEKXgCjGwAiAAA1AAQKfyMABB8ACQp6IeMCABwDAB8ACQp6IeMCABwDACAACQo2EXAbABICAAMAAQqBDQw9ADMAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAYIEAAfAK0ZAA==.Demagorgin:BAAANQAECgcIEgAAAA==.Deqlyn:BAABNQAECn8rAAIIAAoKJRt4TgBAAgAIAAoKJRt4TgBAAgAAAA==.Desmus:BAAANQAECgMIDAAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECn9PAAIBAAoKmxrNDQBPAgABAAoKmxrNDQBPAgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAACAAAAAA==.',
Do='Domwarlock:BAABNQAECn81AAIcAAoK5B7PRgB+AgAcAAoK5B7PRgB+AgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doxophil:BAAANQAECggIEAABNQAECgoKNAAJAJYXAA==.',
Dr='Dragonfloss:BAAANQAECggICAAAAA==.Droax:BAAANQADCgYIBQAAAA==.Droh:BAAANQADCgcIBwAAAA==.Dronin:BAABNQAECn8zAAIhAAoKDxWOFgDgAQAhAAoKDxWOFgDgAQAAAA==.Drpatan:BAABNQAECn8VAAIiAAUKvgY5YgCcAAAiAAUKvgY5YgCcAAAAAA==.Druni:BAABNQAECn8ZAAMBAAgKiQ3KLwBgAQABAAgKiQ3KLwBgAQAIAAEKAABL1QEAAAAAAA==.Drâkenhân:BAAANQAECgcIEwAAAA==.',
Du='Dumpling:BAAANQAECggICAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMICwAAAA==.',
Ed='Edinburger:BAAANQADCggIIwAAAA==.',
Eh='Ehdawg:BAAANQAECggIEAAAAA==.',
Ei='Eiduartrawr:BAABNQAECn8aAAMEAAoKPRNjVgD7AQAEAAkKPRNjVgD7AQAFAAEKAABzUwAAAAABNQAFFAQICAAWAGoXAA==.Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQAECgUIBAAAAA==.',
El='Elguezo:BAAANQAECgMIBwAAAA==.Ellynna:BAAANQAECgQIDgAAAA==.Elynie:BAAANQADCggICAAAAA==.',
Em='Emokillaz:BAAANQAFFAEIAQAAAA==.',
Ep='Epictaxes:BAABNQAECn8WAAIYAAcKfxXeZgBSAQAYAAcKfxXeZgBSAQAAAA==.Epsilón:BAAANQAECgYIBwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAABNQAECn8yAAIWAAoKkxwnNQB0AgAWAAoKkxwnNQB0AgAAAA==.Faylan:BAAANQABCgYIBgAAAA==.',
Fe='Feronnia:BAAANQAECgIIAgAAAA==.',
Fi='Fibot:BAABNQAECn9dAAISAAoKOxe2CwC1AgASAAoKOxe2CwC1AgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQICAAAAA==.Fistavus:BAAANQABCgQIBAAAAA==.',
Fl='Florasol:BAAANQAECgQIBgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAABNQAECn8lAAIWAAoKxBa/QABUAgAWAAoKxBa/QABUAgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAABNQAECn8jAAIKAAkKqiEYFAD6AgAKAAkKqiEYFAD6AgABNQAFFAYIEgAHABcmAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECn8fAAIKAAgKaQ6cxgD3AQAKAAgKaQ6cxgD3AQAAAA==.Ganggangx:BAAANQAECgQIBwAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAFFAQICAAPAAoIAA==.',
Gh='Ghomertin:BAAANQAECgMICAAAAA==.Ghostpepper:BAAANQABCggIFAAAAA==.',
Gi='Gipsydanger:BAACNQAFFH8GAAIGAAIKQhZ1KgCSAAAGAAIKQhZ1KgCSAAA1AAQKf0UAAwYACgoSI4cQAEMDAAYACgoSI4cQAEMDACMAAgorDVggAF8AAAAA.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECgoKHwAKAMUFAA==.',
Go='Goldenspoon:BAAANQADCgIIAgABNQAFFAQIBgAMAM0YAA==.Gonnjass:BAAANQADCgYIEwAAAA==.Goragar:BAAANQAECgQIBAAAAA==.Gorlokk:BAEANQAECggICAAAAA==.',
Gr='Grakonys:BAABNQAECn9OAAIDAAoK/AzzCgC4AQADAAoK/AzzCgC4AQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAABNQAECn8aAAIbAAkKpw57LQCdAQAbAAkKpw57LQCdAQAAAA==.Grolof:BAAANQABCgQIBAABNQAECgoKHwAKAMUFAA==.Grunch:BAAANQADCggIJAAAAA==.Grunnck:BAAANQADCggIQgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAgIHQAEACwbAA==.Guidosarduci:BAAANQADCggICgAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQAECggIBgAAAA==.Harnix:BAAANQAECgMIDAAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECn84AAIGAAoKpyCjGQAKAwAGAAoKpyCjGQAKAwAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgYIFAAIAPESAA==.',
He='Heavenslight:BAAANQAECgUIBQAAAA==.Hellreines:BAACNQAFFH8PAAIUAAQKFBkxDgDqAAAUAAQKFBkxDgDqAAA1AAQKf0gAAhQACgrcI0kJABkDABQACgrcI0kJABkDAAAA.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgMIDgAAAA==.Him:BAAANQAECgUIDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECn8xAAIGAAkK9CTdEQA6AwAGAAkK9CTdEQA6AwAAAA==.Holyscales:BAAANQAECgYIEgAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Id='Idarae:BAAANQAECgUICAABNQAECgoKNgAbAEgfAA==.',
In='Interceptor:BAAANQAECgMIAwAAAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAABNQAECn8pAAIIAAoKbxafVwAoAgAIAAoKbxafVwAoAgAAAA==.',
Iv='Ivvy:BAABNQAECn8XAAIaAAoKJQc+QgAeAQAaAAoKJQc+QgAeAQAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECn8VAAIeAAkKvwguQQDHAQAeAAkKvwguQQDHAQABNQAFFAQICAAWAJMMAA==.Janntro:BAABNQAECn8oAAMiAAkK2RevJwBhAgAiAAkK2RevJwBhAgAQAAEKAADPLQBKAAABNQAECgoKKwALAJUiAA==.Jantra:BAAANQADCgQIBAABNQAECgoKKwALAJUiAA==.Jantro:BAABNQAECn8rAAILAAoKlSJLBwDYAgALAAoKlSJLBwDYAgAAAA==.Janttro:BAAANQAECgUIDwABNQAECgoKKwALAJUiAA==.',
Je='Jebby:BAABNQAECn8xAAIKAAoKHxg0gwB4AgAKAAoKHxg0gwB4AgAAAA==.Jeebz:BAAANQAECgUICAABNQAECgoKMQAKAB8YAA==.Jelmarr:BAAANQAECgIIAgAAAA==.Jerauld:BAABNQAECn8VAAIkAAQKKBJLIwD1AAAkAAQKKBJLIwD1AAAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECn8xAAIUAAkKgRuNLgDzAQAUAAkKgRuNLgDzAQAAAA==.Joshc:BAABNQAECn8tAAILAAgKvwhzNQD1AAALAAgKvwhzNQD1AAAAAA==.',
Jt='Jt:BAACNQAFFH9FAAQcAAoKMSQfAABUAwAcAAoKMSQfAABUAwAdAAIKEyMvBwC4AAAlAAIKDxqwAwC3AAA1AAQKfywAAx0ACgobJnIFAMECABwACAogJlwqANsCAB0ACAqYH3IFAMECAAAA.',
Ju='Judgédred:BAABNQAECn8bAAMIAAkKZhl2TwA9AgAIAAgK+Bx2TwA9AgABAAEKbgCHewACAAAAAA==.Justice:BAAANQAECgYIBQAAAA==.',
['Já']='Ják:BAABNQAECn80AAMJAAoKlhf2NgA/AgAJAAoKlhf2NgA/AgAIAAQK6guwMwGfAAAAAA==.',
Ka='Kaaris:BAABNQAECn8fAAIdAAgKAQkbDQDtAAAdAAgKAQkbDQDtAAAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kaippe:BAAANQAECgEIAQAAAA==.Kairos:BAABNQAECn9QAAIKAAoKOhQ1TQAoAgAKAAoKOhQ1TQAoAgAAAA==.Kalasta:BAAANQADCgMIAwAAAA==.Kanofworms:BAABNQAECn8jAAINAAoKsAmjLQBUAQANAAoKsAmjLQBUAQAAAA==.Karkea:BAABNQAECn8YAAIbAAgKBCICEQAlAwAbAAgKBCICEQAlAwAAAA==.',
Ke='Kebin:BAABNQAECn8wAAIFAAkK7RXnEgCNAQAFAAkK7RXnEgCNAQAAAA==.Kenner:BAAANQAECggICAAAAA==.',
Ki='Kibil:BAABNQAECn8rAAMIAAoKKg+ZjwAGAgAIAAkKdBCZjwAGAgABAAEKJgZUbwAkAAAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECn8tAAIgAAgKGRutCwBtAgAgAAgKGRutCwBtAgAAAA==.Kos:BAACNQAFFH8SAAIHAAYKFyajBAD+AQAHAAYKFyajBAD+AQA1AAQKfzUAAgcACgqOJrQBAHEDAAcACgqOJrQBAHEDAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECgoKKwALAJUiAA==.',
Ku='Kujiera:BAABNQAECn8nAAMdAAoK0wguEgDFAAAdAAoKJAcuEgDFAAAcAAgKtwZOygC8AAAAAA==.Kurick:BAAANQAECggIEgAAAA==.Kurrenter:BAABNQAECn8rAAIJAAoKjx7XKgC8AgAJAAoKjx7XKgC8AgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECn9DAAIBAAoKAhBqJAC9AQABAAoKAhBqJAC9AQAAAA==.',
La='Laiyth:BAABNQAECn86AAIcAAoKiRLlUgDbAQAcAAoKiRLlUgDbAQAAAA==.Larryfish:BAABNQAECn8tAAMTAAoKKCKdFwAvAgAUAAkKAiAyIwB2AgATAAkKXR6dFwAvAgAAAA==.Lavos:BAABNQAECn87AAIdAAoKPBDpBAC3AQAdAAoKPBDpBAC3AQAAAA==.',
Le='Lepracy:BAAANQABCgQICAAAAA==.Levitikus:BAABNQAECn8bAAIWAAoKthqlOQBnAgAWAAoKthqlOQBnAgAAAA==.Levìtikus:BAAANQAECgUIBQAAAA==.',
Li='Lisster:BAABNQAECn8wAAIWAAoKTiAmKACfAgAWAAoKTiAmKACfAgAAAA==.Liyra:BAAANQAECggIEwAAAA==.',
Lo='Loafe:BAABNQAECn87AAIIAAoKyxfnaQD8AQAIAAoKyxfnaQD8AQAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAABNQAECn8ZAAIBAAgKrhTRJgCoAQABAAgKrhTRJgCoAQAAAA==.Luxury:BAABNQAECn9AAAIFAAkK8QTCIQDtAAAFAAkK8QTCIQDtAAAAAA==.',
Ly='Lykanthropos:BAAANQAECgYICgAAAA==.Lynster:BAAANQABCgEIAQAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECn80AAINAAoKbA80RwDiAQANAAoKbA80RwDiAQAAAA==.Mako:BAABNQAECn9BAAIgAAoKzB/hCQAFAwAgAAoKzB/hCQAFAwAAAA==.Malevian:BAAANQADCgcINgAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECn81AAImAAkKZAy2HgCfAQAmAAkKZAy2HgCfAQAAAA==.Marc:BAABNQAECn8qAAIYAAoKUhO4MwAHAgAYAAoKUhO4MwAHAgAAAA==.Mariasha:BAAANQADCgUICQAAAA==.Marichika:BAABNQAECn8YAAIHAAoKEwbELwALAQAHAAoKEwbELwALAQAAAA==.Marvellous:BAAANQADCgUIBQAAAA==.Mazz:BAABNQAECn8VAAIdAAkKRxP3EgDbAQAdAAkKRxP3EgDbAQAAAA==.',
Me='Megana:BAAANQADCgYICwAAAA==.Megaterium:BAABNQAECn8qAAMGAAkKhwtYgQBVAQAGAAkKhwtYgQBVAQAHAAUK9AeDOQDQAAAAAA==.Meláni:BAAANQAECgUICwAAAA==.Menethil:BAABNQAECn8cAAIJAAoKFRsgUgAkAgAJAAoKFRsgUgAkAgAAAA==.',
Mi='Milei:BAAANQAECggIDgAAAA==.Misie:BAAANQABCgIIAQAAAA==.Mispell:BAAANQABCgMIAwAAAA==.Missmisery:BAABNQAECn8oAAMWAAoKNRAUXgAMAgAWAAoKNRAUXgAMAgAnAAQK2ggaDgDMAAAAAA==.Mistaya:BAABNQAECn86AAMXAAgKdg6mbABuAQAXAAgKdg6mbABuAQAYAAEKAABZKgEAAAAAAA==.Mithdraug:BAAANQAECgcIEwAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAABNQAECn8rAAIEAAkK8wjxkwBZAQAEAAkK8wjxkwBZAQAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECggIEgAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
Mu='Mugzee:BAAANQAECgEIAQAAAA==.',
My='Mystiqwolf:BAAANQAECgQIBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgQIBAAAAA==.',
['Mà']='Màtch:BAAANQADCgcICQABNQAFFAIIBQAJAK4XAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAcIGwADADciAA==.',
Ni='Nightparade:BAABNQAECn8ZAAITAAkKjRoaHgDxAQATAAkKjRoaHgDxAQAAAA==.Nishgrail:BAABNQAECn9AAAMLAAoKLyTgAwAtAwALAAoKLyTgAwAtAwAaAAEKbQyZhQA7AAAAAA==.',
No='Nohkal:BAAANQAECgUIDQAAAA==.',
Nu='Nukusmaximus:BAABNQAECn8VAAIKAAQKGQNiJgF1AAAKAAQKGQNiJgF1AAAAAA==.',
Ny='Nyxiie:BAAANQADCgQIBAAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAABNQAECn8VAAIIAAcK+RhLrQDFAQAIAAcK+RhLrQDFAQAAAA==.',
Ok='Oktharun:BAAANQAECggICAABNQAECgkJlQAUAB0lAA==.',
On='Onex:BAAANQAECgcIEwAAAA==.',
Or='Orangethanos:BAAANQADCggICAAAAA==.Orgrím:BAAANQAECgQIAgAAAA==.Ori:BAAANQAECgQIBAAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECn8YAAImAAcKBAwBJwA+AQAmAAcKBAwBJwA+AQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAABNQAECn8uAAMYAAkKxwxEkgB3AQAYAAgK7QpEkgB3AQAXAAMKnAH36gBHAAAAAA==.Persefini:BAABNQAECn8ZAAIZAAkKXxRrHQAYAgAZAAkKXxRrHQAYAgAAAA==.Petrodaear:BAAANQADCgYIEAABNQADCggIGwACAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Phaeder:BAAANQADCgMIAwAAAA==.Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAABNQAECn8XAAInAAgK8gefCgAkAQAnAAgK8gefCgAkAQAAAA==.Philidox:BAAANQADCgYIBgABNQAECgoKNAAJAJYXAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQAECgQIBgAAAA==.Plugugly:BAABNQAECn8vAAIWAAoKXCJYIQC6AgAWAAoKXCJYIQC6AgAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Popita:BAAANQAECgQICgAAAA==.Popos:BAAANQADCgQIBAAAAA==.Portal:BAAANQADCgIIAgABNQAECgkJHgAGAEYSAA==.Potatobear:BAABNQAECn8/AAMWAAoKlSX5CABDAwAWAAoKlSX5CABDAwAhAAMKwRK4WwC2AAAAAA==.Powerbeard:BAAANQAECgYIDAAAAA==.',
Pr='Praytwothee:BAABNQAECn8lAAIHAAoKJR8WDQAaAwAHAAoKJR8WDQAaAwAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECn89AAQQAAoKxxWODwBNAQAiAAoKxxWhMgAWAgAQAAYKrxGODwBNAQAPAAYK7gj2RwAVAQAAAA==.',
Ra='Ragedh:BAABNQAECn83AAIPAAoK2iRpAQDZAwAPAAoK2iRpAQDZAwAAAA==.Ragequit:BAAANQAECgYIBAAAAA==.Ragna:BAAANQAECgYICgAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAABNQAECn82AAIWAAkKIhs6LwCHAgAWAAkKIhs6LwCHAgAAAA==.Ravensblood:BAAANQAECgcIEgAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECggICgAAAA==.Reeses:BAEANQADCggIHAABNQAECggICAACAAAAAA==.Relm:BAAANQADCgYIFQAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDgAAAA==.Roglof:BAABNQAECn8fAAIKAAoKxQV+NwEwAQAKAAoKxQV+NwEwAQAAAA==.Rowlah:BAAANQAECgMIDAAAAA==.Rozy:BAABNQAECn9OAAMJAAoKcx9hDwBGAwAJAAoKcx9hDwBGAwAIAAgKURVfrwDAAQAAAA==.',
Ru='Ruiizu:BAABNQAECn8tAAIIAAgK7B7xZQAFAgAIAAgK7B7xZQAFAgAAAA==.Ruldas:BAAANQADCgYICQAAAA==.Rushuna:BAABNQAECn9MAAIjAAoKUh/FAACEAwAjAAoKUh/FAACEAwAAAA==.',
Sa='Saberjaw:BAABNQAECn8XAAIWAAcKDRLjngDJAQAWAAcKDRLjngDJAQAAAA==.Sairicck:BAABNQAECn84AAIWAAoKFBciUAAtAgAWAAoKFBciUAAtAgAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgcIEwAAAA==.',
Se='Selenar:BAAANQAECgIIAQAAAA==.Selinora:BAAANQAECggIDQAAAA==.Senaria:BAAANQADCgIIAQAAAA==.Senjia:BAAANQADCgUIBQAAAA==.Serhalatath:BAAANQAECgUIBgAAAA==.',
Sh='Shade:BAABNQAECn8eAAMGAAkKRhJxbQDWAQAGAAkKRhJxbQDWAQAjAAEKQBKaJwA3AAAAAA==.Shadonymph:BAABNQAECn8bAAIdAAYK9woBFQCyAAAdAAYK9woBFQCyAAAAAA==.Shadowsbane:BAABNQAECn8zAAMJAAoKYhmTIAC7AgAJAAoKYhmTIAC7AgAIAAYKtArTKAHcAAAAAA==.Shaguar:BAABNQAECn8WAAIIAAcKriKdXACCAgAIAAcKriKdXACCAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwACAAAAAA==.Shamwow:BAABNQAECn87AAIYAAoKWiSKBgBKAwAYAAoKWiSKBgBKAwAAAA==.Shaolinsnake:BAABNQAECn8ZAAIEAAkK5hZgYwDWAQAEAAkK5hZgYwDWAQAAAA==.Sharpspoon:BAAANQAECgYICQABNQAFFAQIBgAMAM0YAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAABNQAECn8hAAMZAAoKZBtOEwCVAgAZAAoKZBtOEwCVAgAaAAMK+BYkfADbAAAAAA==.Shiiva:BAAANQAECgUIBQAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQAECggIDQAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECn8vAAIKAAoKQRBqtwAVAgAKAAoKQRBqtwAVAgAAAA==.',
Sk='Skeetsurfin:BAAANQAECgUIBAAAAA==.Skimm:BAAANQAECggIEAAAAA==.Skolmoon:BAAANQADCgYIBwAAAA==.',
Sl='Sloppyjo:BAABNQAECn82AAIGAAkKFCQwEQBQAwAGAAkKFCQwEQBQAwAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcIDgAAAA==.Solenne:BAAANQADCgcJBwABNQAECgoKRwAJAAIbAA==.Solsti:BAABNQAECn9HAAIJAAoKAhs1IQC3AgAJAAoKAhs1IQC3AgAAAA==.Soulhunter:BAACNQAFFH8IAAIbAAQK0RHGFwCvAAAbAAQK0RHGFwCvAAA1AAQKfyIAAxsACAo7IqMbANICABsACAo7IqMbANICABMAAgqJIlGiALcAAAAA.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgYIBwAAAA==.Spoonbrew:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.Spoondot:BAAANQAECgUIBQABNQAFFAQIBgAMAM0YAA==.',
St='Staceyrella:BAAANQAECgEIAQAAAA==.Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQAECgMIAwAAAA==.Stillthorny:BAAANQAECgYICQAAAA==.Stinjaga:BAABNQAECn8rAAMMAAgKfBn7HgDcAAAKAAgK4ReSyQDyAQAMAAMKjxn7HgDcAAAAAA==.Stormyknight:BAAANQAECgQIEAAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAACNQAFFH8IAAIWAAQKkwxZFgDfAAAWAAQKkwxZFgDfAAA1AAQKfzgAAhYACgqkG3cwAIMCABYACgqkG3cwAIMCAAAA.',
Su='Sunlite:BAAANQAECgcIBwAAAA==.Sunrae:BAAANQAECgQIDgAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQAECgIIAgAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.Syzzurp:BAAANQADCgEIAQAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAKAGkOAA==.Taryen:BAABNQAECn8qAAMbAAoKUwyqPQBJAQAbAAkKbQ2qPQBJAQATAAEKmwTIkgAnAAABNQAECgoKNwAPANokAA==.',
Te='Tedo:BAAANQAECgQIBQABNQAFFAIIBQAJAK4XAA==.Telaari:BAAANQAECgUIBwAAAA==.Telrander:BAAANQAECgIIAQAAAA==.Terivor:BAAANQAECgQIBAAAAA==.Teriyl:BAABNQAECn9AAAMFAAoKshtiCQBBAgAFAAgK3h1iCQBBAgAEAAoKRQ7DhAAQAgAAAA==.',
Th='Thalenia:BAABNQAECn9LAAIWAAoK1g+SYAAGAgAWAAoK1g+SYAAGAgAAAA==.Thallenia:BAAANQADCggIIQAAAA==.Thalpura:BAAANQADCgYIBwAAAA==.Thalron:BAAANQAECgcIDwAAAA==.Thargrim:BAAANQADCgMIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.Thelen:BAAANQADCggIEgAAAA==.Thriller:BAAANQAECgUIBQABNQAFFAIIBQAJAK4XAA==.',
Ti='Tikeidari:BAABNQAECn9eAAIQAAoKAyX1AABUAwAQAAoKAyX1AABUAwAAAA==.Tiltedtroll:BAABNQAECn8uAAIYAAkKfgwaXQBwAQAYAAkKfgwaXQBwAQAAAA==.',
To='Tonofcron:BAAANQADCgcIHQAAAA==.Totemeri:BAABNQAECn88AAMXAAoKuxOTRQD9AQAXAAoKuxOTRQD9AQAYAAcKqg1YowBPAQAAAA==.Toytrux:BAAANQAECgIIAwAAAA==.',
Tr='Trappydk:BAABNQAECn8fAAITAAoKgBl9LgB3AgATAAoKgBl9LgB3AgAAAA==.Trappydruid:BAAANQAECgYIBwABNQAECgoKHwATAIAZAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQAECgMIAwAAAA==.',
Ug='Uglyplug:BAAANQAECgUIBwAAAA==.',
Un='Unagi:BAABNQAECn8cAAIWAAgK9Q4qtgCYAQAWAAgK9Q4qtgCYAQAAAA==.',
Va='Vak:BAAANQAECgYICQAAAA==.Vaks:BAABNQAECn8gAAIBAAgKrBa0GwCUAQABAAgKrBa0GwCUAQAAAA==.Valezeal:BAAANQAECgMIDQAAAA==.Van:BAAANQAECgQIBAAAAA==.Vazdun:BAABNQAECn8bAAMXAAkKdhSQdgCoAQAXAAYK7xaQdgCoAQAYAAUKzhPSxgAFAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYIBgAAAA==.Venan:BAAANQAECgYIDgAAAA==.Venefirous:BAAANQAECgIIAgAAAA==.Venenn:BAAANQAECgQICAAAAA==.Venev:BAAANQAECgYICgAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAABNQAECn8jAAIIAAoKEBRNiQC5AQAIAAoKEBRNiQC5AQABNQAFFAMIDgAaAJwSAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECn8xAAIUAAoK1RLcOwCvAQAUAAoK1RLcOwCvAQAAAA==.',
Wa='Wanji:BAABNQAECn8tAAITAAgKdQjTPQAbAQATAAgKdQjTPQAbAQAAAA==.',
We='Wenesday:BAAANQABCgQIBAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgkJGwAXAHYUAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQAECgEIAQAAAA==.',
Xa='Xaharst:BAABNQAECn8tAAIbAAgKzxAjXACCAQAbAAgKzxAjXACCAQAAAA==.Xandris:BAAANQAECgYICwAAAA==.Xaya:BAABNQAECn85AAIcAAoKAhHDdAADAgAcAAoKAhHDdAADAgAAAA==.',
Xe='Xenophorge:BAABNQAECn8WAAIIAAYKwwbTKwGpAAAIAAYKwwbTKwGpAAAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAABNQAECn8XAAIiAAgKjw0yQgAsAQAiAAgKjw0yQgAsAQAAAA==.',
Xt='Xtayse:BAABNQAECn8/AAIDAAoKVx1jBACVAgADAAoKVx1jBACVAgAAAA==.',
Yi='Yirya:BAABNQAECn8/AAMZAAkKcA61LACKAQAZAAkKcA61LACKAQAaAAIK2gHkvwAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECn84AAILAAoKTSNFCADBAgALAAoKTSNFCADBAgAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIBQAAAA==.',
Za='Zahel:BAABNQAECn9IAAIIAAoKVSBWJgAsAwAIAAoKVSBWJgAsAwAAAA==.Zandruu:BAAANQADCgUIBQABNQAECgUICwACAAAAAA==.Zavier:BAABNQAECn8lAAMEAAoKoRcxTAAbAgAEAAoK5RYxTAAbAgAOAAUKfhivEgB2AQAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAABNQAECn8bAAIUAAkKCA09SwBrAQAUAAkKCA09SwBrAQAAAA==.',
Zh='Zhee:BAABNQAECn8ZAAMmAAgKDwuULwDtAAAmAAcKxweULwDtAAARAAcK3wWkQwCdAAAAAA==.',
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
