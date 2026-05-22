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

local lookup = {'Hunter-Marksmanship','Unknown-Unknown','DeathKnight-Frost','Priest-Holy','Monk-Mistweaver','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Hunter-Survival','Warlock-Destruction','Shaman-Elemental','Mage-Frost','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Druid-Feral','Monk-Windwalker','Warlock-Affliction',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Addu:BAAALgADCgYJBgAAAA==.Adiforis:BAAALgADCgYJBgAAAA==.Adobo:BAAALgADCgEJAQAAAA==.',
Ae='Aeralina:BAABLgAECn8XAAIBAAgJoglyDwAkAQABAAgJoglyDwAkAQAAAA==.Aerandir:BAAALgAECgYJDwABLgAFFAEJAQACAAAAAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgYJDAAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn8iAAIDAAcJkg8oDgAkAQADAAcJkg8oDgAkAQAAAA==.Alyestra:BAAALgAECgYJEQAAAA==.',
An='Anibundance:BAAALgAECgYJBgABLgAECgkJLQAEAJ0iAA==.Animyst:BAACLgAFFH8FAAIFAAMJ+R2xGQACAQAFAAMJ+R2xGQACAQAuAAQKfz0AAgUACAkjJZsDAEMDAAUACAkjJZsDAEMDAAEuAAQKCQktAAQAnSIA.Anipaltu:BAABLgAECn8aAAIGAAYJlR/BGAD/AQAGAAYJlR/BGAD/AQABLgAECgkJLQAEAJ0iAA==.Aniron:BAAALgAECgYJDwABLgAECgkJLQAEAJ0iAA==.Anirot:BAABLgAECn8tAAIEAAkJnSJTAgBUAwAEAAkJnSJTAgBUAwAAAA==.Anithwip:BAAALgAECgYJBgABLgAECgkJLQAEAJ0iAA==.',
Ap='Aphirym:BAAALgAECgIJAgAAAA==.',
Ar='Aranta:BAABLgAECn8aAAMHAAYJmQ5MUgANAQAHAAYJmQ5MUgANAQAIAAYJ9AmPPADTAAAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8hAAIJAAkJZSESDgCeAgAJAAkJZSESDgCeAgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Az='Azulmoon:BAAALgAECgYJBgAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Banashain:BAAALgADCgEJAgAAAA==.Bartholomew:BAABLgAECn8jAAIFAAkJRhwwCADIAgAFAAkJRhwwCADIAgAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn8mAAIEAAgJXSWQAgBLAwAEAAgJXSWQAgBLAwAAAA==.Bigtonka:BAAALgADCgYJBgAAAA==.',
Bl='Bladez:BAAALgAECgUJBgAAAA==.',
Bo='Boffadeez:BAAALgAECgQJBAAAAA==.Boombawks:BAAALgADCgUJBQABLgADCgYJAgACAAAAAA==.Boryndin:BAABLgAECn8dAAIKAAgJYRh2DQDQAQAKAAgJYRh2DQDQAQAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAABLgAECn80AAILAAkJfRcsOgA6AgALAAkJfRcsOgA6AgAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgAECgEJAQAAAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Changsauce:BAAALgAECgEJAQAAAA==.Cherypoptart:BAABLgAECn8WAAIMAAcJKyKwDQA3AgAMAAcJKyKwDQA3AgAAAA==.Chrismeister:BAAALgAECgMJBgAAAA==.',
Cl='Claymordon:BAAALgADCgYJBgAAAA==.',
Co='Codah:BAAALgAECgIJBgAAAA==.Coomonka:BAAALgADCgcJBwAAAA==.Corbenik:BAAALgAECgIJBAABLgAECgcJGAANAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crettephal:BAEALgAECgQJBwAAAA==.',
['Cä']='Cähira:BAAALgADCgUJBQABLgADCgYJCQACAAAAAA==.',
Da='Daellan:BAAALgAECgMJBAAAAA==.Dainaira:BAAALgAECgcJDAAAAA==.Daisia:BAABLgAECn8XAAIOAAcJ/gYdKAAeAQAOAAcJ/gYdKAAeAQAAAA==.Dalarrong:BAAALgAECgIJAgAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgAECgEJAQAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8XAAMNAAgJMg8tZgBCAQANAAcJ4w0tZgBCAQAPAAMJqhEuQQCwAAAAAA==.Derien:BAABLgAECn8fAAIKAAgJ9BbnEAD6AQAKAAgJ9BbnEAD6AQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Dezin:BAAALgAECgYJBgAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAECggJEAACAAAAAA==.',
Dk='Dkerien:BAAALgAECggJCAAAAA==.',
Do='Donkeyteeth:BAABLgAECn8bAAIQAAgJHA6KLgA9AQAQAAgJHA6KLgA9AQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgUJCgAAAA==.Draqula:BAAALgADCgcJBwAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8dAAIRAAYJmAtHoAAKAQARAAYJmAtHoAAKAQAAAA==.',
Du='Dura:BAABLgAECn8iAAISAAgJ3RTXJADlAQASAAgJ3RTXJADlAQAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn8sAAIPAAgJ2QpxDgAUAQAPAAgJ2QpxDgAUAQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn84AAMTAAkJmAzORQC5AQATAAkJmAzORQC5AQAUAAEJJwJpTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erazer:BAAALgADCgMJAwAAAA==.Erilana:BAAALgAECgEJAgAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
Ez='Ezanot:BAAALgADCgYJBgAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgACAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8sAAQMAAgJUwsxJQBYAQAMAAgJUwsxJQBYAQAVAAYJ2wnjLwAhAQAEAAUJYAoARQCQAAAAAA==.Faith:BAABLgAECn8VAAILAAYJDRz1VgCKAQALAAYJDRz1VgCKAQAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgADCgkJEAABLgAECggJIwALABcYAA==.Firebug:BAAALgAECgYJEAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgAECgMJAwAAAA==.',
Fr='Frieren:BAAALgAECgMJAwABLgAFFAQJDwAWAN8gAA==.',
Fu='Furnok:BAABLgAECn8mAAMQAAgJbBBiJwBpAQAQAAgJbBBiJwBpAQASAAQJMhAlcwCjAAAAAA==.Fuzzyshukk:BAAALgAECgQJBwAAAA==.',
Ga='Galethia:BAAALgADCgkJGQAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBQABLgAFFAMJAwACAAAAAA==.',
Gh='Ghutz:BAACLgAFFH8IAAIXAAMJswqnFQDHAAAXAAMJswqnFQDHAAAuAAQKfzgAAxcACAlBGXAMANkBABcACAlBGXAMANkBABgABwmICzZIAIMBAAAA.',
Gl='Glitterhoof:BAAALgAECggJEgAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn8sAAIZAAgJSRJTDQC+AQAZAAgJSRJTDQC+AQAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8WAAILAAcJFRGpcABPAQALAAcJFRGpcABPAQAAAA==.',
Ho='Hollet:BAABLgAECn8VAAIaAAYJgw3BbwAWAQAaAAYJgw3BbwAWAQAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8HAAIGAAMJXhiKHgDmAAAGAAMJXhiKHgDmAAAuAAQKfyUAAwYACQmRIqEFABIDAAYACQmRIqEFABIDAAsAAQlCB2dQAS0AAAAA.',
Hu='Huckk:BAAALgADCgUJBQAAAA==.',
Hy='Hylen:BAAALgAECgcJDgAAAA==.',
Ib='Ibrandul:BAABLgAECn8hAAILAAcJhRFxcABQAQALAAcJhRFxcABQAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIRAAcJ8wGV2QCnAAARAAcJ8wGV2QCnAAAAAA==.',
Ir='Ironhuntress:BAABLgAECn8XAAIaAAcJ1w8wVgBXAQAaAAcJ1w8wVgBXAQAAAA==.',
It='Ithro:BAABLgAECn8lAAIbAAkJGRbWAwAmAgAbAAkJGRbWAwAmAgAAAA==.',
Iy='Iyachtu:BAAALgAECgkJDwAAAA==.',
Ja='Jarlo:BAABLgAECn8sAAIbAAgJVBaMBQDhAQAbAAgJVBaMBQDhAQAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECgkJLQALAMUaAA==.',
Jo='Jobu:BAAALgAECgEJAgAAAA==.Jormungandr:BAABLgAECn8lAAIXAAkJVyEQAwDDAgAXAAkJVyEQAwDDAgAAAA==.',
Ju='Juanhunglow:BAAALgADCggJKwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8gAAMTAAgJFiDwGwBmAgATAAgJFiDwGwBmAgAUAAEJ/w+8SAAqAAAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn8lAAIaAAcJRBQtWwBKAQAaAAcJRBQtWwBKAQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8kAAIZAAkJSRq1BgBdAgAZAAkJSRq1BgBdAgAAAA==.',
Kr='Kreltor:BAABLgAECn8jAAISAAgJRiJ5BwD4AgASAAgJRiJ5BwD4AgAAAA==.Kryptikz:BAAALgAECgcJDAAAAA==.Krystoferson:BAABLgAECn8XAAIcAAgJ/wHYLQDeAAAcAAgJ/wHYLQDeAAAAAA==.',
La='Largar:BAAALgADCgQJBAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgAAAA==.Leianii:BAAALgAECgEJAQAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAINAAcJ8QesgwBTAQANAAcJ8QesgwBTAQAAAA==.Lillat:BAAALgAECgUJCwAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lo='Lollilock:BAAALgAECgcJBAAAAA==.',
Lu='Luena:BAAALgAECgYJEgAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgADCgkJCwAAAA==.Luuggork:BAAALgADCgYJBgAAAA==.',
Ly='Lyrà:BAAALgAECgQJAwAAAA==.',
['Lá']='Ládydèath:BAAALgAECgYJAQAAAA==.',
['Lì']='Lìesson:BAABLgAECn8kAAILAAkJfSFNCQDvAgALAAkJfSFNCQDvAgAAAA==.',
Ma='Mackaroni:BAACLgAFFH8GAAIRAAQJWhDLPwA8AQARAAQJWhDLPwA8AQAuAAQKfxgAAhEABwlBF+JhAIQBABEABwlBF+JhAIQBAAEuAAQKCAkQAAIAAAAA.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn8rAAIRAAgJDRZWQgDcAQARAAgJDRZWQgDcAQAAAA==.Makkagg:BAACLgAFFH8NAAMKAAQJnxI/DQANAQAKAAQJnxI/DQANAQAYAAEJAQZhJABLAAAuAAQKfzUAAwoACQkeIYcCAPACAAoACQkeIYcCAPACABgACAlWDMc5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8WAAIRAAgJ2wQVmgAVAQARAAgJ2wQVmgAVAQAAAA==.',
Mi='Milagrosa:BAABLgAECn8hAAIWAAgJFQ6FKgBMAQAWAAgJFQ6FKgBMAQAAAA==.Mirael:BAACLgAFFH8HAAIaAAQJqxziFgBWAQAaAAQJqxziFgBWAQAuAAQKfywAAhoACQnhH8AIAAcDABoACQnhH8AIAAcDAAAA.Mishuntsalot:BAAALgADCgYJCQAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAAALgAECgYJEwAAAA==.',
Mu='Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8XAAIHAAcJdAwpTAAjAQAHAAcJdAwpTAAjAQAAAA==.Mystryx:BAAALgAECggJEQAAAA==.',
['Mà']='Màck:BAAALgAECggJEAAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8dAAINAAYJhBMyhgD/AAANAAYJhBMyhgD/AAAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECgkJLQALAMUaAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAANAPEHAA==.Nirazen:BAAALgAECgIJAgAAAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8XAAILAAcJWAcDtADaAAALAAcJWAcDtADaAAAAAA==.',
Oa='Oathmere:BAAALgADCgUJBQAAAA==.',
Og='Ogrusao:BAAALgAECggJEwAAAA==.',
Pa='Panasaurus:BAABLgAECn8sAAIdAAgJXxRNCQCOAQAdAAgJXxRNCQCOAQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIeAAcJvhmCMgCHAQAeAAcJvhmCMgCHAQAAAA==.Pelli:BAABLgAECn8gAAIMAAgJEAYiMQASAQAMAAgJEAYiMQASAQAAAA==.Pendraig:BAAALgADCgUJCAAAAA==.',
Pl='Plaza:BAAALgAECgkJCAAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgUJDgACAAAAAA==.Rayst:BAABLgAECn8aAAIRAAYJVQIL2gCmAAARAAYJVQIL2gCmAAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAAALgAECgcJEAABLgAFFAMJBgAHAIERAA==.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8XAAIYAAcJ+iDwEwATAgAYAAcJ+iDwEwATAgAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn8nAAMOAAgJJBQtFADOAQAOAAgJsRMtFADOAQAaAAEJ+hSh1gA/AAAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJLgAfAGQZAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Salindill:BAAALgADCgMJAwAAAA==.Salline:BAABLgAECn8YAAMaAAYJawhMhQDkAAAaAAYJXghMhQDkAAAOAAQJfAIoQgBhAAAAAA==.Samanda:BAABLgAECn8YAAIgAAYJSg5EFwADAQAgAAYJSg5EFwADAQAAAA==.Samshir:BAAALgAFFAEJAQAAAA==.',
Sc='Scorned:BAABLgAECn8iAAIJAAcJ4hAKYwAeAQAJAAcJ4hAKYwAeAQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.Seosinz:BAAALgAECgcJBwAAAA==.',
Sh='Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgAECgMJAwAAAA==.Shaylinn:BAAALgADCggJJwAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAFFAMJBwAGAF4YAA==.',
Si='Siella:BAABLgAECn8iAAIEAAgJthFBGwCxAQAEAAgJthFBGwCxAQAAAA==.Sileves:BAAALgAECgEJAgAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8eAAIRAAgJjCADHQB6AgARAAgJjCADHQB6AgAAAA==.',
So='Sonofmums:BAAALgAECgkJBgAAAA==.Sora:BAAALgADCgIJAgABLgAECgEJAQACAAAAAA==.Soulbaine:BAAALgAECgQJCQAAAA==.',
Sp='Spazeric:BAABLgAECn8aAAMFAAgJdBXTGQDjAQAFAAgJdBXTGQDjAQAhAAQJdRPNWQCpAAAAAA==.Spheria:BAABLgAECn8nAAINAAgJzQaIdAAjAQANAAgJzQaIdAAjAQAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJEQAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Talashea:BAAALgAECgEJAQAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECgQJBQACAAAAAA==.Tarall:BAAALgADCgMJAwAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAABLgAECn8aAAIiAAYJmwboEgDXAAAiAAYJmwboEgDXAAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgADCggJHQAAAA==.',
Ti='Tim:BAAALgAFFAEJAQAAAA==.Timeshadow:BAAALgAECgQJBAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8hAAIRAAkJZRccNgAHAgARAAkJZRccNgAHAgAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAAALgAECgkJDwAAAA==.',
Tr='Triplesix:BAAALgAECggJEwAAAA==.Trittia:BAABLgAECn8YAAIYAAYJQQgMRwDlAAAYAAYJQQgMRwDlAAAAAA==.',
Tu='Tukk:BAAALgAECgYJDgAAAA==.Turtle:BAAALgAECgEJBAAAAA==.',
Tw='Twigatron:BAABLgAECn8VAAIHAAgJBxVIJQDoAQAHAAgJBxVIJQDoAQABLgAECgcJEQACAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBgAAAA==.',
Ty='Tynk:BAAALgADCgUJBQABLgAECgQJBAACAAAAAA==.',
Ur='Urza:BAAALgAECgUJBwAAAA==.',
Va='Vaewind:BAAALgADCgMJAwAAAA==.Valethus:BAABLgAECn8vAAMaAAkJ5BoTGQBNAgAaAAkJ5BoTGQBNAgABAAIJVAgefgBNAAAAAA==.Valmaru:BAAALgADCgkJCQAAAA==.',
Ve='Vesp:BAAALgAECgMJAwAAAA==.Vexxa:BAABLgAECn8WAAIJAAgJIxpmSQBpAQAJAAgJIxpmSQBpAQAAAA==.',
Vy='Vynd:BAAALgADCgkJDgABLgABCgMJBAACAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAABLgAECgcJDAACAAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn8mAAIMAAgJPxq2EQAEAgAMAAgJPxq2EQAEAgAAAA==.Wiggleston:BAAALgAECgYJEAAAAA==.Willscarlet:BAAALgAECgQJBgAAAA==.',
Wy='Wylethia:BAAALgADCgcJCAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAFFAEJAQACAAAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgADCgkJGAAAAA==.',
Za='Zarathia:BAAALgAECgUJCQAAAA==.Zaritym:BAABLgAECn8XAAMFAAcJQhliGgDdAQAFAAcJQhliGgDdAQAhAAQJbw/LSwCTAAAAAA==.Zarrilin:BAABLgAECn8nAAIRAAkJURdAMwASAgARAAkJURdAMwASAgAAAA==.',
Ze='Zebop:BAAALgADCgMJBgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8HAAIPAAMJQAraBgDTAAAPAAMJQAraBgDTAAAuAAQKf0MAAg8ACQnlGloCAFcCAA8ACQnlGloCAFcCAAAA.',
Zo='Zoeheals:BAAALgAECgQJBQAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCQAAAA==.Zulmahn:BAABLgAECn8YAAMSAAcJcBCxQABYAQASAAcJcBCxQABYAQAQAAMJigMLdQA/AAAAAA==.',
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
