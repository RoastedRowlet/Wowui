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

local lookup = {'Unknown-Unknown','Rogue-Outlaw','DemonHunter-Devourer','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Shaman-Enhancement','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Paladin-Holy','DeathKnight-Unholy','Druid-Restoration','Evoker-Preservation','Druid-Guardian','Paladin-Retribution','Warrior-Arms','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Paladin-Protection','Hunter-Marksmanship','Druid-Balance','Warrior-Fury','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Druid-Feral','Warrior-Protection','Hunter-Survival',}
local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=53,date='2026-09-22',data={Aa='Aatto:BAAANQADCgYICgABNQAECgUICAABAAAAAA==.',
Ab='Abefroman:BAAANQADCgQJBAAAAA==.Abefromen:BAAANQADCggICAAAAA==.',
Ac='Acertrick:BAACNQAFFIESAAICAAcKSx0JAACzAgACAAcKSx0JAACzAgA1AAQKgSgAAgIACQpWJg8AAAIEAAIACQpWJg8AAAIEAAAA.',
Ad='Adampriest:BAAANQAFFAEIAQAAAA==.Addh:BAABNQAECoEhAAIDAAkK7Ro/DQDgAgADAAkK7Ro/DQDgAgAAAA==.',
Ae='Aelwyd:BAABNQAECoEtAAQEAAkKZRWvCgAtAgAFAAgK0hPXAwBAAgAEAAkKBg+vCgAtAgAGAAUK7wt+jQAeAQAAAA==.Aeoni:BAAANQADCggICAABNQAECggIHAAHAB4hAA==.Aeronis:BAAANQAECgQJCAAAAA==.Aery:BAAANQADCgUIBQABNQAFFAEIAQABAAAAAA==.Aessara:BAAANQAECgUJBwAAAA==.',
Ag='Aggron:BAABNQAECoEiAAIIAAkKjCClAgBcAwAIAAkKjCClAgBcAwAAAA==.',
Ai='Ailurun:BAAANQADCgEJAgAAAA==.',
Al='Alexassassin:BAABNQAECoEaAAIJAAkK5xsACQDCAgAJAAkK5xsACQDCAgAAAA==.Aloriannis:BAAANQAECgUIEAAAAA==.Aluas:BAAANQAECgIJAgAAAA==.Alurai:BAAANQADCgcIDQAAAA==.',
Am='Amaracepally:BAAANQAECgYIEAAAAA==.Amethar:BAAANQAECgcICgABNQAFFAYIDwAIANgeAA==.Amowdrood:BAAANQAECgIJAgABNQAECgkJGQAKAMkZAA==.Amowshamow:BAABNQAECoEZAAMKAAkKyRnkMQA/AgAKAAcKRRvkMQA/AgALAAQKLAu4jADeAAAAAA==.',
An='Anan:BAAANQAECgIJAwAAAA==.Anaria:BAAANQADCgYJCwAAAA==.Anatall:BAABNQAECoEeAAIMAAkKjR8WCwBQAwAMAAkKjR8WCwBQAwAAAA==.Andrin:BAAANQAECgcIEAAAAA==.Andy:BAAANQADCgYIBgAAAA==.Aneira:BAAANQADCgUIBQAAAA==.Anitá:BAAANQAECgIJAgAAAA==.',
Ap='Applebees:BAAANQADCggJCAABNQAECggIHgANAE8hAA==.',
Ar='Araragi:BAAANQAECgcJDQAAAA==.Archaon:BAAANQAECggIDwAAAA==.Arei:BAABNQAECoEdAAIOAAgKGx9NBQCtAgAOAAgKGx9NBQCtAgABNQAFFAEIAQABAAAAAA==.Argosa:BAABNQAECoEWAAMPAAcK/xBIoQDFAQAPAAcKtg9IoQDFAQAQAAEK0Qq9LAA/AAAAAA==.Argy:BAAANQAECgYIBgAAAA==.Ari:BAABNQAECoEhAAINAAkKPCEQBQBSAwANAAkKPCEQBQBSAwAAAA==.Arianagrande:BAAANQAECgIIAwAAAA==.Ariehh:BAAANQADCgcIDQABNQAECgkJIQANADwhAA==.Arihog:BAAANQAECgcIDgAAAA==.Arioch:BAAANQAECgIIAwAAAA==.Arkilytê:BAACNQAFFIEPAAMRAAYKvRufAgDSAQARAAYKfA+fAgDSAQADAAQKxx8cBACNAQA1AAQKgScAAwMACQr6I+4DAIUDAAMACQoSI+4DAIUDABEABQojIcwlAOMBAAAA.Aryä:BAAANQAECgEJAQAAAA==.',
As='Ascend:BAECNQAFFIEVAAISAAcKphArAQBWAgASAAcKphArAQBWAgA1AAQKgR0AAhIACQoEHvAOABUDABIACQoEHvAOABUDAAAA.Ascendant:BAEANQAECggIEAABNQAFFAcIFQASAKYQAA==.Astraeá:BAAANQAECgcJEgAAAA==.',
At='Ataci:BAAANQAECgIIAgAAAA==.',
Au='Auroch:BAAANQAECggJEgAAAA==.Auxilary:BAABNQAECoEcAAMHAAcKJg6eKwCWAQAHAAcKJg6eKwCWAQATAAIKAglXgABoAAAAAA==.',
Av='Avalen:BAAANQAECgEIAQABNQAECgEIAQABAAAAAA==.Avarcis:BAAANQAECgcJEgAAAA==.Avasauras:BAAANQAECgEIAQAAAA==.Aveleni:BAABNQAECoEfAAIPAAkK7AzfeAAqAgAPAAkK7AzfeAAqAgAAAA==.Aveloree:BAAANQADCgcIHAAAAA==.',
Aw='Awakening:BAAANQAECgUJBQAAAA==.',
Az='Azelie:BAAANQAECgUICAAAAA==.',
Ba='Babwe:BAAANQAECgMJAwABNQAECgcIEwABAAAAAA==.Baddragön:BAAANQADCgIIAgABNQAECgkJHgAUAJwSAA==.Baery:BAAANQAFFAEIAQAAAA==.Baidoom:BAAANQABCgQIBAAAAA==.Balcmeg:BAAANQAECgUICgABNQAECgUICgABAAAAAA==.Bandrui:BAAANQAECgEJAQAAAA==.Banick:BAAANQAECgMIBQAAAA==.Bartszsimpsn:BAAANQAECgUIBQABNQAECgYIEgABAAAAAA==.Bartszwar:BAAANQAECgYIEgAAAA==.',
Be='Bendie:BAAANQAECgEJAQAAAA==.Beret:BAABNQAECoEdAAIVAAkKeh15CADnAgAVAAkKeh15CADnAgAAAA==.Bewmbat:BAAANQAECgUIBgABNQADCgEIAQABAAAAAQ==.',
Bg='Bgaraecen:BAAANQADCgQIBAAAAA==.',
Bi='Bigchimpn:BAAANQAECgIIAgAAAA==.Bimbo:BAAANQAECgUIDAAAAA==.Bindkickplz:BAAANQABCgQIBwAAAA==.Birdinii:BAAANQAECgcIDgAAAA==.Birstormrage:BAAANQAECgMIBgAAAA==.',
Bl='Blacksmoke:BAAANQADCgUIBAAAAA==.Blacktusk:BAAANQAECgYJEAAAAA==.Bladestorm:BAAANQAECgEIAQAAAA==.Blargdruid:BAACNQAFFIEFAAIWAAMKlAkKAgC7AAAWAAMKlAkKAgC7AAA1AAQKgS4AAhYACQqtHNkDAPYCABYACQqtHNkDAPYCAAAA.Blargwar:BAAANQAECgQJBAABNQAFFAMJBQAWAJQJAA==.Blessthat:BAEANQAECgIIAwAAAA==.Blindnada:BAAANQAECgEJAQABNQAECgcIEQABAAAAAA==.',
Bo='Bonkie:BAAANQAECgIIAgABNQAECgUICAABAAAAAA==.Boomkíll:BAAANQADCgUIBwABNQADCggJDgABAAAAAA==.',
Br='Breaze:BAAANQAECgYIBwAAAA==.Brewdyne:BAAANQADCggICAABNQAECggIGwAPAOETAA==.Brewsef:BAAANQADCggICgAAAA==.Brignis:BAAANQADCgUIBQAAAA==.Brisnger:BAAANQADCgYJBgAAAA==.Brizz:BAAANQAECgQICAABNQAECggIGAALAIcbAA==.Brojojojojo:BAAANQAECgcIDQAAAA==.Broxas:BAAANQAECgEIAQAAAA==.Brøken:BAAANQAECggJDgAAAA==.',
Bu='Bubbleblade:BAAANQADCgEIAQAAAA==.Bubblesbro:BAACNQAFFIEIAAIXAAQKqRy/BAB2AQAXAAQKqRy/BAB2AQA1AAQKgSEAAhcACQrhJbwCANoDABcACQrhJbwCANoDAAAA.Bubkiss:BAAANQADCgEIAQAAAQ==.Buffalo:BAABNQAECoEgAAIYAAkKhxtQLwCtAgAYAAkKhxtQLwCtAgAAAA==.Buffs:BAAANQADCgIIAgABNQAECgcJDQABAAAAAA==.Buffy:BAAANQAECgQIBAAAAA==.Bulbasaurz:BAAANQAECgQIBAAAAA==.Buldair:BAAANQAECgEIAgAAAA==.Bunsski:BAAANQAECgUJCgAAAA==.Burntbacon:BAAANQADCggICAABNQAECggIHAAZAOoRAA==.Burstygirl:BAABNQAECoEkAAIDAAkKoBmRDADqAgADAAkKoBmRDADqAgAAAA==.Buzzkill:BAAANQADCgMIAwAAAA==.',
Bw='Bwis:BAAANQAECgMIAwAAAA==.',
['Bø']='Bøkari:BAAANQAECgUJDQAAAA==.',
Ca='Cakes:BAAANQADCgMIAwAAAA==.Callie:BAACNQAFFIEVAAIaAAcK6xJAAQBhAgAaAAcK6xJAAQBhAgA1AAQKgSgAAxoACQqBIuEHAFADABoACQqBIuEHAFADABsACAoVCH0IAIABAAAA.Caloren:BAAANQADCgYICwABNQAECgQIDAABAAAAAA==.Calypsoza:BAAANQADCggIDgAAAA==.Capitis:BAAANQAECgMIAwAAAA==.Catwink:BAAANQAECgEJAQAAAA==.Caulkfu:BAAANQADCgQIBAABNQAECggIGAAYAOoVAA==.Caulkgoblinz:BAAANQADCgMIAwABNQAECggIGAAYAOoVAA==.',
Ce='Celaine:BAAANQADCgIIAgAAAA==.Celine:BAAANQAECgYJDQAAAA==.Ceol:BAAANQAECgUICAAAAA==.Cernath:BAAANQADCgYIBgABNQAECgcJDwABAAAAAA==.',
Ch='Chaddbrochil:BAAANQAECgMJAwAAAA==.Chaosblade:BAAANQAECgYICAAAAA==.Chilicheese:BAAANQADCgEIAQAAAA==.Chocobomb:BAABNQAECoEkAAMKAAkKlBEnNgAnAgAKAAkKlBEnNgAnAgALAAYK3wGQjADfAAAAAA==.Chosen:BAAANQADCggJEAAAAA==.Chronarfs:BAAANQAECgYIDQAAAA==.',
Ci='Cicatrizesp:BAABNQAECoEcAAIIAAcKFA9yEADfAQAIAAcKFA9yEADfAQAAAA==.Citrine:BAAANQADCgUIBQAAAA==.Cive:BAAANQAECgcJDQAAAA==.',
Cl='Clayberd:BAAANQADCgUIBQAAAA==.',
Co='Coldhearrted:BAABNQAECoEgAAMHAAkKZRhnFQBrAgAHAAkK4hdnFQBrAgATAAYKzBQ4PgCfAQAAAA==.Copyleft:BAAANQADCgQJBAAAAA==.Cosmere:BAAANQAECgYIBwAAAA==.',
Cr='Cracku:BAAANQADCgYIBgAAAA==.Crookamow:BAAANQADCgQIBQABNQAECgkJGQAKAMkZAA==.Cryt:BAAANQAECgcIBwAAAA==.',
Da='Dagather:BAAANQADCgcICwAAAA==.Danala:BAAANQADCgQIBAABNQAECgYICwABAAAAAA==.Danendena:BAAANQAECgcIEwAAAA==.Danglars:BAAANQADCggJCwABNQAECgcJEAABAAAAAA==.Darkcorn:BAABNQAECoEaAAIYAAcKSw8IfgCPAQAYAAcKSw8IfgCPAQAAAA==.Darkdecayy:BAAANQADCgQIBQAAAA==.Darkshieldz:BAABNQAECoEYAAMcAAgKMQvcGwB8AQAcAAgKMQvcGwB8AQAXAAcKHgYUlwBBAQAAAA==.Darkstarex:BAAANQAECgIJAgAAAA==.Darktiranus:BAAANQADCggICAAAAA==.David:BAABNQAECoEYAAMdAAkKdSTGCAAYAwAdAAgKPCTGCAAYAwAMAAEKPSYH4QBZAAAAAA==.',
De='Deadkyle:BAAANQADCgQIBAABNQAECgYIBgABAAAAAA==.Deadly:BAAANQADCgUIBQAAAA==.Deathcalls:BAAANQAECgUJBgAAAA==.Deathlywind:BAAANQAECggJDQAAAA==.Delphias:BAAANQAECgUJCQAAAA==.Deru:BAAANQAECgEJAQAAAA==.Destrorin:BAAANQAECgQIBAAAAA==.Dethlok:BAAANQADCgYIDQAAAA==.Deucedeuce:BAAANQADCgcIIgAAAA==.Devowizard:BAABNQAFFIEaAAIPAAgKlh0wAAAcAwAPAAgKlh0wAAAcAwAAAA==.Dewshaman:BAAANQADCgIIAgAAAA==.',
Di='Dibib:BAACNQAFFIEVAAMGAAcKlhDFAQD5AQAGAAYKxxDFAQD5AQAEAAEKcg/hDwBYAAA1AAQKgSgAAwYACQooJVgIAFEDAAYACAr5JFgIAFEDAAQACArkEicLACUCAAAA.Dinglebery:BAABNQAECoEcAAIZAAgK6hE2MgDZAQAZAAgK6hE2MgDZAQAAAA==.Dirac:BAAANQAECgYJCgAAAA==.Dirkdiggles:BAAANQAECgYJBgAAAA==.Dirtybirdz:BAAANQADCggIEAAAAA==.Discowalker:BAAANQAFFAEJAgAAAA==.Dislexy:BAAANQADCgQIBQAAAA==.',
Dk='Dkittie:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.Dkitty:BAAANQAECgcIDQAAAA==.Dkittykat:BAAANQAECgEJAQABNQAECgcIDQABAAAAAA==.Dkizzy:BAAANQAECgUIBQABNQAECgcIDQABAAAAAA==.',
Do='Dogs:BAAANQADCggJDgAAAA==.Donkeydonng:BAAANQAECgYJCwAAAA==.Doodlez:BAAANQAECgEIAQAAAA==.Dota:BAAANQAECgUICwAAAA==.',
Dr='Dracke:BAAANQADCggJCgAAAA==.Draga:BAAANQAECgcJEQAAAA==.Dragondeezn:BAAANQAECgYIBAAAAA==.Drak:BAACNQAFFIEFAAIMAAMKIRCqCAAFAQAMAAMKIRCqCAAFAQA1AAQKgR4AAwwACQrZIGcJAGADAAwACQrZIGcJAGADAB0AAgrLC+hLAHUAAAAA.Dralëon:BAAANQAECgUJBQAAAA==.Drekzul:BAAANQAECgUJCQAAAA==.Drutara:BAAANQAECggIEQAAAA==.',
Du='Ducey:BAAANQAECggIDAAAAA==.Ducksicker:BAAANQAECgUJCgAAAA==.Dumpsterbaby:BAAANQAECgQIBwAAAA==.Dumpsterfire:BAAANQAECgEIAQAAAA==.Durlklok:BAAANQAECgcJBwAAAA==.',
['Dè']='Dèschain:BAAANQADCgYIFAAAAA==.',
['Dé']='Démonic:BAAANQADCgQIBAAAAA==.',
['Dó']='Dóth:BAAANQAFFAEJAQAAAA==.',
['Dø']='Dørf:BAAANQADCgUIBwAAAA==.',
Ef='Effinaye:BAAANQABCgYICAAAAA==.',
Ei='Eightfingers:BAABNQAECoEeAAIHAAgKiRTkHAAXAgAHAAgKiRTkHAAXAgAAAA==.Eisenklopfer:BAAANQAECgIIAgAAAA==.',
Ek='Ekim:BAAANQAECgEIAgAAAA==.',
El='Elara:BAAANQAECgYJCwAAAA==.Elentiya:BAAANQADCgUIBwAAAA==.Elyaen:BAAANQAECgQJDQAAAA==.',
Em='Emailed:BAECNQAFFIENAAMLAAQKrwvOCwDVAAALAAMKRwfOCwDVAAAKAAIKRRNQEQCeAAA1AAQKgSEAAwoACQprHWscAMkCAAoACQprHWscAMkCAAsAAwqtF7CNANsAAAAA.Emi:BAAANQAECgIIAgAAAA==.Emofemboy:BAAANQADCgYICwAAAA==.',
En='Envy:BAAANQAECgYJCAAAAA==.',
Eo='Eore:BAAANQAECgUJCAAAAA==.',
Er='Erequem:BAAANQADCgEIAQAAAA==.',
Eu='Eupatorus:BAAANQAECgEJAgAAAA==.',
Ew='Ewokhunter:BAABNQAECoEfAAIJAAkKkCWsAADaAwAJAAkKkCWsAADaAwAAAA==.',
Ex='Execuwute:BAAANQABCgYICAAAAA==.',
Fa='Fathernylla:BAAANQADCgUJBQABNQAFFAMIBgAPAPILAA==.',
Fe='Felonee:BAAANQADCggIGgAAAA==.Festermight:BAACNQAFFIENAAQHAAMKVheGCACqAAAHAAIKdhiGCACqAAATAAIKoBhpCQCkAAAZAAEKvBAuHQAzAAA1AAQKgSwAAwcACQpcJe0BALkDAAcACQpNJe0BALkDABMACQoTH1AXALACAAAA.',
Fi='Finnhunter:BAAANQADCgEIAQAAAA==.Fireballs:BAAANQAECggJBgAAAA==.Firedur:BAAANQADCgYIBgABNQAECgcIDAABAAAAAA==.Firenze:BAAANQAECgQIBAAAAA==.Fishpockets:BAAANQADCgEIAQAAAA==.',
Fl='Flosstradamu:BAAANQABCgMIAQAAAA==.',
Fr='Fredrock:BAAANQAECgcJEAAAAA==.',
Fu='Fuzziewuzzie:BAAANQAECgMIBAAAAA==.',
['Fî']='Fîshy:BAACNQAFFIEIAAMLAAUKgxwqBgBqAQALAAQKURoqBgBqAQAKAAEKRQjkGgBGAAA1AAQKgRgAAgsACQobFXw1AB4CAAsACQobFXw1AB4CAAAA.',
Ga='Gaibe:BAABNQAECoEfAAISAAkKjiUFAQDWAwASAAkKjiUFAQDWAwAAAA==.Gamba:BAABNQAECoEYAAMHAAcKbyGbHQAQAgAHAAcK7xubHQAQAgAZAAIKHyLKawDAAAAAAA==.Gambaj:BAAANQADCgYIBgAAAA==.Ganicuss:BAAANQAECgcJAQAAAA==.Garuum:BAAANQADCggICAABNQAECgYICwABAAAAAA==.',
Gb='Gb:BAAANQADCgYIBgAAAA==.',
Ge='Genghiscaulk:BAABNQAECoEYAAIYAAgK6hVfSABHAgAYAAgK6hVfSABHAgAAAA==.Georgeknight:BAACNQAFFIEKAAQHAAMKbg+dCQCfAAAHAAIKghWdCQCfAAATAAEKJB/4DABXAAAZAAEKRQPGJAAaAAA1AAQKgScAAwcACQo7IUwKAAMDAAcACQqsHUwKAAMDABMACQpeHkAUAM8CAAAA.Gertrùde:BAAANQAECgUICgAAAA==.Gerunash:BAAANQADCggICAABNQAFFAcIGgAJAIAOAA==.Gewnz:BAAANQAECgcIEQABNQADCgEIAQABAAAAAA==.',
Gi='Gildharts:BAABNQAECoEZAAIaAAkKZiEXBwBZAwAaAAkKZiEXBwBZAwAAAA==.Gingergiant:BAAANQADCgYICAABNQAECgUJCAABAAAAAA==.Girl:BAAANQAECgYIDQAAAA==.',
Gl='Glaiverush:BAAANQADCgMIAwAAAA==.Glowlimn:BAAANQAECgQIBAABNQAECgcJEgABAAAAAA==.',
Go='Goblindur:BAAANQAECgcIDAAAAA==.',
Gr='Gradris:BAABNQAECoEeAAIXAAkKeBojLgChAgAXAAkKeBojLgChAgAAAA==.Greener:BAABNQAECoEeAAIRAAgK/R3xEADAAgARAAgK/R3xEADAAgAAAA==.Griddy:BAAANQAECgcJDQAAAA==.Grimghar:BAAANQAECgEJAQAAAA==.Grimhoof:BAAANQADCgcIBwABNQAECgUIEQABAAAAAA==.Grimrael:BAAANQADCggIDAABNQAECgUIEQABAAAAAA==.Grimreapyr:BAAANQADCgUIBgABNQAECgUIEQABAAAAAA==.Grimtar:BAABNQAECoEYAAILAAgK5RxiKABiAgALAAgK5RxiKABiAgABNQAECgUIEQABAAAAAA==.Grimtariel:BAAANQAECgUIEQAAAA==.Grimzilla:BAAANQAECgEIAQABNQAECgUIEQABAAAAAA==.Grindkíng:BAAANQADCgQJBAAAAA==.Grippin:BAAANQAECgYIDQAAAA==.Gritspark:BAAANQADCgUIBQAAAA==.',
Gu='Guldar:BAAANQADCgYIBgAAAA==.Gunoil:BAAANQAECgUJCwAAAA==.',
['Gì']='Gìngerale:BAAANQAECgIJAgAAAA==.',
Ha='Hamrshifts:BAAANQAECgIJAgAAAA==.Hamrwitch:BAAANQADCgYIBgAAAA==.Harritapoter:BAAANQABCgYIBgAAAA==.Havartihavoc:BAAANQAECgQIBAAAAA==.Hawtdots:BAAANQAECgIIAgABNQAECgQIBwABAAAAAA==.',
He='Healmeplx:BAAANQAECgQIBgAAAA==.Healsfadayz:BAAANQAECgEJAQAAAA==.Heiku:BAAANQAECgIIAwAAAA==.Hekaraa:BAAANQAECgIIAgAAAA==.Hellequin:BAAANQAECgIJAgAAAA==.Hellhammer:BAAANQADCgcIDAAAAA==.Herenya:BAAANQAECgYIBwAAAA==.',
Hi='Hiccup:BAAANQAECgIJAgAAAA==.Hideyourtoes:BAAANQAECgYIEgABNQAFFAQICQAdAPoeAQ==.Himnick:BAACNQAFFIEaAAQEAAcKPR0eAQAaAQAFAAMKnhuCAAAhAQAEAAMKRR8eAQAaAQAGAAMK1RLuDAD3AAA1AAQKgSsABAQACQp1JbkFAJ0CAAQABwryIrkFAJ0CAAYABwodH6AvAGECAAUABQq4I/EEAAoCAAAA.',
Ho='Holyslimes:BAAANQADCgMIAwAAAA==.Honoree:BAAANQAECgEJAgAAAA==.Honse:BAAANQAECgYICwAAAA==.Hoodal:BAACNQAFFIEKAAISAAUKjhE5BQCeAQASAAUKjhE5BQCeAQA1AAQKgRoAAhIACQqTGAwfAJ8CABIACQqTGAwfAJ8CAAAA.Hope:BAABNQAFFIEGAAIVAAQKGAJLCAAIAQAVAAQKGAJLCAAIAQAAAA==.',
Hu='Hugzug:BAAANQAECgQJBAAAAA==.Huntrez:BAAANQADCgEIAQABNQAECgIIAgABAAAAAA==.Hustlepuff:BAAANQADCgYJEQAAAA==.',
Hy='Hyllah:BAAANQAECgIIAwAAAA==.',
['Hè']='Hèrrinà:BAAANQAECgcIDQAAAA==.',
Ik='Ikissdudes:BAABNQAECoEeAAINAAgKTyHRCQDsAgANAAgKTyHRCQDsAgAAAA==.',
Il='Illuunni:BAAANQAECgUJDgAAAA==.',
Im='Imbecile:BAAANQADCgYIBgABNQAECgYICwABAAAAAA==.Imblack:BAABNQAECoEhAAIeAAkK0yEaCABsAwAeAAkK0yEaCABsAwAAAA==.Improv:BAAANQADCggICQABNQAECggJHgAHAIkUAA==.',
Jc='Jclaw:BAAANQADCggJDgAAAA==.',
Je='Jeddak:BAAANQAECgYICgAAAA==.Jennzen:BAAANQAECgIJAgAAAA==.Jesterawr:BAAANQADCgUIBQABNQADCgcIDAABAAAAAA==.',
Ji='Jinjin:BAAANQAECgcIEAAAAA==.',
Jl='Jlimremix:BAAANQAECgcICQAAAA==.',
Jo='Jouley:BAAANQAECgIIBAAAAA==.',
Ju='Justamage:BAAANQAECgQIBgAAAA==.Justsaiyan:BAAANQADCggIDgAAAA==.',
Jx='Jx:BAAANQAECggJGwAAAQ==.',
Jz='Jzimm:BAAANQAECgMIBAAAAA==.',
['Jå']='Jåcob:BAAANQADCggIBgABNQAECgIJAwABAAAAAA==.',
Ka='Kadane:BAAANQADCgYIBwAAAA==.Kaeori:BAACNQAFFIEaAAIeAAcK2BeCAQBoAgAeAAcK2BeCAQBoAgA1AAQKgR4AAh4ACQp3H7sTAOcCAB4ACQp3H7sTAOcCAAAA.Kaeorishock:BAAANQAECgYIBgABNQAFFAcJGgAeANgXAA==.Kalïsta:BAAANQAECgYJCQAAAA==.Karlach:BAAANQADCggIFQAAAA==.Karnesia:BAAANQABCgMIAwAAAA==.Karra:BAABNQAECoEcAAIHAAgKHiH/CwDpAgAHAAgKHiH/CwDpAgAAAA==.Kayliezra:BAAANQAECgEJAQABNQAECgIJAgABAAAAAA==.Kayssa:BAAANQAECgcJCgAAAA==.',
Ke='Keegan:BAABNQAECoEgAAMfAAkKpiECAgACAwAfAAgKfCICAgACAwAYAAIKmRiO1ACUAAAAAA==.Keiragosa:BAAANQAECgQJBwAAAA==.Keita:BAAANQAECgcIEgAAAA==.Kelaran:BAAANQADCgEIAQAAAA==.Kellired:BAAANQADCgIIAgAAAA==.Kelsara:BAABNQAECoEjAAIPAAkKtiOMDgCFAwAPAAkKtiOMDgCFAwAAAA==.Keltan:BAAANQADCgQIBAAAAA==.',
Kh='Khaladyn:BAAANQADCgUJBQAAAA==.Khaladynie:BAAANQAECgIJAgAAAA==.Khazjin:BAAANQADCgUIBQAAAA==.',
Ki='Kiko:BAAANQADCgcIEAABNQAECgIJAgABAAAAAA==.Killersmallz:BAABNQAECoEXAAIZAAgKyR4YEgDVAgAZAAgKyR4YEgDVAgAAAA==.Killshott:BAAANQADCgYJBgAAAA==.Kindatipsy:BAAANQADCgYIEwAAAA==.Kirasti:BAAANQAECgIJAgAAAA==.Kiriko:BAAANQADCggIDwAAAA==.Kirkadh:BAAANQAECgQJBgABNQAFFAcIGAAUAKElAA==.Kirkap:BAAANQADCgUIBQABNQAFFAcIGAAUAKElAA==.Kirkas:BAAANQAECgMIBgABNQAFFAcIGAAUAKElAA==.Kisspr:BAAANQAECgQIBQAAAA==.Kisswar:BAAANQAECgcJDwAAAA==.Kitkatt:BAAANQADCggIDwAAAA==.Kittyen:BAAANQADCggICAAAAA==.',
Kl='Klet:BAAANQAECgcIEwAAAA==.',
Km='Kmage:BAAANQAECgIIAwAAAA==.',
Ko='Kogarasu:BAAANQAECgIJAgAAAA==.Koramar:BAAANQAECgIIAgABNQAFFAcIGgAJAIAOAA==.',
Kr='Kragarsf:BAAANQAECgIJAgAAAA==.',
Ku='Kubernaughty:BAAANQADCgYIBgAAAA==.Kuulistin:BAAANQAECgQJBgAAAA==.',
Ky='Kyoppy:BAABNQAECoEfAAISAAkKNB4DDgAeAwASAAkKNB4DDgAeAwAAAA==.',
La='Labluegirl:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.Lacusclyne:BAAANQADCgEIAQAAAA==.Lavaßurst:BAAANQAECgEIAQAAAA==.',
Le='Leejohn:BAAANQADCgYIBgAAAA==.Legitasaurus:BAAANQADCggJEAAAAA==.Legndairy:BAAANQAECgYJDAAAAA==.Legola:BAAANQADCgQJBQAAAA==.Lenala:BAAANQAFFAIJAwAAAA==.',
Li='Lightdeity:BAAANQADCgQIBgAAAA==.Lilbeefroni:BAAANQABCgEIAQAAAA==.Lilith:BAAANQAECgMIAwAAAA==.Lilythh:BAAANQADCgIIAgABNQAECgIIAgABAAAAAA==.Linessa:BAAANQAECgUIBAAAAA==.Littlelion:BAABNQAECoEZAAIeAAkKUQqwMADiAQAeAAkKUQqwMADiAQAAAA==.Littlepigboy:BAAANQAECgUIBgAAAA==.Littleteapot:BAAANQAECgcIDQAAAA==.',
Lo='Lockedup:BAAANQADCgcJBwAAAA==.Lockjim:BAAANQADCgMIAwAAAA==.Lookatthisph:BAAANQADCgIIAgABNQADCgcJBwABAAAAAA==.',
Lu='Lucentil:BAAANQAECgEJAQABNQAECgIJAgABAAAAAA==.Lucie:BAAANQAECgYJDgAAAA==.Lucigoosey:BAAANQAECgIIAgAAAA==.Lucindra:BAAANQAECgIJAgAAAA==.Luckycharms:BAAANQABCgQIBAAAAA==.Luckycharrmz:BAAANQADCgcJBwAAAA==.Luminth:BAABNQAECoEVAAIRAAgKZBssFwB4AgARAAgKZBssFwB4AgAAAA==.',
Lv='Lv:BAAANQAECgcJCwAAAA==.',
Ly='Lyka:BAABNQAECoEbAAIaAAYKJSTDLABIAgAaAAYKJSTDLABIAgAAAA==.',
Ma='Madoria:BAAANQAECgQIBgAAAA==.Madorie:BAAANQAECgIJAgAAAA==.Magice:BAAANQAECgIIAgAAAA==.Magistus:BAACNQAFFIEVAAIgAAcKvQ9wAABMAgAgAAcKvQ9wAABMAgA1AAQKgScAAyAACQpAH3oCAGoDACAACQpAH3oCAGoDAA4AAQoOHa8gAE0AAAAA.Marmalady:BAECNQAFFIESAAIVAAcK8R0IAQB7AgAVAAcK8R0IAQB7AgA1AAQKgRwAAhUACQr+IzkDAGUDABUACQr+IzkDAGUDAAAA.Masa:BAACNQAFFIEVAAIUAAcK/RwzAACMAgAUAAcK/RwzAACMAgA1AAQKgSgAAhQACQqWJDoBAKwDABQACQqWJDoBAKwDAAAA.Masq:BAAANQAECgUICAAAAA==.Matamharicas:BAAANQAECgYICwAAAA==.Matt:BAAANQAECgMIBAAAAA==.Mauled:BAABNQAFFIEGAAIZAAQKrhh4BwBMAQAZAAQKrhh4BwBMAQABNQAFFAcIFAAcAFwRAA==.Maulnificent:BAAANQAECgIIAgABNQAFFAcIFAAcAFwRAA==.Maulo:BAACNQAFFIEUAAIcAAcKXBHzAAAMAgAcAAcKXBHzAAAMAgA1AAQKgRgAAhwACQpJHLgHAM4CABwACQpJHLgHAM4CAAAA.Maynaminty:BAAANQAECgYJEQAAAA==.',
Mc='Mclovin:BAAANQADCgUIBQAAAA==.',
Me='Medspriest:BAAANQAECgIIAgAAAA==.Megasoreass:BAAANQADCggICwAAAA==.Meliria:BAABNQAECoEYAAISAAgKuBhbIQCRAgASAAgKuBhbIQCRAgAAAA==.',
Mi='Microshanks:BAAANQADCggICQAAAA==.Midgert:BAACNQAFFIEMAAMPAAUKnwyAEABaAQAPAAQKkA+AEABaAQAQAAEK2wByBwBTAAA1AAQKgScAAg8ACQqUIeQeADsDAA8ACQqUIeQeADsDAAAA.Mimint:BAAANQAECgIIAgABNQAFFAcIGgAMAIQlAA==.Misfortune:BAAANQADCgUIBQAAAA==.Mistfit:BAAANQADCgYICgAAAA==.Mitula:BAAANQABCgUIAwAAAA==.',
Mo='Moadebe:BAAANQAECgIIAgAAAA==.Mommyenergy:BAAANQAECgQJBAABNQAECggIEAABAAAAAA==.Moomoomeadow:BAAANQAECgYJCAAAAA==.Moorpheus:BAAANQADCgYIBgAAAA==.Moreshaman:BAAANQADCgIJAQAAAA==.Morgianax:BAAANQAECgEIAQAAAA==.Morphsz:BAAANQAECgEIAQAAAA==.Morphunter:BAAANQAECgYIDQAAAA==.Mozerdozer:BAAANQADCgYIBgAAAA==.',
Mu='Muthabara:BAAANQADCggJCAAAAA==.Muwu:BAABNQAECoEbAAIXAAgKnST2EQBGAwAXAAgKnST2EQBGAwAAAA==.',
My='Myfursona:BAAANQAECgQJCAAAAA==.Mysticpizza:BAAANQADCgMJBAAAAA==.Mystrali:BAAANQAECgYICwAAAA==.Myztified:BAAANQADCgUIBQAAAA==.',
['Mã']='Mãyhem:BAAANQADCgIIAgABNQAECgIJAwABAAAAAA==.',
['Mä']='Mädrina:BAAANQADCggIFgAAAA==.',
Na='Naelyni:BAAANQAECgUIBQABNQADCggJCgABAAAAAA==.Naloxone:BAAANQADCgEIAQAAAA==.Nathrezara:BAAANQABCgIIAgAAAA==.Nawtikal:BAAANQAECgMIBAAAAA==.',
Nc='Nck:BAAANQADCgEIAQAAAA==.',
Ne='Necrootter:BAAANQAECgcJEAAAAA==.Negrumps:BAAANQADCgYJBwAAAA==.Nelune:BAAANQAECgYJCAAAAA==.Neoheals:BAAANQAECgEIAQAAAA==.Neotank:BAAANQADCgUIBQAAAA==.Netgehai:BAAANQADCgQIBAAAAA==.Neurosurgeon:BAAANQADCgEIAQAAAA==.Nezdh:BAACNQAFFIEVAAIRAAcKNhuAAAChAgARAAcKNhuAAAChAgA1AAQKgSQAAxEACQqqJRkCAMMDABEACQqqJRkCAMMDAAMABwqXHt4bACMCAAAA.',
Ni='Nizal:BAAANQAECgQIBAAAAA==.',
No='Nosimpin:BAAANQADCggIFwAAAA==.Notbrianp:BAAANQADCgMIAwABNQAECgUICAABAAAAAA==.Notbrianpage:BAAANQAECgUICAAAAA==.Nox:BAAANQADCggIDwAAAA==.',
Nu='Nutzferbuttz:BAAANQADCgYJBwABNQAECgUIDQABAAAAAA==.',
Ny='Nyllamage:BAACNQAFFIEGAAIPAAMK8gtjGgDyAAAPAAMK8gtjGgDyAAA1AAQKgRwAAg8ACQogIMUfADgDAA8ACQogIMUfADgDAAAA.',
['Nâ']='Nâ:BAAANQADCgIJAgAAAA==.',
Ob='Obdromeda:BAAANQAECgcJEgAAAA==.Oberron:BAAANQAECgYJEgABNQAECgkJHgAMAI0fAA==.',
Ok='Okixs:BAAANQAECgcJEAAAAA==.',
On='Onebaddruid:BAAANQAECgQICwAAAA==.Onebadwarr:BAABNQAECoEYAAIYAAgKigV8ugDZAAAYAAgKigV8ugDZAAABNQAECgQICwABAAAAAA==.',
Oo='Oogabgooga:BAAANQAECgUICAAAAA==.',
Os='Oscartheorc:BAAANQADCgEIAQABNQADCgIJAQABAAAAAA==.Oshamma:BAAANQAECgUIDQAAAA==.Ossoleil:BAAANQADCgYIBgABNQAECgUICAABAAAAAA==.',
Ot='Otterfang:BAAANQAECgUICwAAAA==.',
Oz='Ozatar:BAAANQAECgQIBAABNQAECgYICQABAAAAAA==.Ozcane:BAAANQAECgUIBQABNQAECgYICQABAAAAAA==.Ozen:BAAANQAECgYICQAAAA==.Ozlayn:BAAANQADCgUJCgABNQAECgYICQABAAAAAA==.Ozpal:BAAANQAECgUJDQABNQAECgYICQABAAAAAA==.Oztide:BAAANQAECgQICAABNQAECgYICQABAAAAAA==.Oztington:BAAANQADCgEIAQAAAA==.',
Pa='Paegan:BAAANQADCgQIBAAAAA==.Paiku:BAAANQADCgYICgAAAA==.Palaky:BAAANQAECgUICAAAAA==.Para:BAAANQAECgUJDgAAAA==.',
Pe='Peahole:BAAANQADCgQIBAAAAA==.Peccavi:BAAANQADCgYICQAAAA==.Pelusa:BAAANQAECgYIDQAAAA==.Penelopi:BAAANQAECgcJEgAAAA==.Penguinia:BAAANQAECgEJAQAAAA==.Pensman:BAAANQABCgQIBAAAAA==.',
Pi='Pillowpantsu:BAAANQADCggJCAAAAA==.Pitukis:BAAANQADCgYIBgAAAA==.',
Pl='Plandalorian:BAAANQAECgEJAQAAAA==.Platectonics:BAAANQADCgUJBwAAAA==.Plexadin:BAAANQAECgIIBAAAAA==.',
Po='Ponch:BAAANQADCgQIBAAAAA==.Popmybubble:BAABNQAECoEcAAMXAAgKcQ1RZgDKAQAXAAgKcQ1RZgDKAQAcAAIKPAezRABHAAAAAA==.',
Pr='Prepotenté:BAABNQAECoEdAAIYAAkKGhd0PQBxAgAYAAkKGhd0PQBxAgAAAA==.Priesta:BAABNQAECoEtAAIaAAkK8R6tDAAdAwAaAAkK8R6tDAAdAwAAAA==.Pronebone:BAAANQAECgcIEAAAAA==.',
Qu='Quomy:BAAANQAECgYJDQAAAA==.',
Ra='Rackblaster:BAAANQABCgMIAwAAAA==.Raei:BAABNQAECoEvAAILAAkKbxbAHQCiAgALAAkKbxbAHQCiAgAAAA==.Ragestrasz:BAAANQAECgcJDQAAAA==.Raladin:BAAANQAECgYJDQAAAA==.Ramchi:BAACNQAFFIEaAAMdAAcKKSF2AQBMAgAdAAYKtyB2AQBMAgAMAAQKNiAKAwCpAQA1AAQKgR8AAx0ACQo0JuICAJcDAB0ACQpsJeICAJcDAAwAAgofJoy+ANIAAAAA.Ramhorn:BAAANQAECgIJAgAAAA==.Ramsaur:BAABNQAECoEVAAIYAAgKEx53KADNAgAYAAgKEx53KADNAgAAAA==.Ranniel:BAAANQADCgEIAQAAAA==.Rasalghul:BAAANQADCgUIBgAAAA==.Ratchetron:BAAANQABCgMIAwAAAA==.Raythe:BAAANQADCgIIAwAAAA==.Razorfists:BAAANQAECgcIEgABNQAFFAYJEgAVADYLAA==.Razorscales:BAACNQAFFIESAAQVAAYKNgv+BwAVAQAVAAQKOgP+BwAVAQAhAAIKpApQCACKAAAiAAEKCALOBQBOAAA1AAQKgSoABBUACQonFb8PAFwCABUACQonFb8PAFwCACEABwqhHf8MAEMCACIAAQrVHawVAEoAAAAA.',
Re='Reckon:BAAANQADCggIGAAAAA==.Reeleaf:BAABNQAECoEeAAIUAAkKnBInEQBXAgAUAAkKnBInEQBXAgAAAA==.Reformedbtw:BAAANQAECgUJBAAAAA==.Remainn:BAAANQAECgEIAgAAAA==.Remlar:BAAANQAECgYICwABNQAECgkJJAADAKAZAA==.Renske:BAAANQADCgUIBgAAAA==.',
Ri='Ride:BAAANQAECgIJAwAAAA==.Rizzard:BAAANQAECgYIBwAAAA==.',
Ro='Ronanss:BAAANQABCgIJBAAAAA==.Roriel:BAABNQAECoEaAAIUAAgK7heCEQBRAgAUAAgK7heCEQBRAgAAAA==.Rougarou:BAAANQAECgUIBwAAAA==.Rowdyronda:BAAANQABCgIIBAAAAA==.Roweana:BAAANQAECgIJAgAAAA==.',
Ru='Rubmytotéms:BAAANQADCgUIBQABNQAECggIHAAXAHENAA==.Rumblecat:BAAANQAECgIJAgABNQAECgUJCwABAAAAAA==.',
Ry='Rylankneth:BAAANQADCgYIBgAAAA==.',
['Rî']='Rîce:BAAANQAECgYJDwAAAA==.',
Sa='Sabelorn:BAAANQAECgcJEwAAAA==.Sacredfear:BAABNQAECoElAAMGAAkKkx22FADuAgAGAAkKkx22FADuAgAEAAIKHA27TwBtAAAAAA==.Sacredshammy:BAABNQAECoEVAAMLAAgKZhHpPwDuAQALAAgKZhHpPwDuAQAKAAQKrRLcjAD3AAABNQAECgkJJQAGAJMdAA==.Sandayy:BAACNQAFFIEVAAMMAAcK3h37AwCFAQAdAAUKIhzWAwC/AQAMAAQK2iD7AwCFAQA1AAQKgScAAx0ACQq1JbQHAC0DAB0ACArXJLQHAC0DAAwABwpTJnwZAOECAAAA.Satsao:BAAANQADCgEIAQAAAA==.Sawario:BAAANQADCgMIAwAAAA==.',
Sc='Scalekyle:BAAANQAECgYIBgAAAA==.Screwheals:BAAANQAECgMJBAABNQAECggIHAAZAOoRAA==.',
Se='Sellene:BAACNQAFFIEYAAIUAAcKoSUjAACsAgAUAAcKoSUjAACsAgA1AAQKgSYAAhQACQqzJF4FADADABQACQqzJF4FADADAAAA.Sellina:BAAANQAECgIIAgABNQAFFAcIGAAUAKElAA==.Seneriya:BAAANQABCgIIAgAAAA==.Senorbang:BAAANQAECgYIDgAAAA==.Sep:BAABNQAECoEVAAILAAcKbRtlPQD5AQALAAcKbRtlPQD5AQAAAA==.Serenashadow:BAAANQADCgUIBQAAAA==.',
Sh='Shadowflare:BAAANQADCgcIEwAAAA==.Shaggsalt:BAAANQAECggJAwAAAA==.Shalth:BAAANQADCgIJAgAAAA==.Shaolinhunk:BAABNQAECoEbAAINAAgKxQ4rHADGAQANAAgKxQ4rHADGAQAAAA==.Sharks:BAABNQAECoEgAAIZAAkKkRwBEgDVAgAZAAkKkRwBEgDVAgAAAA==.Shawshanks:BAAANQADCggJAQABNQADCggICQABAAAAAA==.Shazzman:BAAANQAECgIJAgAAAA==.Shelandria:BAACNQAFFIEaAAMJAAcKgA6RAQAXAgAJAAYKfQ6RAQAXAgAjAAMKfwpfBAANAQA1AAQKgS4AAyMACQoSI84DAGMDACMACQpNIc4DAGMDAAkACQqcHbUDAEsDAAAA.Shiko:BAEANQAECgUJBAABNQAECggIHwAkAKAiAA==.Shiroee:BAAANQABCggIBwABNQAECgcJEAABAAAAAA==.Shoda:BAACNQAFFIERAAMMAAYKQBIyCAANAQAdAAUKtQwTBgCAAQAMAAMKqBkyCAANAQA1AAQKgSgAAx0ACQowI6IPALACAB0ACAqAIKIPALACAAwABgrsJCo5AFACAAAA.Shootrmcgávn:BAAANQAECgYJDAAAAA==.Shreker:BAABNQAECoEZAAIaAAkKXR3zHwCOAgAaAAkKXR3zHwCOAgAAAA==.',
Si='Sidchatic:BAAANQADCgEIAQAAAA==.Sidebo:BAAANQAECgEIAQAAAA==.Sinhunter:BAAANQAECgYICwAAAA==.Sirn:BAAANQAECgQJBAAAAA==.Sitonmytotem:BAAANQADCgQIBQABNQADCggICQABAAAAAA==.',
Sj='Sjp:BAAANQAECgIIAgABNQAECggIEAABAAAAAA==.',
Sk='Skeetoo:BAAANQAECggIEQAAAA==.Skeetwo:BAAANQADCggICAABNQAECggIEQABAAAAAA==.Skiera:BAAANQADCggICAABNQAECggIHAAHAB4hAA==.Skiplegs:BAABNQAECoEVAAIXAAgKARGvcQCoAQAXAAgKARGvcQCoAQAAAA==.Skorpeo:BAAANQADCggICQAAAA==.',
Sl='Slimes:BAAANQADCgIIAgAAAA==.Slimxx:BAAANQADCgYJDgAAAA==.',
Sm='Smargendk:BAAANQADCgYIBwAAAA==.Smargenrog:BAACNQAFFIEPAAIIAAYK2B5CAABYAgAIAAYK2B5CAABYAgA1AAQKgSIAAggACQpxJRsBAKkDAAgACQpxJRsBAKkDAAAA.',
Sn='Snaven:BAAANQAECgUJCAAAAA==.Sneggs:BAAANQADCggJGQAAAA==.Snifellz:BAAANQAECgcICwAAAA==.Snifflez:BAAANQAECgQICAABNQAECgcICwABAAAAAA==.Snipermonkey:BAAANQAECgYJEgAAAA==.',
So='Soiled:BAAANQAECgEIAQAAAA==.Solidshaft:BAAANQAECgIIAwAAAA==.Solikar:BAAANQADCggJEwAAAA==.Sopheia:BAAANQAECgQIBQAAAA==.Soul:BAABNQAECoEgAAIPAAkKax+/JQAiAwAPAAkKax+/JQAiAwAAAA==.',
Sp='Spek:BAABNQAECoEgAAMKAAkKMyLUFwDtAgAKAAgK4yLUFwDtAgALAAIKFhFBuQBrAAAAAA==.Split:BAAANQAECgYJEgAAAA==.Springonion:BAAANQAECggIEgABNQAFFAcIFwALANEMAA==.',
Sq='Squidward:BAABNQAECoEnAAIDAAkKxyCABwA9AwADAAkKxyCABwA9AwAAAA==.',
Ss='Ssbraun:BAAANQADCgUJBQAAAA==.',
St='Standardhors:BAAANQADCggICAABNQAECggIHgAKAMsjAA==.Steadchi:BAAANQAECgYJBgAAAA==.Steadyy:BAAANQABCgQIBAAAAA==.Steakburrito:BAAANQAECgQIBAAAAA==.Stedk:BAACNQAFFIEPAAIZAAYKZCPrAABhAgAZAAYKZCPrAABhAgA1AAQKgSAAAhkACQqVJkEBANkDABkACQqVJkEBANkDAAAA.Stepally:BAABNQAFFIEGAAIcAAYKyBGBAQDAAQAcAAYKyBGBAQDAAQAAAA==.Steven:BAAANQAECgYIDgABNQAFFAQIDQAKAH0LAA==.Strongmace:BAAANQADCgIJAgABNQAECgEJAQABAAAAAA==.Strongshift:BAAANQAECgEJAQAAAA==.Stygwyggyr:BAAANQAECgYIDgAAAA==.',
Su='Suebird:BAAANQAECgQIBAABNQAECgkJGQAaAF0dAA==.Sugarzcoat:BAAANQAECggIEgAAAA==.Sulphurous:BAAANQAECgcIBwAAAA==.Sunlight:BAAANQADCgEIAQAAAA==.Supdudejr:BAAANQAECgcJEwAAAA==.Supernovi:BAAANQADCggICAAAAA==.',
Sw='Sweetstache:BAAANQABCgQIBgAAAA==.Swiftus:BAAANQADCgEIAQAAAA==.Swippin:BAAANQADCgYIBwABNQAECgYIDQABAAAAAA==.',
Sy='Syenite:BAAANQAECgUIBQAAAA==.Sykomike:BAABNQAECoEaAAMMAAkKOx6vDgAtAwAMAAkKOx6vDgAtAwAdAAEKxAKbYwAsAAAAAA==.Sylarria:BAAANQADCgYJBgAAAA==.Syler:BAABNQAECoEjAAIjAAkKWSLjAwBgAwAjAAkKWSLjAwBgAwAAAA==.Sylár:BAAANQAECgQIBAAAAA==.Symbol:BAAANQABCgQIBAAAAA==.Syreal:BAAANQADCgYICAAAAA==.',
['Sä']='Säcred:BAAANQAECgMIBQABNQAECgkJJQAGAJMdAA==.',
Ta='Tahlia:BAABNQAECoEeAAIUAAgKxh86CwC4AgAUAAgKxh86CwC4AgAAAA==.Talren:BAAANQAECgYJBwAAAA==.Talìa:BAAANQAECgUJDgAAAA==.Tannadà:BAAANQAECgcIEQAAAA==.Tasari:BAACNQAFFIEVAAIOAAcKoCANAAC1AgAOAAcKoCANAAC1AgA1AAQKgScAAg4ACQr4JXUAAOIDAA4ACQr4JXUAAOIDAAAA.Taurenadin:BAAANQADCgIIAgAAAA==.Tayson:BAAANQADCgEIAQAAAA==.Tazzdingo:BAAANQABCgUIBQAAAA==.',
Te='Tekain:BAAANQAECgEIAQAAAA==.Tequilla:BAAANQADCggICgAAAA==.Terryn:BAAANQAECgEIAQAAAA==.Tesia:BAAANQADCgUICgAAAA==.',
Th='Thedeadlypug:BAAANQADCggIDgAAAA==.Theeripper:BAAANQAECgUJCAAAAA==.Thrashwar:BAAANQAECgUJCAAAAA==.Thrustie:BAAANQAECgcJDgAAAA==.Thusios:BAAANQAECgcIDQAAAA==.',
Ti='Tiazz:BAAANQADCgUIBQAAAA==.Tichu:BAAANQAECgUICAAAAA==.Tiekho:BAAANQADCgUIBQAAAA==.Tifaun:BAAANQADCgUIBQAAAA==.Tifelia:BAAANQAECgEJAQAAAA==.Tigorain:BAAANQADCgcIBgAAAA==.Tizirk:BAAANQAECggICAAAAA==.',
To='Toastybutter:BAAANQADCgYIDAAAAA==.Tonyz:BAAANQAECggIDQAAAA==.Torrak:BAABNQAECoEcAAIlAAgKgh2WBQCmAgAlAAgKgh2WBQCmAgAAAA==.Torthie:BAACNQAFFIEVAAMPAAcKixj7AgBAAgAPAAYKehv7AgBAAgAQAAEK8gYXBQBdAAA1AAQKgScAAw8ACQqwI8wPAH4DAA8ACQqwI8wPAH4DABAAAQqmIYwlAFkAAAAA.Tothdk:BAAANQAFFAYIAQAAAA==.Toxaaris:BAAANQADCgIJAgAAAA==.',
Tr='Trale:BAAANQADCgQJBAAAAA==.Treason:BAAANQADCgYIBwABNQADCggIGAABAAAAAA==.Treeage:BAAANQAECgIJBAAAAA==.Tripp:BAAANQAECgIJAwAAAA==.Troeg:BAAANQABCgUIAwAAAA==.Trollerella:BAAANQADCgQIBAABNQAECgkJJAADAKAZAA==.Trollzealot:BAAANQAECgMIAwAAAA==.Tronxx:BAAANQADCgQIBAAAAA==.Troxigar:BAAANQAECgUIBwAAAA==.',
Tu='Tullyspring:BAAANQADCggJDwAAAA==.Turkeysub:BAAANQADCggIEQAAAA==.',
Tv='Tverdydh:BAAANQAECgYICgAAAA==.Tverdydk:BAAANQAECgMIBwAAAA==.',
Tw='Twertlekat:BAAANQAECgYIDwAAAA==.Twinkiez:BAAANQAECgQJBQABNQAECggIEgABAAAAAA==.Twistkun:BAAANQAECgUIBQAAAA==.',
Un='Unclehog:BAAANQAECgUJCAAAAA==.Unfixable:BAAANQAECgQJBwABNQAFFAYIDwABAAAAAQ==.Unplayable:BAAANQAFFAYIDwAAAQ==.Unusualhorse:BAABNQAECoEeAAMKAAgKyyNpDwA5AwAKAAgKyyNpDwA5AwALAAcKFB6EJAB5AgAAAA==.',
Uu='Uunfar:BAABNQAECoEgAAILAAgKkCU6BwBhAwALAAgKkCU6BwBhAwAAAA==.',
Va='Valby:BAAANQABCgYJCAAAAA==.Valedia:BAAANQAECgYJDQAAAA==.Valn:BAAANQAECgUJCQAAAA==.Valtross:BAAANQAECgEJAQAAAA==.Vangough:BAABNQAECoEdAAIYAAgK9RtQOQCBAgAYAAgK9RtQOQCBAgAAAA==.Vayu:BAAANQADCgQIBAAAAA==.',
Ve='Velvetvixen:BAAANQAECgcJEQAAAA==.',
Vi='Violaswamp:BAAANQADCgMIAwAAAA==.Viper:BAABNQAECoEgAAMjAAkKshtDCAAGAwAjAAkKshtDCAAGAwAJAAMKMROBMQDFAAAAAA==.',
Vl='Vlad:BAAANQAECggIEAAAAA==.',
Vo='Voreâu:BAAANQADCgEIAQAAAA==.Vosslar:BAAANQAECgUJDgAAAA==.Vosslarr:BAAANQADCgMIAwAAAA==.',
Vv='Vvarden:BAAANQAECgIIAgAAAA==.',
['Vî']='Vîper:BAAANQAECgMJAwAAAA==.',
Wa='Waarrlockk:BAACNQAFFIERAAMGAAYKTBjZBgBQAQAGAAQK5xTZBgBQAQAEAAIKFR+vBAC/AAA1AAQKgSgABAQACQorJc0BAEEDAAQACQqcH80BAEEDAAYABwo7JIAZAM8CAAUAAQpDI3oXAGcAAAAA.Walrusrider:BAAANQAECgcIEAAAAA==.Wang:BAABNQAECoEcAAINAAkKfRopDgCbAgANAAkKfRopDgCbAgAAAA==.Warbird:BAAANQAECgYJEAAAAA==.Warhmonger:BAAANQADCggJCQAAAA==.Wassy:BAAANQAECgYJDgAAAA==.Watharaim:BAAANQADCgUIBQABNQAECggIHAAXAHENAA==.',
We='Wemgobyama:BAACNQAFFIEJAAIdAAQK+h7TBgBoAQAdAAQK+h7TBgBoAQA1AAQKgSgABB0ACQr7I4UDAIcDAB0ACQq3I4UDAIcDAAwAAgqaI57IAK4AACYAAQpWAP0OABMAAAAA.',
Wh='Whispy:BAAANQABCgIIAgAAAA==.Whm:BAAANQAECgQIBQAAAA==.Whobe:BAABNQAECoEdAAIJAAkK6g6vDwBOAgAJAAkK6g6vDwBOAgAAAA==.',
Wi='Witherfang:BAAANQAECgMIBQAAAA==.Wizsera:BAAANQAECgIIAgABNQAECgcIIQAKAPYdAA==.Wizshock:BAABNQAECoEhAAIKAAcK9h1/MgA7AgAKAAcK9h1/MgA7AgAAAA==.',
Wn='Wnred:BAACNQAFFIERAAMhAAYKUhx6AQDMAQAhAAUKrBx6AQDMAQAiAAQK2BYMAgBjAQA1AAQKgSgAAyIACQqdJQoBAHcDACIACQqTIwoBAHcDACEACAp+JdwDAD4DAAAA.',
Wo='Wombly:BAAANQADCggIDwAAAA==.Womboree:BAABNQAECoEYAAIeAAgK+h/zEQD5AgAeAAgK+h/zEQD5AgAAAA==.Wonderful:BAAANQADCgcIAgAAAA==.Woobie:BAAANQADCgEIAQAAAA==.Wos:BAAANQAECgEIAQAAAA==.',
Xa='Xanarius:BAAANQAECgYJCwAAAA==.',
Ye='Yellowslice:BAAANQADCgQIBAAAAA==.Yeofp:BAAANQADCgUIBQAAAA==.',
Yk='Ykime:BAAANQADCgEIAQAAAA==.',
Yu='Yukarna:BAAANQAECgcIEwAAAA==.Yukionná:BAAANQADCgYJBgAAAA==.',
Za='Zaafkiel:BAABNQAECoEYAAQcAAcKNhZlIgA7AQAcAAUK9hZlIgA7AQAXAAYKhArkogAkAQASAAQKJwWYnQDIAAAAAA==.Zabuza:BAAANQADCgUIBQAAAA==.Zanaroth:BAAANQAECgIJAgAAAA==.Zandrissil:BAEANQADCgYIBgABNQAECgYIDQABAAAAAA==.Zarafie:BAEANQADCgYIDAABNQAECgYIDQABAAAAAA==.Zarantharia:BAEANQADCgMIAwABNQAECgYIDQABAAAAAA==.Zaraphym:BAEANQAECgYIDQAAAA==.Zarazlow:BAEANQADCgQIBAABNQAECgYIDQABAAAAAA==.Zarreh:BAAANQADCggIHQAAAA==.',
Ze='Zephyrine:BAAANQADCgQIBAAAAA==.Zexan:BAAANQAECgEIAQAAAA==.',
Zh='Zhuzhu:BAAANQAECgYIEQAAAA==.',
Zi='Zigy:BAABNQAECoEgAAIlAAgK+yFoAwALAwAlAAgK+yFoAwALAwAAAA==.',
Zo='Zoeý:BAAANQADCgcIBwAAAA==.Zombie:BAAANQAECgUJDgAAAA==.',
Zu='Zukko:BAAANQAECgUIBwAAAA==.Zulkaris:BAAANQADCggICAAAAA==.Zuroxxar:BAEANQAECgIJAgABNQAECgYIDQABAAAAAA==.Zuwitsudh:BAAANQADCgQIBAAAAA==.',
Zy='Zynny:BAAANQAECgcIEwAAAA==.',
['Zë']='Zëll:BAAANQADCggJEQAAAA==.',
['Åa']='Åa:BAAANQAECgEJAwABNQAECggJGwABAAAAAA==.',
['Ðo']='Ðolo:BAAANQADCgQICAABNQAECgUJDgABAAAAAA==.',
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
