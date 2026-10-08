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

local lookup = {'Warrior-Arms','Mage-Arcane','Unknown-Unknown','Evoker-Preservation','Druid-Guardian','DemonHunter-Vengeance','DeathKnight-Blood','Hunter-BeastMastery','Paladin-Protection','Druid-Balance','Druid-Feral','Monk-Brewmaster','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','DemonHunter-Havoc','Paladin-Retribution','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Druid-Restoration','Priest-Holy','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm='Arygos',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaryssian:BAAANQADCgYIBgAAAA==.',
Ab='Abattoire:BAAANQADCgcIDgAAAA==.Abbyrose:BAAANQABCggICgAAAA==.',
Ad='Adivion:BAAANQAECgUIBQAAAA==.Adrenelian:BAAANQAECgcIEQAAAA==.',
Ak='Akroma:BAAANQAECgUICgAAAA==.',
Al='Allyon:BAAANQADCgQIBwAAAA==.Altezio:BAABNQAECoEnAAIBAAgKWSDMQQCsAgABAAgKWSDMQQCsAgAAAA==.Aluciena:BAAANQADCggIDQAAAA==.',
Am='Amargue:BAAANQADCgEJAQAAAA==.Amorial:BAAANQADCgEIAQAAAA==.',
An='Anbraxas:BAAANQABCgMIAwAAAA==.Ankarna:BAAANQADCgUIDQAAAA==.Annegwish:BAAANQAECggIDwAAAA==.Antashaman:BAAANQAECgMIAwAAAA==.',
Ap='Apah:BAAANQADCgYIBgAAAA==.',
Ar='Arathon:BAAANQAECgQIBwAAAA==.Arclight:BAABNQAECoEdAAICAAgKngUa6gCPAQACAAgKngUa6gCPAQAAAA==.Ardiana:BAAANQADCggICAAAAA==.Ardimis:BAAANQADCgYIBgAAAA==.Ardithan:BAABNQAECoEVAAICAAkKxB4vVgDDAgACAAkKxB4vVgDDAgAAAA==.Arthuur:BAAANQAECgYICQABNQAECgcIEQADAAAAAA==.Arykami:BAAANQAECgQIBQABNQAECgkJHgAEAFceAA==.Arypto:BAAANQADCggICAABNQAECgkJHgAEAFceAA==.Arystrasza:BAABNQAECoEeAAIEAAkKVx7FBwAbAwAEAAkKVx7FBwAbAwAAAA==.Aryzhuque:BAAANQAECgYICwABNQAECgkJHgAEAFceAA==.',
As='Ashmandious:BAAANQAECgcIDQAAAA==.Aspyn:BAAANQABCgIIAgAAAA==.Assandros:BAABNQAECoEnAAIFAAkKmCatAADqAwAFAAkKmCatAADqAwAAAA==.',
At='Athleta:BAEBNQAFFIEKAAIGAAUKTQ9lAQBZAQAGAAUKTQ9lAQBZAQABNQAFFAkJJAAHAAIYAA==.',
Av='Average:BAAANQADCgYIDwAAAA==.',
Ba='Bajablastois:BAAANQAECgQIBAABNQAECgkJLAAHAMkhAA==.Balkaj:BAAANQADCgEIAQAAAA==.Banditrii:BAAANQABCgUIBgAAAA==.Banthum:BAAANQAECgUIEgAAAA==.',
Be='Beefajitas:BAAANQADCgQICQAAAA==.Beerhelmet:BAAANQAECgQIEAAAAA==.Beryl:BAAANQAECgEIAQAAAA==.',
Bi='Biggyword:BAAANQAECgUICQAAAA==.Bingchow:BAAANQADCgQIBAABNQADCgYIBgADAAAAAA==.',
Bl='Blorbusdorp:BAAANQADCgUICAAAAA==.',
Bo='Bobsgirl:BAABNQAECoEdAAIIAAkKtRlgMwCvAgAIAAkKtRlgMwCvAgAAAA==.Bowser:BAAANQAECgYICwAAAA==.',
Br='Braleanna:BAAANQAECgQIBgAAAA==.Brigeta:BAAANQAECggICAAAAA==.',
Bu='Bugge:BAAANQAECgUICgAAAA==.Bulldozzer:BAAANQADCgYICwAAAA==.Bus:BAAANQAECggICQABNQAFFAYIFQAJAKYhAA==.',
Cb='Cbat:BAAANQAECgYICgAAAA==.',
Cd='Cdicepalta:BAABNQAECoEgAAQKAAgKfwtSSgCSAQAKAAgKgQpSSgCSAQAFAAcKkAgkKAAOAQALAAQKMQmEJAC4AAAAAA==.',
Ce='Celes:BAAANQADCgMIAwAAAA==.Cerir:BAAANQAECgUIBwAAAA==.Cetera:BAAANQAECgQIBAAAAA==.',
Ch='Chapulín:BAABNQAECoEhAAIHAAkK2R+MDwAfAwAHAAkK2R+MDwAfAwABNQAECgkJJwAMAHokAA==.',
Ci='Cinimist:BAAANQAECgYIBgAAAA==.Cirberus:BAAANQADCgYICgAAAA==.',
Co='Coinlock:BAAANQAECgIIAgAAAA==.Confettii:BAAANQABCgQIBQABNQAECgQIBQADAAAAAA==.',
Ct='Ctrlaltshot:BAAANQADCggICgAAAA==.',
Cu='Cutedeath:BAAANQADCgUIBwAAAA==.Cuteretsu:BAAANQADCgUIBQAAAA==.',
Da='Dalus:BAAANQAECgYIDQAAAA==.Dankzìlla:BAAANQAECgYIBgAAAA==.Darington:BAABNQAECoEkAAMBAAkKqRLuawAuAgABAAkKqRLuawAuAgANAAEKRAeQLwAvAAAAAA==.Darkslayers:BAAANQADCgYIDgABNQAECgUIDAADAAAAAA==.Dawny:BAABNQAECoEkAAMOAAkK8A5RXADLAQAOAAkK8A5RXADLAQAPAAIKCgxn7gB1AAAAAA==.Daywalkers:BAAANQAECgQIDgABNQAECgUIDAADAAAAAA==.',
De='Dethndk:BAABNQAECoEYAAIHAAkKThvZIgCGAgAHAAkKThvZIgCGAgAAAA==.',
Di='Die:BAABNQAECoEhAAIQAAkKqBV/BgBOAgAQAAkKqBV/BgBOAgAAAA==.',
Do='Doorjob:BAABNQAECoEaAAMRAAkKfR1DGgClAgARAAkKfR1DGgClAgAGAAQK/BBNHADCAAAAAA==.Doràn:BAAANQADCggICAABNQAFFAcICQAJAN8SAA==.',
Dr='Dreadravens:BAAANQADCgUIBQAAAA==.Dreamily:BAABNQAECoEkAAIKAAkKxRPTMgAoAgAKAAkKxRPTMgAoAgAAAA==.Dreamtalker:BAAANQABCggIEQAAAA==.Dråcø:BAAANQADCgUIBQAAAA==.',
Du='Dumpy:BAAANQADCgQIBAAAAA==.',
Ej='Eji:BAAANQABCgYICQAAAA==.',
El='Elenyia:BAAANQAECgUICgAAAA==.Elia:BAABNQAECoEdAAIIAAkKgR4EJADpAgAIAAkKgR4EJADpAgAAAA==.Elmo:BAABNQAECoEbAAIHAAkKWBdfJwBpAgAHAAkKWBdfJwBpAgAAAA==.Elurrmental:BAAANQAECgQIBAAAAA==.Elzä:BAAANQAECgYICQAAAA==.',
Em='Emaria:BAAANQADCgYIGwAAAA==.Emergencii:BAAANQABCgMIBQABNQAECgQIBQADAAAAAA==.Emp:BAAANQADCgYIBgAAAA==.',
En='Enemor:BAAANQADCgMIAwAAAA==.Entranced:BAABNQAECoEhAAIRAAgK+hwPHACVAgARAAgK+hwPHACVAgAAAA==.Entropius:BAAANQAECgUIEgAAAA==.',
Er='Eranica:BAAANQADCgIIAgAAAA==.Ereinion:BAAANQAECgQICgAAAA==.',
Et='Eternitii:BAAANQABCgQIBAABNQAECgQIBQADAAAAAA==.',
Ey='Eyb:BAAANQAECgEIAQAAAA==.',
Ez='Ezayle:BAABNQAECoEhAAISAAkKnhAiiADjAQASAAkKnhAiiADjAQAAAA==.',
Fa='Faxtom:BAAANQADCgQIBAAAAA==.',
Fe='Fearsmage:BAAANQABCgIIAgAAAA==.Femto:BAAANQAECgIIAgAAAA==.Feralkitty:BAAANQAECggIDwAAAA==.',
Fi='Fiachra:BAAANQADCgEIAQAAAA==.',
Fl='Flogg:BAAANQADCgEIAQAAAA==.',
Fo='Fonzie:BAABNQAECoEhAAIPAAkKzA/tUQAEAgAPAAkKzA/tUQAEAgAAAA==.Foregotten:BAABNQAECoEhAAIKAAkKihYiJQCIAgAKAAkKihYiJQCIAgAAAA==.',
Fr='Frostietute:BAAANQAECgQIDAABNQAECggIIQACALobAA==.',
Fu='Furysmight:BAAANQAECgcIEQAAAA==.',
Ga='Gabrielle:BAAANQADCgcIBwABNQAECgkJGQATAOAhAA==.Gamboa:BAAANQAECgIIAwAAAA==.Gauche:BAAANQAECgUIDwAAAA==.Gazreiale:BAAANQAECgQICQAAAA==.',
Gi='Gimlet:BAAANQADCgUJCAAAAA==.',
Gr='Grass:BAAANQAECgQICQAAAA==.Gravel:BAAANQADCggICQAAAA==.Grÿmm:BAAANQAECgYIDAAAAA==.',
Gu='Guhnz:BAAANQADCgYIBgAAAA==.Guldanica:BAAANQAECgQIBAAAAA==.Gunn:BAAANQADCgUIBAABNQADCgYIBgADAAAAAA==.',
Gw='Gwaine:BAAANQAECgUIBgAAAA==.Gwin:BAAANQAECggIEgAAAA==.Gwyndolín:BAAANQADCgYIBgAAAA==.',
Ha='Hallowed:BAAANQADCggIDAAAAA==.Hamslamwich:BAAANQADCgcIDgABNQAECgQIBgADAAAAAA==.',
He='Hellfyrê:BAAANQAECgIIAgAAAA==.Heritikyldin:BAAANQAECgEIAgAAAA==.Heritikylust:BAAANQAECgcIEwAAAA==.',
Hi='Hibou:BAAANQADCgcIBgAAAA==.',
Ho='Holyhero:BAABNQAECoEkAAIUAAgKwRfeGwBEAgAUAAgKwRfeGwBEAgAAAA==.',
Il='Ilectra:BAABNQAECoEkAAIVAAgKABNvIwANAgAVAAgKABNvIwANAgAAAA==.Illani:BAAANQADCgcIDQAAAA==.',
In='Insanitii:BAAANQABCgQIBgABNQAECgQIBQADAAAAAA==.Intensitii:BAAANQABCgQICQABNQAECgQIBQADAAAAAA==.',
Ip='Ipoopied:BAAANQADCgQJBAAAAA==.',
Is='Ishmara:BAAANQAECgUIBwAAAA==.',
Ja='Jaggoff:BAAANQADCgQJBAAAAA==.Janorune:BAAANQADCgUIBQAAAA==.',
Je='Jeudeu:BAAANQADCgQIBAAAAA==.',
Jt='Jthaka:BAAANQADCgYIBgAAAA==.',
Ka='Kabira:BAAANQADCggIEQAAAA==.Kaimed:BAAANQABCgIIAgAAAA==.Kalyth:BAABNQAECoEoAAMWAAkKMhERdgDWAQAWAAgK8g8RdgDWAQAXAAMKoAqNGgCLAAAAAA==.',
Ke='Keionselin:BAAANQABCgYIBgAAAA==.Kepec:BAAANQADCgYJDQAAAA==.',
Ki='Kilgannon:BAAANQAECgEIAQAAAA==.',
Kr='Krakkd:BAAANQADCgcIBwAAAA==.Krimzonbrezz:BAAANQADCgYICgABNQAECgMIBAADAAAAAA==.Krimzondawn:BAAANQADCgIIAgABNQAECgMIBAADAAAAAA==.Krimzonstorm:BAAANQAECgMIBAAAAA==.',
Ku='Kunaee:BAAANQAECgQIBgAAAA==.',
Ky='Kyrius:BAAANQAECgcIDgAAAA==.',
['Kì']='Kìku:BAAANQAECgUIEgAAAA==.',
La='Lausia:BAAANQAECgUIEgABNQAECggIJAAVAAATAA==.',
Ld='Ldyrose:BAAANQADCggIHgAAAA==.',
Le='Leilarose:BAAANQABCgcIBwAAAA==.Lewtiefroopz:BAAANQAECgUIDgAAAA==.',
Li='Lilblade:BAAANQABCgcJDQABNQABCggIEQADAAAAAA==.',
Lo='Lottathicc:BAAANQADCgMIAwAAAA==.',
Lu='Lusande:BAAANQADCgUJAgAAAA==.',
Ly='Lyren:BAAANQADCgMIAwAAAA==.',
['Lì']='Lìlìth:BAAANQADCgYIBgAAAA==.',
['Lï']='Lïghthammer:BAAANQADCggJCAABNQADCggIHwADAAAAAA==.',
Ma='Macabre:BAAANQAECgUIEgAAAA==.Magnificò:BAAANQAECgUIEgAAAA==.Makani:BAAANQAECgUICgAAAA==.Malarix:BAAANQADCgUJBQABNQADCgYIBgADAAAAAA==.Malory:BAABNQAECoEZAAITAAkK4CHvAwA2AwATAAkK4CHvAwA2AwAAAA==.Malzahär:BAABNQAECoEaAAQYAAkKDyGqGgCPAQAWAAcKfiHHRQBkAgAYAAUKpRyqGgCPAQAXAAMKax1rFADXAAAAAA==.Maress:BAAANQABCgEIAQAAAA==.Marician:BAAANQAECgEIAgAAAA==.Matadore:BAAANQADCgYIBgAAAA==.',
Mi='Miniraven:BAAANQAECgUIBQAAAA==.Missluna:BAAANQADCgYIBgAAAA==.',
Mo='Mooyouhapee:BAAANQADCgQIBAAAAA==.Mortìs:BAAANQABCgQIBAAAAA==.',
Mu='Muahahaha:BAAANQAECgQIBgAAAA==.Muffintop:BAAANQAECgUIEgAAAA==.',
My='Mythalyn:BAAANQADCgYIBgAAAA==.Mythoros:BAAANQADCggJCAAAAA==.Mythrondrir:BAAANQAECgcIEgAAAA==.Mythundas:BAAANQADCgYIBgAAAA==.',
['Mø']='Møurningsøul:BAAANQABCggIEgABNQADCggIHwADAAAAAA==.',
Ne='Neosnÿper:BAABNQAECoEbAAMZAAgKihcGIQD0AQAZAAcKYxYGIQD0AQAKAAcKLBH/QwC2AQABNQAECgkJKgAWAN4fAA==.',
Ni='Nielic:BAABNQAECoEYAAMaAAgKehniLACVAgAaAAgKehniLACVAgAbAAMKuAd9GQCFAAAAAA==.Nimbus:BAAANQADCggICAABNQAFFAcIEAAPAOMXAA==.Ninjato:BAAANQADCgIIAgAAAA==.',
No='Nobops:BAAANQADCggICAAAAA==.Norrahh:BAAANQAECgIIAgAAAA==.Nozzle:BAAANQADCgYIBgAAAA==.',
Om='Omgitsmagic:BAAANQAECgQIBAAAAA==.',
On='Ongo:BAABNQAECoEcAAICAAgKIAwnyADQAQACAAgKIAwnyADQAQAAAA==.',
Or='Orion:BAAANQAECgcIDQAAAA==.',
Pa='Palapoxi:BAABNQAECoEnAAIcAAkKzCAkDwBDAwAcAAkKzCAkDwBDAwAAAA==.Pallybugge:BAAANQABCgEIAQAAAA==.',
Pe='Penelopè:BAABNQAECoEnAAIMAAkKeiS0AQCWAwAMAAkKeiS0AQCWAwAAAA==.Penelópe:BAAANQADCgEIAQABNQAECgkJJwAMAHokAA==.Penný:BAAANQAECgIIAgABNQAECgkJJwAMAHokAA==.Pepino:BAAANQAECgQICwAAAA==.',
Ph='Phinx:BAABNQAECoEcAAIdAAkKmBi0NgAoAgAdAAkKmBi0NgAoAgAAAA==.Phocheux:BAABNQAECoEaAAIeAAYKmhtKFQDqAQAeAAYKmhtKFQDqAQAAAA==.Phulgoth:BAAANQAECgMIAwAAAA==.',
Pi='Pierogi:BAAANQAECgMIAwAAAA==.Pippersy:BAAANQADCggJFAAAAA==.Piston:BAAANQAECgIIAwAAAA==.',
Po='Poco:BAAANQAECggIBAAAAA==.Poetrii:BAAANQAECgQIBQAAAA==.Pomickyal:BAAANQAECgUIEgAAAA==.Ponn:BAAANQAECgEIAQAAAA==.',
Ps='Pshamanthe:BAAANQADCggIHQAAAA==.',
Qu='Quantumleaf:BAAANQADCgQIBAAAAA==.',
Ra='Raeline:BAAANQADCgcIFAAAAA==.Ragnärok:BAABNQAECoEXAAIOAAkKPRVhTgD+AQAOAAkKPRVhTgD+AQAAAA==.',
Re='Reelwor:BAAANQAECgMIBQAAAA==.Rendskaar:BAACNQAFFIESAAIHAAUKwRfUCwBqAQAHAAUKwRfUCwBqAQA1AAQKgSoAAgcACQpNIikJAGIDAAcACQpNIikJAGIDAAAA.Reverii:BAAANQABCgYICAABNQAECgQIBQADAAAAAA==.Rezelda:BAAANQAECgMIAwAAAA==.',
Rj='Rj:BAAANQAECgUICgAAAA==.',
Ro='Roughbbq:BAAANQADCgEIAQABNQAECgYIDQADAAAAAA==.',
Rt='Rtpopham:BAAANQAECgQIBgAAAA==.',
['Rá']='Rándy:BAAANQAECgQIBAAAAA==.',
Sa='Saikus:BAAANQAECgUIEQAAAA==.Sandros:BAAANQADCgUIAwAAAA==.Saphrin:BAAANQAECgUIDwAAAA==.Sardiirn:BAAANQAECgEIAwABNQAECgUIDAADAAAAAA==.',
Sc='Scarfiend:BAAANQADCgMIAwAAAA==.Scurus:BAAANQAECgQIEAAAAA==.',
Se='Selynne:BAABNQAECoEkAAISAAkKvyHSNADYAgASAAkKvyHSNADYAgAAAA==.',
Sh='Shamanizeds:BAAANQAECgUIDAAAAA==.Shamwisegamg:BAAANQADCgYIBgAAAA==.Shankems:BAAANQAECgIIAgAAAA==.Sheezee:BAAANQABCgUIBQAAAA==.Shifted:BAABNQAECoEbAAIFAAgKnAu7HgBjAQAFAAgKnAu7HgBjAQAAAA==.Shotgirl:BAAANQADCgEIAQAAAA==.',
Si='Siggie:BAAANQADCgYIDQAAAA==.Sindorei:BAAANQADCgMIAwAAAA==.Sixligma:BAAANQAECgQIDQAAAA==.',
Sk='Skye:BAAANQADCggICwABNQAECgkJIQAKAIoWAA==.',
Sl='Slorrin:BAABNQAECoElAAIBAAkKSSVECgCdAwABAAkKSSVECgCdAwAAAA==.',
So='Solazreiale:BAAANQAECgQIBgAAAA==.Somers:BAAANQADCggIHwAAAA==.Soulistic:BAAANQABCggIHQAAAA==.',
Sp='Spellbind:BAAANQAECgQIBgAAAA==.',
St='Starstorms:BAAANQAECgUIEgAAAA==.Starweaver:BAAANQABCgIIAgAAAA==.',
Su='Suun:BAAANQADCgQIAwAAAA==.',
Sy='Sylvas:BAAANQADCgUIBgAAAA==.Syniz:BAAANQAECgQIBAAAAA==.',
Ta='Taie:BAAANQAECgQIDAAAAA==.Taiez:BAAANQAECgUIDgAAAA==.Tanlia:BAAANQADCgYIBgAAAA==.Tauming:BAAANQAECgIIAwAAAA==.',
Te='Teshala:BAAANQAECgQIBQAAAA==.',
Th='Tharil:BAAANQABCgQJBgAAAA==.Thedarklørd:BAAANQAECgQIBAAAAA==.Thenakedcow:BAAANQADCgEIAQAAAA==.Therapii:BAAANQABCgQIBQABNQAECgQIBQADAAAAAA==.Thesledge:BAABNQAECoEfAAISAAgKBxYLcAAhAgASAAgKBxYLcAAhAgAAAA==.',
Ti='Tifalockhàrt:BAABNQAECoEiAAIcAAkKegXHcACeAQAcAAkKegXHcACeAQAAAA==.Timewarped:BAABNQAECoEcAAICAAgKIxL2pQAVAgACAAgKIxL2pQAVAgAAAA==.',
Tr='Trapsin:BAABNQAECoEjAAICAAkKniERKwAvAwACAAkKniERKwAvAwAAAA==.Treeage:BAABNQAECoEjAAQLAAkKQBKOCwA+AgALAAkKQBKOCwA+AgAKAAIKSQQlmgBCAAAFAAEKtgRHUAAtAAAAAA==.Trufflé:BAAANQAECgUIEgAAAA==.Trustportal:BAAANQADCggIGQABNQAECgUICgADAAAAAA==.Tryniti:BAAANQADCgIIAgAAAA==.',
Ty='Tyg:BAABNQAECoEgAAIfAAkKsSGyFADEAgAfAAkKsSGyFADEAgAAAA==.',
Un='Unholychow:BAAANQADCgYIBgAAAA==.Uny:BAAANQAECgIIAgABNQAECggIJAAVAAATAA==.',
Us='Usdaprime:BAAANQAECgMIBQAAAA==.',
Va='Valstan:BAAANQAECgQIBAAAAA==.Valzyn:BAAANQAECgcICgAAAA==.',
Ve='Velanora:BAAANQADCgQIBwAAAA==.Verdantclaw:BAAANQABCggICwAAAA==.',
Vi='Vivix:BAABNQAECoEnAAMUAAkK9RSMIAAOAgAUAAgKERaMIAAOAgAaAAYKjRAefwBhAQAAAA==.',
Vo='Voidedknight:BAAANQADCggICAAAAA==.',
Wa='Wapoxi:BAAANQAECgEIAQABNQAECgkJJwAcAMwgAA==.Warisfluffy:BAAANQAECgYIDwAAAA==.',
We='Welshie:BAAANQADCgEIAQAAAA==.Westnasty:BAAANQADCgEJAQAAAA==.',
Wo='Worldboss:BAAANQAECgYICQAAAA==.Worldwar:BAAANQAECgUIDgAAAA==.',
Wr='Wradalin:BAABNQAECoEbAAIfAAgKdx75IwBDAgAfAAgKdx75IwBDAgAAAA==.Wraithstorm:BAAANQAECgQIBAAAAA==.',
Yo='Yoshima:BAAANQADCgEIAQAAAA==.',
Yu='Yunera:BAAANQAECgEIAQAAAA==.',
Za='Zalor:BAAANQABCgYIBAAAAA==.Zarila:BAAANQAECgQIBQAAAA==.Zartain:BAAANQAECgUIEgAAAA==.',
Ze='Zenizho:BAAANQAECgEIAQAAAA==.Zennamite:BAAANQAECgUIDgAAAA==.',
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
