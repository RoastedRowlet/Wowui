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

local lookup = {'Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Hunter-BeastMastery','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','DeathKnight-Unholy','Rogue-Assassination','Mage-Frost','Mage-Arcane','Mage-Fire','Paladin-Protection','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Priest-Shadow','Monk-Brewmaster','Monk-Mistweaver','Druid-Restoration','DemonHunter-Havoc','Shaman-Enhancement','Rogue-Subtlety','Hunter-Marksmanship','DemonHunter-Devourer','Priest-Holy','Hunter-Survival','Druid-Guardian','Priest-Discipline',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBQAAAA==.Abadizzoo:BAAANQAFFAEIAQAAAA==.Abeyancë:BAABNQAECn8wAAMBAAoKcBhbXQCAAgABAAoKcBhbXQCAAgACAAIK8RJpBAFwAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECn8xAAIDAAoKOxnsGwDpAgADAAoKOxnsGwDpAgAAAA==.Aite:BAAANQAECgUIBgAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAEAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAEBNQAECn8kAAIBAAgKVRRfjAANAgABAAgKVRRfjAANAgABNQAECgkJGAAFAKAcAA==.Artvandelay:BAAANQAECgQIBgABNQAECggILgAGAO0fAA==.',
As='Asukà:BAABNQAECn8lAAMHAAkKRho1QQBcAgAHAAkKRho1QQBcAgAIAAIK3wEDngAgAAAAAA==.',
Au='Auchenile:BAABNQAECn8lAAMJAAkKFhWNEABOAgAJAAkKFhWNEABOAgAKAAMKzgkhQQCYAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICQAAAA==.',
Av='Avanoura:BAAANQADCggIDQABNQAECgUIDQAEAAAAAA==.',
['Aé']='Aéd:BAAANQADCgcICwABNQAECgYICwAEAAAAAA==.',
Ba='Barkthas:BAAANQAECgcIEAAAAA==.',
Be='Bellarg:BAABNQAECn8nAAMLAAoKBBFWCwD2AQALAAoKBBFWCwD2AQAMAAEKzQeXfQAvAAAAAA==.Belobog:BAAANQAECgYIBQAAAA==.Belyn:BAAANQAECgUIEwAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgYIDQAAAA==.Bloodadinz:BAAANQAECgIIAgAAAA==.',
Bo='Bonedaddy:BAABNQAECn8bAAMNAAcKEhXjQADDAQANAAcKEhXjQADDAQAOAAUK5wRYMwCpAAAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAUIDwABALEkAA==.Brbwifeaggro:BAAANQABCgIIBAAAAA==.Bro:BAABNQAECn8jAAQLAAoK3RUDYAA4AgALAAgKlRcDYAA4AgAMAAIK6hhSTgCUAAAPAAIKiwrKKQBFAAAAAA==.Brolich:BAABNQAECn8yAAMOAAoK9BYRGgAdAQAOAAoK9BYRGgAdAQAQAAEKlQrZ4QAyAAABNQAECgoKIwALAN0VAA==.Broo:BAAANQAECgUIDwABNQAECgoKIwALAN0VAA==.Brooak:BAABNQAECn8UAAMIAAgKsxA64ADWAAAIAAQKzAo64ADWAAAHAAcKuAmvSwDJAAABNQAECgoKIwALAN0VAA==.Brother:BAAANQAECgUIBgABNQAECgoKIwALAN0VAA==.Brozeit:BAAANQAECggIDwABNQAECgoKIwALAN0VAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAABNQAECn8YAAIRAAkKrx5tHACbAgARAAkKrx5tHACbAgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8eAAMSAAcKdhnzAgD3AAATAAYKIhuoDQAKAgASAAMKyRTzAgD3AAA1AAQKfysABBMACgqNI6cyACUDABMACgoPI6cyACUDABQAAwqfIU8GAPoAABIAAQosJXo9AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAFFAMICgAVAK4ZAA==.',
Cl='Clare:BAABNQAECn8eAAIVAAoKZx8RDQDKAgAVAAoKZx8RDQDKAgAAAA==.Cloúd:BAAANQAECgQICgAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIWAAgKvhpPHgBAAgAWAAgKvhpPHgBAAgAAAA==.Darilol:BAAANQADCgYICAABNQAECgYICwAEAAAAAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn8vAAIOAAkKxyMTAgCaAgAOAAkKxyMTAgCaAgAAAA==.Demiize:BAABNQAECn8tAAISAAoKrhoEBAD2AgASAAoKrhoEBAD2AgAAAA==.Demize:BAABNQAECn81AAIGAAoKyRlDJwD7AgAGAAoKyRlDJwD7AgAAAA==.Demonflame:BAAANQAECgUIBQAAAA==.Demíze:BAAANQAECgQICgAAAA==.Deshield:BAABNQAECn8rAAMXAAoK0iHAAwBbAwAXAAgKPybAAwBbAwAYAAoKRiD1CwADAgAAAA==.Deus:BAABNQAECn8YAAITAAgKmAwT1gDbAQATAAgKmAwT1gDbAQAAAA==.Dewry:BAABNQAECn8XAAIZAAgKIx6UFwCaAgAZAAgKIx6UFwCaAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn8wAAMaAAoKoiPmAQCZAwAaAAoKoiPmAQCZAwAWAAIK5xleXgBnAAAAAA==.',
Di='Diemertz:BAAANQADCgQIBQAAAA==.Dingis:BAAANQAECgMIAwABNQAECgYICwAEAAAAAA==.Divine:BAAANQAECgcIDgABNQAECgoKKAAbAOUSAA==.Dizzo:BAABNQAECn8lAAIQAAgKFhq9DwBfAQAQAAgKFhq9DwBfAQAAAA==.',
Do='Doink:BAABNQAECn8bAAILAAkKexSaaQAfAgALAAkKexSaaQAfAgABNQAECgoKOQAcAFMkAA==.Donnajuan:BAABNQAECn8cAAICAAgK8hy0QQBeAgACAAgK8hy0QQBeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGAAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAYIGQAJACYjAA==.',
El='Elimere:BAABNQAECn8tAAIZAAoKhQxPKgDVAQAZAAoKhQxPKgDVAQAAAA==.Elvarg:BAABNQAECn8vAAIJAAoK0hqXCgDCAgAJAAoK0hqXCgDCAgAAAA==.Elywen:BAACNQAFFH8FAAIGAAIKsRLMDACkAAAGAAIKsRLMDACkAAA1AAQKfy8AAgYACgoFIJsdACEDAAYACgoFIJsdACEDAAAA.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgIIAwAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECgoKKQAdAPEdAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAcIEgAVAEQdAA==.Finke:BAAANQAECgQIDQAAAA==.Firemge:BAEANQAECgUIBQABNQAECggICQAEAAAAAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAAANQAECgcIDgAAAA==.',
Fr='Free:BAAANQAECgUIEAABNQAECgYIDAAEAAAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8zAAITAAoKfw/xowA5AgATAAoKfw/xowA5AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn8qAAIRAAkK8SGEAQCRAgARAAkK8SGEAQCRAgAAAA==.',
Gi='Gigazapper:BAABNQAECn8eAAMIAAgKLRPLggCeAQAIAAcKBRDLggCeAQAHAAUKewe/SgDLAAABNQAFFAMICgAVAK4ZAA==.Gizzlit:BAABNQAECn8hAAIeAAkKuBL5CgBGAQAeAAkKuBL5CgBGAQAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBQABNQAFFAYIDgAdAGghAA==.Gofetch:BAABNQAECn8tAAIGAAkKmRkRDgABAgAGAAkKmRkRDgABAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn8uAAIGAAgK7R+JEgDdAQAGAAgK7R+JEgDdAQAAAA==.',
Gs='Gson:BAABNQAECn8UAAIYAAkK8gTHewCmAAAYAAkK8gTHewCmAAAAAA==.',
Gu='Guppy:BAAANQADCgYIBgAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgkJGgARAPkSAA==.Hakka:BAABNQAECn8aAAMRAAkK+RKUPQDZAQARAAkKqAuUPQDZAQAfAAcKJhOQIQDAAQAAAA==.Hal:BAAANQADCgYICwABNQAECggIGwADAIkKAA==.Hallack:BAABNQAECn8bAAIDAAgKiQr8VQCAAQADAAgKiQr8VQCAAQAAAA==.',
He='Healingkiss:BAAANQAECgIIBQAAAA==.',
Hi='Hikingboots:BAABNQAECn8oAAIIAAgKWgwuGwBQAQAIAAgKWgwuGwBQAQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn8nAAMTAAgKQB4KHwCUAQATAAgKQB4KHwCUAQASAAIKHgxkNwBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICgABNQAECgYICgAEAAAAAA==.',
Il='Illani:BAAANQAECgEIAwAAAA==.Ilyanna:BAABNQAECn8qAAMMAAoKRxjtBwCDAgAMAAgKCBvtBwCDAgALAAgKWwx2RQAAAQAAAA==.',
Im='Im:BAACNQAFFH8YAAMgAAcKeiHzAwBCAgAgAAYKXiDzAwBCAgAGAAEK6SU+LQBtAAA1AAQKfzUAAyAACgoMJYMBAIwCACAACgoMJYMBAIwCAAYAAQr0JRxAAWIAAAAA.Immagical:BAAANQAECgMIBAAAAA==.Imscary:BAAANQAECgUICQAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAABNQAECn8WAAISAAcKqxbyEQCGAQASAAcKqxbyEQCGAQAAAA==.',
Je='Jenyaa:BAAANQADCggIFwAAAA==.',
Jh='Jhops:BAABNQAECn8vAAMIAAgKOh4IEQCOAQAIAAgKOh4IEQCOAQAHAAEKMhPamQA1AAAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECn8pAAMhAAoKjRkPJAAnAgAhAAoKjRkPJAAnAgAdAAUKGxAGWQAjAQAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwATAL4iAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJIwATAL4iAA==.Kozand:BAAANQADCgQICwABNQAECgYICwAEAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgEIAQAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgkJJQAJABYVAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAABNQAECn8UAAIeAAgKWhUuFQAVAgAeAAgKWhUuFQAVAgAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAcIEgAVAEQdAA==.',
Ll='Llynryn:BAAANQAECgUIDQAAAA==.',
Lo='Locktuah:BAAANQAECgUIBwABNQAECgYICwAEAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAEAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8wAAITAAoKfCGyIwBPAwATAAoKfCGyIwBPAwABNQAFFAcIGgAhAMUfAA==.Magicmanzz:BAAANQAECgUIEwAAAA==.Magnifuso:BAAANQAECgUIEgAAAA==.Maguapa:BAAANQAECgUIDQAAAA==.Malgata:BAAANQAECgQIDQAAAA==.Mangrove:BAAANQABCggIDgAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8lAAIBAAoKARmNZABtAgABAAoKARmNZABtAgAAAA==.Mastab:BAABNQAECn8uAAMCAAoK6xc+MgCcAgACAAoK6xc+MgCcAgABAAIK4AxQagF2AAAAAA==.',
Mc='Mchammerdin:BAABNQAECn8kAAQBAAgKvxaghwAYAgABAAgKvxaghwAYAgACAAYKxBDRHgBvAQAVAAMKAxE/YABbAAAAAA==.',
Me='Meat:BAABNQAECn8qAAMFAAgK0RwmAwCFAQAFAAcK0RwmAwCFAQAdAAEKAADZkwAzAAAAAA==.',
Mi='Mikio:BAABNQAECn8fAAIDAAcK/wvYGgAOAQADAAcK/wvYGgAOAQAAAA==.Milinka:BAABNQAECn8tAAIiAAoKzB1pIwDgAgAiAAoKzB1pIwDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAhAAwjAA==.',
Mo='Moiryn:BAAANQADCgIIAgAAAA==.',
My='Myshaman:BAABNQAECn8gAAMHAAcKXRwJFQCsAQAHAAcKXRwJFQCsAQAIAAEKQAlzOgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8ZAAMJAAYKJiOkAAAbAQAJAAUKdSOkAAAbAQAKAAEKYheFCgBcAAA1AAQKf5EAAwkACgrEJU8AAPcDAAkACgrEJU8AAPcDAAoACQqMIpkCAA0CAAAA.',
No='Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgkJJgAVALAjAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECgoKKwAXANIhAA==.',
Op='Ophindis:BAABNQAECn8kAAMOAAkKyR79HwCzAgAOAAkKyR79HwCzAgAQAAEKcQp24QAyAAAAAA==.',
Os='Osten:BAAANQAECgUIDQAAAA==.',
Pa='Pagoda:BAABNQAECn8oAAMbAAoK5RLdFAAtAgAbAAoK5RLdFAAtAgAWAAQKNhbxRwDhAAAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIGAAYKyyEpfwAOAgAGAAYKyyEpfwAOAgAAAA==.',
Pi='Pintsize:BAAANQABCggICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Pr='Praystation:BAAANQAECgIIAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8jAAIYAAkK1BaYPwDMAgAYAAkK1BaYPwDMAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAEAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn85AAMBAAoKVxYUDwADAgABAAoKVxYUDwADAgAVAAYKLAneOwATAQAAAA==.Rennx:BAACNQAFFH8eAAIDAAcK8BvLAwB/AgADAAcK8BvLAwB/AgA1AAQKfyQAAgMACgqqJeEFAKcDAAMACgqqJeEFAKcDAAAA.Reznik:BAABNQAECn8uAAIOAAgKRRrvDgBsAQAOAAgKRRrvDgBsAQAAAA==.',
Ri='Rika:BAAANQAECgMIBAAAAA==.Ringmasta:BAAANQAECgMIBgAAAA==.Riot:BAABNQAECn81AAIGAAoKdxyZOADAAgAGAAoKdxyZOADAAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8gAAMfAAYK2xtuGQAUAQAfAAYK2xtuGQAUAQARAAEKbxV5ngA+AAAAAA==.',
['Rè']='Rènza:BAAANQAECggIDQAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgkJIQABAMAaAA==.Saphia:BAECNQAFFH8SAAIVAAcKRB0/AgAYAgAVAAcKRB0/AgAYAgA1AAQKfy0AAhUACgqOJWMBAMsDABUACgqOJWMBAMsDAAAA.Saphyr:BAECNQAFFH8IAAIOAAYKyBU0BwDzAQAOAAYKyBU0BwDzAQA1AAQKfx4AAw4ACgroIFIFAPYBAA4ACgroIFIFAPYBABAAAwquCgy2AIIAAAE1AAUUBwgSABUARB0A.',
Sb='Sblakedragon:BAAANQAECgYICQAAAA==.',
Sc='Scarydude:BAABNQAECn8cAAIhAAgKQRo7BADcAQAhAAgKQRo7BADcAQAAAA==.',
Se='Senniel:BAAANQAECgMIAwAAAA==.Sevrin:BAABNQAECn8uAAMWAAoK4BxLEgDKAgAWAAoK4BxLEgDKAgAaAAEKAADLMAA3AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAAANQAECgUIDwABNQAECgYIBQAEAAAAAA==.Sheesh:BAABNQAECn85AAMcAAoKUyRKCABBAwAcAAoKUyRKCABBAwADAAQKnRbNawAcAQAAAA==.Shinru:BAABNQAECn88AAMCAAoKnSLzDABhAwACAAoKnSLzDABhAwABAAMK7xUZOAHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAECgoKHgAVAGcfAA==.',
Si='Sickdayze:BAABNQAECn8jAAICAAkKtB5aKADHAgACAAkKtB5aKADHAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgkJIwACALQeAA==.Sickntired:BAAANQADCgMJAwABNQAECgkJIwACALQeAA==.Sicktides:BAAANQADCgYICAABNQAECgkJIwACALQeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIHAAcKLRVCfQCUAQAHAAcKLRVCfQCUAQAAAA==.',
Sn='Snaffu:BAAANQAECgYIDgAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAACNQAFFH8FAAIcAAUKsx2bAQC9AQAcAAUKsx2bAQC9AQA1AAQKfygAAxwACgoGJEcDAJQDABwACgoGJEcDAJQDAAMAAQoAAKOmAEsAAAE1AAUUBQgPAAEAsSQA.Sophie:BAACNQAFFH8PAAIBAAUKsSTcBwDPAQABAAUKsSTcBwDPAQA1AAQKfzQAAgEACgqhJYwHAL4DAAEACgqhJYwHAL4DAAAA.Sophisticate:BAABNQAECn8oAAIjAAoKyR+EAQBUAwAjAAoKyR+EAQBUAwABNQAFFAUIDwABALEkAA==.Sophiz:BAABNQAECn8nAAIhAAoK7hx/BwCWAQAhAAoK7hx/BwCWAQABNQAFFAUIDwABALEkAA==.Sophlax:BAABNQAECn8pAAIiAAoKESIUCgByAwAiAAoKESIUCgByAwABNQAFFAUIDwABALEkAA==.Sophs:BAABNQAECn8eAAMHAAcKxRmHfwCNAQAHAAcKxRmHfwCNAQAIAAUKkBnsmwBgAQABNQAFFAUIDwABALEkAA==.Sophz:BAABNQAECn8eAAIQAAkKSCD1BgC/AQAQAAkKSCD1BgC/AQABNQAFFAUIDwABALEkAA==.Sox:BAABNQAECn8xAAIkAAoKWiVxAQDQAwAkAAoKWiVxAQDQAwAAAA==.',
Sp='Spicynoodle:BAABNQAECn8oAAIGAAoKOhwdPAC2AgAGAAoKOhwdPAC2AgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAABNQAECn8eAAIWAAkK3BtuFACyAgAWAAkK3BtuFACyAgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8lAAITAAkKsRQfEgDWAQATAAkKsRQfEgDWAQAAAA==.',
Su='Sua:BAACNQAFFH8ZAAIYAAcKshKKCAAuAgAYAAcKshKKCAAuAgA1AAQKfyUAAhgACgq/HwAxAPsCABgACgq/HwAxAPsCAAAA.Suksuksuk:BAAANQABCgYICgAAAA==.Supergogeta:BAABNQAECn8nAAMcAAgK4hUgEwAsAQAcAAgK4hUgEwAsAQADAAUKKg9mawAdAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEgAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn8sAAIYAAkK7hzkIQB8AQAYAAkK7hzkIQB8AQAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgMIBQAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgYICgAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgkJJAAOAMkeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAIlAAgK9BbpBQA7AgAlAAgK9BbpBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQICQAAAA==.',
Ty='Tyranis:BAEBNQAECn8YAAIFAAkKoByMBAD8AgAFAAkKoByMBAD8AgAAAA==.Tyê:BAABNQAECn8oAAMKAAoK8hI/GgAgAgAKAAoK8hI/GgAgAgAJAAEKAAC6PQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8IAAITAAQKshl4KABFAQATAAQKshl4KABFAQA1AAQKfyMAAhMACgq2H8MxACcDABMACgq2H8MxACcDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQADCgIIAgAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgYIBwAAAA==.',
Vo='Voiddemon:BAAANQAECgIIBAAAAA==.Voltage:BAAANQAECgQIDQABNQAECgYIGQAGAMshAA==.',
Vu='Vulgnash:BAABNQAECn86AAIQAAoKCiJFBwCLAwAQAAoKCiJFBwCLAwAAAA==.Vult:BAABNQAECn8rAAINAAoKRho+HgCZAgANAAoKRho+HgCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Welgo:BAABNQAECn8YAAIXAAoKTCAmAQBqAgAXAAoKTCAmAQBqAgAAAA==.Welmage:BAAANQAECgIIAgABNQAECgoKGAAXAEwgAA==.',
Wi='Wickeddemon:BAAANQAECgIIBAAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8qAAITAAkK4x3dTQDlAgATAAkK4x3dTQDlAgAAAA==.',
Xe='Xerra:BAABNQAECn8yAAIhAAoKwB/gCgAvAwAhAAoKwB/gCgAvAwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYICgAAAA==.Yemoja:BAAANQAECgQIBAAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAECgoKOQAcAFMkAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQAECgYICwAAAA==.',
Ze='Zeit:BAABNQAECn8XAAQFAAgKCw0IEwB9AQAFAAgKogwIEwB9AQAhAAMKjBBWVgC1AAAdAAMKZwkwNACYAAABNQAECgoKIwALAN0VAA==.Zelgie:BAABNQAECn8pAAICAAgKYhu0LwCnAgACAAgKYhu0LwCnAgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQADCgYIDAAAAA==.',
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
