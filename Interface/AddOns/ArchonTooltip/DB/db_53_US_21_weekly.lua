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

local lookup = {'Warrior-Arms','Unknown-Unknown','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Druid-Balance','Druid-Feral','Monk-Brewmaster','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Retribution','Mage-Arcane','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','DeathKnight-Unholy','Shaman-Enhancement','DeathKnight-Frost','Priest-Holy',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgUIBwAAAA==.Abbyrose:BAAANQABCggICgAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAAANQAECgYICwAAAA==.',
Ak='Akroma:BAAANQAECgUICQAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECoEfAAIBAAcKaCFLTwBcAgABAAcKaCFLTwBcAgAAAA==.Aluciena:BAAANQADCgcIBwAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECgYICwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAAANQAECgYIEwAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAAANQAECggIEgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgcICgACAAAAAA==.Arykami:BAAANQAECgIIAgABNQAECgkJHgADAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgADAFceAA==.Arystrasza:BAABNQAECoEeAAIDAAkKVx6ABgAlAwADAAkKVx6ABgAlAwAAAA==.Aryzhuque:BAAANQAECgYICwABNQAECgkJHgADAFceAA==.',
As='Ashmandious:BAAANQAECgcIDQAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECoEkAAIEAAkKjyZ1AADvAwAEAAkKjyZ1AADvAwAAAA==.',
At='Athleta:BAEBNQAFFIEKAAIFAAUKSQ/nAABnAQAFAAUKSQ/nAABnAQABNQAFFAgIGwAGAFYUAA==.',
Av='Average:BAAANQADCgYICQAAAA==.',
Ba='Balkaj:BAAANQADCgEIAQAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAAANQAECgUIDQAAAA==.',
Be='Beefajitas:BAAANQADCgQIBAAAAA==.Beerhelmet:BAAANQAECgQIDAAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAAANQAECgUICQAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Bl='Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECoEZAAIHAAkKVRk7KAC7AgAHAAkKVRk7KAC7AgAAAA==.Bowser:BAAANQAECgQIBQAAAA==.',
Br='Braleanna:BAAANQAECgIIAgAAAA==.Brigeta:BAAANQAECggICAAAAA==.',
Bu='Bugge:BAAANQAECgUIBQAAAA==.Bulldozzer:BAAANQADCgYICwAAAA==.Bus:BAAANQAECgEJAQABNQAFFAYIEwAIAE8hAA==.',
Cb='Cbat:BAAANQAECgYICgAAAA==.',
Cd='Cdicepalta:BAABNQAECoEbAAQEAAgKSwq1HwATAQAJAAgKJAm5RACOAQAEAAcKkAi1HwATAQAKAAQKMQlzHgC8AAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgQIBAAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECoEeAAIGAAkKWR9iDQAjAwAGAAkKWR9iDQAjAwABNQAECgkJJAALAC0kAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCgYIBgAAAA==.',
Co='Coinlock:BAAANQADCgMIAwAAAA==.Confettii:BAAANQABCgQIBQABNQAECgQIBQACAAAAAA==.',
Ct='Ctrlaltshot:BAAANQADCggICgAAAA==.',
Cu='Cutedeath:BAAANQADCgUIBwAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAAANQAECgYICQAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECoEkAAMBAAkKqRJ4WwA0AgABAAkKqRJ4WwA0AgAMAAEKRAeLKQAwAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECgUICAACAAAAAA==.Dawny:BAABNQAECoEkAAMNAAkK8A5PTQDeAQANAAkK8A5PTQDeAQAOAAIKCgxq1AB6AAAAAA==.Daywalkers:BAAANQAECgQICwABNQAECgUICAACAAAAAA==.',
De='Dethndk:BAAANQAECggIEgAAAA==.',
Di='Die:BAABNQAECoEhAAIPAAkKqBW4BQBcAgAPAAkKqBW4BQBcAgAAAA==.',
Do='Doorjob:BAABNQAECoEZAAMQAAkKdh1FFAC/AgAQAAkKdh1FFAC/AgAFAAQK/BB/FwDMAAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQAIAN8SAA==.',
Dr='Dreadravens:BAAANQADCgUJBQAAAA==.Dreamily:BAABNQAECoEkAAIJAAkKxRPaKwA6AgAJAAkKxRPaKwA6AgAAAA==.Dreamtalker:BAAANQABCggIEQAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAAANQAECgUICQAAAA==.Elia:BAABNQAECoEZAAIHAAkKSx3wIwDOAgAHAAkKSx3wIwDOAgAAAA==.Elmo:BAABNQAECoEbAAIGAAkKWBeVIAB5AgAGAAkKWBeVIAB5AgAAAA==.Elurrmental:BAAANQADCggIHwAAAA==.Elzä:BAAANQAECgYICQAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBQABNQAECgQIBQACAAAAAA==.Emp:BAAANQADCgYIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECoEaAAIQAAgKpBynFwCaAgAQAAgKpBynFwCaAgAAAA==.Entropius:BAAANQAECgUIDQAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECgQIBQACAAAAAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECoEhAAIRAAkKnhAPbwD1AQARAAkKnhAPbwD1AQAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feralkitty:BAAANQAECggICAAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECoEeAAIOAAkKzA/HQgAeAgAOAAkKzA/HQgAeAgAAAA==.Foregotten:BAABNQAECoEfAAIJAAgKxBaoKgBDAgAJAAgKxBaoKgBDAgAAAA==.',
Fr='Frostietute:BAAANQAECgQIBwABNQAECggIHAASAOMaAA==.',
Fu='Furysmight:BAAANQAECgcICgAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAECgkJFwATAOAhAA==.Gamboa:BAAANQAECgIIAgAAAA==.Gauche:BAAANQAECgUICgAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAAANQAECgQIBgAAAA==.Gravel:BAAANQADCggICQAAAA==.Grÿmm:BAAANQAECgUICwAAAA==.',
Gu='Guldanica:BAAANQAECgQIBAAAAA==.Gunn:BAAANQADCgQIAwAAAA==.',
Gw='Gwaine:BAAANQAECgUIBgAAAA==.Gwin:BAAANQAECggICgAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgIIAgACAAAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyldin:BAAANQAECgEIAQAAAA==.Heritikylust:BAAANQAECgcIEwAAAA==.',
Hi='Hibou:BAAANQADCgcIBgAAAA==.',
Ho='Holyhero:BAABNQAECoEdAAIUAAgKOxdnGABKAgAUAAgKOxdnGABKAgAAAA==.',
Il='Ilectra:BAABNQAECoEcAAIVAAgKTRJcIAAPAgAVAAgKTRJcIAAPAgAAAA==.Illani:BAAANQADCgcIBwAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQAECgQIBQACAAAAAA==.Intensitii:BAAANQABCgQICQABNQAECgQIBQACAAAAAA==.',
Ip='Ipoopied:BAAANQADCgQJBAAAAA==.',
Is='Ishmara:BAAANQAECgEIAgAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQABCggIEgAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAAANQAECgcIEwAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Kepec:BAAANQADCgYJDQABNQAECgMJBAACAAAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgIIAgACAAAAAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgIIAgACAAAAAA==.Krimzonstorm:BAAANQAECgIIAgAAAA==.',
Ku='Kunaee:BAAANQAECgIIAgAAAA==.',
Ky='Kyrius:BAAANQAECgcIBwAAAA==.',
['Kì']='Kìku:BAAANQAECgUIDQAAAA==.',
La='Lausia:BAAANQAECgUIDQABNQAECggIHAAVAE0SAA==.',
Ld='Ldyrose:BAAANQADCgcIHQAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAAANQAECgQICQAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEQACAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMJAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggJCAABNQADCggIEgACAAAAAA==.',
Ma='Macabre:BAAANQAECgUIDQAAAA==.Magnificò:BAAANQAECgUIDQAAAA==.Makani:BAAANQAECgUICQAAAA==.Malarix:BAAANQADCgUJBQABNQADCgYIBgACAAAAAA==.Malory:BAABNQAECoEXAAITAAkK4CHOAgBNAwATAAkK4CHOAgBNAwAAAA==.Malzahär:BAABNQAECoEaAAQWAAkKDyG3NQB4AgAWAAcKfiG3NQB4AgAXAAUKpRy4GACZAQAYAAMKax1bEQDkAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQADCgUIBwAAAA==.',
Mo='Mooyouhapee:BAAANQADCgQIBAAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgIIAgAAAA==.Muffintop:BAAANQAECgUIDQAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQADCggJCAAAAA==.Mythrondrir:BAAANQAECgYIDQAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQABCggIEAABNQADCggIEgACAAAAAA==.',
Ne='Neosnÿper:BAAANQAECgcIEwABNQAECgkJIwAWAB4eAA==.',
Ni='Nielic:BAAANQAECgcIDwAAAA==.Nimbus:BAAANQADCggICAABNQAFFAQIBgAOAGkPAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Norrahh:BAAANQAECgIIAgAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Om='Omgitsmagic:BAAANQAECgMIAwAAAA==.',
On='Ongo:BAAANQAECgYIEQAAAA==.',
Or='Orion:BAAANQAECgUIBgAAAA==.',
Pa='Palapoxi:BAABNQAECoEmAAIZAAkKzCCaCwBMAwAZAAkKzCCaCwBMAwAAAA==.Pallybugge:BAAANQABCgEIAQAAAA==.',
Pe='Penelopè:BAABNQAECoEkAAILAAkKLSSQAQCTAwALAAkKLSSQAQCTAwAAAA==.Penelópe:BAAANQADCgEIAQABNQAECgkJJAALAC0kAA==.Penný:BAAANQAECgEIAQABNQAECgkJJAALAC0kAA==.Pepino:BAAANQAECgMIBwAAAA==.',
Ph='Phinx:BAABNQAECoEcAAIaAAkKmBj9JgBPAgAaAAkKmBj9JgBPAgAAAA==.Phocheux:BAABNQAECoEUAAIbAAYK9xfGEwDWAQAbAAYK9xfGEwDWAQAAAA==.',
Pi='Pierogi:BAAANQADCgYIBgAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgIIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQAECgQIBQAAAA==.Pomickyal:BAAANQAECgUIDQAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQADCggIHQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQADCgYIEwAAAA==.Ragnärok:BAABNQAECoEXAAINAAkKPRXCQAASAgANAAkKPRXCQAASAgAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFIENAAIGAAUKlRetCAB7AQAGAAUKlRetCAB7AQA1AAQKgScAAgYACQowIkEHAG0DAAYACQowIkEHAG0DAAAA.Reverii:BAAANQABCgYICAABNQAECgQIBQACAAAAAA==.Rezelda:BAAANQAECgMIAwAAAA==.',
Rj='Rj:BAAANQAECgUICQAAAA==.',
Ro='Roughbbq:BAAANQADCgEIAQABNQAECgMIBwACAAAAAA==.',
Rt='Rtpopham:BAAANQAECgQIBgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAAANQAECgUIDAAAAA==.Sandros:BAAANQABCgYJCQAAAA==.Saphrin:BAAANQAECgUICgAAAA==.Sardiirn:BAAANQAECgEIAgABNQAECgUICAACAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAAANQAECgQIDgAAAA==.',
Se='Selynne:BAABNQAECoEkAAIRAAkKvyHWJAD9AgARAAkKvyHWJAD9AgAAAA==.',
Sh='Shamanizeds:BAAANQAECgUICAAAAA==.Shamwisegamg:BAAANQADCgYIBgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Shifted:BAABNQAECoEYAAIEAAgKIgtqGABjAQAEAAgKIgtqGABjAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQADCgMIAwAAAA==.Sixligma:BAAANQAECgQICgAAAA==.',
Sk='Skye:BAAANQADCggJCwABNQAECggIHwAJAMQWAA==.',
Sl='Slorrin:BAABNQAECoEiAAIBAAkKSSVXCQCZAwABAAkKSSVXCQCZAwAAAA==.',
So='Solazreiale:BAAANQAECgIIAgAAAA==.Somers:BAAANQADCggIEgAAAA==.Soulistic:BAAANQABCggIFwAAAA==.',
Sp='Spellbind:BAAANQAECgEIAgAAAA==.',
St='Starstorms:BAAANQAECgUIDQAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQADCgQIAwAAAA==.',
Sy='Sylvas:BAAANQADCgUIBQAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgMICAAAAA==.Taiez:BAAANQAECgUICQAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQJBgAAAA==.Thenakedcow:BAAANQADCgEIAQAAAA==.Therapii:BAAANQABCgQIBQABNQAECgQIBQACAAAAAA==.Thesledge:BAABNQAECoEZAAIRAAgKzRLddADlAQARAAgKzRLddADlAQAAAA==.',
Ti='Tifalockhàrt:BAABNQAECoEgAAIZAAgKJQXQcwBqAQAZAAgKJQXQcwBqAQAAAA==.Timewarped:BAABNQAECoEWAAISAAcKbBP9qQDkAQASAAcKbBP9qQDkAQAAAA==.',
Tr='Trapsin:BAABNQAECoEhAAISAAkKqyBqJAA2AwASAAkKqyBqJAA2AwAAAA==.Treeage:BAABNQAECoEfAAQKAAkKRxHMCQA5AgAKAAkKRxHMCQA5AgAEAAEKtgR2QQAtAAAJAAEKawGVpwAUAAAAAA==.Trufflé:BAAANQAECgUIDQAAAA==.Trustportal:BAAANQADCggIGQABNQAECgUICQACAAAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECoEcAAIcAAkK8yBuEgC8AgAcAAkK8yBuEgC8AgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgIIAgABNQAECggIHAAVAE0SAA==.',
Us='Usdaprime:BAAANQAECgEIAgAAAA==.',
Va='Valstan:BAAANQADCggIIgAAAA==.Valzyn:BAAANQAECgYICAAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECoEkAAMUAAkK9RSOGwAhAgAUAAgKERaOGwAhAgAdAAUK/hHreQA8AQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgkJJgAZAMwgAA==.Warisfluffy:BAAANQAECgYIDwAAAA==.',
We='Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEJAQAAAA==.',
Wo='Worldboss:BAAANQAECgUICAAAAA==.Worldwar:BAAANQAECgUICQAAAA==.',
Wr='Wradalin:BAABNQAECoEbAAIcAAgKdx5qGwBmAgAcAAgKdx5qGwBmAgAAAA==.Wraithstorm:BAAANQADCggJGgAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQADCgYIBwAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQAECgIIAgAAAA==.Zartain:BAAANQAECgUIDQAAAA==.',
Ze='Zenizho:BAAANQAECgEIAQAAAA==.Zennamite:BAAANQAECgUICQAAAA==.',
Zi='Zipzaps:BAAANQAECgIIAwAAAA==.',
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
