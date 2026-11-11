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

local lookup = {'Warlock-Demonology','Paladin-Protection','Mage-Arcane','Warrior-Arms','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Monk-Windwalker','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','DemonHunter-Havoc','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','Rogue-Outlaw','Paladin-Holy','Shaman-Enhancement','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Monk-Mistweaver','Warrior-Protection','Mage-Fire','Mage-Frost','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Priest-Discipline','Monk-Brewmaster',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICwAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAABNQAECn8UAAIBAAgKZQZNvgBQAQABAAgKZQZNvgBQAQAAAA==.',
Ak='Akroma:BAABNQAECn8hAAICAAgKwBheGQAqAgACAAgKwBheGQAqAgABNQAECgoKHQADACETAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECn87AAIEAAkKYyChSgCpAgAEAAkKYyChSgCpAgAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Angerlia:BAAANQAECgMIBQAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgUIBwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECn9KAAIDAAoKYgydagDMAQADAAoKYgydagDMAQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECn8WAAIDAAoK5x1tawCnAgADAAoK5x1tawCnAgAAAA==.Arthuur:BAAANQAECgcICQABNQAECgoKKAAEAN4hAA==.Arykami:BAAANQAECgQIBgABNQAECgkJHgAFAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgAFAFceAA==.Arystrasza:BAABNQAECn8eAAIFAAkKVx5iCQANAwAFAAkKVx5iCQANAwAAAA==.Aryzhuque:BAAANQAECggIEQABNQAECgkJHgAFAFceAA==.',
As='Ashmandious:BAAANQAECggIEAAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECn8oAAIGAAoKniQJAQDiAwAGAAoKniQJAQDiAwAAAA==.',
At='Athleta:BAEBNQAFFH8YAAIHAAgKexs4AAD0AQAHAAgKexs4AAD0AQAAAA==.',
Av='Average:BAAANQADCgcIGwAAAA==.',
Ay='Ayana:BAAANQAECgYIBQAAAA==.',
Ba='Bajablastois:BAABNQAECn8YAAMGAAcKYCHJDwAmAgAGAAcKYCHJDwAmAgAIAAIK0xeELACPAAABNQAECgoKOgAJACAhAA==.Balkaj:BAAANQADCgEIAQAAAA==.Balrog:BAAANQADCgYIBgAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAABNQAECn80AAMKAAkK7xCVKgB9AQAKAAkK7xCVKgB9AQALAAgKWhDNMQBjAQAAAA==.',
Be='Beefajitas:BAAANQAECgQICAAAAA==.Beerhelmet:BAABNQAECn8zAAIMAAoKnxRiJQD5AQAMAAoKnxRiJQD5AQAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAABNQAECn8qAAINAAkKUhZ0QwAVAgANAAkKUhZ0QwAVAgAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgAOAAAAAA==.Birdstrike:BAAANQAECgYIBgAAAA==.',
Bl='Bleddyn:BAAANQADCgcICAAAAA==.Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECn8jAAIPAAkK3BqZQgCjAgAPAAkK3BqZQgCjAgAAAA==.Bowser:BAABNQAECn8dAAMEAAgKTAtFvQCEAQAEAAgKTAtFvQCEAQAQAAEKJwspMgAyAAAAAA==.',
Br='Braleanna:BAAANQAECgUICgAAAA==.Brigeta:BAABNQAECn8YAAMRAAkKwgEheABAAAARAAgKywEheABAAAASAAgKigASXAAOAAAAAA==.',
Bu='Budlofsky:BAABNQAECn8XAAMTAAoKvQv5RwDGAQATAAoKvQv5RwDGAQAUAAQKMwRTVABRAAAAAA==.Bugge:BAABNQAECn8YAAIKAAcKRhzsHwDgAQAKAAcKRhzsHwDgAQAAAA==.Bus:BAABNQAECn8qAAMGAAoKZybFAACFAwAGAAoKZybFAACFAwAIAAEKAAD5VwAAAAABNQAFFAgILAACAPgmAA==.',
Ca='Calinalia:BAAANQADCgcIBwAAAA==.',
Cb='Cbat:BAAANQAECgcIDgAAAA==.',
Cd='Cdicepalta:BAABNQAECn9BAAQLAAoKQhENJQDAAQALAAoKWBANJQDAAQAGAAkKKQsXMQAVAQAIAAQK6AnCLACsAAAAAA==.',
Ce='Cecile:BAAANQAECgYICgAAAA==.Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUIDgAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAACNQAFFH8JAAIJAAQKHRhoEADkAAAJAAQKHRhoEADkAAA1AAQKfyYAAgkACgrXH0EUAAoDAAkACgrXH0EUAAoDAAAA.Chevaiermort:BAAANQADCgcIDAAAAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCggIEgAAAA==.',
Co='Coinlock:BAAANQAECgUIDAAAAA==.Coldtouch:BAAANQADCgcIBwAAAA==.Confettii:BAAANQABCgQIBgABNQAECggIFAAPAAkLAA==.Conän:BAAANQAECgMIBAAAAA==.',
Ct='Ctrlaltshot:BAAANQAECgIIAgAAAA==.',
Cu='Cutedeath:BAAANQAECgEIAQAAAA==.Cuteretsu:BAAANQADCgYIBgAAAA==.',
Da='Dalus:BAABNQAECn8VAAIVAAoKyw3mdQATAQAVAAoKyw3mdQATAQAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECn8lAAMEAAoKuxHmggAUAgAEAAoKuxHmggAUAgAQAAEKRAdGNgAtAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECggIFQAWAOwFAA==.Dawny:BAABNQAECn8lAAMWAAoKkg2JawDJAQAWAAoKkg2JawDJAQAVAAIKCgxgDQFxAAAAAA==.Daywalkers:BAABNQAECn8UAAIPAAUKiBAJ4ABBAQAPAAUKiBAJ4ABBAQABNQAECggIFQAWAOwFAA==.',
De='Dethndk:BAABNQAECn8ZAAIJAAoKABk5KgBzAgAJAAoKABk5KgBzAgAAAA==.',
Di='Die:BAABNQAECn8iAAIXAAoK8xJxBwBAAgAXAAoK8xJxBwBAAgAAAA==.',
Do='Doorjob:BAABNQAECn8aAAMRAAkKJB8nIQCSAgARAAkKJB8nIQCSAgAHAAQK8A67IAC/AAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQACABsVAA==.',
Dr='Dragonslaye:BAAANQADCgQIBAAAAA==.Dreadravens:BAAANQAECgYIBgAAAA==.Dreamily:BAABNQAECn8lAAILAAoKTBHCOgAdAgALAAoKTBHCOgAdAgAAAA==.Dreamtalker:BAAANQABCggIEgAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ei='Eiliminteach:BAABNQAECn8hAAIVAAoKMhU4KwAdAgAVAAoKMhU4KwAdAgAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAABNQAECn8xAAIYAAkKjRbgKQBxAgAYAAkKjRbgKQBxAgAAAA==.Elfredo:BAAANQAECgQIBAAAAA==.Elia:BAABNQAECn8sAAIPAAoKwx43MwDSAgAPAAoKwx43MwDSAgAAAA==.Eligor:BAABNQAECn8uAAIBAAoKlgjaZQCRAQABAAoKlgjaZQCRAQAAAA==.Elisandre:BAAANQAECggICQAAAA==.Elmo:BAABNQAECn8cAAIJAAoKXxZwLwBVAgAJAAoKXxZwLwBVAgAAAA==.Elurrmental:BAABNQAECn8XAAMVAAgKIg3gmQBkAQAVAAYKvwrgmQBkAQAZAAgKnQyIGQBjAQAAAA==.Elzä:BAAANQAECgcIDgAAAA==.',
Em='Emergencii:BAAANQABCgMIBQABNQAECggIFAAPAAkLAA==.Emp:BAAANQAECgQICwAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECn8sAAIRAAoKmBzHHQCsAgARAAoKmBzHHQCsAgAAAA==.Entropius:BAABNQAECn8sAAIaAAkKlBBjJwCTAQAaAAkKlBBjJwCTAQAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Es='Esoteric:BAABNQAECn8gAAIbAAoKiR6hCQC5AgAbAAoKiR6hCQC5AgAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECggIFAAPAAkLAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECn8iAAIcAAoK1Q0jpQDWAQAcAAoK1Q0jpQDWAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feorial:BAAANQAECgYIBwAAAA==.Feralkitty:BAAANQAECggIEwAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQAFFAEIAQAAAA==.',
Fo='Fonzie:BAABNQAECn8iAAIVAAoKBg9/YQD9AQAVAAoKBg9/YQD9AQAAAA==.Foregotten:BAACNQAFFH8OAAILAAQK8BP8DwDlAAALAAQK8BP8DwDlAAA1AAQKfy0AAgsACgqRF+AqAIICAAsACgqRF+AqAIICAAAA.',
Fr='Frostietute:BAABNQAECn8sAAIDAAkKZB5aOgBSAgADAAkKZB5aOgBSAgAAAA==.',
Fu='Furysmight:BAABNQAECn8oAAIEAAoK3iH+JAAlAwAEAAoK3iH+JAAlAwAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAUIDwAdAA8gAA==.Galorw:BAAANQABCgIIAgAAAA==.Gamboa:BAABNQAECn8hAAIRAAkKLw2FLwCDAQARAAkKLw2FLwCDAQAAAA==.Gastly:BAAANQAECgEIAQABNQAECgcIEQAOAAAAAA==.Gauche:BAABNQAECn8xAAMeAAoK0RqIGAD2AQAeAAkKkBqIGAD2AQAMAAgK+huVGQDKAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Go='Goright:BAAANQAECgMIAwAAAA==.',
Gr='Grass:BAABNQAECn8WAAIDAAcK+BBz6gC1AQADAAcK+BBz6gC1AQAAAA==.Gravel:BAAANQADCggICQAAAA==.Grazka:BAAANQAECgIIAgAAAA==.Grÿmm:BAABNQAECn8mAAIIAAkK0gz0FgBGAQAIAAkK0gz0FgBGAQAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgABNQAECgEIAQAOAAAAAA==.Guldanica:BAAANQAECgQIBQAAAA==.Gunn:BAAANQAECgEIAQAAAA==.',
Gw='Gwaine:BAABNQAECn8aAAIfAAYKUAUsJQC7AAAfAAYKUAUsJQC7AAAAAA==.Gwin:BAABNQAECn8iAAQgAAgKLwNVCABxAAAgAAgKHwNVCABxAAAhAAgKFgFUQwA9AAADAAEKNgHC8AEKAAAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgcIEAAOAAAAAA==.Hartland:BAAANQAECgUIBwAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyl:BAAANQAECgIIAwAAAA==.Heritikyldin:BAAANQAECggIDAAAAA==.Heritikylust:BAABNQAECn8mAAIVAAoKlBrXMQCzAgAVAAoKlBrXMQCzAgAAAA==.',
Hi='Hibou:BAAANQAECgEIAQAAAA==.',
Ho='Holyhero:BAABNQAECn8kAAIbAAgKUxawIAAzAgAbAAgKUxawIAAzAgAAAA==.',
Il='Ilectra:BAABNQAECn80AAISAAoKURj3FQD6AQASAAoKURj3FQD6AQAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Ingodwetrust:BAAANQAECgEIAQAAAA==.Insanitii:BAAANQADCgEIAQABNQAECggIFAAPAAkLAA==.Intensitii:BAAANQABCgQICQABNQAECggIFAAPAAkLAA==.',
Ip='Ipoopied:BAAANQAECgEIAQAAAA==.',
Is='Ishmara:BAAANQAECgUICwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCggIDgAAAA==.Jazzhands:BAAANQABCgEIAQAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECn9XAAQBAAoK/BrjMwAxAgABAAoKshrjMwAxAgAiAAUKIxJvFgDAAAAjAAEKTQpHNgAzAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Keishara:BAAANQADCggIFwAAAA==.Kendragon:BAAANQABCgUICQAAAA==.Kentiger:BAAANQABCggICwAAAA==.Kepec:BAAANQAECgUIBgAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Ko='Korosh:BAAANQAECgIIAgAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECggIFwAVAA4KAA==.Krimzondawn:BAAANQADCgIIAgABNQAECggIFwAVAA4KAA==.Krimzonstorm:BAABNQAECn8XAAIVAAgKDgrtbAAqAQAVAAgKDgrtbAAqAQAAAA==.',
Ku='Kunaee:BAAANQAECgcIEQAAAA==.',
Ky='Kyrius:BAABNQAECn83AAMWAAoKAiHyEwAGAwAWAAoKAiHyEwAGAwAVAAEKXwLh/wAoAAAAAA==.',
['Kì']='Kìku:BAABNQAECn81AAIBAAkKnBMeVQDBAQABAAkKnBMeVQDBAQAAAA==.',
La='Labgrown:BAAANQAECgUIBwAAAA==.Lausia:BAABNQAECn81AAMhAAkKTBcgDQDhAQAhAAkKGRYgDQDhAQADAAQKOA1rGAF8AAABNQAECgoKNAASAFEYAA==.',
Ld='Ldyrose:BAAANQAECgUIDQAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAABNQAECn8iAAIPAAkKAhPxYADsAQAPAAkKAhPxYADsAQAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEgAOAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggICAABNQAECgEIAQAOAAAAAA==.',
Ma='Macabre:BAABNQAECn8VAAIJAAcKSgzmewAJAQAJAAcKSgzmewAJAQAAAA==.Magnificò:BAABNQAECn81AAIJAAkKGx5vFgBHAgAJAAkKGx5vFgBHAgAAAA==.Makani:BAABNQAECn8oAAIGAAkKDQ64KAAsAQAGAAkKDQ64KAAsAQAAAA==.Malarix:BAAANQADCgUIBQABNQADCgYIBgAOAAAAAA==.Malory:BAABNQAECn8cAAIfAAkKYiEKBQArAwAfAAkKYiEKBQArAwABNQAFFAUIDwAdAA8gAA==.Malzahär:BAABNQAECn8fAAQjAAoKQR+3HACIAQABAAkKzBtKVwBQAgAjAAUKpRy3HACIAQAiAAMK2hxGFwDWAAAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQAECgIIAgAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgcIEAAAAA==.Muffintop:BAABNQAECn8xAAMkAAkKpxzCKwDuAQAkAAkKNRzCKwDuAQAaAAYKAB/ySwDlAQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQAECgcIDgAAAA==.Mythrondrir:BAABNQAECn8+AAMkAAoKpRhEHQBPAgAkAAoKpRhEHQBPAgAJAAMKFQ5ZYgCwAAAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQADCggICAABNQAECgEIAQAOAAAAAA==.',
Ne='Neosnÿper:BAABNQAECn8zAAMKAAkKKRmrHQBDAgAKAAgKjBmrHQBDAgALAAkKYBTyOQAhAgABNQAFFAYIDgABAPYRAA==.',
Ni='Nielic:BAABNQAECn8zAAQNAAoKFhu6IwDeAgANAAoKFhu6IwDeAgAlAAQKewoBGwCQAAAbAAEKAAAPdQAAAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAUICQAVADIWAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Nobops:BAAANQADCggIEQAAAA==.Norrahh:BAAANQAECgcIDQAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Ny='Nyru:BAAANQAECgIIAQABNQAECgYIBgAOAAAAAA==.',
Ok='Okinawa:BAAANQADCggICAAAAA==.',
Om='Omgitsmagic:BAAANQAECgUIBgAAAA==.',
On='Ongo:BAABNQAECn86AAIDAAoKJw9VZQDaAQADAAoKJw9VZQDaAQAAAA==.',
Or='Orion:BAABNQAECn8wAAIhAAoKJwx1EACfAQAhAAoKJwx1EACfAQAAAA==.',
Pa='Palapoxi:BAABNQAECn8oAAIYAAoKkyDOEgA6AwAYAAoKkyDOEgA6AwAAAA==.',
Pe='Penelopè:BAABNQAECn8oAAImAAoKbSREAgCJAwAmAAoKbSREAgCJAwABNQAFFAQICQAJAB0YAA==.Penelópe:BAAANQADCgEIAQABNQAFFAQICQAJAB0YAA==.Penný:BAAANQAECgMIBQABNQAFFAQICQAJAB0YAA==.Pepino:BAABNQAECn8lAAIPAAcKexPWoQBTAQAPAAcKexPWoQBTAQAAAA==.',
Pf='Pflanlock:BAAANQAECgQIBQAAAA==.',
Ph='Phinx:BAABNQAECn8dAAIaAAoKThbyPwAeAgAaAAoKThbyPwAeAgAAAA==.Phocheux:BAABNQAECn8/AAIZAAoKAB3+CQBuAgAZAAoKAB3+CQBuAgAAAA==.Phulgoth:BAABNQAECn8kAAIaAAkKSRV9HADtAQAaAAkKSRV9HADtAQAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Piligo:BAAANQABCggICgAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgMIAwAAAA==.',
Po='Poco:BAAANQAECggICAAAAA==.Poetrii:BAABNQAECn8UAAIPAAgKCQttnQBcAQAPAAgKCQttnQBcAQAAAA==.Pomickyal:BAABNQAECn8zAAIBAAkKzgdChABBAQABAAkKzgdChABBAQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Pr='Prey:BAAANQAECggICAAAAA==.',
Ps='Pshamanthe:BAAANQAECgcIDAAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQAECgIIBgAAAA==.Ragnärok:BAABNQAECn8YAAIWAAoKyBODWwD9AQAWAAoKyBODWwD9AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFH8rAAIJAAcKXBxcCgCyAQAJAAcKXBxcCgCyAQA1AAQKf0AAAgkACgrkIR0MAFEDAAkACgrkIR0MAFEDAAAA.Reverii:BAAANQABCgYICAABNQAECggIFAAPAAkLAA==.Rez:BAAANQADCgcICwAAAA==.Rezelda:BAAANQAECgMIAwAAAA==.',
Ri='Rinahfire:BAAANQAECgQIBAAAAA==.',
Rj='Rj:BAABNQAECn8UAAMaAAYKeBBzaABvAQAaAAYKeBBzaABvAQAJAAEKAACxwgBDAAAAAA==.',
Ro='Rocky:BAAANQAECgQICAABNQAECgoKMwAMAJ8UAA==.Roughbbq:BAAANQADCgEIAQABNQAECgcIEQAOAAAAAA==.Roxi:BAAANQAECgQIBwAAAA==.',
Rt='Rtpopham:BAABNQAECn8aAAIEAAoK+w2YZQC6AQAEAAoK+w2YZQC6AQAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAABNQAECn8lAAIiAAcK4BMfCgCUAQAiAAcK4BMfCgCUAQAAAA==.Samusaran:BAAANQADCgQIBwAAAA==.Sandros:BAAANQAECgIIAwAAAA==.Saphrin:BAABNQAECn8xAAIRAAoKrxOvHgACAgARAAoKrxOvHgACAgAAAA==.Sardiirn:BAAANQAECgMIBwABNQAECggIFQAWAOwFAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAABNQAECn8vAAIDAAcKWBOD/wCPAQADAAcKWBOD/wCPAQAAAA==.',
Se='Selynne:BAABNQAECn8nAAIcAAoKoh/1SQC3AgAcAAoKoh/1SQC3AgAAAA==.Seofon:BAAANQAECgEIAQAAAA==.',
Sh='Shamanizeds:BAABNQAECn8VAAMWAAgK7AWyyQDUAAAWAAcKngOyyQDUAAAVAAEKAADfXwEZAAAAAA==.Shamwisegamg:BAAANQADCgYICgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQAECgMIBQAAAA==.Shifted:BAABNQAECn8mAAIGAAoKSA0YHwCmAQAGAAoKSA0YHwCmAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.Shé:BAABNQAECn8WAAIGAAkKmBAmIQBiAQAGAAkKmBAmIQBiAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAABNQAECn8UAAIPAAgKIRKmZADjAQAPAAgKIRKmZADjAQAAAA==.Sixligma:BAABNQAECn8bAAQYAAYKIwlUqwAqAQAYAAYKIwlUqwAqAQAcAAIKrARyigFLAAACAAEKXgMbbAAgAAAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAFFAQIDgALAPATAA==.',
Sl='Slorrin:BAABNQAECn8mAAIEAAoKMyTQDwCAAwAEAAoKMyTQDwCAAwAAAA==.',
So='Solazreiale:BAAANQAECgcIEQAAAA==.Somers:BAAANQAECgEIAQAAAA==.',
Sp='Spellbind:BAABNQAECn8kAAMhAAgKSh55GwDkAAADAAYKJx6b+wCWAQAhAAMK5B15GwDkAAAAAA==.Spy:BAAANQAECgEIAQABNQAFFAUICAAKAFgQAA==.',
St='Starstorms:BAABNQAECn81AAIKAAkKPRksFABwAgAKAAkKPRksFABwAgAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Sunarri:BAAANQADCgYIBgABNQAECgIIBgAOAAAAAA==.Suun:BAAANQAECgYICwAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgABNQAECgUIBQAOAAAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAABNQAECn8gAAIZAAkKqwYHGQBqAQAZAAkKqwYHGQBqAQAAAA==.Taiez:BAABNQAECn8zAAMjAAkKYw8ZBwBSAQAjAAkKYw8ZBwBSAQAiAAEKlgfnLwA2AAAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQIBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQAECgQIBAAAAA==.Therapii:BAAANQABCgQIBQABNQAECggIFAAPAAkLAA==.Thesledge:BAABNQAECn9HAAIcAAoK5huPQQBWAgAcAAoK5huPQQBWAgAAAA==.',
Ti='Tifalockhàrt:BAACNQAFFH8OAAIYAAQK5AajFADgAAAYAAQK5AajFADgAAA1AAQKfy8AAxgACgorB4iDAJABABgACgorB4iDAJABAAIAAQqRC6RjAC0AAAAA.Timewarped:BAABNQAECn86AAIDAAkK7hJDWAD7AQADAAkK7hJDWAD7AQAAAA==.',
To='Totemshat:BAAANQAECgcIDgAAAA==.',
Tr='Trapsin:BAACNQAFFH8IAAIDAAIKgRVNNACTAAADAAIKgRVNNACTAAA1AAQKfysAAgMACgoSINk4ABYDAAMACgoSINk4ABYDAAAA.Treeage:BAABNQAECn8jAAQIAAkKsRFEDgAyAgAIAAkKsRFEDgAyAgALAAIKSQTAqgBBAAAGAAEKtgQMZAAsAAAAAA==.Trufflé:BAABNQAECn84AAIVAAkKcBcRSQCaAQAVAAkKcBcRSQCaAQAAAA==.Trustportal:BAABNQAECn8dAAIDAAoKIROxTgAVAgADAAoKIROxTgAVAgAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECn81AAIkAAoK2R6qEgCtAgAkAAoK2R6qEgCtAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgUICQABNQAECgoKNAASAFEYAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valadin:BAAANQADCgUIBQAAAA==.Valstan:BAAANQAECgcIEwAAAA==.Valzyn:BAABNQAECn8YAAIMAAoK8wzCLQCrAQAMAAoK8wzCLQCrAQAAAA==.Varitek:BAAANQAECgQIBAAAAA==.Vates:BAAANQAECgMIAwAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECn8oAAMbAAoKOBPyJQD/AQAbAAkKPRTyJQD/AQANAAYKkBDTkwBbAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgoKKAAYAJMgAA==.Warisfluffy:BAABNQAECn8dAAIRAAgK9gwbTABwAQARAAgK9gwbTABwAQAAAA==.Wariss:BAAANQAECgUIBQAAAA==.',
We='Wedaddams:BAABNQAECn8XAAMgAAkKkAE5CQBeAAAgAAgKuQE5CQBeAAADAAkKUAB9YQEhAAAAAA==.Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEIAQAAAA==.',
Wo='Worldboss:BAABNQAECn8iAAICAAkK/hMhHQBxAQACAAkK/hMhHQBxAQAAAA==.Worldwar:BAABNQAECn8UAAMEAAYKOwyrtQD4AAAEAAYKOwyrtQD4AAAQAAEKQARXOwAcAAAAAA==.',
Wr='Wradalin:BAABNQAECn8dAAIkAAkKZx3oJgBfAgAkAAkKZx3oJgBfAgAAAA==.Wraithstorm:BAABNQAECn8WAAMGAAgKWxtWFQASAgAGAAcKxxxWFQASAgALAAEKPxTofgA8AAAAAA==.',
Ya='Yashimbou:BAAANQADCgMIAwABNQAECggIFQAWAOwFAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zarila:BAAANQAECgUICgAAAA==.Zartain:BAABNQAECn8zAAIUAAgKHhCpFwBgAQAUAAgKHhCpFwBgAQAAAA==.',
Ze='Zelarus:BAAANQAECggICAAAAA==.Zenizho:BAAANQAECgMIBQAAAA==.Zennamite:BAABNQAECn8zAAIVAAoKLxIZPQDKAQAVAAoKLxIZPQDKAQAAAA==.Zennarion:BAAANQABCgIIAgAAAA==.',
Zi='Zipzaps:BAAANQAECgIIBAAAAA==.',
Zu='Zuldarack:BAAANQAECgIIAQAAAA==.',
Zy='Zyalia:BAAANQADCgYICgAAAA==.',
['Çe']='Çelest:BAAANQAECgEIAQAAAA==.',
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
