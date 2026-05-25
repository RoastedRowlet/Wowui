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

local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Rogue-Subtlety','DemonHunter-Devourer','Priest-Shadow','Warrior-Protection','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Paladin-Holy','Unknown-Unknown','Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','Monk-Mistweaver','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Rogue-Outlaw','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-05-23',data={Ad='Adnerb:BAABLgAECn8VAAQBAAgJORJ+FwDVAAABAAYJAxN+FwDVAAACAAQJ6g4TrwCoAAADAAIJkQerVQA3AAABLgAFFAUJBwAEACURAA==.',
Ah='Ahriman:BAABLgAECn8XAAIFAAYJLw50jgDZAAAFAAYJLw50jgDZAAAAAA==.',
Al='Alystra:BAABLgAECn8ZAAIGAAgJRQbKOQADAQAGAAgJRQbKOQADAQAAAA==.',
An='Anjedin:BAAALgAECgYJEAAAAA==.',
Ao='Aoki:BAABLgAECn8jAAICAAgJ6CCIGABqAgACAAgJ6CCIGABqAgAAAA==.',
Ar='Archdemon:BAABLgAECn8iAAIHAAkJOxgWDQDyAQAHAAkJOxgWDQDyAQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAFFAIJAgABLgAFFAUJBwAEACURAA==.Arkanoas:BAACLgAFFH8OAAIIAAUJcgsPUwAhAQAIAAUJcgsPUwAhAQAuAAQKfysAAggACQm2Fgw4AJQCAAgACQm2Fgw4AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBwAEACURAA==.Battahelin:BAAALgAECgQJBgAAAA==.Bazoo:BAAALgAECgEJAQAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBwAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIJAAYJ/Aj5SACyAAAJAAYJ/Aj5SACyAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.Blended:BAAALgAECgEJAQAAAA==.Bloody:BAAALgAFFAEJAQAAAA==.',
Br='Breathplay:BAABLgAECn8YAAIKAAkJbRqWPQBBAgAKAAkJbRqWPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8yAAILAAkJUBPCKQDkAQALAAkJUBPCKQDkAQAAAA==.',
Ca='Caroquintero:BAABLgAECn8fAAIIAAYJcgN04QC0AAAIAAYJcgN04QC0AAAAAA==.',
Ch='Charliemen:BAAALgAECgQJBAAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAACLgAFFH8IAAIMAAMJKxzHHgABAQAMAAMJKxzHHgABAQAuAAQKfzQAAgwACQnRIz0IABIDAAwACQnRIz0IABIDAAAA.Churrasco:BAAALgAECgQJCAAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Co='Cojeculos:BAAALgAECgQJBwAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn81AAMNAAkJZBVFGgDjAQANAAkJZBVFGgDjAQAOAAYJKw1xYQD/AAAAAA==.Daizenat:BAAALgADCgIJAgAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCQAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAACLgAFFH8JAAIKAAQJRQdkXgARAQAKAAQJRQdkXgARAQAuAAQKfyQAAgoACQltGeEkAE4CAAoACQltGeEkAE4CAAAA.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Durötan:BAABLgAECn8YAAQCAAkJUhByMgDpAQACAAkJUhByMgDpAQABAAUJRAoAVgDxAAADAAEJvwrGUwA6AAABLgAFFAgJHAAPAJUdAA==.Dutchess:BAABLgAECn8eAAIQAAgJQBn9RgDSAQAQAAgJQBn9RgDSAQAAAA==.',
Dy='Dylan:BAACLgAFFH8VAAIIAAUJXCK4KACBAQAIAAUJXCK4KACBAQAuAAQKfy4AAggACQlWJaIEAFQDAAgACQlWJaIEAFQDAAAA.Dylanj:BAAALgAECgQJBAABLgAFFAUJFQAIAFwiAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.Echoes:BAAALgADCgQJBAAAAA==.',
Eg='Egonspengler:BAAALgADCgQJBAAAAA==.',
El='Elayia:BAAALgADCgEJAQAAAA==.Elowen:BAAALgAFFAIJBAAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgcJDgAAAA==.Eríngo:BAAALgAFFAEJAQAAAA==.',
Es='Esna:BAAALgADCgUJCQAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJEAAAAA==.',
Fl='Floise:BAACLgAFFH8RAAMRAAUJ6hSDEwCIAQARAAUJthODEwCIAQASAAIJVBNZDQCTAAAuAAQKfx4ABBIACQn7GXcMAIwCABIACQlAGXcMAIwCABEABwkQFaw2AAgBAAYAAQlcEsppADsAAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Foamtotem:BAAALgADCgEJAQAAAA==.Forumsoldier:BAACLgAFFH8GAAIIAAQJageiVQAaAQAIAAQJageiVQAaAQAuAAQKfyMAAggACAmWFyhUADwCAAgACAmWFyhUADwCAAAA.',
Fr='Frozenscorch:BAAALgAECggJEgAAAA==.',
Ft='Fteve:BAAALgAECgUJCQAAAA==.',
['Fä']='Fälkor:BAABLgAECn8rAAMTAAgJrQbpEQDIAAAUAAgJrQYKQAACAQATAAYJJAbpEQDIAAAAAA==.',
['Fö']='Föx:BAAALgAECgcJCQAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glorfindel:BAAALgAFFAEJAgABLgAFFAUJDAAMAPMWAA==.Glys:BAAALgAECgUJCgAAAA==.',
Go='Gogocow:BAAALgAECgEJAQAAAA==.Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAABLgAECn8UAAIPAAcJMAJUaACGAAAPAAcJMAJUaACGAAAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Grandpa:BAAALgAECgYJCAAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8cAAIVAAYJTCM2FABHAgAVAAYJTCM2FABHAgAAAA==.',
He='Helpingyou:BAABLgAECn8bAAIGAAkJ/wgmJACAAQAGAAkJ/wgmJACAAQAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAABLgAECn8dAAIVAAcJsRIoLACJAQAVAAcJsRIoLACJAQAAAA==.',
Im='Impaladin:BAAALgAECgMJAwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwABLgAECgUJBgAWAAAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJEQAAAA==.Izzia:BAABLgAECn8dAAILAAgJ0BjEGgBMAgALAAgJ0BjEGgBMAgAAAA==.',
Ja='Jabbathabutt:BAAALgAECgYJCQAAAA==.Jaceret:BAAALgAECgEJAQAAAA==.Jasia:BAAALgADCgYJCAAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8sAAMRAAkJpA+pGADgAQARAAkJpA+pGADgAQAGAAUJyAhmRADZAAAAAA==.Kaye:BAAALgADCgMJAgAAAA==.Kayewyn:BAABLgAECn8kAAILAAgJaBFfNQCiAQALAAgJaBFfNQCiAQAAAA==.',
Kb='Kbdh:BAAALgAECgYJCwABLgAFFAIJAwAWAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAWAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAWAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAWAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.Kbpaladin:BAAALgAECgYJBgABLgAFFAIJAwAWAAAAAA==.',
Ke='Keiji:BAAALgAECgYJDgAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgYJCgABLgAFFAUJFwALAHUbAA==.Kynn:BAACLgAFFH8XAAILAAUJdRtsDwCwAQALAAUJdRtsDwCwAQAuAAQKfzcAAgsACQmUIvMBAIEDAAsACQmUIvMBAIEDAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8uAAIQAAgJkRJuWgCeAQAQAAgJkRJuWgCeAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgYJDgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAABLgAECggJGgANAHQcAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAUJEQARAOoUAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8rAAMXAAkJlyAtBwBhAgAPAAcJ+B/yGACDAgAXAAkJXh0tBwBhAgAAAA==.',
Mi='Mightymost:BAAALgAECgYJCwAAAA==.',
Mu='Mudd:BAABLgAECn8jAAMXAAgJkh9eCABEAgAXAAgJkh9eCABEAgAPAAEJcBAGhgA2AAAAAA==.Mudds:BAABLgAECn8cAAIJAAgJoSB7EAB5AgAJAAgJoSB7EAB5AgABLgAECggJIwAXAJIfAA==.',
Na='Naelia:BAAALgAECgYJEAABLgAFFAUJFgAKAEEVAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ne='Nenekirimaru:BAAALgADCgIJAgAAAA==.',
Ni='Nicodemus:BAAALgADCgIJAgAAAA==.Nightrush:BAABLgAECn8oAAMCAAgJIiVMGgBfAgACAAYJBCZMGgBfAgABAAYJtCHVCwCCAQAAAA==.',
No='Noodles:BAABLgAECn8dAAIFAAcJvhYUaQAtAQAFAAcJvhYUaQAtAQAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAABLgAECn8UAAILAAYJbgWmdQC0AAALAAYJbgWmdQC0AAAAAA==.',
Ok='Okomo:BAAALgAECgUJBgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMVAAgJdRGqOABAAQAVAAcJrBKqOABAAQAQAAQJXQw6+gCRAAAAAA==.Pantsu:BAABLgAECn9BAAQKAAgJuCWsEQDBAgAKAAgJgSWsEQDBAgAYAAgJ2CDRBgCOAgAZAAgJ/x8MBQAtAgAAAA==.Pateaviejas:BAAALgAECgMJAwAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAABLgAECn8ZAAIaAAYJTgV+XACkAAAaAAYJTgV+XACkAAAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAISAAYJHBFpRAAnAQASAAYJHBFpRAAnAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAACLgAFFH8PAAIJAAQJixgVDAA7AQAJAAQJixgVDAA7AQAuAAQKfykAAgkACQneH34GAMQCAAkACQneH34GAMQCAAAA.',
Pu='Punchbear:BAAALgADCgYJBgAAAA==.Punchize:BAABLgAECn8lAAMbAAgJAiFQCACSAgAbAAgJAiFQCACSAgAaAAIJ9ApUewBIAAAAAA==.Punchlocks:BAAALgAECgEJAQAAAA==.',
Qu='Quirkchungus:BAAALgAECgYJDwAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgkJDQAAAA==.',
Re='Remote:BAAALgAECgQJBwAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJEQAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8mAAIcAAkJGiBfAwCrAgAcAAkJGiBfAwCrAgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgUJCgAAAA==.',
Sc='Scrubuckett:BAAALgADCgYJBgAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8HAAMEAAUJJRHoEQC6AAAEAAUJJRHoEQC6AAAdAAEJrwmxDgBJAAAuAAQKfx8ABB0ABwmTGyoHAPQBAB0ABgnVHioHAPQBAAQABQnGF0w9ADIBAB4AAQn7FwwbAEMAAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowslam:BAAALgAECgYJCAAAAA==.Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJCgABLgAFFAMJBwASAPUSAA==.Shzam:BAAALgADCgYJDgAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8fAAIfAAkJAA7VFQBIAQAfAAkJAA7VFQBIAQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Sneeze:BAAALgADCgIJAgAAAA==.Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8qAAQgAAkJnxcKOgDZAQAgAAgJfRYKOgDZAQAhAAMJ6woSQwCpAAAiAAIJLRFbKwBFAAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8cAAMPAAgJlR1iAACnAgAPAAgJlR1iAACnAgAXAAEJoAa6CwBTAAAuAAQKfy8AAw8ACAl9JccEAPsCAA8ACAl9JccEAPsCABcABQmoIPwcAAgBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBwAEACURAA==.',
Sp='Spongeybob:BAAALgADCgEJAgAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgAECgQJBAAAAA==.',
Ta='Taelia:BAACLgAFFH8WAAIKAAUJQRUzQgBBAQAKAAUJQRUzQgBBAQAuAAQKf0MAAgoACQlkI0wIABUDAAoACQlkI0wIABUDAAAA.Tahine:BAAALgAECgcJEAAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgAECgEJAQABLgAFFAQJCgASAOgHAA==.Timetwoflame:BAABLgAECn8fAAMjAAgJ5RH+DQDKAQAjAAgJ5RH+DQDKAQATAAQJugeeFgCBAAAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJCwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
Tu='Tugboat:BAAALgADCgIJAgAAAA==.',
Tw='Twoæ:BAAALgAECgEJAQAAAA==.',
['Tû']='Tûâny:BAAALgAECgUJBQAAAA==.',
Up='Upphoria:BAABLgAECn8bAAMSAAgJ6AosLQA+AQASAAgJ6AosLQA+AQAGAAIJPgNYewAjAAAAAA==.',
Ur='Urkel:BAAALgAECgEJAQAAAA==.',
Ut='Uthomage:BAAALgAECgMJAwAAAA==.',
Va='Vashi:BAAALgADCgcJBwAAAA==.',
Vi='Viccan:BAABLgAECn8lAAMhAAkJHAeXEAANAQAhAAkJ/AaXEAANAQAgAAMJKgLqAQFDAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgcJBwAAAA==.',
Wi='Wildwood:BAAALgADCgMJAwAAAA==.Willowleaf:BAAALgAECgEJAQABLgAFFAMJBwASAPUSAA==.',
Wo='Wolffie:BAAALgAECggJEQAAAA==.',
Wu='Wushuu:BAAALgAECgUJCgABLgAFFAUJDgAIAHILAA==.',
Xa='Xampu:BAAALgADCgYJBgAAAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8qAAMJAAkJdB5qDABXAgAJAAgJ+B5qDABXAgAaAAQJCAfWZwB9AAAAAA==.',
Za='Zaelyse:BAAALgAECgYJBgAAAA==.Zaton:BAABLgAECn8ZAAIIAAgJLxGTaACOAQAIAAgJLxGTaACOAQAAAA==.',
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
