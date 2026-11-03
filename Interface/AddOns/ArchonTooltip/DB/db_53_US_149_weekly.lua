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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Druid-Restoration','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Druid-Guardian','Druid-Feral','Mage-Frost','Mage-Arcane','Mage-Fire','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Priest-Holy','Priest-Discipline','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBQAAAA==.Abadizzoo:BAABNQAECn8UAAIBAAgKmR21VwBsAgABAAgKmR21VwBsAgAAAA==.Abeyancë:BAABNQAECn86AAQCAAoKOBlbXQCAAgACAAoKGRlbXQCAAgADAAIK8RJpBAFwAAAEAAEKaBbaUgBAAAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECn89AAIFAAoK2RvsGwDpAgAFAAoK2RvsGwDpAgAAAA==.Aite:BAAANQAECgYICQAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Amathal:BAAANQAECgQIBAABNQAECggIDwAGAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAABNQAECn83AAMCAAoKZBfOQAA2AgACAAoKZBfOQAA2AgADAAEKpgH19gAXAAABNQAECgoKIAAHABIcAA==.Artvandelay:BAAANQAECgQIBgABNQAECgoKOgABAFIcAA==.',
As='Asukà:BAABNQAECn8tAAMIAAoKyRg1QQBcAgAIAAoKyRg1QQBcAgAJAAIK3wH39QAZAAAAAA==.',
Au='Auchenile:BAABNQAECn8wAAMKAAkK7hXGCQCiAQAKAAkK7hXGCQCiAQALAAYKVQqMJwCSAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICQAAAA==.',
Av='Avanoura:BAAANQADCggIDQABNQAECggIGwAMAM0NAA==.',
['Aé']='Aéd:BAAANQAECgIIAgABNQAECgcIEAAGAAAAAA==.',
Ba='Barkthas:BAABNQAECn8YAAINAAkKUw6VRQCqAQANAAkKUw6VRQCqAQAAAA==.',
Be='Bellarg:BAABNQAECn85AAMOAAoKyhftLAAuAgAOAAoKyhftLAAuAgAPAAEKzQeXfQAvAAAAAA==.Belobog:BAAANQAECgYIBwABNQAECgcIFwAJALITAA==.Belyn:BAABNQAECn8WAAIDAAUKcxiYkABsAQADAAUKcxiYkABsAQAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgYIEgAAAA==.Bloodadinz:BAAANQAECgUICAAAAA==.',
Bo='Bonedaddy:BAABNQAECn8nAAMQAAkKQRZBLgBuAQANAAgKAxXjQADDAQAQAAcKzRJBLgBuAQAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAYIBwARAEEhAA==.Brbwifeaggro:BAAANQABCgIIBAAAAA==.Bro:BAABNQAECn8xAAQOAAoK1BhXRQDPAQAOAAoKaBZXRQDPAQAPAAIK6hhSTgCUAAASAAIKiwrKKQBFAAAAAA==.Brogue:BAABNQAECn8jAAMTAAoKGxIWDwCzAQAUAAkKExPaOgDNAQATAAkK9QoWDwCzAQAAAA==.Brolich:BAABNQAECn88AAMQAAoK9BbeLQBwAQAQAAoK9BbeLQBwAQAVAAEKlQrZ4QAyAAABNQAECgoKMQAOANQYAA==.Broo:BAABNQAECn8VAAUWAAgKcRgDIwAyAQAWAAcKxxgDIwAyAQAFAAIK9AfWnwBfAAARAAMK+AQaYABGAAAXAAEKxwKlRwAVAAABNQAECgoKMQAOANQYAA==.Brooak:BAABNQAECn8bAAMIAAgK6Av/pgAkAQAIAAcK4Qr/pgAkAQAJAAYKOQ6nfwDYAAABNQAECgoKMQAOANQYAA==.Brother:BAAANQAECgUIBgABNQAECgoKMQAOANQYAA==.Brozeit:BAABNQAECn8YAAQEAAkKoxUtIwDIAQAEAAkKoxUtIwDIAQACAAEKuw2wqQEyAAADAAIK8gW45AAvAAABNQAECgoKMQAOANQYAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Calculusx:BAABNQAECn8gAAITAAkKOiBzBgB4AgATAAkKOiBzBgB4AgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8gAAMYAAgK4BnzAgD3AAAZAAcKSxuoDQAKAgAYAAMKyRTzAgD3AAA1AAQKfz8ABBoACgpNJS0AAFQDABoACgq+JC0AAFQDABkACgrUI9gNAAoDABgAAQosJXo9AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAFFAQIDgAEALcaAA==.',
Cl='Clare:BAACNQAFFH8HAAIEAAIKDhU1CACAAAAEAAIKDhU1CACAAAA1AAQKfyYAAgQACgpnHxENAMoCAAQACgpnHxENAMoCAAAA.Cloúd:BAAANQAECgQICgAAAA==.',
Co='Colmacka:BAAANQAECgUIBwAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIbAAgKvhpPHgBAAgAbAAgKvhpPHgBAAgAAAA==.Darilol:BAAANQADCgYICAABNQAECgcIEAAGAAAAAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn86AAIQAAkKxyPODQBCAwAQAAkKxyPODQBCAwAAAA==.Demiize:BAABNQAECn8+AAIYAAoKmR0EBAD2AgAYAAoKmR0EBAD2AgAAAA==.Demize:BAABNQAECn9AAAIBAAoKKBtDJwD7AgABAAoKKBtDJwD7AgAAAA==.Demonflame:BAAANQAECgUIBQAAAA==.Demonhazard:BAAANQADCgIIAgAAAA==.Demíze:BAAANQAECgQICgAAAA==.Deshield:BAACNQAFFH8HAAMcAAMKHRfQEQDxAAAcAAMKxxXQEQDxAAAdAAEK+yMrBQBnAAA1AAQKfzMAAx0ACgpWJMADAFsDAB0ACAo/JsADAFsDABwACgrwIoIYAFYDAAAA.Deus:BAABNQAECn8YAAIZAAgKmAwT1gDbAQAZAAgKmAwT1gDbAQAAAA==.Dewry:BAABNQAECn8XAAIMAAgKIx6UFwCaAgAMAAgKIx6UFwCaAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn8+AAMeAAoKTCTmAQCZAwAeAAoKTCTmAQCZAwAbAAIK5xleXgBnAAAAAA==.',
Di='Diemertz:BAAANQAECgUICgAAAA==.Dingis:BAAANQAECgMIAwABNQAECgcIEAAGAAAAAA==.Divine:BAABNQAECn8aAAQMAAkKSBSKKADkAQAMAAkKSBSKKADkAQAfAAUKchPtigD/AAAgAAIK3g1IHgBuAAABNQAECgoKNAAhAOUSAA==.Dizzo:BAABNQAECn8nAAIVAAgKFhpcPwAhAgAVAAgKFhpcPwAhAgAAAA==.',
Do='Doink:BAABNQAECn8lAAIOAAoKIBgdKQBBAgAOAAoKIBgdKQBBAgABNQAFFAQICgARANMVAA==.Donnajuan:BAABNQAECn8jAAIDAAkKzBy0QQBeAgADAAkKzBy0QQBeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGQAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAcIGwAKADciAA==.',
El='Elimere:BAABNQAECn81AAIMAAoKhwxPKgDVAQAMAAoKhwxPKgDVAQAAAA==.Elinalise:BAAANQAECgQIBAABNQAECgoKJwABAJEZAA==.Elvarg:BAABNQAECn84AAIKAAoKnhuXCgDCAgAKAAoKnhuXCgDCAgAAAA==.Elywen:BAACNQAFFH8IAAIBAAMK7hFBEQDmAAABAAMK7hFBEQDmAAA1AAQKfzsAAgEACgoEIZsdACEDAAEACgoEIZsdACEDAAAA.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgcIDgAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECgoKKgAiAH4eAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAgIFAAEAGAaAA==.Finke:BAAANQAECgUIDgAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAgIGQAEAHQaAA==.Firesham:BAAANQADCgQIBAABNQAFFAYICwAjALoXAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAABNQAECn8ZAAIbAAgK0ASPRgDpAAAbAAgK0ASPRgDpAAAAAA==.',
Fr='Free:BAAANQAECgUIEAABNQAECggIHAAhABEUAA==.Frisbee:BAAANQAECgIIAgAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8zAAIZAAoKfw/xowA5AgAZAAoKfw/xowA5AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn82AAITAAoK8SJRAwD0AgATAAoK8SJRAwD0AgAAAA==.',
Gi='Gigazapper:BAABNQAECn8mAAMJAAkKLBLLggCeAQAJAAgKKw/LggCeAQAIAAYKKxSJWQB8AQABNQAFFAQIDgAEALcaAA==.Gil:BAAANQAECgUIBgAAAA==.Gizzlit:BAABNQAECn8kAAIkAAkKuBITEwA4AgAkAAkKuBITEwA4AgAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBQABNQAFFAcIDwAiABQgAA==.Gofetch:BAABNQAECn81AAIBAAkKvRlfPQCyAgABAAkKvRlfPQCyAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn86AAIBAAoKUhyJNwDEAgABAAoKUhyJNwDEAgAAAA==.',
Gs='Gson:BAABNQAECn8UAAIcAAkK8gTu8wD3AAAcAAkK8gTu8wD3AAAAAA==.',
Gu='Guppy:BAAANQAECgEIAQAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgoKIAATAP4VAA==.Hakka:BAABNQAECn8gAAMTAAoK/hWUPQDZAQATAAkKqAuUPQDZAQAUAAkKyxaQIQDAAQAAAA==.Hal:BAAANQADCgYICwABNQAECgkJHQAFAEsKAA==.Hallack:BAABNQAECn8dAAIFAAkKSwr8VQCAAQAFAAkKSwr8VQCAAQAAAA==.Harlemshakez:BAAANQABCgUIBgAAAA==.',
He='Healingkiss:BAAANQAECgIIBQAAAA==.',
Hi='Hikingboots:BAABNQAECn8yAAIJAAoK/Ao/RwB+AQAJAAoK/Ao/RwB+AQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn80AAMZAAoKEBzPTwD5AQAZAAoKEBzPTwD5AQAYAAIKHgxkNwBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICgABNQAECgUICgAGAAAAAA==.',
Il='Illani:BAAANQAECgEIAwAAAA==.Ilyanna:BAABNQAECn8yAAMPAAoKCxvtBwCDAgAPAAgKCBvtBwCDAgAOAAgKWxQVfAAyAQAAAA==.',
Im='Im:BAACNQAFFH8ZAAMlAAcKeiHzAwBCAgAlAAYKXiDzAwBCAgABAAEK6SU+LQBtAAA1AAQKf0AAAyUACgriJXQEAI4DACUACgriJXQEAI4DAAEAAQr0JRxAAWIAAAAA.Immagical:BAAANQAECgQIBAAAAA==.Imscary:BAAANQAECgYICgAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAABNQAECn8YAAIYAAcKuhfyEQCGAQAYAAcKuhfyEQCGAQAAAA==.',
Je='Jenyaa:BAAANQAECgYIBgAAAA==.',
Jh='Jhops:BAABNQAECn89AAMJAAoKVBxCIwAuAgAJAAoKVBxCIwAuAgAIAAEKMhML6AAuAAAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.Kaz:BAAANQAECggICQAAAA==.',
Ke='Keju:BAAANQAECgEIAQAAAA==.Kerrigan:BAABNQAECn8yAAMjAAoKRBsPJAAnAgAjAAoKRBsPJAAnAgAiAAUKGxAGWQAjAQABNQAECgoKJwABAJEZAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwAZAL4iAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJIwAZAL4iAA==.Kozand:BAAANQADCgYIDQABNQAECgcIEAAGAAAAAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgUICQAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgkJMAAKAO4VAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAABNQAECn8UAAIkAAgKWhUuFQAVAgAkAAgKWhUuFQAVAgAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAgIFAAEAGAaAA==.',
Ll='Llynryn:BAABNQAECn8bAAIMAAgKzQ1QJgAUAQAMAAgKzQ1QJgAUAQAAAA==.',
Lo='Locktuah:BAAANQAECgQIBwABNQAECgcIEAAGAAAAAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8xAAIZAAoKfCGyIwBPAwAZAAoKfCGyIwBPAwABNQAFFAcIGwAjAMUfAA==.Magicmanzz:BAABNQAECn8eAAIYAAcKpA1DFABlAQAYAAcKpA1DFABlAQAAAA==.Magnifuso:BAABNQAECn8aAAIEAAcKXgXtLQDXAAAEAAcKXgXtLQDXAAAAAA==.Maguapa:BAAANQAECgYIDQAAAA==.Malgata:BAABNQAECn8dAAIWAAYKuxDGKwA5AQAWAAYKuxDGKwA5AQAAAA==.Mangrove:BAAANQABCggIFAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8pAAICAAoKARmNZABtAgACAAoKARmNZABtAgAAAA==.Mastab:BAABNQAECn8uAAMDAAoK6xc+MgCcAgADAAoK6xc+MgCcAgACAAIK4AxQagF2AAAAAA==.',
Mc='Mchammerdin:BAABNQAECn8yAAQEAAoK0BkYEwC8AQACAAgKvxaghwAYAgAEAAcKrhkYEwC8AQADAAYKxBB9ZgBRAQAAAA==.',
Me='Meat:BAABNQAECn81AAMHAAkKmxxFBgAHAgAHAAgKmxxFBgAHAgAiAAEKAADZkwAzAAAAAA==.Merçenaries:BAAANQADCggICAAAAA==.',
Mi='Mikio:BAABNQAECn8oAAIFAAgKswo9PQADAQAFAAgKswo9PQADAQAAAA==.Milinka:BAABNQAECn8yAAIfAAoKNx5pIwDgAgAfAAoKNx5pIwDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAjAAwjAA==.',
Mo='Moiryn:BAAANQADCgMIAgAAAA==.',
My='Myshaman:BAABNQAECn8lAAMIAAkKfxqvLgA2AgAIAAkKfxqvLgA2AgAJAAEKQAlzOgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8bAAMKAAcKNyL9AABfAQAKAAYKzyH9AABfAQALAAEKYhdqEgBYAAA1AAQKf6oAAwoACgqHJk8AAPcDAAoACgqHJk8AAPcDAAsACQqMItIHACkDAAAA.',
No='Nota:BAAANQAECggICgAAAA==.Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgoKKgAEAMgjAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAFFAMIBwAcAB0XAA==.',
Op='Ophindis:BAABNQAECn8nAAMQAAkK8x79HwCzAgAQAAkK8x79HwCzAgAVAAEKcQp24QAyAAAAAA==.',
Os='Osten:BAAANQAECgUIDQAAAA==.',
Pa='Pagoda:BAABNQAECn80AAMhAAoK5RLdFAAtAgAhAAoK5RLdFAAtAgAbAAcKJhJ7JgAtAQAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIBAAYKyyEpfwAOAgABAAYKyyEpfwAOAgAAAA==.',
Pi='Pintsize:BAAANQABCggICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Po='Pond:BAAANQADCgYIBgAAAA==.Porkit:BAAANQAECgEIAQAAAA==.',
Pr='Praystation:BAAANQAECgYICAAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8jAAIcAAkK1BaYPwDMAgAcAAkK1BaYPwDMAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAGAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn9NAAMCAAoKXBiMOwBJAgACAAoKXBiMOwBJAgAEAAYKLAneOwATAQAAAA==.Rennx:BAACNQAFFH8gAAIFAAgK5RzLAwB/AgAFAAgK5RzLAwB/AgA1AAQKfzgAAgUACgrAJi8AAJsDAAUACgrAJi8AAJsDAAAA.Reznik:BAABNQAECn88AAIQAAoKCRsZGQAQAgAQAAoKCRsZGQAQAgAAAA==.',
Ri='Rika:BAAANQAECgMIBAAAAA==.Ringmasta:BAAANQAECgUIDgAAAA==.Riot:BAABNQAECn9BAAIBAAoKoxyZOADAAgABAAoKoxyZOADAAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8nAAMUAAcKzRn3GQAJAgAUAAcKzRn3GQAJAgATAAEKbxV5ngA+AAAAAA==.',
['Rè']='Rènza:BAABNQAECn8jAAIiAAoKZxevFwAkAgAiAAoKZxevFwAkAgAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgkJMgACAO0dAA==.Saphia:BAECNQAFFH8UAAIEAAgKYBo/AgAYAgAEAAgKYBo/AgAYAgA1AAQKfzkAAwQACgqOJWMBAMsDAAQACgqOJWMBAMsDAAIABAqFFYLyAMMAAAAA.Saphyr:BAECNQAFFH8IAAIQAAYKyBU0BwDzAQAQAAYKyBU0BwDzAQA1AAQKfyUABBAACgrCIY8SABgDABAACgrCIY8SABgDAA0ABQr8DxZtALAAABUAAwquCgy2AIIAAAE1AAUUCAgUAAQAYBoA.',
Sb='Sblakedragon:BAAANQAECgYICgAAAA==.',
Sc='Scarydude:BAABNQAECn8nAAIjAAoKVRgbEgAMAgAjAAoKVRgbEgAMAgAAAA==.',
Se='Senniel:BAAANQAECgQICAAAAA==.Sevrin:BAABNQAECn8uAAMbAAoK4BxLEgDKAgAbAAoK4BxLEgDKAgAeAAEKAADLMAA3AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAABNQAECn8XAAIJAAcKshOHUwBSAQAJAAcKshOHUwBSAQAAAA==.Sheesh:BAACNQAFFH8KAAIRAAQK0xVGBwBBAQARAAQK0xVGBwBBAQA1AAQKf00AAxEACgqUJT8FAGwDABEACgqUJT8FAGwDAAUABgoeGDBKAMgAAAAA.Shinru:BAABNQAECn9IAAMDAAoK/CLzDABhAwADAAoK/CLzDABhAwACAAMKkxYZOAHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAFFAIIBwAEAA4VAA==.',
Si='Sickdayze:BAABNQAECn8jAAIDAAkKtB5aKADHAgADAAkKtB5aKADHAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgkJIwADALQeAA==.Sickntired:BAAANQADCgMJAwABNQAECgkJIwADALQeAA==.Sicktides:BAAANQADCgYICAABNQAECgkJIwADALQeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIIAAcKLRVCfQCUAQAIAAcKLRVCfQCUAQAAAA==.',
Sn='Snaffu:BAABNQAECn8WAAIOAAkKCRLIdABDAQAOAAkKCRLIdABDAQAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAACNQAFFH8HAAIRAAYKQSGJAgAbAgARAAYKQSGJAgAbAgA1AAQKfzMAAxEACgoSJUcDAJQDABEACgoSJUcDAJQDAAUAAQoAAKOmAEsAAAAA.Sophie:BAACNQAFFH8PAAICAAUKsSTcBwDPAQACAAUKsSTcBwDPAQA1AAQKfz4AAgIACgpnJowHAL4DAAIACgpnJowHAL4DAAE1AAUUBggHABEAQSEA.Sophisticate:BAABNQAECn8zAAImAAoKyR+EAQBUAwAmAAoKyR+EAQBUAwABNQAFFAYIBwARAEEhAA==.Sophiz:BAABNQAECn8xAAIjAAoK1R0cDwD8AgAjAAoK1R0cDwD8AgABNQAFFAYIBwARAEEhAA==.Sophlax:BAABNQAECn8uAAIfAAoKsCIUCgByAwAfAAoKsCIUCgByAwABNQAFFAYIBwARAEEhAA==.Sophs:BAABNQAECn8mAAMIAAgKmBqHfwCNAQAIAAgKmBqHfwCNAQAJAAUK/hnsmwBgAQABNQAFFAYIBwARAEEhAA==.Sophz:BAABNQAECn8qAAIVAAkKGyE3GQD2AgAVAAkKGyE3GQD2AgABNQAFFAYIBwARAEEhAA==.Sox:BAABNQAECn87AAMWAAoKaCVxAQDQAwAWAAoKaCVxAQDQAwAXAAEKchM3OQA7AAAAAA==.',
Sp='Spicynoodle:BAABNQAECn8sAAIBAAoKOhwdPAC2AgABAAoKOhwdPAC2AgAAAA==.Spookyougi:BAAANQAECgQICwAAAA==.',
Sq='Squattinchop:BAABNQAECn8qAAIbAAoKXR40DABxAgAbAAoKXR40DABxAgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8xAAIZAAkK7xfKQAAmAgAZAAkK7xfKQAAmAgAAAA==.',
Su='Sua:BAACNQAFFH8bAAIcAAgKxhCKCAAuAgAcAAgKxhCKCAAuAgA1AAQKfzMAAhwACgqVJIkMACEDABwACgqVJIkMACEDAAAA.Suksuksuk:BAAANQABCgYICgAAAA==.Supergogeta:BAABNQAECn8vAAMRAAoKZhXFJgDrAQARAAoKZhXFJgDrAQAFAAUKKg9mawAdAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEgAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn86AAIcAAoKGh8KOwAqAgAcAAoKGh8KOwAqAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgQICQAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgUICgAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgkJJwAQAPMeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAIgAAgK9BbpBQA7AgAgAAgK9BbpBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQICQAAAA==.',
Ty='Tyranis:BAABNQAECn8gAAIHAAoKEhyMBAD8AgAHAAoKEhyMBAD8AgAAAA==.Tyê:BAABNQAECn8sAAMLAAoKHBQ/GgAgAgALAAoKHBQ/GgAgAgAKAAEKAAC6PQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8IAAIZAAQKshl4KABFAQAZAAQKshl4KABFAQA1AAQKfyMAAhkACgq2H8MxACcDABkACgq2H8MxACcDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQAECgQIBAAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Ve='Vee:BAAANQAECgEIAQAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voiddemon:BAAANQAECgIIBAAAAA==.Voltage:BAAANQAECgQIDQABNQAECgYIGQABAMshAA==.',
Vu='Vulgnash:BAACNQAFFH8HAAIVAAMK1BwoBAATAQAVAAMK1BwoBAATAQA1AAQKf0wAAhUACgpqJB8EACsDABUACgpqJB8EACsDAAAA.Vult:BAABNQAECn8rAAINAAoKRho+HgCZAgANAAoKRho+HgCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Weiyoung:BAAANQAECgEIAQAAAA==.Welgo:BAABNQAECn8mAAIdAAoKJiHiAwBWAwAdAAoKJiHiAwBWAwAAAA==.Welmage:BAAANQAECgIIAgABNQAECgoKJgAdACYhAA==.',
Wi='Wickeddemon:BAAANQAECgUICQAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8uAAIZAAoKOBzdTQDlAgAZAAoKOBzdTQDlAgAAAA==.',
Xe='Xerra:BAACNQAFFH8FAAIjAAIKdhG9CgCPAAAjAAIKdhG9CgCPAAA1AAQKfzoAAiMACgr4H+AKAC8DACMACgr4H+AKAC8DAAAA.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYIEwAAAA==.Yemoja:BAAANQAECgUICgAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAFFAQICgARANMVAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAAANQAECgcIEAAAAA==.',
Ze='Zeit:BAABNQAECn8hAAQHAAgKew81DQBBAQAHAAgKEg81DQBBAQAjAAMKjBBWVgC1AAAiAAQKZwmnXAB9AAABNQAECgoKMQAOANQYAA==.Zelgie:BAABNQAECn81AAIDAAoK/hlEGwCwAgADAAoK/hlEGwCwAgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.',
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
