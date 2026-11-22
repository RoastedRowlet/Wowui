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
local provider = {region='US',realm='Maiev',name='US',type='weekly',zone=53,date='2026-11-17',data={Aa='Aayron:BAAANQADCgIIAgAAAA==.',
Ab='Abadizzo:BAAANQAECggIBQAAAA==.Abadizzoo:BAABNQAECn8UAAIBAAgKmR21VwBsAgABAAgKmR21VwBsAgAAAA==.Abeyancë:BAABNQAECn86AAQCAAoKOBlbXQCAAgACAAoKGRlbXQCAAgADAAIK8RJpBAFwAAAEAAEKaBYFYAA9AAAAAA==.Abilities:BAAANQABCgYIDAAAAA==.',
Ae='Aeshanth:BAAANQADCgUIBgAAAA==.',
Ai='Airie:BAAANQABCgIIAgAAAA==.Airwrecka:BAABNQAECn89AAIFAAoK2RvsGwDpAgAFAAoK2RvsGwDpAgAAAA==.Aite:BAAANQAECgYICQAAAA==.',
Al='Altlas:BAAANQADCggIEAAAAA==.',
Am='Amadk:BAAANQAECgIIAQABNQAECggIEgAGAAAAAA==.Amaterasu:BAAANQADCgYIBgABNQAECgEIAQAGAAAAAA==.Amathal:BAAANQAECgQICgABNQAECggIEgAGAAAAAA==.',
An='Anise:BAAANQADCgEIAQAAAA==.',
Ar='Arahgon:BAABNQAECn83AAMCAAoKZBd7WgAgAgACAAoKZBd7WgAgAgADAAEKpgGtDwEXAAABNQAECgoKIAAHABIcAA==.Artvandelay:BAAANQAECgQIBgABNQAECgoKPwABAH4cAA==.',
As='Asukà:BAABNQAECn8tAAMIAAoKyRg1QQBcAgAIAAoKyRg1QQBcAgAJAAIK3wGSFAEZAAAAAA==.',
Au='Auchenile:BAABNQAECn8wAAMKAAkK7hWNEABOAgAKAAkK7hWNEABOAgALAAYKVQqnLQCRAAAAAA==.Austin:BAAANQAECgIIAQAAAA==.Austinthedog:BAAANQAECggICQAAAA==.',
Av='Avanoura:BAAANQADCggIDQABNQAECgkJHAAMAOkMAA==.',
['Aé']='Aéd:BAAANQAECgIIAgABNQAECggIGQANAF4OAA==.',
Ba='Barkthas:BAABNQAECn8aAAIOAAkK4w6VRQCqAQAOAAkK4w6VRQCqAQAAAA==.',
Be='Bellarg:BAABNQAECn8/AAMPAAoKzBcONwA1AgAPAAoKzBcONwA1AgAQAAEKzQeXfQAvAAAAAA==.Belobog:BAAANQAECgYIBwABNQAECgcIFwAJALITAA==.Belyn:BAABNQAECn8YAAIDAAYK9ReLeQBJAQADAAYK9ReLeQBJAQAAAA==.',
Bi='Bifesor:BAAANQADCgMIAwAAAA==.Bizmania:BAAANQADCgQIBAAAAA==.',
Bl='Blackhøof:BAAANQADCgYIEgAAAA==.Bloodadinz:BAAANQAECgYIDgAAAA==.',
Bo='Bonedaddy:BAABNQAECn8pAAMRAAkKeRaGNwBmAQAOAAkK2xTuOwCuAQARAAcKzRKGNwBmAQAAAA==.Bootsboots:BAAANQAECgYIDAAAAA==.',
Br='Bratlax:BAAANQAECgQIBAABNQAFFAYIBwASAEEhAA==.Brbwifeaggro:BAAANQABCgIIBAAAAA==.Bro:BAABNQAECn88AAQPAAoKABpORAAIAgAPAAoKlRdORAAIAgAQAAQKUBUkHgB3AAATAAIKiwrKKQBFAAAAAA==.Brogue:BAABNQAECn83AAMUAAoKDherDAABAgAVAAoKqBTTMwAsAgAUAAkK6xGrDAABAgAAAA==.Brolich:BAABNQAECn9CAAQRAAoK9BaUPgAGAgARAAoK9BaUPgAGAgAOAAMK6w2KkgB6AAAWAAEKlQrZ4QAyAAABNQAECgoKPAAPAAAaAA==.Broo:BAABNQAECn8eAAUXAAkKpBiVLAApAQAXAAcKxxiVLAApAQASAAQKkwoAWgCQAAAFAAQKWwxfcQBtAAAYAAEKxwKNVwAVAAABNQAECgoKPAAPAAAaAA==.Brooak:BAABNQAECn8gAAMIAAgK6Av/pgAkAQAIAAcK4Qr/pgAkAQAJAAcK6Q2shAAGAQABNQAECgoKPAAPAAAaAA==.Brother:BAAANQAECgUIBgABNQAECgoKPAAPAAAaAA==.Brozeit:BAABNQAECn8cAAQEAAoKgRUtIwDIAQAEAAoK2hQtIwDIAQACAAMKSxHkVAF2AAADAAIK8gVF/gAtAAABNQAECgoKPAAPAAAaAA==.',
Bu='Bubblegump:BAAANQAECgUIBQAAAA==.',
Ca='Caboom:BAAANQAECgUIAwAAAA==.Calculusx:BAABNQAECn8gAAIUAAkKOiBbCABnAgAUAAkKOiBbCABnAgAAAA==.Camión:BAAANQADCggIDwAAAA==.',
Ce='Cellice:BAACNQAFFH8iAAQZAAkK6xnzAgD3AAAaAAgKHBuoDQAKAgAZAAMKyRTzAgD3AAAbAAEKAAAIAgAAAAA1AAQKf0AABBsACgp+JUkAAE0DABsACgruJEkAAE0DABoACgrUIwsVAPUCABkAAQosJXo9AEoAAAAA.',
Ch='Chad:BAAANQADCgQIBAAAAA==.Chuckborris:BAAANQADCgEIAQABNQAFFAUIDwAEAH8XAA==.',
Cl='Clare:BAACNQAFFH8KAAIEAAUK5xByBwC8AAAEAAUK5xByBwC8AAA1AAQKfycAAgQACgrqHxENAMoCAAQACgrqHxENAMoCAAAA.Cloúd:BAAANQAECgUIDwAAAA==.',
Co='Colmacka:BAAANQAECgUIBwAAAA==.',
Da='Daddydimes:BAABNQAECn8dAAIcAAgKvhpPHgBAAgAcAAgKvhpPHgBAAgAAAA==.Darilol:BAAANQADCgYICAABNQAECggIGQANAF4OAA==.',
De='Deathfu:BAAANQADCgQIBAAAAA==.Deathless:BAABNQAECn9DAAIRAAoKIiPODQBCAwARAAoKIiPODQBCAwAAAA==.Demiize:BAABNQAECn9CAAIZAAoKxR0EBAD2AgAZAAoKxR0EBAD2AgAAAA==.Demize:BAABNQAECn9BAAIBAAoKKBtDJwD7AgABAAoKKBtDJwD7AgAAAA==.Demonflame:BAAANQAECgUICAAAAA==.Demonhazard:BAAANQADCgIIAgAAAA==.Demíze:BAAANQAECgQICgAAAA==.Deshield:BAACNQAFFH8HAAMdAAMKHRfNGADoAAAdAAMKxxXNGADoAAAeAAEK+yOIBgBkAAA1AAQKfzoAAx4ACgpWJMADAFsDAB4ACAo/JsADAFsDAB0ACgrwIoIYAFYDAAAA.Deus:BAABNQAECn8YAAIaAAgKmAwT1gDbAQAaAAgKmAwT1gDbAQAAAA==.Dewry:BAABNQAECn8XAAIMAAgKIx6UFwCaAgAMAAgKIx6UFwCaAgAAAA==.',
Dh='Dhudamuthi:BAABNQAECn8+AAMfAAoKTCTmAQCZAwAfAAoKTCTmAQCZAwAcAAIK5xleXgBnAAAAAA==.',
Di='Diemertz:BAAANQAECgYIDQAAAA==.Dingis:BAAANQAECgMIAwABNQAECggIGQANAF4OAA==.Divine:BAABNQAECn8aAAQMAAkKSBSKKADkAQAMAAkKSBSKKADkAQAgAAUKchPtoQD3AAANAAIK3g1IHgBuAAABNQAECgoKNAAhAOUSAA==.Dizzo:BAABNQAECn8nAAIWAAgKFhpcPwAhAgAWAAgKFhpcPwAhAgAAAA==.',
Do='Doink:BAABNQAECn8lAAIPAAoKIBh2OAAwAgAPAAoKIBh2OAAwAgABNQAFFAQICgASANMVAA==.Donnajuan:BAABNQAECn8qAAIDAAoKwBy0QQBeAgADAAoKwBy0QQBeAgAAAA==.Dornath:BAAANQAECgQIBAAAAA==.',
Dr='Draaxelro:BAAANQADCgUIDAAAAA==.Dragontiddys:BAAANQADCgIIAgAAAA==.Drakaris:BAAANQADCggIGQAAAA==.',
Ed='Edgeillus:BAAANQADCgMIBAABNQAFFAcIGwAKADciAA==.',
El='Elimere:BAABNQAECn82AAIMAAoKhwxPKgDVAQAMAAoKhwxPKgDVAQAAAA==.Elinalise:BAAANQAECgQIBAABNQAECgoKJwABAJEZAA==.Elvarg:BAABNQAECn84AAIKAAoKnhuXCgDCAgAKAAoKnhuXCgDCAgAAAA==.Elywen:BAACNQAFFH8MAAIBAAQKfxLlFQDiAAABAAQKfxLlFQDiAAA1AAQKfzwAAgEACgoEIZsdACEDAAEACgoEIZsdACEDAAAA.',
Eq='Eqlipse:BAAANQADCgYIBgAAAA==.',
Es='Esira:BAAANQADCgIIAgAAAA==.',
Ev='Evién:BAAANQAECgYIEQAAAA==.',
Ex='Executè:BAAANQAECggIAgABNQAECgoKLQAiAMgfAA==.',
Fi='Fiammetta:BAEANQADCgcIBwABNQAFFAkJFwAEAHkcAA==.Finke:BAAANQAECgUIDgAAAA==.Firemge:BAEANQAECgUIBQABNQAFFAgIGQAEAHQaAA==.Firesham:BAAANQAECgcIBwABNQAFFAcIDAAjAE4ZAA==.Fistzz:BAAANQADCgIIAgAAAA==.',
Fl='Flickerbeat:BAABNQAECn8gAAIcAAkKWQWPRgDpAAAcAAkKWQWPRgDpAAAAAA==.',
Fr='Free:BAAANQAECgUIEAABNQAECgkJKwAhAPgYAA==.Frisbee:BAAANQAECgIIAgAAAA==.',
Fu='Futurama:BAAANQADCgQIBAAAAA==.',
Ga='Gabi:BAAANQABCgIIAgAAAA==.',
Gd='Gdizz:BAABNQAECn8zAAIaAAoKfw/xowA5AgAaAAoKfw/xowA5AgAAAA==.',
Gh='Ghostshadows:BAABNQAECn82AAIUAAoK8SJ5BADiAgAUAAoK8SJ5BADiAgAAAA==.',
Gi='Gigazapper:BAABNQAECn8mAAMJAAkKLBLLggCeAQAJAAgKKw/LggCeAQAIAAYKKxRjbQBsAQABNQAFFAUIDwAEAH8XAA==.Gil:BAAANQAECgUIBgAAAA==.Gizzlit:BAABNQAECn8nAAIkAAoKRRETEwA4AgAkAAoKRRETEwA4AgAAAA==.',
Go='Gobiasinds:BAAANQAECgMIBQABNQAFFAcIDwAiABQgAA==.Gofetch:BAABNQAECn83AAIBAAoKHhlfPQCyAgABAAoKHhlfPQCyAgAAAA==.Goodbye:BAAANQAECgYIBgAAAA==.',
Gr='Grandgoop:BAAANQAECgMIBQAAAA==.Grasputin:BAAANQADCgUIBQAAAA==.Grissum:BAABNQAECn8/AAIBAAoKfhyJNwDEAgABAAoKfhyJNwDEAgAAAA==.',
Gs='Gson:BAABNQAECn8UAAIdAAkK8gTu8wD3AAAdAAkK8gTu8wD3AAAAAA==.',
Gu='Guppy:BAAANQAECgEIAQAAAA==.',
Ha='Hac:BAAANQAECgUIBwABNQAECgoKIAAUAP4VAA==.Hakka:BAABNQAECn8gAAMUAAoK/hWUPQDZAQAUAAkKqAuUPQDZAQAVAAkKyxaQIQDAAQAAAA==.Hal:BAAANQADCgYICwABNQAECgoKHwAFAEcKAA==.Hallack:BAABNQAECn8fAAIFAAoKRwr8VQCAAQAFAAoKRwr8VQCAAQAAAA==.',
He='Healingkiss:BAAANQAECgIIBQAAAA==.',
Hi='Hikingboots:BAABNQAECn8yAAIJAAoK/AqkWAB9AQAJAAoK/AqkWAB9AQAAAA==.',
Ho='Hollypallz:BAAANQAECgIIAgAAAA==.Holymages:BAABNQAECn85AAMaAAoKEBxXYgDyAQAaAAoKEBxXYgDyAQAZAAIKHgxkNwBfAAAAAA==.',
Ik='Iknowaguy:BAAANQAECgQICgABNQAECgYIDAAGAAAAAA==.',
Il='Illani:BAAANQAECgEIAwAAAA==.Ilyanna:BAABNQAECn8yAAMQAAoKCxvtBwCDAgAQAAgKCBvtBwCDAgAPAAgKWxSsnwCXAQAAAA==.',
Im='Im:BAACNQAFFH8ZAAMlAAcKeiHzAwBCAgAlAAYKXiDzAwBCAgABAAEK6SU+LQBtAAA1AAQKf0AAAyUACgriJXQEAI4DACUACgriJXQEAI4DAAEAAQr0JRxAAWIAAAAA.Immagical:BAAANQAECgQIBAAAAA==.Imscary:BAAANQAECgcICwAAAA==.',
It='Itooktheflag:BAAANQADCgMIAwAAAA==.',
Iz='Izzo:BAAANQAECggICAAAAA==.',
Ja='Jausi:BAABNQAECn8ZAAIZAAcKuhfyEQCGAQAZAAcKuhfyEQCGAQAAAA==.',
Je='Jenyaa:BAAANQAECgYIDAAAAA==.',
Jh='Jhops:BAABNQAECn9DAAMJAAoKaxxhKQA7AgAJAAoKaxxhKQA7AgAIAAEKMhNWAQEsAAAAAA==.',
Ji='Jilliadk:BAAANQAECgEIAQAAAA==.Jirachi:BAAANQADCggIEwAAAA==.',
Ka='Katz:BAAANQADCgUIBQAAAA==.Kaz:BAAANQAECgcIDgAAAA==.',
Ke='Keju:BAAANQAECgEIAQAAAA==.Kerrigan:BAABNQAECn8yAAMjAAoKRBsPJAAnAgAjAAoKRBsPJAAnAgAiAAUKGxAGWQAjAQABNQAECgoKJwABAJEZAA==.',
Ko='Kookler:BAAANQADCgUIBQABNQAECgkJIwAaAL4iAA==.Kookluhh:BAAANQAECgUIBwABNQAECgkJIwAaAL4iAA==.Kozand:BAAANQADCgYIDQABNQAECggIGQANAF4OAA==.',
Ku='Kuji:BAAANQAECgQICAAAAA==.Kushmon:BAAANQADCgUIDAAAAA==.',
Ky='Kyirr:BAAANQAECggJEQAAAA==.Kyralen:BAAANQABCgQIBQABNQAECgkJMAAKAO4VAA==.',
La='Layke:BAAANQADCggIEwAAAA==.Lazerbeampew:BAABNQAECn8UAAIkAAgKWhUuFQAVAgAkAAgKWhUuFQAVAgAAAA==.',
Li='Lilli:BAEANQADCggICAABNQAFFAkJFwAEAHkcAA==.',
Ll='Llynryn:BAABNQAECn8cAAIMAAkK6QznJwBGAQAMAAkK6QznJwBGAQAAAA==.',
Lo='Locktuah:BAAANQAECgQIBwABNQAECggIGQANAF4OAA==.Loklak:BAAANQADCgcIBwABNQAECgEIAQAGAAAAAA==.',
Ly='Lycann:BAAANQABCgYIDQAAAA==.',
Ma='Magicae:BAABNQAECn8xAAIaAAoKfCGyIwBPAwAaAAoKfCGyIwBPAwABNQAFFAgIHQAjACceAA==.Magicmanzz:BAABNQAECn8hAAIZAAcKpA1DFABlAQAZAAcKpA1DFABlAQAAAA==.Magnifuso:BAABNQAECn8iAAIEAAoKFgYSKgAkAQAEAAoKFgYSKgAkAQAAAA==.Maguapa:BAAANQAECgYIDQAAAA==.Malgata:BAABNQAECn8iAAIXAAYKMhLGKwA5AQAXAAYKMhLGKwA5AQAAAA==.Mangrove:BAAANQABCggIFgAAAA==.Margarita:BAAANQADCgQIBAAAAA==.Masstech:BAABNQAECn8pAAICAAoKARmNZABtAgACAAoKARmNZABtAgAAAA==.Mastab:BAABNQAECn83AAMDAAoK6xc+MgCcAgADAAoK6xc+MgCcAgACAAMKlwwhQwGLAAAAAA==.',
Mc='Mchammerdin:BAABNQAECn81AAQEAAoKdxzcEwDvAQACAAgKvxaghwAYAgAEAAcKOB3cEwDvAQADAAYKxBBRfABAAQAAAA==.',
Me='Meat:BAABNQAECn87AAMHAAoKRx7YBACGAgAHAAkKRx7YBACGAgAiAAEKAADZkwAzAAAAAA==.Merçenaries:BAAANQADCggICAAAAA==.',
Mi='Mikio:BAABNQAECn8oAAIFAAgKswpQSAABAQAFAAgKswpQSAABAQAAAA==.Milinka:BAABNQAECn8zAAIgAAoKqx5pIwDgAgAgAAoKqx5pIwDgAgAAAA==.Mirror:BAAANQAECgYIBwABNQAECgkJMAAjAAwjAA==.',
Mo='Moiryn:BAAANQADCgMIAgAAAA==.',
My='Myshaman:BAABNQAECn8mAAMIAAkKoBqjOAA2AgAIAAkKoBqjOAA2AgAJAAEKQAlzOgExAAAAAA==.',
Na='Navillus:BAACNQAFFH8bAAMKAAcKNyIOAgANAgAKAAYKzyEOAgANAgALAAEKYheYFgBSAAA1AAQKf7MAAwoACgqhJk8AAPcDAAoACgqhJk8AAPcDAAsACgosItIHACkDAAAA.',
No='Nota:BAAANQAECggICgAAAA==.Noxi:BAAANQAECgYIDQAAAA==.',
Oa='Oakensoul:BAAANQAECgEIAQABNQAECgoKLQAEAMgjAA==.',
Og='Ogron:BAAANQADCgYIBgABNQAFFAMIBwAdAB0XAA==.',
Op='Ophindis:BAABNQAECn8nAAMRAAkK8x79HwCzAgARAAkK8x79HwCzAgAWAAEKcQp24QAyAAAAAA==.',
Os='Osten:BAAANQAECgUIDQAAAA==.',
Pa='Pagoda:BAABNQAECn80AAMhAAoK5RLdFAAtAgAhAAoK5RLdFAAtAgAcAAcKJhL+LQApAQAAAA==.Panerai:BAAANQADCgYIBgAAAA==.',
Pe='Pewpop:BAABNQAECn8ZAAIBAAYKyyEpfwAOAgABAAYKyyEpfwAOAgAAAA==.',
Pi='Pintsize:BAAANQABCggICQAAAA==.',
Pj='Pjt:BAAANQADCgEIAQAAAA==.',
Po='Pond:BAAANQADCgYIBgAAAA==.Porkit:BAAANQAECgEIAQAAAA==.',
Pr='Praystation:BAAANQAECggICwAAAA==.',
Pu='Putemuptoo:BAAANQAECgEIAQAAAA==.',
Py='Pyosi:BAAANQADCggICAAAAA==.',
Qp='Qpti:BAABNQAECn8jAAIdAAkK1BaYPwDMAgAdAAkK1BaYPwDMAgAAAA==.',
Ra='Razorclaw:BAAANQADCgEIAQABNQAECgUICwAGAAAAAA==.Razz:BAAANQABCgcIBgAAAA==.',
Re='Rejectlol:BAABNQAECn9YAAMCAAoK3R2ELQCrAgACAAoK3R2ELQCrAgAEAAYKLAneOwATAQAAAA==.Rennx:BAACNQAFFH8iAAIFAAkKPR3LAwB/AgAFAAkKPR3LAwB/AgA1AAQKfzgAAgUACgrAJlUAAJcDAAUACgrAJlUAAJcDAAAA.Reznik:BAABNQAECn9BAAIRAAoKCRtjHwABAgARAAoKCRtjHwABAgAAAA==.',
Ri='Rika:BAAANQAECgMIBAAAAA==.Ringmasta:BAABNQAECn8UAAIVAAUKiQpxmQDZAAAVAAUKiQpxmQDZAAAAAA==.Riot:BAABNQAECn9BAAIBAAoKoxyZOADAAgABAAoKoxyZOADAAgAAAA==.',
Ro='Rosé:BAAANQAFFAEIAQAAAA==.Rowen:BAABNQAECn8vAAMVAAgK3hj3GQAJAgAVAAgK3hj3GQAJAgAUAAEKbxV5ngA+AAAAAA==.',
['Rè']='Rènza:BAABNQAECn8kAAIiAAoKZxcUHgAcAgAiAAoKZxcUHgAcAgAAAA==.',
Sa='Saintlorric:BAAANQABCgQIBAAAAA==.Sanguineous:BAAANQAECgIIBAABNQAECgoKTAACANkiAA==.Saphia:BAECNQAFFH8XAAIEAAkKeRw/AgAYAgAEAAkKeRw/AgAYAgA1AAQKfzoAAwQACgqPJWMBAMsDAAQACgqPJWMBAMsDAAIABAqFFegaAcEAAAAA.Saphyr:BAECNQAFFH8JAAIRAAcKqhY0BwDzAQARAAcKqhY0BwDzAQA1AAQKfyYABBEACgrCIY8SABgDABEACgrCIY8SABgDAA4ABQr8D3mAAK4AABYAAwquCgy2AIIAAAE1AAUUCQkXAAQAeRwA.',
Sb='Sblakedragon:BAAANQAECgYICgAAAA==.',
Sc='Scarydude:BAABNQAECn8sAAIjAAoKVRjpFgAAAgAjAAoKVRjpFgAAAgAAAA==.',
Se='Senniel:BAAANQAECgQICAAAAA==.Sevrin:BAABNQAECn8uAAMcAAoK4BxLEgDKAgAcAAoK4BxLEgDKAgAfAAEKAADLMAA3AAAAAA==.',
Sh='Shamoon:BAAANQAECgQIBQAAAA==.Shamwow:BAABNQAECn8XAAIJAAcKshM9aABOAQAJAAcKshM9aABOAQAAAA==.Sheesh:BAACNQAFFH8KAAISAAQK0xWPCQAxAQASAAQK0xWPCQAxAQA1AAQKf00AAxIACgqUJXIHAGcDABIACgqUJXIHAGcDAAUABgoeGExWAMYAAAAA.Shinru:BAABNQAECn9IAAMDAAoK/CLzDABhAwADAAoK/CLzDABhAwACAAMKkxYZOAHGAAAAAA==.Shrikedk:BAAANQADCgIIAgABNQAFFAUICgAEAOcQAA==.',
Si='Sickdayze:BAABNQAECn8jAAIDAAkKtB5aKADHAgADAAkKtB5aKADHAgAAAA==.Sickhymns:BAAANQAECgMIAwABNQAECgkJIwADALQeAA==.Sickntired:BAAANQADCgMJAwABNQAECgkJIwADALQeAA==.Sicktides:BAAANQADCgYICAABNQAECgkJIwADALQeAA==.',
Sk='Skinnymini:BAAANQADCgEIAQAAAA==.',
Sl='Slyxxar:BAABNQAECn8eAAIIAAcKLRVCfQCUAQAIAAcKLRVCfQCUAQAAAA==.',
Sn='Snaffu:BAABNQAECn8WAAIPAAkKCRIFjgBAAQAPAAkKCRIFjgBAAQAAAA==.Snoopyy:BAAANQADCgcIBwAAAA==.',
So='Soar:BAAANQAECgUICwAAAA==.Soph:BAACNQAFFH8HAAISAAYKQSEhBAAMAgASAAYKQSEhBAAMAgA1AAQKfzUAAxIACgoSJUcDAJQDABIACgoSJUcDAJQDAAUAAQoAAKOmAEsAAAAA.Sophie:BAACNQAFFH8PAAICAAUKsSTcBwDPAQACAAUKsSTcBwDPAQA1AAQKf0AAAgIACgpnJowHAL4DAAIACgpnJowHAL4DAAE1AAUUBggHABIAQSEA.Sophisticate:BAABNQAECn81AAImAAoKryCEAQBUAwAmAAoKryCEAQBUAwABNQAFFAYIBwASAEEhAA==.Sophiz:BAABNQAECn8yAAIjAAoK1R0cDwD8AgAjAAoK1R0cDwD8AgABNQAFFAYIBwASAEEhAA==.Sophlax:BAABNQAECn8wAAIgAAoKsCIUCgByAwAgAAoKsCIUCgByAwABNQAFFAYIBwASAEEhAA==.Sophs:BAABNQAECn8nAAMIAAgKmBqHfwCNAQAIAAgKmBqHfwCNAQAJAAYKphfsmwBgAQABNQAFFAYIBwASAEEhAA==.Sophz:BAABNQAECn8rAAIWAAkKZyE3GQD2AgAWAAkKZyE3GQD2AgABNQAFFAYIBwASAEEhAA==.Sox:BAABNQAECn87AAMXAAoKaCVxAQDQAwAXAAoKaCVxAQDQAwAYAAEKchP3RgA7AAAAAA==.',
Sp='Spicynoodle:BAABNQAECn8tAAIBAAoKOhwdPAC2AgABAAoKOhwdPAC2AgAAAA==.Spookyougi:BAAANQAECgUICwAAAA==.',
Sq='Squattinchop:BAABNQAECn8sAAIcAAoK/x4TDgB7AgAcAAoK/x4TDgB7AgAAAA==.',
St='Stabamon:BAAANQADCggICAAAAA==.Stiffcrit:BAABNQAECn8xAAIaAAkK7xdbUAAfAgAaAAkK7xdbUAAfAgAAAA==.',
Su='Sua:BAACNQAFFH8dAAIdAAkKKBCKCAAuAgAdAAkKKBCKCAAuAgA1AAQKfzQAAh0ACgpVJWcMAC8DAB0ACgpVJWcMAC8DAAAA.Suksuksuk:BAAANQABCgYICgAAAA==.Supergogeta:BAABNQAECn80AAMSAAoKJBbFJgDrAQASAAoKJBbFJgDrAQAFAAUKKg9mawAdAQAAAA==.',
Sy='Sylvie:BAAANQAECgcIEgAAAA==.Synistër:BAAANQADCgYIDgAAAA==.',
['Sï']='Sïnsu:BAABNQAECn8/AAIdAAoKGh/TSQAiAgAdAAoKGh/TSQAiAgAAAA==.',
Ta='Takoda:BAAANQAECgQIBQAAAA==.Talauyia:BAAANQAECgQICQAAAA==.Tankyou:BAAANQADCgYIBgAAAA==.',
Te='Temporë:BAAANQAECgQIBQAAAA==.',
Th='Thicness:BAAANQADCgUIBQAAAA==.Thndrsquirel:BAAANQAECgUICgABNQAECgYIDAAGAAAAAA==.Thrayne:BAAANQADCgQIBAAAAA==.',
Ti='Tiriandrel:BAAANQAECgIIAgABNQAECgkJJwARAPMeAA==.',
To='Toofaded:BAAANQADCgUIBQAAAA==.Torio:BAABNQAECn8dAAINAAgK9BbpBQA7AgANAAgK9BbpBQA7AgAAAA==.',
Tw='Twofow:BAAANQAECgQICQAAAA==.',
Ty='Tyranis:BAABNQAECn8gAAIHAAoKEhyMBAD8AgAHAAoKEhyMBAD8AgAAAA==.Tyê:BAABNQAECn8sAAMLAAoKHBQ/GgAgAgALAAoKHBQ/GgAgAgAKAAEKAAC6PQAxAAAAAA==.',
['Té']='Témalabécane:BAACNQAFFH8IAAIaAAQKshl4KABFAQAaAAQKshl4KABFAQA1AAQKfyMAAhoACgq2H8MxACcDABoACgq2H8MxACcDAAAA.',
['Të']='Tërry:BAAANQADCgEIAQAAAA==.',
Un='Unspoken:BAAANQADCgMIAwAAAA==.',
Va='Vael:BAAANQADCgYIBgAAAA==.Valexisea:BAAANQAECgUIBwAAAA==.Valériana:BAAANQAECgQIBAAAAA==.Vanítas:BAAANQADCgcIBgAAAA==.',
Ve='Vee:BAAANQAECggICwAAAA==.',
Vi='Visable:BAAANQAECgUIBwAAAA==.',
Vo='Voiddemon:BAAANQAECgQICwAAAA==.Voltage:BAAANQAECgQIDQABNQAECgYIGQABAMshAA==.',
Vu='Vulgnash:BAACNQAFFH8HAAIWAAMK1BwFBgACAQAWAAMK1BwFBgACAQA1AAQKf1UAAhYACgqkJGgDAEkDABYACgqkJGgDAEkDAAAA.Vult:BAABNQAECn8rAAIOAAoKRho+HgCZAgAOAAoKRho+HgCZAgAAAA==.',
Wa='Water:BAAANQAECgIIAgAAAA==.',
We='Weiyoung:BAAANQAECgEIAQAAAA==.Welgo:BAABNQAECn8sAAIeAAoKviHiAwBWAwAeAAoKviHiAwBWAwAAAA==.Welmage:BAAANQAECgIIAgABNQAECgoKLAAeAL4hAA==.Welpunch:BAAANQAECggIDgABNQAECgoKLAAeAL4hAA==.',
Wi='Wickeddemon:BAAANQAECgUIDwAAAA==.Windtusk:BAAANQADCggJCQAAAA==.',
Xc='Xcesive:BAAANQADCggJDQAAAA==.Xcessiv:BAAANQADCgQIBAAAAA==.Xcéssiv:BAABNQAECn8uAAIaAAoKOBzdTQDlAgAaAAoKOBzdTQDlAgAAAA==.',
Xe='Xerra:BAACNQAFFH8FAAIjAAIKdhE9DQCJAAAjAAIKdhE9DQCJAAA1AAQKf0AAAiMACgr4H+AKAC8DACMACgr4H+AKAC8DAAAA.',
['Xû']='Xûrû:BAAANQADCgQIBAAAAA==.',
Ye='Yeast:BAAANQAECgYIEwAAAA==.Yemoja:BAAANQAECgUIDgAAAA==.',
Yi='Yikes:BAAANQADCgQIBAABNQAFFAQICgASANMVAA==.',
Yr='Yravengi:BAAANQAECgQIBAAAAA==.Yrel:BAABNQAECn8ZAAMNAAgKXg6ZCAAuAQANAAgKXg6ZCAAuAQAMAAIKaQgGaQBdAAAAAA==.',
Ze='Zeit:BAABNQAECn8nAAQHAAkKmRDiDACBAQAHAAkKPRDiDACBAQAjAAMKjBBWVgC1AAAiAAQKZwnzaACCAAABNQAECgoKPAAPAAAaAA==.Zelgie:BAABNQAECn82AAIDAAoKTBpPIwCpAgADAAoKTBpPIwCpAgAAAA==.',
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
