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

local lookup = {'Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Mage-Frost','Priest-Holy','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Evoker-Devastation','DeathKnight-Frost',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aaravos:BAAANQAECgQJBAAAAA==.Aatrøx:BAAANQAECgIIAwAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQADCgYIBgAAAA==.',
Ae='Aeirith:BAAANQAECgYIEwAAAA==.',
Ai='Ailsà:BAAANQADCgIJAgABNQAECgEJAQABAAAAAA==.Airius:BAAANQADCgYIBwAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMJAwAAAA==.',
Am='Amalthia:BAAANQADCggJFAAAAA==.Amarasu:BAAANQAECgEJAQAAAA==.Amarlly:BAAANQAECgIIAgAAAA==.',
An='Ancelina:BAAANQAECgEIAQAAAA==.Anderton:BAAANQAECgQJDAAAAA==.Andilocks:BAAANQADCgYIEgAAAA==.Anditracks:BAAANQADCgUJDgAAAA==.Andraenei:BAAANQADCgYJDAAAAA==.Andrela:BAAANQADCgYJBwAAAA==.Aneira:BAAANQAECgEJAQAAAA==.',
Ap='Applefritter:BAAANQADCgYJBgABNQAECgIJBgABAAAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECoEVAAICAAgKdR9WEgDSAgACAAgKdR9WEgDSAgAAAA==.Archmedies:BAAANQABCgYICQAAAA==.Archérhiro:BAACNQAFFIEGAAMDAAQKiBEYBwAdAQADAAMKiBYYBwAdAQAEAAEKhgK5FwA9AAA1AAQKgSoAAwMACQpLI50HAHQDAAMACQpLI50HAHQDAAQAAwqIEjk8AMkAAAAA.Arillann:BAAANQAECgYJDwAAAA==.Arin:BAAANQAECgQIBgABNQAECgQJCAABAAAAAA==.Arms:BAAANQABCgEIAQAAAA==.Arrook:BAAANQADCgYIBgAAAA==.Artdemsamis:BAAANQAECggJEAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgABAAAAAA==.Ashylock:BAAANQAECgQJBAABNQAECgkJJQAFAFQbAA==.Ashymage:BAABNQAECoElAAMFAAkKVBtFKgASAwAFAAkKVBtFKgASAwAGAAEK0wphLgA7AAAAAA==.Askevar:BAAANQAECgMJBQAAAA==.Asriél:BAAANQAECgYIBgAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgEJAQABNQAECgkJJAAHAFYUAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.',
Az='Azaleah:BAAANQAECgYJDQAAAA==.Azraesha:BAAANQAECgUIBgAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Be='Beareold:BAAANQADCgYIBwAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIBQAAAA==.Bigmon:BAABNQAECoEpAAIIAAgKeR0GMgChAgAIAAgKeR0GMgChAgAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgEJAQAAAA==.Blackstaff:BAAANQADCggJCgAAAA==.Blessthefall:BAAANQAECgQJBAAAAA==.Bloodygrundl:BAAANQAECgYJDwAAAA==.Bluestorm:BAAANQADCggICAAAAA==.',
Bo='Bonegrinda:BAAANQAECgYJDwAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwABAAAAAA==.',
Br='Branwynn:BAAANQADCgYJBwAAAA==.Bringg:BAAANQADCgYIBgAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Callmemommy:BAAANQADCgUJDgAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQADCggICAAAAA==.Ceri:BAAANQAECggJAQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFIEJAAIJAAUKvR0hAwDdAQAJAAUKvR0hAwDdAQA1AAQKgR0AAgkACQq6JFYEAIoDAAkACQq6JFYEAIoDAAAA.Chantix:BAAANQADCgMIAwAAAA==.Chaosshadow:BAAANQAECgIIBAAAAA==.Chaosti:BAAANQAECgUJCgAAAA==.Cheekymonkey:BAAANQAECgYIDwAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Christy:BAAANQADCgIJAgAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQADCggJCgABNQAECgIJBgABAAAAAA==.',
Co='Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAAANQAECgQJEgAAAA==.Crosslock:BAAANQADCgUIBwAAAA==.',
Cu='Cuack:BAAANQADCgQIBAAAAA==.',
Cy='Cynnari:BAAANQAECgMIBgAAAA==.',
Da='Dagnabit:BAAANQADCggIFAAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAAANQAECgUJBgABNQAECgUJCAABAAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgQJCAAAAA==.Dartian:BAAANQAECgMJAwABNQAECgQIBwABAAAAAA==.',
De='Deathmare:BAAANQAECgYIBgAAAA==.Deeptroat:BAAANQADCgEIAQABNQAECgEJAQABAAAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAAANQAECgQICgAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAAANQAECgMIAwAAAA==.Diltlish:BAAANQAECgIIAgAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAAANQAECgcJEAAAAA==.',
Dm='Dmginc:BAAANQAECgEJAQAAAA==.',
Do='Doeblin:BAAANQADCgYJFwAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgIJAgAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Dragonflai:BAAANQAECgYJDAAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQADCgQJBAAAAA==.Drakkei:BAAANQAECgQJBgABNQAECgYIDAABAAAAAA==.Drshortbus:BAAANQADCgYJEQAAAA==.Drylo:BAEANQAECggIDwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQADCgYJFAAAAA==.',
El='Elarol:BAAANQADCgYIBgAAAA==.Elray:BAAANQADCggJDwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgEJAQAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erfinden:BAAANQADCgIIAgAAAA==.',
Es='Espers:BAAANQAECgYJDgAAAA==.',
Et='Ethellin:BAAANQAECgUJCAAAAA==.',
Eu='Euph:BAAANQADCgcIEQAAAA==.',
Ev='Evilhearts:BAAANQADCgcJBwAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgEIAQABNQAECggIGwAKAJQjAA==.Feedmepizzas:BAAANQAECgEJAwAAAA==.Feildmedic:BAAANQADCgMJBAABNQAECgUJCgABAAAAAA==.Feleria:BAAANQADCgUJBQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQADCgIIAgAAAA==.',
Fl='Fluxarata:BAAANQAECgQJBAAAAA==.',
Fr='Fred:BAAANQAECgEJAQAAAA==.Friendly:BAAANQAECggIEAAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.',
['Fï']='Fïzzle:BAAANQAECgEJAQABNQAECgEJAQABAAAAAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAAANQAECgYJDAAAAA==.Gardyson:BAAANQAECgYJDAAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Go='Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAAANQAECgUJCQAAAA==.Grenadeout:BAAANQAECgEIAQAAAA==.',
Ha='Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQABAAAAAA==.',
He='Hefty:BAAANQAECgUJCgAAAA==.Hellsspawn:BAAANQADCgUJCgAAAA==.',
Ho='Hokàge:BAAANQAECgcIEgAAAA==.Homealone:BAAANQAECgMIAwAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huntinfuzzy:BAAANQAECgYICwAAAA==.',
Hy='Hymncarrey:BAAANQAECgQIBwAAAA==.',
Ig='Igothots:BAAANQAECgQIBAABNQAECgYJBgABAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAAANQAECgQIBQAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECgEJAQABAAAAAA==.',
Ja='Jackyll:BAAANQAECgcJBwAAAA==.Jatix:BAAANQAECgcJCwAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgEIAQABAAAAAA==.',
Je='Jellytown:BAAANQAECgYIDwAAAA==.Jelorinea:BAAANQADCgYJBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgEJAQAAAA==.',
Ju='Juicylucy:BAAANQADCgQIBAAAAA==.Jundra:BAAANQADCgIIAgAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCgUIBQAAAA==.',
['Jô']='Jôhnwick:BAAANQAECgYJCgAAAA==.',
Ka='Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAAANQAECgYJDwAAAA==.Kashmir:BAAANQADCgUJCQAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Kh='Khota:BAAANQAECgEIAQABNQAECgQIBAABAAAAAA==.',
Ko='Koldfront:BAAANQADCgQICAAAAA==.Kollinator:BAAANQADCggJDQAAAA==.',
Ku='Kurtina:BAAANQAECgQJCgAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAAANQAECgMJAwAAAA==.',
Le='Leddy:BAAANQADCgUJCQAAAA==.Leif:BAAANQAECgYJDwAAAA==.Lemmart:BAAANQAECgQJBAAAAA==.Lenik:BAAANQAECgMJAwAAAA==.',
Li='Licorice:BAAANQAECgIJBgAAAA==.Lieree:BAAANQAECgUICwAAAA==.Limosfire:BAAANQADCgQIBwAAAA==.',
Lo='Lockty:BAAANQAECgEJAQABNQAECgMJAwABAAAAAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAAANQAECgIJAwAAAA==.Lucity:BAAANQAECgIJAgABNQAECgcJCwABAAAAAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgUJDQAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQABAAAAAA==.Lunà:BAAANQAECgEIAQAAAA==.',
Ly='Lystral:BAAANQAECgEJAQAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUICQAAAA==.',
Ma='Magdalena:BAAANQAECgEIAQAAAA==.Mageyboi:BAAANQADCgMJAwABNQAECgcIEgABAAAAAA==.Magickul:BAAANQAECgQIBwAAAA==.Manadâr:BAAANQAECgEIAQAAAA==.Marinas:BAAANQADCgUJDwAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgEJAgAAAA==.Mazumaragg:BAAANQADCgIIBAABNQAECgYJDAABAAAAAA==.',
Mi='Miande:BAAANQAECgQJBgAAAA==.Microburst:BAAANQAECgUJEgAAAA==.Minilock:BAAANQAECgYJCwAAAA==.Missdeeds:BAAANQABCgQJBAAAAA==.Missleading:BAAANQABCgEJAQAAAA==.Missused:BAAANQABCgIJAwAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUJCgABAAAAAA==.Mièlikki:BAAANQADCggJEAAAAA==.',
Mo='Mongermook:BAAANQAECgUICgAAAA==.Monnkysham:BAAANQADCgYJBgAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAAANQAECgUJCQAAAA==.Nacronor:BAAANQADCgYJFgAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgEIAgAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCgYIDQAAAA==.Nexedo:BAAANQADCgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBAAAAA==.Nickelodeon:BAAANQAECgQIBAAAAA==.Nightgear:BAACNQAFFIEGAAIDAAQKeg12BQBWAQADAAQKeg12BQBWAQA1AAQKgT4AAgMACQoBHk4aANwCAAMACQoBHk4aANwCAAAA.Nixeava:BAAANQADCgYICwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAAANQAECgYIDAAAAA==.',
Od='Ode:BAAANQAECgYJCgAAAA==.Odex:BAAANQAECgEIAQAAAA==.',
On='Onlymages:BAAANQAECgQICAAAAA==.Onos:BAAANQAECgQJCwAAAA==.',
Or='Orinin:BAAANQAECgUJCgAAAA==.',
Ou='Outkíll:BAAANQAECgUIBgAAAA==.',
Pa='Pally:BAAANQAECgQIBAAAAA==.Pandarweb:BAAANQADCgUJBQAAAA==.Pathogen:BAAANQAECgYJDwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAAANQAECgQJCAAAAA==.Perve:BAAANQAECgUJCQABNQAECgYIBgABAAAAAA==.',
Pf='Pfchen:BAAANQADCgQJAgAAAA==.',
Pi='Pippy:BAAANQADCgYJBgAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEJAQAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgIIAgAAAA==.Promethèus:BAAANQAECgYJCwAAAA==.',
Qo='Qoheleth:BAAANQAECgUJCgAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAAANQAECgUICQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgEIAQAAAA==.Rainsvoker:BAABNQAECoE6AAILAAkKDBnoBgDgAgALAAkKDBnoBgDgAgAAAA==.Ramike:BAAANQAECgcJEAAAAA==.Randal:BAAANQABCgIIAgAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQADCgcIBwAAAA==.Reddan:BAAANQAECgQICgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgcIEgABAAAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rit:BAAANQADCggICAAAAA==.Ritzon:BAAANQAECgYJDwAAAA==.',
Rr='Rrook:BAAANQADCgIJAgAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgQIBwABAAAAAA==.Rykken:BAAANQADCggICAABNQAECgIIAgABAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQADCgcIDwAAAA==.',
Sh='Shan:BAAANQAECgcIDwAAAA==.Shaxx:BAAANQAECgcJDwAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAAANQADCgYIBgABNQAECgIJAwABAAAAAA==.',
Si='Sieya:BAAANQADCgYJCwAAAA==.Sinarria:BAAANQADCgUICAAAAA==.',
Sk='Skullace:BAAANQAECgEIAQAAAA==.Skylette:BAAANQADCggJDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.',
Sn='Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgEIAQABNQAECgYJDAABAAAAAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.',
Sp='Sparthos:BAAANQAECgUJEAAAAA==.Springbuck:BAAANQABCgIJAgAAAA==.',
Sr='Srfreaky:BAAANQADCgYJFwAAAA==.',
St='Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAAANQAECgUJDgAAAA==.Stocklock:BAAANQADCgQJBgAAAA==.Stormblessed:BAAANQADCgQJBAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgYJDAABAAAAAA==.Tatari:BAAANQADCgYJCgABNQAECgEJAQABAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAAANQAECgYJDwAAAA==.Tellanna:BAAANQAECgIJBAAAAA==.Tensuken:BAAANQAECgQJBgAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgEIAgAAAA==.',
Th='That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgQJBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgQJBAAAAA==.Theunclepaul:BAAANQAECgUJCgAAAA==.',
Ti='Tiarl:BAABNQAECoEcAAIHAAgKnxQaMgAsAgAHAAgKnxQaMgAsAgAAAA==.Tinydots:BAAANQAECgQJBQAAAA==.',
To='Tom:BAAANQADCgIIBAAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQADCgUJEAAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggJBgAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgMJAwAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAAANQAECgEIAgAAAA==.',
Va='Valakk:BAAANQADCgYJCwAAAA==.Valsitril:BAAANQAECgUJCAAAAA==.Vanara:BAAANQABCggICgAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgUJCAABAAAAAA==.',
Ve='Velsetin:BAAANQADCgQIBAABNQAECgUIBQABAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcJFwAAAA==.',
Vi='Vicas:BAAANQAECgIJAgAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Wa='Warded:BAAANQADCggJDwAAAA==.',
We='Wesjenks:BAAANQAECgUIBQAAAA==.',
Wh='Whisperlia:BAAANQADCgQJBAAAAA==.Whisperwindd:BAAANQADCgcJGQAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQADCgEJAQAAAA==.',
Wi='Wilco:BAAANQAECggIBgAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgEJAQABAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAAAAA==.',
Ya='Yaerin:BAAANQAECgcJEgAAAA==.Yaoi:BAAANQAECgYJEwAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQADCgQJBQAAAA==.',
Yu='Yuukon:BAAANQAECgYIDAAAAA==.',
Za='Zackman:BAAANQADCgEJAQAAAA==.Zadira:BAABNQAECoEiAAMMAAkK3xxRDQDVAgAMAAkK3xxRDQDVAgACAAEKFBhpkABFAAAAAA==.Zadirasham:BAAANQAECgQJBAABNQAECgkJIgAMAN8cAA==.',
Ze='Zephrylia:BAAANQADCgYJFQAAAA==.',
Zu='Zuriel:BAAANQAECgQJBgAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgQJBAAAAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQAECgEJAQAAAA==.',
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
