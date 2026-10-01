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

local lookup = {'Mage-Arcane','Unknown-Unknown','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Mage-Frost','Priest-Holy','Paladin-Retribution','Warrior-Arms','DeathKnight-Unholy','Shaman-Restoration','Rogue-Subtlety','Paladin-Holy','Evoker-Devastation','Druid-Balance','Rogue-Assassination','Warrior-Protection','Druid-Restoration','Priest-Discipline','Shaman-Elemental','DeathKnight-Frost',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaravos:BAAANQAECgUIBQAAAA==.Aatrøx:BAAANQAECgMIBAAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQADCgYIBgAAAA==.',
Ae='Aeirith:BAABNQAECoEYAAIBAAgKAhR2lQARAgABAAgKAhR2lQARAgAAAA==.',
Ai='Ailsà:BAAANQADCgIJAgABNQAECgQIBQACAAAAAA==.Airius:BAAANQADCgYIBwAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMJAwAAAA==.',
Am='Amalthia:BAAANQAECgUIBQAAAA==.Amarasu:BAAANQAECgUIBgAAAA==.Amarlly:BAAANQAECgIIAwAAAA==.',
An='Ancelina:BAAANQAECgEIAQAAAA==.Anderton:BAAANQAECgYIEgAAAA==.Andilocks:BAAANQADCgcIFQAAAA==.Anditracks:BAAANQADCggIFgAAAA==.Andraenei:BAAANQADCggIFAAAAA==.Andrela:BAAANQADCgYIBwAAAA==.Aneira:BAAANQAECgQIBQAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECgMICQACAAAAAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECoEfAAIDAAkK2yAJCQBVAwADAAkK2yAJCQBVAwAAAA==.Archmedies:BAAANQADCgEIAQAAAA==.Archérhiro:BAACNQAFFIEIAAMEAAQKpxndBwBpAQAEAAQKpxndBwBpAQAFAAEKhgJAHQA9AAA1AAQKgS4AAwQACQquI8MLAF0DAAQACQquI8MLAF0DAAUABQp9E9I0AEgBAAAA.Arillann:BAABNQAECoEXAAIGAAcKuiEHDACWAgAGAAcKuiEHDACWAgAAAA==.Arin:BAAANQAECgQIBgABNQAECgcIEAACAAAAAA==.Arms:BAAANQABCgIIAgABNQAECgUICQACAAAAAA==.Arrook:BAAANQADCgYICgAAAA==.Artdemsamis:BAAANQAECggIEQAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgACAAAAAA==.Ashylock:BAAANQAECgcICwABNQAFFAMIBgABAJIPAA==.Ashymage:BAACNQAFFIEGAAIBAAMKkg9nJQDoAAABAAMKkg9nJQDoAAA1AAQKgSgAAwEACQoHHQ8zAAgDAAEACQoHHQ8zAAgDAAcAAQrTCgw3ADoAAAAA.Askevar:BAAANQAECgUICQAAAA==.Asriél:BAAANQAECgYIDAAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgEIAQABNQAFFAMIBgAIAH8OAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAAANQAECgUIBQAAAA==.',
Az='Azaleah:BAABNQAECoEYAAIJAAgKsgvHhAC3AQAJAAgKsgvHhAC3AQAAAA==.Azlan:BAAANQABCgMIAwAAAA==.Azraesha:BAAANQAECgYIDAAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQADCgIIAgAAAA==.',
Be='Beareold:BAAANQADCgYIBwAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQICQAAAA==.Bigmon:BAABNQAECoExAAIKAAkKHh4yIQAPAwAKAAkKHh4yIQAPAwAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgQIBQAAAA==.Blackstaff:BAAANQADCggJCgAAAA==.Blessthefall:BAAANQAECgQIBAAAAA==.Bloodygrundl:BAABNQAECoEXAAIDAAcKhiDYHwB/AgADAAcKhiDYHwB/AgAAAA==.Bluestorm:BAAANQAECgQIBAAAAA==.',
Bo='Bonegrinda:BAABNQAECoEXAAILAAcKTh/3JwBIAgALAAcKTh/3JwBIAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwACAAAAAA==.',
Br='Branwynn:BAAANQADCgYIBwAAAA==.Bringg:BAAANQADCgYIBgAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQADCgYIEgAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQAECgEIAQAAAA==.Ceri:BAAANQAECggJAQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFIEOAAIMAAUKqx62BADgAQAMAAUKqx62BADgAQA1AAQKgR8AAgwACQq6JPIGAHIDAAwACQq6JPIGAHIDAAAA.Chantix:BAAANQADCgMIAwAAAA==.Chaosshadow:BAAANQAECgUICQAAAA==.Chaosti:BAAANQAECgUICgAAAA==.Cheekymonkey:BAABNQAECoEXAAIBAAcKwAmB2ACFAQABAAcKwAmB2ACFAQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Christy:BAAANQADCggICgAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgkJGwANAIUdAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQADCggJCgABNQAECgMICQACAAAAAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECoEdAAIOAAUKkh+TWADGAQAOAAUKkh+TWADGAQAAAA==.Crosslock:BAAANQADCgUIBwAAAA==.',
Cu='Cuack:BAAANQADCgQIBAAAAA==.',
Cy='Cynnari:BAAANQAECgQICgAAAA==.',
Da='Dagnabit:BAAANQADCggIFAAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAAANQAECgYIBwAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDQAAAA==.Dartian:BAAANQAECgMJAwABNQAECgQICAACAAAAAA==.',
De='Deathmare:BAAANQAECgYIDAAAAA==.Deeptroat:BAAANQADCgEIAQABNQAECgUIBgACAAAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAAANQAECgUIDwAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAAANQAECgMIAwAAAA==.Diltlish:BAAANQAECgIIAgAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECoEZAAIKAAkKfBfuQwCDAgAKAAkKfBfuQwCDAgAAAA==.',
Dm='Dmginc:BAAANQAECgEIAQAAAA==.',
Do='Doeblin:BAAANQADCgcIHgAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgIJAgAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Dragonflai:BAAANQAECgcIEwAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQADCgUIBAAAAA==.Drakkei:BAAANQAECgUICwABNQAECgYIEgACAAAAAA==.Drshortbus:BAAANQAECgQIBAAAAA==.Drylo:BAEBNQAECoEYAAIPAAcK6SMvCADQAgAPAAcK6SMvCADQAgAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQADCgYJFAAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgMIAwAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgIIAgAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgEJAQAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erf:BAAANQADCgYIBgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECoEWAAIQAAgKTw0RPgC2AQAQAAgKTw0RPgC2AQAAAA==.',
Et='Ethellin:BAAANQAECgYIDgAAAA==.',
Eu='Euph:BAAANQADCggIFAAAAA==.',
Ev='Evilhearts:BAAANQADCgcJBwAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgQIBQABNQAECggIHwAJAJQjAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgQIBAABNQAECgUIDQACAAAAAA==.Feleria:BAAANQADCgUJBQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.',
Fl='Fluxarata:BAAANQAECgYIBgAAAA==.',
Fr='Fred:BAAANQAECgIIAwAAAA==.Friendly:BAABNQAECoEXAAIRAAkKSCFXBQBXAwARAAkKSCFXBQBXAwAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fuzzyhunter:BAAANQADCgQIBAAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgQIBQACAAAAAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAAANQAECgcIEwAAAA==.Gagageoff:BAAANQADCgUIBQAAAA==.Gardyson:BAAANQAECgcIDgAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Go='Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAAANQAECgYIDgAAAA==.Grenadeout:BAAANQAECgQIBQAAAA==.Grimaldus:BAAANQABCgIIAgAAAA==.',
Ha='Harrod:BAAANQADCgYIBgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
He='Hefty:BAAANQAECgUIDQAAAA==.Hellsspawn:BAAANQADCgUJCgAAAA==.',
Ho='Hokàge:BAABNQAECoEbAAMNAAkKhR0OGgDjAQANAAUKMSEOGgDjAQARAAQK7RhcQgAzAQAAAA==.Homealone:BAAANQAECgMIAwAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huntinfuzzy:BAAANQAECgcIDAAAAA==.Huugg:BAAANQABCgQIBAAAAA==.',
Hy='Hymncarrey:BAAANQAECgQICwAAAA==.Hynkie:BAAANQAECgQIBAABNQAECgUIDAACAAAAAA==.',
Ig='Igothots:BAAANQAECgQIBAABNQAECgYICQACAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAAANQAECgUICgAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECgUIBgACAAAAAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAAANQAECgcIEAAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQACAAAAAA==.',
Je='Jellytown:BAABNQAECoEXAAIHAAcKcB/eBQBkAgAHAAcKcB/eBQBkAgAAAA==.Jelorinea:BAAANQADCgYJBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQIBQAAAA==.',
Ju='Juicylucy:BAAANQADCgQIBAAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCggIDQAAAA==.',
['Jô']='Jôhnwick:BAAANQAECggIEgAAAA==.',
Ka='Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECoEXAAIEAAcKCRQiZgDxAQAEAAcKCRQiZgDxAQAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Kh='Khota:BAAANQAECgYIBwAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQADCggJDQAAAA==.',
Ku='Kurtina:BAAANQAECgYIEAAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAAANQAECgcICgAAAA==.Larac:BAAANQAECgUIBQAAAA==.',
Le='Leddy:BAAANQADCgUJCQAAAA==.Leif:BAABNQAECoEXAAIPAAcKXxP1FAC7AQAPAAcKXxP1FAC7AQAAAA==.Lemmart:BAAANQAECgYICgAAAA==.Lenik:BAAANQAECgQIBwAAAA==.',
Li='Licorice:BAAANQAECgMICQAAAA==.Lieree:BAAANQAECgYIDgAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgMIAwAAAA==.',
Lo='Lockty:BAAANQAECgEIAQABNQAECgcICgACAAAAAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAAANQAECgIIAwAAAA==.Lucity:BAAANQAECgQIBwABNQAECgcIEAACAAAAAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgYIDgAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lunà:BAAANQAECgQIBQAAAA==.',
Ly='Lystral:BAAANQAECgIIAwAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
Ma='Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQADCggICAABNQAECgkJGwANAIUdAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQADCgIIAgABNQAECgcIDgACAAAAAA==.Manadâr:BAAANQAECgEIAQAAAA==.Marinas:BAAANQADCgUIDwAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgEIAwAAAA==.Mazumaragg:BAAANQADCgQICAABNQAECgcIDgACAAAAAA==.',
Mi='Miande:BAAANQAECgQJBgAAAA==.Microburst:BAAANQAECgUJEgAAAA==.Minilock:BAAANQAECgYIEQAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEJAQAAAA==.Missused:BAAANQABCgIJAwAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIDQACAAAAAA==.Mièlikki:BAAANQAECgMIAwAAAA==.',
Mo='Mongermook:BAAANQAECgUIDwAAAA==.Monnkysham:BAAANQADCgYJBgAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAAANQAECgUIDgAAAA==.Nacronor:BAAANQADCgcIHQAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgEIAgAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCgcIEgAAAA==.Nexedo:BAAANQADCgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQIBAAAAA==.Nightgear:BAACNQAFFIELAAIEAAUKIRGBBQCfAQAEAAUKIRGBBQCfAQA1AAQKgUEAAgQACQoBHqImAMMCAAQACQoBHqImAMMCAAAA.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgEIAgAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAAANQAECgYIEgAAAA==.',
Od='Ode:BAAANQAECgYIEAAAAA==.Odex:BAAANQAECgMIAwAAAA==.',
On='Onlymages:BAAANQAECgQIDAAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAAANQAECgUIDwAAAA==.',
Ou='Outkíll:BAAANQAECgUIBgAAAA==.',
Pa='Pally:BAAANQAECgUICQAAAA==.Pandarweb:BAAANQADCgUJBQAAAA==.Pathogen:BAABNQAECoEXAAILAAcKZiJFHQCWAgALAAcKZiJFHQCWAgAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAAANQAECgQIDAAAAA==.Perve:BAAANQAECgUJCQABNQAECgYIDAACAAAAAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pippy:BAAANQADCgYJBgAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAgAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgMIAwAAAA==.Promethèus:BAAANQAECgcIDwAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAAANQAECgYIDwAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAABNQAECoFEAAIPAAkKEB+DBAA0AwAPAAkKEB+DBAA0AwAAAA==.Ramike:BAABNQAECoEXAAISAAcKPRkNDgD0AQASAAcKPRkNDgD0AQAAAA==.Randal:BAAANQABCgIIAgAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQADCgcIBwAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgkJGwANAIUdAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECoEXAAIKAAcKzRxZVwBBAgAKAAcKzRxZVwBBAgAAAA==.',
Rr='Rrook:BAAANQADCgQIBgAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgQICwACAAAAAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQADCggIFwAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shan:BAAANQAECgcIDwAAAA==.Shaxx:BAABNQAECoEXAAIJAAgK1h5hNAC5AgAJAAgK1h5hNAC5AgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Si='Sieya:BAAANQADCgcIEgAAAA==.Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skullace:BAAANQAECgIIAwAAAA==.Skullhead:BAAANQABCggIHwAAAA==.Skylette:BAAANQADCggJDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgMIBAABNQAECgcIDgACAAAAAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.',
Sp='Sparthos:BAAANQAECgUIEgAAAA==.Springbuck:BAAANQABCgIJAgAAAA==.',
Sr='Srfreaky:BAAANQADCgYJFwAAAA==.',
St='Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAAANQAECgUIEwAAAA==.Stocklock:BAAANQADCgUIBwAAAA==.Stormblessed:BAAANQADCgQJBAAAAA==.Stumpyborg:BAAANQADCggICAABNQAECgUIDQACAAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgcIDgACAAAAAA==.Tatari:BAAANQADCgYJCgABNQAECgMIBAACAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAABNQAECoEXAAITAAcKBxHDJgCGAQATAAcKBxHDJgCGAQAAAA==.Tellanna:BAAANQAECgUICQAAAA==.Tensuken:BAAANQAECgQICAAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgQIBwAAAA==.',
Th='That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgQJBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgUIBQAAAA==.Theunclepaul:BAAANQAECgUJCgAAAA==.',
Ti='Tiarl:BAABNQAECoEkAAIIAAgKixpgKwB9AgAIAAgKixpgKwB9AgAAAA==.Tinydots:BAAANQAECgQIBwAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQADCgUIFQAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAMIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAAANQAECgEIAgAAAA==.Unfriendly:BAAANQADCgQIBAAAAA==.',
Va='Valakk:BAAANQADCgcIDwAAAA==.Valsitril:BAAANQAECgUICgABNQAECgYIBwACAAAAAA==.Vanara:BAAANQABCggICwAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgYIBwACAAAAAA==.',
Ve='Velsetin:BAAANQADCgQIBAABNQAECgUIBwACAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcIGQABNQAECgYIEwACAAAAAA==.',
Vi='Vicas:BAAANQAECgIIAgAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQADCggJDwAAAA==.',
We='Wesjenks:BAAANQAECgUIBgAAAA==.',
Wh='Whisperlia:BAAANQADCgQJBAAAAA==.Whisperwindd:BAAANQADCggIIQAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgEIAQAAAA==.',
Wi='Wilco:BAAANQAECggIBgAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgMIBAACAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAAAAA==.',
Ya='Yaerin:BAABNQAECoEbAAMIAAgKayFfFQD4AgAIAAgKayFfFQD4AgAUAAMK0Q7bFACfAAAAAA==.Yaoi:BAABNQAECoEfAAMMAAgKSAjNcgBcAQAMAAgKSAjNcgBcAQAVAAYKmgOxngACAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECgQIAwAAAA==.',
Yu='Yuukon:BAAANQAECgcIEwAAAA==.',
Za='Zackman:BAAANQADCgYICQAAAA==.Zad:BAAANQAECgQIAgABNQAFFAMIBwAWAIkYAA==.Zadira:BAACNQAFFIEHAAIWAAMKiRgaCAD2AAAWAAMKiRgaCAD2AAA1AAQKgSYAAxYACQoqHsQSALgCABYACQqhHcQSALgCAAMAAwraGW5xAOEAAAAA.Zadirasham:BAAANQAECgYICgABNQAFFAMIBwAWAIkYAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.Zephrylia:BAAANQADCgYJFQAAAA==.',
Zu='Zuriel:BAAANQAECgQJBgAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgUIBQAAAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQAECgMIBAAAAA==.',
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
