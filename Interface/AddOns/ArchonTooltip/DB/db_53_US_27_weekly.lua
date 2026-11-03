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

local lookup = {'DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Mage-Arcane','Druid-Guardian','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Paladin-Retribution','Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Mage-Frost','Priest-Holy','DemonHunter-Devourer','Warrior-Protection','Shaman-Restoration','Rogue-Subtlety','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Devastation','Druid-Balance','Warrior-Fury','Rogue-Assassination','Rogue-Outlaw','Monk-Brewmaster','Monk-Windwalker','Evoker-Preservation','Druid-Feral','Priest-Discipline','Evoker-Augmentation','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-11-03',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAABNQAECn8VAAQBAAgKFwpfUwALAQABAAcKtwlfUwALAQACAAEKCRQdjAA8AAADAAEKRQO5hwAgAAAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQAECgYIBQAAAA==.Adura:BAAANQADCggICwAAAA==.',
Ae='Aeirith:BAABNQAECn8xAAIEAAoKmxzRKQB6AgAEAAoKmxzRKQB6AgAAAA==.',
Ai='Ailsà:BAAANQADCgIIAgABNQAECgYIIQAFAA8SAA==.Airius:BAAANQAECgQIBAAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAABNQAECn8XAAIGAAkK7hsMLwAlAgAGAAkK7hsMLwAlAgAAAA==.Amarasu:BAABNQAECn8gAAIHAAgKfhAPBwBwAQAHAAgKfhAPBwBwAQAAAA==.Amarlly:BAABNQAECn8fAAIBAAgKHRB4RwCgAQABAAgKHRB4RwCgAQAAAA==.',
An='Ancelina:BAABNQAECn8dAAIIAAcKYR9RFgC/AQAIAAcKYR9RFgC/AQAAAA==.Anderton:BAABNQAECn9DAAIJAAkKjxJ/eACdAQAJAAkKjxJ/eACdAQAAAA==.Andilocks:BAAANQAECgEIAQAAAA==.Anditracks:BAAANQAECgEIAQAAAA==.Andraenei:BAABNQAECn8gAAIKAAYKUA52pQBJAQAKAAYKUA52pQBJAQAAAA==.Andrela:BAAANQAECgIIAgAAAA==.Andromadda:BAAANQADCgcIBwAAAA==.Aneira:BAABNQAECn8hAAIFAAYKDxLtKABPAQAFAAYKDxLtKABPAQAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECgkJJgAGAN4aAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECn9JAAICAAoKmyMRCgBkAwACAAoKmyMRCgBkAwAAAA==.Archérhiro:BAACNQAFFH8XAAMLAAcKgRogBgBcAQALAAcKgRogBgBcAQAMAAEKAAAfKAA1AAA1AAQKf0gAAwsACgp0JGEIADUDAAsACgp0JGEIADUDAAwABQpTEANFADEBAAAA.Arillann:BAABNQAECn8yAAINAAoKByHaBwAjAwANAAoKByHaBwAjAwAAAA==.Arin:BAAANQAECgQIBgABNQAECgoKHgAOAOwXAA==.Arms:BAAANQAECgcICwABNQAECgoKLAAJAFAYAA==.Arrook:BAAANQAECgQIBQAAAA==.Artdemsamis:BAABNQAECn8aAAQPAAoKPBEWNgDpAAAGAAgKEhCymACpAQAPAAQKqw4WNgDpAAAQAAEKAAD+KwAAAAAAAA==.Arttimar:BAAANQAECggICAAAAA==.Arvena:BAAANQADCgQIBAAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgARAAAAAA==.Ashylock:BAABNQAECn8fAAIGAAoKlBTKUQBgAgAGAAoKlBTKUQBgAgABNQAFFAUIEwAEAFUbAA==.Ashymage:BAACNQAFFH8TAAIEAAUKVRt8FQAPAQAEAAUKVRt8FQAPAQA1AAQKf0EAAwQACgoDJcgWAHgDAAQACgoDJcgWAHgDABIAAQrTCu1GADYAAAAA.Askevar:BAABNQAECn8eAAIDAAcKowgLPgDuAAADAAcKowgLPgDuAAAAAA==.Asriél:BAABNQAECn8ZAAILAAkKtBn1YwBNAgALAAkKtBn1YwBNAgAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgQIBQABNQAFFAUIDwATAA8RAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAABNQAECn8dAAIJAAkKLAN5AQGuAAAJAAkKLAN5AQGuAAAAAA==.',
Az='Azaleah:BAABNQAECn82AAIJAAoKEBGJegA2AgAJAAoKEBGJegA2AgAAAA==.Azlan:BAAANQAECgEIAgAAAA==.Azraesha:BAABNQAECn8mAAIUAAoKIRFhGgCkAQAUAAoKIRFhGgCkAQAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQAECgUIBAAAAA==.',
Be='Beareold:BAAANQAECgEIAgAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQIDQAAAA==.Bigjuicy:BAAANQAECgEIAQAAAA==.Bigmon:BAABNQAECn9ZAAMOAAoKuSFsIQAyAwAOAAoKuSFsIQAyAwAVAAEKgA/SRAAvAAAAAA==.Billie:BAAANQAECgEIAgAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgYIDAAAAA==.Blackstaff:BAAANQADCggIEQABNQAECgcIHgAFAGocAA==.Blessthefall:BAAANQAECggICQAAAA==.Bloodygrundl:BAABNQAECn8wAAICAAoK4yBVEAAqAwACAAoK4yBVEAAqAwAAAA==.Bluestorm:BAABNQAECn8cAAIKAAkKSgJ5lQCoAAAKAAkKSgJ5lQCoAAAAAA==.',
Bo='Bonegrinda:BAABNQAECn8qAAIDAAkK/R6rMgBhAgADAAkK/R6rMgBhAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwARAAAAAA==.',
Br='Branwynn:BAAANQAECgIIAwAAAA==.Brigor:BAAANQAECgIIAgABNQAECgcIHgAFAGocAA==.Bringg:BAAANQAECgQIBAAAAA==.',
Bu='Budgetcuts:BAAANQADCgYIBgAAAA==.Bulldoza:BAAANQADCgQIBAAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgIIAwAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgMIBAAAAA==.Camrookie:BAAANQADCgYIBgAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAABNQAECn8dAAIOAAoKHwXJlAAgAQAOAAoKHwXJlAAgAQAAAA==.Ceri:BAAANQAECggICQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFH8YAAIWAAcK1h8LBABFAgAWAAcK1h8LBABFAgA1AAQKfzQAAhYACgo0JfQIAHoDABYACgo0JfQIAHoDAAAA.Chantix:BAAANQAECgEIAQAAAA==.Chaosshadow:BAABNQAECn8oAAIIAAkKQRFHFwCxAQAIAAkKQRFHFwCxAQAAAA==.Chaosti:BAABNQAECn8XAAIDAAkKlwp2bABhAQADAAkKlwp2bABhAQAAAA==.Cheekymonkey:BAABNQAECn8rAAIEAAoKbQmFiABoAQAEAAoKbQmFiABoAQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Chueyé:BAAANQAECgUIBQABNQAECgoKPwAXAIAgAA==.Chune:BAAANQADCgEIAQABNQAECgcIHgAFAGocAA==.Churros:BAAANQAECggIDgABNQAECgkJJgAGAN4aAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Conqueefador:BAAANQAECgIIAwAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECn8mAAIYAAYKtR2ecwC9AQAYAAYKtR2ecwC9AQAAAA==.Crosslock:BAAANQADCgcICwAAAA==.',
Cu='Cuack:BAAANQAECgEIAQAAAA==.',
Cy='Cynnari:BAABNQAECn8kAAIGAAcKvQjmlwDyAAAGAAcKvQjmlwDyAAAAAA==.',
Da='Dagnabit:BAAANQAECgMIAwABNQAECgcIHgAFAGocAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAABNQAECn8nAAIZAAgKvg8DMQBSAQAZAAgKvg8DMQBSAQAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgcIHgALAIUMAA==.',
De='Deathmare:BAABNQAECn8gAAMZAAkK+Qs4JgCcAQAZAAkKngs4JgCcAQAaAAQKdAf6IQCzAAAAAA==.Deathty:BAAANQAECggIEQABNQAECgoKKAALAAoaAA==.Deeptroat:BAAANQADCgEIAQABNQAECggIIAAHAH4QAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECn8tAAMGAAgKAhTqdQAAAgAGAAgKAhTqdQAAAgAQAAEKAAAfMQAzAAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAABNQAECn8VAAQBAAUKiA/UbwDfAAABAAQKQw/UbwDfAAADAAIKtQRBzABUAAACAAEK0g1PywAzAAAAAA==.Diltlish:BAAANQAECgUIDQAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECn8nAAIOAAkKYBslfwAdAgAOAAkKYBslfwAdAgAAAA==.',
Dm='Dmginc:BAAANQAECgQIDQAAAA==.',
Do='Doeblin:BAAANQAECgEIAQAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgQIBgAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAABNQAECn8XAAIIAAYKKwPGPwB9AAAIAAYKKwPGPwB9AAAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAABNQAECn8nAAIEAAoKixAznwBDAgAEAAoKixAznwBDAgAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQAECgUICAAAAA==.Drakkei:BAABNQAECn85AAILAAoKORX6SQD/AQALAAoKORX6SQD/AQABNQAECgoKPQAFAEkUAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQAECgQIBQAAAA==.Drylo:BAEBNQAECn8rAAIbAAkKhiIoBgAqAwAbAAkKhiIoBgAqAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQAECgEIAQAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgUIBwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECggIDAAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
En='Endrin:BAAANQAECgEIAQAAAA==.',
Er='Erf:BAAANQADCgYIDgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECn8sAAIcAAoKOw1qSwC3AQAcAAoKOw1qSwC3AQAAAA==.',
Et='Ethellin:BAABNQAECn8pAAIJAAgK7wTRBQEVAQAJAAgK7wTRBQEVAQAAAA==.',
Eu='Euph:BAAANQAECgYIEAAAAA==.',
Ev='Evilhearts:BAAANQAECgQIBAAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgYIEwABNQAECgoKNwAJAEMmAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBwABNQAECgUIEAARAAAAAA==.Feleria:BAAANQAECgEIAQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluffbutt:BAAANQAECgEIAQAAAA==.Fluxarata:BAABNQAECn8aAAIUAAcK4gehQgA6AQAUAAcK4gehQgA6AQAAAA==.',
Fr='Fred:BAABNQAECn8VAAIdAAcKQge1FgDPAAAdAAcKQge1FgDPAAAAAA==.Friendly:BAABNQAECn86AAMeAAoK2SRbBQB+AwAeAAoKeyRbBQB+AwAXAAkKox+qCwACAwAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgYIDwAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fupacabra:BAAANQADCgcIBwAAAA==.Fuzzyhunter:BAAANQADCgcIEQAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgYIIQAFAA8SAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAABNQAECn8nAAILAAoK1BnFPwCrAgALAAoK1BnFPwCrAgAAAA==.Gagageoff:BAAANQAECgEIAQAAAA==.Gardyson:BAABNQAECn8uAAMVAAoKCg0fIABOAQAOAAoKYwkcsQCiAQAVAAgK0A0fIABOAQAAAA==.Garwarmegad:BAAANQAECgQIBQAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Gn='Gnomew:BAAANQAECgUIBAAAAA==.',
Go='Gobsprocket:BAAANQADCggICAAAAA==.Gojira:BAAANQAECgEIAQAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECn82AAIMAAoKExOVEwDRAQAMAAoKExOVEwDRAQAAAA==.Grenadeout:BAABNQAECn8cAAQXAAkKZBs+JgA3AgAXAAkKZBs+JgA3AgAeAAMKahY8cwDkAAAfAAEKAAB1GQBNAAAAAA==.Grimaldus:BAAANQAECgIIAQABNQAECgYICwARAAAAAA==.',
Ha='Harrod:BAAANQAECgIIAgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQARAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAABNQAECn8WAAMgAAgKAhdbDQAlAgAgAAgKAhdbDQAlAgAhAAYK4ADnbQAuAAAAAA==.Hellsspawn:BAAANQADCgUIDAAAAA==.',
Ho='Hokàge:BAABNQAECn8/AAMXAAoKgCDRGACSAgAXAAoKpB/RGACSAgAeAAcKixwXLAA4AgAAAA==.Holyprom:BAAANQADCgUIBQAAAA==.Homealone:BAABNQAECn8dAAMWAAkKoAx3TQCqAQAWAAkKoAx3TQCqAQAKAAMKnQFSFAFkAAAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQAECgUIBwABNQAECgoKKAAIAKcQAA==.Huntinfuzzy:BAABNQAECn8bAAILAAgKjwnktACaAQALAAgKjwnktACaAQAAAA==.Huugg:BAAANQAECgQIBAAAAA==.',
Hy='Hymncarrey:BAABNQAECn8kAAITAAcK/COfLAC2AgATAAcK/COfLAC2AgAAAA==.Hynkie:BAABNQAECn8kAAITAAoKzBNRLwBRAgATAAoKzBNRLwBRAgABNQAECgoKKgAiALgXAA==.',
Id='Idari:BAAANQABCgEIAQAAAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECggIEgARAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAABNQAECn8zAAQQAAkKpxybBAAOAgAQAAkKpxybBAAOAgAGAAYKXA5dtgBiAQAPAAEK4wZnfwAtAAAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECggIIAAHAH4QAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECn8aAAIJAAkKThjsbgBSAgAJAAkKThjsbgBSAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQARAAAAAA==.',
Je='Jellytown:BAABNQAECn8vAAISAAoKBxmMBQC3AgASAAoKBxmMBQC3AgAAAA==.Jelorinea:BAAANQADCgYIBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Judgementalx:BAAANQAECgIIAgAAAA==.Juicifer:BAAANQAECgEIAwAAAA==.Juicylucy:BAAANQAECgEIAQAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQAECgMIAwAAAA==.Justine:BAAANQAECgMIBQAAAA==.',
['Jô']='Jôhnwick:BAABNQAECn8dAAIMAAkKZw4UKwDyAQAMAAkKZw4UKwDyAQAAAA==.',
Ka='Kaedas:BAAANQAECgUIBQABNQAECgoKPQAFAEkUAA==.Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECn8vAAILAAoKQhS7UgB4AgALAAoKQhS7UgB4AgAAAA==.Kaladil:BAAANQAECgMIBwAAAA==.Kamaren:BAAANQAECgMIBQAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgQICwAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Ke='Kelaino:BAAANQABCgYIBgAAAA==.',
Kh='Khota:BAAANQAECggICwAAAA==.',
Ki='Killanick:BAAANQAECgUIBQAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQAECgcICgAAAA==.',
Ku='Kurtina:BAABNQAECn85AAIOAAoKyBQxTADpAQAOAAoKyBQxTADpAQAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAABNQAECn8oAAILAAoKChrELgBZAgALAAoKChrELgBZAgAAAA==.Larac:BAAANQAECggIDQAAAA==.',
Le='Leddy:BAAANQADCgUICQAAAA==.Leif:BAABNQAECn8uAAIbAAoKbhaBCQCqAQAbAAoKbhaBCQCqAQAAAA==.Lemmart:BAABNQAECn8dAAIQAAkKPw3MCgBNAQAQAAkKPw3MCgBNAQAAAA==.Lenik:BAAANQAECgYIEQAAAA==.',
Li='Licorice:BAABNQAECn8mAAMGAAkK3ho5OgD4AQAGAAkK3ho5OgD4AQAPAAEKEwvQewAxAAAAAA==.Lieree:BAABNQAECn8lAAIEAAoKign63gDKAQAEAAoKign63gDKAQAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgYICgAAAA==.',
Lo='Lockty:BAABNQAECn8mAAIGAAoKMRGQRwDIAQAGAAoKMRGQRwDIAQABNQAECgoKKAALAAoaAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.Lorian:BAAANQAECgYICQAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAEANQAECgIIAwAAAA==.Lucity:BAAANQAECgcIEQABNQAECgkJGgAJAE4YAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQAECgEIAQAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQARAAAAAA==.Lunà:BAAANQAECgQICQAAAA==.',
Ly='Lystral:BAAANQAECgUICwAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
['Lá']='Lásh:BAAANQAECgYICwABNQAECgYIIQAFAA8SAA==.',
Ma='Mace:BAABNQAECn8lAAIJAAoKqB/RHgBIAwAJAAoKqB/RHgBIAwAAAA==.Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQAECgMIAgABNQAECgoKPwAXAIAgAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQAECgEIAQABNQAECgoKLgAVAAoNAA==.Malìficus:BAAANQADCgcIBwAAAA==.Manadâr:BAAANQAECgUIBgAAAA==.Manawave:BAAANQAECggICAAAAA==.Marinas:BAAANQADCgcIFgAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgQICQAAAA==.Mazumaragg:BAAANQAECgQICAABNQAECgoKLgAVAAoNAA==.',
Me='Mediocre:BAAANQAECgMIAwAAAA==.Mello:BAAANQAECgMIAwAAAA==.',
Mi='Miande:BAAANQAECgYICgAAAA==.Microburst:BAABNQAECn8wAAIKAAoKYgeAWgA7AQAKAAoKYgeAWgA7AQAAAA==.Milamagi:BAAANQADCgYIBgAAAA==.Minilock:BAABNQAECn8nAAQGAAoKtQknXQCDAQAGAAoKtQknXQCDAQAPAAMKwgHqYQBhAAAQAAEKDAcpMgAwAAAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEIAQAAAA==.Missused:BAAANQAECgEIAQAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIEAARAAAAAA==.Mièlikki:BAABNQAECn8eAAIFAAcKahyVGACLAQAFAAcKahyVGACLAQAAAA==.',
Mo='Modelotime:BAAANQADCggICwAAAA==.Modsagoodtnk:BAAANQADCggICQABNQAECgEIAgARAAAAAA==.Mongermook:BAABNQAECn8aAAMFAAgKRg2nKABRAQAFAAgKRg2nKABRAQAjAAEK4QivPQAwAAAAAA==.Monnkysham:BAAANQAECgIIAwAAAA==.Montclair:BAAANQAECgEIAgABNQAECgkJGQAYAFMTAA==.Mooglefur:BAAANQADCgcICAAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECn8lAAIWAAgKThe7VwCDAQAWAAgKThe7VwCDAQAAAA==.Nacronor:BAAANQAECgEIAQAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgcICgAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQICQAAAA==.Nickita:BAAANQAECgQIBwAAAA==.Nicky:BAAANQAECgEIAQAAAA==.Nightgear:BAACNQAFFH8WAAILAAcKHRHfAwAhAgALAAcKHRHfAwAhAgA1AAQKf1kAAgsACgrdIjcXAMgCAAsACgrdIjcXAMgCAAAA.Nighti:BAAANQADCgQIBAAAAA==.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgQIDwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECn89AAMFAAoKSRRtFwD3AQAFAAkKFBZtFwD3AQAcAAkKvwd5QQDvAAAAAA==.',
Od='Ode:BAABNQAECn8uAAIEAAoKqgtMZQC9AQAEAAoKqgtMZQC9AQAAAA==.Odex:BAABNQAECn8aAAIbAAkKnQoIDABiAQAbAAkKnQoIDABiAQAAAA==.',
On='Onlymages:BAABNQAECn8oAAIEAAcK3AzkswATAQAEAAcK3AzkswATAQAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECn8oAAMIAAoKpxDBGACeAQAIAAoKpxDBGACeAQAkAAMKhgtAGwCOAAAAAA==.',
Ou='Outdeath:BAAANQAECgMIAwABNQAECgcIGwAOAGsJAA==.Outheal:BAAANQAECgQIBQABNQAECgcIGwAOAGsJAA==.Outkíll:BAABNQAECn8bAAIOAAcKawm8ogABAQAOAAcKawm8ogABAQAAAA==.',
Pa='Pally:BAABNQAECn8sAAIJAAoKUBh9SgAWAgAJAAoKUBh9SgAWAgAAAA==.Pandarweb:BAAANQAECgUIBwAAAA==.Papasmurfz:BAAANQAECgUIBQAAAA==.Pathogen:BAABNQAECn8wAAIDAAoKfiPqCQBuAwADAAoKfiPqCQBuAwAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAABNQAECn8sAAIBAAkK9hE8MACsAQABAAkK9hE8MACsAQAAAA==.Perve:BAABNQAECn8VAAITAAkKFgmwWgCYAQATAAkKFgmwWgCYAQABNQAECgkJGQALALQZAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pippy:BAAANQAECgIIAgAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.',
Pr='Prom:BAAANQADCggIEQAAAA==.Promethèus:BAABNQAECn8kAAIEAAoKxxkUSgDuAgAEAAoKxxkUSgDuAgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQAECggIAQAAAA==.Quansamdi:BAAANQAECggIAgAAAA==.Queedle:BAABNQAECn8qAAIfAAoKTgsvAwCUAQAfAAoKTgsvAwCUAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Ragnarook:BAAANQAECgEIAQABNQAECgIIAgARAAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFH8SAAIbAAcK/RDqAgDXAQAbAAcK/RDqAgDXAQA1AAQKf3IAAxsACgqAITIDAHcDABsACgqAITIDAHcDACUAAQo4AwIcAB8AAAAA.Ramike:BAABNQAECn8qAAIVAAkKjBpiDQBcAgAVAAkKjBpiDQBcAgAAAA==.Randal:BAAANQABCgQIBAAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQAECgIIBAAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgoKPwAXAIAgAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rinà:BAAANQAECgcICAAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECn8vAAIOAAoKVhqDSgCqAgAOAAoKVhqDSgCqAgAAAA==.',
Ro='Robbert:BAAANQAECggICAAAAA==.Rosara:BAABNQAECn8ZAAIYAAkKUxPGMgAgAgAYAAkKUxPGMgAgAgAAAA==.',
Rr='Rrook:BAAANQADCgQICAAAAA==.',
Ry='Ryanrainolds:BAAANQAECgYIBgABNQAECgcIJAATAPwjAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgARAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Sacredjuice:BAAANQAECgEIAQAAAA==.Saela:BAAANQAECgEIAQAAAA==.Sakúra:BAAANQAECgUICQAAAA==.Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQAECgQICAAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgUIBwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAEANQADCgYIBgABNQAECgIIAwARAAAAAA==.',
Si='Sieya:BAAANQAECgEIAQAAAA==.Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECggIDgAAAA==.Skullace:BAABNQAECn8hAAIGAAgK8AYkiAAXAQAGAAgK8AYkiAAXAQAAAA==.Skullhead:BAAANQABCggINAAAAA==.Skylette:BAAANQADCggIDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakeosham:BAAANQAECgYICQAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUIDgABNQAECgoKLgAVAAoNAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.Sortiebatoru:BAAANQAECgEIAQAAAA==.Soulblight:BAAANQADCggIFwAAAA==.Souldune:BAAANQAECgYICAAAAA==.',
Sp='Sparkplugg:BAAANQADCgQICAAAAA==.Sparthos:BAABNQAECn8XAAMbAAYKugVNJgAEAQAbAAYKugVNJgAEAQAlAAEKAABOJwAmAAAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQABCgIIAgAAAA==.',
Sr='Srfreaky:BAAANQAECgEIAQAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECn8sAAIBAAoKPwcwTgB9AQABAAoKPwcwTgB9AQAAAA==.Stocklock:BAAANQAECgUICQAAAA==.Stormblessed:BAAANQADCgQIBAAAAA==.Stowned:BAAANQAECgQIBQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAARAAAAAA==.',
Su='Sune:BAAANQADCgUICQABNQAECgcIHgAFAGocAA==.Suzuya:BAAANQABCggICgAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tanlon:BAAANQAECgEIAgAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgoKLgAVAAoNAA==.Tatari:BAAANQADCgYJCgABNQAECggIDQARAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Tel:BAAANQAECgEIAQAAAA==.Telandril:BAABNQAECn8vAAImAAoKgBGAJgDuAQAmAAoKgBGAJgDuAQAAAA==.Tellanna:BAABNQAECn8gAAIEAAgKiAJU4wC8AAAEAAgKiAJU4wC8AAAAAA==.Tensuken:BAABNQAECn8VAAIJAAcK3RXhxgCOAQAJAAcK3RXhxgCOAQAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgUIEgAAAA==.',
Th='Thadium:BAAANQADCgcIBwAAAA==.Thaet:BAAANQABCgUIBwAAAA==.That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgUIBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgYIDAAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECn9FAAMTAAoK/B94HgC3AgATAAoK/B94HgC3AgAIAAMKtA24RABpAAAAAA==.Tinydots:BAAANQAECgYIEgAAAA==.Tinypaws:BAAANQADCgUIBwAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQAECgEIAQAAAA==.Torhal:BAAANQADCgIIAgAAAA==.Totemilk:BAAANQADCgYIBgAAAA==.',
Tr='Traw:BAAANQADCgUIBAAAAA==.Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAQIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECgkJKwAbAIYiAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAABNQAECn8cAAMDAAkK7iAhOwA2AgADAAcKoSEhOwA2AgABAAQK6h2oYgAZAQAAAA==.Unfriendly:BAAANQAECgEIAQAAAA==.',
Va='Vaelora:BAABNQAECn8YAAMCAAkKHhLiJwCVAQACAAkKHhLiJwCVAQABAAEKtAhloQAwAAAAAA==.Vaelyria:BAAANQAECgEIAQAAAA==.Valakk:BAABNQAECn8bAAMdAAcK1wbEHwC/AAAOAAYKUAUQtgDWAAAdAAQKvQnEHwC/AAAAAA==.Valsitril:BAABNQAECn8YAAISAAYKERO2FwA9AQASAAYKERO2FwA9AQABNQAECggIJwAZAL4PAA==.Vanara:BAAANQABCggIDQAAAA==.Varelyna:BAAANQADCgYIBgABNQAECggIJwAZAL4PAA==.',
Ve='Velsetin:BAAANQAECgEIAQABNQAFFAMIAwARAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Veryspooky:BAAANQAECgQIBgABNQAECgUIDAARAAAAAA==.Vexian:BAAANQADCgcIGQABNQAECgkJOgAIAOMbAA==.',
Vi='Vicas:BAAANQAECgYICgAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQAECgIIAQAAAA==.',
We='Webgar:BAAANQAECgUIBQAAAA==.Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAABNQAECn8aAAILAAYKGwQ73AC3AAALAAYKGwQ73AC3AAAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgIIBQAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECggIDQARAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.Xanndor:BAAANQAECgEIAgAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQAECgMIAwABNQAECgQICQARAAAAAA==.',
Ya='Yaerin:BAABNQAECn8iAAMTAAoKjR4+EgA3AwATAAoKjR4+EgA3AwAkAAMK0Q79GgCQAAAAAA==.Yahman:BAAANQAECgQIBAABNQAECgoKKAAEACIkAA==.Yaoi:BAABNQAECn83AAMKAAoKyQ2bZwDpAQAKAAoKyQ2bZwDpAQAWAAgK0wjAlABUAQAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECggICQAAAA==.',
Yu='Yungblood:BAAANQAECgYIBwAAAA==.Yungfungi:BAAANQAECgMIAwAAAA==.Yuukon:BAABNQAECn8vAAIBAAoKiQ91PgDSAQABAAoKiQ91PgDSAQAAAA==.',
Za='Zackman:BAAANQADCggIHAAAAA==.Zad:BAAANQAECgUIBAABNQAFFAUIDAABAKcWAA==.Zaddydruid:BAAANQAECgYIBgABNQAFFAUIDAABAKcWAA==.Zadira:BAACNQAFFH8MAAIBAAUKpxZFBwCHAQABAAUKpxZFBwCHAQA1AAQKfz8AAwEACgpcIWIKAEcDAAEACgpcIWIKAEcDAAIABgodF1tWAL4AAAAA.Zadirasham:BAABNQAECn8eAAIKAAkKwB6mLADzAQAKAAkKwB6mLADzAQABNQAFFAUIDAABAKcWAA==.Zadorca:BAAANQAECgYICAABNQAFFAUIDAABAKcWAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.Zephrylia:BAAANQAECgEIAQAAAA==.',
Zu='Zuriel:BAABNQAECn8VAAIWAAUKbhoBYQBiAQAWAAUKbhoBYQBiAQAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgYIDgAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgoKLwANAOIjAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ða']='Ðark:BAAANQAECgEIAQAAAA==.',
['Ös']='Östara:BAAANQAECggIDQAAAA==.',
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
