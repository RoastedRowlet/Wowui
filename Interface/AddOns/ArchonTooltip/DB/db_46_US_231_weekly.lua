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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Monk-Brewmaster','Druid-Balance','DemonHunter-Devourer','Warrior-Fury','Druid-Restoration','Evoker-Devastation','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-05-24',data={Ab='Abelle:BAAALgAECgUJDgAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJBgABLgAECggJGAABAN4eAA==.Anonymoose:BAAALgAECgYJDQABLgAECgcJBwACAAAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgADCgYJCwAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8eAAIDAAkJ1xlmLgAnAgADAAkJ1xlmLgAnAgAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAUJDQAEAOkdAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBDDHQB/AQAFAAgJfBDDHQB/AQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8GAAIGAAQJ7wl4DwDGAAAGAAQJ7wl4DwDGAAAuAAQKfyoAAwYACAlXGHcMAOQBAAYACAlXGHcMAOQBAAcABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BcYMACfAQAIAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJBQAJADUDAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQACAAAAAA==.',
Bu='Bubbies:BAABLgAECn8gAAMKAAkJnhTdFAAKAgAKAAkJnhTdFAAKAgALAAQJGwq/SQC9AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIDAAkJLhIfVgCsAQADAAkJLhIfVgCsAQAAAA==.Chiste:BAABLgAECn8iAAIMAAgJow4/DABOAQAMAAgJow4/DABOAQAAAA==.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwACAAAAAA==.Coredellion:BAAALgADCgUJDAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn80AAINAAkJoRupDADNAgANAAkJoRupDADNAgABLgAFFAcJHAAOAN8VAA==.Dannica:BAAALgAECgkJEQAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAILAAYJxw3HOQAGAQALAAYJxw3HOQAGAQAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAFFAEJAQABLgAFFAYJEAAPAN0WAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8fAAIDAAkJIhBhRQDZAQADAAkJIhBhRQDZAQAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAQJCgAQAIMXAA==.Donut:BAACLgAFFH8FAAIRAAMJRgyIfwDYAAARAAMJRgyIfwDYAAAuAAQKfxgAAhEACQkeFCc2AAYCABEACQkeFCc2AAYCAAEuAAQKBwkWAAcASg8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8JAAMSAAMJhhnoFgD5AAASAAMJhhnoFgD5AAATAAEJqQFOVgA0AAAuAAQKfz0AAxIACQmkIokBAGsDABIACQmkIokBAGsDABMABwleFHgqAHUBAAAA.Elizalynn:BAABLgAECn8lAAIUAAkJyREjGwDKAQAUAAkJyREjGwDKAQAAAA==.',
Ev='Eveycakes:BAABLgAECn8WAAMUAAYJZR+eFQACAgAUAAYJZR+eFQACAgAKAAUJmQndNgDvAAABLgAFFAUJDQAEAOkdAA==.',
Fe='Fengshui:BAABLgAECn8WAAIIAAkJrxF4HwC9AQAIAAkJrxF4HwC9AQAAAA==.Ferritin:BAABLgAECn8sAAIPAAkJESTcAQBjAwAPAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8QAAIVAAUJdRnYEgCAAQAVAAUJdRnYEgCAAQAuAAQKfz0AAxUACQmEG/AOAGgCABUACQmEG/AOAGgCABYACQkNHMsNAEMCAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIXAAkJAB17HQCTAgAXAAkJAB17HQCTAgAAAA==.Foxthisup:BAAALgAECgcJBwAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJGAAYAJ0QAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAcJHAAOAN8VAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQACAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJCAAAAA==.Grultock:BAAALgAECgcJDgAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8kAAINAAkJAR3CCwDYAgANAAkJAR3CCwDYAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgQJBAAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgYJCAABLgAECgkJNgAOAFYbAA==.Hockeyhunter:BAABLgAECn82AAIOAAkJVhtvEwCOAgAOAAkJVhtvEwCOAgAAAA==.Hockeylockz:BAABLgAECn8VAAMZAAYJrAumFgDZAAAZAAUJ2w2mFgDZAAAaAAUJxgWBxQCoAAABLgAECgkJNgAOAFYbAA==.Hockeysticks:BAAALgADCgMJAwABLgAECgkJNgAOAFYbAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgAAAA==.',
Hu='Hunthunthunt:BAABLgAECn8cAAMOAAgJ2BjuMADvAQAOAAgJ2BjuMADvAQAYAAEJMAmLNwArAAABLgAFFAQJBgAGAO8JAA==.',
['Hè']='Hèxen:BAAALgADCgcJCAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8YAAIYAAYJnRCHEgAQAQAYAAYJnRCHEgAQAQAAAA==.',
Ig='Igneel:BAAALgAECgEJAgAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgUJCQAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEQACAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx30CQBmAAAbAAIJ7A/zFwCOAAABAAIJBST0CQBmAAAuAAQKfyYAAwEACQkRJnkAAE4DAAEACQkRJnkAAE4DABsAAQmhFZpRAEEAAAEuAAUUBgkXABwAZyEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIJAAkJjSNQAwDmAgAJAAkJjSNQAwDmAgAAAA==.',
Ku='Kuzu:BAAALgAECgEJAQAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIdAAcJkw21OQD9AAAdAAcJkw21OQD9AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwACAAAAAA==.Laizee:BAABLgAECn8jAAMNAAkJzANLXgAOAQANAAkJzANLXgAOAQAIAAEJ4gM+mAAlAAAAAA==.Latrice:BAABLgAECn8lAAIDAAkJ6x1CJQBQAgADAAkJ6x1CJQBQAgAAAA==.Laveyan:BAEALgAECgYJCgABLgAFFAQJCwAPAG4iAA==.',
Li='Liquidnitro:BAAALgADCgQJBAAAAA==.',
Lo='Loki:BAABLgAECn8fAAISAAYJKxz2DADhAQASAAYJKxz2DADhAQAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8rAAIeAAgJIhg7LQD1AQAeAAgJIhg7LQD1AQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIVAAkJPRo8DACnAgAVAAkJPRo8DACnAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJPwAUAL4gAA==.',
Me='Melander:BAABLgAECn8kAAMJAAkJwxuiBgDEAgAJAAkJwxuiBgDEAgAfAAQJXBGHTQDrAAAAAA==.Melandruid:BAAALgAECgEJAQABLgAECgkJJAAJAMMbAA==.',
Mh='Mhoram:BAAALgAECgYJBQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAQJCgAQAIMXAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIRAAIJeSBxOACqAAARAAIJeSBxOACqAAAuAAQKfyUAAhEACAl7JJQZAI4CABEACAl7JJQZAI4CAAAA.',
My='Myth:BAAALgAFFAEJAQAAAA==.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAAALgAECggJDwABLgAECgkJJAAJAMMbAA==.Nerzhuul:BAACLgAFFH8KAAIQAAQJgxe/BABHAQAQAAQJgxe/BABHAQAuAAQKfzIAAhAACQmGIGQCANkCABAACQmGIGQCANkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQACAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIEAAgJAxxcGQBIAgAEAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIXAAYJFxUMxgBbAQAXAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMgAAgJBBshKADwAQAgAAYJuB0hKADwAQAdAAcJ0Q5pMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAFFAMJAwABLgAFFAYJEAAPAN0WAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8FAAIJAAIJNQMBIABfAAAJAAIJNQMBIABfAAAuAAQKfyAAAgkACQlyDHoWAGsBAAkACQlyDHoWAGsBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgADCgEJAQABLgAFFAYJEAAPAN0WAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8gAAQUAAgJEx+OCgCbAgAUAAgJEx+OCgCbAgALAAUJIRr0NAAeAQAKAAEJNRaOYAA7AAABLgAFFAIJBgANAP8LAA==.Raggnarr:BAACLgAFFH8TAAIfAAUJVx6yEABSAQAfAAUJVx6yEABSAQAuAAQKfzYAAh8ACQmJJdECACoDAB8ACQmJJdECACoDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8PAAIUAAQJ3x67CgBoAQAUAAQJ3x67CgBoAQAAAA==.Rania:BAABLgAECn8VAAIcAAgJ1CBsDQC8AgAcAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgIJAgAAAA==.',
Ry='Rythevia:BAABLgAECn9EAAMTAAkJnRi+EwAiAgATAAgJDRe+EwAiAgAhAAgJdhL0EgCzAQAAAA==.',
Sa='Sanctified:BAAALgAECgYJEgAAAA==.Saphíra:BAEALgAECgQJCAABLgAFFAQJCwAPAG4iAA==.Satanick:BAAALgADCgEJAQABLgAFFAQJCgAQAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAQJCgAQAIMXAA==.',
Se='Seraph:BAABLgAECn8kAAIUAAkJqRIzHgCwAQAUAAkJqRIzHgCwAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAECgkJJAAJAMMbAA==.',
So='Sojourner:BAABLgAECn8dAAMEAAYJPha8LwB3AQAEAAYJPha8LwB3AQADAAQJzAuM0wDLAAAAAA==.',
Sp='Spoonzilla:BAABLgAECn8ZAAIdAAYJ2Ap4SQC3AAAdAAYJ2Ap4SQC3AAAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIeAAgJ+R6hGgC0AgAeAAgJ+R6hGgC0AgABLgAECgkJEQACAAAAAA==.',
Su='Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8hAAMgAAkJsx7kLAD7AQAgAAkJsx7kLAD7AQAdAAcJWBIsLwA3AQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn80AAIYAAkJDSBtAgCwAgAYAAkJDSBtAgCwAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8kAAIgAAgJhA7tRABcAQAgAAgJhA7tRABcAQAAAA==.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgADCggJCAAAAA==.',
Ti='Tinydragon:BAAALgAFFAQJBAAAAA==.Tinyvoid:BAACLgAFFH8GAAIeAAMJewpdUgDFAAAeAAMJewpdUgDFAAAuAAQKfyMAAh4ACQnbGK8pAAYCAB4ACQnbGK8pAAYCAAEuAAUUBAkEAAIAAAAA.',
To='Togdumburz:BAACLgAFFH8KAAIaAAMJuhWtWwDkAAAaAAMJuhWtWwDkAAAuAAQKfyUAAxoACQkhGp4fAFACABoACQkhGp4fAFACAAwAAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8XAAIcAAYJZyEeAgBMAgAcAAYJZyEeAgBMAgAuAAQKfxwABBwACAnkIeQJAOsCABwACAnPIeQJAOsCABYAAgnJFCpcAKAAABUAAgmdD1taAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAECgkJJAAJAMMbAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIAAiAPoRAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMJAAQJoxraDQAiAQAJAAMJvSHaDQAiAQAjAAEJUwV0MgA0AAAuAAQKfxkAAwkACAmbImIJAD0CAAkABwknJGIJAD0CACMABgkSGzIiACkBAAEuAAUUBgkXABwAZyEA.',
Vi='Vietsham:BAABLgAECn8oAAINAAkJgxGvNgCpAQANAAkJgxGvNgCpAQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAAALgAECgcJBwAAAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8QAAIPAAYJ3RaGDgBEAQAPAAYJ3RaGDgBEAQAuAAQKfyIAAg8ACAmOHL0MABMCAA8ACAmOHL0MABMCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJGgAgAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn8/AAMUAAkJviA3BQANAwAUAAkJviA3BQANAwAKAAcJBBR7HQC2AQAAAA==.',
Ye='Yetlian:BAACLgAFFH8NAAIEAAUJ6R28DwCHAQAEAAUJ6R28DwCHAQAuAAQKfyAAAwQACAlxJG8IAOECAAQACAlxJG8IAOECAAMAAQkAAd2MARMAAAAA.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8jAAIjAAcJviMXAQB4AgAjAAcJviMXAQB4AgAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgUJDgAAAA==.',
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
