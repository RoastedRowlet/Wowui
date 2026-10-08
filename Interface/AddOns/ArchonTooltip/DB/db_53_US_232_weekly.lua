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

local lookup = {'Unknown-Unknown','Evoker-Devastation','Priest-Holy','Paladin-Retribution','Paladin-Holy','Druid-Guardian','Mage-Frost','Mage-Arcane','Warrior-Fury','Monk-Windwalker','Shaman-Enhancement','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Rogue-Assassination','DemonHunter-Havoc','Warrior-Protection','Hunter-BeastMastery','Rogue-Subtlety','Monk-Mistweaver','Warrior-Arms',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=53,date='2026-10-06',data={Ae='Aelithsong:BAEANQAECgIIAwABNQADCgcICwABAAAAAA==.',
Ah='Aha:BAAANQADCgYICAAAAA==.',
Ai='Aiax:BAABNQAECoEaAAICAAgKQxFOFQDXAQACAAgKQxFOFQDXAQAAAA==.',
Al='Alderok:BAAANQADCgcICAABNQAECgcICwABAAAAAA==.Aliancia:BAAANQAECgYIDwAAAA==.Aloriel:BAAANQAECgEIAQAAAA==.Alydin:BAAANQAECgQJBAAAAA==.',
Am='Amalthea:BAAANQAECgYIBgAAAA==.Amynle:BAAANQAECgQIBAAAAA==.',
An='Anerius:BAAANQABCgMIAwAAAA==.Annora:BAABNQAECoElAAIDAAgKQSDKJAC7AgADAAgKQSDKJAC7AgAAAA==.Antherina:BAAANQADCgEIAQAAAA==.Antonious:BAAANQAECgEIAQAAAA==.',
Ap='Apollyon:BAABNQAECoElAAMEAAgK3yPCQQCqAgAEAAcKkCPCQQCqAgAFAAQKiBYcmQAsAQAAAA==.',
Ar='Ari:BAAANQAECgUIEQAAAA==.Ariioch:BAAANQAECgQIBQAAAA==.Arolz:BAAANQADCgEIAQAAAA==.',
As='Asiago:BAAANQAECgEIAgAAAA==.Assclapiuss:BAABNQAECoEkAAMEAAgK0iOOLQD0AgAEAAgK0iOOLQD0AgAFAAQKSxCYuADhAAAAAA==.Asterchades:BAABNQAECoEqAAIGAAgKzhRUEwDqAQAGAAgKzhRUEwDqAQAAAA==.Asteriou:BAAANQAECgIIAwAAAA==.',
At='Attikus:BAABNQAECoElAAIHAAgKkgcdEQBrAQAHAAgKkgcdEQBrAQAAAA==.Atuan:BAAANQAECgUIBgAAAA==.',
Au='Auralass:BAAANQAECgMIBQAAAA==.Autauga:BAAANQAECgUICAAAAA==.',
Av='Avatard:BAAANQAECgQIBAABNQAECggIHQAIAJIPAA==.Avilla:BAAANQAECgcIEgAAAA==.',
Ax='Axem:BAABNQAECoEbAAIJAAgKzxY/CAA5AgAJAAgKzxY/CAA5AgAAAA==.',
Az='Azhriel:BAAANQADCgIIAgAAAA==.Azulathan:BAAANQAECgUICwAAAA==.',
Ba='Bangpewpew:BAAANQADCgQJBAAAAA==.',
Be='Bechett:BAABNQAECoEfAAIKAAgKGxM9JADVAQAKAAgKGxM9JADVAQAAAA==.Beep:BAAANQAECgIIAgAAAA==.Beerguy:BAAANQADCgcIEQAAAA==.Behemothe:BAABNQAECoEsAAILAAgKPBh+DQB7AgALAAgKPBh+DQB7AgAAAA==.Berníesandrs:BAAANQAECgQICAAAAA==.Beryllos:BAAANQADCggIFwAAAA==.Bewzey:BAAANQAECgcIEgAAAA==.',
Bi='Bittiesxo:BAAANQABCgcICwAAAA==.',
Bl='Bledana:BAAANQADCgQIBAAAAA==.Bloodmourne:BAABNQAECoEUAAIMAAYK8yIxNAA2AgAMAAYK8yIxNAA2AgAAAA==.Bloodytoutii:BAAANQAECgMIBgAAAA==.',
Bo='Bortman:BAABNQAECoEfAAINAAgK/SHaDAAHAwANAAgK/SHaDAAHAwAAAA==.Boukz:BAAANQADCgcIBgAAAA==.Bowowner:BAAANQAECgYIDAAAAA==.',
Br='Brazken:BAAANQADCgUIBQAAAA==.',
Bu='Buhbul:BAAANQAECgUIEgAAAA==.Buzzball:BAAANQAECgUIEAAAAA==.',
Bw='Bwicked:BAABNQAECoEjAAMHAAgKXxK2EQBiAQAIAAgK1Qr7xQDVAQAHAAcKihK2EQBiAQAAAA==.',
Ca='Caroline:BAAANQADCgQJBAAAAA==.Catdamage:BAAANQAECgQIBAABNQAECgUIBQABAAAAAA==.',
Ce='Celonge:BAAANQAECgQIBQABNQAECggILQAFAPkXAA==.Ceremony:BAEANQADCgUJBQABNQAECggIHwAIAGkSAA==.',
Ch='Chamelean:BAAANQADCgUIBQABNQAECgUIDAABAAAAAA==.Chimpnzthat:BAAANQAECgMIBgAAAA==.Chookicookie:BAABNQAECoEkAAMOAAgKHCOOGQDwAgAOAAgKHCOOGQDwAgAPAAcK/xTLXwDSAQAAAA==.Chrome:BAABNQAECoEqAAMQAAgKhRrSFwBbAgAQAAgKhRrSFwBbAgARAAcKWRvkMgAnAgAAAA==.',
Ci='Cindyy:BAAANQAECgcIEQAAAA==.Cini:BAAANQADCgEIAQAAAA==.Cirí:BAABNQAECoEfAAISAAgKjR/6FwDWAgASAAgKjR/6FwDWAgAAAA==.',
Co='Coldbeans:BAAANQAECgEIAQABNQAECgYICQABAAAAAA==.Coresh:BAABNQAECoEmAAILAAgKSxpTDQB+AgALAAgKSxpTDQB+AgAAAA==.Cornpuff:BAAANQAECgUIBQAAAA==.',
Cr='Crickets:BAAANQAECgMIBgAAAA==.Crucifixx:BAAANQADCggIEAAAAA==.',
Cu='Cupsandcakes:BAAANQAECgUIDAAAAA==.',
Da='Dacarry:BAAANQAECgQIBAAAAA==.Dadbody:BAAANQAECgQICgABNQAECggIJAAEANIjAA==.Damessiah:BAAANQADCggICAAAAA==.Dark:BAABNQAECoElAAITAAgKDSIMHQD7AgATAAgKDSIMHQD7AgAAAA==.Darkphyre:BAAANQAECgUIBgAAAA==.Darthtree:BAAANQAECgUIBQAAAA==.',
De='Deadloc:BAAANQADCggIEwAAAA==.Deadmandan:BAABNQAECoErAAMTAAkKTCT/AwCuAwATAAkKTCT/AwCuAwAUAAEK+h2tZgBIAAAAAA==.Deathtike:BAABNQAECoEjAAISAAgKSR9CGQDMAgASAAgKSR9CGQDMAgABNQAECggIKgAVAOwiAA==.Decius:BAAANQAECgUIBgAAAA==.Deltairlines:BAACNQAFFIEKAAMWAAUKnB0TAwC0AQAWAAUKnB0TAwC0AQAXAAEKXgBDGAAkAAA1AAQKgSAABBYACQqvIV0CACgDABYACQqvIV0CACgDABcACQo2EU4YAB8CAAIAAQqBDeg2ADkAAAAA.Deltayaya:BAAANQAECggICgABNQAFFAUICgAWAJwdAA==.Demagorgin:BAAANQAECgYIDgAAAA==.Deqlyn:BAABNQAECoEfAAIEAAgKdxwEUwBzAgAEAAgKdxwEUwBzAgAAAA==.Desmus:BAAANQAECgMIBgAAAA==.Devilmaycry:BAAANQADCggIDAAAAA==.Deáthreaver:BAABNQAECoEiAAIYAAgKsxpUFAA8AgAYAAgKsxpUFAA8AgAAAA==.',
Di='Diddyy:BAAANQAECgMIBQABNQAECgQIBAABAAAAAA==.',
Do='Domwarlock:BAABNQAECoEdAAITAAgKRBokQQByAgATAAgKRBokQQByAgAAAA==.Dots:BAAANQAECgQIBAAAAA==.Doublehungus:BAAANQABCgQIBAAAAA==.Doxophil:BAAANQADCgQIBAABNQAECgcIEgABAAAAAA==.',
Dr='Droax:BAAANQADCgYIBQAAAA==.Dronin:BAABNQAECoEYAAIZAAYKdxS3NAB8AQAZAAYKdxS3NAB8AQAAAA==.Drpatan:BAAANQAECgQIBwAAAA==.Druni:BAAANQAECgUIBgAAAA==.Drâkenhân:BAAANQAECgQIBQAAAA==.',
Du='Dumpling:BAAANQADCgQIBAAAAA==.Durango:BAAANQADCgcIFwAAAA==.',
Ea='Eamon:BAAANQADCggIEQAAAA==.',
Ec='Echowalker:BAAANQAECgMIBQAAAA==.',
Ed='Edinburger:BAAANQADCgYIDgAAAA==.',
Eh='Ehdawg:BAAANQAECgMIBQAAAA==.',
Ei='Eirya:BAAANQADCgEIAQAAAA==.Eivy:BAAANQABCgMIAwAAAA==.',
El='Elguezo:BAAANQAECgEIAQAAAA==.',
Em='Emokillaz:BAAANQADCgcIBwAAAA==.',
Ep='Epictaxes:BAAANQAECgUICQAAAA==.Epsilón:BAEANQADCgcICwAAAA==.',
Es='Esmerr:BAAANQADCggIHwAAAA==.',
Fa='Faxon:BAAANQAECgcIEwAAAA==.',
Fe='Feronnia:BAAANQADCggIFwAAAA==.',
Fi='Fibot:BAABNQAECoEqAAILAAgKFxfzDQBzAgALAAgKFxfzDQBzAgAAAA==.Fireboürne:BAAANQAECgIIAgAAAA==.Fireishot:BAAANQAECgQIBgAAAA==.',
Fl='Florasol:BAAANQAECgIIAgAAAA==.',
Fr='Fraeyah:BAAANQADCgUIBgAAAA==.Frahaad:BAAANQADCgYIBgAAAA==.Frakz:BAAANQADCgYIBwAAAA==.Friede:BAAANQAECgQIDgABNQAFFAQICgAaAJgkAA==.',
['Fè']='Fènrys:BAAANQADCgYICgAAAA==.',
Ga='Galvanize:BAEBNQAECoEfAAIIAAgKaRJcrAAIAgAIAAgKaRJcrAAIAgAAAA==.Gastbubble:BAAANQAECgQIBAAAAA==.',
Ge='Geewetsya:BAAANQAECgIIBAAAAA==.Gengarr:BAAANQADCgMIAwABNQAECggIGAANAAAOAA==.',
Gh='Ghomertin:BAAANQAECgMIBQAAAA==.',
Gi='Gipsydanger:BAABNQAECoErAAMDAAkK2B+IDABMAwADAAkK2B+IDABMAwAbAAIKKw0CHQBhAAAAAA==.',
Gl='Gladiatrix:BAAANQADCgYIBgAAAA==.Glofor:BAAANQADCgUIBQABNQAECggIDgABAAAAAA==.',
Go='Gonnjass:BAAANQADCgYIEgAAAA==.Gorlokk:BAEANQADCgcICAAAAA==.',
Gr='Grakonys:BAABNQAECoEfAAICAAgKmQgMGgCKAQACAAgKmQgMGgCKAQAAAA==.Greed:BAAANQAECgUJCQAAAA==.Grimmbot:BAAANQAECgQICQAAAA==.Grunch:BAAANQADCgUICQAAAA==.Grunnck:BAAANQADCggIIgAAAA==.',
Gu='Guayusa:BAAANQAECgIIAgABNQAFFAUIEAABAAAAAA==.',
Gy='Gypsydanger:BAAANQADCgcICAAAAA==.',
Ha='Habb:BAAANQADCggIEAAAAA==.Harnix:BAAANQAECgMIBAAAAA==.Harryputter:BAAANQABCgYIBgAAAA==.Hawtbooty:BAABNQAECoEeAAIDAAgKwh+kHADnAgADAAgKwh+kHADnAgAAAA==.Hazuul:BAAANQABCgQIBAABNQAECgUIEAABAAAAAA==.',
He='Hellreines:BAABNQAECoEpAAIcAAkKESGACABMAwAcAAkKESGACABMAwAAAA==.Hemolythria:BAAANQADCgIIAgAAAA==.',
Hi='Hildi:BAAANQAECgMIBgAAAA==.Him:BAAANQAECgUJDwAAAA==.Himothy:BAAANQADCgMIAwAAAA==.',
Ho='Holy:BAABNQAECoEiAAIDAAgKeyMkDwA4AwADAAgKeyMkDwA4AwAAAA==.Holyscales:BAAANQAECgQICQAAAA==.Hotmess:BAAANQADCgUIBwAAAA==.',
Hu='Hurcules:BAAANQABCgEIAQAAAA==.',
Ic='Icespirit:BAAANQABCgEIAQAAAA==.',
Ir='Irintha:BAAANQABCgMIAwAAAA==.',
Is='Ishura:BAAANQAECgMIBgAAAA==.',
It='Itslevi:BAAANQAECgMIBQAAAA==.',
Iv='Ivvy:BAAANQAECgUIBwAAAA==.',
Iz='Izanami:BAAANQADCgcIDwAAAA==.',
Ja='Jaffer:BAABNQAECoEVAAIdAAkKGwmVMwDTAQAdAAkKGwmVMwDTAQAAAA==.Janntro:BAABNQAECoEaAAMeAAgK6RcHJgBEAgAeAAgK6RcHJgBEAgAVAAEKOBx2JwBLAAAAAA==.Jantra:BAAANQADCgQIBAABNQAECggIGgAeAOkXAA==.Jantro:BAAANQAECgcIEQABNQAECggIGgAeAOkXAA==.Janttro:BAAANQAECgUICgABNQAECggIGgAeAOkXAA==.',
Je='Jebby:BAABNQAECoEcAAIIAAgKWhQXoAAiAgAIAAgKWhQXoAAiAgAAAA==.Jeebz:BAAANQAECgUICAABNQAECggIHAAIAFoUAA==.Jelmarr:BAAANQADCggIFwAAAA==.Jerauld:BAAANQAECgMIBgAAAA==.',
Ji='Jimmyhoffá:BAAANQAECgEIAQAAAA==.',
Jo='Johnnyzyns:BAABNQAECoEVAAIcAAYK0BXcPwCFAQAcAAYK0BXcPwCFAQAAAA==.Joshc:BAABNQAECoEVAAIGAAYKDgiOKwD0AAAGAAYKDgiOKwD0AAAAAA==.',
Ju='Judgédred:BAAANQADCgYIBgAAAA==.',
['Já']='Ják:BAAANQAECgcIEgAAAA==.',
Ka='Kaaris:BAAANQAECgUIDgAAAA==.Kaiarie:BAAANQAECgIIAwAAAA==.Kainraziel:BAAANQAECgUIDAAAAA==.Kairos:BAABNQAECoElAAIIAAgKiw7XvwDhAQAIAAgKiw7XvwDhAQAAAA==.Kanofworms:BAAANQAECgUIDAAAAA==.Karkea:BAABNQAECoEXAAISAAgKCiN+DQA0AwASAAgKCiN+DQA0AwAAAA==.',
Ke='Kebin:BAABNQAECoEYAAIfAAcKHBUuFAC2AQAfAAcKHBUuFAC2AQAAAA==.',
Ki='Kibil:BAAANQAECgcIEgAAAA==.',
Ko='Koga:BAAANQADCgIIAgAAAA==.Korax:BAAANQADCgUIBAAAAA==.Kortharion:BAABNQAECoEVAAIXAAYKMBXCIgCRAQAXAAYKMBXCIgCRAQAAAA==.Kos:BAACNQAFFIEKAAIaAAQKmCSYBQCpAQAaAAQKmCSYBQCpAQA1AAQKgR0AAhoACQqeJYQEAIMDABoACQqeJYQEAIMDAAAA.',
Kr='Krule:BAAANQADCgYIBgABNQAECggIGgAeAOkXAA==.',
Ku='Kujiera:BAABNQAECoEYAAMUAAgKywX5IwBIAQAUAAcKyQX5IwBIAQATAAYKzQS/zgD/AAAAAA==.Kurick:BAAANQAECgUIDAAAAA==.Kurrenter:BAAANQAECgcIEgAAAA==.',
['Ká']='Kárgorr:BAAANQADCgQIBgAAAA==.',
['Kÿ']='Kÿtten:BAABNQAECoEjAAIYAAgKpBBLIwCaAQAYAAgKpBBLIwCaAQAAAA==.',
La='Laiyth:BAABNQAECoEaAAITAAgKoxMrXAAhAgATAAgKoxMrXAAhAgAAAA==.Larryfish:BAAANQAECgcIEgAAAA==.Lavos:BAABNQAECoEhAAIUAAgKhwxLFADEAQAUAAgKhwxLFADEAQAAAA==.',
Le='Levitikus:BAAANQAECgEIAQAAAA==.',
Li='Lisster:BAABNQAECoEVAAIgAAYKFCHfYAAqAgAgAAYKFCHfYAAqAgAAAA==.Liyra:BAAANQAECgYIEAAAAA==.',
Lo='Loafe:BAABNQAECoEcAAIEAAcKmBR5mAC8AQAEAAcKmBR5mAC8AQAAAA==.Loennicus:BAAANQADCgQIBAAAAA==.Logout:BAAANQADCgQIBAAAAA==.',
Lu='Lurts:BAAANQAECgEIAQAAAA==.Luthais:BAAANQAECgUIBgAAAA==.Luxury:BAABNQAECoEWAAIfAAcKpgMAJAD2AAAfAAcKpgMAJAD2AAAAAA==.',
Ly='Lykanthropos:BAAANQADCggIGAAAAA==.',
Ma='Magmabeard:BAAANQADCggICwAAAA==.Maingauche:BAABNQAECoEbAAIhAAgKhAwNGwDrAQAhAAgKhAwNGwDrAQAAAA==.Mako:BAABNQAECoEfAAIXAAkKch5PCAARAwAXAAkKch5PCAARAwAAAA==.Malevian:BAAANQADCgYIJwAAAA==.Malfuridan:BAAANQAECgQIBAAAAA==.Malocki:BAAANQADCgcIBwAAAA==.Maples:BAABNQAECoEoAAIiAAgKLwxCHgB5AQAiAAgKLwxCHgB5AQAAAA==.Mariasha:BAAANQADCgQIBAAAAA==.Marichika:BAAANQAECgQIBwAAAA==.Mazz:BAAANQAECgYIEQAAAA==.',
Me='Megaterium:BAAANQAECgYIDQAAAA==.Meláni:BAAANQAECgEIAQAAAA==.Menethil:BAAANQAECgYICgAAAA==.',
Mi='Milei:BAAANQAECgIIAgAAAA==.Misie:BAAANQABCgIIAQAAAA==.Missmisery:BAAANQAECgcIEQAAAA==.Mistaya:BAAANQAECgUIEgAAAA==.Mithdraug:BAAANQAECgUIBgAAAA==.',
Mo='Modrem:BAAANQADCgYICQAAAA==.Monache:BAAANQAECgUIDgAAAA==.Mongalf:BAAANQADCgYIBgAAAA==.Moocheala:BAAANQADCgMIAwAAAA==.Mortarîon:BAAANQAECgIIAQAAAA==.',
Ms='Msdktank:BAAANQADCgIIAgAAAA==.',
My='Mystiqwolf:BAAANQAECgQJBAAAAA==.Mythrilblade:BAAANQADCgQICAAAAA==.Myzeel:BAAANQABCgMIAwAAAA==.',
['Mà']='Màtch:BAAANQADCgQIBAABNQAECgkJHgAFAO0aAA==.',
Na='Naavilus:BAAANQADCggICAABNQAFFAUIDgACAIobAA==.',
Ni='Nightparade:BAAANQAECgUIBgAAAA==.Nishgrail:BAABNQAECoEkAAIGAAgKayOvBAA0AwAGAAgKayOvBAA0AwAAAA==.',
No='Nohkal:BAAANQADCgcIEgAAAA==.',
Nu='Nukusmaximus:BAAANQAECgMIBgAAAA==.',
Ny='Nyxiie:BAAANQADCgMIAwAAAA==.Nyxofflimits:BAAANQABCgMIAwAAAA==.',
Od='Odioz:BAAANQAECgcIEAAAAA==.',
On='Onex:BAAANQAECgUIBgAAAA==.',
Or='Ori:BAAANQAECgIIAwAAAA==.',
Oz='Ozmo:BAAANQADCgQIBAAAAA==.',
Pa='Palidinas:BAAANQADCggIFAAAAA==.Pards:BAAANQADCgQIBAAAAA==.Pawmasutra:BAABNQAECoEYAAIiAAcKBAykIgBEAQAiAAcKBAykIgBEAQAAAA==.Paypally:BAAANQABCgYICgAAAA==.',
Pe='Pencil:BAAANQAECgYIDgAAAA==.Persefini:BAAANQAECgIIAgAAAA==.Petrodaear:BAAANQADCgEJAQABNQADCggIGwABAAAAAA==.Petrodrak:BAAANQADCggIGwAAAA==.',
Ph='Pheeguh:BAAANQAECgUIBQAAAA==.Pheylan:BAAANQAECgUIBgAAAA==.Philidox:BAAANQADCgYIBgABNQAECgcIEgABAAAAAA==.Phløw:BAAANQAECgEIAQAAAA==.',
Pl='Plugadin:BAAANQADCgUIBQAAAA==.Plugugly:BAAANQAECgcIEwAAAA==.',
Po='Polinemarois:BAAANQADCgUIAwAAAA==.Portal:BAAANQADCgIIAgABNQAECgYIEQABAAAAAA==.Potatobear:BAABNQAECoEjAAMgAAgK2yQdEwA8AwAgAAgK2yQdEwA8AwAZAAMKwRIZUADAAAAAAA==.',
Pr='Praytwothee:BAABNQAECoEaAAIaAAgKqSB7DwDjAgAaAAgKqSB7DwDjAgAAAA==.',
Qu='Quickbow:BAAANQADCgUIBQAAAA==.Quicktime:BAABNQAECoEmAAMeAAgKbhN2LQALAgAeAAgKbhN2LQALAgANAAYK4wfxPgAjAQAAAA==.',
Ra='Ragedh:BAABNQAECoEdAAINAAgKUiW1BQBxAwANAAgKUiW1BQBxAwAAAA==.Ragequit:BAAANQAECgYICQAAAA==.Ragna:BAAANQADCggICAAAAA==.Ragnoir:BAAANQAECgYIDwAAAA==.Rased:BAAANQAECgUICgAAAA==.Ravensblood:BAAANQAECgUIBQAAAA==.Rawdøg:BAAANQAECgMIAQAAAA==.',
Re='Reddfire:BAAANQAECgYIBwAAAA==.Reeses:BAEANQADCgUICQABNQADCgcICAABAAAAAA==.',
Ro='Robnsparkles:BAAANQABCgUIDAAAAA==.Roglof:BAAANQAECggIDgAAAA==.Rowlah:BAAANQAECgMIBgAAAA==.Rozy:BAABNQAECoErAAMFAAkK4RUXOgBfAgAFAAkK4RUXOgBfAgAEAAcKFBTylwC9AQAAAA==.',
Ru='Ruiizu:BAABNQAECoEVAAIEAAYKBSDncgAaAgAEAAYKBSDncgAaAgAAAA==.Rushuna:BAABNQAECoEdAAIbAAgKZRNdBgAPAgAbAAgKZRNdBgAPAgAAAA==.',
Sa='Saberjaw:BAABNQAECoEXAAIgAAcKxRKYgwDVAQAgAAcKxRKYgwDVAQAAAA==.Sairicck:BAABNQAECoEcAAIgAAcKRxePdgD0AQAgAAcKRxePdgD0AQAAAA==.Santamorte:BAAANQADCgMIAwAAAA==.Sarauco:BAAANQADCgQIBAAAAA==.Sarcasticus:BAAANQAECgUIBgAAAA==.',
Se='Selinora:BAAANQAECgcIDAAAAA==.Serhalatath:BAAANQAECgQIBQAAAA==.',
Sh='Shade:BAAANQAECgYIEQAAAA==.Shadonymph:BAAANQADCggICAAAAA==.Shadowsbane:BAABNQAECoEcAAMFAAcKUBNyYwDJAQAFAAcKUBNyYwDJAQAEAAIKyAScUwFYAAAAAA==.Shaguar:BAABNQAECoEWAAIEAAcKaiJeRgCcAgAEAAcKaiJeRgCcAgAAAA==.Shamhawk:BAAANQADCgMIAwABNQAECgcICwABAAAAAA==.Shamwow:BAABNQAECoEZAAIPAAgK2yC5IwDZAgAPAAgK2yC5IwDZAgAAAA==.Shaolinsnake:BAAANQAECgIIAgAAAA==.Sharpspoon:BAAANQAECgMIAwABNQAECgUIBQABAAAAAA==.Shemonkk:BAAANQADCgUIBwAAAA==.Shiftshow:BAAANQAECgYICQAAAA==.Shiiva:BAAANQAECgQIBAAAAA==.Shinukagé:BAAANQAECgQIBQAAAA==.Shizzite:BAAANQADCggICAAAAA==.',
Si='Silverscream:BAAANQADCgYJBgAAAA==.Singe:BAABNQAECoEdAAIIAAgKkg/RtwDxAQAIAAgKkg/RtwDxAQAAAA==.',
Sk='Skeetsurfin:BAAANQABCgIIAgAAAA==.',
Sl='Sloppyjo:BAABNQAECoEbAAIDAAcKoR0fOgBdAgADAAcKoR0fOgBdAgAAAA==.',
Sm='Smallblackdk:BAAANQAECgIIAgAAAA==.',
So='Solai:BAAANQADCgcICAAAAA==.Solenne:BAAANQADCgcJBwABNQAECggILQAFAPkXAA==.Solsti:BAABNQAECoEtAAIFAAgK+RcbPQBSAgAFAAgK+RcbPQBSAgAAAA==.Soulhunter:BAABNQAECoEfAAMSAAgKsB0EHwCiAgASAAgKsB0EHwCiAgAMAAIKiSIqkwC6AAAAAA==.',
Sp='Spears:BAAANQAECgQIBQAAAA==.Spoiledsoup:BAAANQAECgEIAQAAAA==.Spoondot:BAAANQAECgUIBQAAAA==.',
St='Stainpngolin:BAAANQADCgYIBgAAAA==.Stephe:BAAANQABCgYIBgAAAA==.Stillhorn:BAAANQADCgQIBAAAAA==.Stillthorny:BAAANQABCgQIBAAAAA==.Stinjaga:BAABNQAECoEVAAIIAAYKhRtiwwDaAQAIAAYKhRtiwwDaAQAAAA==.Stormyknight:BAAANQADCgYIBgAAAA==.Strglsngls:BAAANQADCgIIAgAAAA==.Strikerv:BAAANQAECgcIDAABNQAECgkJFQAdABsJAA==.',
Su='Sunrae:BAAANQAECgMIBgAAAA==.',
Sw='Swifty:BAAANQAECgIIAgAAAA==.',
Sy='Sylinsor:BAAANQAECgIIAgAAAA==.Symor:BAAANQADCgcIEwAAAA==.Syxmoo:BAAANQAECgEIAgAAAA==.',
['Så']='Sålty:BAAANQADCgYIBgAAAA==.',
Ta='Taproot:BAEANQADCgcJDgABNQAECggIHwAIAGkSAA==.Taryen:BAAANQAECgcIEgABNQAECggIHQANAFIlAA==.',
Te='Tedo:BAAANQADCgIIAgABNQAECgkJHgAFAO0aAA==.Telaari:BAAANQAECgUIBwAAAA==.Teriyl:BAABNQAECoEdAAMjAAcKuBNAogCcAQAjAAcKhw1AogCcAQAfAAMKchuuJADvAAAAAA==.',
Th='Thalenia:BAABNQAECoEhAAIgAAgKIgw2dgD1AQAgAAgKIgw2dgD1AQAAAA==.Thallenia:BAAANQADCgcIDQAAAA==.Thalron:BAAANQAECgUIBgAAAA==.Thargrim:BAAANQADCgIIAgAAAA==.Thelandra:BAAANQADCgMJAwAAAA==.',
Ti='Tikeidari:BAABNQAECoEqAAIVAAgK7CLeAgAkAwAVAAgK7CLeAgAkAwAAAA==.Tiltedtroll:BAABNQAECoEUAAIPAAYK1AmClQA+AQAPAAYK1AmClQA+AQAAAA==.',
To='Tonofcron:BAAANQADCgYIEwAAAA==.Totemeri:BAABNQAECoEiAAMOAAgKLhFQZgCqAQAOAAgKLhFQZgCqAQAPAAYKAA8NjgBQAQAAAA==.',
Tr='Trappydk:BAAANQAECgcIDgAAAA==.',
Tu='Turbotastic:BAAANQADCgQIBAAAAA==.Turtlesmomm:BAAANQADCgcIBwAAAA==.',
Ug='Uglyplug:BAAANQAECgIIAgAAAA==.',
Un='Unagi:BAAANQAECgYIDAAAAA==.',
Va='Vaks:BAAANQAECgYIBgAAAA==.Valezeal:BAAANQAECgIIAwAAAA==.Vazdun:BAABNQAECoEVAAMOAAcKXhXPkgArAQAOAAQKwxnPkgArAQAPAAUKTA1prgAHAQAAAA==.',
Ve='Vehlahi:BAAANQABCgIIAgAAAA==.Velari:BAAANQADCgQIBAAAAA==.Vemazan:BAAANQABCgYJBgAAAA==.Venan:BAAANQAECgIIAwAAAA==.Venefirous:BAAANQADCgUIBgAAAA==.Venenn:BAAANQAECgIIAgAAAA==.Venev:BAAANQAECgQICQAAAA==.Ventana:BAAANQAECgQJCAAAAA==.Verdilac:BAAANQAECgcICgABNQAECgkJRAARANwcAA==.',
Vi='Vinceglortho:BAAANQADCgcIFAAAAA==.',
Vl='Vlad:BAAANQADCgIIAgAAAA==.',
Vy='Vyranox:BAABNQAECoEcAAIcAAcK8hAwPQCWAQAcAAcK8hAwPQCWAQAAAA==.',
Wa='Wanji:BAABNQAECoEVAAIMAAYK+gRvggDsAAAMAAYK+gRvggDsAAAAAA==.',
Wh='Whiteookami:BAAANQAECgIIAgABNQAECgcIFQAOAF4VAA==.',
Wi='Widginatrix:BAAANQADCgYIBgAAAA==.Wildthangz:BAAANQAECgEIAQAAAA==.Wintyr:BAAANQADCgcIEwAAAA==.',
Xa='Xaharst:BAABNQAECoEYAAISAAcK5hHWUACQAQASAAcK5hHWUACQAQAAAA==.Xandris:BAAANQABCgEIAQAAAA==.Xaya:BAABNQAECoEaAAITAAgKIg40eQDNAQATAAgKIg40eQDNAQAAAA==.',
Xe='Xenophorge:BAAANQAECgMIAwAAAA==.',
Xi='Xiurong:BAAANQADCggIEwAAAA==.',
Xo='Xovace:BAAANQAECgUIBgAAAA==.',
Xt='Xtayse:BAAANQAECgcIEQAAAA==.',
Yi='Yirya:BAABNQAECoEgAAMQAAgKKgvuLAB/AQAQAAgKKgvuLAB/AQARAAEK2gF1rQAhAAAAAA==.',
Yo='Yoruechi:BAABNQAECoEcAAIGAAcKoiLYCAC2AgAGAAcKoiLYCAC2AgAAAA==.Youroverlord:BAAANQADCggJCAAAAA==.',
['Yú']='Yúmyúm:BAAANQAECgIIAgAAAA==.',
Za='Zahel:BAABNQAECoEoAAIEAAgKhyJALQD1AgAEAAgKhyJALQD1AgAAAA==.Zavier:BAAANQAECgcICwAAAA==.',
Ze='Zebajin:BAAANQAECgUJBQAAAA==.Zefiryn:BAAANQABCgIIAgAAAA==.Zeppola:BAAANQAECgMIBAAAAA==.',
Zh='Zhee:BAAANQAECgUIBgAAAA==.',
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
