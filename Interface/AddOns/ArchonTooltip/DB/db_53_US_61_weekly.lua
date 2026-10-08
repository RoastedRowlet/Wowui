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

local lookup = {'DeathKnight-Frost','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Hunter-Marksmanship','Warrior-Arms','Priest-Discipline','DeathKnight-Unholy','Warrior-Protection','DemonHunter-Devourer','Warrior-Fury','Rogue-Subtlety','Monk-Brewmaster','DeathKnight-Blood','Monk-Windwalker','Shaman-Restoration','Druid-Balance','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Retribution','Paladin-Holy','Priest-Holy','Druid-Restoration','Monk-Mistweaver','Rogue-Outlaw','Shaman-Enhancement','Priest-Shadow','Mage-Arcane',}
local provider = {region='US',realm='Darrowmere',name='US',type='weekly',zone=53,date='2026-10-06',data={Ab='Abaddonmoon:BAABNQAECoEfAAIBAAgKyQ/+MwDQAQABAAgKyQ/+MwDQAQAAAA==.',
Ah='Ahnari:BAACNQAFFIEFAAICAAMKbwJBFwDHAAACAAMKbwJBFwDHAAA1AAQKgSMAAgIACQrCD7lSAFACAAIACQrCD7lSAFACAAAA.',
Ai='Ailinaa:BAAANQAECgIIAgAAAA==.',
Al='Alerat:BAAANQADCgYIBgABNQAECggIGQADAFoLAA==.Alistìn:BAABNQAECoEYAAIEAAgKyh8dDQCoAgAEAAgKyh8dDQCoAgAAAA==.Alistín:BAAANQAECgQIBAAAAA==.Allahwe:BAAANQAECgEIAgAAAA==.Allo:BAAANQADCggICQAAAA==.Alìstin:BAAANQADCgYIBgAAAA==.',
Am='Ameri:BAAANQAECgUICQAAAA==.',
An='Annalistiana:BAABNQAECoEZAAIFAAgKzxLQXgAZAgAFAAgKzxLQXgAZAgABNQAECgUICgAGAAAAAA==.',
Ap='Apiphone:BAAANQABCgQIBAAAAA==.',
Ar='Aradin:BAAANQAECgEIAwAAAA==.Archanfel:BAABNQAECoEVAAIHAAYKqQsxPQA5AQAHAAYKqQsxPQA5AQAAAA==.Argasha:BAAANQAECgQICQAAAA==.Aro:BAAANQADCggICAABNQAECgQICQAGAAAAAA==.Artemesya:BAAANQAECgEIAgAAAA==.',
Ay='Ayurvedas:BAAANQADCgYIBgAAAA==.',
Az='Azaadi:BAEANQADCgYIBgABNQAECgEIBQAGAAAAAA==.',
Ba='Bandie:BAAANQAECgQIBwAAAA==.Bashan:BAAANQADCgEIAQAAAA==.Bayn:BAAANQABCggIFwAAAA==.',
Be='Beeftruck:BAABNQAECoEUAAIIAAcK6hL6jgDPAQAIAAcK6hL6jgDPAQAAAA==.Berried:BAABNQAECoEnAAIJAAkK8xVHBAByAgAJAAkK8xVHBAByAgAAAA==.',
Bi='Bigred:BAAANQAECgQIBwAAAA==.Biminem:BAAANQADCgYIBgAAAA==.Bitomax:BAAANQAECgQIBQAAAA==.',
Bl='Blað:BAAANQADCgEIAQAAAA==.Bloôdymary:BAAANQAECgQIBQAAAA==.',
Br='Brewer:BAAANQADCgQIBAAAAA==.Briline:BAAANQADCgQIBAAAAA==.Brolly:BAAANQAECggIAQAAAA==.',
Ca='Calamari:BAAANQADCgQIBAAAAA==.Camine:BAABNQAECoElAAIKAAcKhxpIOwAPAgAKAAcKhxpIOwAPAgAAAA==.Capmurica:BAAANQAECgMICwAAAA==.Castadrood:BAAANQAECgEIAwAAAA==.Cates:BAAANQADCgUIBQAAAA==.',
Ch='Choppstik:BAAANQADCgQIBAAAAA==.',
Co='Cocstrong:BAAANQADCgEIAgAAAA==.Coriolis:BAAANQAECgUICgAAAA==.',
Cr='Craano:BAAANQABCgQIBAABNQAECgEIAQAGAAAAAA==.',
Da='Dagdag:BAAANQAECgIIAQAAAA==.Dagnamagus:BAAANQADCgUIBwAAAA==.',
De='Deathcokie:BAAANQAECgQICQAAAA==.Deatho:BAABNQAECoEpAAMLAAgK7CbWAQCXAwALAAgK7CbWAQCXAwAIAAIKphzrBQGcAAAAAA==.Deimos:BAAANQADCgQIBAAAAA==.',
Di='Diamondshard:BAAANQAECgEIAQAAAA==.Diviniah:BAAANQADCgYIBgAAAA==.',
Do='Dotdotcurse:BAAANQADCggICAAAAA==.',
Dr='Drash:BAAANQAECgEIAQAAAA==.Dreadful:BAABNQAECoEfAAIMAAgKrBZgHQBMAgAMAAgKrBZgHQBMAgAAAA==.Dreyra:BAAANQADCggIJwABNQAECggIHAANALYbAA==.Droodtrass:BAAANQAECgQICAAAAA==.Drunksausage:BAAANQAECgEIAQAAAA==.',
Du='Duncan:BAAANQADCggIEAABNQAECggIJwAIABIIAA==.',
['Dö']='Döctorfate:BAABNQAECoEnAAIOAAgKtwriHADYAQAOAAgKtwriHADYAQAAAA==.',
Ed='Ediela:BAAANQADCgEIAQAAAA==.',
Ef='Effinsoldier:BAAANQAECgEIAgAAAA==.',
El='Elix:BAAANQADCgEIAQAAAA==.Elixir:BAAANQAECgEIAgAAAA==.Elvira:BAABNQAECoEYAAIFAAgKeQiyiwCaAQAFAAgKeQiyiwCaAQAAAA==.',
En='Endwa:BAAANQAECgIIAgAAAA==.',
Ep='Epsicarinae:BAAANQADCgIIAgAAAA==.',
Er='Erel:BAAANQAECgEIBAAAAA==.Eridrel:BAAANQAECgUIDAAAAA==.',
Fa='Fasriel:BAAANQAECgEIBQAAAA==.',
Fi='Fiyero:BAABNQAECoEnAAIIAAgKEgjMowCYAQAIAAgKEgjMowCYAQAAAA==.',
Fl='Fleabath:BAAANQADCggJDgABNQAECgUIEwAGAAAAAA==.',
Fu='Fury:BAABNQAECoEzAAMNAAkKOCFEAgBAAwANAAkKGB5EAgBAAwAIAAcKsR2eaAA3AgAAAA==.',
Ga='Galdames:BAAANQAECggIDwAAAA==.Gandolphgrey:BAAANQAECgQIBwAAAA==.',
Ge='Genghar:BAAANQADCggIDAAAAA==.Gertluzgin:BAAANQAECgEIAQAAAA==.',
Gi='Gilforty:BAAANQAECgEIAgAAAA==.',
Go='Gonk:BAABNQAECoEUAAIPAAgKhBLvDgDiAQAPAAgKhBLvDgDiAQAAAA==.',
Gr='Gripnkill:BAABNQAECoFWAAMQAAkK/xjWKABfAgAQAAkKBhjWKABfAgABAAIKghgRcwCQAAAAAA==.',
Gu='Gump:BAAANQAECgEIAwABNQAECgcIFAAIAOoSAA==.',
Gv='Gvendalyn:BAABNQAECoEmAAICAAkKFiZ2AQDrAwACAAkKFiZ2AQDrAwAAAA==.',
Gy='Gyatsò:BAABNQAECoEcAAIRAAgKLB16FACOAgARAAgKLB16FACOAgAAAA==.',
Ha='Harshc:BAAANQAECgUIEAABNQAECgYIBwAGAAAAAA==.Harshdh:BAAANQAECgYIBwAAAA==.',
He='Helapa:BAAANQAECgMIBQAAAA==.Helel:BAABNQAECoEzAAMKAAkKISLqEwADAwAKAAkK2CHqEwADAwAQAAgKRB4zHgCnAgAAAA==.',
Ho='Hops:BAAANQAECgIIAwAAAA==.',
Ip='Ipokeu:BAAANQADCgUIBQAAAA==.',
Ja='Jabohabo:BAABNQAECoEdAAIIAAkKgx5ZIwAcAwAIAAkKgx5ZIwAcAwAAAA==.Jaffy:BAAANQAECgEIAgAAAA==.Jamninja:BAAANQAECgEIAQAAAA==.Javamaster:BAAANQADCgIIAgAAAA==.Jaxxson:BAABNQAECoEVAAISAAcKSR7pNwBYAgASAAcKSR7pNwBYAgAAAA==.',
Je='Jellyfish:BAAANQAECgEIAgAAAA==.Jeriko:BAAANQADCgQIBAAAAA==.Jessamyn:BAAANQAECgEIAgAAAA==.',
Jh='Jhoira:BAAANQABCgIIAgAAAA==.',
Jo='Jordyy:BAABNQAECoEUAAIFAAgKMxq6QAB0AgAFAAgKMxq6QAB0AgAAAA==.',
Ka='Kalifa:BAACNQAFFIELAAITAAUKiRmfCQCrAQATAAUKiRmfCQCrAQA1AAQKgSAAAhMACQoLIr8QAC8DABMACQoLIr8QAC8DAAAA.Karrod:BAAANQAECgEIAQAAAA==.Kayohs:BAAANQAECgQIDwAAAA==.',
Kh='Khrysus:BAABNQAECoEdAAIRAAgKpQ5GKACrAQARAAgKpQ5GKACrAQAAAA==.',
Ki='Kiv:BAABNQAECoEoAAQFAAkK+iCRFwAVAwAFAAkK+iCRFwAVAwAUAAIKZw24IABcAAAVAAEKnRcZaABEAAAAAA==.Kiwaj:BAAANQAECgEIAQABNQAECgQJCgAGAAAAAA==.',
Kn='Knoa:BAAANQAECgEIAwAAAA==.',
Ko='Kodachi:BAAANQAECgEIAQAAAA==.Komayetu:BAAANQADCgQICAAAAA==.',
Kr='Krashed:BAAANQAECgEIAgAAAA==.Krateis:BAAANQAECgEIAQAAAA==.',
Ku='Kunfool:BAAANQAECgEIAQAAAA==.',
Kv='Kvit:BAAANQAECgIIAgAAAA==.',
Ky='Kyoki:BAABNQAECoEkAAIWAAgKLQ/ZFQDMAQAWAAgKLQ/ZFQDMAQAAAA==.',
La='Lazyace:BAAANQAECgIIAwAAAA==.',
Li='Liendrel:BAAANQABCgYIBgAAAA==.',
Ly='Lyset:BAAANQADCgEIAQABNQAECgIIAgAGAAAAAA==.',
Ma='Maeze:BAAANQAECgUIEwAAAA==.Malandru:BAACNQAFFIEMAAMXAAUKCAyHDgAnAQAXAAQKcQyHDgAnAQAYAAQKuwozEAAgAQA1AAQKgSYAAxgACQpwGyciAM0CABgACAp4HiciAM0CABcAAgrdIBUeAbUAAAAA.Mawwow:BAABNQAECoEjAAIXAAgKpCRYIQAmAwAXAAgKpCRYIQAmAwAAAA==.',
Me='Meatfingers:BAAANQAECgEIAQAAAA==.Meekah:BAABNQAECoEfAAMZAAkKFwqgXwDRAQAZAAkKFwqgXwDRAQAJAAMKlwcJGgB+AAAAAA==.Melyndia:BAAANQADCggICgABNQAECgkJKAAaADkfAA==.Meriks:BAAANQADCgYIBgABNQAECggIKwAMALgkAA==.',
Mi='Mickfurry:BAAANQAECgcICgABNQAFFAUIDAAbAJkdAA==.Micksippy:BAACNQAFFIEMAAIbAAUKmR23AgDQAQAbAAUKmR23AgDQAQA1AAQKgScAAhsACQpoI9cDAFwDABsACQpoI9cDAFwDAAAA.Milamber:BAAANQAECgUICwAAAA==.Milfy:BAAANQADCgQJBAABNQAECgQICQAGAAAAAA==.',
My='Mylarna:BAABNQAECoEZAAIDAAgKWgsJcwCYAQADAAgKWgsJcwCYAQAAAA==.Mynx:BAAANQAECgcIDgAAAA==.',
Mz='Mzivvee:BAAANQADCgMIAgABNQAECgYIFAAcAD8PAA==.',
Na='Nashea:BAAANQADCgcJEAAAAA==.',
Ne='Neltharis:BAAANQABCgQIBAAAAA==.Neona:BAAANQADCgUIBwAAAA==.',
Ni='Nixii:BAABNQAECoEnAAITAAgK4xReMwAkAgATAAgK4xReMwAkAgAAAA==.',
No='Nocticula:BAABNQAECoEgAAIZAAgKLAU9fwBgAQAZAAgKLAU9fwBgAQAAAA==.',
Ny='Nyalota:BAAANQADCggIDgAAAA==.Nyet:BAAANQAFFAIIAgAAAA==.',
Og='Ogucci:BAAANQADCggICAAAAA==.',
Op='Opalauria:BAAANQADCgUIBQAAAA==.',
Or='Orine:BAAANQADCgYICAAAAA==.Orion:BAAANQAECgYICQAAAA==.Orioz:BAACNQAFFIEFAAIdAAMKrhokAwAVAQAdAAMKrhokAwAVAQA1AAQKgRsAAh0ACQrsHhoGABgDAB0ACQrsHhoGABgDAAAA.',
Oz='Oz:BAABNQAECoEaAAIFAAcKViBPOgCJAgAFAAcKViBPOgCJAgAAAA==.',
Pa='Pakali:BAAANQABCgMIAgAAAA==.Paladinhalos:BAAANQABCgYICAAAAA==.Paladinsan:BAAANQAECgQIBAABNQAECggIDwAGAAAAAA==.',
Po='Police:BAAANQADCgUIBQABNQAECggIAgAGAAAAAQ==.',
Ps='Psychomurda:BAAANQADCgYIBgABNQAECgkJHwAZABcKAA==.',
Py='Pytheas:BAAANQADCgYIBgABNQADCgQIBAAGAAAAAA==.',
Ra='Radio:BAAANQAECgMJBQAAAA==.Raistlin:BAAANQAECgUIBQABNQAFFAUICQATAA4EAA==.',
Re='Renfri:BAAANQAECgEIAwAAAA==.',
Ro='Robel:BAAANQAECgIIBgAAAA==.Roflburger:BAAANQAECgQICQAAAA==.Rovox:BAAANQAECgQJCgAAAA==.',
Sa='Sadness:BAAANQAECgEIAQAAAA==.Sardrian:BAAANQAECgEIAQAAAA==.Saî:BAAANQADCgYIBgAAAA==.',
Sc='Scarletwrath:BAAANQADCgYICgAAAA==.',
Se='Seika:BAAANQAECgEIAwAAAA==.Seimie:BAAANQAECgQIDQAAAA==.Senethotsare:BAAANQADCgUIBwAAAA==.',
Sh='Shaboudi:BAAANQAECgQIBAABNQAECggIFAAPAIQSAA==.Shammwow:BAABNQAECoEUAAIDAAcK3AILrgAIAQADAAcK3AILrgAIAQAAAA==.Sherryl:BAABNQAECoEnAAIaAAgKYA92JADSAQAaAAgKYA92JADSAQAAAA==.',
Sk='Skdragon:BAAANQAECgYIDwAAAA==.Skyara:BAAANQAECgQIBQABNQAECggIIgAeAO8fAA==.Skylaar:BAAANQADCggICAAAAA==.',
So='Soulstik:BAAANQADCgcIDQAAAA==.',
Sp='Spiritshard:BAAANQAECgEIAgAAAA==.Spriggens:BAAANQAECgUICQABNQAECgkJJgACABYmAA==.',
St='Stalkr:BAAANQADCgQIBAAAAA==.Sthise:BAAANQADCgYJCgAAAA==.',
Sy='Sykoman:BAACNQAFFIEWAAITAAcK2hp3AwBeAgATAAcK2hp3AwBeAgA1AAQKgR0AAhMACQqkJFMKAG0DABMACQqkJFMKAG0DAAAA.Sykowoman:BAAANQAECgQJBAABNQAFFAcIFgATANoaAA==.',
['Sì']='Sìrius:BAAANQAECgEIAQAAAA==.',
Te='Terumi:BAAANQADCgcJEAAAAA==.',
Th='Thiizz:BAABNQAECoEfAAIKAAgKkR1fJACQAgAKAAgKkR1fJACQAgAAAA==.Thracious:BAAANQADCgUIBwAAAA==.Thïzz:BAAANQAECgQICQABNQAECgkJHQAIAIMeAA==.',
Ti='Ticklemebutt:BAAANQAECgUIEAAAAA==.Tinksy:BAAANQADCgYIBgABNQAECgQICQAGAAAAAA==.Titanx:BAAANQADCgMJBAAAAA==.',
To='Toeto:BAAANQADCgUIBQAAAA==.Toetoeto:BAAANQAECgcIEQAAAA==.Toetoetoete:BAAANQADCgcJCAAAAA==.Tooe:BAAANQAECgQICwAAAA==.Torquei:BAAANQAECgcIEQAAAA==.Toxan:BAAANQADCgUIBgAAAA==.',
Tp='Tpaman:BAAANQADCgMIBAAAAA==.',
Tr='Triks:BAAANQAECgYIDAAAAA==.',
Ts='Tsjudilla:BAAANQADCgQJBAAAAA==.',
Tu='Tujefe:BAABNQAECoEoAAIFAAkKgxDnWQAnAgAFAAkKgxDnWQAnAgAAAA==.',
Ty='Tylorialin:BAAANQADCgMIAwABNQAECgcIFAAIAOoSAA==.',
Ur='Urpalharsh:BAAANQADCgIIAgABNQAECgYIBwAGAAAAAA==.',
Va='Vahldire:BAAANQADCggIJQAAAA==.Valeeraa:BAAANQAECgQIBwAAAA==.Valeri:BAAANQADCgcIBwAAAA==.',
Ve='Veresa:BAAANQAECgEIAgAAAA==.',
Wa='Waeder:BAAANQADCgcIDQAAAA==.Waren:BAAANQAECgMIAwAAAA==.',
Wi='Wisteria:BAABNQAECoEiAAQVAAkKxQsAJABIAQAFAAgK4QpRgwCwAQAVAAcKNwcAJABIAQAUAAEKSQOdLwAoAAABNQADCgQIBAAGAAAAAA==.',
Wo='Wompalot:BAAANQADCggIDwABNQAECgMIBAAGAAAAAA==.Wompeter:BAAANQAECgMIBAAAAA==.Womplock:BAAANQADCgIIAgAAAA==.Wooly:BAAANQADCgMIAwAAAA==.',
Wr='Wrâth:BAABNQAECoEiAAIfAAgK5AxxvgDjAQAfAAgK5AxxvgDjAQAAAA==.',
Xa='Xael:BAAANQAECgQIBwAAAA==.',
Xu='Xunarii:BAAANQADCgUIBQABNQAECggIIgAeAO8fAA==.',
Za='Zalus:BAAANQADCgYICgAAAA==.Zaymaa:BAAANQAECgEIAQAAAA==.',
Ze='Zeal:BAAANQAECgQICQAAAA==.Zenatria:BAAANQADCgcICwAAAA==.',
Zi='Zindetra:BAAANQADCgEIAQAAAA==.',
Zo='Zorana:BAAANQAECgEIAQAAAA==.',
['Ów']='Ówl:BAAANQADCgUIDgAAAA==.',
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
