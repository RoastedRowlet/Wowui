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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Mage-Arcane','Mage-Fire','Druid-Guardian','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Monk-Brewmaster','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-07-12',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORIxHADNAAABAAYJAxMxHADNAAACAAQJ6g5A1gCfAAADAAIJkQf9ZAA0AAABLgAFFAUJBwAEACURAA==.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw75pQDYAAAFAAYJLw75pQDYAAAAAA==.',
Al='Alystra:BAABLgAECn8aAAIGAAgJ1wbiQQAIAQAGAAgJ1wbiQQAIAQAAAA==.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAACLgAFFH8MAAICAAMJCBsYVQD9AAACAAMJCBsYVQD9AAAuAAQKfykAAgIACQmUIL4SALwCAAIACQmUIL4SALwCAAAA.',
Ar='Archdemon:BAABLgAECn88AAIHAAkJZhxcCQBfAgAHAAkJZhxcCQBfAgAAAA==.Argonos:BAAALgAECgcJDgAAAA==.Arielias:BAABLgAECn8dAAMIAAkJGhpjCAAIAgAIAAcJGxtjCAAIAgAJAAYJuRelHAB0AQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8RAAIKAAYJHg5oQgBmAQAKAAYJHg5oQgBmAQAuAAQKfysAAgoACQm2Fgw4AJQCAAoACQm2Fgw4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Balaba:BAAALgAECgEJAQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/AjNWgCoAAALAAYJ/AjNWgCoAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgAMAAkJbRqWPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBOMMADfAQANAAkJUBOMMADfAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8lAAIKAAYJhgUt6wDLAAAKAAYJhgUt6wDLAAAAAA==.',
Ch='Charliemen:BAABLgAECn8WAAIOAAgJ0wcfCADmAAAOAAgJ0wcfCADmAAAAAA==.Chilli:BAAALgAECgUJBQAAAA==.Chubtart:BAACLgAFFH8VAAIOAAYJ9hYMCwAoAQAOAAYJ9hYMCwAoAQAuAAQKfzQAAg4ACQnRIz0IABIDAA4ACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Ci='Ciborg:BAAALgAECgUJBwAAAA==.',
Cl='Clank:BAAALgAFFAMJBAAAAA==.Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAFFAIJBAAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAACLgAFFH8PAAMPAAMJzRDuJgCSAAAPAAMJzRDuJgCSAAAQAAIJWAhGSQBrAAAuAAQKfzUAAxAACQlkFTMhANoBABAACQlkFTMhANoBAA8ABgkrDfJ1APwAAAAA.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgAECgUJCQAAAA==.Deathslam:BAACLgAFFH8NAAIMAAQJ/AhVgQAFAQAMAAQJ/AhVgQAFAQAuAAQKfyQAAgwACQltGQgvAEMCAAwACQltGQgvAEMCAAAA.',
Do='Dordis:BAAALgAECgMJBgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhBWQQDeAQACAAkJUhBWQQDeAQABAAUJRAoAVgDxAAADAAEJvwolZAA1AAABLgAFFAkJIwARAKceAA==.Dutchess:BAABLgAECn8nAAISAAkJwx5kHQCVAgASAAkJwx5kHQCVAgAAAA==.',
Dy='Dylan:BAACLgAFFH8dAAIKAAYJbCBcJADpAQAKAAYJbCBcJADpAQAuAAQKfy8AAgoACQlpJQIGAFMDAAoACQlpJQIGAFMDAAAA.Dylanj:BAAALgAECgQJBAABLgAFFAYJHQAKAGwgAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgAECgIJAgAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elendale:BAAALgAECgUJBQAAAA==.Elowen:BAAALgAFFAIJBQAAAQ==.',
Er='Eresiine:BAAALgAECggJEAAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.Estara:BAAALgAECgEJAQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8WAAMTAAYJTxRMGACrAQATAAYJTxNMGACrAQAUAAIJVBNZDQCTAAAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFZdBAAQBAAYAAQlcEniBADoAAAAA.Flounder:BAAALgAECgIJBAAAAA==.',
Fo='Foamtotem:BAAALgAECgUJCgAAAA==.Forumshaman:BAAALgADCgcJBwAAAA==.Forumsoldier:BAACLgAFFH8KAAIKAAUJ8wj6bwACAQAKAAUJ8wj6bwACAQAuAAQKfygAAgoACQnUFdpFAAkCAAoACQnUFdpFAAkCAAAA.',
Fr='Frozenscorch:BAABLgAECn8XAAQKAAkJghA+YgC6AQAKAAkJbw8+YgC6AQAVAAIJywwWBQBVAAAWAAIJWgbmBAAxAAAAAA==.',
Ft='Fteve:BAAALgAECgUJEgAAAA==.',
Fu='Fungasaur:BAABLgAFFH8GAAIXAAMJnxhuFQDWAAAXAAMJnxhuFQDWAAAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMYAAgJrQZGFQC9AAAZAAgJrQYQTwDyAAAYAAYJJAZGFQC9AAAAAA==.',
['Fö']='Föx:BAABLgAFFH8LAAIaAAQJeBGsCgAGAQAaAAQJeBGsCgAGAQAAAA==.',
Ge='Gearspring:BAAALgAECgIJBAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAABLgAFFH8JAAIbAAMJ5AunEQCiAAAbAAMJ5AunEQCiAAABLgAFFAgJGQAOAGIUAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn80AAIRAAcJegVdDgCpAAARAAcJegVdDgCpAAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJDwAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8fAAIcAAcJGSLYEACPAgAcAAcJGSLYEACPAgAAAA==.',
He='Helpingyou:BAABLgAECn8lAAIGAAkJPw1xJgCZAQAGAAkJPw1xJgCZAQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8kAAIcAAgJvxITLACxAQAcAAgJvxITLACxAQAAAA==.',
Ia='Iamthewalrus:BAAALgAECgEJAgABLgAECggJEwAdAAAAAA==.',
Il='Ilitha:BAAALgAECgIJAwAAAA==.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJCAAdAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAABLgAECn8iAAICAAcJRhsKBgDgAQACAAcJRhsKBgDgAQAAAA==.Izzia:BAABLgAECn8nAAINAAkJAhmjFQCcAgANAAkJAhmjFQCcAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA/OIADHAQATAAkJpA/OIADHAQAGAAUJyAhmRADZAAAAAA==.Kaye:BAAALgAECgYJBgAAAA==.Kayewyn:BAABLgAECn8xAAINAAkJvxWIIQA7AgANAAkJvxWIIQA7AgAAAA==.',
Kb='Kbdh:BAAALgAECgYJDgABLgAFFAIJAwAdAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAdAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAdAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAdAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAdAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.Kelôx:BAAALgAECgQJCQAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Ko='Koharu:BAAALgAECgEJAQAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJHAANAO8dAA==.Kynn:BAACLgAFFH8cAAINAAUJ7x26FgCsAQANAAUJ7x26FgCsAQAuAAQKfzgAAw0ACQmUIvMBAIEDAA0ACQmUIvMBAIEDAA4AAQl3EcyHADsAAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8yAAISAAkJgxKacgCJAQASAAkJgxKacgCJAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAQAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAYJFgATAE8UAA==.Meepijuana:BAAALgAECgQJBwABLgAFFAQJCgAEAMkaAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMeAAkJlyCrCQBTAgARAAcJ+B/yGACDAgAeAAkJXh2rCQBTAgAAAA==.',
Mi='Mightymost:BAACLgAFFH8FAAIfAAIJNQOzQwBhAAAfAAIJNQOzQwBhAAAuAAQKfzIAAx8ACAk/EbYGAGcBAB8ACAmED7YGAGcBACAACAmYC5UTABUBAAAA.Minute:BAAALgADCgIJAgAAAA==.',
Mu='Mudd:BAABLgAECn8nAAMeAAkJUB5cBgCZAgAeAAkJUB5cBgCZAgARAAEJcBBTogAyAAABLgAECgkJHQALAB4gAA==.Muddrogue:BAAALgAECgEJAgABLgAECgkJHQALAB4gAA==.Mudds:BAABLgAECn8dAAILAAkJHiB7EAB5AgALAAkJHiB7EAB5AgAAAA==.',
Na='Naelia:BAACLgAFFH8GAAIfAAIJhwuGpQCFAAAfAAIJhwuGpQCFAAAuAAQKfx4AAh8ABwniFlNUAJ8BAB8ABwniFlNUAJ8BAAEuAAUUBgksAAwAuxgA.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiVbJQBNAgACAAYJBCZbJQBNAgABAAYJtCFaDgB5AQAAAA==.',
No='Noodles:BAABLgAECn8iAAIFAAgJfRY0XgBuAQAFAAgJfRY0XgBuAQAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Ny='Nya:BAAALgAECgEJAgAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgXQgwCxAAANAAYJbgXQgwCxAAAAAA==.',
Ok='Okomo:BAAALgAECgUJCAAAAA==.',
Or='Orgulav:BAAALgAECgUJEAAAAA==.',
Pa='Palaben:BAABLgAECn8hAAMcAAkJDRGgQQA7AQAcAAcJrBKgQQA7AQASAAYJ0grO3gDfAAAAAA==.Pandaroo:BAAALgAECgYJBwAAAA==.Pantsu:BAABLgAECn9DAAQMAAkJuSWeCAAtAwAMAAkJiCWeCAAtAwAJAAgJ2CB0CQB7AgAIAAgJ/x9SBwAkAgAAAA==.Pateaviejas:BAAALgAECgMJBgAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIhAAYJTgVygQCdAAAhAAYJTgVygQCdAAAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQAUAAYJHBFpRAAnAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8ZAAILAAYJuxvaDwA+AQALAAYJuxvaDwA+AQAuAAQKfykAAgsACQneH+4IALcCAAsACQneH+4IALcCAAAA.',
Pu='Punchbear:BAAALgAECgcJDgAAAA==.Punchize:BAABLgAECn8zAAQbAAkJSyMAAwAlAwAbAAkJSyMAAwAlAwAhAAIJ9ApxqwBIAAALAAEJJwOjwQAVAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQABLgAFFAQJDgAaACQfAA==.',
Re='Remote:BAAALgAECgQJDQAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Riddlez:BAABLgAECn8YAAIhAAYJBhhyNQCfAQAhAAYJBhhyNQCfAQAAAA==.Rilea:BAABLgAECn8VAAICAAgJlRCkgAA9AQACAAgJlRCkgAA9AQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn9AAAIiAAkJ6iITAgAHAwAiAAkJ6iITAgAHAwAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubbucket:BAAALgAECgMJAwAAAA==.Scrubuckett:BAAALgAECgEJAQAAAA==.',
Se='Sebrine:BAAALgAECgUJDAAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAAEAAUJJRHoEQC6AAAjAAEJrwmGEwA7AAAuAAQKfx8ABCMABwmTGyoHAPQBACMABgnVHioHAPQBAAQABQnGF0w9ADIBACQAAQn7F/ghAEMAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJDgAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJBAAAAA==.Shzam:BAAALgAECgQJBAAAAA==.',
Si='Sidearmz:BAAALgAECgEJAQAAAA==.Sixtontbone:BAAALgAECgMJBAABLgAECgYJFwAUABwRAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Slang:BAAALgAECgEJAQAAAA==.Sleipner:BAABLgAECn8fAAIlAAkJAA7tGgBBAQAlAAkJAA7tGgBBAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQfAAkJnxc1RgDIAQAfAAgJfRY1RgDIAQAgAAMJ6woSQwCpAAAmAAIJLRFhOgA/AAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8jAAMRAAkJpx7WAQCRAgARAAkJpx7WAQCRAgAeAAEJoAa6CwBTAAAuAAQKfzYAAxEACAl9JaYGAPQCABEACAl9JaYGAPQCAB4ABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.Spookyboy:BAAALgAECgkJEAAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBwAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8sAAIMAAYJuxhBNQCVAQAMAAYJuxhBNQCVAQAuAAQKf0QAAgwACQlkIwINAAUDAAwACQlkIwINAAUDAAAA.Tahine:BAABLgAECn8VAAIaAAcJFhJOGQBEAQAaAAcJFhJOGQBEAQAAAA==.Taisho:BAAALgAECgYJDAAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJDgAUAL4QAA==.Timetwoflame:BAABLgAECn8mAAMnAAgJkBWADgDmAQAnAAgJkBWADgDmAQAYAAQJugemGgB5AAAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8pAAQTAAkJfAobDAC6AAAUAAkJ8wksMQBIAQATAAUJGAYbDAC6AAAGAAIJPgOJmAAgAAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8qAAMgAAkJIAeHFQD+AAAgAAkJ/AaHFQD+AAAfAAUJiQKe8ACAAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgAECgQJBAAAAA==.',
Wi='Wildwood:BAAALgAECgIJAgAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJBAAdAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAYJEQAKAB4OAA==.',
Xa='Xampu:BAAALgAECgQJBAAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8/AAMLAAkJ4x8ECQC1AgALAAkJ4x8ECQC1AgAhAAQJCAegjwB6AAAAAA==.',
Za='Zaelyse:BAABLgAFFH8JAAISAAMJsRnQMQCrAAASAAMJsRnQMQCrAAAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxEzfgB7AQAKAAgJLxEzfgB7AQAAAA==.',
['Ða']='Ðark:BAAALgAFFAMJBAAAAA==.',
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
