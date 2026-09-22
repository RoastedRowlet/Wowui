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

local lookup = {'Warrior-Arms','Unknown-Unknown','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Monk-Brewmaster','Shaman-Restoration','Rogue-Outlaw','Druid-Balance','Paladin-Retribution','Shaman-Elemental','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','DeathKnight-Unholy','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Priest-Holy',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgIIAgAAAA==.Abbyrose:BAAANQABCggICgAAAA==.',
Ad='Adrenelian:BAAANQAECgUJBQAAAA==.',
Ak='Akroma:BAAANQAECgMIBAAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECoEYAAIBAAcKaCGSOwB4AgABAAcKaCGSOwB4AgAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECgYICwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAAANQAECgUIDQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAAANQAECgcIEQAAAA==.Arthuur:BAAANQAECgYJCQABNQAECgcICAACAAAAAA==.Arykami:BAAANQAECgIIAgABNQAECgkJHgADAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgADAFceAA==.Arystrasza:BAABNQAECoEeAAIDAAkKVx5GBQAvAwADAAkKVx5GBQAvAwAAAA==.Aryzhuque:BAAANQAECgYICAABNQAECgkJHgADAFceAA==.',
As='Ashmandious:BAAANQAECgQIBgAAAA==.Assandros:BAABNQAECoEhAAIEAAkKcyZTAADzAwAEAAkKcyZTAADzAwAAAA==.',
At='Athleta:BAEBNQAFFIEIAAIFAAUKeQ2ZAABXAQAFAAUKeQ2ZAABXAQABNQAFFAcJGQAGADUUAA==.',
Av='Average:BAAANQADCgMIAwAAAA==.',
Ba='Balkaj:BAAANQADCgEIAQAAAA==.Banditrii:BAAANQABCgUJBwAAAA==.Banthum:BAAANQAECgQJCAAAAA==.',
Be='Beerhelmet:BAAANQAECgQICwAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAAANQAECgQIBAAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgACAAAAAA==.',
Bl='Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECoEZAAIHAAkKVRkKGwDYAgAHAAkKVRkKGwDYAgAAAA==.Bowser:BAAANQAECgIJAwAAAA==.',
Br='Braleanna:BAAANQADCgcIEAAAAA==.',
Bu='Bugge:BAAANQADCgcIDQAAAA==.Bulldozzer:BAAANQADCgUIBQAAAA==.Bus:BAAANQAECgEJAQABNQAFFAUIEQAIADUhAA==.',
Cb='Cbat:BAAANQAECgQIBAAAAA==.',
Cd='Cdicepalta:BAAANQAECgYIEAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECoEbAAIGAAkKDh2ADgD8AgAGAAkKDh2ADgD8AgABNQAECgkJIQAJAC0kAA==.',
Ci='Ciele:BAAANQABCgEIAQAAAA==.Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCgYIBgAAAA==.',
Co='Coinlock:BAAANQADCgMIAwAAAA==.Confettii:BAAANQABCgUICAABNQAECgEIAQACAAAAAA==.Corwynn:BAAANQABCgEIAQAAAA==.',
Ct='Ctrlaltshot:BAAANQADCggICgAAAA==.',
Cu='Cutedeath:BAAANQADCgIIAgAAAA==.Cuteretsu:BAAANQABCgYIBwAAAA==.',
Da='Dalus:BAAANQAECgYJBgAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECoEcAAIBAAgKkxJPVwAQAgABAAgKkxJPVwAQAgAAAA==.Darkslayers:BAAANQADCgUICAABNQAECgQICAACAAAAAA==.Dawny:BAABNQAECoEhAAIKAAkK6A72OgAFAgAKAAkK6A72OgAFAgAAAA==.Daywalkers:BAAANQAECgQICAAAAA==.',
De='Dethndk:BAAANQAECgcIDAAAAA==.',
Di='Die:BAABNQAECoEeAAILAAkKqBV8BAB6AgALAAkKqBV8BAB6AgAAAA==.',
Do='Doorjob:BAAANQAECgcIEwAAAA==.Doràn:BAAANQADCggICAABNQAFFAcIBwAIAFoRAA==.',
Dr='Dreadravens:BAAANQADCgUJBQAAAA==.Dreamily:BAABNQAECoEhAAIMAAkK+BIoJQBBAgAMAAkK+BIoJQBBAgAAAA==.Dreamtalker:BAAANQABCggIEwAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ej='Eji:BAAANQABCgYICgAAAA==.',
El='Elenyia:BAAANQAECgMIBAAAAA==.Elia:BAABNQAECoEZAAIHAAkKSx29FwDsAgAHAAkKSx29FwDsAgAAAA==.Elmo:BAAANQAECgcIEwAAAA==.Elurrmental:BAAANQADCggJFwAAAA==.Elzä:BAAANQAECgMIAwAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBwABNQAECgEIAQACAAAAAA==.Emp:BAAANQADCgYIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAAANQAECgYIEAAAAA==.Entropius:BAAANQAECgQJCAAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Et='Eternitii:BAAANQABCgEIAgABNQAECgEIAQACAAAAAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECoEhAAINAAkKnhDlUgALAgANAAkKnhDlUgALAgAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feralkitty:BAAANQAECggICAAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECoEbAAIOAAkKGw+XNgAlAgAOAAkKGw+XNgAlAgAAAA==.Foregotten:BAABNQAECoEdAAIMAAgKxBZYIgBaAgAMAAgKxBZYIgBaAgAAAA==.',
Fr='Frostietute:BAAANQAECgIJAwABNQAECgcIEgACAAAAAA==.',
Fu='Furysmight:BAAANQAECgcICAAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAFFAIJAgACAAAAAA==.Gamboa:BAAANQAECgIIAgAAAA==.Gauche:BAAANQAECgQJBQAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAAANQAECgEIAgAAAA==.Grÿmm:BAAANQAECgUIBwAAAA==.',
Gu='Guldanica:BAAANQAECgQIBAAAAA==.Gunn:BAAANQADCgQIAwAAAA==.',
Gw='Gwaine:BAAANQAECgEIAQAAAA==.Gwin:BAAANQAECggJCAAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCgQJBAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQADCggIBwACAAAAAA==.',
He='Hellfyrê:BAAANQAECgIJAgAAAA==.Heritikylust:BAAANQAECgYIDQAAAA==.',
Hi='Hibou:BAAANQADCgcIBgAAAA==.',
Ho='Holyhero:BAABNQAECoEWAAIPAAgKHhUkFQBPAgAPAAgKHhUkFQBPAgAAAA==.',
Il='Ilectra:BAAANQAECgUJEAAAAA==.',
In='Insanitii:BAAANQABCgQIBwABNQAECgEIAQACAAAAAA==.Intensitii:BAAANQABCgQJCgABNQAECgEIAQACAAAAAA==.',
Ip='Ipoopied:BAAANQADCgQJBAAAAA==.',
Is='Ishmara:BAAANQAECgEIAQAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQABCggJEAAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAAANQAECgYJDQAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Kepec:BAAANQADCgYJDQABNQAECgMJBAACAAAAAA==.',
Kn='Knyxxe:BAAANQABCgEIAQAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgAAAA==.Krimzondawn:BAAANQADCgIIAgABNQADCgYICgACAAAAAA==.Krimzonstorm:BAAANQADCgQJBQABNQADCgYICgACAAAAAA==.',
Ku='Kunaee:BAAANQADCgcIDwAAAA==.',
Ky='Kyrius:BAAANQADCggIEwABNQAECgcIDAACAAAAAA==.',
['Kì']='Kìku:BAAANQAECgQJCAAAAA==.',
La='Lausia:BAAANQAECgQJCAABNQAECgUJEAACAAAAAA==.',
Ld='Ldyrose:BAAANQADCgYJFgAAAA==.',
Le='Leilarose:BAAANQABCgcICAAAAA==.Lewtiefroopz:BAAANQAECgQIBQAAAA==.',
Li='Lilblade:BAAANQABCgcJDgABNQABCggIEwACAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMJAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggJCAABNQADCgcICgACAAAAAA==.',
Ma='Macabre:BAAANQAECgQJCAAAAA==.Magnificò:BAAANQAECgQJCAAAAA==.Makani:BAAANQAECgMIBAAAAA==.Malarix:BAAANQADCgUJBQABNQADCgYIBgACAAAAAA==.Malory:BAAANQAECgcIEQABNQAFFAIJAgACAAAAAA==.Malzahär:BAABNQAECoEaAAQQAAkKDyE1JQCRAgAQAAcKfiE1JQCRAgARAAUKpRwHFgCkAQASAAMKax07DgDoAAAAAA==.Maress:BAAANQABCgEIAwAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQADCgUIBwAAAA==.',
Mo='Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQADCggIBwAAAA==.Muffintop:BAAANQAECgQJCAAAAA==.',
My='Mysticstorms:BAAANQABCgEIAQABNQAECgQJCAACAAAAAA==.Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQADCggJCAAAAA==.Mythrondrir:BAAANQAECgYJDQAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQABCgQICQABNQADCgcICgACAAAAAA==.',
Ne='Neosnÿper:BAAANQAECgUIDAABNQAECggJIAAQAK4fAA==.',
Ni='Nielic:BAAANQAECgUIDQAAAA==.Nimbus:BAAANQADCggICAABNQAFFAUICAAOALYTAA==.',
No='Norrahh:BAAANQADCgcIFgAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Om='Omgitsmagic:BAAANQAECgIIAgAAAA==.',
On='Ongo:BAAANQAECgUICgAAAA==.',
Or='Orion:BAAANQAECgMIAwAAAA==.',
Pa='Palapoxi:BAABNQAECoEjAAITAAkKnh8YCgBFAwATAAkKnh8YCgBFAwAAAA==.',
Pe='Penelopè:BAABNQAECoEhAAIJAAkKLSQcAQCkAwAJAAkKLSQcAQCkAwAAAA==.Penelópe:BAAANQADCgEIAQABNQAECgkJIQAJAC0kAA==.Penný:BAAANQAECgEIAQABNQAECgkJIQAJAC0kAA==.Pepino:BAAANQAECgMIBwAAAA==.',
Ph='Phinx:BAABNQAECoEZAAIUAAkKbhgSHACGAgAUAAkKbhgSHACGAgAAAA==.Phocheux:BAAANQAECgYJDgAAAA==.',
Pi='Pierogi:BAAANQADCgYIBgAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgIIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQAECgEIAQAAAA==.Pomickyal:BAAANQAECgQJCAAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQADCggIHQAAAA==.',
Py='Pyssmissile:BAAANQAECgEIAQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQADCgUJDQAAAA==.Ragnärok:BAABNQAECoEWAAIKAAgKKBU/QADtAQAKAAgKKBU/QADtAQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFIEIAAIGAAUKCBfXBQCAAQAGAAUKCBfXBQCAAQA1AAQKgSQAAgYACQr4IQsGAHEDAAYACQr4IQsGAHEDAAAA.Reverii:BAAANQABCgYICgABNQAECgEIAQACAAAAAA==.Rezelda:BAAANQADCgIJAgAAAA==.',
Rj='Rj:BAAANQAECgMIBAAAAA==.',
Ro='Roughbbq:BAAANQADCgEIAQABNQAECgMIBgACAAAAAA==.',
Rt='Rtpopham:BAAANQAECgQIBgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAAANQAECgQJBwAAAA==.Sandros:BAAANQABCgYJCgAAAA==.Saphrin:BAAANQAECgMJBQAAAA==.Sardiirn:BAAANQAECgEJAQABNQAECgQICAACAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAAANQAECgQICgAAAA==.',
Se='Selynne:BAABNQAECoEhAAINAAkKVSFSGgANAwANAAkKVSFSGgANAwAAAA==.',
Sh='Shamanizeds:BAAANQAECgMJAwABNQAECgQICAACAAAAAA==.Shamwisegamg:BAAANQADCgYIBgAAAA==.Shankems:BAAANQADCgEIAQAAAA==.Shifted:BAAANQAECgYIDQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQADCgMIAwAAAA==.Sixligma:BAAANQAECgEJAQAAAA==.',
Sk='Skye:BAAANQADCggJCwABNQAECggIHQAMAMQWAA==.',
Sl='Slorrin:BAABNQAECoEhAAIBAAkKSSVMBQC2AwABAAkKSSVMBQC2AwAAAA==.',
So='Solazreiale:BAAANQADCgcIFgAAAA==.Somers:BAAANQADCgcICgAAAA==.Soulistic:BAAANQABCggIEwAAAA==.',
Sp='Spellbind:BAAANQAECgEIAQAAAA==.',
St='Starstorms:BAAANQAECgQJCAAAAA==.Stillette:BAAANQABCgEIAQAAAA==.',
Sy='Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgMJBQAAAA==.Taiez:BAAANQAECgQIBAAAAA==.Tauming:BAAANQAECgIJAgAAAA==.',
Te='Teshala:BAAANQAECgQIBAAAAA==.',
Th='Tharil:BAAANQABCgQJBgAAAA==.Therapii:BAAANQABCgQJBwABNQAECgEIAQACAAAAAA==.Thesledge:BAAANQAECgYIDgAAAA==.',
Ti='Tifalockhàrt:BAABNQAECoEeAAITAAgKHAUIYQBzAQATAAgKHAUIYQBzAQAAAA==.Timewarped:BAAANQAECgYJEAAAAA==.',
Tr='Trapsin:BAABNQAECoEcAAIVAAgKNiJaKgASAwAVAAgKNiJaKgASAwAAAA==.Treeage:BAABNQAECoEZAAQWAAgK5w5mCgDgAQAWAAgK5w5mCgDgAQAEAAEKtgS4MwAtAAAMAAEKawHDlAAVAAAAAA==.Trufflé:BAAANQAECgQJCAAAAA==.Trustportal:BAAANQADCggIGQABNQAECgMIBAACAAAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECoEZAAIXAAkKriAGDgDLAgAXAAkKriAGDgDLAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQADCgEIAQABNQAECgUJEAACAAAAAA==.',
Us='Usdaprime:BAAANQAECgEIAQAAAA==.',
Va='Valstan:BAAANQADCggJGgAAAA==.Valzyn:BAAANQAECgIIAgAAAA==.',
Ve='Velanora:BAAANQADCgMIBQAAAA==.Verdantclaw:BAAANQABCgUICQAAAA==.',
Vi='Vivix:BAABNQAECoEhAAMPAAkKvBQaFgBBAgAPAAgK0RUaFgBBAgAYAAUK/hGRZQBAAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgkJIwATAJ4fAA==.Warisfluffy:BAAANQAECgUICQAAAA==.',
We='Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEJAQAAAA==.',
Wo='Worldboss:BAAANQAECgQIBAAAAA==.Worldwar:BAAANQAECgQIBAAAAA==.',
Wr='Wradalin:BAABNQAECoEaAAIXAAgKAR6FEwCCAgAXAAgKAR6FEwCCAgAAAA==.Wraithstorm:BAAANQADCggJGgAAAA==.',
Yu='Yunera:BAAANQADCgYJBgAAAA==.',
Za='Zalor:BAAANQABCgYJBAAAAA==.Zarila:BAAANQADCgcIFgAAAA==.Zartain:BAAANQAECgQJCAAAAA==.',
Ze='Zenizho:BAAANQADCgcJBwAAAA==.Zennamite:BAAANQAECgQIBAAAAA==.',
Zi='Zipzaps:BAAANQAECgEIAQAAAA==.',
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
