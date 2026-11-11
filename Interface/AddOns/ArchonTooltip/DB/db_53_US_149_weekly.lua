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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Paladin-Protection','Druid-Balance','Unknown-Unknown','DemonHunter-Vengeance','Shaman-Restoration','Shaman-Elemental','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Druid-Restoration','Warlock-Affliction','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Druid-Guardian','Druid-Feral','Mage-Frost','Mage-Arcane','Mage-Fire','Monk-Windwalker','Warrior-Arms','Warrior-Protection','Monk-Brewmaster','Priest-Holy','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival',}
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBwAAAA==.Abadizzoo:BAABNQAECn8UAAIBAAgKmR21VwBsAgABAAgKmR21VwBsAgAAAA==.Abeyancë:BAABNQAECn86AAQCAAoKOBlbXQCAAgACAAoKGRlbXQCAAgADAAIK8RJpBAFwAAAEAAEKaBaIWgA+AAAAAA==.Abilities:BAAANQAECgEIBQAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQAECgEIAQAAAA==.Airwrecka:BAABNQAECn89AAIFAAoK2RvsGwDpAgAFAAoK2RvsGwDpAgAAAA==.Aite:BAAANQAECgYICQAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amadk:BAAANQAECgIIAQABNQAECggIEQAGAAAAAA==.Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Amathal:BAAANQAECgQIBwABNQAECggIEQAGAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAABNQAECn83AAMCAAoKZBclUAAqAgACAAoKZBclUAAqAgADAAEKpgE+BgEXAAABNQAECgoKIAAHABIcAA==.Artvandelay:BAAANQAECgQICAABNQAECgoKPwABAH4cAA==.',
As='Asukà:BAABNQAECn8tAAMIAAoKyRg1QQBcAgAIAAoKyRg1QQBcAgAJAAIK3wFjCAEZAAAAAA==.',
Au='Auchenile:BAABNQAECn8wAAMKAAkK7hWNEABOAgAKAAkK7hWNEABOAgALAAYKVQpJKwCRAAAAAA==.Austin:BAAANQAECgIIBgAAAA==.Austinthedog:BAAANQAECggICgAAAA==.',
Av='Avanoura:BAAANQAECgEIAQABNQAECgkJHAAMAOkMAA==.',
['Aé']='Aéd:BAAANQAECgIIAgABNQAECggIGQANAF4OAA==.',
Ba='Barkthas:BAABNQAECn8aAAIOAAkK4w6VRQCqAQAOAAkK4w6VRQCqAQAAAA==.',
Be='Bellarg:BAABNQAECn8/AAMPAAoKzBfnMAA8AgAPAAoKzBfnMAA8AgAQAAEKzQeXfQAvAAAAAA==.Belobog:BAAANQAECgYICAABNQAECgcIFwAJALITAA==.Belyn:BAABNQAECn8YAAIDAAYK9ReCbwBTAQADAAYK9ReCbwBTAQAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgYIEgAAAA==.Bloodadinz:BAAANQAECgYIDwAAAA==.',
Bo='Bonedaddy:BAABNQAECn8pAAMOAAkKeRb/NQC0AQAOAAkK2xT/NQC0AQARAAcKzRIBNABqAQAAAA==.Bootsboots:BAAANQAECgcIBgAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAYIBwASAEEhAA==.Brbwifeaggro:BAAANQABCgIIBAAAAA==.Bro:BAABNQAECn82AAQPAAoKThl9TgDWAQAPAAoK4xZ9TgDWAQAQAAQKUBWtHQBxAAATAAIKiwrKKQBFAAAAAA==.Brogue:BAABNQAECn8zAAMUAAoKshTIEACvAQAVAAoKqBTaLgAuAgAUAAkK9QrIEACvAQAAAA==.Brolich:BAABNQAECn8+AAMRAAoK9BaUPgAGAgARAAoK9BaUPgAGAgAWAAEKlQrZ4QAyAAABNQAECgoKNgAPAE4ZAA==.Broo:BAABNQAECn8YAAUXAAgKcRjKKAAsAQAXAAcKxxjKKAAsAQAFAAIK9AfWnwBfAAASAAMK+AQ/aABJAAAYAAEKxwIiUQAVAAABNQAECgoKNgAPAE4ZAA==.Brooak:BAABNQAECn8bAAMIAAgK6Av/pgAkAQAIAAcK4Qr/pgAkAQAJAAYKOQ5vjgDYAAABNQAECgoKNgAPAE4ZAA==.Brother:BAAANQAECgUIBgABNQAECgoKNgAPAE4ZAA==.Brozeit:BAABNQAECn8ZAAQEAAoK2hQtIwDIAQAEAAoK2hQtIwDIAQACAAEKuw2wqQEyAAADAAIK8gV98wAvAAABNQAECgoKNgAPAE4ZAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Caboom:BAAANQAECgUIAwAAAA==.Calculusx:BAABNQAECn8gAAIUAAkKOiCeBwBtAgAUAAkKOiCeBwBtAgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8iAAQZAAkK6xnzAgD3AAAaAAgKHBuoDQAKAgAZAAMKyRTzAgD3AAAbAAEKAACuAQAAAAA1AAQKf0AABBsACgp+JTkAAFEDABsACgruJDkAAFEDABoACgrUIxESAP0CABkAAQosJXo9AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAFFAUIDwAEAH8XAA==.',
Cl='Clare:BAACNQAFFH8KAAIEAAUK5xCwBgC8AAAEAAUK5xCwBgC8AAA1AAQKfycAAgQACgrqHxENAMoCAAQACgrqHxENAMoCAAAA.Cloúd:BAAANQAECgUIEgAAAA==.',
Co='Colmacka:BAAANQAECgUIBwAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIcAAgKvhpPHgBAAgAcAAgKvhpPHgBAAgAAAA==.Darilol:BAAANQADCgYICAABNQAECggIGQANAF4OAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn89AAIRAAkKxyPODQBCAwARAAkKxyPODQBCAwAAAA==.Demiize:BAABNQAECn8/AAIZAAoKxR0EBAD2AgAZAAoKxR0EBAD2AgAAAA==.Demize:BAABNQAECn9BAAIBAAoKKBtDJwD7AgABAAoKKBtDJwD7AgAAAA==.Demonflame:BAAANQAECgUICQAAAA==.Demonhazard:BAAANQADCgIIAgAAAA==.Demíze:BAAANQAECgQIDAAAAA==.Deshield:BAACNQAFFH8HAAMdAAMKHReZFQDrAAAdAAMKxxWZFQDrAAAeAAEK+yP8BQBlAAA1AAQKfzoAAx4ACgpWJMADAFsDAB4ACAo/JsADAFsDAB0ACgrwIoIYAFYDAAAA.Deus:BAABNQAECn8YAAIaAAgKmAwT1gDbAQAaAAgKmAwT1gDbAQAAAA==.Dewry:BAABNQAECn8XAAIMAAgKIx6UFwCaAgAMAAgKIx6UFwCaAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn8+AAMfAAoKTCTmAQCZAwAfAAoKTCTmAQCZAwAcAAIK5xleXgBnAAAAAA==.',
Di='Diemertz:BAAANQAECgUICwAAAA==.Dingis:BAAANQAECgMIAwABNQAECggIGQANAF4OAA==.Divine:BAABNQAECn8aAAQMAAkKSBSKKADkAQAMAAkKSBSKKADkAQAgAAUKchPilwD8AAANAAIK3g1IHgBuAAABNQAECgoKNAAhAOUSAA==.Dizzo:BAABNQAECn8nAAIWAAgKFhpcPwAhAgAWAAgKFhpcPwAhAgAAAA==.',
Do='Doink:BAABNQAECn8lAAIPAAoKIBiqMgA1AgAPAAoKIBiqMgA1AgABNQAFFAQICgASANMVAA==.Donnajuan:BAABNQAECn8pAAIDAAkKzBy0QQBeAgADAAkKzBy0QQBeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQAECgEIAgAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGQAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAcIGwAKADciAA==.',
El='Elimere:BAABNQAECn82AAIMAAoKhwxPKgDVAQAMAAoKhwxPKgDVAQAAAA==.Elinalise:BAAANQAECgQIBAABNQAECgoKJwABAJEZAA==.Elvarg:BAABNQAECn84AAIKAAoKnhuXCgDCAgAKAAoKnhuXCgDCAgAAAA==.Elywen:BAACNQAFFH8MAAIBAAQKfxJxEwDlAAABAAQKfxJxEwDlAAA1AAQKfzwAAgEACgoEIZsdACEDAAEACgoEIZsdACEDAAAA.',
En='Enry:BAAANQAECgEIAQAAAA==.',
Eq='Eqlipse:BAAANQAECgEIAQAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgYIEQAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECgoKKgAiAH4eAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAgIFAAEAGAaAA==.Finke:BAAANQAECgUIDwAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAgIGQAEAHQaAA==.Firesham:BAAANQAECgcIBwABNQAFFAcIDAAjAE4ZAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAABNQAECn8dAAIcAAgK0ASPRgDpAAAcAAgK0ASPRgDpAAAAAA==.',
Fr='Free:BAABNQAECn8VAAMLAAYKYh3BHAD/AQALAAYKYh3BHAD/AQAKAAEKAACoQwAgAAABNQAECggIIwAhAMkYAA==.Frisbee:BAAANQAECgIIAgAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8zAAIaAAoKfw/xowA5AgAaAAoKfw/xowA5AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn82AAIUAAoK8SIZBADpAgAUAAoK8SIZBADpAgAAAA==.',
Gi='Gigazapper:BAABNQAECn8mAAMJAAkKLBLLggCeAQAJAAgKKw/LggCeAQAIAAYKKxS8ZABxAQABNQAFFAUIDwAEAH8XAA==.Gil:BAAANQAECgUIBgAAAA==.Gizzlit:BAABNQAECn8nAAIkAAoKRRETEwA4AgAkAAoKRRETEwA4AgAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBwABNQAFFAcIDwAiABQgAA==.Gofetch:BAABNQAECn83AAIBAAoKHhlfPQCyAgABAAoKHhlfPQCyAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn8/AAIBAAoKfhyJNwDEAgABAAoKfhyJNwDEAgAAAA==.',
Gs='Gson:BAABNQAECn8UAAIdAAkK8gTu8wD3AAAdAAkK8gTu8wD3AAAAAA==.',
Gu='Guppy:BAAANQAECgEIAgAAAA==.',
Ha='Hac:BAAANQAECgUICAABNQAECgoKIAAUAP4VAA==.Hakka:BAABNQAECn8gAAMUAAoK/hWUPQDZAQAUAAkKqAuUPQDZAQAVAAkKyxaQIQDAAQAAAA==.Hal:BAAANQAECgEIAQABNQAECgoKHwAFAEcKAA==.Hallack:BAABNQAECn8fAAIFAAoKRwr8VQCAAQAFAAoKRwr8VQCAAQAAAA==.Harlemshakez:BAAANQABCgUIBgAAAA==.',
He='Healingkiss:BAAANQAECgIIBQAAAA==.',
Hi='Hikingboots:BAABNQAECn8yAAIJAAoK/ApaUQB+AQAJAAoK/ApaUQB+AQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn85AAMaAAoKEBwbWwD0AQAaAAoKEBwbWwD0AQAZAAIKHgxkNwBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQIDgABNQAECgcIBgAGAAAAAA==.',
Il='Illani:BAAANQAECgEIBgAAAA==.Ilyanna:BAABNQAECn8yAAMQAAoKCxvtBwCDAgAQAAgKCBvtBwCDAgAPAAgKWxSsnwCXAQAAAA==.',
Im='Im:BAACNQAFFH8ZAAMlAAcKeiHzAwBCAgAlAAYKXiDzAwBCAgABAAEK6SU+LQBtAAA1AAQKf0AAAyUACgriJXQEAI4DACUACgriJXQEAI4DAAEAAQr0JRxAAWIAAAAA.Immagical:BAAANQAECgQIBwAAAA==.Imscary:BAAANQAECgYIDwAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAABNQAECn8YAAIZAAcKuhfyEQCGAQAZAAcKuhfyEQCGAQAAAA==.',
Je='Jenyaa:BAAANQAECgYIBgAAAA==.',
Jh='Jhops:BAABNQAECn9DAAMJAAoKaxyMJQA+AgAJAAoKaxyMJQA+AgAIAAEKMhNb9wAtAAAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.Kaz:BAAANQAECggIDAAAAA==.',
Ke='Keju:BAAANQAECgEIAQAAAA==.Kerrigan:BAABNQAECn8yAAMjAAoKRBsPJAAnAgAjAAoKRBsPJAAnAgAiAAUKGxAGWQAjAQABNQAECgoKJwABAJEZAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwAaAL4iAA==.Kookluhh:BAAANQAECgUICAABNQAECgkJIwAaAL4iAA==.Kozand:BAAANQADCgYIDQABNQAECggIGQANAF4OAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgUICwAAAA==.',
Ky='Kyirr:BAABNQAECn8TAAIKAAgKoRliEABRAgAKAAgKoRliEABRAgAAAA==.Kyralen:BAAANQAECgEIAQABNQAECgkJMAAKAO4VAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAABNQAECn8UAAIkAAgKWhUuFQAVAgAkAAgKWhUuFQAVAgAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAgIFAAEAGAaAA==.',
Ll='Llynryn:BAABNQAECn8cAAIMAAkK6QzsJABGAQAMAAkK6QzsJABGAQAAAA==.',
Lo='Locktuah:BAAANQAECgQICAABNQAECggIGQANAF4OAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8xAAIaAAoKfCGyIwBPAwAaAAoKfCGyIwBPAwABNQAFFAgIGwAjAMUfAA==.Magicmanzz:BAABNQAECn8gAAIZAAcKpA1DFABlAQAZAAcKpA1DFABlAQAAAA==.Magnifuso:BAABNQAECn8bAAIEAAgKvAU4LQD5AAAEAAgKvAU4LQD5AAAAAA==.Maguapa:BAAANQAECgYIDgAAAA==.Malgata:BAABNQAECn8iAAIXAAYKMhLGKwA5AQAXAAYKMhLGKwA5AQAAAA==.Mangrove:BAAANQABCggIFAAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8pAAICAAoKARmNZABtAgACAAoKARmNZABtAgAAAA==.Mastab:BAABNQAECn83AAMDAAoK6xc+MgCcAgADAAoK6xc+MgCcAgACAAMKlwwqMwGMAAAAAA==.',
Mc='Mchammerdin:BAABNQAECn81AAQEAAoKdxwUEgDzAQACAAgKvxaghwAYAgAEAAcKOB0UEgDzAQADAAYKxBCYcwBGAQAAAA==.',
Me='Meat:BAABNQAECn83AAMHAAoKdRwIBQBpAgAHAAkKdRwIBQBpAgAiAAEKAADZkwAzAAAAAA==.Merçenaries:BAAANQADCggICAAAAA==.',
Mi='Mikio:BAABNQAECn8oAAIFAAgKswrLQwACAQAFAAgKswrLQwACAQAAAA==.Milinka:BAABNQAECn8zAAIgAAoKqx5pIwDgAgAgAAoKqx5pIwDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAjAAwjAA==.',
Mo='Moiryn:BAAANQADCgMIAgAAAA==.',
My='Myshaman:BAABNQAECn8mAAMIAAkKoBoSMwA8AgAIAAkKoBoSMwA8AgAJAAEKQAlzOgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8bAAMKAAcKNyI7AQBXAQAKAAYKzyE7AQBXAQALAAEKYhfHFABVAAA1AAQKf7MAAwoACgqhJk8AAPcDAAoACgqhJk8AAPcDAAsACgosItIHACkDAAAA.',
No='Nota:BAAANQAECggICgAAAA==.Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgoKLQAEAMgjAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAFFAMIBwAdAB0XAA==.',
Om='Omnislásh:BAAANQAECgEIAQAAAA==.',
Op='Ophindis:BAABNQAECn8nAAMRAAkK8x79HwCzAgARAAkK8x79HwCzAgAWAAEKcQp24QAyAAAAAA==.',
Os='Osten:BAAANQAECgUIEAAAAA==.',
Pa='Pagoda:BAABNQAECn80AAMhAAoK5RLdFAAtAgAhAAoK5RLdFAAtAgAcAAcKJhL2KgApAQAAAA==.Panerai:BAAANQAECgEIAQAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIBAAYKyyEpfwAOAgABAAYKyyEpfwAOAgAAAA==.',
Pi='Pintsize:BAAANQABCggICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Po='Pond:BAAANQADCgYIBgAAAA==.Porkit:BAAANQAECgEIAgAAAA==.',
Pr='Praystation:BAAANQAECggIDAAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8jAAIdAAkK1BaYPwDMAgAdAAkK1BaYPwDMAgAAAA==.',
Ra='Rave:BAAANQAECgEIAQAAAA==.Razorclaw:BAAANQADCgEIAQABNQAECgUICwAGAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn9XAAMCAAoK3R3HJwC3AgACAAoK3R3HJwC3AgAEAAYKLAneOwATAQAAAA==.Rennx:BAACNQAFFH8iAAIFAAkKPR3LAwB/AgAFAAkKPR3LAwB/AgA1AAQKfzgAAgUACgrAJkMAAJkDAAUACgrAJkMAAJkDAAAA.Reznik:BAABNQAECn9BAAIRAAoKCRugHAAKAgARAAoKCRugHAAKAgAAAA==.',
Ri='Rika:BAAANQAECgMIBQAAAA==.Ringmasta:BAAANQAECgUIEgAAAA==.Riot:BAABNQAECn9BAAIBAAoKoxyZOADAAgABAAoKoxyZOADAAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8uAAMVAAgKhBj3GQAJAgAVAAgKhBj3GQAJAgAUAAEKbxV5ngA+AAAAAA==.',
['Rè']='Rènza:BAABNQAECn8kAAIiAAoKZxe5GwAdAgAiAAoKZxe5GwAdAgAAAA==.',
Sa='Sacred:BAAANQAECgEIAQAAAA==.Saintlorric:BAAANQAECgEIAgAAAA==.Sanguineous:BAAANQAECgIIBgABNQAECgoKRAACAL4iAA==.Saphia:BAECNQAFFH8UAAIEAAgKYBo/AgAYAgAEAAgKYBo/AgAYAgA1AAQKfzoAAwQACgqPJWMBAMsDAAQACgqPJWMBAMsDAAIABAqFFW0KAcQAAAAA.Saphyr:BAECNQAFFH8IAAIRAAYKyBU0BwDzAQARAAYKyBU0BwDzAQA1AAQKfyUABBEACgrCIY8SABgDABEACgrCIY8SABgDAA4ABQr8D+p4AK8AABYAAwquCgy2AIIAAAE1AAUUCAgUAAQAYBoA.',
Sb='Sblakedragon:BAAANQAECgYICgAAAA==.',
Sc='Scarydude:BAABNQAECn8sAAIjAAoKVRi6FAAJAgAjAAoKVRi6FAAJAgAAAA==.',
Se='Senniel:BAAANQAECgQICQAAAA==.Sevrin:BAABNQAECn8uAAMcAAoK4BxLEgDKAgAcAAoK4BxLEgDKAgAfAAEKAADLMAA3AAAAAA==.',
Sh='Shadda:BAAANQAECgEIAQAAAA==.Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAABNQAECn8XAAIJAAcKshOAXwBQAQAJAAcKshOAXwBQAQAAAA==.Sheesh:BAACNQAFFH8KAAISAAQK0xV4CAA1AQASAAQK0xV4CAA1AQA1AAQKf00AAxIACgqUJYAGAGoDABIACgqUJYAGAGoDAAUABgoeGHNRAMYAAAAA.Shinru:BAABNQAECn9IAAMDAAoK/CLzDABhAwADAAoK/CLzDABhAwACAAMKkxYZOAHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAFFAUICgAEAOcQAA==.',
Si='Sickdayze:BAABNQAECn8jAAIDAAkKtB5aKADHAgADAAkKtB5aKADHAgAAAA==.Sickhymns:BAAANQAECgMIBAABNQAECgkJIwADALQeAA==.Sickntired:BAAANQAECgEIAQABNQAECgkJIwADALQeAA==.Sicktides:BAAANQADCgYICAABNQAECgkJIwADALQeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIIAAcKLRVCfQCUAQAIAAcKLRVCfQCUAQAAAA==.',
Sn='Snaffu:BAABNQAECn8WAAIPAAkKCRK/gwBCAQAPAAkKCRK/gwBCAQAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAACNQAFFH8HAAISAAYKQSFVAwAQAgASAAYKQSFVAwAQAgA1AAQKfzUAAxIACgoSJUcDAJQDABIACgoSJUcDAJQDAAUAAQoAAKOmAEsAAAAA.Sophie:BAACNQAFFH8PAAICAAUKsSTcBwDPAQACAAUKsSTcBwDPAQA1AAQKf0AAAgIACgpnJowHAL4DAAIACgpnJowHAL4DAAE1AAUUBggHABIAQSEA.Sophisticate:BAABNQAECn81AAImAAoKryCEAQBUAwAmAAoKryCEAQBUAwABNQAFFAYIBwASAEEhAA==.Sophiz:BAABNQAECn8yAAIjAAoK1R0cDwD8AgAjAAoK1R0cDwD8AgABNQAFFAYIBwASAEEhAA==.Sophlax:BAABNQAECn8wAAIgAAoKsCIUCgByAwAgAAoKsCIUCgByAwABNQAFFAYIBwASAEEhAA==.Sophs:BAABNQAECn8nAAMIAAgKmBqHfwCNAQAIAAgKmBqHfwCNAQAJAAYKphcIegAJAQABNQAFFAYIBwASAEEhAA==.Sophz:BAABNQAECn8rAAIWAAkKZyE3GQD2AgAWAAkKZyE3GQD2AgABNQAFFAYIBwASAEEhAA==.Sox:BAABNQAECn87AAMXAAoKaCVxAQDQAwAXAAoKaCVxAQDQAwAYAAEKchNlQQA7AAAAAA==.',
Sp='Spankgg:BAAANQAECgEIAgAAAA==.Spicynoodle:BAABNQAECn8tAAIBAAoKOhwdPAC2AgABAAoKOhwdPAC2AgAAAA==.Spookyougi:BAAANQAECgUIDgAAAA==.',
Sq='Squattinchop:BAABNQAECn8sAAIcAAoK/x4DDQB9AgAcAAoK/x4DDQB9AgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8xAAIaAAkK7xfCSQAiAgAaAAkK7xfCSQAiAgAAAA==.',
Su='Sua:BAACNQAFFH8dAAIdAAkKKBCKCAAuAgAdAAkKKBCKCAAuAgA1AAQKfzQAAh0ACgpVJb8KADYDAB0ACgpVJb8KADYDAAAA.Succulent:BAAANQAECgEIAQAAAA==.Suksuksuk:BAAANQAECgEIBAAAAA==.Supergogeta:BAABNQAECn80AAMSAAoKJBYRJQCtAQASAAoKJBYRJQCtAQAFAAUKKg9mawAdAQAAAA==.',
Sy='Sylvie:BAABNQAECn8WAAIgAAgKmAmbhgCDAQAgAAgKmAmbhgCDAQAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn8/AAIdAAoKGh/ZQgAqAgAdAAoKGh/ZQgAqAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBgAAAA==.Talauyia:BAAANQAECgQICQAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgUIDwABNQAECgcIBgAGAAAAAA==.Thrayne:BAAANQAECgEIAQAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgkJJwARAPMeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAINAAgK9BbpBQA7AgANAAgK9BbpBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQIDAAAAA==.',
Ty='Tyranis:BAABNQAECn8gAAIHAAoKEhyMBAD8AgAHAAoKEhyMBAD8AgAAAA==.Tyê:BAABNQAECn8sAAMLAAoKHBQ/GgAgAgALAAoKHBQ/GgAgAgAKAAEKAAC6PQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8IAAIaAAQKshl4KABFAQAaAAQKshl4KABFAQA1AAQKfyMAAhoACgq2H8MxACcDABoACgq2H8MxACcDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQAECgQIBAAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Ve='Vee:BAAANQAECgMIAwAAAA==.',
Vi='Visable:BAAANQAECgUICAAAAA==.',
Vo='Voiddemon:BAAANQAECgQIBwAAAA==.Voltage:BAAANQAECgQIDgABNQAECgYIGQABAMshAA==.',
Vu='Vulgnash:BAACNQAFFH8HAAIWAAMK1BwSBQAMAQAWAAMK1BwSBQAMAQA1AAQKf1UAAhYACgqkJPkCAE4DABYACgqkJPkCAE4DAAAA.Vult:BAABNQAECn8rAAIOAAoKRho+HgCZAgAOAAoKRho+HgCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Weiyoung:BAAANQAECgEIAQAAAA==.Welgo:BAABNQAECn8pAAIeAAoKXiHiAwBWAwAeAAoKXiHiAwBWAwAAAA==.Welmage:BAAANQAECgIIAwABNQAECgoKKQAeAF4hAA==.',
Wi='Wickeddemon:BAAANQAECgUIDQAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8uAAIaAAoKOBzdTQDlAgAaAAoKOBzdTQDlAgAAAA==.',
Xe='Xerra:BAACNQAFFH8FAAIjAAIKdhEkDACLAAAjAAIKdhEkDACLAAA1AAQKfz0AAiMACgr4H+AKAC8DACMACgr4H+AKAC8DAAAA.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAABNQAECn8ZAAISAAcK9x6bFgBNAgASAAcK9x6bFgBNAgAAAA==.Yemoja:BAAANQAECgUIDwAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAFFAQICgASANMVAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAABNQAECn8ZAAMNAAgKXg7SBwA1AQANAAgKXg7SBwA1AQAMAAIKaQgGaQBdAAAAAA==.',
Ze='Zeit:BAABNQAECn8kAAQHAAgKew8EDwA/AQAHAAgKEg8EDwA/AQAjAAMKjBBWVgC1AAAiAAQKZwl0YwCCAAABNQAECgoKNgAPAE4ZAA==.Zelgie:BAABNQAECn82AAIDAAoKTBohHwCzAgADAAoKTBohHwCzAgAAAA==.',
Zi='Zienna:BAAANQADCgcICQAAAA==.Zin:BAAANQAECgEIAgAAAA==.',
Zu='Zuleika:BAAANQAECgEIAQAAAA==.',
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
