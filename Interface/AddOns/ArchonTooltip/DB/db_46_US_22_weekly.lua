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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Druid-Guardian','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-06-13',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORK9GwDNAAABAAYJAxO9GwDNAAACAAQJ6g400gCfAAADAAIJkQeEYwA0AAABLgAFFAUJBwAEACURAA==.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw6aowDYAAAFAAYJLw6aowDYAAAAAA==.',
Al='Alystra:BAABLgAECn8aAAIGAAgJ1wZzQAAMAQAGAAgJ1wZzQAAMAQAAAA==.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAACLgAFFH8JAAICAAMJCBtTUQD+AAACAAMJCBtTUQD+AAAuAAQKfyYAAgIACAkfIr0cAHQCAAIACAkfIr0cAHQCAAAA.',
Ar='Archdemon:BAABLgAECn8yAAIHAAkJMxwmCQBgAgAHAAkJMxwmCQBgAgAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAABLgAECn8bAAMIAAkJ/BkwCAALAgAIAAcJ9RowCAALAgAJAAYJvhclHAB3AQABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8PAAIKAAYJXAxEQQBtAQAKAAYJXAxEQQBtAQAuAAQKfysAAgoACQm2Fgw4AJQCAAoACQm2Fgw4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Balaba:BAAALgAECgEJAQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAILAAYJ/Ai2WACrAAALAAYJ/Ai2WACrAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIMAAkJbRqWPQBBAgAMAAkJbRqWPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAINAAkJUBPwLwDhAQANAAkJUBPwLwDhAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8lAAIKAAYJhgVI6ADLAAAKAAYJhgVI6ADLAAAAAA==.',
Ch='Charliemen:BAAALgAECgQJCAAAAA==.Chilli:BAAALgAECgUJBQAAAA==.Chubtart:BAACLgAFFH8MAAIOAAQJ9BrbGQBEAQAOAAQJ9BrbGQBEAQAuAAQKfzQAAg4ACQnRIz0IABIDAA4ACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Ci='Ciborg:BAAALgAECgMJBQAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJEwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAACLgAFFH8LAAMPAAMJPA5mTwCwAAAPAAMJPA5mTwCwAAAQAAIJWAjRRgBrAAAuAAQKfzUAAxAACQlkFbIgANsBABAACQlkFbIgANsBAA8ABgkrDRx0APwAAAAA.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.Darthforum:BAAALgADCgMJAwAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8NAAIMAAQJ/AgafQAJAQAMAAQJ/AgafQAJAQAuAAQKfyQAAgwACQltGRsuAEQCAAwACQltGRsuAEQCAAAA.',
Do='Dordis:BAAALgADCgEJAQAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8ZAAQCAAkJUhD5PwDeAQACAAkJUhD5PwDeAQABAAUJRAoAVgDxAAADAAEJvwrrXwA5AAABLgAFFAgJHgARADEeAA==.Dutchess:BAABLgAECn8nAAISAAkJwx61HACXAgASAAkJwx61HACXAgAAAA==.',
Dy='Dylan:BAACLgAFFH8cAAIKAAUJjCRUNACaAQAKAAUJjCRUNACaAQAuAAQKfy8AAgoACQlpJbYFAFQDAAoACQlpJbYFAFQDAAAA.Dylanj:BAAALgAECgQJBAABLgAFFAUJHAAKAIwkAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgAECgEJAQAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
Er='Eresiine:BAAALgAECggJEAAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8UAAMTAAYJBxQmFwCvAQATAAYJBhMmFwCvAQAUAAIJVBNZDQCTAAAuAAQKfx4ABBQACQn7GXcMAIwCABQACQlAGXcMAIwCABMABwkQFRhBAAQBAAYAAQlcEg5/ADoAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgAECgUJCgAAAA==.Forumshaman:BAAALgADCgcJBwAAAA==.Forumsoldier:BAACLgAFFH8IAAIKAAUJHQgobQAPAQAKAAUJHQgobQAPAQAuAAQKfygAAgoACQnUFb9EAAoCAAoACQnUFb9EAAoCAAAA.',
Fr='Frozenscorch:BAAALgAECgkJEwAAAA==.',
Ft='Fteve:BAAALgAECgUJEgAAAA==.',
Fu='Fungasaur:BAABLgAFFH8FAAIVAAMJnxhjFADZAAAVAAMJnxhjFADZAAAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMWAAgJrQbyFAC9AAAXAAgJrQZITQD0AAAWAAYJJAbyFAC9AAAAAA==.',
['Fö']='Föx:BAAALgAFFAQJBAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAwABLgAFFAYJEAAOABwUAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8lAAIRAAcJaANMbACvAAARAAcJaANMbACvAAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgcJDgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8fAAIYAAcJGSKZEACQAgAYAAcJGSKZEACQAgAAAA==.Hathus:BAAALgAECgMJBAAAAA==.',
He='Helpingyou:BAABLgAECn8lAAIGAAkJPw0sJQCfAQAGAAkJPw0sJQCfAQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8hAAIYAAgJHxIrKwC0AQAYAAgJHxIrKwC0AQAAAA==.',
Il='Ilitha:BAAALgAECgEJAQAAAA==.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAZAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAABLgAECn8VAAICAAYJ+xSIUQB0AQACAAYJ+xSIUQB0AQAAAA==.Izzia:BAABLgAECn8mAAINAAgJUxsmGgByAgANAAgJUxsmGgByAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMTAAkJpA/hHwDMAQATAAkJpA/hHwDMAQAGAAUJyAhmRADZAAAAAA==.Kaye:BAAALgAECgYJBgAAAA==.Kayewyn:BAABLgAECn8tAAINAAkJBhUMIQA8AgANAAkJBhUMIQA8AgAAAA==.',
Kb='Kbdh:BAAALgAECgYJDgABLgAFFAIJAwAZAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAZAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAZAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAZAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAZAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.Kelemvor:BAAALgAECgUJBQAAAA==.Kelôx:BAAALgAECgQJCAAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Ko='Koharu:BAAALgAECgEJAQAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJHAANAO8dAA==.Kynn:BAACLgAFFH8cAAINAAUJ7x3FFQCtAQANAAUJ7x3FFQCtAQAuAAQKfzgAAw0ACQmUIvMBAIEDAA0ACQmUIvMBAIEDAA4AAQl3EWyFADsAAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8wAAISAAgJkRLebwCMAQASAAgJkRLebwCMAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgAQAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAYJFAATAAcUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMaAAkJlyB5CQBTAgARAAcJ+B/yGACDAgAaAAkJXh15CQBTAgAAAA==.',
Mi='Mightymost:BAABLgAECn8ZAAIbAAgJAQjtFQD0AAAbAAgJAQjtFQD0AAAAAA==.',
Mu='Mudd:BAABLgAECn8nAAMaAAkJUB43BgCZAgAaAAkJUB43BgCZAgARAAEJcBBQngA2AAAAAA==.Mudds:BAABLgAECn8dAAILAAkJHiB7EAB5AgALAAkJHiB7EAB5AgABLgAECgkJJwAaAFAeAA==.',
Na='Naelia:BAACLgAFFH8FAAIcAAIJ/AoWogCFAAAcAAIJ/AoWogCFAAAuAAQKfx4AAhwABwniFr5TAKABABwABwniFr5TAKABAAEuAAUUBgkoAAwA3hYA.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiVBJABOAgACAAYJBCZBJABOAgABAAYJtCEcDgB5AQAAAA==.',
No='Noodles:BAABLgAECn8fAAIFAAcJvhYdeQAqAQAFAAcJvhYdeQAqAQAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Ny='Nya:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAINAAYJbgWuggCxAAANAAYJbgWuggCxAAAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8hAAMYAAkJDRHlQAA8AQAYAAcJrBLlQAA8AQASAAYJ0go82gDiAAAAAA==.Pantsu:BAABLgAECn9DAAQMAAkJuSVCCAAvAwAMAAkJiCVCCAAvAwAJAAgJ2CBBCQB9AgAIAAgJ/x8wBwAlAgAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIdAAYJTgVZfQCdAAAdAAYJTgVZfQCdAAAAAA==.Pennyz:BAAALgADCgYJBgAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIUAAYJHBFpRAAnAQAUAAYJHBFpRAAnAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8WAAILAAUJLRsbDwA/AQALAAUJLRsbDwA/AQAuAAQKfykAAgsACQneH70IALcCAAsACQneH70IALcCAAAA.',
Pu='Punchbear:BAAALgAECgUJBQAAAA==.Punchize:BAABLgAECn8xAAMeAAkJSyPpAgAmAwAeAAkJSyPpAgAmAwAdAAIJ9AoipgBHAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQABLgAFFAQJCgAfAOccAA==.',
Re='Remote:BAAALgAECgQJCAAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Riddlez:BAAALgAECgYJEAAAAA==.Rilea:BAABLgAECn8UAAICAAcJAw8sfgA9AQACAAcJAw8sfgA9AQAAAA==.Risenspirits:BAAALgAECgYJBgAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn82AAIgAAkJjyIEAgAIAwAgAAkJjyIEAgAIAwAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgAECgEJAQAAAA==.',
Se='Sebrine:BAAALgAECgUJDAAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAAEAAUJJRHoEQC6AAAhAAEJrwktEwA7AAAuAAQKfx8ABCEABwmTGyoHAPQBACEABgnVHioHAPQBAAQABQnGF0w9ADIBACIAAQn7FzchAEMAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJDAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAFFAMJBAAAAA==.Shzam:BAAALgAECgEJAQAAAA==.',
Si='Sixtontbone:BAAALgAECgIJAwABLgAECgYJFwAUABwRAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Slang:BAAALgAECgEJAQAAAA==.Sleipner:BAABLgAECn8fAAIjAAkJAA6HGgBBAQAjAAkJAA6HGgBBAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQcAAkJnxd0RADMAQAcAAgJfRZ0RADMAQAbAAMJ6woSQwCpAAAkAAIJLRGQOABAAAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8eAAMRAAgJMR6VAQCVAgARAAgJMR6VAQCVAgAaAAEJoAa6CwBTAAAuAAQKfzYAAxEACAl9JXkGAPYCABEACAl9JXkGAPYCABoABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.Spookyboy:BAAALgAECgcJBwAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBwAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8oAAIMAAYJ3ha5MgCUAQAMAAYJ3ha5MgCUAQAuAAQKf0QAAgwACQlkI50MAAYDAAwACQlkI50MAAYDAAAA.Tahine:BAABLgAECn8VAAIfAAcJFhK1GABEAQAfAAcJFhK1GABEAQAAAA==.Taisho:BAAALgAECgUJBwAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJDgAUAL4QAA==.Timetwoflame:BAABLgAECn8kAAMlAAgJLxNODgDmAQAlAAgJLxNODgDmAQAWAAQJugc+GgB5AAAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8gAAMUAAkJ8wlnMABIAQAUAAkJ8wlnMABIAQAGAAIJPgPplAAhAAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8qAAMbAAkJIAcSFQD/AAAbAAkJ/AYSFQD/AAAcAAUJiQLt7gCAAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJBAAZAAAAAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAYJDwAKAFwMAA==.',
Xa='Xampu:BAAALgAECgQJBAAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn86AAMLAAkJex/VCAC2AgALAAkJex/VCAC2AgAdAAQJCAcWiwB6AAAAAA==.',
Za='Zaelyse:BAABLgAFFH8GAAISAAMJ/hZJYQDmAAASAAMJ/hZJYQDmAAAAAA==.Zaton:BAABLgAECn8ZAAIKAAgJLxFUfAB8AQAKAAgJLxFUfAB8AQAAAA==.',
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
