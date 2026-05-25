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

local lookup = {'Priest-Shadow','Priest-Discipline','Unknown-Unknown','Mage-Frost','Paladin-Holy','DeathKnight-Blood','Priest-Holy','DemonHunter-Havoc','Monk-Mistweaver','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Hunter-Marksmanship','Shaman-Enhancement','Hunter-BeastMastery','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Arms','Shaman-Restoration','Warrior-Protection','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Vengeance','Druid-Restoration','Druid-Balance','Shaman-Elemental','Rogue-Assassination','Druid-Guardian','Druid-Feral','Monk-Windwalker','Mage-Arcane','Monk-Brewmaster','Hunter-Survival',}
local provider = {region='US',realm="Mok'Nathal",name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaralia:BAABLgAECn8fAAMBAAkJ/BvqEgBfAgABAAgJ6B3qEgBfAgACAAIJBgzOUQBsAAAAAA==.',
Ab='Abovezero:BAAALgADCgYJBgAAAA==.Abyssdark:BAAALgAECgEJAgAAAA==.',
Ac='Achílleus:BAAALgAECgEJAQAAAA==.',
Ad='Adarae:BAAALgAECgcJDQAAAA==.Ademal:BAAALgAECgEJAQAAAA==.Adic:BAAALgAFFAIJAgAAAA==.',
Ae='Aeria:BAAALgAECgEJAgAAAA==.Aerwen:BAAALgAECgYJEQAAAA==.Aeverey:BAAALgADCgcJCgAAAA==.',
Ah='Ahriet:BAAALgADCgMJAwABLgAECgkJEAADAAAAAA==.',
Ak='Akadeus:BAAALgAECgEJAQAAAA==.',
Al='Alarielle:BAAALgAECgQJCAABLgAECggJLQAEAGAVAA==.Alearia:BAAALgADCgEJAQAAAA==.Alewynt:BAAALgAECgEJBQAAAA==.Altiv:BAAALgAECgQJBQAAAA==.Altx:BAAALgAECgEJAgAAAA==.Altzilla:BAAALgAECgIJAwAAAA==.',
Am='Amalthea:BAAALgAECgIJAgAAAA==.Amerihc:BAAALgADCgIJAgAAAA==.Amoral:BAAALgAECgYJDgAAAA==.',
An='Andarick:BAAALgADCgkJDQAAAA==.Antipasta:BAAALgADCgcJFAAAAA==.',
Ap='Apoptosis:BAAALgAECgMJAwAAAA==.',
Ar='Aramist:BAAALgADCgUJBAAAAA==.Arkin:BAAALgAECgkJDwAAAA==.Arkinzor:BAAALgAECgQJBAAAAA==.Arroy:BAAALgADCgEJBAAAAA==.Arîane:BAAALgAECgQJBgAAAA==.',
As='Asapferg:BAAALgAECgcJEAAAAA==.Ashaman:BAABLgAECn8bAAICAAYJxAWrRAC2AAACAAYJxAWrRAC2AAAAAA==.Astanah:BAABLgAECn8cAAIFAAgJ5xSRMAC/AQAFAAgJ5xSRMAC/AQAAAA==.',
Az='Azari:BAAALgAECgQJBAAAAA==.',
Ba='Baneofhorde:BAAALgAECgQJBwAAAA==.Barnigolas:BAAALgADCgMJAwAAAA==.Barricadex:BAAALgADCgcJDAAAAA==.Basatan:BAAALgADCgcJBwABLgAFFAUJDAAGACMVAA==.',
Be='Bearyjane:BAAALgAECgUJBQAAAA==.Beastkraven:BAAALgAECgUJBQAAAA==.',
Bi='Bigspicyd:BAAALgADCgMJAwAAAA==.',
Bl='Blodkuil:BAABLgAECn8WAAIHAAgJjgLwPgDOAAAHAAgJjgLwPgDOAAAAAA==.Bloodedge:BAABLgAECn8lAAIIAAkJtx9ABADdAgAIAAkJtx9ABADdAgAAAA==.',
Bo='Bobbyswagger:BAAALgAFFAIJBAAAAA==.Bolock:BAAALgADCgYJCwAAAA==.Boomchickeñ:BAAALgADCgEJAQAAAA==.',
Br='Braulter:BAAALgAECgYJBwAAAA==.Brentobox:BAABLgAECn8iAAIJAAgJvSAdCQDVAgAJAAgJvSAdCQDVAgAAAA==.Brew:BAAALgAECgMJAwAAAA==.Brooceree:BAAALgAECgYJEAAAAA==.Broomkin:BAAALgADCgMJAwAAAA==.Brother:BAAALgAECgEJAQAAAA==.',
Bu='Bungeholio:BAACLgAFFH8GAAIBAAIJMAPCJwB1AAABAAIJMAPCJwB1AAAuAAQKfx8AAgEACAmhDl00AB4BAAEACAmhDl00AB4BAAEuAAUUAwkDAAMAAAAA.Bunzzlle:BAAALgAFFAMJAwAAAA==.Butterhoof:BAAALgADCgEJAQABLgAFFAUJDAAGACMVAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Cakkes:BAAALgADCgcJBwAAAA==.Caltora:BAAALgAECgMJAwAAAA==.Cannelle:BAABLgAECn8gAAIEAAkJCwgBZwCSAQAEAAkJCwgBZwCSAQAAAA==.Carden:BAABLgAECn8pAAMGAAgJaiIyBgCdAgAGAAgJaiIyBgCdAgAKAAEJzwpzHwE3AAAAAA==.Carimknight:BAAALgAECggJDgAAAA==.Cathraga:BAAALgADCgEJAQAAAA==.',
Ch='Chardh:BAABLgAECn8dAAILAAgJxCR1CwAmAwALAAgJxCR1CwAmAwAAAA==.Charlas:BAAALgADCgUJBQAAAA==.Chesstickle:BAABLgAECn8aAAIKAAgJOgV9lgAVAQAKAAgJOgV9lgAVAQAAAA==.Chillywillie:BAABLgAECn8iAAIMAAgJEBE2KACVAQAMAAgJEBE2KACVAQAAAA==.Chitos:BAAALgAECgYJBgAAAA==.Chosandik:BAAALgAECgcJBwAAAA==.Chrodne:BAAALgAECgQJCwAAAA==.Chromax:BAAALgADCgYJCQAAAA==.Chucknorrîs:BAAALgAECgEJAwAAAA==.',
Ci='Cigam:BAAALgADCgMJAwAAAA==.',
Cl='Clasmind:BAAALgAECgMJBwAAAA==.Cleptodog:BAAALgAECgkJAwAAAA==.Clintbarton:BAAALgAECgYJEAAAAA==.Cloudstrike:BAAALgAFFAIJAwAAAA==.',
Co='Coordination:BAAALgADCggJDQAAAA==.',
Cr='Crend:BAAALgAECgUJCwAAAA==.',
Ct='Cthullu:BAACLgAFFH8MAAIGAAUJIxWjHQC6AAAGAAUJIxWjHQC6AAAuAAQKfxkAAwYACQktHSoJAFgCAAYACQlfHCoJAFgCAAoABQk0HMOaAEsBAAAA.',
['Cø']='Cøldshoulder:BAABLgAECn8dAAIKAAgJQBo4VACkAQAKAAgJQBo4VACkAQAAAA==.',
Da='Dabi:BAAALgAECgQJEAAAAA==.Daemon:BAABLgAECn8VAAILAAgJRhvaLgDsAQALAAgJRhvaLgDsAQAAAA==.Dagore:BAAALgADCgYJBgAAAA==.Dailyalice:BAAALgAECgMJBgAAAA==.Danglinwang:BAAALgADCgEJAQAAAA==.Dankwoods:BAAALgAECgUJCQAAAA==.Darcmatter:BAABLgAECn86AAQNAAkJfB0WFACXAgANAAkJfB0WFACXAgAOAAQJXxLYKAAfAQAPAAEJshlRLgA7AAAAAA==.Darkemperor:BAAALgADCgEJAQABLgAECgEJAgADAAAAAA==.Dayday:BAAALgAECgIJAgABLgAECggJHQAQAD4ZAA==.',
De='Deathsend:BAABLgAECn8gAAIKAAcJkAUGpwD5AAAKAAcJkAUGpwD5AAAAAA==.Decamoose:BAABLgAECn8fAAIRAAkJyBLnBwDfAQARAAkJyBLnBwDfAQAAAA==.Deeboogie:BAAALgAECgQJBAAAAA==.Deepsicks:BAABLgAFFH8FAAISAAIJcgysDACRAAASAAIJcgysDACRAAAAAA==.Deepstate:BAAALgAECgIJAgAAAA==.Deidamia:BAAALgAECgEJAgAAAA==.Deimosz:BAAALgAECgcJEAABLgAFFAQJDwAJAI8XAA==.Demonaholio:BAAALgAECgEJAQABLgAFFAMJAwADAAAAAA==.Demonicade:BAABLgAECn8eAAMNAAgJQgs4cgBAAQANAAcJQgs4cgBAAQAOAAEJAABmdQAvAAAAAA==.Demonäde:BAAALgADCgYJBgAAAA==.Desaint:BAAALgAECgQJBAAAAA==.Devana:BAAALgADCgMJAwAAAA==.',
Di='Dima:BAABLgAECn86AAITAAkJbiCWCwDTAgATAAkJbiCWCwDTAgAAAA==.Dingler:BAAALgAECgUJBAAAAA==.Dithy:BAAALgAECgUJDAAAAA==.',
Dn='Dne:BAABLgAECn8kAAIKAAgJxQ98YgDMAQAKAAgJxQ98YgDMAQAAAA==.',
Do='Donavon:BAACLgAFFH8GAAIFAAMJhRwVJgDEAAAFAAMJhRwVJgDEAAAuAAQKfzsAAwUACQkCIQYFACQDAAUACQkCIQYFACQDABQACAngHYAGAFMCAAAA.Dornnbryda:BAAALgAECggJEAAAAA==.',
Dp='Dpuncher:BAAALgADCgUJBQAAAA==.',
Dr='Drackothyr:BAABLgAECn8sAAQVAAgJPyAKBgDOAQAWAAgJ1hx7FQAOAgAVAAYJhyIKBgDOAQAXAAYJuAVLHgDgAAAAAA==.Drecarus:BAABLgAECn8UAAMFAAkJ7hLlQwBoAQAFAAkJ7hLlQwBoAQAQAAQJeghm/ACOAAAAAA==.Drgoodvibes:BAAALgADCgYJBgABLgAFFAUJDAAGACMVAA==.',
Du='Duudeimalock:BAAALgADCgYJBgAAAA==.',
Dw='Dwalk:BAAALgAECgkJAgAAAA==.',
Ec='Echidna:BAAALgADCgkJFgAAAA==.',
Eg='Egosnipe:BAAALgADCgEJAQAAAA==.',
El='Elamshinae:BAAALgAECgcJJQAAAQ==.Elementalor:BAAALgAECgQJBAAAAA==.Elizaf:BAAALgAECgEJAQAAAA==.Elizarothgol:BAAALgADCgcJBwAAAA==.Elyia:BAAALgADCgMJAwAAAA==.',
En='Entchen:BAAALgAECgIJAgABLgAECgYJCwADAAAAAA==.',
Ep='Eppey:BAAALgAECgMJAwAAAA==.',
Er='Erragorn:BAABLgAECn8iAAMMAAgJzheqGgD0AQAMAAgJzReqGgD0AQAYAAEJYwKJbgAOAAAAAA==.',
Es='Estinzione:BAAALgADCgYJBgAAAA==.',
Ex='Exalitor:BAAALgADCgYJEgAAAA==.',
Ey='Eyeguy:BAABLgAECn8VAAMIAAkJfARmQQD0AAAIAAkJfARmQQD0AAALAAMJHgH62AA+AAAAAA==.',
['Eö']='Eöath:BAAALgAECgcJDwAAAA==.',
Fa='Falaurenta:BAAALgAECgYJDAAAAA==.',
Fe='Fea:BAAALgADCgEJAQAAAA==.Feidao:BAAALgADCgcJDAAAAA==.Feltank:BAAALgAECgUJBgABLgAFFAUJDAAGACMVAA==.',
Fr='Francesca:BAAALgAECgIJAwAAAA==.Franck:BAAALgAECgQJCwAAAA==.Frazierr:BAAALgAECgEJAQAAAA==.Freedessert:BAAALgAECgUJBgAAAA==.',
Fu='Fuuke:BAABLgAECn8bAAIBAAgJcw8AJgBzAQABAAgJcw8AJgBzAQAAAA==.',
Ga='Gailinn:BAAALgAECgQJCAAAAA==.Galreth:BAAALgAECgUJCgAAAA==.Ganon:BAABLgAECn8hAAQNAAgJmSH2EwCYAgANAAgJmSH2EwCYAgAOAAIJChIsVAByAAAPAAEJHRkmKQBNAAAAAA==.',
Go='Gozebo:BAAALgADCgMJBAAAAA==.',
Gr='Greggdshami:BAABLgAECn8oAAIZAAkJzBmRFgBpAgAZAAkJzBmRFgBpAgAAAA==.Gresh:BAAALgADCgYJBgAAAA==.Gretagobbo:BAAALgAECgYJDQABLgAFFAQJDwAJAI8XAA==.Grimmlockk:BAABLgAECn8fAAINAAcJZxvGMgD1AQANAAcJZxvGMgD1AQABLgAFFAcJGAALAHscAA==.Grimroc:BAAALgADCgQJBAAAAA==.Grunbeld:BAAALgAECgQJBAAAAA==.',
Gu='Gunblade:BAABLgAECn8vAAIaAAgJPA+xGABQAQAaAAgJPA+xGABQAQAAAA==.Gundin:BAAALgADCgYJBgAAAA==.Gurney:BAAALgADCggJDwABLgADCgkJGAADAAAAAA==.',
['Gü']='Güenhwyvar:BAAALgAECgEJAQAAAA==.',
Ha='Hailprincess:BAAALgAECgMJAwAAAA==.Hanuufalem:BAAALgAECgYJDAAAAA==.Hassad:BAAALgADCgcJDQAAAA==.',
He='Healaton:BAAALgAECgkJEAAAAA==.Healmonger:BAACLgAFFH8JAAMHAAMJwwfPGwCsAAACAAMJZQKjKQCtAAAHAAMJwwfPGwCsAAAuAAQKfysABAcACQnmFIMSACMCAAcACQnmFIMSACMCAAEABglsB9xBAN0AAAIAAgmwCTJUAGEAAAAA.Healpants:BAAALgAECgcJBgAAAA==.Heruin:BAABLgAFFH8HAAMKAAMJ7g/agADSAAAKAAMJ7g/agADSAAAbAAEJGgOXGgA+AAAAAA==.',
Hi='Hilgasmic:BAAALgAFFAEJAQAAAA==.',
Ho='Hohenhaim:BAABLgAECn8YAAMGAAkJ5Q8IIwAMAQAGAAkJ5Q8IIwAMAQAKAAEJTwURUgEkAAAAAA==.Holly:BAAALgAECggJEAAAAA==.Holykal:BAEBLgAECn8kAAIQAAgJ/B/+IgBaAgAQAAgJ/B/+IgBaAgAAAA==.Hope:BAAALgADCgYJBgABLgAECggJDAADAAAAAA==.Horse:BAACLgAFFH8rAAIHAAcJCAMrBwCdAQAHAAcJCAMrBwCdAQAuAAQKfz8AAgcACQneFz0QAEACAAcACQneFz0QAEACAAAA.',
Ib='Ibelurkin:BAAALgAECgYJBgAAAA==.',
Ic='Icu:BAAALgAFFAIJAgAAAA==.',
Ih='Ihasabukkit:BAAALgAECgEJAQABLgAECgUJBQADAAAAAA==.Ihunt:BAAALgADCgIJAwAAAA==.',
In='Indominus:BAAALgAECgMJAwAAAA==.',
Ja='Jabachi:BAAALgAECgQJCwAAAA==.Jarixx:BAAALgAECgQJBQAAAA==.Jaydubz:BAAALgADCgMJAwAAAA==.Jaysashi:BAABLgAECn8jAAIcAAkJ7hzNBQCyAgAcAAkJ7hzNBQCyAgAAAA==.',
Ji='Jigsaww:BAAALgADCgYJBgAAAA==.',
Ju='Jun:BAACLgAFFH8iAAMLAAcJ+CQABAB1AgALAAcJ+CQABAB1AgAIAAIJ+h7kEwC2AAAuAAQKfzwAAwsACQmhJf4CAEkDAAsACQmhJf4CAEkDAAgABwmMJE4JAM0CAAAA.Justdruid:BAAALgADCgMJAwAAAA==.Juum:BAAALgADCgIJAgAAAA==.',
Ka='Kahla:BAAALgAECgEJAQAAAA==.Kaho:BAAALgAECgQJCQAAAA==.Karkas:BAAALgAECgYJEAAAAA==.Kass:BAAALgADCgMJAwAAAA==.Kasumaus:BAABLgAECn8kAAMKAAkJKQpPdgBRAQAKAAgJ6glPdgBRAQAbAAMJUgu4HgCFAAAAAA==.Kateera:BAAALgAECgYJCQABLgAECgkJLgAaAIEbAA==.Kayroonrangi:BAAALgAECgEJAgAAAA==.',
Ke='Kearyn:BAABLgAECn8uAAMaAAkJgRtdBgCEAgAaAAkJgRtdBgCEAgAMAAQJIgqXVwDDAAAAAA==.Keifrene:BAAALgADCgcJCwAAAA==.Keldra:BAAALgAECgcJDgAAAA==.Kelnis:BAAALgAECgQJDAAAAA==.Kelp:BAAALgADCgkJGgABLgAECgkJOQALAAElAA==.Kevrad:BAAALgADCgcJCAAAAA==.',
Kh='Khephris:BAABLgAECn8tAAIEAAgJYBUIVQDAAQAEAAgJYBUIVQDAAQAAAA==.',
Ki='Kilin:BAAALgADCgEJAQAAAA==.Kiralni:BAAALgAECgEJAQAAAA==.Kiramdh:BAAALgADCgMJAwAAAA==.',
Kn='Knivex:BAABLgAECn83AAIEAAkJxCHQDwDlAgAEAAkJxCHQDwDlAgAAAA==.',
Ko='Koani:BAAALgADCgEJAgAAAA==.',
Kr='Krazyplaya:BAAALgADCgEJAQAAAA==.',
La='Laceddoob:BAAALgADCgYJBgAAAA==.Lahra:BAAALgAECgIJAgAAAA==.Lalatina:BAAALgAECgEJAQAAAA==.Lambo:BAAALgAECgcJDwAAAA==.Landris:BAAALgADCgkJCQAAAA==.Lanel:BAAALgADCgUJBQAAAA==.Lanners:BAAALgAECgQJBwAAAA==.Lazermoose:BAAALgAECgYJDgAAAA==.Lazuleon:BAAALgAECgcJBwAAAA==.',
Le='Leap:BAACLgAFFH8JAAIdAAMJWAq8BwCVAAAdAAMJWAq8BwCVAAAuAAQKfx8AAh0ACQl/FHoHAN4BAB0ACQl/FHoHAN4BAAAA.Leonîdas:BAAALgAECgIJAgAAAA==.',
Lf='Lfwowgf:BAAALgAECgcJBwAAAA==.',
Li='Lightbläster:BAAALgAECgYJCgAAAA==.Lightrider:BAAALgAECgUJBQAAAA==.Lionroar:BAACLgAFFH8dAAIeAAYJlxnhCwDgAQAeAAYJlxnhCwDgAQAuAAQKfy0AAx4ACAlhIXkSAKICAB4ACAlhIXkSAKICAB8ABgnqFUA1AGkBAAAA.',
Ll='Llaothtaed:BAAALgAECgkJDwAAAA==.',
Lo='Locktard:BAAALgAECgYJCQAAAA==.Lokalock:BAAALgADCggJCgABLgAECgkJJgASAM8ZAA==.Lorellei:BAABLgAECn8fAAIHAAgJugyQKQBWAQAHAAgJugyQKQBWAQAAAA==.Lothgow:BAAALgAECgUJCAAAAA==.Lourdes:BAABLgAECn8ZAAIEAAgJhgKHvQDwAAAEAAgJhgKHvQDwAAAAAA==.',
Lu='Luxus:BAAALgADCggJEAAAAA==.',
Lv='Lvispriestly:BAAALgAECgQJBAAAAA==.',
['Lì']='Lìnk:BAAALgADCgIJAwABLgAFFAUJDAAGACMVAA==.',
Ma='Magchro:BAAALgADCgIJAwAAAA==.Maggzz:BAAALgAECgEJAwAAAA==.Magîcpin:BAAALgAECgEJAQAAAA==.Malefiroar:BAAALgADCgUJCAAAAA==.Manticor:BAAALgAECgEJAQAAAA==.Matteas:BAABLgAECn8yAAIQAAkJciNWBgAmAwAQAAkJciNWBgAmAwAAAA==.May:BAAALgAECgMJAQAAAA==.',
Me='Mebbe:BAAALgADCgIJAgAAAA==.Mediumtit:BAAALgADCgIJAgAAAA==.Mew:BAAALgADCgUJBQAAAA==.Mewchi:BAAALgAECgEJAQABLgAECgcJHAAFAHYdAA==.Mewzi:BAAALgAECgUJCwAAAA==.',
Mi='Miah:BAABLgAECn8nAAIRAAYJ5Br5DABoAQARAAYJ5Br5DABoAQAAAA==.Miip:BAAALgADCgYJCgAAAA==.Mikelock:BAAALgADCgEJAQABLgAFFAEJAgADAAAAAA==.Milkmissile:BAAALgADCgkJFgAAAA==.Milkyflower:BAAALgAECgcJEwAAAA==.Mindbender:BAAALgADCgEJAQABLgAECgcJDgADAAAAAA==.',
Mo='Mograins:BAABLgAECn88AAMNAAkJ+h3FGQBwAgANAAcJfR7FGQBwAgAOAAIJZRp/QwCnAAAAAA==.Monzcarro:BAAALgAECgYJCgAAAA==.Morgainne:BAAALgAECgUJDAAAAA==.Morpho:BAAALgAECgkJCAAAAA==.Mortmor:BAAALgADCgkJCQAAAA==.',
Ms='Mstrsinister:BAAALgADCgcJBwAAAA==.',
Mu='Muffinn:BAABLgAECn8cAAITAAkJBAkDYgBUAQATAAkJBAkDYgBUAQAAAA==.Mugvinx:BAAALgAECgEJAQAAAA==.Munti:BAAALgAECgkJCAAAAA==.',
My='Myko:BAAALgAECgkJEwAAAA==.Mymdos:BAAALgAECgcJDQABLgABCgMJAwADAAAAAA==.',
['Mä']='Mästérdòn:BAAALgADCgQJCAAAAA==.',
['Må']='Måsterdon:BAABLgAECn8VAAIUAAgJTg88FABbAQAUAAgJTg88FABbAQAAAA==.Måstërdön:BAAALgADCgQJBAAAAA==.',
Na='Nala:BAACLgAFFH8LAAIMAAMJbxqwIwDvAAAMAAMJbxqwIwDvAAAuAAQKfyQAAgwACQmvIScJALACAAwACQmvIScJALACAAAA.',
Ne='Nerc:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Nercos:BAAALgADCgYJBgAAAA==.Neverborn:BAABLgAECn8UAAQHAAcJ6xQULABFAQAHAAcJ6xQULABFAQACAAIJhwRqUQBGAAABAAEJYQPbaAAnAAAAAA==.',
Ni='Niame:BAABLgAECn8eAAIgAAYJ+xNhOAAlAQAgAAYJ+xNhOAAlAQAAAA==.Nitraina:BAAALgAECgUJCQAAAA==.Niyabelle:BAABLgAECn8kAAMcAAcJ2RvUGACrAQAcAAcJVhnUGACrAQAhAAYJ9RfgCwBNAQAAAA==.',
No='Noether:BAAALgAECggJDwAAAA==.Nolimitation:BAAALgAECgEJAQAAAA==.',
Ny='Nybrax:BAAALgADCgYJBgAAAA==.Nyomi:BAAALgADCgQJBAAAAA==.',
Oa='Oakmane:BAABLgAECn8VAAMiAAcJYxMCHAAqAQAiAAYJZhUCHAAqAQAjAAUJFwg0MgBYAAAAAA==.',
Ok='Okamí:BAAALgADCgUJBQABLgAECggJDAADAAAAAA==.Okinawa:BAAALgAECgEJAgAAAA==.',
Ol='Oleevia:BAABLgAECn8jAAIBAAkJlBbqEwALAgABAAkJlBbqEwALAgAAAA==.',
On='Onrangi:BAAALgADCgIJAgAAAA==.',
Or='Oralis:BAAALgADCgUJBQAAAA==.Oraxia:BAAALgAECgEJAQABLgAFFAQJDwAJAI8XAA==.Oreiel:BAAALgAECgEJAQAAAA==.Orgdh:BAACLgAFFH8oAAILAAcJuhnKDADuAQALAAcJuhnKDADuAQAuAAQKfzYAAgsACQliId4MAMQCAAsACQliId4MAMQCAAAA.Orgdynamite:BAAALgAECgUJCAAAAA==.',
Oz='Ozzynäter:BAAALgADCgEJAQAAAA==.',
Pa='Paedragon:BAAALgAECgUJDAAAAA==.Paladareian:BAABLgAECn8uAAMFAAkJzh+pBQAXAwAFAAkJzh+pBQAXAwAQAAEJJQWTdQEpAAAAAA==.Palm:BAAALgAECgEJAQABLgAFFAMJCwAMAG8aAA==.Pandalin:BAABLgAECn8WAAIZAAcJMxB9RQBlAQAZAAcJMxB9RQBlAQABLgAECggJDAADAAAAAA==.',
Pe='Pejbolt:BAAALgAFFAEJAQABLgAFFAcJIgALAPgkAA==.Pennywiseit:BAAALgAECgYJBwAAAA==.Percwalker:BAAALgAECgcJDQAAAA==.',
Ph='Phenomenon:BAAALgAECggJDgAAAA==.',
Pi='Pinheadd:BAAALgAECgUJDAAAAA==.Pink:BAAALgADCgYJCgAAAA==.',
Pm='Pmsm:BAAALgAECgQJCAAAAA==.',
Po='Powerslavé:BAABLgAECn8cAAQaAAcJShznEACxAQAaAAcJXBrnEACxAQAYAAYJdBtrGQBkAQAMAAEJgg5RigAyAAABLgAFFAQJDAAEAO4XAA==.',
Pr='Priestitoot:BAAALgAECgcJEgAAAA==.',
Pu='Puffpuffpass:BAAALgAECgEJAgAAAA==.Pumkinhead:BAAALgAECgMJBAAAAA==.',
Qu='Quadzilla:BAAALgAECgEJAQAAAA==.Qudenos:BAAALgAECggJDAAAAA==.',
['Qû']='Qûeenpin:BAAALgADCgEJAQAAAA==.',
Ra='Ragous:BAAALgAECgYJEgAAAA==.Raiden:BAABLgAECn8gAAIQAAgJ2wo8egBZAQAQAAgJ2wo8egBZAQAAAA==.Ralister:BAAALgAECgIJAgAAAA==.Rathis:BAAALgADCgUJBgAAAA==.Ravenkiss:BAAALgAECgMJAwAAAA==.',
Re='Reazzecxan:BAAALgAECgMJAwAAAA==.Reeses:BAAALgADCgYJBgAAAA==.Renniel:BAAALgAECgcJDQAAAA==.Retropâlly:BAAALgAECgIJAgAAAA==.Revoker:BAAALgADCgcJFQABLgAECggJDAADAAAAAA==.Rexarg:BAAALgAECgYJDgAAAA==.',
Rh='Rhysänd:BAAALgAECgQJBwAAAA==.',
Ri='Rielz:BAAALgAECgEJAQAAAA==.',
Ro='Rockbitér:BAAALgAECgMJAwABLgAFFAQJDwAJAI8XAA==.Rockbìter:BAACLgAFFH8PAAIJAAQJjxeKGQAtAQAJAAQJjxeKGQAtAQAuAAQKfxgAAwkACAnOH/MLAJMCAAkACAnOH/MLAJMCACQAAQkAADGgAAAAAAAA.Rockthyr:BAAALgAECgQJBQABLgAFFAQJDwAJAI8XAA==.Rockzi:BAAALgAECgcJBwABLgAFFAQJDwAJAI8XAA==.Rojas:BAABLgAECn8ZAAIEAAcJFQY3rgAJAQAEAAcJFQY3rgAJAQAAAA==.',
['Ré']='Réåper:BAABLgAECn8aAAIQAAgJuxCOcABtAQAQAAgJuxCOcABtAQAAAA==.',
['Rö']='Römana:BAABLgAECn8oAAITAAgJ6w60UQB/AQATAAgJ6w60UQB/AQAAAA==.',
Sa='Saaran:BAAALgAECggJDAAAAA==.Sandoriel:BAAALgADCgkJGwAAAA==.Sapmedaddy:BAAALgAECgEJAgABLgAECgUJBQADAAAAAA==.Sathenasand:BAAALgAECgYJEgABLgAFFAQJDwAKANESAA==.',
Sc='Scamps:BAAALgAECgEJAQAAAA==.Scarellia:BAAALgAECgUJDQAAAA==.Scarly:BAAALgAECgEJAQAAAA==.Scorch:BAABLgAECn86AAIEAAkJEyLfCAAgAwAEAAkJEyLfCAAgAwAAAA==.',
Sh='Shadowkirby:BAAALgADCgUJBQAAAA==.Shadowkushh:BAAALgAECgYJEgAAAA==.Shamwowolio:BAAALgAECgUJBgABLgAFFAMJAwADAAAAAA==.Shatterfrost:BAABLgAECn8oAAMlAAYJ+RqGCgA1AQAEAAYJABnyfwBbAQAlAAUJIBOGCgA1AQAAAA==.Shayd:BAAALgAECggJDAAAAA==.Shiggles:BAAALgAECgQJBAABLgAECgcJDAADAAAAAA==.Shirraz:BAAALgAECgEJAQAAAA==.',
Si='Sicksdeep:BAACLgAFFH8LAAMYAAMJtQiIHAC4AAAYAAMJOwiIHAC4AAAMAAIJXgVNQABEAAAuAAQKfx0AAxgACAndFvgJAAoCABgACAndFvgJAAoCAAwABQltCZ1sAAQBAAAA.Silverpaws:BAAALgADCgQJBAAAAA==.Silverstorm:BAABLgAECn8VAAITAAYJoA7ndgAjAQATAAYJoA7ndgAjAQAAAA==.Sister:BAAALgAECgEJAQAAAA==.',
Sk='Skelmirson:BAAALgAECgYJCwAAAA==.Skewpin:BAAALgADCgQJBAAAAA==.Skoomauser:BAAALgAECgQJBAAAAA==.Skÿe:BAABLgAECn83AAIRAAkJniJKAQD/AgARAAkJniJKAQD/AgAAAA==.',
Sl='Slamma:BAACLgAFFH8nAAIMAAcJYCGzAABtAgAMAAcJYCGzAABtAgAuAAQKf0EAAwwACQnCJjUAAPgDAAwACQnCJjUAAPgDABgAAQn9JbhHAHAAAAAA.Slammahd:BAAALgAECgkJCwABLgAFFAcJJwAMAGAhAA==.Slicedbread:BAACLgAFFH8XAAIJAAcJahPECgDlAQAJAAcJahPECgDlAQAuAAQKfyQABAkACQnqHCIQAG4CAAkACAl7HSIQAG4CACYABgkNIfojAGwBACQAAQniF7x2AD8AAAEuAAUUBgkUAAUA/BwA.',
Sm='Smokadaganga:BAAALgAFFAIJAgAAAA==.',
Sn='Snoball:BAAALgAECgIJAwAAAA==.',
So='Solarean:BAAALgADCgQJBwAAAA==.Solidarity:BAAALgAECgYJDAAAAA==.Sols:BAACLgAFFH8MAAIEAAQJ7hfFOwBLAQAEAAQJ7hfFOwBLAQAuAAQKfycAAgQACQkHHyIPAOoCAAQACQkHHyIPAOoCAAAA.Sorceroar:BAAALgADCgYJCQAAAA==.Sowet:BAAALgAECgQJBAAAAA==.',
Sp='Sparcyy:BAAALgADCgYJBgAAAA==.Spatula:BAAALgAECgUJEAAAAA==.Speoghii:BAAALgAECgYJEgAAAA==.Spiffjbug:BAAALgADCggJGwAAAA==.Spifftreebug:BAAALgAECgcJEQAAAA==.',
St='Starhoof:BAAALgADCgcJDQAAAA==.Starshine:BAAALgAECgMJAwAAAA==.Steelerschic:BAABLgAECn8WAAIgAAYJ5QMAWwCjAAAgAAYJ5QMAWwCjAAAAAA==.Stillfrazier:BAABLgAECn8eAAQBAAgJMAppLABKAQABAAgJMAppLABKAQACAAcJ4QofNQD7AAAHAAIJdQQldQBVAAAAAA==.Stormleader:BAAALgADCgcJCAAAAA==.',
Su='Subcintus:BAAALgAECgcJDQAAAA==.Subterfuge:BAAALgAECgEJAQAAAA==.Surge:BAAALgAECgUJCAAAAA==.',
Sv='Svarog:BAAALgAECgYJEAABLgAFFAMJCwAMAG8aAA==.',
['Sö']='Söphie:BAAALgAECgkJDwAAAA==.',
Ta='Tainema:BAABLgAECn8dAAIQAAYJPhlWbgByAQAQAAYJPhlWbgByAQAAAA==.Talangi:BAAALgAECgkJBwAAAA==.Tallow:BAAALgADCgQJBAAAAA==.Tarheelpally:BAAALgAECgkJCQAAAA==.Taurriel:BAABLgAECn8mAAITAAkJzB3lGABoAgATAAkJzB3lGABoAgAAAA==.Tazzm:BAAALgAECgYJBgAAAA==.',
Te='Teranok:BAABLgAECn8gAAIkAAkJuSCtBgDAAgAkAAkJuSCtBgDAAgAAAA==.Terozon:BAAALgAECgYJCwAAAA==.',
Th='Tharianrex:BAABLgAECn8vAAMSAAkJ6CTcAAA0AwASAAkJ6CTcAAA0AwAZAAEJMgIIxwAdAAAAAA==.Theacused:BAAALgAECgQJCAAAAA==.Thedreadwolf:BAAALgAECgMJAwAAAA==.Them:BAAALgAECggJEwAAAA==.Thisguy:BAAALgADCgQJBAABLgAECggJHQAQAD4ZAA==.Thoir:BAACLgAFFH8rAAIZAAcJfB4jAQD/AQAZAAcJfB4jAQD/AQAuAAQKf0AAAhkACQl3JPwAAJgDABkACQl3JPwAAJgDAAEuAAUUBwkrAAcACAMA.Thorodinson:BAAALgADCgYJBgAAAA==.Thyrus:BAAALgADCgcJBwAAAA==.',
Ti='Tiaeda:BAAALgAECgEJAQAAAA==.Tickells:BAABLgAECn8yAAMCAAkJdAkZHwCmAQACAAkJdAkZHwCmAQABAAkJIg1UHwCjAQAAAA==.Tipsylorcet:BAABLgAECn8nAAImAAgJuxs6EgAFAgAmAAgJuxs6EgAFAgAAAA==.Tirohunt:BAAALgAECgYJCwAAAA==.',
Tk='Tkbear:BAAALgADCgUJBAAAAA==.',
Tr='Tricktìckler:BAAALgAECgUJDAAAAA==.Trinestia:BAAALgADCgUJDQAAAA==.Truggrug:BAAALgADCgEJAQAAAA==.Truthstrike:BAAALgADCgEJAQAAAA==.Trvll:BAAALgADCgEJAQAAAA==.',
Tu='Tubylumpkins:BAAALgAECggJEgAAAA==.Tulay:BAAALgADCgQJBAABLgADCggJFAADAAAAAA==.Turiell:BAAALgAECgQJCAAAAA==.',
Ty='Tybird:BAABLgAECn8hAAIbAAgJDyOABABEAgAbAAgJDyOABABEAgAAAA==.Tyllimath:BAAALgADCgEJAQABLgAECggJHAAFAOcUAA==.',
['Tø']='Tøuchmeeh:BAAALgAECgkJDQAAAA==.',
Uf='Ufug:BAAALgADCgEJAQAAAA==.',
Ul='Ulsull:BAAALgADCgkJGAAAAA==.Ultima:BAAALgADCgkJEwAAAA==.Ulymage:BAAALgADCgUJBQABLgAFFAcJKwABAI4iAA==.Ulyssi:BAACLgAFFH8rAAIBAAcJjiLMAQBZAgABAAcJjiLMAQBZAgAuAAQKfz8AAgEACQmZJR0CAD8DAAEACQmZJR0CAD8DAAAA.',
['Uñ']='Uñàble:BAAALgADCgcJBwAAAA==.',
Va='Vadazzle:BAAALgADCgEJAQAAAA==.Valethara:BAAALgAECgUJBQAAAA==.Valkyrr:BAAALgAECgcJDgAAAA==.Valthorin:BAAALgADCgUJCAAAAA==.Vandagylon:BAAALgADCgcJCwAAAA==.Vaniillalate:BAAALgADCgUJCAAAAA==.',
Ve='Velanir:BAAALgAECgQJBQAAAA==.Velkron:BAAALgAECgYJCQAAAA==.Ven:BAABLgAECn8rAAIBAAgJVAjXLgA8AQABAAgJVAjXLgA8AQAAAA==.Venturecap:BAAALgAFFAEJAgAAAA==.Verxina:BAABLgAECn8dAAInAAgJTCIGDQA6AgAnAAgJTCIGDQA6AgAAAA==.',
Vi='Viltrumite:BAAALgAECgkJDAAAAA==.',
Vl='Vlayne:BAAALgADCgMJAwAAAA==.',
Vo='Voidedkushh:BAAALgAECgYJDgAAAA==.Vondeuce:BAAALgADCgYJBgABLgAECgYJEgADAAAAAA==.Voroq:BAAALgAECgIJBQAAAA==.',
Vu='Vullrog:BAABLgAECn8mAAIRAAgJfhZyDQBfAQARAAgJfhZyDQBfAQAAAA==.',
Wa='Wankstar:BAAALgAECgUJBQAAAA==.Warvein:BAAALgAECgEJAQAAAA==.',
We='Weehunt:BAABLgAECn8bAAITAAgJXxokNQDeAQATAAgJXxokNQDeAQAAAA==.',
Wh='Whez:BAAALgAECgUJBgAAAA==.',
Wi='Wicka:BAABLgAECn82AAIZAAgJwiTXBQAuAwAZAAgJwiTXBQAuAwAAAA==.Widowfang:BAAALgAECgYJCwAAAA==.Wikka:BAAALgAECgYJEQAAAA==.Wildriver:BAABLgAECn8mAAIeAAgJUx8LDgDJAgAeAAgJUx8LDgDJAgAAAA==.',
Xa='Xaehyun:BAACLgAFFH8rAAMkAAcJtSQ0AQAsAgAkAAUJvCU0AQAsAgAJAAIJyiQVJQDLAAAuAAQKf0MAAyQACQnQJhAAAAoEACQACQnQJhAAAAoEAAkABQlEHVEhAKkBAAAA.Xalley:BAAALgADCgQJBAAAAA==.Xandrelar:BAABLgAECn8cAAQdAAYJiiBRCQCrAQAdAAUJiiBRCQCrAQAIAAUJhB0sKgBzAQALAAQJoRKwmwDhAAABLgAECggJDAADAAAAAA==.Xanni:BAABLgAECn8zAAMgAAgJoAzWMwA9AQAgAAgJoAzWMwA9AQAZAAMJkQN7iQBuAAAAAA==.',
Xe='Xellorr:BAAALgAECgYJDAAAAA==.',
Xm='Xmrpdk:BAACLgAFFH8rAAIGAAcJGyACAwAkAgAGAAcJGyACAwAkAgAuAAQKfz8AAgYACQkFI+wCADYDAAYACQkFI+wCADYDAAAA.Xmrpdruid:BAAALgAECgMJAQABLgAFFAcJKwAGABsgAA==.Xmrpmonk:BAAALgAECgcJEgABLgAFFAcJKwAGABsgAA==.',
Xo='Xohan:BAABLgAECn8qAAIMAAkJBSCHCwCMAgAMAAkJBSCHCwCMAgAAAA==.',
Xy='Xyr:BAAALgAECgMJAwAAAA==.',
Ye='Yelizaveta:BAAALgAECgQJBAAAAA==.',
Yn='Ynotna:BAABLgAECn8eAAITAAkJ0hR8KQANAgATAAkJ0hR8KQANAgAAAA==.',
Yo='Yoyiek:BAAALgAECgEJAgAAAA==.',
Yu='Yukí:BAAALgADCggJFgAAAA==.',
Za='Zacygos:BAACLgAFFH8rAAIXAAcJOx+DAgCFAgAXAAcJOx+DAgCFAgAuAAQKf0AAAxcACQkIIw8CAEADABcACQkIIw8CAEADABUABQkeHZgPAO4AAAAA.Zamosc:BAAALgADCgEJAQABLgAFFAMJCwAMAG8aAA==.Zanne:BAACLgAFFH8UAAIRAAQJ4Ri3DQA4AQARAAQJ4Ri3DQA4AQAuAAQKfx4AAhEACAlNHfwZAFoCABEACAlNHfwZAFoCAAAA.Zarellia:BAAALgADCgIJAgAAAA==.Zarthul:BAAALgAECgYJBwAAAA==.',
Zb='Zbämfz:BAAALgAECgEJAQABLgAECgQJCAADAAAAAA==.',
Ze='Zehara:BAABLgAECn8cAAMCAAcJtAhFMgAiAQACAAcJtAhFMgAiAQABAAEJCwEgfwATAAAAAA==.Zenovesh:BAAALgAECgEJAQAAAA==.Zerraphos:BAAALgADCgcJCgAAAA==.Zezima:BAAALgAECgUJCAAAAA==.',
Zh='Zhaolin:BAAALgADCgcJDAAAAA==.',
Zl='Zlot:BAECLgAFFH8rAAQTAAcJsx/FBQDcAQATAAYJ1h7FBQDcAQARAAQJbhMnGADTAAAnAAIJhQ6mIACXAAAuAAQKf0AABBMACQlPJlEFAB4DABMACQkzJlEFAB4DABEABwlAIDYYAGsCACcAAgmEGto/AJgAAAAA.',
Zo='Zoblin:BAAALgAECgUJBQAAAA==.',
['Ör']='Öriana:BAABLgAECn8WAAMOAAgJpwxbDQA8AQAOAAgJpwxbDQA8AQANAAMJ6AZw2wB4AAAAAA==.',
['Úl']='Úlfa:BAAALgAECggJEwAAAA==.',
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
