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

local lookup = {'Hunter-Survival','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Warrior-Fury','Warrior-Arms','Monk-Mistweaver','DeathKnight-Unholy','Druid-Feral','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Druid-Guardian','Druid-Balance','Rogue-Subtlety','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Monk-Brewmaster','Evoker-Devastation','DemonHunter-Devourer','Mage-Arcane','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','DemonHunter-Vengeance','Warlock-Destruction','Rogue-Outlaw',}
local provider = {region='US',realm='Uldaman',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abasi:BAAANQABCgQIBAAAAA==.',
Ad='Ademar:BAABNQAECn8mAAIBAAoK3RqxAgADAwABAAoK3RqxAgADAwABNQAFFAIIBQACAOoOAA==.',
Al='Alkie:BAAANQADCggICgAAAA==.Allectra:BAAANQAECgUICwAAAA==.Allupinya:BAAANQAECgQIBAABNQAECggIGgADAMsbAA==.',
Am='Amarie:BAAANQABCgMIAwAAAA==.Amnon:BAABNQAECn8eAAIEAAgKnhitAQCVAQAEAAgKnhitAQCVAQAAAA==.',
An='Anáthema:BAAANQABCgEIAQAAAA==.',
Ar='Arath:BAAANQADCggICQAAAA==.Arielsz:BAAANQADCgUJBQAAAA==.',
As='Asanath:BAAANQADCgYJBQAAAA==.Ashlara:BAAANQAECgYICgAAAA==.',
Au='Ausha:BAAANQADCggICAAAAA==.',
Az='Azdaja:BAAANQADCgQIBAAAAA==.Azulå:BAACNQAFFH8IAAIFAAMKVgnoCADaAAAFAAMKVgnoCADaAAA1AAQKfz4AAgUACgriIH8MAHoDAAUACgriIH8MAHoDAAAA.',
Ba='Baadkitty:BAAANQADCgQIBAAAAA==.Bandwidth:BAAANQADCgUIBQABNQAECgQIBwAGAAAAAA==.',
Be='Becomedeath:BAAANQABCgcICwAAAA==.Bellachai:BAAANQAECgQIBwAAAA==.Benm:BAAANQADCgcIBwABNQAECgoKLwAHANYgAA==.Berastu:BAABNQAECn8vAAMIAAoKQhlCAgDEAQAIAAoKQhlCAgDEAQAJAAQKkAqBHgGeAAAAAA==.Bergalicious:BAAANQAECgUIBwAAAA==.',
Bo='Booz:BAAANQADCgQJBAAAAA==.Bowdacious:BAAANQAECgQIBgABNQAECggIGgADAMsbAA==.',
Bu='Bugabooed:BAAANQADCggICgAAAA==.',
Ca='Callee:BAAANQADCgcICQAAAA==.Calyse:BAAANQADCgYIBgAAAA==.Casima:BAAANQAECgEIAQAAAA==.',
Ch='Cheydinhal:BAABNQAECn8nAAIHAAkKegmxdQC7AQAHAAkKegmxdQC7AQAAAA==.Cheydinhalas:BAAANQADCgQIBgAAAA==.Chichi:BAABNQAECn8cAAIKAAcK9xpxFwAGAgAKAAcK9xpxFwAGAgAAAA==.Chicknwaffle:BAAANQAECgQIBQAAAA==.Chumlee:BAAANQADCgYIBwAAAA==.Chunks:BAAANQAECgUIDQAAAA==.',
Co='Colleague:BAAANQAECgcICwAAAA==.Cornmoon:BAAANQADCgYIEwAAAA==.',
Cr='Creamed:BAAANQAECgUIBQABNQAECgkJKwAFAAgYAA==.',
Da='Darksushi:BAAANQAECgcICAAAAA==.Dashamana:BAAANQAECggIEQAAAA==.',
De='Deathbear:BAAANQAECgQIDgAAAA==.Demacia:BAAANQADCggIDgABNQAFFAUICQALALYLAA==.',
Dh='Dhabyss:BAAANQADCgIIAgABNQAECggIKQAGAAAAAA==.',
Di='Dimensionul:BAAANQAECgEIAQAAAA==.Dimensiònal:BAAANQADCgMIAwAAAA==.Dinbek:BAAANQAECgMIAwAAAA==.Displacement:BAAANQADCgQIBAABNQAECgQIBwAGAAAAAA==.',
Do='Dordis:BAABNQAECn8UAAIMAAcKqBtKEAAGAgAMAAcKqBtKEAAGAgAAAA==.',
Dr='Dragonflamz:BAAANQABCgIIAgAAAA==.Drashammy:BAAANQADCggIEAAAAA==.',
Du='Duckmyass:BAAANQADCgMIAwAAAA==.Dusksurge:BAAANQADCggIBwAAAA==.',
['Dÿ']='Dÿmmensional:BAAANQAECgMIAgAAAA==.',
Ec='Eclipze:BAABNQAECn8yAAINAAkKHxjaCABnAQANAAkKHxjaCABnAQAAAA==.Eclipzee:BAAANQAECgUICQABNQAECgkJMgANAB8YAA==.Eclipzé:BAAANQAECgQIBgABNQAECgkJMgANAB8YAA==.Eclípze:BAAANQADCgcIBwABNQAECgkJMgANAB8YAA==.',
Ei='Eifel:BAABNQAECn8cAAMOAAcKZSHTKACFAQAOAAcKZSHTKACFAQAPAAEKsR78YQBVAAAAAA==.',
El='Elaure:BAAANQADCgYIBgABNQAFFAQICAADAIocAA==.Elenna:BAAANQAECgEIAgABNQAECggILwAQAHokAA==.Elessardan:BAABNQAECn8vAAQQAAgKeiSsCAA6AwAQAAgKeiSsCAA6AwARAAgKUhQ/FwD5AQASAAIKVgeJpABRAAAAAA==.',
En='Endilli:BAAANQAECgYIDQABNQAECgoKNgAOAFwgAA==.',
Eq='Equinoxis:BAEANQAECgYICwABNQAFFAcIGgANAIIPAA==.',
Ey='Eyeeball:BAAANQADCgcJBwAAAA==.',
Fa='Fallynangel:BAABNQAECn8eAAITAAYKlg6eKwCwAAATAAYKlg6eKwCwAAAAAA==.',
Fi='Filho:BAAANQAECgEJAQAAAA==.',
Fo='Foxptm:BAAANQAECgcIDgAAAA==.',
Fr='Frastbert:BAAANQABCgEIAQAAAA==.Friedtips:BAAANQADCgQIAwABNQAECgoKJwAUABQbAA==.Frostymilk:BAABNQAECn8oAAISAAoKexqDIQDCAgASAAoKexqDIQDCAgAAAA==.',
Ga='Galvek:BAACNQAFFH8GAAIVAAIKLgiHCQCGAAAVAAIKLgiHCQCGAAA1AAQKfyUAAxUACgq2Fw4tAOMBABUACQrBEg4tAOMBAAUABArPFI/4ABIBAAAA.Garjzlaa:BAAANQAECgQIBAAAAA==.Garugamesh:BAAANQAECgIIBAAAAA==.Gas:BAAANQAECgEIAQAAAA==.',
Gi='Gigglecups:BAAANQAECgEIAQAAAA==.',
Gl='Glutton:BAAANQADCggICAAAAA==.',
Gr='Greenfoam:BAAANQADCgMIAwAAAA==.Greyswandir:BAAANQAECgQIEAAAAA==.',
Gw='Gwarr:BAAANQAECgYICQAAAA==.Gwendolynn:BAABNQAECn8fAAIHAAkK6hgkSgBHAgAHAAkK6hgkSgBHAgAAAA==.',
Ha='Hailyea:BAABNQAECn8rAAIWAAkKfxYOAgDPAQAWAAkKfxYOAgDPAQAAAA==.Havøc:BAAANQADCgQIBwABNQAECgcIBwAGAAAAAA==.Haylee:BAAANQADCgEIAQAAAA==.',
He='Healydan:BAAANQADCgUIBQAAAA==.',
Ho='Holii:BAAANQADCgUIBwAAAA==.',
Hu='Husky:BAAANQADCgYICgABNQAECgUIDQAGAAAAAA==.',
Id='Idfc:BAAANQADCgQIBAAAAA==.',
Il='Ilovesanta:BAAANQAECgUIBwAAAA==.',
In='Indigobleue:BAABNQAECn8xAAIHAAkKSSC5BADIAgAHAAkKSSC5BADIAgAAAA==.',
Iv='Ivyluna:BAAANQAECgQIBAAAAA==.',
Je='Jemera:BAAANQADCgUIBQAAAA==.',
Ji='Jinkalou:BAAANQADCgcICgABNQAECggIJQAXAJYfAA==.Jinsun:BAAANQADCggIEAAAAA==.Jinzun:BAAANQADCgYICQAAAA==.Jiñ:BAAANQADCgUICAAAAA==.',
Ka='Kabbitha:BAAANQADCgEIAQAAAA==.Kahuma:BAAANQADCgYIBgAAAA==.Kalzdemar:BAACNQAFFH8FAAICAAIK6g5IFwCGAAACAAIK6g5IFwCGAAA1AAQKfzQAAwIACgo9IlMDAK4DAAIACgo9IlMDAK4DAAsABQoFFDGKAPoAAAAA.',
Ke='Keldanor:BAAANQADCgQIBAAAAA==.',
Kh='Kheann:BAAANQADCgYIBgAAAA==.Khärdeen:BAAANQAECgEIAQAAAA==.',
Ki='Kimjongheals:BAABNQAECn8kAAIHAAkKFB3QKwC5AgAHAAkKFB3QKwC5AgAAAA==.Kissey:BAAANQADCgEIAQAAAA==.',
Ko='Konjar:BAAANQADCgUIBAAAAA==.',
Ku='Kungpowpoee:BAAANQADCgEIAQABNQADCgIIAgAGAAAAAA==.',
Ky='Kyrak:BAAANQAECgYIDgAAAA==.',
La='Lainey:BAABNQAECn8rAAIFAAoKAhrBDgD7AQAFAAoKAhrBDgD7AQAAAA==.Landocamando:BAAANQAECgQICQAAAA==.',
Le='Lerya:BAABNQAECn8WAAIYAAgK8A6HFwDRAQAYAAgK8A6HFwDRAQAAAA==.Lessa:BAAANQADCgQIBAAAAA==.Lexnn:BAABNQAECn8zAAIZAAkK2RVzBADWAQAZAAkK2RVzBADWAQAAAA==.',
Li='Lifedrynker:BAAANQADCgUIBQAAAA==.Ligetnoone:BAAANQADCggIOwAAAA==.Lighte:BAABNQAECn8qAAMWAAkKFiEWAwAgAwAWAAkKFiEWAwAgAwAaAAEKAADSxgE1AAAAAA==.',
Lo='Logicx:BAAANQAECgUIBAAAAA==.Lorin:BAAANQABCgIIAgAAAA==.',
Lu='Lunalia:BAAANQADCgYIBgAAAA==.Lunarrastorm:BAAANQAECgYIDAAAAA==.Lunarìa:BAAANQAECgYIBgABNQAECgoKIgAPAKQXAA==.',
['Lê']='Lêssa:BAAANQAECgIIAQAAAA==.',
Ma='Magici:BAAANQAECgMIBQAAAA==.Marraud:BAAANQAECgEIAQAAAA==.Mavren:BAAANQAECgUICAAAAA==.',
Me='Mellesaun:BAAANQADCgMIAwAAAA==.Mephístø:BAABNQAECn8qAAMbAAcKHSPWLADKAgAbAAcKHSPWLADKAgAcAAcKohaSgQCHAQABNQAECggIKAAIAEUaAA==.Merie:BAAANQABCgMIAwAAAA==.Mewtwo:BAAANQAECgMIAwABNQAFFAcIFgAFAOocAA==.',
Mi='Micali:BAABNQAECn8iAAIOAAkKmRjPdQBCAgAOAAkKmRjPdQBCAgAAAA==.Mithrios:BAAANQADCgcIGgABNQAECggICAAGAAAAAA==.',
Mo='Monoris:BAAANQADCgcICwAAAA==.Moonk:BAAANQADCggIFAAAAA==.Moonsaw:BAABNQAECn83AAIdAAoKbCI/BACQAwAdAAoKbCI/BACQAwAAAA==.Morgarlan:BAABNQAECn8vAAIHAAoK1iC/EgA1AwAHAAoK1iC/EgA1AwAAAA==.',
My='Mysaa:BAAANQAECgIIAgABNQADCgYIBgAGAAAAAA==.',
['Má']='Máxîmús:BAAANQABCgEIAQAAAA==.',
['Mï']='Mïck:BAAANQAECgQIDwAAAA==.',
Na='Narusia:BAAANQADCgQIBAAAAA==.',
Ne='Newt:BAABNQAECn8mAAMZAAoKghlqBgCpAQAZAAoKghlqBgCpAQAeAAIKMQRYMwAvAAABNQAFFAEIAQAGAAAAAA==.',
Ni='Ninkasi:BAABNQAECn8aAAIdAAgK5xLoKQDPAQAdAAgK5xLoKQDPAQAAAA==.Nishikki:BAECNQAFFH8aAAINAAcKgg/mBQDQAQANAAcKgg/mBQDQAQA1AAQKfzQAAg0ACgrPIG4KADsDAA0ACgrPIG4KADsDAAAA.',
No='Noomrats:BAAANQABCgQIAgAAAA==.',
Ny='Nydie:BAABNQAECn8nAAIPAAoKKw+mJwChAQAPAAoKKw+mJwChAQAAAA==.',
Om='Omegon:BAAANQADCgcJBwAAAA==.',
Pa='Pallyrocker:BAAANQAECgIIAgAAAA==.',
Pe='Penumbral:BAAANQAECgQIBwAAAA==.Peterios:BAAANQADCgYIBgABNQAFFAUIEwAcAI8cAA==.',
Ph='Phalst:BAAANQABCgMIBQAAAA==.Phibalan:BAAANQAECgEIAgAAAA==.Phyeo:BAAANQADCgcICwABNQAECgoKMgAOACYMAA==.',
Pi='Pixishot:BAAANQADCggIGgAAAA==.',
Pl='Plagueia:BAAANQADCggIDwAAAA==.',
Pu='Pubba:BAAANQAECgYIEQAAAA==.Pubbamorn:BAAANQAECgQIBAABNQAECgYIEQAGAAAAAA==.',
['Pá']='Páin:BAAANQABCgEIAQAAAA==.',
Ra='Radiator:BAAANQADCgYIEAABNQAECgQIBwAGAAAAAA==.Raelyndria:BAAANQAECgQICQAAAA==.Rampart:BAAANQADCgMIAwAAAA==.Ratraxx:BAAANQAECgUIBwABNQAECggIJQAXAJYfAA==.Ravagen:BAAANQADCgcICAAAAA==.',
Re='Redrogue:BAABNQAECn8UAAIfAAUK2wV9CgB3AAAfAAUK2wV9CgB3AAAAAA==.Reiko:BAAANQADCgEIAQAAAA==.Renjanà:BAAANQAECgUIBQAAAA==.',
Ri='Riftan:BAABNQAECn8qAAILAAoKYhbiMQBlAgALAAoKYhbiMQBlAgAAAA==.Riviee:BAAANQADCggIGgAAAA==.',
Ro='Roderígo:BAAANQADCgEIAQAAAA==.Rogun:BAABNQAECn8dAAIVAAkKUAmfEgDxAAAVAAkKUAmfEgDxAAAAAA==.Roredge:BAABNQAECn8lAAMXAAgKlh+ECACiAgAXAAgKlh+ECACiAgAdAAcKLBp3IQAgAgAAAA==.',
Sa='Sarann:BAABNQAECn8iAAMQAAkKBAtgMwCAAQAQAAkKBAtgMwCAAQASAAEKLQKztwAqAAAAAA==.',
Sc='Scarypoppins:BAABNQAECn8aAAIDAAgKyxuyMgBEAgADAAgKyxuyMgBEAgAAAA==.',
Sh='Shamoomoo:BAAANQADCggICAAAAA==.Sharrell:BAAANQADCgIIAgAAAA==.Shoripan:BAAANQAECgEIAQAAAA==.',
Si='Silvertrees:BAABNQAECn8bAAIQAAYKwgYmHgDYAAAQAAYKwgYmHgDYAAAAAA==.',
Sk='Skorpius:BAAANQAECgUIEQAAAA==.',
Sl='Slaytanic:BAABNQAECn8XAAMOAAYKqQ826QBJAQAOAAYKqQ826QBJAQAPAAEKAAAefwAeAAAAAA==.Slymick:BAAANQADCgYICwABNQAECgQIDwAGAAAAAA==.',
Sn='Snoka:BAABNQAECn8yAAIOAAoKJgzFLwBxAQAOAAoKJgzFLwBxAQAAAA==.',
So='Solora:BAABNQAECn8UAAIbAAUKqQUBXgB8AAAbAAUKqQUBXgB8AAAAAA==.',
Sp='Sparklesky:BAAANQADCgYICQAAAA==.',
St='Stankyy:BAAANQAFFAEIAQAAAA==.Starí:BAAANQADCgYIBwAAAA==.Strawry:BAAANQADCgcIDAAAAA==.',
Su='Sunjiwung:BAAANQADCgUIBQAAAA==.Supadin:BAAANQADCgIIAgAAAA==.',
Sy='Sylanan:BAAANQAECgUIBwAAAA==.Syrüs:BAABNQAECn8nAAIUAAoKFBt1IQCQAgAUAAoKFBt1IQCQAgAAAA==.',
['Sã']='Sãrik:BAAANQADCgMIAwAAAA==.',
Te='Tempestfury:BAAANQADCgIIAgAAAA==.Temuraire:BAAANQADCgUIBgAAAA==.Tethyssra:BAAANQADCgYICwABNQAECgQIBwAGAAAAAA==.',
Th='Thalyra:BAABNQAECn8bAAIZAAcKDB/VJAAgAgAZAAcKDB/VJAAgAgABNQAECggIJAAaAK0kAA==.Thestar:BAAANQADCgQICgAAAA==.Thirstrap:BAABNQAECn8oAAIUAAkKeBFrHAATAQAUAAkKeBFrHAATAQAAAA==.Thorge:BAABNQAECn8YAAMBAAcKvhC2CAC9AQABAAcKEA+2CAC9AQAFAAYKmg0tuQCRAQAAAA==.Thíngtwo:BAAANQADCgUIBQAAAA==.',
Ti='Tiltawhirl:BAAANQAECgMIBQAAAA==.',
Tw='Twigz:BAAANQABCgYICQAAAA==.',
Un='Unclerukus:BAAANQADCgMIAwAAAA==.Unnserra:BAAANQAECgQIBAABNQAECgoKMQAgAOIWAA==.Unrestraind:BAAANQAECgYICwAAAA==.Unrêstrained:BAAANQADCgcICQAAAA==.',
Va='Valeska:BAAANQADCgMIAwAAAA==.',
Ve='Vennt:BAACNQAFFH8UAAIVAAcKpR4oBQARAgAVAAcKpR4oBQARAgA1AAQKfzsAAhUACgooIqkEAIoDABUACgooIqkEAIoDAAAA.Ventt:BAAANQADCggIDgABNQAFFAcIFAAVAKUeAA==.Veredelyse:BAAANQADCgQIBAABNQAECgoKMQAgAOIWAA==.',
Vu='Vuhdostev:BAAANQAECgIIAgAAAA==.',
Wa='Warpéd:BAAANQABCgQIAwAAAA==.Wartraxx:BAAANQAECgEIAQABNQAECggIJQAXAJYfAA==.Wayme:BAAANQADCggIGgAAAA==.',
We='Weewitch:BAAANQADCgcIBwAAAA==.',
Wi='Wizzlord:BAAANQAECgQIBQAAAA==.',
Wo='Woghog:BAAANQAECgYICwAAAA==.Wotlk:BAAANQADCgQIBQAAAA==.',
Xa='Xahle:BAABNQAECn8nAAQDAAgK9hJPHAAQAQALAAgK9hL2UgDHAQADAAcKPAdPHAAQAQACAAEK8AJsvwAdAAAAAA==.',
Ya='Yaboì:BAAANQADCgQIBAAAAA==.',
Za='Zareck:BAAANQADCgYIBgAAAA==.',
Ze='Zendayah:BAAANQADCggIDAAAAA==.Zent:BAAANQAECgUIBwAAAA==.Zephie:BAAANQADCgYIBgABNQAECggIGgAdAOcSAA==.',
Zi='Zitillidan:BAACNQAFFH8FAAIUAAIKfA58CQCAAAAUAAIKfA58CQCAAAA1AAQKfyMAAhQACQrRGTAfAKACABQACQrRGTAfAKACAAE1AAUUAggFAAIA6g4A.',
Zo='Zogo:BAAANQADCgIIAgAAAA==.',
['Ör']='Öreö:BAAANQADCggICQAAAA==.',
['ße']='ßeech:BAAANQABCggICgAAAA==.',
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
