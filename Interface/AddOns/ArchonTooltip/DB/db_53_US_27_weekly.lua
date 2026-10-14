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

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Warlock-Demonology','Mage-Frost','Priest-Holy','Warrior-Protection','DeathKnight-Unholy','Shaman-Restoration','Priest-Shadow','Rogue-Assassination','Paladin-Holy','Warlock-Affliction','Druid-Guardian','Evoker-Devastation','Druid-Balance','Rogue-Subtlety','Evoker-Preservation','Warlock-Destruction','Shaman-Elemental','Priest-Discipline','Rogue-Outlaw','DeathKnight-Frost','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-10-13',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAAANQAECgMIBgAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQAECgEIAQAAAA==.Adura:BAAANQADCgcICAAAAA==.',
Ae='Aeirith:BAABNQAECn8jAAIBAAkKKxevjABlAgABAAkKKxevjABlAgAAAA==.',
Ai='Ailsà:BAAANQADCgIJAgABNQAECgYIEAACAAAAAA==.Airius:BAAANQAECgEIAQAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAAANQAECgUIBQAAAA==.Amarasu:BAAANQAECgYIEAAAAA==.Amarlly:BAAANQAECgUIDQAAAA==.',
An='Ancelina:BAAANQAECgUICgAAAA==.Anderton:BAABNQAECn8lAAIDAAcKHBJdwACVAQADAAcKHBJdwACVAQAAAA==.Andilocks:BAAANQADCgcIHwAAAA==.Anditracks:BAAANQADCggIFwAAAA==.Andraenei:BAAANQAECgUICgAAAA==.Andrela:BAAANQAECgEIAQAAAA==.Aneira:BAAANQAECgYIEAAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECgYIEwACAAAAAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECn8uAAIEAAkKBiT0CQBlAwAEAAkKBiT0CQBlAwAAAA==.Archmedies:BAAANQADCgEIAQAAAA==.Archérhiro:BAACNQAFFH8SAAMFAAUKMSOmBwDOAQAFAAUKMSOmBwDOAQAGAAEKAACFJwA1AAA1AAQKfzQAAwUACQoUI3MUAEsDAAUACQoUI3MUAEsDAAYABQpTEDNEADEBAAAA.Arillann:BAABNQAECn8fAAIHAAkK0R++BwAkAwAHAAkK0R++BwAkAwAAAA==.Arin:BAAANQAECgQIBgABNQAECgkJFwAIAN4WAA==.Arms:BAAANQAECgEIAQABNQAECggIHAADAOYVAA==.Arrook:BAAANQAECgEIAQAAAA==.Artdemsamis:BAAANQAECggIEQAAAA==.Arttimar:BAAANQAECggICAAAAA==.Arvena:BAAANQADCgQIBAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgACAAAAAA==.Ashylock:BAABNQAECn8VAAIJAAkKehNCUABhAgAJAAkKehNCUABhAgABNQAFFAUICwABANMNAA==.Ashymage:BAACNQAFFH8LAAIBAAUK0w2VIQB0AQABAAUK0w2VIQB0AQA1AAQKfzgAAwEACQrVIkcWAHoDAAEACQrVIkcWAHoDAAoAAQrTChdGADYAAAAA.Askevar:BAAANQAECgYIEAAAAA==.Asriél:BAABNQAECn8YAAIFAAgK7RhyYgBOAgAFAAgK7RhyYgBOAgAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgIIAwABNQAFFAQIDAALAE8QAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAAANQAECgYIDwAAAA==.',
Az='Azaleah:BAABNQAECn8pAAIDAAkKthCaeAA3AgADAAkKthCaeAA3AgAAAA==.Azlan:BAAANQADCgQIBAAAAA==.Azraesha:BAAANQAECgcIEQAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQADCgIIAgAAAA==.',
Be='Beareold:BAAANQAECgEIAQAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIDQAAAA==.Bigmon:BAABNQAECn9BAAMIAAkKFyLTIAAzAwAIAAkKFyLTIAAzAwAMAAEKgA/EQwAvAAAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgQIBQAAAA==.Blackstaff:BAAANQADCggJCgAAAA==.Blessthefall:BAAANQAECggIBQAAAA==.Bloodygrundl:BAABNQAECn8fAAIEAAkK7R8WEAAqAwAEAAkK7R8WEAAqAwAAAA==.Bluestorm:BAAANQAECgYIDwAAAA==.',
Bo='Bonegrinda:BAABNQAECn8dAAINAAcKGiAXMgBhAgANAAcKGiAXMgBhAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwACAAAAAA==.',
Br='Branwynn:BAAANQADCgYIBwAAAA==.Bringg:BAAANQAECgQIBAAAAA==.',
Bu='Bulldoza:BAAANQADCgQIBAAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQAECgYIBwAAAA==.Ceri:BAAANQAECggIAQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFH8VAAIOAAYKJCDjAwBFAgAOAAYKJCDjAwBFAgA1AAQKfyQAAg4ACQoNJbQIAHoDAA4ACQoNJbQIAHoDAAAA.Chantix:BAAANQADCgYIBwAAAA==.Chaosshadow:BAABNQAECn8XAAIPAAcKWBBVMQCUAQAPAAcKWBBVMQCUAQAAAA==.Chaosti:BAAANQAECgYIEAAAAA==.Cheekymonkey:BAABNQAECn8hAAIBAAgKBwjt6AC1AQABAAgKBwjt6AC1AQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgkJKAAQAKEeAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQAECgYIBwABNQAECgYIEwACAAAAAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECn8kAAIRAAUKkh+DcgC9AQARAAUKkh+DcgC9AQAAAA==.Crosslock:BAAANQADCgcICwAAAA==.',
Cu='Cuack:BAAANQAECgEIAQAAAA==.',
Cy='Cynnari:BAAANQAECgYIEwAAAA==.',
Da='Dagnabit:BAAANQADCggIFAAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAAANQAECgYIEAAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgUIDQACAAAAAA==.',
De='Deathmare:BAAANQAECgYIDAAAAA==.Deeptroat:BAAANQADCgEIAQABNQAECgYIEAACAAAAAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECn8hAAMJAAgK0BMcdAAAAgAJAAgK0BMcdAAAAgASAAEKAACsMAAzAAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAAANQAECgQIDAAAAA==.Diltlish:BAAANQAECgQIBwAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECn8jAAIIAAkKzxdwWgB5AgAIAAkKzxdwWgB5AgAAAA==.',
Dm='Dmginc:BAAANQAECgMIBgAAAA==.',
Do='Doeblin:BAAANQADCggIIwAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgMIAwAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAAANQAECgUICQAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAABNQAECn8hAAIBAAkKChGAnABHAgABAAkKChGAnABHAgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQAECgUIBQAAAA==.Drakkei:BAABNQAECn8dAAIFAAgKIBNqawA5AgAFAAgKIBNqawA5AgABNQAECggIJwATACYWAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQAECgQIBAAAAA==.Drylo:BAEBNQAECn8gAAIUAAgKNyMIBgArAwAUAAgKNyMIBgArAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQADCggIGQAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgUIBwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgYICAAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erf:BAAANQADCgYIDgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECn8jAAIVAAgKOg6gSgC3AQAVAAgKOg6gSgC3AQAAAA==.',
Et='Ethellin:BAABNQAECn8eAAIDAAcKYwT8AQEVAQADAAcKYwT8AQEVAQAAAA==.',
Eu='Euph:BAAANQAECgQICAAAAA==.',
Ev='Evilhearts:BAAANQADCggICAAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgYIDwABNQAECgkJKwADAMYlAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBgABNQAECgUIEAACAAAAAA==.Feleria:BAAANQADCgUJBQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluxarata:BAAANQAECgYICAAAAA==.',
Fr='Fred:BAAANQAECgUIBwAAAA==.Friendly:BAABNQAECn8dAAIQAAkKVSMvBQB+AwAQAAkKVSMvBQB+AwAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fupacabra:BAAANQADCgcIBwAAAA==.Fuzzyhunter:BAAANQADCgcICwAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgYIEAACAAAAAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAABNQAECn8hAAIFAAkKUBiDPgCtAgAFAAkKUBiDPgCtAgAAAA==.Gagageoff:BAAANQADCgcIFwAAAA==.Gardyson:BAABNQAECn8dAAMMAAkKFAysHwBOAQAIAAkKLwgerwCiAQAMAAcK1QysHwBOAQAAAA==.Garwarmegad:BAAANQADCggICwAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Go='Gobsprocket:BAAANQADCggICAAAAA==.Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECn8kAAIGAAkKixMCHwBVAgAGAAkKixMCHwBVAgAAAA==.Grenadeout:BAAANQAECgQIBwAAAA==.Grimaldus:BAAANQAECgEIAQAAAA==.',
Ha='Harrod:BAAANQADCgYIBgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAAANQAECggIEgAAAA==.Hellsspawn:BAAANQADCgUIDAAAAA==.',
Ho='Hokàge:BAABNQAECn8oAAMQAAkKoR5EKwA3AgAQAAcKjhtEKwA3AgAWAAUKZCOhHgDZAQAAAA==.Homealone:BAAANQAECgYICgAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQADCggICQABNQAECgcIGwAPAH4SAA==.Huntinfuzzy:BAABNQAECn8WAAIFAAgK/wZ5sgCaAQAFAAgK/wZ5sgCaAQAAAA==.Huugg:BAAANQAECgQIBAAAAA==.',
Hy='Hymncarrey:BAABNQAECn8ZAAILAAcKIyPiKwC3AgALAAcKIyPiKwC3AgAAAA==.Hynkie:BAAANQAECgQICAABNQAECgkJIgAXAGUTAA==.',
Id='Idari:BAAANQABCgEIAQAAAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECgcIDgACAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAABNQAECn8ZAAQSAAcKnBi3BwAbAgASAAcKnBi3BwAbAgAJAAYKXA4ctABiAQAYAAEK4wa+fgAtAAAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECgYIEAACAAAAAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECn8aAAIDAAkKThgbbQBTAgADAAkKThgbbQBTAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQACAAAAAA==.',
Je='Jellytown:BAABNQAECn8eAAIKAAkKOxqABQC3AgAKAAkKOxqABQC3AgAAAA==.Jelorinea:BAAANQADCgYIBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Juicylucy:BAAANQADCgQIBAAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCggIFwAAAA==.',
['Jô']='Jôhnwick:BAABNQAECn8dAAIGAAkKZw63KgDyAQAGAAkKZw63KgDyAQAAAA==.',
Ka='Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECn8eAAIFAAkKxxI6UQB5AgAFAAkKxxI6UQB5AgAAAA==.Kaladil:BAAANQAECgEIAQAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgEIAQAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Kh='Khota:BAAANQAECgcICwAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQAECgQIBAAAAA==.',
Ku='Kurtina:BAABNQAECn8hAAIIAAkK3hOScAA+AgAIAAkK3hOScAA+AgAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAABNQAECn8XAAIFAAkKrRXIUAB7AgAFAAkKrRXIUAB7AgAAAA==.Larac:BAAANQAECggIDQAAAA==.',
Le='Leddy:BAAANQADCgUICQAAAA==.Leif:BAABNQAECn8eAAIUAAkKBxdJEABRAgAUAAkKBxdJEABRAgAAAA==.Lemmart:BAAANQAECgYICgAAAA==.Lenik:BAAANQAECgQICwAAAA==.',
Li='Licorice:BAAANQAECgYIEwAAAA==.Lieree:BAABNQAECn8eAAIBAAgK/gnN3ADLAQABAAgK/gnN3ADLAQAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgUIBwAAAA==.',
Lo='Lockty:BAAANQAECggIDgABNQAECgkJFwAFAK0VAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAAANQAECgIIAwAAAA==.Lucity:BAAANQAECgcIDQABNQAECgkJGgADAE4YAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgYIDgAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lunà:BAAANQAECgQIBQAAAA==.',
Ly='Lystral:BAAANQAECgQIBwAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
Ma='Mace:BAABNQAECn8fAAIDAAkKpyIrHgBJAwADAAkKpyIrHgBJAwAAAA==.Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQAECgIIAgABNQAECgkJKAAQAKEeAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQADCgIIAgABNQAECgkJHQAMABQMAA==.Malìficus:BAAANQADCgcIBwAAAA==.Manadâr:BAAANQAECgQIBgAAAA==.Marinas:BAAANQADCgcIFgAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgEIAwAAAA==.Mazumaragg:BAAANQAECgMIAwABNQAECgkJHQAMABQMAA==.',
Mi='Miande:BAAANQAECgUICgAAAA==.Microburst:BAABNQAECn8iAAIZAAgKXAhmigCGAQAZAAgKXAhmigCGAQAAAA==.Minilock:BAABNQAECn8aAAQJAAgKdgk9mwCdAQAJAAgKdgk9mwCdAQAYAAMKwgFjYQBhAAASAAEKDAeyMQAwAAAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEIAQAAAA==.Missused:BAAANQABCgIIAwAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIEAACAAAAAA==.Mièlikki:BAAANQAECgQICQAAAA==.',
Mo='Modelotime:BAAANQADCggICwAAAA==.Modsagoodtnk:BAAANQADCgEIAQABNQADCgUICwACAAAAAA==.Mongermook:BAABNQAECn8YAAITAAcKKQ0BKABRAQATAAcKKQ0BKABRAQAAAA==.Monnkysham:BAAANQADCgYJBgAAAA==.Mooglefur:BAAANQADCgcICAAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECn8bAAIOAAcKTxX2cQCyAQAOAAcKTxX2cQCyAQAAAA==.Nacronor:BAAANQADCggIIgAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgQIAwAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCgcIHQAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQIBAAAAA==.Nickita:BAAANQAECgIIAgAAAA==.Nightgear:BAACNQAFFH8VAAIFAAYK2Q6xAwAhAgAFAAYK2Q6xAwAhAgA1AAQKf0oAAgUACQorIbcoAPQCAAUACQorIbcoAPQCAAAA.Nighti:BAAANQADCgQIBAAAAA==.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgQICwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECn8nAAMTAAgKJhYCFwD2AQATAAgKJhYCFwD2AQAVAAYKXQm1ZgAuAQAAAA==.',
Od='Ode:BAABNQAECn8eAAIBAAgKHQof3wDHAQABAAgKHQof3wDHAQAAAA==.Odex:BAAANQAECgYICQAAAA==.',
On='Onlymages:BAABNQAECn8cAAIBAAUKnA9oOwEmAQABAAUKnA9oOwEmAQAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECn8bAAMPAAcKfhL7LAC6AQAPAAcKfhL7LAC6AQAaAAMKhgv8GgCOAAAAAA==.',
Ou='Outkíll:BAAANQAECgUIBwAAAA==.',
Pa='Pally:BAABNQAECn8cAAIDAAgK5hVdfQArAgADAAgK5hVdfQArAgAAAA==.Pandarweb:BAAANQAECgQIBAAAAA==.Pathogen:BAABNQAECn8fAAINAAkKxiHSCQBuAwANAAkKxiHSCQBuAwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAAANQAECgQIEQAAAA==.Perve:BAAANQAECgUICQABNQAECggIGAAFAO0YAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pippy:BAAANQAECgEIAQAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgQIBQAAAA==.Promethèus:BAABNQAECn8hAAIBAAkKBRvfRwDzAgABAAkKBRvfRwDzAgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAABNQAECn8aAAIbAAgKygrHCwCiAQAbAAgKygrHCwCiAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFH8RAAIUAAYKDxLlAgDYAQAUAAYKDxLlAgDYAQA1AAQKf1sAAhQACQqYIRMDAHgDABQACQqYIRMDAHgDAAAA.Ramike:BAABNQAECn8hAAIMAAgKgRsxDQBdAgAMAAgKgRsxDQBdAgAAAA==.Randal:BAAANQABCgIIAgAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQAECgIIAgAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgkJKAAQAKEeAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rinà:BAAANQADCgIIAgAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECn8eAAIIAAkKFxkHSQCrAgAIAAkKFxkHSQCrAgAAAA==.',
Ro='Rosara:BAAANQAECgcIBwAAAA==.',
Rr='Rrook:BAAANQADCgQIBgAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgcIGQALACMjAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQAECgEIAQAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgIIAwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Si='Sieya:BAAANQADCggIFgAAAA==.Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECgQIBAAAAA==.Skullace:BAAANQAECgUIDAAAAA==.Skullhead:BAAANQABCggIJgAAAA==.Skylette:BAAANQADCggJDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUIDgABNQAECgkJHQAMABQMAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.Sortiebatoru:BAAANQAECgEIAQAAAA==.Soulblight:BAAANQADCggICAAAAA==.',
Sp='Sparkplugg:BAAANQADCgQICAAAAA==.Sparthos:BAAANQAECgUIEgAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQABCgIIAgAAAA==.',
Sr='Srfreaky:BAAANQADCggIHAAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECn8jAAIcAAgKAwi4TAB9AQAcAAgKAwi4TAB9AQAAAA==.Stocklock:BAAANQAECgEIAQAAAA==.Stormblessed:BAAANQADCgQJBAAAAA==.Stowned:BAAANQAECgQIBQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAACAAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.Suzuya:BAAANQABCggICAAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgkJHQAMABQMAA==.Tatari:BAAANQADCgYJCgABNQAECgUICQACAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAABNQAECn8eAAIdAAkKpxAxJgDtAQAdAAkKpxAxJgDtAQAAAA==.Tellanna:BAABNQAECn8VAAIBAAYKOAIMaQHiAAABAAYKOAIMaQHiAAAAAA==.Tensuken:BAAANQAECgUIEAAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgUICQAAAA==.',
Th='Thadium:BAAANQADCgcIBwAAAA==.That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgQJBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgYIBgAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECn8zAAILAAkKRBuGJQDTAgALAAkKRBuGJQDTAgAAAA==.Tinydots:BAAANQAECgUIDwAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQADCgcIIgAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAMIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECggIIAAUADcjAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAAANQAECgcIDgAAAA==.Unfriendly:BAAANQADCggIDAAAAA==.',
Va='Vaelora:BAAANQAECgcIBwAAAA==.Valakk:BAAANQAECgMIBgAAAA==.Valsitril:BAAANQAECgUIEQABNQAECgYIEAACAAAAAA==.Vanara:BAAANQABCggICwAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgYIEAACAAAAAA==.',
Ve='Velsetin:BAAANQAECgEIAQABNQAECggIDAACAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcIGQABNQAECggIIgAPALEZAA==.',
Vi='Vicas:BAAANQAECgIIAgAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQADCggIDwAAAA==.',
We='Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAAANQAECgMIBQAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgEIAQAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgUICQACAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.Xanndor:BAAANQABCggICAAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAABNQAECgQIBQACAAAAAA==.',
Ya='Yaerin:BAABNQAECn8eAAMLAAkK4R/hEQA4AwALAAkK4R/hEQA4AwAaAAMK0Q65GgCQAAAAAA==.Yahman:BAAANQAECgQIBAAAAA==.Yaoi:BAABNQAECn8pAAMZAAkKSA5AZgDqAQAZAAkKSA5AZgDqAQAOAAgKSAhIkwBUAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECgUIBQAAAA==.',
Yu='Yungfungi:BAAANQADCgcIFQAAAA==.Yuukon:BAABNQAECn8lAAIcAAgKVBFcPQDSAQAcAAgKVBFcPQDSAQAAAA==.',
Za='Zackman:BAAANQADCgYIEgAAAA==.Zad:BAAANQAECgUIBAABNQAFFAUIDAAcAKcWAA==.Zadira:BAACNQAFFH8MAAIcAAUKpxbmBgCIAQAcAAUKpxbmBgCIAQA1AAQKfzIAAxwACQq3IRMKAEkDABwACQq2IRMKAEkDAAQAAwq8GiWKANMAAAAA.Zadirasham:BAAANQAECgcIEgABNQAFFAUIDAAcAKcWAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.Zephrylia:BAAANQADCggIFwAAAA==.',
Zu='Zuriel:BAAANQAECgQICwAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgYIBgAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgYIFAAEAOYeAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQAECgUICQAAAA==.',
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
