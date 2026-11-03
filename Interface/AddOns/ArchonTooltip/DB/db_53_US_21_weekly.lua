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

local lookup = {'Warlock-Demonology','Paladin-Protection','Mage-Arcane','Warrior-Arms','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Balance','Druid-Restoration','Monk-Windwalker','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Holy','Shaman-Enhancement','DeathKnight-Unholy','Priest-Shadow','Paladin-Retribution','Evoker-Augmentation','Monk-Mistweaver','Warrior-Protection','Mage-Fire','Mage-Frost','DemonHunter-Devourer','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Priest-Discipline','Monk-Brewmaster',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICwAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAABNQAECn8UAAIBAAgKZQZNvgBQAQABAAgKZQZNvgBQAQAAAA==.',
Ak='Akroma:BAABNQAECn8dAAICAAgKwBheGQAqAgACAAgKwBheGQAqAgABNQAECgoKGQADAOQRAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECn87AAIEAAkKYyChSgCpAgAEAAkKYyChSgCpAgAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Angerlia:BAAANQAECgMIAwAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgUIBwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECn9DAAIDAAoKqQuodwCNAQADAAoKqQuodwCNAQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECn8WAAIDAAoK5x1tawCnAgADAAoK5x1tawCnAgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgoKJwAEAN4hAA==.Arykami:BAAANQAECgQIBgABNQAECgkJHgAFAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgAFAFceAA==.Arystrasza:BAABNQAECn8eAAIFAAkKVx5iCQANAwAFAAkKVx5iCQANAwAAAA==.Aryzhuque:BAAANQAECggIDgABNQAECgkJHgAFAFceAA==.',
As='Ashmandious:BAAANQAECggIEAAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECn8oAAIGAAoKniQJAQDiAwAGAAoKniQJAQDiAwAAAA==.',
At='Athleta:BAEBNQAFFH8YAAIHAAgKexsmAAAAAgAHAAgKexsmAAAAAgAAAA==.',
Av='Average:BAAANQADCgcIGwAAAA==.',
Ay='Ayana:BAAANQAECgYIBQAAAA==.',
Ba='Bajablastois:BAABNQAECn8VAAIGAAcKJSGLDQAmAgAGAAcKJSGLDQAmAgABNQAECgoKOgAIACAhAA==.Balkaj:BAAANQADCgEIAQAAAA==.Balrog:BAAANQADCgYIBgAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAABNQAECn8xAAMJAAgKtA5OLgBYAQAJAAgKtA5OLgBYAQAKAAgKThDVLQA3AQAAAA==.',
Be='Beefajitas:BAAANQAECgQICAAAAA==.Beerhelmet:BAABNQAECn8zAAILAAoKnxRiJQD5AQALAAoKnxRiJQD5AQAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAABNQAECn8oAAIMAAgKXhhKRADvAQAMAAgKXhhKRADvAQAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgANAAAAAA==.Birdstrike:BAAANQAECgYIBgAAAA==.',
Bl='Bleddyn:BAAANQADCgcICAAAAA==.Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECn8jAAIOAAkK3BqZQgCjAgAOAAkK3BqZQgCjAgAAAA==.Bowser:BAABNQAECn8cAAMEAAgKTAtFvQCEAQAEAAgKTAtFvQCEAQAPAAEKJwsxLAAyAAAAAA==.',
Br='Braleanna:BAAANQAECgUICgAAAA==.Brigeta:BAAANQAECggIDwAAAA==.',
Bu='Budlofsky:BAABNQAECn8WAAMQAAoKvQuTPgC9AQAQAAoKvQuTPgC9AQARAAQKMwRrUABUAAAAAA==.Bugge:BAABNQAECn8WAAIKAAcKRhzxGgDjAQAKAAcKRhzxGgDjAQAAAA==.Bus:BAABNQAECn8oAAIGAAoKZyaeAACHAwAGAAoKZyaeAACHAwABNQAFFAgIJgACAPgmAA==.',
Ca='Calinalia:BAAANQADCgcIBwAAAA==.',
Cb='Cbat:BAAANQAECgcIDgAAAA==.',
Cd='Cdicepalta:BAABNQAECn8/AAQJAAoKUxAVJAClAQAJAAoK8A4VJAClAQAGAAkKKQsXMQAVAQASAAQK6AnCLACsAAAAAA==.',
Ce='Cecile:BAAANQAECgYICgAAAA==.Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUIDgAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAACNQAFFH8HAAIIAAQKHRiCDQDoAAAIAAQKHRiCDQDoAAA1AAQKfyYAAggACgrXH0EUAAoDAAgACgrXH0EUAAoDAAAA.Chevaiermort:BAAANQADCgcIDAAAAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCggIEgAAAA==.',
Co='Coinlock:BAAANQAECgUIDAAAAA==.Coldtouch:BAAANQADCgcIBwAAAA==.Confettii:BAAANQABCgQIBgABNQAECggIFAAOAAkLAA==.Conän:BAAANQAECgQIAwAAAA==.',
Ct='Ctrlaltshot:BAAANQAECgIIAgAAAA==.',
Cu='Cutedeath:BAAANQAECgEIAQAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAABNQAECn8VAAITAAoKyA1xaAAUAQATAAoKyA1xaAAUAQAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECn8lAAMEAAoKuxHmggAUAgAEAAoKuxHmggAUAgAPAAEKRAdGNgAtAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECggIEgANAAAAAA==.Dawny:BAABNQAECn8lAAMUAAoKkg2JawDJAQAUAAoKkg2JawDJAQATAAIKCgxgDQFxAAAAAA==.Daywalkers:BAABNQAECn8UAAIOAAUKiBAJ4ABBAQAOAAUKiBAJ4ABBAQABNQAECggIEgANAAAAAA==.',
De='Dethndk:BAABNQAECn8ZAAIIAAoKABk5KgBzAgAIAAoKABk5KgBzAgAAAA==.',
Di='Die:BAABNQAECn8iAAIVAAoK8xJxBwBAAgAVAAoK8xJxBwBAAgAAAA==.',
Do='Doorjob:BAABNQAECn8aAAMWAAkKJB8nIQCSAgAWAAkKJB8nIQCSAgAHAAQK8A67IAC/AAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQACABsVAA==.',
Dr='Dragonslaye:BAAANQADCgQIBAAAAA==.Dreadravens:BAAANQAECgYIBgAAAA==.Dreamily:BAABNQAECn8lAAIJAAoKTBHCOgAdAgAJAAoKTBHCOgAdAgAAAA==.Dreamtalker:BAAANQABCggIEgAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ei='Eiliminteach:BAABNQAECn8XAAITAAgKRBUsQACYAQATAAgKRBUsQACYAQAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAABNQAECn8qAAIXAAgKShUlNwAKAgAXAAgKShUlNwAKAgAAAA==.Elfredo:BAAANQAECgQIBAAAAA==.Elia:BAABNQAECn8qAAIOAAoKwx43MwDSAgAOAAoKwx43MwDSAgAAAA==.Eligor:BAABNQAECn8tAAIBAAoKWghuXQCCAQABAAoKWghuXQCCAQAAAA==.Elisandre:BAAANQAECggICQAAAA==.Elmo:BAABNQAECn8cAAIIAAoKXxZwLwBVAgAIAAoKXxZwLwBVAgAAAA==.Elurrmental:BAABNQAECn8XAAMYAAgKIg3AFgBjAQATAAYKvwrgmQBkAQAYAAgKnQzAFgBjAQAAAA==.Elzä:BAAANQAECgYIDQAAAA==.',
Em='Emergencii:BAAANQABCgMIBQABNQAECggIFAAOAAkLAA==.Emp:BAAANQAECgQICgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECn8sAAIWAAoKmBzHHQCsAgAWAAoKmBzHHQCsAgAAAA==.Entropius:BAABNQAECn8pAAIZAAgKGxD7KgBbAQAZAAgKGxD7KgBbAQAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Es='Esoteric:BAABNQAECn8cAAIaAAoKkh1kCQClAgAaAAoKkh1kCQClAgAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECggIFAAOAAkLAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECn8iAAIbAAoK1Q0jpQDWAQAbAAoK1Q0jpQDWAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feorial:BAAANQAECgYIBwAAAA==.Feralkitty:BAAANQAECggIEwAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECn8iAAITAAoKBg9/YQD9AQATAAoKBg9/YQD9AQAAAA==.Foregotten:BAACNQAFFH8LAAIJAAMK4hH9DQDgAAAJAAMK4hH9DQDgAAA1AAQKfywAAgkACgqRF+AqAIICAAkACgqRF+AqAIICAAAA.',
Fr='Frostietute:BAABNQAECn8qAAIDAAkKZB6wMABfAgADAAkKZB6wMABfAgAAAA==.',
Fu='Furysmight:BAABNQAECn8nAAIEAAoK3iH+JAAlAwAEAAoK3iH+JAAlAwAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAUIDwAcAA8gAA==.Galorw:BAAANQABCgIIAgAAAA==.Gamboa:BAABNQAECn8aAAIWAAgKjAxZNAA9AQAWAAgKjAxZNAA9AQAAAA==.Gastly:BAAANQAECgEIAQABNQAECgcIEQANAAAAAA==.Gauche:BAABNQAECn8vAAMdAAoK3xyIGAD2AQAdAAgKDRyIGAD2AQALAAgK+ht+FgDOAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Go='Goright:BAAANQAECgMIAwAAAA==.',
Gr='Grass:BAABNQAECn8WAAIDAAcK+BBz6gC1AQADAAcK+BBz6gC1AQAAAA==.Gravel:BAAANQADCggICQAAAA==.Grazka:BAAANQAECgIIAgAAAA==.Grÿmm:BAABNQAECn8mAAISAAkK0gw6EwBIAQASAAkK0gw6EwBIAQAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.Guldanica:BAAANQAECgQIBQAAAA==.Gunn:BAAANQAECgEIAQAAAA==.',
Gw='Gwaine:BAABNQAECn8aAAIeAAYKUAWRIADBAAAeAAYKUAWRIADBAAAAAA==.Gwin:BAABNQAECn8aAAQfAAgKDQM1BwBrAAAfAAgK1wI1BwBrAAAgAAgKFgFUQwA9AAADAAEKNgHC8AEKAAAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgcIEAANAAAAAA==.Hartland:BAAANQAECgUIBwAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyl:BAAANQAECgIIAgAAAA==.Heritikyldin:BAAANQAECggIDAAAAA==.Heritikylust:BAABNQAECn8mAAITAAoKlBrXMQCzAgATAAoKlBrXMQCzAgAAAA==.',
Hi='Hibou:BAAANQAECgEIAQAAAA==.',
Ho='Holyhero:BAABNQAECn8kAAIaAAgKUxawIAAzAgAaAAgKUxawIAAzAgAAAA==.',
Il='Ilectra:BAABNQAECn8zAAIhAAoKURgUEwD+AQAhAAoKURgUEwD+AQAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Insanitii:BAAANQADCgEIAQABNQAECggIFAAOAAkLAA==.Intensitii:BAAANQABCgQICQABNQAECggIFAAOAAkLAA==.',
Ip='Ipoopied:BAAANQAECgEIAQAAAA==.',
Is='Ishmara:BAAANQAECgUICwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCggIDgAAAA==.Jazzhands:BAAANQABCgEIAQAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECn9QAAQBAAoK/Bo+LAAyAgABAAoKsho+LAAyAgAiAAQKAg85HgCJAAAjAAEKTQpGMgAzAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Keishara:BAAANQADCggIFwAAAA==.Kendragon:BAAANQABCgUICQAAAA==.Kentiger:BAAANQABCggICwAAAA==.Kepec:BAAANQAECgUIBgABNQAECggIDAANAAAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Ko='Korosh:BAAANQAECgIIAgAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgcIFAATAKgJAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgcIFAATAKgJAA==.Krimzonstorm:BAABNQAECn8UAAITAAcKqAmmdQDwAAATAAcKqAmmdQDwAAAAAA==.',
Ku='Kunaee:BAAANQAECgYIEAAAAA==.',
Ky='Kyrius:BAABNQAECn8qAAMUAAoKAiH9DwAVAwAUAAoKAiH9DwAVAwATAAEKXwID7gAoAAAAAA==.',
['Kì']='Kìku:BAABNQAECn8yAAIBAAgK0hTNWgCKAQABAAgK0hTNWgCKAQAAAA==.',
La='Labgrown:BAAANQAECgUIBwAAAA==.Lausia:BAABNQAECn8yAAMgAAgKhRYgDQDhAQAgAAgKIBUgDQDhAQADAAQKOA2lCgF8AAABNQAECgoKMwAhAFEYAA==.',
Ld='Ldyrose:BAAANQAECgUIDQAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAABNQAECn8fAAIOAAgKTQ9FewB8AQAOAAgKTQ9FewB8AQAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEgANAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggICAABNQAECgEIAQANAAAAAA==.',
Ma='Macabre:BAABNQAECn8VAAIIAAcKSgzmewAJAQAIAAcKSgzmewAJAQAAAA==.Magnificò:BAABNQAECn8yAAIIAAgK2BwRHgDfAQAIAAgK2BwRHgDfAQAAAA==.Makani:BAABNQAECn8hAAIGAAgKeQ52KwD4AAAGAAgKeQ52KwD4AAAAAA==.Malarix:BAAANQADCgUIBQABNQADCgYIBgANAAAAAA==.Malory:BAABNQAECn8cAAIeAAkKYiEKBQArAwAeAAkKYiEKBQArAwABNQAFFAUIDwAcAA8gAA==.Malzahär:BAABNQAECn8bAAQjAAkKzSC3HACIAQABAAcKUCFKVwBQAgAjAAUKpRy3HACIAQAiAAMK2hxGFwDWAAAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQAECgIIAgAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgcIEAAAAA==.Muffintop:BAABNQAECn8uAAMkAAgK8hzkMQAaAgAkAAgKbBzkMQAaAgAZAAYKAB/ySwDlAQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQAECgYIDQAAAA==.Mythrondrir:BAABNQAECn82AAMkAAoK0hdlHQArAgAkAAoK0hdlHQArAgAIAAEKkg4HiwA9AAAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQADCggICAABNQAECgEIAQANAAAAAA==.',
Ne='Neosnÿper:BAABNQAECn8zAAMKAAkKKRmrHQBDAgAKAAgKjBmrHQBDAgAJAAkKYBTPKQB4AQABNQAFFAUIDAABANIVAA==.',
Ni='Nielic:BAABNQAECn8wAAQMAAoKVBq6IwDeAgAMAAoKVBq6IwDeAgAlAAQKewoBGwCQAAAaAAEKAADmagAAAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAcIGwATADwXAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Norrahh:BAAANQAECgYIDAAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Ny='Nyru:BAAANQAECgIIAQABNQAECgYIBgANAAAAAA==.',
Om='Omgitsmagic:BAAANQAECgUIBgAAAA==.',
On='Ongo:BAABNQAECn82AAIDAAoKXQ5rXgDQAQADAAoKXQ5rXgDQAQAAAA==.',
Or='Orion:BAABNQAECn8oAAIgAAgKnAt1EACfAQAgAAgKnAt1EACfAQAAAA==.',
Pa='Palapoxi:BAABNQAECn8oAAIXAAoKkyDOEgA6AwAXAAoKkyDOEgA6AwAAAA==.',
Pe='Penelopè:BAABNQAECn8oAAImAAoKbSREAgCJAwAmAAoKbSREAgCJAwABNQAFFAQIBwAIAB0YAA==.Penelópe:BAAANQADCgEIAQABNQAFFAQIBwAIAB0YAA==.Penný:BAAANQAECgMIBQABNQAFFAQIBwAIAB0YAA==.Pepino:BAABNQAECn8lAAIOAAcKexNViwBYAQAOAAcKexNViwBYAQAAAA==.',
Pf='Pflanlock:BAAANQAECgEIAQAAAA==.',
Ph='Phinx:BAABNQAECn8dAAIZAAoKThbyPwAeAgAZAAoKThbyPwAeAgAAAA==.Phocheux:BAABNQAECn85AAIYAAoKAB04CAB2AgAYAAoKAB04CAB2AgAAAA==.Phulgoth:BAABNQAECn8dAAIZAAkKOxI0HwC1AQAZAAkKOxI0HwC1AQAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Piligo:BAAANQABCggICgAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgMIAwAAAA==.',
Po='Poco:BAAANQAECggICAAAAA==.Poetrii:BAABNQAECn8UAAIOAAgKCQuQjQBTAQAOAAgKCQuQjQBTAQAAAA==.Pomickyal:BAABNQAECn8yAAIBAAgK+Qc5iQAUAQABAAgK+Qc5iQAUAQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Pr='Prey:BAAANQAECggIBwAAAA==.',
Ps='Pshamanthe:BAAANQAECgcIDAAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQAECgEIAwAAAA==.Ragnärok:BAABNQAECn8YAAIUAAoKyBODWwD9AQAUAAoKyBODWwD9AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFH8rAAIIAAcKXByJBgBuAQAIAAcKXByJBgBuAQA1AAQKfz8AAggACgq2IR0MAFEDAAgACgq2IR0MAFEDAAAA.Reverii:BAAANQABCgYICAABNQAECggIFAAOAAkLAA==.Rez:BAAANQADCgcICwAAAA==.Rezelda:BAAANQAECgMIAwAAAA==.',
Ri='Rinahfire:BAAANQAECgQIBAAAAA==.',
Rj='Rj:BAABNQAECn8UAAMZAAYKeBBzaABvAQAZAAYKeBBzaABvAQAIAAEKAACxwgBDAAAAAA==.',
Ro='Rocky:BAAANQAECgQICAABNQAECgoKMwALAJ8UAA==.Roughbbq:BAAANQADCgEIAQABNQAECgcIEQANAAAAAA==.Roxi:BAAANQAECgQIBwAAAA==.',
Rt='Rtpopham:BAAANQAECggIDwAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAABNQAECn8eAAIiAAcK7xHgDACPAQAiAAcK7xHgDACPAQAAAA==.Samusaran:BAAANQADCgQIBwAAAA==.Sandros:BAAANQAECgIIAQAAAA==.Saphrin:BAABNQAECn8uAAIWAAkK2hAjJwCVAQAWAAkK2hAjJwCVAQAAAA==.Sardiirn:BAAANQAECgMIBgABNQAECggIEgANAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAABNQAECn8vAAIDAAcKWBPltQAPAQADAAcKWBPltQAPAQAAAA==.',
Se='Selynne:BAABNQAECn8nAAIbAAoKoh/1SQC3AgAbAAoKoh/1SQC3AgAAAA==.Seofon:BAAANQAECgEIAQAAAA==.',
Sh='Shamanizeds:BAAANQAECggIEgAAAA==.Shamwisegamg:BAAANQADCgYICgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQAECgMIBQAAAA==.Shifted:BAABNQAECn8mAAIGAAoKSA0YHwCmAQAGAAoKSA0YHwCmAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.Shé:BAABNQAECn8UAAIGAAkKaBCAHABlAQAGAAkKaBCAHABlAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQAECgcIEAAAAA==.Sixligma:BAABNQAECn8VAAQXAAYKBQlUqwAqAQAXAAYKBQlUqwAqAQAbAAIKrARyigFLAAACAAEKpAJPZgAZAAAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAFFAMICwAJAOIRAA==.',
Sl='Slorrin:BAABNQAECn8mAAIEAAoKMyTQDwCAAwAEAAoKMyTQDwCAAwAAAA==.',
So='Solazreiale:BAAANQAECgYIEAAAAA==.Somers:BAAANQAECgEIAQAAAA==.',
Sp='Spellbind:BAABNQAECn8iAAMgAAgKxRzLFwDnAAADAAYK3hub+wCWAQAgAAMK5B3LFwDnAAAAAA==.Spy:BAAANQAECgEIAQABNQAFFAUICAAKAFgQAA==.',
St='Starstorms:BAABNQAECn8yAAIKAAgKaxoNFQAyAgAKAAgKaxoNFQAyAgAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQAECgYICwAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAABNQAECn8dAAIYAAgKpQaVGQA4AQAYAAgKpQaVGQA4AQAAAA==.Taiez:BAABNQAECn8pAAMjAAcKhQyFHwBzAQAjAAcKhQyFHwBzAQAiAAEKlgfnLwA2AAAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQIBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQAECgQIBAAAAA==.Therapii:BAAANQABCgQIBQABNQAECggIFAAOAAkLAA==.Thesledge:BAABNQAECn9BAAIbAAoK5hv4NwBXAgAbAAoK5hv4NwBXAgAAAA==.',
Ti='Tifalockhàrt:BAACNQAFFH8LAAIXAAMKUwPEFwCZAAAXAAMKUwPEFwCZAAA1AAQKfy4AAxcACgorB4iDAJABABcACgorB4iDAJABAAIAAQqRCxNcAC0AAAAA.Timewarped:BAABNQAECn80AAIDAAkKHRI1VgDoAQADAAkKHRI1VgDoAQAAAA==.',
To='Totemshat:BAAANQAECgYIDAAAAA==.',
Tr='Trapsin:BAACNQAFFH8IAAIDAAIKgRUoLgCWAAADAAIKgRUoLgCWAAA1AAQKfysAAgMACgoSINk4ABYDAAMACgoSINk4ABYDAAAA.Treeage:BAABNQAECn8jAAQSAAkKsRFEDgAyAgASAAkKsRFEDgAyAgAJAAIKSQTAqgBBAAAGAAEKtgQMZAAsAAAAAA==.Trufflé:BAABNQAECn8yAAITAAgKXRhdXgAHAgATAAgKXRhdXgAHAgAAAA==.Trustportal:BAABNQAECn8ZAAIDAAoK5BFtSgAJAgADAAoK5BFtSgAJAgAAAA==.',
Ty='Tyg:BAABNQAECn8yAAIkAAoK2R4BDwC5AgAkAAoK2R4BDwC5AgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgUICQABNQAECgoKMwAhAFEYAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valstan:BAAANQAECgcIEwAAAA==.Valzyn:BAABNQAECn8YAAILAAoK8wzCLQCrAQALAAoK8wzCLQCrAQAAAA==.Varitek:BAAANQAECgQIBAAAAA==.Vates:BAAANQAECgEIAQAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECn8oAAMaAAoKOBPyJQD/AQAaAAkKPRTyJQD/AQAMAAYKkBDTkwBbAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgoKKAAXAJMgAA==.Warisfluffy:BAABNQAECn8cAAIWAAcK+gwbTABwAQAWAAcK+gwbTABwAQAAAA==.Wariss:BAAANQAECgUIBQAAAA==.',
We='Wedaddams:BAABNQAECn8XAAMfAAkKkAGqBwBfAAAfAAgKuQGqBwBfAAADAAkKUAAyUgEiAAAAAA==.Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEIAQAAAA==.',
Wo='Worldboss:BAABNQAECn8iAAICAAkK/hOxGAB7AQACAAkK/hOxGAB7AQAAAA==.Worldwar:BAABNQAECn8UAAMEAAYKOwyjpQD6AAAEAAYKOwyjpQD6AAAPAAEKQARXOwAcAAAAAA==.',
Wr='Wradalin:BAABNQAECn8dAAIkAAkKZx3oJgBfAgAkAAkKZx3oJgBfAgAAAA==.Wraithstorm:BAABNQAECn8WAAMGAAgKWxtWFQASAgAGAAcKxxxWFQASAgAJAAEKPxSKdgA8AAAAAA==.',
Ya='Yashimbou:BAAANQADCgMIAwABNQAECggIEgANAAAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQAECgUICgAAAA==.Zartain:BAABNQAECn8yAAIRAAgKHhCvFQBkAQARAAgKHhCvFQBkAQAAAA==.',
Ze='Zelarus:BAAANQAECggICAAAAA==.Zenizho:BAAANQAECgIIAwAAAA==.Zennamite:BAABNQAECn8uAAITAAgKDhLPVwBEAQATAAgKDhLPVwBEAQAAAA==.',
Zi='Zipzaps:BAAANQAECgIIBAAAAA==.',
Zu='Zuldarack:BAAANQAECgIIAQAAAA==.',
Zy='Zyalia:BAAANQADCgQIBAAAAA==.',
['Çe']='Çelest:BAAANQADCgQIAwAAAA==.',
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
