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

local lookup = {'Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Unknown-Unknown','Druid-Restoration','Evoker-Augmentation','DeathKnight-Frost','Priest-Shadow','Druid-Balance','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Warlock-Demonology','DeathKnight-Unholy','Hunter-BeastMastery','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Shaman-Elemental','Paladin-Protection','Warrior-Protection','Mage-Fire','Shaman-Restoration','Rogue-Subtlety','Evoker-Devastation','Shaman-Enhancement','Druid-Guardian','Paladin-Holy','Priest-Discipline','Evoker-Preservation','Mage-Arcane','Rogue-Assassination','Warrior-Arms',}
local provider = {region='US',realm='Staghelm',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Absens:BAABLgAECn82AAMBAAkJExJ0BwCQAQABAAkJgA90BwCQAQACAAgJag+3CABxAQAAAA==.',
Ad='Adorian:BAAALgAECgcJBwABLgAFFAQJCAADANYcAA==.Adwillon:BAAALgADCgQJBQABLgAECgYJDgAEAAAAAA==.',
Ae='Aedoril:BAAALgADCgEJAQAAAA==.Aerosse:BAAALgADCgEJAQAAAA==.',
Af='Aforceofone:BAAALgAECgMJBwAAAA==.',
Ai='Airdreanna:BAAALgADCgQJBAAAAA==.',
Ak='Akama:BAAALgAECgYJCwABLgAFFAYJGgAFABgdAA==.',
Al='Alivanllan:BAAALgAECgIJAgAAAA==.Alteisen:BAAALgAECgUJBQAAAA==.',
Am='Ambitious:BAAALgAECgMJCgAAAA==.Amerlinn:BAAALgAECgUJCwAAAA==.',
An='Anamuht:BAAALgAECgYJBgABLgAECggJJwAGAPIeAA==.Annaday:BAABLgAECn8gAAIDAAgJtg37HQD+AAADAAgJtg37HQD+AAAAAA==.Antiock:BAACLgAFFH8IAAIDAAQJ1hyhCgBMAQADAAQJ1hyhCgBMAQAuAAQKfycAAwMACQnaI0EEAAoDAAMACQnaI0EEAAoDAAcABwnPHE8FAO4BAAAA.Anyaesthesia:BAAALgADCgYJBgAAAA==.Anyamonka:BAAALgAECgYJDgAAAA==.',
Ap='Apocalich:BAAALgAECgUJBQAAAA==.',
Aq='Aquenia:BAAALgADCggJDAAAAA==.',
Ar='Aralaith:BAABLgAECn8hAAIIAAgJXiXyBADTAgAIAAgJXiXyBADTAgABLgAFFAgJFAAJAEQiAA==.Argonaut:BAAALgAECgIJAgAAAA==.Argul:BAAALgADCgEJAQAAAA==.Ariea:BAAALgADCgYJBgAAAA==.Artto:BAABLgAECn8eAAIKAAYJPxHfhAAcAQAKAAYJPxHfhAAcAQAAAA==.',
As='Asevenhex:BAAALgAECgEJAQAAAA==.Ashbrínger:BAABLgAECn89AAIKAAkJSSVSAgBYAwAKAAkJSSVSAgBYAwAAAA==.Association:BAAALgADCgQJBAAAAA==.Asunã:BAAALgAECgIJAgAAAA==.',
Au='Aurah:BAAALgAECgIJBAAAAA==.',
Av='Averax:BAABLgAECn8gAAMLAAcJTBnXMwCuAQALAAcJTBnXMwCuAQAMAAEJvQ2JbgA3AAAAAA==.Avyrax:BAAALgADCgcJDQABLgAECgcJIAALAEwZAA==.',
Ay='Aybara:BAAALgADCgQJBAAAAA==.Aylakaye:BAAALgADCgMJAwAAAA==.Ayraena:BAABLgAECn8XAAMJAAgJHQioLAAYAQAJAAgJHQioLAAYAQAFAAQJEgFiogA+AAAAAA==.',
Az='Azyrieth:BAAALgADCgEJAQAAAA==.Azzathoth:BAAALgADCgcJDAAAAA==.',
Ba='Babyshoes:BAAALgAECgEJAQAAAA==.Bakedtofu:BAABLgAECn8UAAMBAAYJ7wc9RwCZAAANAAYJ7wegowC5AAABAAQJGQQ9RwCZAAAAAA==.Bashine:BAAALgAECgYJEQABLgAFFAUJFgAOAP4fAA==.Baylohn:BAABLgAECn8WAAIPAAcJ8haCRgB3AQAPAAcJ8haCRgB3AQAAAA==.',
Be='Bearwrestler:BAABLgAECn8aAAIQAAgJ1Bd5QwDRAQAQAAgJ1Bd5QwDRAQABLgAFFAQJDwADAJAgAA==.Beefynugs:BAAALgAECgkJAQAAAA==.',
Bi='Bier:BAAALgAECgQJCAAAAA==.Bigrig:BAAALgAECgkJDgAAAA==.Bitterman:BAABLgAECn8bAAMNAAgJhA3zUwBjAQANAAgJeA3zUwBjAQABAAEJww/ZcAA1AAAAAA==.',
Bj='Bjornvalion:BAAALgADCgQJBAAAAA==.',
Bl='Blackmage:BAAALgAECgEJAQAAAA==.Bladed:BAABLgAECn8ZAAQRAAYJURfwDwD7AAALAAYJpRPWWwAlAQARAAUJuRfwDwD7AAAMAAEJAACDWwAAAAAAAA==.Blinx:BAAALgADCgQJBAAAAA==.',
Bo='Boogies:BAAALgADCgQJBwAAAA==.',
Bu='Buffie:BAABLgAECn8ZAAIKAAgJGBoeWADaAQAKAAgJGBoeWADaAQAAAA==.Bullwyf:BAAALgADCgMJAwAAAA==.Bumblbeetuna:BAAALgADCgQJBAAAAA==.',
['Bá']='Bád:BAAALgADCggJDgABLgADCgkJCQAEAAAAAA==.',
Ca='Calduu:BAAALgAECgMJAwAAAA==.Caledia:BAAALgAECgYJEQAAAA==.Callana:BAAALgADCgMJBQAAAA==.Camedra:BAABLgAECn8pAAIFAAgJVyJODAC/AgAFAAgJVyJODAC/AgAAAA==.Carinancey:BAAALgAECgEJAQAAAA==.Carperoni:BAAALgADCgcJBwAAAA==.Casseous:BAAALgADCgUJBwAAAA==.Catamynyia:BAABLgAECn8fAAIPAAgJJAweSAByAQAPAAgJJAweSAByAQAAAA==.Caylaetal:BAAALgADCgYJCwAAAA==.',
Cc='Cchaos:BAAALgAECgIJBgAAAA==.',
Ce='Celaborn:BAABLgAECn8aAAISAAgJPxxRHAC+AQASAAgJPxxRHAC+AQAAAA==.',
Ch='Chazaraz:BAABLgAECn8iAAMTAAgJtgr6GgB+AQATAAcJQAn6GgB+AQAPAAgJEQjrXAA1AQAAAA==.Chevy:BAAALgAECgEJAwAAAA==.Chifreak:BAAALgAFFAIJAgABLgAECgcJIAALAPkiAA==.Chillmourne:BAAALgAECgcJEwABLgAECggJDgAEAAAAAA==.Chimaira:BAAALgADCgIJAgAAAA==.Chucknoris:BAAALgADCgcJCQAAAA==.Chugbuggins:BAAALgAECgYJDgAAAA==.',
Ci='Cindria:BAABLgAECn8eAAIQAAYJzAw0oAACAQAQAAYJzAw0oAACAQAAAA==.',
Cl='Cliffgate:BAAALgADCgMJAwAAAA==.',
Co='Conduction:BAAALgAECgUJCAAAAA==.',
Cp='Cptbonez:BAAALgAECgYJEgABLgAECggJFwAUAHQQAA==.',
Cr='Crankadin:BAAALgADCgUJBQABLgAECgIJAwAEAAAAAA==.Crankchi:BAAALgADCgYJBwABLgAECgIJAwAEAAAAAA==.Crazz:BAAALgADCgEJAQAAAA==.Crooky:BAAALgADCgcJBwABLgAFFAUJFAAOAKwcAA==.Crucifiiks:BAAALgAECgMJAwAAAA==.Cruciö:BAAALgAECgEJAQAAAA==.Crànk:BAAALgAECgIJAwAAAA==.',
Cu='Curveball:BAAALgAECgMJAwABLgAECggJGwANAIQNAA==.',
Da='Dalearnhardt:BAAALgADCgcJDgABLgAECgcJEgAEAAAAAA==.Darkstär:BAABLgAECn8pAAIDAAgJ7RqnDgChAQADAAgJ7RqnDgChAQAAAA==.Darkwood:BAAALgADCgEJAgAAAA==.Dauc:BAAALgADCgEJAQAAAA==.',
De='Deacon:BAABLgAECn8gAAQVAAcJAgg0PwC2AAAVAAUJmgo0PwC2AAAUAAUJLgTNRgCpAAAWAAQJFgQiVQB7AAAAAA==.Deadmantooth:BAAALgADCgYJBgABLgAECgcJIAANACwVAA==.Deardren:BAAALgAECgUJBQAAAA==.Deathknights:BAAALgAFFAEJAQAAAA==.Deeanne:BAAALgAECgMJAwAAAA==.Deepfriar:BAABLgAECn8pAAIXAAgJkiKWCACZAgAXAAgJkiKWCACZAgAAAA==.Deidra:BAAALgADCgMJAwAAAA==.Demonhunts:BAAALgAFFAMJAwAAAA==.Demonmore:BAABLgAECn8cAAMMAAYJfQx4OwASAQAMAAYJNAt4OwASAQARAAUJWQo+FwCdAAAAAA==.Derailed:BAAALgAECgQJBwAAAA==.Dethwing:BAAALgADCggJDAAAAA==.Devilfrost:BAAALgAECgEJAQABLgAECgMJBgAEAAAAAA==.Dewshine:BAAALgAECgYJCwAAAA==.',
Dh='Dhampir:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Dhgeek:BAAALgAECgEJAQAAAA==.',
Di='Diablognomis:BAAALgAECgMJBgAAAA==.Dingô:BAAALgADCggJGAAAAA==.Dirtman:BAABLgAECn8jAAIYAAgJKxmLGQDEAQAYAAgJKxmLGQDEAQAAAA==.',
Dk='Dkrise:BAAALgAECgMJAwABLgAECggJJAAGAFcLAA==.',
Dn='Dneoh:BAAALgAECgkJCAABLgAFFAMJCgAJAOciAA==.',
Do='Donald:BAAALgADCgQJBAAAAA==.Donny:BAABLgAECn8bAAMKAAgJJB3RIQA7AgAKAAgJJB3RIQA7AgAZAAEJWw/gOwAtAAAAAA==.Doodyshamala:BAAALgAECgEJAQAAAA==.Doozey:BAACLgAFFH8GAAILAAMJzhLrPQDkAAALAAMJzhLrPQDkAAAuAAQKfyUAAgsACAl4IAAaADcCAAsACAl4IAAaADcCAAAA.Dorigis:BAAALgADCgkJLQABLgAECggJFwAaAG8fAA==.Dotdotdotded:BAABLgAECn8WAAINAAgJtwUVcgAcAQANAAgJtwUVcgAcAQAAAA==.',
Dr='Drewdog:BAABLgAECn8jAAMPAAYJLxaqYwAjAQATAAYJKQz+JAAmAQAPAAYJGRaqYwAjAQAAAA==.Droid:BAAALgAECgEJAQAAAA==.Drunkgerardo:BAAALgAECgQJBQAAAA==.Drunkzen:BAAALgAECgUJBQAAAA==.Druyesil:BAAALgAECgEJAgAAAA==.',
Du='Dubes:BAABLgAECn8mAAIQAAgJgRRQTQCyAQAQAAgJgRRQTQCyAQAAAA==.',
['Dá']='Dárkthorn:BAAALgAECgIJBAAAAA==.',
['Dö']='Dökkálfar:BAAALgAECgEJAQAAAA==.',
Ea='Easybreezin:BAAALgAECgUJDAAAAA==.',
Ei='Eirote:BAABLgAECn8pAAIbAAgJABZ1AgDPAQAbAAgJABZ1AgDPAQAAAA==.',
El='Eldari:BAABLgAECn8YAAIJAAgJ2RtHEgD1AQAJAAgJ2RtHEgD1AQAAAA==.Elem:BAACLgAFFH8PAAIcAAYJUwhdDwB5AQAcAAYJUwhdDwB5AQAuAAQKfyMAAhwACAmcIFMYAFMCABwACAmcIFMYAFMCAAAA.Elm:BAAALgAECgYJEAAAAA==.Elyssaena:BAAALgAECgYJCgAAAA==.',
Em='Emiliachan:BAAALgAECgcJCwAAAA==.',
En='Enzojr:BAABLgAECn8yAAIdAAkJtyP6AgDjAgAdAAkJtyP6AgDjAgAAAA==.',
Ep='Ephixa:BAAALgAECgYJDwAAAA==.',
Er='Eridanos:BAAALgADCgYJBgAAAA==.Erisiel:BAAALgAECgEJAQAAAA==.Eruelle:BAAALgAFFAIJAwABLgAFFAgJFAAJAEQiAA==.',
Ev='Evoke:BAABLgAECn8fAAMGAAgJgyF3CgDOAgAGAAgJdB93CgDOAgAeAAYJZyBaDQAEAgAAAA==.',
Ey='Eye:BAACLgAFFH8IAAIfAAMJBiGJBAAwAQAfAAMJBiGJBAAwAQAuAAQKfx4AAx8ACAk0IooFAK0CAB8ACAk0IooFAK0CABgAAQmZDN2PACgAAAAA.',
['Eí']='Eís:BAAALgADCgYJCwAAAA==.',
Fa='Faeira:BAAALgAECgcJCQAAAA==.Faloril:BAAALgAECgEJAQAAAA==.Faranth:BAABLgAECn8oAAIGAAgJvhkWFgDeAQAGAAgJvhkWFgDeAQAAAA==.Faronyr:BAAALgAECgEJAQAAAA==.',
Fe='Felboi:BAAALgAECgUJDgAAAA==.Felorc:BAAALgAECgEJAQAAAA==.Felynne:BAAALgAECgUJCwAAAA==.Fenrík:BAAALgADCgIJAgAAAA==.Feo:BAABLgAECn8ZAAILAAgJnhf4MAC6AQALAAgJnhf4MAC6AQAAAA==.Ferum:BAABLgAECn83AAIFAAkJ/iLeAgByAwAFAAkJ/iLeAgByAwAAAA==.',
Fi='Fionnan:BAABLgAECn8kAAIgAAgJlQiuHwDPAAAgAAgJlQiuHwDPAAABLgAECggJKQAcANgJAA==.',
Fo='Forest:BAACLgAFFH8IAAQJAAMJfguqIADIAAAJAAMJtAqqIADIAAAFAAIJZwbpQwBsAAAgAAIJtgjsEwBhAAAuAAQKfykAAwkACAktHikNAMYCAAkACAktHikNAMYCAAUAAwn3G4lXAO8AAAAA.',
Fr='Fretless:BAAALgADCgYJCgAAAA==.Frostedrayne:BAAALgADCgUJBQAAAA==.Frostthrower:BAAALgAECgEJAgAAAA==.Fryeguy:BAAALgAECgYJCgAAAA==.',
Fu='Funkysoup:BAAALgADCgYJBgAAAA==.',
Fy='Fyodor:BAAALgAECgIJBQAAAA==.',
['Fè']='Fèresha:BAAALgAECggJEAAAAA==.',
Ga='Gallium:BAAALgAECgYJDgAAAA==.Gazerbeam:BAAALgAECgYJDwAAAA==.',
Ge='Geelock:BAAALgADCggJFgAAAA==.Gehena:BAAALgAFFAIJAgAAAQ==.Gemsareyum:BAAALgAECgYJDgABLgAFFAUJLAAPAP0kAA==.Gesht:BAABLgAECn8YAAIKAAgJSg7rcQBBAQAKAAgJSg7rcQBBAQAAAA==.',
Gh='Ghostfreak:BAAALgADCgYJBgAAAA==.',
Gi='Gidgetz:BAAALgADCgMJAwAAAA==.',
Gl='Glamourkills:BAAALgADCgcJDQAAAA==.',
Go='Goldenbell:BAAALgAECgUJBQAAAA==.Goof:BAABLgAECn81AAIhAAkJ6gyEMwCvAQAhAAkJ6gyEMwCvAQAAAA==.Goontas:BAAALgAECgMJBAAAAA==.',
Gr='Grimsheèper:BAAALgAECgMJBAAAAA==.Grish:BAAALgAECgYJEAAAAA==.Griz:BAAALgAECgQJCAAAAA==.Grollnar:BAAALgAECgEJAQABLgAECgkJDwAEAAAAAA==.Grossevache:BAAALgAECgYJEAAAAA==.Gròws:BAAALgAECgkJBwAAAA==.',
Ha='Haddor:BAABLgAECn8aAAIZAAYJSRmVEQCuAQAZAAYJSRmVEQCuAQAAAA==.Haelexi:BAAALgADCgcJDQAAAA==.Halujoxar:BAAALgADCgcJDgABLgAECggJKQAEAAAAAA==.Hamonkulous:BAAALgADCgcJCAAAAA==.Hankerin:BAAALgADCgcJCAAAAA==.Harandar:BAAALgAECgEJAQAAAA==.Harpomage:BAAALgADCgcJCQAAAA==.Hatcher:BAAALgAECgEJAQAAAA==.Haunter:BAABLgAECn8cAAMOAAYJ4iFmYwDJAQAOAAUJpiJmYwDJAQADAAMJtRtGLQCVAAAAAA==.Hayleigh:BAACLgAFFH8aAAIFAAYJGB33BAApAgAFAAYJGB33BAApAgAuAAQKfy4AAgUACAmgJHUGACQDAAUACAmgJHUGACQDAAAA.',
He='Heimdallr:BAAALgAECgEJAQAAAA==.Heisenborg:BAAALgAECgUJBQAAAA==.Hellbreezy:BAAALgAECgkJEAAAAA==.Helldin:BAABLgAECn8eAAIKAAYJFRNqewAuAQAKAAYJFRNqewAuAQAAAA==.Hellenfeller:BAABLgAECn8WAAIMAAYJEBKWHwAWAQAMAAYJEBKWHwAWAQAAAA==.',
Hi='Hilitepriest:BAABLgAECn8bAAMiAAgJ0Rm+DQA9AgAiAAgJQBm+DQA9AgAXAAIJ1BZvaACLAAAAAA==.Hittomi:BAAALgAECgYJBgAAAA==.',
Ho='Holific:BAABLgAECn8pAAIKAAgJlRPdUwCGAQAKAAgJlRPdUwCGAQAAAA==.Honeychild:BAAALgAECgYJCgAAAA==.Hotrodranger:BAAALgAECgcJEgAAAA==.',
Hu='Huckleberry:BAAALgADCggJDQAAAA==.',
Hv='Hvac:BAABLgAECn8nAAIQAAgJKQyZbQBiAQAQAAgJKQyZbQBiAQAAAA==.',
Ic='Iceovo:BAAALgADCgEJAQAAAA==.Icycritties:BAABLgAECn8VAAIQAAYJhQ0lvQBoAQAQAAYJhQ0lvQBoAQAAAA==.',
Id='Idovoodew:BAAALgADCgUJCAAAAA==.',
Ih='Iheals:BAAALgAECgMJCQAAAA==.',
Im='Imjustadruid:BAAALgADCgUJBAAAAA==.Immortal:BAAALgAECggJCAAAAA==.Implants:BAAALgADCggJCQAAAA==.',
In='Incarnate:BAAALgAECgcJCgAAAA==.Incarnated:BAACLgAFFH8JAAIOAAIJQiQYewBuAAAOAAIJQiQYewBuAAAuAAQKfysAAg4ACQmFIg4JAPMCAA4ACQmFIg4JAPMCAAAA.Inflammation:BAAALgADCgcJDwABLgAECgUJCAAEAAAAAA==.',
Ir='Irocc:BAAALgAECgMJBwAAAA==.',
Is='Ishankyou:BAAALgAECgEJAQAAAA==.Istara:BAAALgADCgcJDQAAAA==.',
Iu='Iu:BAAALgADCgEJAgAAAA==.',
Ja='Jackdowe:BAAALgAECgQJBAAAAA==.Jackfash:BAAALgADCgUJBQAAAA==.Jadecross:BAABLgAECn8VAAIWAAcJyhUMIQCVAQAWAAcJyhUMIQCVAQAAAA==.Jalenhunter:BAAALgADCgUJCAAAAA==.',
Je='Jedith:BAAALgAECgQJBAAAAA==.Jerambae:BAAALgAECgYJEgAAAA==.Jerryatric:BAAALgAECggJDQAAAA==.',
Jo='Joelah:BAAALgAECgcJDwAAAA==.Joshua:BAAALgAECgYJDAAAAA==.',
Ju='Justincasê:BAAALgADCgcJDAAAAA==.',
Ka='Kalfeen:BAAALgAECgUJEgAAAA==.Kallikan:BAABLgAECn8dAAIgAAcJahXFEgBTAQAgAAcJahXFEgBTAQAAAA==.Kanmojo:BAAALgADCgQJBQAAAA==.Kashume:BAAALgAECggJEwAAAA==.Kasteen:BAAALgAECgMJBgAAAA==.Kazon:BAAALgADCgcJCgABLgAFFAQJCAADANYcAA==.Kaøs:BAAALgADCgcJAQAAAA==.',
Kd='Kdoggparker:BAAALgAECgIJAwAAAA==.',
Ke='Kementari:BAAALgAECgQJBQAAAA==.Kenzaki:BAACLgAFFH8NAAIKAAQJ2QknMQAVAQAKAAQJ2QknMQAVAQAuAAQKfzQAAgoACAmFGtA3ANwBAAoACAmFGtA3ANwBAAAA.',
Kh='Khaosreborn:BAAALgAECgUJEAAAAA==.Khaotic:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Ki='Kiiren:BAAALgAECgEJAQABLgAECgUJEgAEAAAAAA==.Kilaaz:BAAALgAECgUJDwAAAA==.Kilaz:BAAALgADCgUJBQAAAA==.',
Kn='Knuts:BAACLgAFFH8GAAIUAAQJBRbQEwA1AQAUAAQJBRbQEwA1AQAuAAQKfxYAAhQACQlUGNsVAMABABQACQlUGNsVAMABAAAA.',
Ko='Korius:BAAALgAECgUJBQAAAA==.Ková:BAAALgAECgYJBgAAAA==.',
Kr='Krutesiq:BAAALgADCgkJCQAAAA==.',
Ku='Kullman:BAAALgADCgYJCgAAAA==.Kungfurry:BAAALgAECgIJAwAAAA==.Kutherrek:BAAALgAECgEJAQAAAA==.Kuubar:BAABLgAECn8hAAIHAAgJ5hMyCACRAQAHAAgJ5hMyCACRAQAAAA==.',
Ky='Kyian:BAAALgAECgMJAwAAAA==.',
La='Ladaeze:BAAALgADCgIJAgAAAA==.Ladiesnutz:BAABLgAECn8UAAQjAAYJiSDTEQBjAQAjAAQJ4R/TEQBjAQAGAAUJ/hSUMQA7AQAeAAMJkBSZEwCHAAAAAA==.Law:BAAALgAECgEJAQABLgAFFAYJGgAFABgdAA==.Laz:BAAALgADCgMJAwAAAA==.Lazerous:BAAALgADCgYJBgAAAA==.',
Le='Lealoo:BAABLgAECn8dAAIKAAcJ+xPaXgBrAQAKAAcJ+xPaXgBrAQABLgAECggJIwAMABURAA==.Leghorn:BAAALgADCgIJAgABLgAECgUJEgAEAAAAAA==.Legolard:BAABLgAECn8XAAIaAAgJbx+GBwBEAgAaAAgJbx+GBwBEAgAAAA==.Lever:BAAALgADCggJCQAAAA==.',
Li='Liath:BAAALgAECgMJBAAAAA==.Lightsky:BAAALgADCgIJAQAAAA==.Lildèbbíe:BAABLgAECn8gAAIQAAgJowtVZQB0AQAQAAgJowtVZQB0AQAAAA==.Lilspoon:BAAALgADCgMJAwAAAA==.Liltrapstarx:BAAALgAECgQJCAAAAA==.Linddori:BAABLgAECn8hAAIKAAgJYhtRMQD1AQAKAAgJYhtRMQD1AQAAAA==.Lindmajik:BAAALgADCgUJBQAAAA==.Liori:BAAALgAECgEJAwAAAA==.Lirillïa:BAAALgADCggJDQABLgAECggJIQAKAGIbAA==.',
Lo='Lodestone:BAAALgADCgMJAwAAAA==.Loena:BAABLgAECn8dAAIKAAkJByMqMQD1AQAKAAkJByMqMQD1AQAAAA==.Lokk:BAAALgAECgQJBAABLgAECgYJDgAEAAAAAA==.',
Lu='Lunabug:BAABLgAECn8oAAIVAAgJfR01EgDiAQAVAAgJfR01EgDiAQAAAA==.Lupinos:BAAALgADCgYJCAAAAA==.',
Ly='Lyadra:BAABLgAECn8ZAAIXAAgJ2hkuIwDMAQAXAAgJ2hkuIwDMAQAAAA==.Lyandre:BAACLgAFFH8JAAIXAAUJhApHCgBGAQAXAAUJhApHCgBGAQAuAAQKfx0AAhcACAlGE4MWACgCABcACAlGE4MWACgCAAAA.Lynna:BAAALgADCgQJBAAAAA==.Lyntoo:BAAALgAECgIJAQAAAA==.Lyntu:BAAALgAECgEJAQAAAA==.',
['Lú']='Lúffy:BAAALgAECgcJBwABLgAECgcJIAALAPkiAA==.',
Ma='Madan:BAAALgAECgYJEgAAAA==.Malasminna:BAAALgADCgYJBgAAAA==.Malehorelock:BAAALgAECgEJAQABLgAECgYJIQAPAG0iAA==.Malicioun:BAAALgADCgEJAQAAAA==.Malkariss:BAABLgAECn8gAAMQAAcJhR47NAAHAgAQAAcJhR47NAAHAgAkAAEJ5AjgHAA5AAAAAA==.Mammadruid:BAABLgAECn8gAAMgAAgJ8AbTIADGAAAgAAgJ8AbTIADGAAAFAAUJcQx2ZwC7AAAAAA==.Maralen:BAAALgADCgcJCQAAAA==.Marann:BAAALgAECgEJAQAAAA==.Matadør:BAAALgAECgcJDAAAAA==.Mathwhiz:BAAALgAECgYJDQABLgAECggJGwANAIQNAA==.Mauldis:BAABLgAECn8fAAIYAAYJmQx5PgDjAAAYAAYJmQx5PgDjAAAAAA==.Mavgard:BAAALgADCgcJCgAAAA==.Mavgards:BAAALgADCgMJAwABLgADCgcJCgAEAAAAAA==.Maxrebo:BAABLgAECn8bAAIUAAgJoBswDQAoAgAUAAgJoBswDQAoAgAAAA==.',
Me='Meatwàd:BAAALgAECgIJAgAAAA==.Mekanzi:BAAALgAECgQJBwAAAA==.Meliõdas:BAAALgAECgUJEQAAAA==.Merebels:BAAALgAECgQJBwABLgAECgYJBgAEAAAAAA==.Merkodisco:BAAALgAECgIJAgAAAA==.',
Mi='Miaka:BAABLgAECn8pAAICAAgJtxYhBgC1AQACAAgJtxYhBgC1AQAAAA==.Miakah:BAAALgAECgUJBQAAAA==.Minirook:BAAALgADCgEJAQABLgAFFAUJFAAOAKwcAA==.Misfire:BAABLgAECn8cAAIPAAgJyw98QACMAQAPAAgJyw98QACMAQAAAA==.Mithygos:BAAALgAECgYJEQAAAA==.Mito:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.',
Mo='Moar:BAAALgAECgEJAgAAAA==.Moghroth:BAABLgAECn8pAAMJAAgJkwkpMgD6AAAJAAcJSwkpMgD6AAAgAAEJQwu7RgAkAAAAAA==.Molykote:BAAALgAECgEJAgAAAA==.Monks:BAAALgAFFAIJAgAAAA==.',
My='Myhiknee:BAAALgADCgMJAwAAAA==.Myriana:BAAALgAECgQJBwAAAA==.Mystyle:BAAALgADCgcJBwAAAA==.',
['Má']='Mágnus:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâsterdon:BAAALgAECgUJCgAAAA==.',
Na='Nahryn:BAABLgAECn8gAAIFAAcJbR+WEwBrAgAFAAcJbR+WEwBrAgAAAA==.Najamei:BAAALgADCgUJBQAAAA==.Najanira:BAAALgADCgYJBgAAAA==.Narya:BAAALgAECgIJAwAAAA==.',
Ne='Nella:BAAALgAECgQJBAABLgAECggJKQAWAEQhAA==.Nerbert:BAAALgADCgYJBgABLgAECggJJQAGAI4VAA==.Neretsym:BAABLgAECn8kAAIPAAgJpx1JHQApAgAPAAgJpx1JHQApAgAAAA==.Nevercumdin:BAAALgADCgEJAwAAAA==.',
Ni='Nibbzz:BAABLgAECn8bAAIiAAgJlhZ8GAC3AQAiAAgJlhZ8GAC3AQAAAA==.Nineva:BAABLgAECn8eAAIFAAcJ6gM0ZwC8AAAFAAcJ6gM0ZwC8AAAAAA==.',
No='Nobas:BAABLgAECn8pAAMJAAgJsghYLQAVAQAJAAgJsghYLQAVAQAFAAEJ6wJ05AAhAAAAAA==.',
Nu='Nugs:BAAALgAECgkJBQAAAA==.',
On='Onlyfeet:BAAALgAECgMJBgAAAA==.',
Op='Oppgjør:BAAALgAECgcJDAAAAA==.',
Or='Oreeree:BAAALgAECgYJBgAAAA==.Orenge:BAAALgAECgQJCAAAAA==.Orkus:BAAALgADCgkJCwAAAA==.Ormr:BAABLgAECn8lAAIGAAgJjhVCHwCPAQAGAAgJjhVCHwCPAQAAAA==.Orpsa:BAAALgADCgYJBgAAAA==.',
Os='Osteo:BAABLgAECn8kAAMNAAgJXgSUegAJAQANAAgJXgSUegAJAQABAAcJCALAPwC1AAAAAA==.',
Ou='Ouron:BAABLgAECn8eAAMcAAgJfBOVMACXAQAcAAcJvROVMACXAQAYAAQJrQxFZACyAAAAAA==.',
Pa='Papashrimps:BAACLgAFFH8QAAIQAAQJBRnIMABUAQAQAAQJBRnIMABUAQAuAAQKfzkAAhAACQl1IggIABQDABAACQl1IggIABQDAAAA.',
Ph='Phrazes:BAAALgAECgQJBAAAAA==.',
Pi='Pikyu:BAAALgADCgEJAQAAAA==.',
Pl='Placeholder:BAABLgAECn8oAAIZAAgJRhoKCAADAgAZAAgJRhoKCAADAgAAAA==.Plaguestingr:BAABLgAECn80AAIPAAkJDiRNAwAtAwAPAAkJDiRNAwAtAwAAAA==.',
Po='Pontifex:BAABLgAECn8cAAIXAAYJ1RtSGgCvAQAXAAYJ1RtSGgCvAQAAAA==.Portandmorph:BAABLgAECn8XAAIQAAcJbBI9agBpAQAQAAcJbBI9agBpAQAAAA==.Potlock:BAAALgAECgMJBwAAAA==.',
Pr='Proey:BAABLgAECn8oAAMIAAgJ/hR9FwC8AQAIAAgJ/hR9FwC8AQAiAAUJJhP8KwAZAQAAAA==.Prone:BAABLgAECn8pAAIcAAgJ2AnPRQA1AQAcAAgJ2AnPRQA1AQAAAA==.',
Ps='Psychokiller:BAAALgADCgYJBgAAAA==.',
Pu='Puf:BAAALgAECgMJBwAAAA==.Pumpidan:BAAALgAECgIJBQAAAA==.',
Py='Pyrelyn:BAAALgADCgEJAQAAAA==.',
Qr='Qròw:BAAALgADCgMJAwAAAA==.',
Ra='Raakotah:BAABLgAECn87AAIJAAkJsSOAAgAeAwAJAAkJsSOAAgAeAwAAAA==.Raelo:BAABLgAECn8dAAIfAAgJxAr0DgBQAQAfAAgJxAr0DgBQAQAAAA==.Raiseurmug:BAABLgAECn8XAAIUAAgJdBD1HwBqAQAUAAgJdBD1HwBqAQAAAA==.Rakash:BAACLgAFFH8IAAIOAAMJiRzQWQCsAAAOAAMJiRzQWQCsAAAuAAQKfyUAAg4ACAknIa0gAL8CAA4ACAknIa0gAL8CAAAA.Rascaldragon:BAAALgAECgQJBQAAAA==.Ravenlark:BAABLgAECn8YAAINAAgJzAYbcAAgAQANAAgJzAYbcAAgAQAAAA==.Ravia:BAABLgAECn8gAAMLAAcJ+SJkGgA1AgALAAcJMiJkGgA1AgARAAUJUiE4CQDdAQAAAA==.Razuki:BAAALgAECgYJDQABLgAECgkJNAAhAIwiAA==.',
Re='Reddale:BAAALgADCgcJDAAAAA==.Redeamer:BAAALgAECgEJAQAAAA==.Resco:BAACLgAFFH8gAAISAAcJbhm/AQDxAQASAAcJbhm/AQDxAQAuAAQKfzYAAhIACQnTJHMGAD8DABIACQnTJHMGAD8DAAAA.Rescotwo:BAAALgAECgYJDgAAAA==.',
Ri='Riddle:BAABLgAECn8YAAIcAAkJcgfWVgDzAAAcAAkJcgfWVgDzAAAAAA==.Rimeouo:BAAALgADCgEJAQAAAA==.Rize:BAAALgAECgMJAwABLgAECggJJAAGAFcLAA==.',
Ro='Rocksolid:BAAALgADCgUJBgAAAA==.Ronnie:BAAALgAECgEJAQAAAA==.Rook:BAACLgAFFH8UAAMOAAUJrBxgLgAAAQAOAAQJrBxgLgAAAQADAAEJAACmPgAAAAAuAAQKfygAAg4ACAmwIikXAPACAA4ACAmwIikXAPACAAAA.Rookmonger:BAAALgAECgUJBQABLgAFFAUJFAAOAKwcAA==.Rosenrott:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.Rosepiercer:BAABLgAECn8lAAIPAAgJQyPMEACDAgAPAAgJQyPMEACDAgAAAA==.Rosies:BAAALgAECgQJBAAAAA==.Rouz:BAABLgAECn8WAAIeAAYJMw+1CwAXAQAeAAYJMw+1CwAXAQAAAA==.',
Ry='Ryenoh:BAAALgADCgYJBgAAAA==.Ryoto:BAACLgAFFH8NAAMGAAQJ6iAvFgA/AQAGAAMJlCQvFgA/AQAeAAIJKRyKCABVAAAuAAQKfxsAAwYACQmEJT8RABECAAYACQmEJT8RABECAB4AAwkXJCMmAPIAAAAA.',
Sa='Sadness:BAAALgADCgYJBwAAAA==.Saetha:BAAALgAECgYJDgAAAA==.Samandean:BAABLgAECn8jAAIMAAgJFRHLFQB3AQAMAAgJFRHLFQB3AQAAAA==.Santhallibar:BAABLgAECn8iAAIlAAgJuwItEADeAAAlAAgJuwItEADeAAAAAA==.Sarasvati:BAABLgAECn8aAAIFAAYJ2B/8HAAXAgAFAAYJ2B/8HAAXAgAAAA==.Saster:BAABLgAECn8cAAIOAAgJ9SDWFQCEAgAOAAgJ9SDWFQCEAgAAAA==.Sathrel:BAAALgADCgIJAgABLgAECgkJBwAEAAAAAA==.',
Sc='Scrabs:BAAALgAECgkJDwAAAA==.',
Se='Sellena:BAABLgAECn8cAAIfAAYJ7RSFEQAlAQAfAAYJ7RSFEQAlAQABLgAECggJIwAMABURAA==.Sementha:BAAALgADCgcJDgABLgAECgYJCQAEAAAAAA==.Senpai:BAABLgAECn8UAAIWAAYJyRxQIQCpAQAWAAYJyRxQIQCpAQABLgAFFAYJGgAFABgdAA==.',
Sh='Shadowmyst:BAAALgADCgQJCgAAAA==.Shaken:BAAALgAECgIJAgAAAA==.Shandow:BAACLgAFFH8PAAIQAAQJjRFEOwBCAQAQAAQJjRFEOwBCAQAuAAQKfzUAAhAACQmLH8cPAMoCABAACQmLH8cPAMoCAAAA.Shango:BAAALgADCgcJCQAAAA==.Shansoracle:BAACLgAFFH8LAAIXAAUJnwmWCgBBAQAXAAUJnwmWCgBBAQAuAAQKfxoAAhcACQmZHZIDAB8DABcACQmZHZIDAB8DAAEuAAUUBAkPABAAjREA.Shed:BAACLgAFFH8HAAIYAAQJ4BjbEQA0AQAYAAQJ4BjbEQA0AQAuAAQKfyYAAhgACAlLIZYNAMgCABgACAlLIZYNAMgCAAAA.Sheislegend:BAAALgAECgUJBgAAAA==.Shelby:BAABLgAECn8oAAIXAAgJwRsWDABbAgAXAAgJwRsWDABbAgAAAA==.Shmoon:BAEALgAECgIJAgABLgAECgMJAwAEAAAAAA==.Shmuckman:BAAALgADCgkJEwAAAA==.Shoty:BAAALgAECgMJAwABLgAFFAUJFAAOAKwcAA==.',
Si='Siccinok:BAABLgAECn8aAAIQAAcJ8xEJegBIAQAQAAcJ8xEJegBIAQAAAA==.Silicá:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Sindorian:BAABLgAECn8hAAMPAAYJbSIRJwAdAgAPAAYJHSIRJwAdAgATAAYJax5JFwCgAQAAAA==.',
Sk='Skrimphorn:BAAALgAECgEJAQAAAA==.',
Sl='Slimped:BAAALgAECgEJAQAAAA==.',
Sm='Smurricane:BAAALgAECgUJCAAAAA==.',
Sn='Snowybato:BAAALgAECgQJBQAAAA==.',
So='Solandor:BAABLgAECn8pAAQaAAkJViAjBACoAgAaAAkJFx4jBACoAgASAAgJ6B3CFwCOAgAmAAMJnRksNgCJAAAAAA==.Solar:BAAALgAECgQJBAAAAA==.Solarial:BAAALgAECgUJDgAAAA==.Solastra:BAABLgAECn8cAAIhAAcJSxmRFgALAgAhAAcJSxmRFgALAgAAAA==.Soramai:BAAALgADCgcJDwAAAA==.Soth:BAABLgAECn8pAAIOAAgJ/hYoRQCuAQAOAAgJ/hYoRQCuAQAAAA==.',
Sp='Sparticusdru:BAAALgAECgcJEQAAAA==.Spore:BAAALgAECgMJAwAAAA==.',
Sq='Sqaw:BAAALgAECgEJAQAAAA==.',
St='Starkadia:BAAALgAECgYJBgAAAA==.Staryxia:BAACLgAFFH8QAAIHAAQJHxfVBAA2AQAHAAQJHxfVBAA2AQAuAAQKfy0AAgcACQmhIUsBAPYCAAcACQmhIUsBAPYCAAAA.Steamdruid:BAAALgAECgYJEAAAAA==.Stonecookies:BAABLgAECn8dAAMNAAgJ+whjZQA4AQANAAgJ7AdjZQA4AQABAAUJ7AYySQCTAAAAAA==.Stonecross:BAAALgAECgYJCgAAAA==.Stoneldo:BAAALgADCgEJAQAAAA==.Stonetotem:BAAALgAECgYJCQAAAA==.Stormbolt:BAABLgAECn8pAAIJAAgJeRKIHACMAQAJAAgJeRKIHACMAQAAAA==.Stormspirit:BAAALgADCggJCAAAAA==.Striggen:BAAALgAECgUJDgAAAA==.',
Su='Succystrazsa:BAAALgADCgIJAgAAAA==.Sugarsham:BAAALgAECgcJCwAAAA==.Sulwen:BAACLgAFFH8UAAIJAAgJRCLvAAA9AgAJAAgJRCLvAAA9AgAuAAQKfyAAAgkACQmQJpEDAPoCAAkACQmQJpEDAPoCAAAA.Sumerset:BAAALgAECgMJBgAAAA==.Supaflytnt:BAAALgAECgUJCAAAAA==.Sustia:BAAALgAECgYJDQAAAA==.',
Ta='Tacopie:BAAALgAECgQJBgAAAA==.Taera:BAABLgAECn8pAAIWAAgJRCGrBgDfAgAWAAgJRCGrBgDfAgAAAA==.Taika:BAAALgADCgkJDwAAAA==.Tailchaser:BAAALgADCgcJBwAAAA==.Talanazar:BAABLgAECn8nAAQGAAgJ8h4wDQBFAgAGAAgJ8h4wDQBFAgAeAAYJgR2AFAChAQAjAAEJqRL6LgA2AAAAAA==.Talavenn:BAAALgAECgcJDQAAAA==.Tallish:BAABLgAECn8dAAILAAgJbQ33egA3AQALAAgJbQ33egA3AQAAAA==.Tarage:BAAALgAECgIJAgAAAA==.Taterchip:BAABLgAECn8cAAISAAYJbBZqMAA+AQASAAYJbBZqMAA+AQAAAA==.Taylia:BAAALgAECgQJBgAAAA==.',
Te='Teaorix:BAAALgADCgQJBAAAAA==.Teds:BAAALgADCgUJBQAAAA==.Temporary:BAAALgADCgYJBgAAAA==.Tempus:BAAALgAECgYJDwAAAA==.Teradoxx:BAAALgAECgYJDgAAAA==.Teriko:BAABLgAECn8tAAMOAAkJFx6tEQCiAgAOAAkJFx6tEQCiAgADAAEJywS2TAAWAAAAAA==.',
Th='Thanks:BAAALgAECgEJAQAAAA==.Thequixote:BAAALgADCgEJAQAAAA==.Therizino:BAAALgADCgQJBAAAAA==.Thrashy:BAAALgAECgQJCAAAAA==.Thrum:BAAALgAECgEJAQAAAA==.',
To='Toxictotes:BAAALgAECgIJAwAAAA==.',
Tw='Twiddleado:BAABLgAECn8lAAIQAAgJsBHIVgCYAQAQAAgJsBHIVgCYAQAAAA==.Twinkie:BAAALgADCgcJBwABLgAECgcJIAALAPkiAA==.Twinkle:BAAALgADCgEJAQAAAA==.',
Ty='Tylor:BAAALgAECgYJDwAAAA==.',
['Tå']='Tåkete:BAAALgAECgYJCwAAAA==.',
Uk='Ukuindadookr:BAAALgADCgYJBgAAAA==.',
Um='Ume:BAAALgAECgEJAQAAAA==.',
Un='Unta:BAAALgAECgYJCQAAAA==.',
Va='Valaera:BAAALgAECgQJBwAAAA==.Valenora:BAABLgAECn8UAAIBAAYJwBteEgC5AQABAAYJwBteEgC5AQAAAA==.Valise:BAAALgAECgYJEgAAAA==.Varielle:BAAALgAECgYJCQAAAA==.Varuz:BAAALgAECgQJBgABLgAECgYJDgAEAAAAAA==.Vaticamt:BAAALgAECgUJBQAAAA==.',
Ve='Vecxx:BAAALgADCgUJBQAAAA==.Velanie:BAAALgAECgcJCwAAAA==.Velanise:BAAALgADCgMJAwAAAA==.Velight:BAAALgADCgEJAQAAAA==.Velinara:BAAALgAECgEJAQAAAA==.Velindroz:BAAALgAECgMJBgAAAA==.Veloras:BAAALgAECgEJAQAAAA==.Verene:BAABLgAECn8aAAIcAAgJfBZAHAAUAgAcAAgJfBZAHAAUAgAAAA==.',
Vi='Viperc:BAAALgADCgMJAwABLgAECgQJDAAEAAAAAA==.Vipul:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Viridria:BAAALgAECgEJAQAAAA==.Virridian:BAABLgAECn8jAAIPAAgJFB9pHAAuAgAPAAgJFB9pHAAuAgAAAA==.Virrigosa:BAAALgADCgcJBwAAAA==.Vistia:BAAALgADCgEJAQAAAA==.',
Vl='Vlado:BAAALgADCgMJAwAAAA==.',
Vo='Vodalus:BAAALgADCgUJBQAAAA==.Voideria:BAAALgAECgQJBgAAAA==.Voolock:BAAALgADCggJCQAAAA==.',
Wa='Wallofshame:BAABLgAECn8cAAIhAAgJIx56EQBBAgAhAAgJIx56EQBBAgAAAA==.Walt:BAAALgADCgIJAgAAAA==.Warchef:BAAALgADCgYJCgABLgAECgcJIAAQAIUeAA==.Warriorclaps:BAAALgADCggJDgAAAA==.Wartooth:BAABLgAECn8gAAMNAAcJLBWUawAqAQANAAUJcBOUawAqAQABAAQJJRTkHgBwAAAAAA==.Wassergott:BAAALgADCgIJAgAAAA==.',
We='Webicus:BAABLgAECn8hAAIaAAgJGxW1EACOAQAaAAgJGxW1EACOAQAAAA==.Wendee:BAABLgAECn8cAAMXAAgJZwFQOwC9AAAXAAgJZwFQOwC9AAAIAAUJdQTkSwCoAAAAAA==.',
Wh='Whitefóx:BAABLgAFFH8GAAIZAAQJygcEBwC8AAAZAAQJygcEBwC8AAABLgAFFAQJDwAQAI0RAA==.Whitley:BAAALgAECggJEgAAAA==.',
Wi='Wijing:BAAALgAECgIJAgAAAA==.',
Wo='Wolololo:BAAALgAECgEJAQABLgAECggJHAAOAPUgAA==.',
Xa='Xanthium:BAAALgAECgYJEgAAAA==.Xanzib:BAAALgADCgYJBgAAAA==.Xaphy:BAAALgAECgYJCwAAAA==.Xardots:BAABLgAECn8lAAIBAAgJohWXBwCKAQABAAgJohWXBwCKAQABLgAECggJKQAEAAAAAA==.',
Xe='Xeetali:BAAALgADCgYJBgAAAA==.',
Xi='Xiareth:BAABLgAECn8gAAIjAAcJagy4EwBDAQAjAAcJagy4EwBDAQAAAA==.',
Xt='Xtronger:BAABLgAECn8fAAIFAAgJmRZYJQDeAQAFAAgJmRZYJQDeAQAAAA==.',
['Xá']='Xároth:BAAALgAECggJKQAAAQ==.',
Ya='Yaddi:BAAALgAECgMJAwAAAA==.Yarrow:BAAALgADCgkJCQAAAA==.',
Ye='Yeeyee:BAAALgAECgkJCgAAAA==.',
Za='Zalik:BAAALgAECgMJAwAAAA==.',
Ze='Zeebo:BAAALgAECgIJAwAAAA==.Zest:BAABLgAECn8pAAMjAAkJ2BCxCQADAgAjAAkJ2BCxCQADAgAGAAIJkAg5XABmAAAAAA==.',
Zm='Zmaryjane:BAAALgAECgIJBAAAAA==.',
Zo='Zorakfoghorn:BAAALgADCgIJAgAAAA==.Zorithic:BAAALgAECgQJAwAAAA==.Zorrak:BAAALgAECgQJBQAAAA==.',
Zu='Zulls:BAAALgAECgIJAgAAAA==.',
Zy='Zyde:BAAALgAECgYJDgAAAA==.',
['Zæ']='Zælys:BAAALgAECgcJCAAAAA==.',
['År']='Årthas:BAAALgADCgEJAQAAAA==.',
['Øa']='Øake:BAAALgAECgEJAQAAAA==.',
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
