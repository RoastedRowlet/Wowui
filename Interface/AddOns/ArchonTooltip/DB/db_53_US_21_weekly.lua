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

local lookup = {'Paladin-Protection','Warrior-Arms','Mage-Arcane','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Monk-Windwalker','Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Warrior-Fury','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Paladin-Retribution','Evoker-Augmentation','Monk-Mistweaver','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warrior-Protection','Warlock-Destruction','DeathKnight-Frost','Priest-Discipline','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-10-20',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICwAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAAANQAECgcIEgAAAA==.',
Ak='Akroma:BAABNQAECn8WAAIBAAcKzhpeGQAqAgABAAcKzhpeGQAqAgAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECn81AAICAAkK2x4tHwCHAQACAAkK2x4tHwCHAQAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Angerlia:BAAANQAECgIIAgAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgMIAwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECn8rAAIDAAoKMwbmbQDgAAADAAoKMwbmbQDgAAAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECn8VAAIDAAkKTSBtawCnAgADAAkKTSBtawCnAgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgoKHAACADUgAA==.Arykami:BAAANQAECgQIBgABNQAECgkJHgAEAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgAEAFceAA==.Arystrasza:BAABNQAECn8eAAIEAAkKVx5iCQANAwAEAAkKVx5iCQANAwAAAA==.Aryzhuque:BAAANQAECgYIDAABNQAECgkJHgAEAFceAA==.',
As='Ashmandious:BAAANQAECggIEAAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECn8oAAIFAAoKniQJAQDiAwAFAAoKniQJAQDiAwAAAA==.',
At='Athleta:BAEBNQAFFH8RAAIGAAcKnBAhAACqAQAGAAcKnBAhAACqAQABNQAFFAkJNAAHAN4gAA==.',
Av='Average:BAAANQADCgYIDwAAAA==.',
Ay='Ayana:BAAANQAECgEIAQAAAA==.',
Ba='Bajablastois:BAAANQAECgUIDAABNQAECgoKOQAHAE4gAA==.Balkaj:BAAANQADCgEIAQAAAA==.Balrog:BAAANQADCgYIBgAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAABNQAECn8iAAMIAAgKFhe+NwBfAQAIAAYKkRO+NwBfAQAJAAQKmgYBOgByAAAAAA==.',
Be='Beefajitas:BAAANQAECgEIAQAAAA==.Beerhelmet:BAABNQAECn8mAAIKAAoKmRFjDwA2AQAKAAoKmRFjDwA2AQAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAABNQAECn8ZAAILAAgKdhOZGwCcAQALAAgKdhOZGwCcAQAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgAMAAAAAA==.Birdstrike:BAAANQAECgYIBgAAAA==.',
Bl='Bleddyn:BAAANQADCgIIAgAAAA==.Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECn8jAAINAAkK3BqZQgCjAgANAAkK3BqZQgCjAgAAAA==.Bowser:BAABNQAECn8cAAMCAAgKTAsOUAD9AAACAAgKTAsOUAD9AAAOAAEKJwuuFgA8AAAAAA==.',
Br='Braleanna:BAAANQAECgUICgAAAA==.Brigeta:BAAANQAECggIDwAAAA==.',
Bu='Budlofsky:BAAANQAECgMIAwAAAA==.Bugge:BAAANQAECgYIEwAAAA==.Bus:BAABNQAECn8XAAIFAAoKTCbXAADqAwAFAAoKTCbXAADqAwABNQAFFAgIFwAHABQiAA==.',
Ca='Calinalia:BAAANQADCgcIBwAAAA==.',
Cb='Cbat:BAAANQAECgcIDQAAAA==.',
Cd='Cdicepalta:BAABNQAECn8uAAQJAAoK/gxtGgAQAQAFAAcKiwkXMQAVAQAJAAoKyAttGgAQAQAPAAQK6AnCLACsAAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUICwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECn8lAAIHAAoKwR9BFAAKAwAHAAoKwR9BFAAKAwAAAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCggIEgAAAA==.',
Co='Coinlock:BAAANQAECgUICgAAAA==.Coldtouch:BAAANQADCgcIBwAAAA==.Confettii:BAAANQABCgQIBgABNQAECgcICQAMAAAAAA==.',
Ct='Ctrlaltshot:BAAANQAECgIIAgAAAA==.',
Cu='Cutedeath:BAAANQADCgUIBwAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAAANQAECgYIDgAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECn8kAAMCAAkKVhLmggAUAgACAAkKVhLmggAUAgAOAAEKRAdGNgAtAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECggIEgAMAAAAAA==.Dawny:BAABNQAECn8lAAMQAAoKkg2JawDJAQAQAAoKkg2JawDJAQARAAIKCgxgDQFxAAAAAA==.Daywalkers:BAABNQAECn8UAAINAAUKiBAJ4ABBAQANAAUKiBAJ4ABBAQABNQAECggIEgAMAAAAAA==.',
De='Dethndk:BAABNQAECn8YAAIHAAkK1Bo5KgBzAgAHAAkK1Bo5KgBzAgAAAA==.',
Di='Die:BAABNQAECn8iAAISAAoK8xJxBwBAAgASAAoK8xJxBwBAAgAAAA==.',
Do='Doorjob:BAABNQAECn8aAAMTAAkKJB8nIQCSAgATAAkKJB8nIQCSAgAGAAQK8A67IAC/AAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQABABsVAA==.',
Dr='Dreadravens:BAAANQAECgYIBgAAAA==.Dreamily:BAABNQAECn8lAAIJAAoKTBHCOgAdAgAJAAoKTBHCOgAdAgAAAA==.Dreamtalker:BAAANQABCggIEQAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ei='Eiliminteach:BAAANQAECgYIBwAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAABNQAECn8cAAIUAAcK5w1fLgApAQAUAAcK5w1fLgApAQAAAA==.Elia:BAABNQAECn8nAAINAAoKCR43MwDSAgANAAoKCR43MwDSAgAAAA==.Eligor:BAAANQAECgQIEwAAAA==.Elisandre:BAAANQADCgYIBgAAAA==.Elmo:BAABNQAECn8bAAIHAAkKrBdwLwBVAgAHAAkKrBdwLwBVAgAAAA==.Elurrmental:BAAANQAECgUIDQAAAA==.Elzä:BAAANQAECgcIDAAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBQABNQAECgcICQAMAAAAAA==.Emp:BAAANQAECgIIAgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECn8sAAITAAoKehzHHQCsAgATAAoKehzHHQCsAgAAAA==.Entropius:BAABNQAECn8aAAIVAAYKeBBvdwA7AQAVAAYKeBBvdwA7AQAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Es='Esoteric:BAAANQAECgcIBwAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECgcICQAMAAAAAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECn8iAAIWAAoK1Q0jpQDWAQAWAAoK1Q0jpQDWAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feorial:BAAANQAECgUIAwAAAA==.Feralkitty:BAAANQAECggIEAAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECn8iAAIRAAoKBg9/YQD9AQARAAoKBg9/YQD9AQAAAA==.Foregotten:BAACNQAFFH8GAAIJAAIKCAwNDACWAAAJAAIKCAwNDACWAAA1AAQKfyYAAgkACgoEFuAqAIICAAkACgoEFuAqAIICAAAA.',
Fr='Frostietute:BAABNQAECn8YAAIDAAYKzhwavAAMAgADAAYKzhwavAAMAgABNQAECgoKMgADAJseAA==.',
Fu='Furysmight:BAABNQAECn8cAAICAAoKNSD+JAAlAwACAAoKNSD+JAAlAwAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAQIDgAXAJYhAA==.Galorw:BAAANQABCgIIAgAAAA==.Gamboa:BAAANQAECgUICAAAAA==.Gastly:BAAANQAECgEIAQABNQAECgYIEQAMAAAAAA==.Gauche:BAABNQAECn8gAAMYAAkKfxyIGAD2AQAYAAcKZhyIGAD2AQAKAAgKBxggBQDBAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAABNQAECn8WAAIDAAcK+BBz6gC1AQADAAcK+BBz6gC1AQAAAA==.Gravel:BAAANQADCggICQAAAA==.Grazka:BAAANQAECgIIAgAAAA==.Grÿmm:BAABNQAECn8cAAIPAAcKPQydCQAKAQAPAAcKPQydCQAKAQAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgABNQAECgEIAQAMAAAAAA==.Guldanica:BAAANQAECgQIBQAAAA==.Gunn:BAAANQAECgEIAQAAAA==.',
Gw='Gwaine:BAAANQAECgYIEQAAAA==.Gwin:BAAANQAECggIEgAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgcICwAMAAAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyl:BAAANQABCgIIAgAAAA==.Heritikyldin:BAAANQAECgYICAAAAA==.Heritikylust:BAABNQAECn8jAAIRAAoKwhnXMQCzAgARAAoKwhnXMQCzAgAAAA==.',
Hi='Hibou:BAAANQAECgEIAQAAAA==.',
Ho='Holyhero:BAABNQAECn8kAAIZAAgKUxawIAAzAgAZAAgKUxawIAAzAgAAAA==.',
Il='Ilectra:BAABNQAECn8vAAIaAAgKMxckCACNAQAaAAgKMxckCACNAQAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQAECgcICQAMAAAAAA==.Intensitii:BAAANQABCgQICQABNQAECgcICQAMAAAAAA==.',
Ip='Ipoopied:BAAANQAECgEIAQAAAA==.',
Is='Ishmara:BAAANQAECgUICwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCggIDgAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECn85AAMbAAoKxRgCSAB7AgAbAAoKxRgCSAB7AgAcAAMKSgk5HgCJAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Keishara:BAAANQADCggIFwAAAA==.Kepec:BAAANQADCgYJDQABNQAECgYICgAMAAAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Ko='Korosh:BAAANQADCgUIBQAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgUICQAMAAAAAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgUICQAMAAAAAA==.Krimzonstorm:BAAANQAECgUICQAAAA==.',
Ku='Kunaee:BAAANQAECgUICwAAAA==.',
Ky='Kyrius:BAABNQAECn8bAAMQAAgKyyLSIADmAgAQAAgKyyLSIADmAgARAAEKXwIomwAqAAAAAA==.',
['Kì']='Kìku:BAABNQAECn8jAAIbAAgK7RFiGwCDAQAbAAgK7RFiGwCDAQAAAA==.',
La='Labgrown:BAAANQAECgUIBQAAAA==.Lausia:BAABNQAECn8jAAMdAAgKhRZVBABtAQAdAAgKIBVVBABtAQADAAIK3Q7QpgF0AAABNQAECggILwAaADMXAA==.',
Ld='Ldyrose:BAAANQAECgMIBQAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAAANQAECgYIDwAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEQAMAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggICAABNQADCggIHwAMAAAAAA==.',
Ma='Macabre:BAAANQAECgYIEgAAAA==.Magnificò:BAABNQAECn8jAAIHAAgKQhgpCgCdAQAHAAgKQhgpCgCdAQAAAA==.Makani:BAABNQAECn8aAAIFAAcKBg99KgBEAQAFAAcKBg99KgBEAQAAAA==.Malarix:BAAANQADCgUIBQABNQADCgYIBgAMAAAAAA==.Malory:BAABNQAECn8cAAIeAAkKYiEKBQArAwAeAAkKYiEKBQArAwABNQAFFAQIDgAXAJYhAA==.Malzahär:BAABNQAECn8aAAQfAAkKzSC3HACIAQAbAAcKUCFKVwBQAgAfAAUKpRy3HACIAQAcAAMK2hxGFwDWAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQADCgQIBAAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgcICwAAAA==.Muffintop:BAABNQAECn8fAAMgAAcKvR7kMQAaAgAgAAcKHR7kMQAaAgAVAAYKAB/ySwDlAQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQAECgEIAQAAAA==.Mythrondrir:BAABNQAECn8mAAIgAAoK0BZPCQDEAQAgAAoK0BZPCQDEAQAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQADCggICAABNQADCggIHwAMAAAAAA==.',
Ne='Neosnÿper:BAABNQAECn8pAAMIAAkKyRerHQBDAgAIAAgKABirHQBDAgAJAAkKZhKqFAA2AQABNQAFFAMIBwAbAO8SAA==.',
Ni='Nielic:BAABNQAECn8kAAQLAAoKgxi6IwDeAgALAAoKgxi6IwDeAgAhAAQKewoBGwCQAAAZAAEKAABtPwAAAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAcIGgARADwXAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Nobops:BAAANQADCggIEAAAAA==.Norrahh:BAAANQAECgUIBwAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Ny='Nyru:BAAANQAECgEIAQABNQAECgYIBgAMAAAAAA==.',
Om='Omgitsmagic:BAAANQAECgQIBAAAAA==.',
On='Ongo:BAABNQAECn8qAAIDAAkKRgzpGgCjAQADAAkKRgzpGgCjAQAAAA==.',
Or='Orion:BAABNQAECn8eAAIdAAgKKwt1EACfAQAdAAgKKwt1EACfAQAAAA==.',
Pa='Palapoxi:BAABNQAECn8oAAIUAAoKkyDOEgA6AwAUAAoKkyDOEgA6AwAAAA==.',
Pe='Penelopè:BAABNQAECn8oAAIiAAoKbSREAgCJAwAiAAoKbSREAgCJAwABNQAECgoKJQAHAMEfAA==.Penelópe:BAAANQADCgEIAQABNQAECgoKJQAHAMEfAA==.Penný:BAAANQAECgMIBAABNQAECgoKJQAHAMEfAA==.Pepino:BAAANQAECgQIEwAAAA==.',
Pf='Pflanlock:BAAANQADCgcIBwAAAA==.',
Ph='Phinx:BAABNQAECn8dAAIVAAoKThbyPwAeAgAVAAoKThbyPwAeAgAAAA==.Phocheux:BAABNQAECn8pAAIjAAkKwRwDAwD4AQAjAAkKwRwDAwD4AQAAAA==.Phulgoth:BAAANQAECgYIDAAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgMIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQAECgcICQAAAA==.Pomickyal:BAABNQAECn8jAAIbAAgKPAe6OQAeAQAbAAgKPAe6OQAeAQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQAECgUIBQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQAECgEIAgAAAA==.Ragnärok:BAABNQAECn8XAAIQAAkKPRWDWwD9AQAQAAkKPRWDWwD9AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFH8eAAIHAAYK3xtcCgCyAQAHAAYK3xtcCgCyAQA1AAQKfzEAAgcACgqmHh0MAFEDAAcACgqmHh0MAFEDAAAA.Reverii:BAAANQABCgYICAABNQAECgcICQAMAAAAAA==.Rezelda:BAAANQAECgQIAwAAAA==.',
Rj='Rj:BAABNQAECn8UAAMVAAYKeBBzaABvAQAVAAYKeBBzaABvAQAHAAEKAACxwgBDAAAAAA==.',
Ro='Rocky:BAAANQAECgQIBAABNQAECgoKJgAKAJkRAA==.Roughbbq:BAAANQADCgEIAQABNQAECgYIEQAMAAAAAA==.Roxi:BAAANQAECgMIBAAAAA==.',
Rt='Rtpopham:BAAANQAECgQIBgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAABNQAECn8XAAIcAAYK3xLgDACPAQAcAAYK3xLgDACPAQAAAA==.Samusaran:BAAANQADCgQIBQAAAA==.Sandros:BAAANQAECgEIAQAAAA==.Saphrin:BAABNQAECn8dAAITAAcKxw0QGQApAQATAAcKxw0QGQApAQAAAA==.Sardiirn:BAAANQAECgMIBgABNQAECggIEgAMAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAABNQAECn8kAAIDAAcK7BHWWQAJAQADAAcK7BHWWQAJAQAAAA==.',
Se='Selynne:BAABNQAECn8lAAIWAAoKoh/1SQC3AgAWAAoKoh/1SQC3AgAAAA==.',
Sh='Shamanizeds:BAAANQAECggIEgAAAA==.Shamwisegamg:BAAANQADCgYICgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQAECgMIAgAAAA==.Shifted:BAABNQAECn8iAAIFAAoKrgwYHwCmAQAFAAoKrgwYHwCmAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.Shé:BAAANQAECgUICQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQAECgIIAgAAAA==.Sixligma:BAAANQAECgYIEwAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAFFAIIBgAJAAgMAA==.',
Sl='Slorrin:BAABNQAECn8mAAICAAoKMyTQDwCAAwACAAoKMyTQDwCAAwAAAA==.',
So='Solazreiale:BAAANQAECgUICwAAAA==.Somers:BAAANQADCggIHwAAAA==.Soulistic:BAAANQABCggIHwAAAA==.',
Sp='Spellbind:BAABNQAECn8WAAMdAAcKZx0ODgCqAAADAAUKAx2b+wCWAQAdAAMKgB0ODgCqAAAAAA==.',
St='Starstorms:BAABNQAECn8jAAIIAAgKmxc2CQCkAQAIAAgKmxc2CQCkAQAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQAECgYICgAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgABNQADCgYIBgAMAAAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgQIEQAAAA==.Taiez:BAABNQAECn8dAAMfAAcK5wqFHwBzAQAfAAcK5wqFHwBzAQAcAAEKlgfnLwA2AAAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQJBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQADCgIIAwAAAA==.Therapii:BAAANQABCgQIBQABNQAECgcICQAMAAAAAA==.Thesledge:BAABNQAECn8wAAIWAAoKWRlnFADZAQAWAAoKWRlnFADZAQAAAA==.',
Ti='Tifalockhàrt:BAACNQAFFH8GAAIUAAIKygTcDwBtAAAUAAIKygTcDwBtAAA1AAQKfycAAhQACgoVBoiDAJABABQACgoVBoiDAJABAAAA.Timewarped:BAABNQAECn8oAAIDAAgKFRPRPgA/AQADAAgKFRPRPgA/AQAAAA==.',
To='Totemshat:BAAANQAECgQIBAAAAA==.',
Tr='Trapsin:BAACNQAFFH8GAAIDAAIKgRX9GACcAAADAAIKgRX9GACcAAA1AAQKfygAAgMACgoSINk4ABYDAAMACgoSINk4ABYDAAAA.Treeage:BAABNQAECn8jAAQPAAkKsRFEDgAyAgAPAAkKsRFEDgAyAgAJAAIKSQTAqgBBAAAFAAEKtgQMZAAsAAAAAA==.Trufflé:BAABNQAECn8jAAIRAAcKvhldXgAHAgARAAcKvhldXgAHAgAAAA==.Trustportal:BAAANQAECgcIBwABNQAECgcIFgABAM4aAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECn8kAAIgAAoK0x44GwCxAgAgAAoK0x44GwCxAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgQIBwABNQAECggILwAaADMXAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valstan:BAAANQAECgUIDQAAAA==.Valzyn:BAAANQAECggIDwAAAA==.Varitek:BAAANQAECgQIBAAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECn8oAAMZAAoKOBPyJQD/AQAZAAkKPRTyJQD/AQALAAYKkBDTkwBbAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgoKKAAUAJMgAA==.Warisfluffy:BAABNQAECn8UAAITAAcKiAwbTABwAQATAAcKiAwbTABwAQAAAA==.',
We='Wedaddams:BAAANQAECggIDgAAAA==.Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEJAQAAAA==.',
Wo='Worldboss:BAABNQAECn8YAAIBAAcKJRTADQApAQABAAcKJRTADQApAQAAAA==.Worldwar:BAABNQAECn8UAAMCAAYKOwyERwARAQACAAYKOwyERwARAQAOAAEKQARXOwAcAAAAAA==.',
Wr='Wradalin:BAABNQAECn8dAAIgAAkKZx3oJgBfAgAgAAkKZx3oJgBfAgAAAA==.Wraithstorm:BAAANQAECgUIDQAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQAECgUICgAAAA==.Zartain:BAABNQAECn8jAAIkAAgKuQruDQBWAQAkAAgKuQruDQBWAQAAAA==.',
Ze='Zelarus:BAAANQAECgcICAAAAA==.Zenizho:BAAANQAECgIIAwAAAA==.Zennamite:BAABNQAECn8fAAIRAAgK6BFEFwBmAQARAAgK6BFEFwBmAQAAAA==.',
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
