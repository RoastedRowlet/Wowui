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

local lookup = {'Priest-Holy','Priest-Discipline','Unknown-Unknown','Shaman-Restoration','DeathKnight-Unholy','Monk-Windwalker','Paladin-Retribution','Shaman-Enhancement','Hunter-BeastMastery','DeathKnight-Blood','Warrior-Arms','Warrior-Protection','Warrior-Fury','Mage-Arcane','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Druid-Feral','Warlock-Destruction','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Warlock-Affliction','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Mistweaver','Druid-Guardian','Shaman-Elemental','Evoker-Preservation','Monk-Brewmaster','Mage-Frost','DeathKnight-Frost',}
local provider = {region='US',realm='Shadowsong',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aarazi:BAAANQAECgYIEgAAAA==.',
Ab='Abbinormal:BAAANQADCgUIDAAAAA==.Abolish:BAAANQABCgIIAgAAAA==.',
Ae='Aeriss:BAAANQADCgYIDAAAAA==.Aezili:BAAANQADCgcIBwAAAA==.',
Ag='Agamotto:BAAANQADCgMIAwAAAA==.Agerol:BAAANQAECgUIDQAAAA==.',
Ah='Ahaego:BAAANQAECgIIAwAAAA==.Ahnari:BAAANQAECgEJAQAAAA==.',
Ak='Akkadien:BAAANQAECgcIEQAAAA==.Akumunter:BAAANQAECgYIDQAAAA==.',
Al='Alacardias:BAAANQAECgYIDwAAAA==.Alihuntress:BAAANQADCgQIBQAAAA==.Allthesnacks:BAAANQADCgMIAwAAAA==.',
Am='Amarynth:BAAANQADCgQIBAAAAA==.Amäri:BAABNQAECoEUAAMBAAgKIiRdEwAFAwABAAgKECRdEwAFAwACAAQK1BiCDQAnAQAAAA==.',
An='Anassand:BAAANQAECgYIBwABNQAECgcIDQADAAAAAA==.Andimorph:BAAANQAECgYIDwAAAA==.Angeleria:BAAANQADCgUIBQAAAA==.',
Ap='Apazz:BAAANQAECgcIEgAAAA==.',
Aq='Aqualight:BAAANQAECgIIAgABNQAECggIHwAEAEgiAA==.Aquashade:BAAANQAECgUIBQABNQAECggIHwAEAEgiAA==.Aquaterra:BAABNQAECoEfAAIEAAgKSCLJEgAHAwAEAAgKSCLJEgAHAwAAAA==.Aquina:BAAANQAECgQJBgABNQAECggIHwAEAEgiAA==.',
Ar='Arakadia:BAABNQAECoEhAAIFAAgKfBGCOgDVAQAFAAgKfBGCOgDVAQAAAA==.Artoriaz:BAAANQADCgcJCwAAAA==.Aruteeru:BAAANQAECgUICwAAAA==.',
As='Aseanna:BAAANQAECgIIAwAAAA==.Astraen:BAAANQADCgQIBgAAAA==.',
Au='Augmentussy:BAAANQADCggICAABNQAECgkJHQAGAAslAA==.Auxiliater:BAAANQADCgEIAQAAAA==.Auxiliator:BAAANQADCgYIBgAAAA==.Auxlox:BAAANQADCgcIBwAAAA==.Auxshadow:BAAANQABCgIIAgABNQADCgYIBgADAAAAAA==.',
Av='Avarous:BAAANQAECgUIDQAAAA==.',
Ax='Axará:BAAANQADCgQIBAAAAA==.Axel:BAAANQADCgUIBwAAAA==.',
Ay='Ayala:BAABNQAFFIEHAAIHAAMKgRsIDAANAQAHAAMKgRsIDAANAQAAAA==.',
Az='Azaireos:BAAANQADCgYIDQAAAA==.Azulpunkt:BAABNQAECoEYAAIIAAkKNBbACgCPAgAIAAkKNBbACgCPAgAAAA==.',
Ba='Baddaboomkin:BAAANQADCgEIAQAAAA==.Bananashamma:BAAANQAECgUIDwAAAA==.Barbedwire:BAAANQAECgEIAQAAAA==.',
Be='Bearmao:BAABNQAECoEbAAIJAAgKMBzVKAC5AgAJAAgKMBzVKAC5AgAAAA==.Beknight:BAABNQAECoEYAAIKAAgKxxrjHgCGAgAKAAgKxxrjHgCGAgAAAA==.Belfas:BAAANQAECgIIAwAAAA==.Bellah:BAAANQABCgIIAgAAAA==.Bellybutton:BAAANQAECgMIBAAAAA==.',
Bi='Bigpeach:BAAANQADCgEIAQAAAA==.Biltong:BAAANQAECgMIAwAAAA==.',
Bl='Blackpink:BAAANQADCgUIBQAAAA==.Bludnite:BAABNQAECoEfAAIKAAgKIhyzJwBJAgAKAAgKIhyzJwBJAgAAAA==.',
Bo='Bokchoi:BAAANQAECgUIBQAAAA==.Boom:BAAANQADCgQICAAAAA==.',
Br='Brey:BAAANQAECgEJAQAAAA==.Bruute:BAABNQAECoEhAAILAAkKViKYEgBaAwALAAkKViKYEgBaAwAAAA==.',
Bu='Budplatinum:BAAANQAECgMIAwAAAA==.',
['Bå']='Båcon:BAAANQABCgQIBAAAAA==.',
Ca='Cairo:BAABNQAECoEeAAMMAAgKfCFKBwCfAgAMAAcKVyJKBwCfAgALAAgKvByEPQCZAgAAAA==.Capitalchaos:BAABNQAECoEUAAINAAYKOhmcCgDSAQANAAYKOhmcCgDSAQABNQAECgkJIQAOAK8NAA==.Capnbeni:BAAANQADCgMIAwAAAA==.Cassandraa:BAAANQADCgQIBwAAAA==.Castingchaos:BAABNQAECoEhAAIOAAkKrw2WjgAhAgAOAAkKrw2WjgAhAgAAAA==.',
Ce='Cell:BAABNQAECoEgAAIPAAgKFyEeAwDzAgAPAAgKFyEeAwDzAgAAAA==.Ceviche:BAAANQAECgYJCAAAAA==.Ceàrrdòrn:BAAANQAECgMIBgAAAA==.',
Ch='Chibí:BAAANQADCggIFgAAAA==.Chillzmatic:BAAANQAECgIIBAAAAA==.Chudbucket:BAAANQAECgYIEQAAAA==.',
Ci='Cirillø:BAAANQABCggICAABNQAECggIGwAQAJUkAA==.',
Cl='Clovergold:BAABNQAECoEbAAIHAAkKAhttNwCsAgAHAAkKAhttNwCsAgAAAA==.Clyde:BAAANQAECgYIEgAAAA==.',
Co='Corbis:BAEANQAECgYIEQAAAA==.',
Cr='Crevarus:BAAANQADCgUJDAAAAA==.Crimsonjeybi:BAAANQAECgcJCAAAAA==.Crunchwich:BAAANQADCggIDgAAAA==.',
Cu='Cutename:BAAANQADCgEIAQAAAA==.',
Cy='Cynamyn:BAAANQADCggIDgAAAA==.',
Cz='Czeskilight:BAAANQADCgIIAgAAAA==.',
['Cö']='Cömet:BAAANQADCgcICAAAAA==.',
Da='Daane:BAAANQADCgYIDQAAAA==.Daevarys:BAAANQADCgIIAgAAAA==.Dakhran:BAAANQADCgIJBAAAAA==.Dan:BAAANQAECgEIBAAAAA==.Darkdemon:BAAANQAECgQJBgAAAA==.Darlord:BAAANQADCggIDgAAAA==.Dawnliht:BAAANQADCgIIAgAAAA==.',
De='Deagle:BAAANQABCgIIBAABNQAECgkJHQAGAAslAA==.Deedubbya:BAAANQADCgcIBwAAAA==.Delryd:BAAANQADCggIDgAAAA==.Demônlock:BAAANQADCggICwAAAA==.Desideria:BAAANQAECgUICAAAAA==.Despondence:BAABNQAECoEWAAIRAAgKWBurFQCHAgARAAgKWBurFQCHAgAAAA==.Desynn:BAAANQAECgYJDgAAAA==.',
Di='Divinesyn:BAAANQADCgYIBgAAAA==.',
Dj='Djelysium:BAAANQADCggICwAAAA==.Djtaki:BAABNQAECoEhAAISAAgK8xdsGwBNAgASAAgK8xdsGwBNAgAAAA==.',
Do='Dogwater:BAAANQADCgYIBgABNQAFFAUIDAATAOEgAA==.Doncarlos:BAABNQAECoElAAIJAAkKXh52FgATAwAJAAkKXh52FgATAwAAAA==.Dorn:BAAANQADCgUIBQAAAA==.Dotty:BAAANQAECgEIAQAAAA==.Dottzz:BAAANQADCgYIBgAAAA==.Downbeatxo:BAECNQAFFIEQAAMUAAYKNxAFAgD2AAAUAAMKOhAFAgD2AAAVAAMKNBCAFQDlAAA1AAQKgSIAAxUACQq+IZUeANkCABUACAq0IZUeANkCABQABAomGoAnACUBAAAA.',
Dr='Drdevoted:BAAANQADCgIIAgAAAA==.Dròòid:BAAANQADCgQJBAABNQAECggIHwAKACIcAA==.',
Du='Dubdred:BAAANQAECgIIAgAAAA==.Duhon:BAAANQADCgQIBAAAAA==.Dumptruck:BAAANQAECggIDQAAAA==.',
Dw='Dwín:BAAANQAECgcIEwAAAA==.',
['Dê']='Dêals:BAAANQAECgYIEgAAAA==.',
Ed='Edgelordxx:BAAANQADCgcIBwAAAA==.',
El='Elasper:BAAANQADCgcIBwAAAA==.Eliselyia:BAAANQADCgQIEAAAAA==.Ellierose:BAAANQAECgcICwAAAA==.',
Em='Ems:BAAANQAECgEIAQAAAA==.',
En='Enjin:BAABNQAECoEfAAMJAAgKThtEOAB9AgAJAAgK+hpEOAB9AgAWAAMK2xtmCwDOAAAAAA==.Enragedbeef:BAAANQAECgUIBQABNQAECggIJQAXADUZAA==.Entheogen:BAAANQAECgUJCQAAAA==.',
Eo='Eogan:BAAANQADCgIIAwAAAA==.',
Ep='Epichuntard:BAAANQAECgEIAQAAAA==.',
Er='Erolas:BAAANQADCgQIBwAAAA==.',
Et='Ethereall:BAAANQAECgcIEQAAAA==.',
Ev='Evalilly:BAAANQADCgYIBgAAAA==.Evanessance:BAAANQADCgEIAQAAAA==.Evilice:BAABNQAECoEZAAIHAAcKQA1PlACQAQAHAAcKQA1PlACQAQAAAA==.Evoka:BAAANQAECgEIAgAAAA==.',
Fa='Faavibear:BAAANQAECggJAQAAAA==.Fallendevout:BAAANQAECgQICAAAAA==.Fallentroll:BAABNQAECoEdAAMFAAkKzRkzJQBcAgAFAAkKPBkzJQBcAgAKAAMK4RpYcQDhAAAAAA==.Fatdoinkers:BAAANQADCgYIBgABNQAECggIDQADAAAAAA==.Fatman:BAAANQADCgQIBAABNQADCgIIAwADAAAAAA==.Faydark:BAAANQADCgQIBAAAAA==.Fayia:BAAANQADCgYIBgAAAA==.Fayye:BAAANQAECgIIAgAAAA==.',
Fi='Fireflydh:BAAANQADCgYIBgABNQAECgIIBAADAAAAAA==.Firragol:BAAANQABCgYICgAAAA==.Firèflyjd:BAAANQAECgIIBAAAAA==.Fishstick:BAAANQADCggIEAAAAA==.',
Fl='Floatpass:BAABNQAECoEfAAIOAAkKahvDPwDlAgAOAAkKahvDPwDlAgAAAA==.',
Fo='Foot:BAAANQADCgcJCQAAAA==.',
Fr='Frizz:BAAANQADCgcJAwAAAA==.Froey:BAEANQAECgMIAwAAAA==.',
Fu='Fuzzypally:BAAANQAECgcJDgAAAA==.Fuzzytotems:BAAANQAECgcIBwAAAA==.',
['Fá']='Fáavi:BAAANQAECgQIBAAAAA==.',
Ga='Gali:BAAANQADCgQJBAABNQAECggIHwAKACIcAA==.Galiagante:BAAANQADCggJDAAAAA==.Gallynna:BAABNQAECoEbAAQVAAcKYxNDZQDYAQAVAAcKYxNDZQDYAQAUAAIKzQ/9UQB0AAAYAAIK5woCHQBeAAAAAA==.Galorfax:BAAANQAECgUIDQAAAA==.Galushi:BAAANQADCgYIDQAAAA==.Garm:BAABNQAECoEZAAIJAAgKfB96JQDIAgAJAAgKfB96JQDIAgABNQAECgkJIQALAFYiAA==.',
Ge='Gelinea:BAAANQADCgMICQAAAA==.Genovese:BAEANQADCgYJDAABNQAECgYIEQADAAAAAA==.',
Gi='Gilgaroth:BAABNQAECoEUAAMZAAgKahORFAAfAgAZAAgKmhGRFAAfAgASAAYKUQ9dNACMAQAAAA==.Girlslove:BAAANQADCgIIAgABNQAFFAUIDAATAOEgAA==.',
Go='Gobo:BAAANQAECgUIDAAAAA==.',
Gr='Graysonn:BAAANQADCggIFQAAAA==.Greafox:BAAANQAECggIEQAAAA==.Grrimreaperr:BAAANQADCgcIBwAAAA==.Grýla:BAAANQADCgUIBQAAAA==.',
Gu='Guildenstern:BAAANQAECgYIBgABNQAFFAUIDAATAOEgAA==.Gundrakk:BAAANQAECgQICAAAAA==.Gunnr:BAAANQAECgQICQABNQAECgYICwADAAAAAA==.Gunthorian:BAAANQAECgMJAwAAAA==.',
He='Heart:BAAANQAECgUIAwABNQAECgYICAADAAAAAA==.Heid:BAAANQADCgYIDQAAAA==.Helldozer:BAAANQADCgcIBwAAAA==.',
Hi='Higanbana:BAACNQAFFIEQAAIRAAUKwhk3BADBAQARAAUKwhk3BADBAQA1AAQKgSoAAhEACQraI60EAH0DABEACQraI60EAH0DAAAA.Himawari:BAAANQAECgYIEwABNQAFFAUIEAARAMIZAA==.Himejoshi:BAACNQAFFIEMAAITAAUK4SBrAADrAQATAAUK4SBrAADrAQA1AAQKgS4AAhMACQqdJpUAAN4DABMACQqdJpUAAN4DAAAA.Hippocampus:BAAANQAECgQIBwAAAA==.Hirys:BAABNQAECoEXAAIZAAgKIxLNFAAcAgAZAAgKIxLNFAAcAgAAAA==.',
Ho='Holybeks:BAAANQAECgEIAQABNQAECggIGAAKAMcaAA==.Holydaddy:BAAANQADCgcIBwAAAA==.Holysmite:BAAANQAECgQIBAABNQAECgcIBAADAAAAAA==.Hotdoggin:BAAANQADCgEIAQABNQAECggIDQADAAAAAA==.',
Hu='Huntfosho:BAAANQADCggICAAAAA==.',
['Há']='Háldrin:BAABNQAECoEjAAMaAAkKbSAdDAD2AgAaAAkK1h8dDAD2AgAJAAEKNCbcAQFiAAAAAA==.',
Ia='Iamprepared:BAAANQABCgEIAQAAAA==.',
Ic='Icybacon:BAAANQADCggICAAAAA==.Icëcrëam:BAAANQADCggICAAAAA==.',
Ih='Ihavegrass:BAAANQAECgMIBQAAAA==.',
Im='Imbue:BAAANQAECgYIEAAAAA==.Imbuer:BAAANQAECgQIBAAAAA==.',
In='Innil:BAAANQAECgcIEgAAAA==.',
Je='Jessix:BAAANQAECgEIAQAAAA==.Jezebel:BAAANQAECgUICgAAAA==.',
Ji='Jimfowler:BAAANQADCgIIAgAAAA==.Jirito:BAAANQAECgMJAwAAAA==.',
Jo='Jomadead:BAAANQAECgUJBgABNQAECgkJFgAEAIEUAA==.Jomas:BAABNQAECoEWAAIEAAkKgRQ4PAAlAgAEAAkKgRQ4PAAlAgAAAA==.Jovaar:BAAANQADCgYIBgAAAA==.',
Ju='Judera:BAABNQAECoEWAAIHAAUKfh0xlACQAQAHAAUKfh0xlACQAQABNQAECggICAADAAAAAA==.Juditis:BAAANQABCgUJBQAAAA==.',
Ka='Kagura:BAAANQABCgcIBwAAAA==.Kaing:BAAANQAECgQIBQAAAA==.Kaladen:BAAANQAECgcIDwAAAA==.Kalec:BAAANQADCgUJBQAAAA==.Kalysti:BAAANQAECgMIBgAAAQ==.Kaoticnature:BAAANQADCgQIBwAAAA==.Karolg:BAAANQAECgMIBQAAAA==.Katostrafic:BAAANQAECgYIEQAAAA==.Katrynna:BAAANQADCgQICAAAAA==.',
Ke='Kelarra:BAAANQADCgQIBgAAAA==.',
Kh='Khromscarin:BAABNQAECoElAAMPAAkKziAGAgBCAwAPAAkKziAGAgBCAwARAAcKgA5eKgCwAQAAAA==.',
Ki='Killidan:BAABNQAECoEYAAIRAAgKmRwIEwCnAgARAAgKmRwIEwCnAgAAAA==.Kirklees:BAAANQADCggIDgAAAA==.Kitsuchan:BAAANQAECgMIAwABNQAECggIGgAbALAkAA==.',
Ko='Kodama:BAAANQAECgYIEAAAAA==.Koi:BAAANQADCgcIEgABNQAECgcIGwAPAEgeAA==.Kookiemon:BAAANQADCgcIDQAAAA==.Kookiesplz:BAAANQADCggJCAAAAA==.Kopili:BAAANQADCgUIBwAAAA==.',
Kr='Kromag:BAAANQADCgYIBgAAAA==.',
Ku='Kunpochiken:BAAANQABCgEIAQABNQAECgYIEQADAAAAAA==.',
Ky='Kyanna:BAAANQADCggIDQAAAA==.',
La='Ladifantasie:BAAANQADCgUIBQAAAA==.Laria:BAAANQAECgUIDQAAAA==.Laxinmedium:BAAANQADCgYIDQAAAA==.',
Le='Leenei:BAAANQADCggIDgAAAA==.Lenlaar:BAAANQADCggICwAAAA==.Levande:BAAANQAECgcIBwAAAA==.',
Li='Lifeblume:BAAANQADCgUIBQAAAA==.Lilithandria:BAAANQAECgcICwAAAA==.Linamar:BAAANQADCggIJwAAAA==.',
Lo='Loaq:BAABNQAECoEgAAMBAAgKjROmRQAIAgABAAgKjROmRQAIAgACAAMK4ggkFgCNAAAAAA==.Longbottom:BAAANQAECgUJBQABNQAECggIDQADAAAAAA==.Lorbert:BAAANQADCgQIAwABNQAECggIHAALAPQUAA==.Lostalot:BAAANQAECgYIEAAAAA==.',
Lu='Luxæterna:BAABNQAECoEhAAIHAAkKZBlSQgCEAgAHAAkKZBlSQgCEAgAAAA==.',
Ly='Lyphiara:BAAANQADCggIGgABNQAECgcIGwAcABQiAA==.',
Ma='Malice:BAABNQAECoEVAAMYAAgK0xPABgD1AQAYAAgK0xPABgD1AQAUAAIKZAX6XQBTAAAAAA==.Mandwandos:BAAANQAECgYIDQAAAA==.Maraliss:BAAANQAECgIIAwAAAA==.',
Me='Melaunis:BAAANQADCgYICwAAAA==.Meowzer:BAAANQAECgQIBwABNQAECggIJQAXADUZAA==.Meteora:BAABNQAECoEYAAIMAAkK2RnhCABzAgAMAAkK2RnhCABzAgAAAA==.',
Mi='Mideel:BAAANQADCggIDgAAAA==.Migolbearcow:BAABNQAECoEaAAIdAAgKphnNCgBOAgAdAAgKphnNCgBOAgAAAA==.Missed:BAAANQAECgIJAwAAAA==.Missedweaver:BAAANQADCgYICAABNQAECgIJAwADAAAAAA==.Missrae:BAAANQADCgYICgAAAA==.',
Ml='Mlglock:BAAANQADCgMIAwAAAA==.',
Mo='Moiira:BAAANQAECgEIAQAAAA==.Monyshot:BAAANQADCgUICwAAAA==.Mooniè:BAAANQAECgIIAwAAAA==.Moosenuts:BAAANQAECgIJAwAAAA==.Moriavus:BAABNQAECoEdAAIYAAgKDhoqAwCUAgAYAAgKDhoqAwCUAgAAAA==.Morocha:BAAANQAECgUIDAAAAA==.Mortèm:BAAANQAECgIIAgAAAA==.',
Mu='Muragore:BAAANQAECgIIAwAAAA==.',
My='Mychropien:BAAANQAECgYIDQAAAA==.Myylus:BAAANQADCgYIDwAAAA==.',
['Mö']='Mökes:BAABNQAECoEjAAIUAAkKkCIFAQCJAwAUAAkKkCIFAQCJAwAAAA==.',
Na='Nadroj:BAAANQADCgUIDQAAAA==.Nancydru:BAAANQADCgYIBgAAAA==.Naosu:BAAANQADCgEJAQAAAA==.Nax:BAAANQAECgQIBAAAAA==.Nazzersaurus:BAAANQAECgYIEAAAAA==.',
Ne='Nec:BAAANQADCgcIEQAAAA==.Necrøtic:BAAANQAECgcIEAAAAA==.Nekosmasta:BAAANQABCgIIAgAAAA==.Neodin:BAAANQADCggIJwAAAA==.Nevermiss:BAAANQAECgYIEAAAAA==.',
Ni='Nightjewel:BAAANQADCgYIDQAAAA==.',
No='Noggs:BAAANQADCggIDwAAAA==.Notmewasyou:BAAANQAECgUIDgAAAA==.',
Nu='Nuali:BAAANQAECgYIDAAAAA==.Numi:BAAANQADCggIDQAAAA==.',
Od='Odysseus:BAAANQADCgUICQAAAA==.',
Ok='Okameshiz:BAAANQADCggJDQAAAA==.',
On='Onlyspins:BAAANQAECgYIBwAAAA==.',
Or='Orý:BAABNQAECoEgAAIeAAgKbhswLACPAgAeAAgKbhswLACPAgAAAA==.',
Os='Oslatem:BAAANQADCgcIBwAAAA==.',
Ox='Oxosorrel:BAAANQABCggIEAAAAA==.',
Oz='Ozzmodious:BAAANQADCgUICwAAAA==.',
Pa='Paladan:BAABNQAECoEZAAIQAAgKsCALCQDUAgAQAAgKsCALCQDUAgAAAA==.Palagi:BAAANQAECgMIBgAAAA==.Pallu:BAAANQADCgQIBAAAAA==.Pallyana:BAAANQAECgUIDwAAAA==.Pallymcbeall:BAAANQAECgEIAQAAAA==.Paprikaman:BAAANQADCggICwAAAA==.Parallax:BAAANQADCgEIAQAAAA==.Pariahrain:BAAANQAECgQIBwABNQAECgcIEwADAAAAAA==.Parishealton:BAAANQAECggIEgAAAA==.Payday:BAAANQADCgYICwAAAA==.Pazzuzu:BAAANQADCgUIBQAAAA==.',
Pe='Perprotrus:BAAANQADCgQIBAABNQAECggIHwAKACIcAA==.',
Po='Poulsbo:BAAANQADCgcJBgAAAA==.Pozole:BAAANQAECgcIDQAAAA==.',
Pr='Prominence:BAAANQAECgUIDwAAAA==.Promisques:BAAANQADCgYJEAAAAA==.Prozak:BAAANQAECgYIEAAAAA==.',
Pw='Pwomf:BAAANQAECgYJBgAAAA==.',
Py='Pyrolily:BAAANQAECgQICQAAAA==.',
Qu='Question:BAAANQADCgIIAwAAAA==.Qulung:BAAANQADCggIFAAAAA==.',
Ra='Rabyd:BAAANQADCggICAAAAA==.Raegasm:BAAANQADCgYIBgAAAA==.Raha:BAAANQAECgEIAQAAAA==.Ramue:BAAANQADCgcIDgAAAA==.Raskela:BAABNQAECoEYAAMcAAgKLhL6EwDnAQAcAAgKLhL6EwDnAQAGAAcKKBMAIwCxAQAAAA==.Rastakan:BAAANQAECgEIAQABNQAECgkJIQALAFYiAA==.Razal:BAAANQADCgUIBQAAAA==.',
Re='Reesespiecez:BAAANQAECgcJCwAAAA==.Rellidana:BAAANQADCgcJBgAAAA==.Remove:BAAANQAECgUIBQAAAA==.Retradormi:BAAANQADCggIDQAAAA==.Rexi:BAABNQAECoEhAAIXAAkK/w7zHAAQAgAXAAkK/w7zHAAQAgAAAA==.',
Ri='Rickcando:BAAANQAECgUICAAAAA==.Ricshard:BAAANQAECgUIDwAAAA==.Ridjeckgron:BAAANQADCgcIBwAAAA==.',
Rm='Rmft:BAAANQADCgQICgABNQAECgUIDQADAAAAAA==.',
Ro='Roomnboard:BAAANQAECgEIAQAAAA==.Roughluver:BAAANQADCgYIBgABNQAECggIJQAXADUZAA==.',
Ru='Ruben:BAAANQADCgEIAgAAAA==.Rungar:BAAANQAECgEIAQAAAA==.',
Rv='Rvoker:BAAANQADCgQIBAAAAA==.',
Ry='Rylia:BAAANQADCgcIBwAAAA==.Ryuk:BAAANQADCgMIAwAAAA==.Ryñ:BAAANQADCgMIAwAAAA==.',
['Rà']='Ràein:BAAANQAECgQIDQAAAA==.',
['Ró']='Ród:BAABNQAECoEiAAIHAAgKrh9gQwCAAgAHAAgKrh9gQwCAAgAAAA==.',
['Rø']='Røth:BAAANQADCgYIDAAAAA==.',
Sa='Saalira:BAAANQADCgcIEAAAAA==.Sabellice:BAAANQAECgUIDwAAAA==.Sakonna:BAABNQAECoEfAAIXAAkKCxU0FwBaAgAXAAkKCxU0FwBaAgAAAA==.Salinoria:BAAANQAECgQICQABNQAECgYIDAADAAAAAA==.Sandymaw:BAAANQADCgIIAgABNQAECggIJQAXADUZAA==.Sarlius:BAABNQAECoEgAAIJAAgKUCYJCgBtAwAJAAgKUCYJCgBtAwAAAA==.Sassybuns:BAAANQABCgQIBAAAAA==.Satyrical:BAAANQAECgYICAAAAA==.Savin:BAAANQAECgIIAwAAAA==.',
Sc='Scavenger:BAAANQAECgQIBQAAAA==.Scrumptiøus:BAAANQADCggICQABNQAECgYIEQADAAAAAA==.',
Se='Selkamonk:BAABNQAECoEbAAIcAAcKFCIPCwCfAgAcAAcKFCIPCwCfAgAAAA==.Seniorbold:BAAANQAECgcIDAAAAA==.Sentrina:BAABNQAECoEmAAIfAAkKSRx7CgDaAgAfAAkKSRx7CgDaAgAAAA==.Seraph:BAAANQAECgEIAgAAAA==.Seshy:BAABNQAECoElAAIXAAgKNRmoFwBUAgAXAAgKNRmoFwBUAgAAAA==.Seshymutedme:BAAANQAECgcICwABNQAECggIJQAXADUZAA==.',
Sh='Shamanagins:BAAANQADCgEIAQAAAA==.Shannon:BAAANQADCgYIBgABNQAECgIIAgADAAAAAA==.Shannoon:BAAANQAECgMIAwAAAA==.Sharr:BAAANQADCgYJDAAAAA==.Shekzeer:BAABNQAECoEdAAQGAAkKCyUFBgBQAwAGAAgKZyUFBgBQAwAcAAYKeRoMFQDVAQAgAAIKCSPdGwDJAAAAAA==.Shiverr:BAAANQAECgUIDQAAAA==.Shockakan:BAAANQABCgQIBAAAAA==.Shockazulu:BAAANQADCgIIAgAAAA==.Shocktard:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.',
Si='Siatraz:BAAANQADCggICAABNQAECgIIBAADAAAAAA==.Siegatrox:BAAANQADCgIIAQAAAA==.Silgan:BAAANQADCgYIBgAAAA==.Silverbain:BAAANQADCgQIBAAAAA==.',
Sk='Skizem:BAAANQABCgcIDgAAAA==.Skott:BAAANQADCggIJQAAAA==.',
Sl='Sleepadin:BAAANQAECgcIDQAAAA==.Sleepyr:BAAANQAECgYIDQAAAA==.',
Sn='Snowi:BAAANQADCgYIBgABNQAECgYICwADAAAAAA==.Snowstorm:BAAANQAECgEIAQAAAA==.',
So='Soakra:BAAANQAECgcIEwAAAA==.Solignis:BAACNQAFFIEPAAMNAAUKOSViAAC2AQANAAQKDyRiAAC2AQALAAQKcx21CwCPAQA1AAQKgTIAAw0ACQr6JgQAACUEAA0ACQr6JgQAACUEAAsACQp8JroCANwDAAAA.Soniviolence:BAAANQAECgcIEwAAAA==.Soohots:BAAANQAECgYICwAAAA==.',
Sp='Sparklehappy:BAAANQAECgUICQAAAA==.',
St='Stausa:BAAANQADCgcIBwAAAA==.Stormcreek:BAAANQAECgQIBAAAAA==.Storri:BAABNQAECoEiAAMBAAgKHxcHPAAxAgABAAgKHxcHPAAxAgAXAAUKngbbQQDLAAAAAA==.',
Su='Sufferinhero:BAAANQADCggICAABNQAECgkJJQAPAM4gAA==.Suzuya:BAAANQADCgcJEQAAAA==.',
Sw='Swiftmage:BAACNQAFFIEPAAMhAAUKTyA9AADoAQAhAAUKESA9AADoAQAOAAQKMhtaFgBkAQA1AAQKgTQAAyEACQqjJggAABMEACEACQqjJggAABMEAA4ACQoLJaALAJwDAAAA.Switchboard:BAAANQADCgYICgAAAA==.',
Sy='Sygh:BAAANQAECgEIAQABNQAECgYICAADAAAAAA==.Syndragonkin:BAAANQAECgYIEQAAAA==.Syndrome:BAAANQADCggIDgAAAA==.Synger:BAAANQADCgUICwAAAA==.',
Ta='Taima:BAAANQABCgEIAQAAAA==.Talyndis:BAACNQAFFIEaAAIaAAcKMyHUAAC5AgAaAAcKMyHUAAC5AgA1AAQKgSQAAhoACQqwI1QEAHwDABoACQqwI1QEAHwDAAAA.Tamyr:BAAANQADCgIIAgAAAA==.Tazadar:BAAANQADCgcIBwAAAA==.Taze:BAAANQAECgUJBwABNQAECggIHwAKACIcAA==.Tazjiingo:BAAANQADCgIIBAAAAA==.',
Te='Ted:BAAANQADCggIEAAAAA==.Terrika:BAAANQAECgUICwAAAA==.Tetshajeh:BAABNQAECoEpAAMLAAkK7R6hHwAXAwALAAkK7R6hHwAXAwAMAAMKCxuFIADkAAAAAA==.Teyliana:BAAANQADCggIDgAAAA==.',
Th='Thillarick:BAAANQAECgUIDQAAAA==.Thromanor:BAAANQADCgEIAQAAAA==.Thwip:BAABNQAECoEfAAMJAAgKRB/6MQCVAgAJAAgKRB/6MQCVAgAaAAYKZQciPgD4AAAAAA==.',
Ti='Tikwid:BAAANQAECgUIDQAAAA==.Tiranmyashol:BAABNQAECoEcAAILAAgK9BT+ZAAWAgALAAgK9BT+ZAAWAgAAAA==.',
To='Tomoya:BAAANQAECgcIEgAAAA==.Too:BAAANQADCgEIAQAAAA==.Toothdk:BAAANQAECgQICAAAAA==.',
Tr='Treebreak:BAAANQAECgQICAAAAA==.',
Ty='Tyrandrea:BAAANQADCgcIBwAAAA==.',
Ud='Udari:BAAANQAECgYJBgAAAA==.Udarii:BAAANQAECgIIAgAAAA==.',
Um='Umàdbrah:BAAANQAECgYIDwAAAA==.',
Un='Unbelievable:BAAANQAECgUICAAAAA==.Unprovoked:BAABNQAECoEaAAIOAAgKZh8RXgCWAgAOAAgKZh8RXgCWAgAAAA==.',
Va='Valamor:BAAANQAECgUIDwAAAA==.Varia:BAAANQAECgEIAQABNQAECgcIDQADAAAAAA==.',
Ve='Veefib:BAABNQAECoEXAAIeAAgKpBkMNABkAgAeAAgKpBkMNABkAgAAAA==.Velvettwitch:BAABNQAECoEXAAIUAAcKaQ+aFgCqAQAUAAcKaQ+aFgCqAQAAAA==.Vendler:BAAANQAECgUIDgAAAA==.Verahla:BAAANQADCgQIDAAAAA==.Vermis:BAABNQAECoEXAAIiAAYKKg1UQQBHAQAiAAYKKg1UQQBHAQAAAA==.Veryaverage:BAAANQAECgMIBgAAAA==.Vexation:BAAANQADCggIGAAAAA==.',
Vi='Vicarious:BAAANQAFFAEIAQAAAA==.Vidreaux:BAABNQAECoEZAAMOAAcKqgtc7QBdAQAOAAYKJwxc7QBdAQAhAAEKvgj/NQA8AAAAAA==.Villaraa:BAAANQADCgEIAQAAAA==.',
Vo='Voidofvoids:BAAANQAECgEIAQAAAA==.Votingromney:BAAANQAECgEJAQABNQAECgkJHQAGAAslAA==.Vowz:BAAANQADCgMIAwAAAA==.',
Vu='Vulpe:BAABNQAECoEdAAIJAAgKVhqdNwCAAgAJAAgKVhqdNwCAAgAAAA==.',
Vy='Vyolenta:BAAANQADCgIIAgAAAA==.',
['Vë']='Vëxhunter:BAAANQAECgcIBAAAAA==.',
Wa='Waldorf:BAAANQAECgMIAwAAAA==.Wallegator:BAAANQADCgIIBAABNQAECgUIBQADAAAAAA==.Walleroot:BAAANQAECgUIBQAAAA==.',
Wh='Whitewhitch:BAAANQADCgIIAwAAAA==.Whosethetank:BAAANQADCgcIBQAAAA==.',
Wo='Wolfpup:BAAANQAECggICAAAAA==.Worstelf:BAAANQAECgYIEQAAAA==.',
Xi='Xilstar:BAAANQADCgUIBQAAAA==.',
Xz='Xzavier:BAAANQADCgYIDQAAAA==.',
Yf='Yfelshammy:BAAANQAECgcIEwAAAA==.',
Yv='Yvaldi:BAAANQAECgYIBgABNQAECggIFAABACIkAA==.Yvonnél:BAAANQADCggIEgAAAA==.',
Za='Zanebusby:BAABNQAECoEYAAIUAAkKwhh6BADOAgAUAAkKwhh6BADOAgAAAA==.Zankru:BAAANQADCgYIBwAAAA==.Zaraë:BAAANQADCggIDgAAAA==.Zaria:BAAANQAECgYICwABNQAECgkJHQAGAAslAA==.Zartash:BAAANQAECgUJCwAAAA==.Zatharis:BAAANQAECgIIAwAAAA==.',
Ze='Zelik:BAAANQADCgMIAwABNQAECggIIAAJAFAmAA==.Zevellian:BAAANQADCggIDgABNQAECgcIEQADAAAAAA==.',
Zm='Zmona:BAAANQAECgcIDQAAAA==.',
Zo='Zolrath:BAAANQABCgQIAgAAAA==.',
['Ãm']='Ãmpstar:BAAANQADCgMIAwAAAA==.',
['Äm']='Ämpstarr:BAAANQADCgEIAQAAAA==.',
['Çy']='Çyanide:BAAANQADCgQICgABNQAECgYICAADAAAAAA==.',
['Ðr']='Ðragonshaft:BAABNQAECoEaAAIJAAgKnA7uZQDyAQAJAAgKnA7uZQDyAQAAAA==.',
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
