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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Demonology','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-05-30',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORIRGQDUAAABAAYJAxMRGQDUAAACAAQJ6g6avgCkAAADAAIJkQdMXQA0AAABLgAFFAUJBwAEACURAA==.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw6+fgAtAQAFAAYJLw6+fgAtAQAAAA==.',
Al='Alystra:BAABLgAECn8aAAIGAAgJ1wZOPAD9AAAGAAgJ1wZOPAD9AAAAAA==.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAABLgAECn8lAAICAAgJHyLcFwCAAgACAAgJHyLcFwCAAgAAAA==.',
Ar='Archdemon:BAABLgAECn8oAAIHAAkJtBitDAAKAgAHAAkJtBitDAAKAgAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAABLgAECn8WAAMIAAkJAhkDBwADAgAIAAcJ9RoDBwADAgAJAAYJyxN+IgAkAQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8OAAIKAAUJcgvsXAAYAQAKAAUJcgvsXAAYAQAuAAQKfysAAgoACQm2Fgw4AJQCAAoACQm2Fgw4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/AiUTwCxAAALAAYJ/AiUTwCxAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgAMAAkJbRqWPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBOkLADjAQANAAkJUBOkLADjAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8fAAIKAAYJcgOS7wChAAAKAAYJcgOS7wChAAAAAA==.',
Ch='Charliemen:BAAALgAECgQJCAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8MAAIOAAQJ9BpuEwBSAQAOAAQJ9BpuEwBSAQAuAAQKfzQAAg4ACQnRIz0IABIDAA4ACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Ci='Ciborg:BAAALgADCgUJBQAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJCwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAACLgAFFH8FAAMPAAMJhA3aQQDCAAAPAAMJhA3aQQDCAAAQAAEJ1QjpSAA8AAAuAAQKfzUAAxAACQlkFfQcAOEBABAACQlkFfQcAOEBAA8ABgkrDcRpAP4AAAAA.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8NAAIMAAQJ/AhWaAAPAQAMAAQJ/AhWaAAPAQAuAAQKfyQAAgwACQltGdsoAEoCAAwACQltGdsoAEoCAAAA.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhCgNwDoAQACAAkJUhCgNwDoAQABAAUJRAoAVgDxAAADAAEJvwqaWQA6AAABLgAFFAgJHAARAIwdAA==.Dutchess:BAABLgAECn8iAAISAAkJUhuZKwA6AgASAAkJUhuZKwA6AgAAAA==.',
Dy='Dylan:BAACLgAFFH8ZAAIKAAUJayOcKgCQAQAKAAUJayOcKgCQAQAuAAQKfy8AAgoACQlpJYcEAFQDAAoACQlpJYcEAFQDAAAA.Dylanj:BAAALgAECgQJBAABLgAFFAUJGQAKAGsjAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgADCgQJBAAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECggJDwAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8SAAMTAAUJ6hTVFwBuAQATAAUJthPVFwBuAQAUAAIJVBNZDQCTAAAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFRc5AAYBAAYAAQlcEn9xADoAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgAECgUJBQAAAA==.Forumshaman:BAAALgADCgcJBwAAAA==.Forumsoldier:BAACLgAFFH8GAAIKAAQJagfVXwAQAQAKAAQJagfVXwAQAQAuAAQKfyQAAgoACQnEFVlMAN8BAAoACQnEFVlMAN8BAAAA.',
Fr='Frozenscorch:BAAALgAECgkJEwAAAA==.',
Ft='Fteve:BAAALgAECgUJCgAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMVAAgJrQYvEwDFAAAWAAgJrQZNSQDiAAAVAAYJJAYvEwDFAAAAAA==.',
['Fö']='Föx:BAAALgAFFAQJBAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAgABLgAFFAIJBwAMAEwSAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8ZAAIRAAcJQQIYbgCLAAARAAcJQQIYbgCLAAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJDAAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8cAAIXAAYJTCMcFgBDAgAXAAYJTCMcFgBDAgAAAA==.Hathus:BAAALgAECgIJAgAAAA==.',
He='Helpingyou:BAABLgAECn8gAAIGAAkJSwyAIwCNAQAGAAkJSwyAIwCNAQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8gAAIXAAgJHxLIJwC2AQAXAAgJHxLIJwC2AQAAAA==.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAYAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEgAAAA==.Izzia:BAABLgAECn8hAAINAAgJQxmLHABOAgANAAgJQxmLHABOAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA8QHADMAQATAAkJpA8QHADMAQAGAAUJyAhmRADZAAAAAA==.Kaye:BAAALgAECgEJAQAAAA==.Kayewyn:BAABLgAECn8qAAINAAgJGhZRJwACAgANAAgJGhZRJwACAgAAAA==.',
Kb='Kbdh:BAAALgAECgYJDQABLgAFFAIJAwAYAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAYAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAYAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAYAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAYAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.Kelôx:BAAALgAECgQJBAAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJHAANAO8dAA==.Kynn:BAACLgAFFH8cAAINAAUJ7x3IEADBAQANAAUJ7x3IEADBAQAuAAQKfzgAAw0ACQmUIvMBAIEDAA0ACQmUIvMBAIEDAA4AAQl3EcZ5ADwAAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8uAAISAAgJkRK4YwCPAQASAAgJkRK4YwCPAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAQAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAUJEgATAOoUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMZAAkJlyAyCABYAgARAAcJ+B/yGACDAgAZAAkJXh0yCABYAgAAAA==.',
Mi='Mightymost:BAAALgAECgYJDwAAAA==.',
Mu='Mudd:BAABLgAECn8kAAMZAAgJkh90CQA8AgAZAAgJkh90CQA8AgARAAEJcBBdkAA2AAABLgAECgkJHQALAB8gAA==.Mudds:BAABLgAECn8dAAILAAkJHyB7EAB5AgALAAkJHyB7EAB5AgAAAA==.',
Na='Naelia:BAABLgAECn8dAAIaAAcJRBY7TwCiAQAaAAcJRBY7TwCiAQABLgAFFAUJGgAMAEEVAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiW2HgBYAgACAAYJBCa2HgBYAgABAAYJtCHUDAB+AQAAAA==.',
No='Noodles:BAABLgAECn8dAAIFAAcJvhaUbwAoAQAFAAcJvhaUbwAoAQAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgVDewC0AAANAAYJbgVDewC0AAAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMXAAgJdRGHPAA+AQAXAAcJrBKHPAA+AQASAAQJXQzlCQGKAAAAAA==.Pantsu:BAABLgAECn9DAAQMAAkJuSV1BgA2AwAMAAkJiCV1BgA2AwAJAAgJ2CDiBwCHAgAIAAgJ/x/0BQAjAgAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIbAAYJTgXpagCdAAAbAAYJTgXpagCdAAAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQAUAAYJHBFpRAAnAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8RAAILAAUJixj2DgAxAQALAAUJixj2DgAxAQAuAAQKfykAAgsACQneH34HAL4CAAsACQneH34HAL4CAAAA.',
Pu='Punchbear:BAAALgADCgYJBgAAAA==.Punchize:BAABLgAECn8tAAMcAAgJMCOSBgDAAgAcAAgJMCOSBgDAAgAbAAIJ9AobjgBGAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQABLgAFFAQJBgAdAGsXAA==.',
Re='Remote:BAAALgAECgQJBwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8sAAIeAAkJGyAoAwDDAgAeAAkJGyAoAwDDAgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgADCgYJBgAAAA==.',
Se='Sebrine:BAAALgAECgUJDAAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAAEAAUJJRHoEQC6AAAfAAEJrwmhEABBAAAuAAQKfx8ABB8ABwmTGyoHAPQBAB8ABgnVHioHAPQBAAQABQnGF0w9ADIBACAAAQn7F5odAEMAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJCAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJAwAAAA==.Shzam:BAAALgAECgEJAQAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIhAAkJAA7CFwBGAQAhAAkJAA7CFwBGAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQaAAkJnxdcPwDSAQAaAAgJfRZcPwDSAQAiAAMJ6woSQwCpAAAjAAIJLREmMABFAAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8cAAMRAAgJjB2+AACTAgARAAgJjB2+AACTAgAZAAEJoAa6CwBTAAAuAAQKfzIAAxEACAl9JU8FAPsCABEACAl9JU8FAPsCABkABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8aAAIMAAUJQRWdUQAxAQAMAAUJQRWdUQAxAQAuAAQKf0QAAgwACQlkIx4KAA4DAAwACQlkIx4KAA4DAAAA.Tahine:BAABLgAECn8UAAIdAAcJABHrFgA3AQAdAAcJABHrFgA3AQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJDgAUAL4QAA==.Timetwoflame:BAABLgAECn8fAAMkAAgJ5RH2DgDKAQAkAAgJ5RH2DgDKAQAVAAQJugc2GAB+AAAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8cAAMUAAgJ6AooMAA3AQAUAAgJ6AooMAA3AQAGAAIJPgMxhQAiAAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8lAAMiAAkJHAeWEgAGAQAiAAkJ/AaWEgAGAQAaAAMJKgKBEAFDAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJAwAYAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAUJDgAKAHILAA==.',
Xa='Xampu:BAAALgADCgYJBwAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8wAAMLAAkJGR1MCQCbAgALAAkJGR1MCQCbAgAbAAQJCAccdgB8AAAAAA==.',
Za='Zaelyse:BAAALgAFFAMJAwAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxHucwB3AQAKAAgJLxHucwB3AQAAAA==.',
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
