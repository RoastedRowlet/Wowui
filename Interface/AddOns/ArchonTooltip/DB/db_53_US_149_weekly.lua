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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Mage-Frost','Mage-Arcane','Mage-Fire','Monk-Windwalker','Warrior-Protection','Warrior-Arms','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','DemonHunter-Havoc','Shaman-Enhancement','Hunter-Marksmanship','DemonHunter-Devourer','Druid-Guardian','Hunter-Survival','Druid-Feral',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBQAAAA==.Abadizzoo:BAABNQAECn8UAAIBAAgKmR21VwBsAgABAAgKmR21VwBsAgAAAA==.Abeyancë:BAABNQAECn80AAQCAAoKOBlbXQCAAgACAAoKhhhbXQCAAgADAAIK8RJpBAFwAAAEAAEKaBaXRQBCAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECn83AAIFAAoK2RvsGwDpAgAFAAoK2RvsGwDpAgAAAA==.Aite:BAAANQAECgUICAAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAEBNQAECn8vAAMCAAoKCxeATQDOAQACAAkKPhaATQDOAQADAAEKpgFD2wAXAAABNQAECgoKHAAHABIcAA==.Artvandelay:BAAANQAECgQIBgABNQAECggIMwABAO0fAA==.',
As='Asukà:BAABNQAECn8tAAMIAAoKyRg1QQBcAgAIAAoKyRg1QQBcAgAJAAIK3wF41QAZAAAAAA==.',
Au='Auchenile:BAABNQAECn8tAAMKAAkK7hUyBwCuAQAKAAkK7hUyBwCuAQALAAMKzgkhQQCYAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICQAAAA==.',
Av='Avanoura:BAAANQADCggIDQABNQAECgcIGQAMAHoNAA==.',
['Aé']='Aéd:BAAANQAECgIIAgABNQAECgYIEAAGAAAAAA==.',
Ba='Barkthas:BAAANQAECgcIEAAAAA==.',
Be='Bellarg:BAABNQAECn8wAAMNAAoKyhfJHgBFAgANAAoKyhfJHgBFAgAOAAEKzQeXfQAvAAAAAA==.Belobog:BAAANQAECgcIBwABNQAECgcIFQAJAMUSAA==.Belyn:BAABNQAECn8WAAIDAAUKcxivYAAfAQADAAUKcxivYAAfAQAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgYIDQAAAA==.Bloodadinz:BAAANQAECgUIBwAAAA==.',
Bo='Bonedaddy:BAABNQAECn8gAAMPAAcKPBbjQADDAQAPAAcKPBbjQADDAQAQAAUK5wQqUwCdAAAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAUIDwACALEkAA==.Brbwifeaggro:BAAANQABCgIIBAAAAA==.Bro:BAABNQAECn8sAAQNAAoKnxgMMwDfAQANAAoKNBYMMwDfAQAOAAIK6hhSTgCUAAARAAIKiwrKKQBFAAAAAA==.Brogue:BAABNQAECn8ZAAMSAAoKGxIBCwDSAQASAAkK9QoBCwDSAQATAAgKwROtNACaAQAAAA==.Brolich:BAABNQAECn83AAMQAAoK9BZZIwB5AQAQAAoK9BZZIwB5AQAUAAEKlQrZ4QAyAAABNQAECgoKLAANAJ8YAA==.Broo:BAAANQAECgcIEwABNQAECgoKLAANAJ8YAA==.Brooak:BAABNQAECn8bAAMIAAgK6AtXdADhAAAIAAcK4QpXdADhAAAJAAYKOQ5yZgDaAAABNQAECgoKLAANAJ8YAA==.Brother:BAAANQAECgUIBgABNQAECgoKLAANAJ8YAA==.Brozeit:BAAANQAECggIEQABNQAECgoKLAANAJ8YAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAABNQAECn8aAAISAAkKrx5tHACbAgASAAkKrx5tHACbAgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8gAAMVAAgK4BnzAgD3AAAWAAcKSxuoDQAKAgAVAAMKyRTzAgD3AAA1AAQKfzUABBYACgrVIxsHACYDABYACgrUIxsHACYDABcAAwqfIU8GAPoAABUAAQosJXo9AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAECggIIwAJAIATAA==.',
Cl='Clare:BAACNQAFFH8FAAIEAAIKBxR+BgCFAAAEAAIKBxR+BgCFAAA1AAQKfyIAAgQACgpnHxENAMoCAAQACgpnHxENAMoCAAAA.Cloúd:BAAANQAECgQICgAAAA==.',
Co='Colmacka:BAAANQAECgQIBAAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIYAAgKvhpPHgBAAgAYAAgKvhpPHgBAAgAAAA==.Darilol:BAAANQADCgYICAABNQAECgYIEAAGAAAAAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn8yAAIQAAkKxyPODQBCAwAQAAkKxyPODQBCAwAAAA==.Demiize:BAABNQAECn83AAIVAAoKXR0EBAD2AgAVAAoKXR0EBAD2AgAAAA==.Demize:BAABNQAECn87AAIBAAoKOxpDJwD7AgABAAoKOxpDJwD7AgAAAA==.Demonflame:BAAANQAECgUIBQAAAA==.Demíze:BAAANQAECgQICgAAAA==.Deshield:BAABNQAECn8vAAMZAAoKViTAAwBbAwAZAAgKPybAAwBbAwAaAAoKySKCGABWAwAAAA==.Deus:BAABNQAECn8YAAIWAAgKmAwT1gDbAQAWAAgKmAwT1gDbAQAAAA==.Dewry:BAABNQAECn8XAAIMAAgKIx6UFwCaAgAMAAgKIx6UFwCaAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn85AAMbAAoK8CPmAQCZAwAbAAoK8CPmAQCZAwAYAAIK5xleXgBnAAAAAA==.',
Di='Diemertz:BAAANQAECgYIBQAAAA==.Dingis:BAAANQAECgMIAwABNQAECgYIEAAGAAAAAA==.Divine:BAABNQAECn8UAAQMAAkKthWKKADkAQAMAAgKixOKKADkAQAcAAUKchP+gADXAAAdAAIK3g1IHgBuAAABNQAECgoKLgAeAOUSAA==.Dizzo:BAABNQAECn8nAAIUAAgKFhpcPwAhAgAUAAgKFhpcPwAhAgAAAA==.',
Do='Doink:BAABNQAECn8iAAINAAoKQRXjKwABAgANAAoKQRXjKwABAgABNQAFFAMIBwAfAKgVAA==.Donnajuan:BAABNQAECn8fAAIDAAgK8hy0QQBeAgADAAgK8hy0QQBeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGQAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAYIGgAKAI4jAA==.',
El='Elimere:BAABNQAECn8vAAIMAAoKhQxPKgDVAQAMAAoKhQxPKgDVAQAAAA==.Elvarg:BAABNQAECn8zAAIKAAoKMxuXCgDCAgAKAAoKMxuXCgDCAgAAAA==.Elywen:BAACNQAFFH8IAAIBAAMK7hELDQDsAAABAAMK7hELDQDsAAA1AAQKfzIAAgEACgoEIZsdACEDAAEACgoEIZsdACEDAAAA.',
En='Enry:BAAANQADCggIEAAAAA==.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgQICAAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECgoKKgAgAH4eAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAcIEgAEAEQdAA==.Finke:BAAANQAECgYIDQAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAgIGQAEAHQaAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAABNQAECn8UAAIYAAgKogSPRgDpAAAYAAgKogSPRgDpAAAAAA==.',
Fr='Free:BAAANQAECgUIEAABNQAECgcIEwAGAAAAAA==.Frisbee:BAAANQAECgIIAgAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8zAAIWAAoKfw/xowA5AgAWAAoKfw/xowA5AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn8yAAISAAkKliN3AwC7AgASAAkKliN3AwC7AgAAAA==.',
Gi='Gigazapper:BAABNQAECn8jAAMJAAgKgBPLggCeAQAJAAcKBRDLggCeAQAIAAUKGRdaTwBZAQAAAA==.Gil:BAAANQABCgQIBwAAAA==.Gizzlit:BAABNQAECn8hAAIhAAkKuBITEwA4AgAhAAkKuBITEwA4AgAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBQABNQAFFAYIDgAgAGghAA==.Gofetch:BAABNQAECn8yAAIBAAkKmRlfPQCyAgABAAkKmRlfPQCyAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn8zAAIBAAgK7R+JNwDEAgABAAgK7R+JNwDEAgAAAA==.',
Gs='Gson:BAABNQAECn8UAAIaAAkK8gTu8wD3AAAaAAkK8gTu8wD3AAAAAA==.',
Gu='Guppy:BAAANQAECgEIAQAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgoKIAASAP4VAA==.Hakka:BAABNQAECn8gAAMSAAoK/hWUPQDZAQASAAkKqAuUPQDZAQATAAkKyxZOPgBpAQAAAA==.Hal:BAAANQADCgYICwABNQAECggIGwAFAIkKAA==.Hallack:BAABNQAECn8bAAIFAAgKiQr8VQCAAQAFAAgKiQr8VQCAAQAAAA==.Harlemshakez:BAAANQABCgUIBgAAAA==.',
He='Healingkiss:BAAANQAECgIIBQAAAA==.',
Hi='Hikingboots:BAABNQAECn8oAAIJAAgKWgxiSwArAQAJAAgKWgxiSwArAQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn8tAAMWAAkKKhulVQCrAQAWAAkKKhulVQCrAQAVAAIKHgxkNwBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICgABNQAECgYICgAGAAAAAA==.',
Il='Illani:BAAANQAECgEIAwAAAA==.Ilyanna:BAABNQAECn8sAAMOAAoKRxjtBwCDAgAOAAgKCBvtBwCDAgANAAgKrBBmcQAYAQAAAA==.',
Im='Im:BAACNQAFFH8ZAAMiAAcKeiHzAwBCAgAiAAYKXiDzAwBCAgABAAEK6SU+LQBtAAA1AAQKfz8AAyIACgoMJXQEAI4DACIACgoMJXQEAI4DAAEAAQr0JRxAAWIAAAAA.Immagical:BAAANQAECgQIBAAAAA==.Imscary:BAAANQAECgUICQAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAABNQAECn8XAAIVAAcKqxbyEQCGAQAVAAcKqxbyEQCGAQAAAA==.',
Je='Jenyaa:BAAANQADCggIHQAAAA==.',
Jh='Jhops:BAABNQAECn81AAMJAAgKYx5NQgBsAgAJAAgKYx5NQgBsAgAIAAEKMhPtywAxAAAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.',
Ke='Keju:BAAANQAECgEJAQAAAA==.Kerrigan:BAABNQAECn8uAAMjAAoK2hkTFwCDAQAjAAoK2hkTFwCDAQAgAAUKGxAGWQAjAQAAAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwAWAL4iAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJIwAWAL4iAA==.Kozand:BAAANQADCgQICwABNQAECgYIEAAGAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgUIBQAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgkJLQAKAO4VAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAABNQAECn8UAAIhAAgKWhUuFQAVAgAhAAgKWhUuFQAVAgAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAcIEgAEAEQdAA==.',
Ll='Llynryn:BAABNQAECn8ZAAIMAAcKeg28PgA4AQAMAAcKeg28PgA4AQAAAA==.',
Lo='Locktuah:BAAANQAECgQIBwABNQAECgYIEAAGAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8xAAIWAAoKfCGyIwBPAwAWAAoKfCGyIwBPAwABNQAFFAcIGwAjAMUfAA==.Magicmanzz:BAABNQAECn8ZAAIVAAcKpA1DFABlAQAVAAcKpA1DFABlAQAAAA==.Magnifuso:BAAANQAECgYIEwAAAA==.Maguapa:BAAANQAECgYIDQAAAA==.Malgata:BAABNQAECn8XAAIkAAYK5g/GKwA5AQAkAAYK5g/GKwA5AQAAAA==.Mangrove:BAAANQABCggIEQAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8nAAICAAoKARmNZABtAgACAAoKARmNZABtAgAAAA==.Mastab:BAABNQAECn8uAAMDAAoK6xc+MgCcAgADAAoK6xc+MgCcAgACAAIK4AxQagF2AAAAAA==.',
Mc='Mchammerdin:BAABNQAECn8rAAQEAAoKrBemFQBZAQACAAgKvxaghwAYAgADAAYKxBD/TgBbAQAEAAYKPxemFQBZAQAAAA==.',
Me='Meat:BAABNQAECn8yAAMHAAkKShv3BADvAQAHAAgKShv3BADvAQAgAAEKAADZkwAzAAAAAA==.Merçenaries:BAAANQADCggICAAAAA==.',
Mi='Mikio:BAABNQAECn8lAAIFAAcKVAygMwABAQAFAAcKVAygMwABAQAAAA==.Milinka:BAABNQAECn8tAAIcAAoKzB1pIwDgAgAcAAoKzB1pIwDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAjAAwjAA==.',
Mo='Moiryn:BAAANQADCgIIAgAAAA==.',
My='Myshaman:BAABNQAECn8hAAMIAAgKjxuHMQDbAQAIAAgKjxuHMQDbAQAJAAEKQAlzOgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8aAAMKAAYKjiMOAgANAgAKAAUKdSMOAgANAgALAAEKYhdlDwBYAAA1AAQKf5gAAwoACgrRJU8AAPcDAAoACgrRJU8AAPcDAAsACQqMItIHACkDAAAA.',
No='Nota:BAAANQAECgMIAgAAAA==.Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgoKKgAEAMgjAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAECgoKLwAZAFYkAA==.',
Op='Ophindis:BAABNQAECn8nAAMQAAkK8x79HwCzAgAQAAkK8x79HwCzAgAUAAEKcQp24QAyAAAAAA==.',
Os='Osten:BAAANQAECgUIDQAAAA==.',
Pa='Pagoda:BAABNQAECn8uAAMeAAoK5RLdFAAtAgAeAAoK5RLdFAAtAgAYAAcKTA80JAADAQAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIBAAYKyyEpfwAOAgABAAYKyyEpfwAOAgAAAA==.',
Pi='Pintsize:BAAANQABCggICgAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Po='Pond:BAAANQADCgYIBgAAAA==.Porkit:BAAANQAECgEIAQAAAA==.',
Pr='Praystation:BAAANQAECgMIAgAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8jAAIaAAkK1BaYPwDMAgAaAAkK1BaYPwDMAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAGAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn9DAAMCAAoKhRa4QwDuAQACAAoKhRa4QwDuAQAEAAYKLAneOwATAQAAAA==.Rennx:BAACNQAFFH8gAAIFAAgK5RzLAwB/AgAFAAgK5RzLAwB/AgA1AAQKfy4AAgUACgpgJrAAAIIDAAUACgpgJrAAAIIDAAAA.Reznik:BAABNQAECn80AAIQAAkKAhcUIwB7AQAQAAkKAhcUIwB7AQAAAA==.',
Ri='Rika:BAAANQAECgMIBAAAAA==.Ringmasta:BAAANQAECgMICQAAAA==.Riot:BAABNQAECn87AAIBAAoKdxyZOADAAgABAAoKdxyZOADAAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8nAAMTAAcKzRn3GQAJAgATAAcKzRn3GQAJAgASAAEKbxV5ngA+AAAAAA==.',
['Rè']='Rènza:BAABNQAECn8aAAIgAAoKgRSvGADdAQAgAAoKgRSvGADdAQAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgkJKQACALYdAA==.Saphia:BAECNQAFFH8SAAIEAAcKRB0/AgAYAgAEAAcKRB0/AgAYAgA1AAQKfzgAAwQACgqOJWMBAMsDAAQACgqOJWMBAMsDAAIABAqFFaXJAMwAAAAA.Saphyr:BAECNQAFFH8IAAIQAAYKyBU0BwDzAQAQAAYKyBU0BwDzAQA1AAQKfyQABBAACgqDIY8SABgDABAACgqDIY8SABgDAA8ABQr8D89YALkAABQAAwquCgy2AIIAAAE1AAUUBwgSAAQARB0A.',
Sb='Sblakedragon:BAAANQAECgYICgAAAA==.',
Sc='Scarydude:BAABNQAECn8gAAIjAAgKQRrAFQCVAQAjAAgKQRrAFQCVAQAAAA==.',
Se='Senniel:BAAANQAECgQIBAAAAA==.Sevrin:BAABNQAECn8uAAMYAAoK4BxLEgDKAgAYAAoK4BxLEgDKAgAbAAEKAADLMAA3AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAABNQAECn8VAAIJAAcKxRLJPwBVAQAJAAcKxRLJPwBVAQAAAA==.Sheesh:BAACNQAFFH8HAAIfAAMKqBXcBwDnAAAfAAMKqBXcBwDnAAA1AAQKf0QAAx8ACgp2JEoIAEEDAB8ACgp2JEoIAEEDAAUABgoeGM1rABwBAAAA.Shinru:BAABNQAECn9AAAMDAAoKnSLzDABhAwADAAoKnSLzDABhAwACAAMKkxYZOAHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAFFAIIBQAEAAcUAA==.',
Si='Sickdayze:BAABNQAECn8jAAIDAAkKtB5aKADHAgADAAkKtB5aKADHAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgkJIwADALQeAA==.Sickntired:BAAANQADCgMJAwABNQAECgkJIwADALQeAA==.Sicktides:BAAANQADCgYICAABNQAECgkJIwADALQeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIIAAcKLRVCfQCUAQAIAAcKLRVCfQCUAQAAAA==.',
Sn='Snaffu:BAAANQAECggIEgAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAACNQAFFH8GAAIfAAUKYSDzAgC7AQAfAAUKYSDzAgC7AQA1AAQKfy8AAx8ACgqvJEcDAJQDAB8ACgqvJEcDAJQDAAUAAQoAAKOmAEsAAAE1AAUUBQgPAAIAsSQA.Sophie:BAACNQAFFH8PAAICAAUKsSTcBwDPAQACAAUKsSTcBwDPAQA1AAQKfzoAAgIACgraJYwHAL4DAAIACgraJYwHAL4DAAAA.Sophisticate:BAABNQAECn8tAAIlAAoKyR+EAQBUAwAlAAoKyR+EAQBUAwABNQAFFAUIDwACALEkAA==.Sophiz:BAABNQAECn8tAAIjAAoKmB0cDwD8AgAjAAoKmB0cDwD8AgABNQAFFAUIDwACALEkAA==.Sophlax:BAABNQAECn8qAAIcAAoKTCIUCgByAwAcAAoKTCIUCgByAwABNQAFFAUIDwACALEkAA==.Sophs:BAABNQAECn8hAAMIAAcK8RmHfwCNAQAIAAcK8RmHfwCNAQAJAAUKkBnsmwBgAQABNQAFFAUIDwACALEkAA==.Sophz:BAABNQAECn8kAAIUAAkK9iA3GQD2AgAUAAkK9iA3GQD2AgABNQAFFAUIDwACALEkAA==.Sox:BAABNQAECn81AAMkAAoKaCVxAQDQAwAkAAoKaCVxAQDQAwAmAAEKchOlKwBDAAAAAA==.',
Sp='Spicynoodle:BAABNQAECn8oAAIBAAoKOhwdPAC2AgABAAoKOhwdPAC2AgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAABNQAECn8mAAIYAAkKIh1uFACyAgAYAAkKIh1uFACyAgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8uAAIWAAkK7xd2LQA8AgAWAAkK7xd2LQA8AgAAAA==.',
Su='Sua:BAACNQAFFH8bAAIaAAgKxhCKCAAuAgAaAAgKxhCKCAAuAgA1AAQKfykAAhoACgojIAAxAPsCABoACgojIAAxAPsCAAAA.Suksuksuk:BAAANQABCgYICgAAAA==.Supergogeta:BAABNQAECn8oAAMfAAgK4hXFJgDrAQAfAAgK4hXFJgDrAQAFAAUKKg9mawAdAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEgAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn8yAAIaAAkKtR0pWACDAgAaAAkKtR0pWACDAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgQIBwAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgYICgAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgkJJwAQAPMeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAIdAAgK9BbpBQA7AgAdAAgK9BbpBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQICQAAAA==.',
Ty='Tyranis:BAEBNQAECn8cAAIHAAoKEhyMBAD8AgAHAAoKEhyMBAD8AgAAAA==.Tyê:BAABNQAECn8sAAMLAAoKHBQ/GgAgAgALAAoKHBQ/GgAgAgAKAAEKAAC6PQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8IAAIWAAQKshl4KABFAQAWAAQKshl4KABFAQA1AAQKfyMAAhYACgq2H8MxACcDABYACgq2H8MxACcDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQAECgQIBAAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voiddemon:BAAANQAECgIIBAAAAA==.Voltage:BAAANQAECgQIDQABNQAECgYIGQABAMshAA==.',
Vu='Vulgnash:BAABNQAECn9DAAIUAAoKAiOLAwAaAwAUAAoKAiOLAwAaAwAAAA==.Vult:BAABNQAECn8rAAIPAAoKRho+HgCZAgAPAAoKRho+HgCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Welgo:BAABNQAECn8iAAIZAAoKJiHMAgDSAgAZAAoKJiHMAgDSAgAAAA==.Welmage:BAAANQAECgIIAgABNQAECgoKIgAZACYhAA==.',
Wi='Wickeddemon:BAAANQAECgMIBwAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8qAAIWAAkK4x3dTQDlAgAWAAkK4x3dTQDlAgAAAA==.',
Xe='Xerra:BAABNQAECn83AAIjAAoK+B/gCgAvAwAjAAoK+B/gCgAvAwAAAA==.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgcICgAAAA==.Yemoja:BAAANQAECgUICQAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAFFAMIBwAfAKgVAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQAECgYIEAAAAA==.',
Ze='Zeit:BAABNQAECn8fAAQHAAgKew/4CQBHAQAHAAgKEg/4CQBHAQAjAAMKjBBWVgC1AAAgAAMKZwmSTgCLAAABNQAECgoKLAANAJ8YAA==.Zelgie:BAABNQAECn8uAAIDAAgKhBu0LwCnAgADAAgKhBu0LwCnAgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQADCgYIDAAAAA==.',
['Ác']='Áchillès:BAAANQAECggICAAAAA==.',
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
