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

local lookup = {'Warrior-Arms','Mage-Arcane','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Monk-Windwalker','Unknown-Unknown','Hunter-BeastMastery','Druid-Feral','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Protection','DeathKnight-Unholy','Paladin-Retribution','Evoker-Devastation','Monk-Mistweaver','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Warrior-Protection','Warlock-Destruction','DeathKnight-Frost','Priest-Holy','Priest-Discipline','Paladin-Holy','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICgAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAAANQAECgcIEQAAAA==.',
Ak='Akroma:BAAANQAECgYIEAAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECn8vAAIBAAgKECGXSQCqAgABAAgKECGXSQCqAgAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Angerlia:BAAANQAECgIIAgAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgMIAwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECn8kAAICAAgKcAWHAQGIAQACAAgKcAWHAQGIAQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECn8VAAICAAkKTSDEagCoAgACAAkKTSDEagCoAgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgkJGAABADAgAA==.Arykami:BAAANQAECgQIBgABNQAECgkJHgADAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgADAFceAA==.Arystrasza:BAABNQAECn8eAAIDAAkKVx4/CQAOAwADAAkKVx4/CQAOAwAAAA==.Aryzhuque:BAAANQAECgYIDAABNQAECgkJHgADAFceAA==.',
As='Ashmandious:BAAANQAECgcIDwAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECn8nAAIEAAkKeCYFAQDiAwAEAAkKeCYFAQDiAwAAAA==.',
At='Athleta:BAEBNQAFFH8KAAIFAAUKNxXhAQBKAQAFAAUKNxXhAQBKAQABNQAFFAkJLAAGAGgaAA==.',
Av='Average:BAAANQADCgYIDwAAAA==.',
Ba='Bajablastois:BAAANQAECgUIBwABNQAECgkJNQAGAJMhAA==.Balkaj:BAAANQADCgEIAQAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAABNQAECn8bAAMHAAcKwhUuNwBfAQAHAAYKkRMuNwBfAQAIAAEKkAdYrgA2AAAAAA==.',
Be='Beefajitas:BAAANQADCgUIEQAAAA==.Beerhelmet:BAABNQAECn8fAAIJAAkKQBH4JAD4AQAJAAkKQBH4JAD4AQAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAAANQAECgYIDwAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgAKAAAAAA==.',
Bl='Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECn8jAAILAAkK3BpIQQClAgALAAkK3BpIQQClAgAAAA==.Bowser:BAAANQAECgYIEAAAAA==.',
Br='Braleanna:BAAANQAECgQIBgAAAA==.Brigeta:BAAANQAECggIDwAAAA==.',
Bu='Budlofsky:BAAANQADCgUIBQAAAA==.Bugge:BAAANQAECgUIDgAAAA==.Bus:BAABNQAECn8UAAIEAAkKUibTAADqAwAEAAkKUibTAADqAwABNQAFFAcIFQAGABkhAA==.',
Ca='Calinalia:BAAANQADCgcIBwAAAA==.',
Cb='Cbat:BAAANQAECgYICgAAAA==.',
Cd='Cdicepalta:BAABNQAECn8nAAQIAAkKJQzRRwDIAQAIAAkKwwrRRwDIAQAEAAcKiwkqMAAVAQAMAAQK6AnOKwCuAAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUICwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECn8kAAIGAAkKWSDhEwALAwAGAAkKWSDhEwALAwAAAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCggIDgAAAA==.',
Co='Coinlock:BAAANQAECgUIBgAAAA==.Coldtouch:BAAANQADCgcIBwAAAA==.Confettii:BAAANQABCgQIBQABNQAECgQIBQAKAAAAAA==.',
Ct='Ctrlaltshot:BAAANQADCggICgAAAA==.',
Cu='Cutedeath:BAAANQADCgUIBwAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAAANQAECgYIDQAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECn8kAAMBAAkKVhJkgQAUAgABAAkKVhJkgQAUAgANAAEKRAeDNQAtAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECgcIEQAKAAAAAA==.Dawny:BAABNQAECn8kAAMOAAkK8A5bagDJAQAOAAkK8A5bagDJAQAPAAIKCgyUCQFxAAAAAA==.Daywalkers:BAAANQAECgQIEgABNQAECgcIEQAKAAAAAA==.',
De='Dethndk:BAABNQAECn8YAAIGAAkK1Bq7KQBzAgAGAAkK1Bq7KQBzAgAAAA==.',
Di='Die:BAABNQAECn8hAAIQAAkKNhVqBwA/AgAQAAkKNhVqBwA/AgAAAA==.',
Do='Doorjob:BAABNQAECn8aAAMRAAkKJB+5IACRAgARAAkKJB+5IACRAgAFAAQK8A5jIAC/AAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQASABsVAA==.',
Dr='Dreadravens:BAAANQAECgYIBgAAAA==.Dreamily:BAABNQAECn8kAAIIAAkK5BIcOgAdAgAIAAkK5BIcOgAdAgAAAA==.Dreamtalker:BAAANQABCggIEQAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ei='Eiliminteach:BAAANQAECgIIAgAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAAANQAECgYIEAAAAA==.Elia:BAABNQAECn8jAAILAAkKix4CMgDUAgALAAkKix4CMgDUAgAAAA==.Eligor:BAAANQAECgQIBwAAAA==.Elisandre:BAAANQADCgYIBgAAAA==.Elmo:BAABNQAECn8bAAIGAAkKrBfsLgBVAgAGAAkKrBfsLgBVAgAAAA==.Elurrmental:BAAANQAECgUICQAAAA==.Elzä:BAAANQAECgYICQAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBQABNQAECgQIBQAKAAAAAA==.Emp:BAAANQADCgYIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECn8oAAIRAAgKvh0xHQCsAgARAAgKvh0xHQCsAgAAAA==.Entropius:BAABNQAECn8aAAITAAYKeBBXdgA7AQATAAYKeBBXdgA7AQAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECgQIBQAKAAAAAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECn8hAAIUAAkKzA7CogDWAQAUAAkKzA7CogDWAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feorial:BAAANQAECgMIAwAAAA==.Feralkitty:BAAANQAECggIEAAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECn8hAAIPAAkKWw8gYAD9AQAPAAkKWw8gYAD9AQAAAA==.Foregotten:BAABNQAECn8jAAIIAAkKxRVmKgCCAgAIAAkKxRVmKgCCAgAAAA==.',
Fr='Frostietute:BAAANQAECgUIEQABNQAECgkJKAACALAdAA==.',
Fu='Furysmight:BAABNQAECn8YAAIBAAkKMCA7JAAlAwABAAkKMCA7JAAlAwAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAQICgAVAJYhAA==.Galorw:BAAANQABCgIIAgAAAA==.Gamboa:BAAANQAECgIIAwAAAA==.Gastly:BAAANQAECgEIAQABNQAECgYIEQAKAAAAAA==.Gauche:BAABNQAECn8XAAMWAAYKyB05GAD2AQAWAAYKyB05GAD2AQAJAAYK3BnqJwDdAQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAAANQAECgYIDwAAAA==.Gravel:BAAANQADCggICQAAAA==.Grazka:BAAANQAECgIIAgAAAA==.Grÿmm:BAAANQAECgYIEgAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgABNQAECgEIAQAKAAAAAA==.Guldanica:BAAANQAECgQIBAAAAA==.Gunn:BAAANQAECgEIAQAAAA==.',
Gw='Gwaine:BAAANQAECgUICwAAAA==.Gwin:BAAANQAECggIEgAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgQIBgAKAAAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyldin:BAAANQAECgYICAAAAA==.Heritikylust:BAABNQAECn8fAAIPAAkKWRknMQCzAgAPAAkKWRknMQCzAgAAAA==.',
Hi='Hibou:BAAANQAECgEIAQAAAA==.',
Ho='Holyhero:BAABNQAECn8kAAIXAAgKUxZTIAA0AgAXAAgKUxZTIAA0AgAAAA==.',
Il='Ilectra:BAABNQAECn8oAAIYAAgKMxcBIgA4AgAYAAgKMxcBIgA4AgAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQAECgQIBQAKAAAAAA==.Intensitii:BAAANQABCgQICQABNQAECgQIBQAKAAAAAA==.',
Ip='Ipoopied:BAAANQAECgEIAQAAAA==.',
Is='Ishmara:BAAANQAECgUICwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCggIDQAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECn8xAAMZAAkKNBmURgB8AgAZAAkK7hiURgB8AgAaAAMKSgnvHQCJAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Keishara:BAAANQADCgcIBwAAAA==.Kepec:BAAANQADCgYJDQAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgUICAAKAAAAAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgUICAAKAAAAAA==.Krimzonstorm:BAAANQAECgUICAAAAA==.',
Ku='Kunaee:BAAANQAECgQIBgAAAA==.',
Ky='Kyrius:BAABNQAECn8XAAIOAAgKAiBPIADmAgAOAAgKAiBPIADmAgAAAA==.',
['Kì']='Kìku:BAABNQAECn8bAAIZAAcKlxPQhQDTAQAZAAcKlxPQhQDTAQAAAA==.',
La='Labgrown:BAAANQAECgUIBQAAAA==.Lausia:BAABNQAECn8bAAMbAAcKeBf4DADiAQAbAAcKyxX4DADiAQACAAIK3Q7yogF0AAABNQAECggIKAAYADMXAA==.',
Ld='Ldyrose:BAAANQAECgIIAgAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAAANQAECgYIDwAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEQAKAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggJCAABNQADCggIHwAKAAAAAA==.',
Ma='Macabre:BAAANQAECgUIEgAAAA==.Magnificò:BAABNQAECn8bAAIGAAcKqhijPQAIAgAGAAcKqhijPQAIAgAAAA==.Makani:BAAANQAECgYIEAAAAA==.Malarix:BAAANQADCgUJBQABNQADCgYIBgAKAAAAAA==.Malory:BAABNQAECn8cAAIcAAkKYiHzBAAsAwAcAAkKYiHzBAAsAwABNQAFFAQICgAVAJYhAA==.Malzahär:BAABNQAECn8aAAQdAAkKzSCLHACIAQAZAAcKUCHCVQBRAgAdAAUKpRyLHACIAQAaAAMK2hwJFwDWAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQADCgQIBAAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgQIBgAAAA==.Muffintop:BAABNQAECn8bAAMeAAcKvR7QMAAbAgAeAAcKHR7QMAAbAgATAAYKAB8lSwDlAQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQAECgEIAQAAAA==.Mythrondrir:BAABNQAECn8fAAIeAAkKWBe3IQB8AgAeAAkKWBe3IQB8AgAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQADCggICAABNQADCggIHwAKAAAAAA==.',
Ne='Neosnÿper:BAABNQAECn8iAAMHAAkKQRZOHQBDAgAHAAgKRxZOHQBDAgAIAAgKvhJLOQAiAgAAAA==.',
Ni='Nielic:BAABNQAECn8fAAMfAAkK1hkQIwDfAgAfAAkK1hkQIwDfAgAgAAMKzQq9GgCQAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAcIFAAPADQXAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Nobops:BAAANQADCggICgAAAA==.Norrahh:BAAANQAECgIIAgAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Om='Omgitsmagic:BAAANQAECgQIBAAAAA==.',
On='Ongo:BAABNQAECn8iAAICAAgKEQzU2QDRAQACAAgKEQzU2QDRAQAAAA==.',
Or='Orion:BAAANQAECgcIEgAAAA==.',
Pa='Palapoxi:BAABNQAECn8nAAIhAAkKzCCPEgA6AwAhAAkKzCCPEgA6AwAAAA==.Pallybugge:BAAANQABCgEIAQAAAA==.',
Pe='Penelopè:BAABNQAECn8nAAIiAAkKoSQ6AgCKAwAiAAkKoSQ6AgCKAwABNQAECgkJJAAGAFkgAA==.Penelópe:BAAANQADCgEIAQABNQAECgkJJAAGAFkgAA==.Penný:BAAANQAECgMIBAABNQAECgkJJAAGAFkgAA==.Pepino:BAAANQAECgQIDwAAAA==.',
Ph='Phinx:BAABNQAECn8cAAITAAkKJxhQPwAeAgATAAkKJxhQPwAeAgAAAA==.Phocheux:BAABNQAECn8iAAIjAAgKexu2CwCyAgAjAAgKexu2CwCyAgAAAA==.Phulgoth:BAAANQAECgUICAAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgIIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQAECgQIBQAAAA==.Pomickyal:BAABNQAECn8bAAIZAAcKUwcEwABHAQAZAAcKUwcEwABHAQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQAECgUIBQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQAECgEIAQAAAA==.Ragnärok:BAABNQAECn8XAAIOAAkKPRV0WgD9AQAOAAkKPRV0WgD9AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFH8YAAIGAAYK3xsVCgCzAQAGAAYK3xsVCgCzAQA1AAQKfy0AAgYACQq3IvULAFEDAAYACQq3IvULAFEDAAAA.Reverii:BAAANQABCgYICAABNQAECgQIBQAKAAAAAA==.Rezelda:BAAANQAECgMIAwAAAA==.',
Rj='Rj:BAAANQAECgUIDgAAAA==.',
Ro='Roughbbq:BAAANQADCgEIAQABNQAECgYIEQAKAAAAAA==.Roxi:BAAANQAECgMIBAAAAA==.',
Rt='Rtpopham:BAAANQAECgQIBgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAABNQAECn8XAAIaAAYK3xLHDACPAQAaAAYK3xLHDACPAQAAAA==.Samusaran:BAAANQADCgQIBQAAAA==.Sandros:BAAANQAECgEIAQAAAA==.Saphrin:BAABNQAECn8XAAIRAAYK3g0ITQBlAQARAAYK3g0ITQBlAQAAAA==.Sardiirn:BAAANQAECgMIBgABNQAECgcIEQAKAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAABNQAECn8dAAICAAYKaRJh/QCPAQACAAYKaRJh/QCPAQAAAA==.',
Se='Selynne:BAABNQAECn8kAAIUAAkKyyBrSAC4AgAUAAkKyyBrSAC4AgAAAA==.',
Sh='Shamanizeds:BAAANQAECgcIEQAAAA==.Shamwisegamg:BAAANQADCgYICgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQAECgIIAgAAAA==.Shifted:BAABNQAECn8eAAIEAAgK2Q2JHgClAQAEAAgK2Q2JHgClAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.Shé:BAAANQAECgQIBAAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQADCgMIAwAAAA==.Sixligma:BAAANQAECgYIEwAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAECgkJIwAIAMUVAA==.',
Sl='Slorrin:BAABNQAECn8lAAIBAAkK5CRhDwCBAwABAAkK5CRhDwCBAwAAAA==.',
So='Solazreiale:BAAANQAECgQIBgAAAA==.Somers:BAAANQADCggIHwAAAA==.Soulistic:BAAANQABCggIHgAAAA==.',
Sp='Spellbind:BAAANQAECgYIDAAAAA==.',
St='Starstorms:BAABNQAECn8bAAIHAAcKdBkrJAAAAgAHAAcKdBkrJAAAAgAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQAECgYIBQAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgQIEAAAAA==.Taiez:BAABNQAECn8XAAMdAAcK5wpZHwBzAQAdAAcK5wpZHwBzAQAaAAEKlgdxLwA2AAAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQJBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQADCgIIAwAAAA==.Therapii:BAAANQABCgQIBQABNQAECgQIBQAKAAAAAA==.Thesledge:BAABNQAECn8mAAIUAAgKlRZDewAwAgAUAAgKlRZDewAwAgAAAA==.',
Ti='Tifalockhàrt:BAABNQAECn8kAAIhAAkKjAX9gQCRAQAhAAkKjAX9gQCRAQAAAA==.Timewarped:BAABNQAECn8iAAICAAgKxRJCtQAXAgACAAgKxRJCtQAXAgAAAA==.',
Tr='Trapsin:BAABNQAECn8lAAICAAkK1yAgOAAYAwACAAkK1yAgOAAYAwAAAA==.Treeage:BAABNQAECn8jAAQMAAkKsREPDgA0AgAMAAkKsREPDgA0AgAIAAIKSQTgqABBAAAEAAEKtgSRYQAsAAAAAA==.Trufflé:BAABNQAECn8bAAIPAAcKzxgaXQAHAgAPAAcKzxgaXQAHAgAAAA==.Trustportal:BAAANQADCggIHAABNQAECgYIEAAKAAAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECn8hAAIeAAkKaiG4GgCxAgAeAAkKaiG4GgCxAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgQIBgABNQAECggIKAAYADMXAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valstan:BAAANQAECgUICQAAAA==.Valzyn:BAAANQAECgcIDAAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECn8nAAMXAAkKRBOVJQD/AQAXAAgKdxSVJQD/AQAfAAYKkBA3kgBaAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgkJJwAhAMwgAA==.Warisfluffy:BAAANQAECgYIDwAAAA==.',
We='Wedaddams:BAAANQAECggICAAAAA==.Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEJAQAAAA==.',
Wo='Worldboss:BAAANQAECgYIDwAAAA==.Worldwar:BAAANQAECgUIDgAAAA==.',
Wr='Wradalin:BAABNQAECn8dAAIeAAkKZx0nJgBfAgAeAAkKZx0nJgBfAgAAAA==.Wraithstorm:BAAANQAECgUICQAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQAECgQIBQAAAA==.Zartain:BAABNQAECn8bAAIkAAcKtQpWSwCPAQAkAAcKtQpWSwCPAQAAAA==.',
Ze='Zelarus:BAAANQAECgcIBwAAAA==.Zenizho:BAAANQAECgIIAwAAAA==.Zennamite:BAABNQAECn8XAAIPAAcKbRJTgQCdAQAPAAcKbRJTgQCdAQAAAA==.',
Zi='Zipzaps:BAAANQAECgIIBAAAAA==.',
Zu='Zuldarack:BAAANQAECgEIAQAAAA==.',
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
