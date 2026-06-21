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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Mage-Arcane','Mage-Fire','Druid-Guardian','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORIxHADNAAABAAYJAxMxHADNAAACAAQJ6g461gCfAAADAAIJkQf8ZAA0AAABLgAFFAUJBwAEACURAA==.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw76pQDYAAAFAAYJLw76pQDYAAAAAA==.',
Al='Alystra:BAABLgAECn8aAAIGAAgJ1wbbQQAIAQAGAAgJ1wbbQQAIAQAAAA==.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAACLgAFFH8LAAICAAMJCBsYVQD9AAACAAMJCBsYVQD9AAAuAAQKfykAAgIACQmVIMESALwCAAIACQmVIMESALwCAAAA.',
Ar='Archdemon:BAABLgAECn8yAAIHAAkJMxxeCQBfAgAHAAkJMxxeCQBfAgAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAABLgAECn8bAAMIAAkJ+RljCAAIAgAIAAcJ9RpjCAAIAgAJAAYJuRekHAB0AQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8QAAIKAAYJHg6IQgBmAQAKAAYJHg6IQgBmAQAuAAQKfysAAgoACQm2Fgw4AJQCAAoACQm2Fgw4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Balaba:BAAALgAECgEJAQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/AjOWgCoAAALAAYJ/AjOWgCoAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgAMAAkJbRqWPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBOOMADfAQANAAkJUBOOMADfAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8lAAIKAAYJhgUp6wDLAAAKAAYJhgUp6wDLAAAAAA==.',
Ch='Charliemen:BAAALgAECgQJCAAAAA==.Chilli:BAAALgAECgUJBQAAAA==.Chubtart:BAACLgAFFH8PAAIOAAUJ9BoFGwBBAQAOAAUJ9BoFGwBBAQAuAAQKfzQAAg4ACQnRIz0IABIDAA4ACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Ci='Ciborg:BAAALgAECgMJBQAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAFFAIJAQAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAACLgAFFH8NAAMPAAMJzRCwBgCfAAAPAAMJzRCwBgCfAAAQAAIJWAhISQBrAAAuAAQKfzUAAxAACQlkFTUhANoBABAACQlkFTUhANoBAA8ABgkrDep1APwAAAAA.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgAECgEJAQAAAA==.Deathslam:BAACLgAFFH8NAAIMAAQJ/AhdgQAFAQAMAAQJ/AhdgQAFAQAuAAQKfyQAAgwACQltGQcvAEMCAAwACQltGQcvAEMCAAAA.',
Do='Dordis:BAAALgAECgEJAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhBZQQDeAQACAAkJUhBZQQDeAQABAAUJRAoAVgDxAAADAAEJvwolZAA1AAABLgAFFAgJHgARADEeAA==.Dutchess:BAABLgAECn8nAAISAAkJwx5jHQCVAgASAAkJwx5jHQCVAgAAAA==.',
Dy='Dylan:BAACLgAFFH8dAAIKAAYJbCB2JADpAQAKAAYJbCB2JADpAQAuAAQKfy8AAgoACQlpJQIGAFMDAAoACQlpJQIGAFMDAAAA.Dylanj:BAAALgAECgQJBAABLgAFFAYJHQAKAGwgAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgAECgEJAQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
Er='Eresiine:BAAALgAECggJEAAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.Estara:BAAALgAECgEJAQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8VAAMTAAYJBxRcGACrAQATAAYJBhNcGACrAQAUAAIJVBNZDQCTAAAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFZhBAAQBAAYAAQlcEnCBADoAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgAECgUJCgAAAA==.Forumshaman:BAAALgADCgcJBwAAAA==.Forumsoldier:BAACLgAFFH8JAAIKAAUJHQgYcAACAQAKAAUJHQgYcAACAQAuAAQKfygAAgoACQnUFdxFAAkCAAoACQnUFdxFAAkCAAAA.',
Fr='Frozenscorch:BAABLgAECn8XAAQKAAkJghA+YgC6AQAKAAkJbw8+YgC6AQAVAAIJywzjAABjAAAWAAIJWgZCAQAxAAAAAA==.',
Ft='Fteve:BAAALgAECgUJEgAAAA==.',
Fu='Fungasaur:BAABLgAFFH8GAAIXAAMJnxhtFQDWAAAXAAMJnxhtFQDWAAAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMYAAgJrQZHFQC9AAAZAAgJrQYQTwDyAAAYAAYJJAZHFQC9AAAAAA==.',
['Fö']='Föx:BAABLgAFFH8FAAIaAAQJCQ+sCgAGAQAaAAQJCQ+sCgAGAQAAAA==.',
Ge='Gearspring:BAAALgADCgUJCwAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAIJBAAAAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8lAAIRAAcJaANEbgCsAAARAAcJaANEbgCsAAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJDwAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8fAAIbAAcJGSLZEACPAgAbAAcJGSLZEACPAgAAAA==.Hathus:BAAALgAECgMJBAAAAA==.',
He='Helpingyou:BAABLgAECn8lAAIGAAkJPw1wJgCZAQAGAAkJPw1wJgCZAQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8hAAIbAAgJHxIRLACxAQAbAAgJHxIRLACxAQAAAA==.',
Ia='Iamthewalrus:BAAALgAECgEJAQABLgAECggJEQAcAAAAAA==.',
Il='Ilitha:BAAALgAECgIJAwAAAA==.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAcAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAABLgAECn8VAAICAAYJ+xSIUQB0AQACAAYJ+xSIUQB0AQAAAA==.Izzia:BAABLgAECn8nAAINAAkJAhmjFQCcAgANAAkJAhmjFQCcAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA/LIADHAQATAAkJpA/LIADHAQAGAAUJyAhmRADZAAAAAA==.Kaye:BAAALgAECgYJBgAAAA==.Kayewyn:BAABLgAECn8vAAINAAkJChWKIQA7AgANAAkJChWKIQA7AgAAAA==.',
Kb='Kbdh:BAAALgAECgYJDgABLgAFFAIJAwAcAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAcAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAcAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAcAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAcAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.Kelôx:BAAALgAECgQJCQAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Ko='Koharu:BAAALgAECgEJAQAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJHAANAO8dAA==.Kynn:BAACLgAFFH8cAAINAAUJ7x2/FgCsAQANAAUJ7x2/FgCsAQAuAAQKfzgAAw0ACQmUIvMBAIEDAA0ACQmUIvMBAIEDAA4AAQl3EcmHADsAAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8wAAISAAgJkRKccgCJAQASAAgJkRKccgCJAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAQAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAYJFQATAAcUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMdAAkJlyCsCQBTAgARAAcJ+B/yGACDAgAdAAkJXh2sCQBTAgAAAA==.',
Mi='Mightymost:BAABLgAECn8kAAIeAAgJmAuVEwAVAQAeAAgJmAuVEwAVAQAAAA==.',
Mu='Mudd:BAABLgAECn8nAAMdAAkJUB5cBgCZAgAdAAkJUB5cBgCZAgARAAEJcBBQogAyAAAAAA==.Muddrogue:BAAALgAECgEJAQABLgAECgkJJwAdAFAeAA==.Mudds:BAABLgAECn8dAAILAAkJHiB7EAB5AgALAAkJHiB7EAB5AgABLgAECgkJJwAdAFAeAA==.',
Na='Naelia:BAACLgAFFH8FAAIfAAIJ/AqbpQCFAAAfAAIJ/AqbpQCFAAAuAAQKfx4AAh8ABwniFlJUAJ8BAB8ABwniFlJUAJ8BAAEuAAUUBgkpAAwAuxgA.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiVdJQBNAgACAAYJBCZdJQBNAgABAAYJtCFaDgB5AQAAAA==.',
No='Noodles:BAABLgAECn8hAAIFAAgJfRY3XgBuAQAFAAgJfRY3XgBuAQAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Ny='Nya:BAAALgAECgEJAgAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgXPgwCxAAANAAYJbgXPgwCxAAAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Or='Orgulav:BAAALgADCgYJCAAAAA==.',
Pa='Palaben:BAABLgAECn8hAAMbAAkJDRGfQQA7AQAbAAcJrBKfQQA7AQASAAYJ0grL3gDfAAAAAA==.Pantsu:BAABLgAECn9DAAQMAAkJuSWeCAAtAwAMAAkJiCWeCAAtAwAJAAgJ2CB1CQB7AgAIAAgJ/x9SBwAkAgAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIgAAYJTgVugQCdAAAgAAYJTgVugQCdAAAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQAUAAYJHBFpRAAnAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8XAAILAAUJLRvbDwA+AQALAAUJLRvbDwA+AQAuAAQKfykAAgsACQneH+8IALcCAAsACQneH+8IALcCAAAA.',
Pu='Punchbear:BAAALgAECgUJBQAAAA==.Punchize:BAABLgAECn8zAAQhAAkJSyMAAwAmAwAhAAkJSyMAAwAmAwAgAAIJ9ApoqwBIAAALAAEJJwOiwQAVAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQABLgAFFAQJDAAaAOccAA==.',
Re='Remote:BAAALgAECgQJCAAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Riddlez:BAABLgAECn8UAAIgAAYJBhhvNQCfAQAgAAYJBhhvNQCfAQAAAA==.Rilea:BAABLgAECn8UAAICAAcJAw+mgAA9AQACAAcJAw+mgAA9AQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn82AAIiAAkJjyIUAgAHAwAiAAkJjyIUAgAHAwAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgAECgEJAQAAAA==.',
Se='Sebrine:BAAALgAECgUJDAAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAAEAAUJJRHoEQC6AAAjAAEJrwmFEwA7AAAuAAQKfx8ABCMABwmTGyoHAPQBACMABgnVHioHAPQBAAQABQnGF0w9ADIBACQAAQn7F/khAEMAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJDAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJBAAAAA==.Shzam:BAAALgAECgEJAQAAAA==.',
Si='Sixtontbone:BAAALgAECgIJAwABLgAECgYJFwAUABwRAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Slang:BAAALgAECgEJAQAAAA==.Sleipner:BAABLgAECn8fAAIlAAkJAA7tGgBBAQAlAAkJAA7tGgBBAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQfAAkJnxczRgDIAQAfAAgJfRYzRgDIAQAeAAMJ6woSQwCpAAAmAAIJLRFhOgA/AAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8eAAMRAAgJMR7ZAQCRAgARAAgJMR7ZAQCRAgAdAAEJoAa6CwBTAAAuAAQKfzYAAxEACAl9JaYGAPQCABEACAl9JaYGAPQCAB0ABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.Spookyboy:BAAALgAECgcJBwAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBwAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8pAAIMAAYJuxhPNQCVAQAMAAYJuxhPNQCVAQAuAAQKf0QAAgwACQlkIwENAAUDAAwACQlkIwENAAUDAAAA.Tahine:BAABLgAECn8VAAIaAAcJFhJNGQBEAQAaAAcJFhJNGQBEAQAAAA==.Taisho:BAAALgAECgUJCwAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJDgAUAL4QAA==.Timetwoflame:BAABLgAECn8kAAMnAAgJLxOBDgDmAQAnAAgJLxOBDgDmAQAYAAQJugemGgB5AAAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8gAAMUAAkJ8wkoMQBIAQAUAAkJ8wkoMQBIAQAGAAIJPgOCmAAgAAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8qAAMeAAkJIAeFFQD+AAAeAAkJ/AaFFQD+AAAfAAUJiQKd8ACAAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgAECgEJAQAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJBAAcAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAYJEAAKAB4OAA==.',
Xa='Xampu:BAAALgAECgQJBAAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn86AAMLAAkJex8ECQC1AgALAAkJex8ECQC1AgAgAAQJCAeajwB6AAAAAA==.',
Za='Zaelyse:BAABLgAFFH8IAAISAAMJghk8CAC1AAASAAMJghk8CAC1AAAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxE1fgB7AQAKAAgJLxE1fgB7AQAAAA==.',
['Ða']='Ðark:BAAALgAECgEJAQABLgAECgcJGgASAEEaAA==.',
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
