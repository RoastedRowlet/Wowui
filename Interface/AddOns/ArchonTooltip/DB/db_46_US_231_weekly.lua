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

local lookup = {'DemonHunter-Vengeance','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DemonHunter-Devourer','Druid-Restoration','Warrior-Fury','Evoker-Devastation','Warlock-Demonology','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abelle:BAAALgAECgQJCQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgIJAwAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJBgABLgAECggJFQABAOwdAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgUJBQAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8bAAICAAgJOxcxSQCvAQACAAgJOxcxSQCvAQAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAUJDQADAOkdAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAYJDwAEAN0WAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBCVGgB2AQAFAAgJfBCVGgB2AQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8FAAIGAAMJIgmWDwCSAAAGAAMJIgmWDwCSAAAuAAQKfygAAwYACAktF1ALANMBAAYACAktF1ALANMBAAcABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BcYMACfAQAIAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJBQAJADUDAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQAKAAAAAA==.',
Bu='Bubbies:BAABLgAECn8eAAMLAAkJEBRTFwDQAQALAAgJnxRTFwDQAQAMAAQJHAr5QwC0AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAICAAkJLhLiSACwAQACAAkJLhLiSACwAQAAAA==.Chiste:BAABLgAECn8iAAINAAgJow7SCgBMAQANAAgJow7SCgBMAQAAAA==.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwAKAAAAAA==.Coredellion:BAAALgADCgUJDAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn80AAIOAAkJoRsDCgDTAgAOAAkJoRsDCgDTAgABLgAFFAYJGgAPAJMYAA==.Dannica:BAAALgAECgcJCAAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgYJEQAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAYJDwAEAN0WAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8cAAICAAgJjQ7RXwB0AQACAAgJjQ7RXwB0AQAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAMJCAAQAMocAA==.Donut:BAABLgAECn8VAAIRAAgJABJLOADmAQARAAgJABJLOADmAQABLgAECgcJFgAHAEkPAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn81AAMSAAkJFyJuAQBeAwASAAkJFyJuAQBeAwATAAcJCBQnJwBjAQAAAA==.Elizalynn:BAABLgAECn8kAAIUAAgJohJnHACmAQAUAAgJohJnHACmAQAAAA==.',
Ev='Eveycakes:BAAALgAFFAEJAgABLgAFFAUJDQADAOkdAA==.',
Fe='Fengshui:BAABLgAECn8WAAIIAAkJsBHtGgDCAQAIAAkJsBHtGgDCAQAAAA==.Ferritin:BAABLgAECn8sAAIEAAkJESTcAQBjAwAEAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJAgAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8OAAIVAAQJABl6FAA2AQAVAAQJABl6FAA2AQAuAAQKfzkAAxUACQlbG/AOAGgCABUACQlbG/AOAGgCABYACAlvHGkRAPUBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIXAAkJAR2bFwCaAgAXAAkJAR2bFwCaAgAAAA==.Foxthisup:BAAALgAECgYJBgABLgAECgYJDQAKAAAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJEAAKAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGgAPAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQAKAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJCAAAAA==.Grultock:BAAALgAECgUJCwAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8jAAIOAAgJsh3WDgCYAgAOAAgJsh3WDgCYAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgUJBwABLgAECgkJMAAPAAkaAA==.Hockeyhunter:BAABLgAECn8wAAIPAAkJCRpuGgBEAgAPAAkJCRpuGgBEAgAAAA==.Hockeylockz:BAAALgAECgYJEQABLgAECgkJMAAPAAkaAA==.Hockeysticks:BAAALgADCgMJAwABLgAECgkJMAAPAAkaAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAXANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8bAAMPAAgJ8xdlKwDrAQAPAAgJ8xdlKwDrAQAYAAEJMAncMgArAAABLgAFFAMJBQAGACIJAA==.',
['Hè']='Hèxen:BAAALgADCgcJCAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgYJEAAAAA==.',
Ig='Igneel:BAAALgAECgEJAQAAAA==.',
Je='Jedem:BAAALgADCgUJCQAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAAKAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCAAAAA==.Kazum:BAAALgAECgEJAgAAAA==.',
Ke='Keralan:BAACLgAFFH8HAAMBAAMJbx10CABnAAABAAIJBSR0CABnAAAZAAEJ2BYqGABNAAAuAAQKfyYAAwEACQkQJk0AAFUDAAEACQkQJk0AAFUDABkAAQmhFUFIAEIAAAEuAAUUBQkVABoA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8gAAIJAAgJ+yMUBQCSAgAJAAgJ+yMUBQCSAgAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIbAAcJlA03NAD8AAAbAAcJlA03NAD8AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwAKAAAAAA==.Laizee:BAABLgAECn8gAAIOAAgJ3gOJWgD1AAAOAAgJ3gOJWgD1AAAAAA==.Latrice:BAABLgAECn8lAAICAAkJ6h0MHgBYAgACAAkJ6h0MHgBYAgAAAA==.Laveyan:BAEALgAECgEJAQABLgAFFAMJBwAEAAgfAA==.',
Lo='Loki:BAABLgAECn8aAAISAAYJ8BqxDADJAQASAAYJ8BqxDADJAQAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8kAAIcAAYJ2hYJWAA8AQAcAAYJ2hYJWAA8AQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIVAAkJPBrdCQCqAgAVAAkJPBrdCQCqAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJOAAUAL8gAA==.',
Me='Melander:BAABLgAECn8gAAIJAAkJwhuiBgDEAgAJAAkJwhuiBgDEAgAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAMJCAAQAMocAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIRAAIJeSBxOACqAAARAAIJeSBxOACqAAAuAAQKfyQAAhEACAl5JC8UAJgCABEACAl5JC8UAJgCAAAA.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECggJDgABLgAECgkJIAAJAMIbAA==.Nerzhuul:BAACLgAFFH8IAAIQAAMJyhy+BQAMAQAQAAMJyhy+BQAMAQAuAAQKfy0AAhAACQmaHp4FAKkCABAACQmaHp4FAKkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQAKAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxzyEgA5AgADAAgJAxzyEgA5AgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIXAAYJFxUwowAFAQAXAAYJFxUwowAFAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMdAAgJBBvuIwDxAQAdAAYJuB3uIwDxAQAbAAcJ0Q5pMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJEAABLgAFFAYJDwAEAN0WAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8FAAIJAAIJNQO7GwBiAAAJAAIJNQO7GwBiAAAuAAQKfx0AAgkACAltDVcYADgBAAkACAltDVcYADgBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgYJCQAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgADCgEJAQABLgAFFAYJDwAEAN0WAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8fAAQUAAgJEx9vCACnAgAUAAgJEx9vCACnAgAMAAUJIRqiLgAfAQALAAEJNRa9VQA8AAABLgAFFAIJBAAKAAAAAA==.Raggnarr:BAACLgAFFH8PAAIeAAQJVx5qCwBiAQAeAAQJVx5qCwBiAQAuAAQKfzQAAh4ACQmJJeYBADcDAB4ACQmJJeYBADcDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8LAAIUAAQJpRz4CQBTAQAUAAQJpRz4CQBTAQAAAA==.Rania:BAABLgAECn8VAAIaAAgJ1CBsDQC8AgAaAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn89AAMTAAkJnRinEQAXAgATAAgJ/RanEQAXAgAfAAgJdhL0EgCzAQAAAA==.',
Sa='Sanctified:BAAALgAECgYJDAAAAA==.Saphíra:BAEALgAECgQJCAABLgAFFAMJBwAEAAgfAA==.Satanick:BAAALgADCgEJAQABLgAFFAMJCAAQAMocAA==.Satanickk:BAAALgAECgEJAQABLgAFFAMJCAAQAMocAA==.',
Se='Seraph:BAABLgAECn8kAAIUAAkJqBKxGgC2AQAUAAkJqBKxGgC2AQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgYJBgAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAECgkJIAAJAMIbAA==.',
So='Sojourner:BAABLgAECn8XAAMDAAYJAxHqMwBBAQADAAYJAxHqMwBBAQACAAQJzAsTvADOAAAAAA==.',
Sp='Spoonzilla:BAABLgAECn8VAAIbAAYJ9QexRgCoAAAbAAYJ9QexRgCoAAAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIcAAgJ+R6hGgC0AgAcAAgJ+R6hGgC0AgABLgAECgkJEQAKAAAAAA==.',
Su='Supersham:BAAALgAECgEJAQAAAA==.Superspam:BAABLgAECn8gAAMdAAgJSh/kLAD7AQAdAAgJSh/kLAD7AQAbAAcJWBJ4KgAyAQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn80AAIYAAkJDiDnAQC9AgAYAAkJDiDnAQC9AgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8kAAIdAAgJhA4DPwBbAQAdAAgJhA4DPwBbAQAAAA==.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgADCgMJAgAAAA==.',
Ti='Tinyvoid:BAABLgAECn8gAAIcAAgJlxiQNgCuAQAcAAgJlxiQNgCuAQAAAA==.',
To='Togdumburz:BAACLgAFFH8KAAIgAAMJuhUBTgDnAAAgAAMJuhUBTgDnAAAuAAQKfyUAAyAACQkhGukZAFcCACAACQkhGukZAFcCAA0AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIaAAUJ3CE2AwD4AQAaAAUJ3CE2AwD4AQAuAAQKfxwABBoACAnkIeQJAOsCABoACAnPIeQJAOsCABYAAgnJFCpcAKAAABUAAgmdD1taAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECggJGwAhAIASAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMJAAQJoxq8CgAvAQAJAAMJvSG8CgAvAQAiAAEJUwWMKAA6AAAuAAQKfxkAAwkACAmVItsHAEcCAAkABwkfJNsHAEcCACIABgkTG9QcACsBAAEuAAUUBQkVABoA3CEA.',
Vi='Vietsham:BAABLgAECn8kAAIOAAgJehD3QQBTAQAOAAgJehD3QQBTAQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8PAAIEAAYJ3RabCwBGAQAEAAYJ3RabCwBGAQAuAAQKfyEAAgQACAmNHGgKACICAAQACAmNHGgKACICAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAdAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgAECgEJAQAKAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn84AAMUAAkJvyA8BAASAwAUAAkJvyA8BAASAwALAAYJshEgJABfAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8NAAIDAAUJ6R34CwCbAQADAAUJ6R34CwCbAQAuAAQKfyAAAwMACAlxJPIGAOUCAAMACAlxJPIGAOUCAAIAAQkAActmARMAAAAA.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8fAAIiAAYJnyV2AQAcAgAiAAYJnyV2AQAcAgAuAAQKfyAAAiIACAmrIWUCAAADACIACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgQJCQAAAA==.',
Zy='Zyrahh:BAAALgADCgYJBgAAAA==.',
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
