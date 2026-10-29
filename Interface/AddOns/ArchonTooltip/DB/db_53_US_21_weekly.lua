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

local lookup = {'Warlock-Demonology','Paladin-Protection','Warrior-Arms','Mage-Arcane','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Monk-Windwalker','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Holy','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Retribution','Evoker-Devastation','Monk-Mistweaver','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Warlock-Affliction','Mage-Frost','Warlock-Destruction','DeathKnight-Frost','Priest-Discipline','Monk-Brewmaster','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-10-27',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICwAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAABNQAECn8UAAIBAAgKZQZNvgBQAQABAAgKZQZNvgBQAQAAAA==.',
Ak='Akroma:BAABNQAECn8dAAICAAgKwBheGQAqAgACAAgKwBheGQAqAgAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECn87AAIDAAkKYyChSgCpAgADAAkKYyChSgCpAgAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Angerlia:BAAANQAECgIIAgAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgUIBwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECn82AAIEAAoKzAoVTQDIAQAEAAoKzAoVTQDIAQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECn8WAAIEAAoK5x1tawCnAgAEAAoK5x1tawCnAgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgoKJgADAEohAA==.Arykami:BAAANQAECgQIBgABNQAECgkJHgAFAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgAFAFceAA==.Arystrasza:BAABNQAECn8eAAIFAAkKVx5iCQANAwAFAAkKVx5iCQANAwAAAA==.Aryzhuque:BAAANQAECggIDQABNQAECgkJHgAFAFceAA==.',
As='Ashmandious:BAAANQAECggIEAAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECn8oAAIGAAoKniQJAQDiAwAGAAoKniQJAQDiAwAAAA==.',
At='Athleta:BAEBNQAFFH8YAAIHAAgKexsYAAAXAgAHAAgKexsYAAAXAgAAAA==.',
Av='Average:BAAANQADCgYIFQAAAA==.',
Ay='Ayana:BAAANQAECgUIBQAAAA==.',
Ba='Bajablastois:BAAANQAECgYIDwABNQAECgoKOgAIACAhAA==.Balkaj:BAAANQADCgEIAQAAAA==.Balrog:BAAANQADCgYIBgAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAABNQAECn8qAAMJAAgKThAiIwBDAQAJAAgKThAiIwBDAQAKAAQKmgY+WQBoAAAAAA==.',
Be='Beefajitas:BAAANQAECgUIBQAAAA==.Beerhelmet:BAABNQAECn8tAAILAAoKdBOMGABvAQALAAoKdBOMGABvAQAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAABNQAECn8hAAIMAAgK9xcaMwDwAQAMAAgK9xcaMwDwAQAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgANAAAAAA==.Birdstrike:BAAANQAECgYIBgAAAA==.',
Bl='Bleddyn:BAAANQADCgcIBwAAAA==.Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECn8jAAIOAAkK3BqZQgCjAgAOAAkK3BqZQgCjAgAAAA==.Bowser:BAABNQAECn8cAAMDAAgKTAtFvQCEAQADAAgKTAtFvQCEAQAPAAEKJwtlIwAyAAAAAA==.',
Br='Braleanna:BAAANQAECgUICgAAAA==.Brigeta:BAAANQAECggIDwAAAA==.',
Bu='Budlofsky:BAAANQAFFAEIAQAAAA==.Bugge:BAABNQAECn8UAAIJAAcK7BsoFADmAQAJAAcK7BsoFADmAQAAAA==.Bus:BAABNQAECn8gAAIGAAoKYybXAADqAwAGAAoKYybXAADqAwABNQAFFAgIHwACANMmAA==.',
Ca='Calinalia:BAAANQADCgcIBwAAAA==.',
Cb='Cbat:BAAANQAECgcIDgAAAA==.',
Cd='Cdicepalta:BAABNQAECn84AAQKAAoKzQ/eHgCRAQAKAAoKVw7eHgCRAQAGAAkKKQsXMQAVAQAQAAQK6AnCLACsAAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUICwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECn8lAAIIAAoKwR9BFAAKAwAIAAoKwR9BFAAKAwAAAA==.Chevaiermort:BAAANQADCgcIBwAAAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCggIEgAAAA==.',
Co='Coinlock:BAAANQAECgQICgAAAA==.Coldtouch:BAAANQADCgcIBwAAAA==.Confettii:BAAANQABCgQIBgABNQAECggIFAAOAAkLAA==.',
Ct='Ctrlaltshot:BAAANQAECgIIAgAAAA==.',
Cu='Cutedeath:BAAANQADCgUIBwAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAAANQAECggIDwAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECn8lAAMDAAoKuxHmggAUAgADAAoKuxHmggAUAgAPAAEKRAdGNgAtAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECggIEgANAAAAAA==.Dawny:BAABNQAECn8lAAMRAAoKkg2JawDJAQARAAoKkg2JawDJAQASAAIKCgxgDQFxAAAAAA==.Daywalkers:BAABNQAECn8UAAIOAAUKiBAJ4ABBAQAOAAUKiBAJ4ABBAQABNQAECggIEgANAAAAAA==.',
De='Dethndk:BAABNQAECn8ZAAIIAAoKABk5KgBzAgAIAAoKABk5KgBzAgAAAA==.',
Di='Die:BAABNQAECn8iAAITAAoK8xJxBwBAAgATAAoK8xJxBwBAAgAAAA==.',
Do='Doorjob:BAABNQAECn8aAAMUAAkKJB8nIQCSAgAUAAkKJB8nIQCSAgAHAAQK8A67IAC/AAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQACABsVAA==.',
Dr='Dragonslaye:BAAANQADCgQIBAAAAA==.Dreadravens:BAAANQAECgYIBgAAAA==.Dreamily:BAABNQAECn8lAAIKAAoKTBHCOgAdAgAKAAoKTBHCOgAdAgAAAA==.Dreamtalker:BAAANQABCggIEQAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ei='Eiliminteach:BAAANQAECgcIDQAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAABNQAECn8jAAIVAAgKihAnPwCaAQAVAAgKihAnPwCaAQAAAA==.Elfredo:BAAANQAECgQIBAAAAA==.Elia:BAABNQAECn8oAAIOAAoKEB43MwDSAgAOAAoKEB43MwDSAgAAAA==.Eligor:BAABNQAECn8cAAIBAAcK4gbjgwDsAAABAAcK4gbjgwDsAAAAAA==.Elisandre:BAAANQAECgcIBgAAAA==.Elmo:BAABNQAECn8cAAIIAAoKXxZwLwBVAgAIAAoKXxZwLwBVAgAAAA==.Elurrmental:BAABNQAECn8XAAMWAAgKIg27EQBqAQAWAAgKnQy7EQBqAQASAAYKvwrgmQBkAQAAAA==.Elzä:BAAANQAECgYIDQAAAA==.',
Em='Emergencii:BAAANQABCgMIBQABNQAECggIFAAOAAkLAA==.Emp:BAAANQAECgQIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECn8sAAIUAAoKmBzHHQCsAgAUAAoKmBzHHQCsAgAAAA==.Entropius:BAABNQAECn8iAAIXAAgKQQ0sNADyAAAXAAgKQQ0sNADyAAAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Es='Esoteric:BAAANQAECggIDwAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECggIFAAOAAkLAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECn8iAAIYAAoK1Q0jpQDWAQAYAAoK1Q0jpQDWAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feorial:BAAANQAECgQIBwAAAA==.Feralkitty:BAAANQAECggIEwAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECn8iAAISAAoKBg9/YQD9AQASAAoKBg9/YQD9AQAAAA==.Foregotten:BAACNQAFFH8IAAIKAAIKkhKcEACaAAAKAAIKkhKcEACaAAA1AAQKfykAAgoACgoEFuAqAIICAAoACgoEFuAqAIICAAAA.',
Fr='Frostietute:BAABNQAECn8gAAIEAAgKnRx8YwCEAQAEAAgKnRx8YwCEAQAAAA==.',
Fu='Furysmight:BAABNQAECn8mAAIDAAoKSiHwFwCpAgADAAoKSiHwFwCpAgAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAQIDgAZAJYhAA==.Galorw:BAAANQABCgIIAgAAAA==.Gamboa:BAAANQAECgcIDgAAAA==.Gastly:BAAANQAECgEIAQABNQAECgYIEQANAAAAAA==.Gauche:BAABNQAECn8qAAMaAAoKyxuIGAD2AQAaAAgKIBuIGAD2AQALAAgK+hucEADcAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAABNQAECn8WAAIEAAcK+BBz6gC1AQAEAAcK+BBz6gC1AQAAAA==.Gravel:BAAANQADCggICQAAAA==.Grazka:BAAANQAECgIIAgAAAA==.Grÿmm:BAABNQAECn8lAAIQAAgKxgyxDwAwAQAQAAgKxgyxDwAwAQAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgABNQAECgEIAQANAAAAAA==.Guldanica:BAAANQAECgQIBQAAAA==.Gunn:BAAANQAECgEIAQAAAA==.',
Gw='Gwaine:BAABNQAECn8VAAIbAAYKUAXtGQDDAAAbAAYKUAXtGQDDAAAAAA==.Gwin:BAAANQAECggIEgAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECggICwANAAAAAA==.Hartland:BAAANQAECgEIAQAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyl:BAAANQAECgEIAQAAAA==.Heritikyldin:BAAANQAECggICwAAAA==.Heritikylust:BAABNQAECn8mAAISAAoKlBrXMQCzAgASAAoKlBrXMQCzAgAAAA==.',
Hi='Hibou:BAAANQAECgEIAQAAAA==.',
Ho='Holyhero:BAABNQAECn8kAAIcAAgKUxawIAAzAgAcAAgKUxawIAAzAgAAAA==.',
Il='Ilectra:BAABNQAECn8zAAIdAAoKURh7DQAVAgAdAAoKURh7DQAVAgAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQAECggIFAAOAAkLAA==.Intensitii:BAAANQABCgQICQABNQAECggIFAAOAAkLAA==.',
Ip='Ipoopied:BAAANQAECgEIAQAAAA==.',
Is='Ishmara:BAAANQAECgUICwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCggIDgAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECn9HAAMBAAoKlRpDJwAYAgABAAoKSxpDJwAYAgAeAAQKAg85HgCJAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Keishara:BAAANQADCggIFwAAAA==.Kentiger:BAAANQABCggICwAAAA==.Kepec:BAAANQAECgIIAgAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Ko='Korosh:BAAANQAECgIIAgAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgUIDgANAAAAAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgUIDgANAAAAAA==.Krimzonstorm:BAAANQAECgUIDgAAAA==.',
Ku='Kunaee:BAAANQAECgUICwAAAA==.',
Ky='Kyrius:BAABNQAECn8iAAMRAAoKRSBJFwCKAgARAAoKRSBJFwCKAgASAAEKXwLPzgApAAAAAA==.',
['Kì']='Kìku:BAABNQAECn8rAAIBAAgKTBQyRwCQAQABAAgKTBQyRwCQAQAAAA==.',
La='Labgrown:BAAANQAECgUIBwAAAA==.Lausia:BAABNQAECn8rAAMfAAgKhRYgDQDhAQAfAAgKIBUgDQDhAQAEAAIK3Q7QpgF0AAABNQAECgoKMwAdAFEYAA==.',
Ld='Ldyrose:BAAANQAECgMICAAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAABNQAECn8YAAIOAAgKKA1RZwBsAQAOAAgKKA1RZwBsAQAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEQANAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggICAABNQADCggIHwANAAAAAA==.',
Ma='Macabre:BAABNQAECn8UAAIIAAcKSgzmewAJAQAIAAcKSgzmewAJAQAAAA==.Magnificò:BAABNQAECn8rAAIIAAgKSRtyGwC4AQAIAAgKSRtyGwC4AQAAAA==.Makani:BAABNQAECn8aAAIGAAcKBg99KgBEAQAGAAcKBg99KgBEAQAAAA==.Malarix:BAAANQADCgUIBQABNQADCgYIBgANAAAAAA==.Malory:BAABNQAECn8cAAIbAAkKYiEKBQArAwAbAAkKYiEKBQArAwABNQAFFAQIDgAZAJYhAA==.Malzahär:BAABNQAECn8bAAQgAAkKzSC3HACIAQABAAcKUCFKVwBQAgAgAAUKpRy3HACIAQAeAAMK2hxGFwDWAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQADCgQIBAAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECggICwAAAA==.Muffintop:BAABNQAECn8nAAMhAAgK8hzkMQAaAgAhAAgKbBzkMQAaAgAXAAYKAB/ySwDlAQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQAECgYIBwAAAA==.Mythrondrir:BAABNQAECn8uAAIhAAoK0hfLFAAxAgAhAAoK0hfLFAAxAgAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQADCggICAABNQADCggIHwANAAAAAA==.',
Ne='Neosnÿper:BAABNQAECn8uAAMJAAkK0BerHQBDAgAJAAgKCBirHQBDAgAKAAkKXxTnHwCHAQABNQAFFAUICQABANYRAA==.',
Ni='Nielic:BAABNQAECn8rAAQMAAoKVBq6IwDeAgAMAAoKVBq6IwDeAgAiAAQKewoBGwCQAAAcAAEKAAA+WQAAAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAcIGwASADwXAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Nobops:BAAANQADCggIEQAAAA==.Norrahh:BAAANQAECgUIBwAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Ny='Nyru:BAAANQAECgIIAQABNQAECgYIBgANAAAAAA==.',
Om='Omgitsmagic:BAAANQAECgUIBgAAAA==.',
On='Ongo:BAABNQAECn8wAAIEAAoKhw0PTADMAQAEAAoKhw0PTADMAQAAAA==.',
Or='Orion:BAABNQAECn8fAAIfAAgKKwt1EACfAQAfAAgKKwt1EACfAQAAAA==.',
Pa='Palapoxi:BAABNQAECn8oAAIVAAoKkyDOEgA6AwAVAAoKkyDOEgA6AwAAAA==.',
Pe='Penelopè:BAABNQAECn8oAAIjAAoKbSREAgCJAwAjAAoKbSREAgCJAwABNQAECgoKJQAIAMEfAA==.Penelópe:BAAANQADCgEIAQABNQAECgoKJQAIAMEfAA==.Penný:BAAANQAECgMIBQABNQAECgoKJQAIAMEfAA==.Pepino:BAABNQAECn8fAAIOAAcKtBJJcQBUAQAOAAcKtBJJcQBUAQAAAA==.',
Pf='Pflanlock:BAAANQADCgcICwAAAA==.',
Ph='Phinx:BAABNQAECn8dAAIXAAoKThbyPwAeAgAXAAoKThbyPwAeAgAAAA==.Phocheux:BAABNQAECn8zAAIWAAoKAB1aBQCPAgAWAAoKAB1aBQCPAgAAAA==.Phulgoth:BAAANQAECgYIEQAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Piligo:BAAANQABCggICgAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgMIAwAAAA==.',
Po='Poco:BAAANQAECggICAAAAA==.Poetrii:BAABNQAECn8UAAIOAAgKCQs/agBlAQAOAAgKCQs/agBlAQAAAA==.Pomickyal:BAABNQAECn8rAAIBAAgKkQfccQAXAQABAAgKkQfccQAXAQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Pr='Prey:BAAANQAECggIBwAAAA==.',
Ps='Pshamanthe:BAAANQAECgUIBQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQAECgEIAwAAAA==.Ragnärok:BAABNQAECn8YAAIRAAoKyBODWwD9AQARAAoKyBODWwD9AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFH8lAAIIAAcKlRqfBABpAQAIAAcKlRqfBABpAQA1AAQKfzsAAggACgq2IR0MAFEDAAgACgq2IR0MAFEDAAAA.Reverii:BAAANQABCgYICAABNQAECggIFAAOAAkLAA==.Rez:BAAANQADCgUIBQAAAA==.Rezelda:BAAANQAECgQIAwAAAA==.',
Ri='Rinahfire:BAAANQAECgQIBAAAAA==.',
Rj='Rj:BAABNQAECn8UAAMXAAYKeBBzaABvAQAXAAYKeBBzaABvAQAIAAEKAACxwgBDAAAAAA==.',
Ro='Rocky:BAAANQAECgQICAABNQAECgoKLQALAHQTAA==.Roughbbq:BAAANQADCgEIAQABNQAECgYIEQANAAAAAA==.Roxi:BAAANQAECgQIBwAAAA==.',
Rt='Rtpopham:BAAANQAECggIDgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAABNQAECn8XAAIeAAYK3xLgDACPAQAeAAYK3xLgDACPAQAAAA==.Samusaran:BAAANQADCgQIBwAAAA==.Sandros:BAAANQAECgEIAQAAAA==.Saphrin:BAABNQAECn8lAAIUAAkKTQ+VHwCaAQAUAAkKTQ+VHwCaAQAAAA==.Sardiirn:BAAANQAECgMIBgABNQAECggIEgANAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAABNQAECn8pAAIEAAcK+RLDpQD7AAAEAAcK+RLDpQD7AAAAAA==.',
Se='Selynne:BAABNQAECn8nAAIYAAoKoh/1SQC3AgAYAAoKoh/1SQC3AgAAAA==.',
Sh='Shamanizeds:BAAANQAECggIEgAAAA==.Shamwisegamg:BAAANQADCgYICgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQAECgMIBQAAAA==.Shifted:BAABNQAECn8iAAIGAAoKrgwYHwCmAQAGAAoKrgwYHwCmAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.Shé:BAAANQAECgUIDQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQAECgQIBQAAAA==.Sixligma:BAABNQAECn8UAAQVAAYKBQlUqwAqAQAVAAYKBQlUqwAqAQAYAAIKrARyigFLAAACAAEKpAIeggAaAAAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAFFAIICAAKAJISAA==.',
Sl='Slorrin:BAABNQAECn8mAAIDAAoKMyTQDwCAAwADAAoKMyTQDwCAAwAAAA==.',
So='Solazreiale:BAAANQAECgUICwAAAA==.Somers:BAAANQADCggIHwAAAA==.Soulistic:BAAANQABCggIIgAAAA==.',
Sp='Spellbind:BAABNQAECn8bAAMfAAcK1h2+KgCkAAAEAAUKWR2b+wCWAQAfAAMK5B2+KgCkAAAAAA==.',
St='Starstorms:BAABNQAECn8rAAIJAAgK5hkrEQATAgAJAAgK5hkrEQATAgAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQAECgYICwAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgABNQAECgMIAwANAAAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAABNQAECn8aAAIWAAcKIgYwGQABAQAWAAcKIgYwGQABAQAAAA==.Taiez:BAABNQAECn8jAAMgAAcKBQuFHwBzAQAgAAcKBQuFHwBzAQAeAAEKlgfnLwA2AAAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQIBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQADCgQIBQAAAA==.Therapii:BAAANQABCgQIBQABNQAECggIFAAOAAkLAA==.Thesledge:BAABNQAECn85AAIYAAoKpxqqLQBGAgAYAAoKpxqqLQBGAgAAAA==.',
Ti='Tifalockhàrt:BAACNQAFFH8IAAIVAAIKygRdFwBuAAAVAAIKygRdFwBuAAA1AAQKfyoAAhUACgoVBoiDAJABABUACgoVBoiDAJABAAAA.Timewarped:BAABNQAECn8tAAIEAAgKUhMiVQCtAQAEAAgKUhMiVQCtAQAAAA==.',
To='Totemshat:BAAANQAECgUICQAAAA==.',
Tr='Trapsin:BAACNQAFFH8IAAIEAAIKgRUTJQCeAAAEAAIKgRUTJQCeAAA1AAQKfysAAgQACgoSINk4ABYDAAQACgoSINk4ABYDAAAA.Treeage:BAABNQAECn8jAAQQAAkKsRFEDgAyAgAQAAkKsRFEDgAyAgAKAAIKSQTAqgBBAAAGAAEKtgQMZAAsAAAAAA==.Trufflé:BAABNQAECn8rAAISAAgKXRhBOgBsAQASAAgKXRhBOgBsAQAAAA==.Trustportal:BAAANQAECgcICwABNQAECggIHQACAMAYAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECn8qAAIhAAoK0x44GwCxAgAhAAoK0x44GwCxAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgUICAABNQAECgoKMwAdAFEYAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valstan:BAAANQAECgcIEwAAAA==.Valzyn:BAABNQAECn8UAAILAAoK6gvCLQCrAQALAAoK6gvCLQCrAQAAAA==.Varitek:BAAANQAECgQIBAAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECn8oAAMcAAoKOBPyJQD/AQAcAAkKPRTyJQD/AQAMAAYKkBDTkwBbAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgoKKAAVAJMgAA==.Warisfluffy:BAABNQAECn8YAAIUAAcKkQwbTABwAQAUAAcKkQwbTABwAQAAAA==.',
We='Wedaddams:BAAANQAECggIDgAAAA==.Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEIAQAAAA==.',
Wo='Worldboss:BAABNQAECn8hAAICAAgKJxRwFgBQAQACAAgKJxRwFgBQAQAAAA==.Worldwar:BAABNQAECn8UAAMDAAYKOww3igD8AAADAAYKOww3igD8AAAPAAEKQARXOwAcAAAAAA==.',
Wr='Wradalin:BAABNQAECn8dAAIhAAkKZx3oJgBfAgAhAAkKZx3oJgBfAgAAAA==.Wraithstorm:BAABNQAECn8WAAMGAAgKWxvLEQCUAQAGAAcKxxzLEQCUAQAKAAEKPxR+aAA8AAAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zarila:BAAANQAECgUICgAAAA==.Zartain:BAABNQAECn8rAAIkAAgKyw9eEQB3AQAkAAgKyw9eEQB3AQAAAA==.',
Ze='Zelarus:BAAANQAECggICAAAAA==.Zenizho:BAAANQAECgIIAwAAAA==.Zennamite:BAABNQAECn8nAAISAAgKDhKNQwBGAQASAAgKDhKNQwBGAQAAAA==.',
Zi='Zipzaps:BAAANQAECgMIBAAAAA==.',
Zu='Zuldarack:BAAANQAECgIIAQAAAA==.',
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
