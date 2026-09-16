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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Mage-Arcane','Mage-Frost','Priest-Holy','Warrior-Arms','Shaman-Restoration','Evoker-Devastation','DeathKnight-Frost',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-09-15',data={Aa='Aaravos:BAAANQAECgIIAgAAAA==.Aatrøx:BAAANQAECgIIAwAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQADCgYIBgAAAA==.',
Ae='Aeirith:BAAANQAECgYIDgAAAA==.',
Ai='Airius:BAAANQADCgYIBwAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAgAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAAANQADCggIFAAAAA==.Amarasu:BAAANQADCggIGwAAAA==.Amarlly:BAAANQADCggIGwAAAA==.',
An='Ancelina:BAAANQADCggIGgAAAA==.Anderton:BAAANQAECgQICQAAAA==.Andilocks:BAAANQADCgYIEgAAAA==.Anditracks:BAAANQADCgUICQAAAA==.Andraenei:BAAANQADCgYIBgAAAA==.Andrela:BAAANQADCgYIBwAAAA==.Aneira:BAAANQAECgEIAQAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAAANQAECgcIDQAAAA==.Archérhiro:BAACNQAFFIEFAAIBAAMJiBYqAwAnAQABAAMJiBYqAwAnAQA1AAQKgSEAAgEACQlLIwMEAJIDAAEACQlLIwMEAJIDAAAA.Arillann:BAAANQAECgUICQAAAA==.Arin:BAAANQAECgIIAgABNQAECgQIBAACAAAAAA==.Arrook:BAAANQADCgYIBgAAAA==.Artdemsamis:BAAANQAECggIDwAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgMIAwACAAAAAA==.Ashylock:BAAANQADCgUIBQABNQAECgkJHAADAL8RAA==.Ashymage:BAABNQAECoEcAAMDAAkJvxH/TABlAgADAAkJLBH/TABlAgAEAAEJ0wrqJAA+AAAAAA==.Askevar:BAAANQAECgIIAgAAAA==.Asriél:BAAANQADCgEIAQABNQAECgUICQACAAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQADCgYIBgABNQAECgkJHQAFAFYUAA==.',
At='Atlassian:BAAANQAECgIIAgAAAA==.',
Az='Azaleah:BAAANQAECgQIBwAAAA==.Azraesha:BAAANQAECgEIAQAAAA==.Azureflamez:BAAANQADCgMIAwAAAA==.',
Be='Beareold:BAAANQADCgYIBwAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQIBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIBAAAAA==.Bigmon:BAABNQAECoEeAAIGAAgJphiKNwBbAgAGAAgJphiKNwBbAgAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgEIAQAAAA==.Blackstaff:BAAANQADCgIIAgAAAA==.Bloodygrundl:BAAANQAECgUICQAAAA==.Bluestorm:BAAANQADCggICAAAAA==.',
Bo='Bonegrinda:BAAANQAECgYICgAAAA==.Boogy:BAAANQADCgEIAQAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwACAAAAAA==.',
Br='Branwynn:BAAANQADCgYIBwAAAA==.Bringg:BAAANQADCgYIBgAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Callmemommy:BAAANQADCgUIDAAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQABCgcIBwAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAABNQAECoEbAAIHAAkJuiR6AgCfAwAHAAkJuiR6AgCfAwAAAA==.Chantix:BAAANQADCgMIAwAAAA==.Chaosshadow:BAAANQAECgIIAgAAAA==.Chaosti:BAAANQAECgMIBQAAAA==.Cheekymonkey:BAAANQAECgUICQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgYICwACAAAAAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQADCgYIBgABNQAECgIIBAACAAAAAA==.',
Co='Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAAANQAECgQIDgAAAA==.Crosslock:BAAANQADCgUIBwAAAA==.',
Cu='Cuack:BAAANQADCgQIBAAAAA==.',
Cy='Cynnari:BAAANQAECgIIAgAAAA==.',
Da='Dagnabit:BAAANQADCggIEgAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAAANQAECgEIAQABNQAECgMIAwACAAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgQICAAAAA==.Dartian:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.',
De='Deeptroat:BAAANQADCgEIAQABNQADCggIGwACAAAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAAANQAECgQIBgAAAA==.',
Di='Dibick:BAAANQABCgQIBAAAAA==.Dictaiter:BAAANQAECgMIAwAAAA==.Diltlish:BAAANQAECgEIAQAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAAANQAECgcIDQAAAA==.',
Dm='Dmginc:BAAANQADCgUIBgAAAA==.',
Do='Doeblin:BAAANQADCgYIEQAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQABCgIIAgAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Dragonflai:BAAANQAECgUIBgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQADCgQIBAAAAA==.Drakkei:BAAANQAECgMIAwABNQAECgUIBgACAAAAAA==.Drshortbus:BAAANQADCgYICwAAAA==.Drylo:BAEANQAECggICQAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQADCgYIDgAAAA==.',
El='Elarol:BAAANQADCgYIBgAAAA==.Elray:BAAANQADCgYIDAAAAA==.',
Em='Emeralde:BAAANQABCgYICgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgEIAQAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erfinden:BAAANQADCgIIAgAAAA==.',
Es='Espers:BAAANQAECgQICAAAAA==.',
Et='Ethellin:BAAANQAECgIIAwAAAA==.',
Eu='Euph:BAAANQADCgcIEQAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgEIAQABNQAECgYIDwACAAAAAA==.Feedmepizzas:BAAANQAECgEIAgAAAA==.Feildmedic:BAAANQADCgIIAgABNQAECgQIBQACAAAAAA==.Feleria:BAAANQADCgUIBQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQADCgIIAgAAAA==.',
Fl='Fluxarata:BAAANQADCgcIDQAAAA==.',
Fr='Fred:BAAANQADCgcIFwAAAA==.Friendly:BAAANQAECggICQAAAA==.Frightrice:BAAANQAECgMIBQAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.',
['Fï']='Fïzzle:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.',
Ga='Gabel:BAAANQADCggICAAAAA==.Gablyn:BAAANQAECgUIBgAAAA==.Gardyson:BAAANQAECgUICAAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Go='Gojira:BAAANQABCgQIBQAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAAANQAECgIIBAAAAA==.',
Ha='Hauteliotie:BAAANQAECgIIBAAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
He='Hefty:BAAANQAECgQIBQAAAA==.Hellsspawn:BAAANQADCgQIBQAAAA==.',
Ho='Hokàge:BAAANQAECgYICwAAAA==.Homealone:BAAANQAECgMIAwAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huntinfuzzy:BAAANQAECgUICAAAAA==.',
Hy='Hymncarrey:BAAANQAECgIIAwAAAA==.',
Ig='Igothots:BAAANQAECgQIBAABNQAECgUIBQACAAAAAA==.',
Ir='Irritable:BAAANQAECgQIBQAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQADCggIGwACAAAAAA==.',
Ja='Jackyll:BAAANQAECgcIAwAAAA==.Jatix:BAAANQAECgQIBAAAAA==.Jawzlyn:BAAANQADCgYIBwAAAA==.',
Je='Jellytown:BAAANQAECgUICQAAAA==.Jessiana:BAAANQADCgcICwAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBQAAAA==.',
Jp='Jpeppers:BAAANQAECgEIAQAAAA==.',
Ju='Juicylucy:BAAANQADCgQIBAAAAA==.Jundra:BAAANQADCgIIAgAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.',
['Jô']='Jôhnwick:BAAANQAECgUICQAAAA==.',
Ka='Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAAANQAECgUICQAAAA==.Kashmir:BAAANQADCgQIBAAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Kh='Khota:BAAANQAECgEIAQAAAA==.',
Ko='Koldfront:BAAANQADCgQIBAAAAA==.Kollinator:BAAANQADCgcIDQAAAA==.',
Ku='Kurtina:BAAANQAECgQIBgAAAA==.',
Ky='Kyyell:BAAANQADCgYIBgAAAA==.',
La='Lafty:BAAANQAECgMIAwAAAA==.',
Le='Leddy:BAAANQADCgUIBwAAAA==.Leif:BAAANQAECgUICQAAAA==.Lemmart:BAAANQADCggIGQAAAA==.Lenik:BAAANQADCggIEwAAAA==.',
Li='Licorice:BAAANQAECgIIBAAAAA==.Lieree:BAAANQAECgUICwAAAA==.Limosfire:BAAANQADCgQIBwAAAA==.',
Lo='Lockty:BAAANQABCgQIBAABNQAECgMIAwACAAAAAA==.Logi:BAAANQADCgIIAgAAAA==.Longtotem:BAAANQAECgIIAgAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAAANQAECgIIAwAAAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgUIDQAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lunà:BAAANQAECgEIAQAAAA==.',
Ly='Lystral:BAAANQAECgEIAQAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgQIBAAAAA==.',
Ma='Magickul:BAAANQAECgQIBwAAAA==.Manadâr:BAAANQAECgEIAQAAAA==.Marinas:BAAANQADCgQICgAAAA==.Maru:BAAANQADCgYIBgAAAA==.Mazumaragg:BAAANQADCgIIBAABNQAECgUICAACAAAAAA==.',
Mi='Miande:BAAANQAECgIIAgAAAA==.Microburst:BAAANQAECgUIDQAAAA==.Minilock:BAAANQAECgUIBQAAAA==.Missleading:BAAANQABCgEIAQAAAA==.Missused:BAAANQABCgIIAwAAAA==.Miyagifu:BAAANQADCgIIAgAAAA==.Mièlikki:BAAANQADCggICAAAAA==.',
Mo='Mongermook:BAAANQAECgQIBQAAAA==.Monnkysham:BAAANQADCgYIBgAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAgAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAAANQAECgQIBAAAAA==.Nacronor:BAAANQADCgYIEAAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgEIAQAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCgYIBgAAAA==.Nexedo:BAAANQADCgEIAQAAAA==.',
Ni='Nickatnite:BAAANQADCgEIAQAAAA==.Nickelodeon:BAAANQADCgMIAwAAAA==.Nightgear:BAABNQAECoE5AAIBAAgJHx8gFwDAAgABAAgJHx8gFwDAAgAAAA==.Nixeava:BAAANQADCgYICwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAAANQAECgUIBgAAAA==.',
Od='Ode:BAAANQAECgQIBAAAAA==.Odex:BAAANQAECgEIAQAAAA==.',
On='Onlymages:BAAANQAECgQIBQAAAA==.Onos:BAAANQAECgQIBwAAAA==.',
Or='Orinin:BAAANQAECgQIBQAAAA==.',
Ou='Outkíll:BAAANQAECgUIBgAAAA==.',
Pa='Pally:BAAANQADCgcIDgAAAA==.Pathogen:BAAANQAECgUICQAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAAANQAECgQIBAAAAA==.Perve:BAAANQAECgUICQAAAA==.',
Pf='Pfchen:BAAANQADCgMIAQAAAA==.',
Pi='Pippy:BAAANQADCgYIBgAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQADCgQIBgAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgIIAgAAAA==.Promethèus:BAAANQAECgUICgAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAAANQAECgUICQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggICgAAAA==.Rainlette:BAAANQADCggIEwAAAA==.Rainsvoker:BAABNQAECoEpAAIIAAgJjBOGCwA4AgAIAAgJjBOGCwA4AgAAAA==.Ramike:BAAANQAECgUICQAAAA==.Randal:BAAANQABCgIIAgAAAA==.',
Re='Reaveldahar:BAAANQADCgUIBwAAAA==.Recovery:BAAANQADCgcIBwAAAA==.Reddan:BAAANQAECgQIBwAAAA==.Rei:BAAANQADCgUIBQAAAA==.Revy:BAAANQAECgIIAgAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rit:BAAANQADCggICAAAAA==.Ritzon:BAAANQAECgUICQAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgIIAwACAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAgAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQADCgYICAAAAA==.',
Sh='Shan:BAAANQAECgYICQAAAA==.Shaxx:BAAANQAECgYICQAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Si='Sieya:BAAANQADCgUIBQAAAA==.Sinarria:BAAANQADCgUIBQAAAA==.',
Sk='Skullace:BAAANQAECgEIAQAAAA==.Skylette:BAAANQADCgUIBQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.',
Sn='Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgEIAQABNQAECgUICAACAAAAAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.',
Sp='Sparthos:BAAANQAECgQICwAAAA==.Springbuck:BAAANQABCgIIAgAAAA==.',
Sr='Srfreaky:BAAANQADCgYIEQAAAA==.',
St='Stepbrogon:BAAANQADCgIIAgAAAA==.Sterlìng:BAAANQAECgUICQAAAA==.Stocklock:BAAANQADCgMIAwAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgUICAACAAAAAA==.Tatari:BAAANQADCgUIBQABNQADCggIFAACAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAAANQAECgUICQAAAA==.Tellanna:BAAANQAECgIIAgAAAA==.Tensuken:BAAANQAECgIIAgAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgEIAQAAAA==.',
Th='That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgQIBAAAAA==.Thebran:BAAANQADCggIEAAAAA==.Thejuiciest:BAAANQAECgIIAgAAAA==.Theunclepaul:BAAANQAECgQIBQAAAA==.',
Ti='Tiarl:BAAANQAECgcIEgAAAA==.Tinydots:BAAANQAECgEIAQAAAA==.',
To='Tom:BAAANQADCgIIAgAAAA==.Toniichopper:BAAANQAECgEIAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQADCgQICwAAAA==.',
Tr='Trimble:BAAANQABCgYIBAAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.',
Ty='Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAAANQAECgEIAgAAAA==.',
Va='Valakk:BAAANQADCgUIBgAAAA==.Valsitril:BAAANQAECgMIAwAAAA==.Vanara:BAAANQABCggICgAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgMIAwACAAAAAA==.',
Ve='Velsetin:BAAANQADCgQIBAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgYIEAABNQAECgQICAACAAAAAA==.',
Vi='Vicas:BAAANQAECgIIAgAAAA==.Vipbull:BAAANQADCgUIBQAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Wa='Warded:BAAANQADCgcIBwAAAA==.',
We='Wesjenks:BAAANQADCgYIBwAAAA==.',
Wh='Whisperwindd:BAAANQADCgcIEgAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQADCgEIAQAAAA==.',
Wi='Wilco:BAAANQAECggIAQAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQADCggIFAACAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAAAAA==.',
Ya='Yaerin:BAAANQAECgYICwAAAA==.Yaoi:BAAANQAECgUIDQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQADCgIIAgAAAA==.',
Yu='Yuukon:BAAANQAECgQIBgAAAA==.',
Za='Zackman:BAAANQADCgEIAQAAAA==.Zadira:BAABNQAECoEeAAIJAAkJjBmdCgCwAgAJAAkJjBmdCgCwAgAAAA==.Zadirasham:BAAANQADCgYIBgABNQAECgkJHgAJAIwZAA==.',
Ze='Zephrylia:BAAANQADCgYIDwAAAA==.',
Zu='Zuriel:BAAANQAECgIIAgAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgIIAgAAAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQADCggIFAAAAA==.',
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
