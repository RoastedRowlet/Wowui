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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Devourer','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Druid-Balance','Warrior-Fury','Druid-Restoration','Evoker-Devastation','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-05-31',data={Ab='Abelle:BAAALgAECgUJDgAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJDAABLgAECgkJGwABAIwdAA==.Anonymoose:BAAALgAECgYJDQABLgAFFAEJAgACAAAAAA==.Antrus:BAAALgAECgkJDgAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgAECgEJAQAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8fAAIDAAkJ5BqILAA3AgADAAkJ5BqILAA3AgAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAYJDwAEAPEcAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBCkIAB3AQAFAAgJfBCkIAB3AQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8JAAIGAAQJ7wkIFADAAAAGAAQJ7wkIFADAAAAuAAQKfyoAAwYACAlXGEIOAOABAAYACAlXGEIOAOABAAcABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIIAAcJ+BcYMACfAQAIAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAQAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJBwAJAEYFAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQACAAAAAA==.',
Bu='Bubbies:BAABLgAECn8iAAMKAAkJnhRGFwD8AQAKAAkJnhRGFwD8AQALAAUJewuWOwADAQAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIDAAkJLhKjXwCZAQADAAkJLhKjXwCZAQAAAA==.Chiste:BAACLgAFFH8FAAIMAAIJkgYQEwB+AAAMAAIJkgYQEwB+AAAuAAQKfyIAAgwACAmjDq4NAEkBAAwACAmjDq4NAEkBAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwACAAAAAA==.Coredellion:BAAALgADCgYJEQAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn86AAINAAkJoRuiDgDIAgANAAkJoRuiDgDIAgABLgAFFAcJHAAOAN8VAA==.Dannica:BAAALgAECgkJEQAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAILAAYJxw3KPgDzAAALAAYJxw3KPgDzAAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAABLgAECn8YAAMBAAYJFxIYFgDdAAABAAYJFxIYFgDdAAAPAAYJUQWQrgCwAAABLgAFFAcJEgAQAEMVAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8kAAIDAAkJnRPROgABAgADAAkJnRPROgABAgAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAQJDgARAIMXAA==.Donut:BAACLgAFFH8FAAISAAMJRgxukADOAAASAAMJRgxukADOAAAuAAQKfxwAAhIACQk+FEk2ABQCABIACQk+FEk2ABQCAAEuAAQKBwkWAAcASg8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8KAAMTAAMJhhm4GADzAAATAAMJhhm4GADzAAAUAAEJqQEjXwAxAAAuAAQKfz0AAxMACQmkItgBAGIDABMACQmkItgBAGIDABQABwleFBktAGwBAAAA.Elizalynn:BAABLgAECn8lAAIVAAkJyRFpHQDEAQAVAAkJyRFpHQDEAQAAAA==.',
Ev='Eveycakes:BAABLgAECn8bAAMVAAYJZR/cFwD7AQAVAAYJZR/cFwD7AQAKAAYJWwoIRADPAAABLgAFFAYJDwAEAPEcAA==.',
Fe='Fengshui:BAABLgAECn8WAAIIAAkJrxGbIgC5AQAIAAkJrxGbIgC5AQAAAA==.Ferritin:BAABLgAECn8yAAIQAAkJESTcAQBjAwAQAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8RAAIWAAUJdRkBFwB0AQAWAAUJdRkBFwB0AQAuAAQKf0QABBYACQmEG/AOAGgCABYACQmEG/AOAGgCABcACQkNHF8PAD4CABgABwkhGSAbALwBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIZAAkJAB0sIQCFAgAZAAkJAB0sIQCFAgAAAA==.Foxthisup:BAAALgAFFAEJAgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJGQAaAJ0QAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAcJHAAOAN8VAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQACAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJDQAAAA==.Grultock:BAAALgAECgcJEQAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8kAAINAAkJAR2XDQDUAgANAAkJAR2XDQDUAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQABLgAECgIJAgACAAAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgQJBQAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgcJDQABLgAECgkJOwAOAB8cAA==.Hockeyhunter:BAABLgAECn87AAIOAAkJHxwDFACeAgAOAAkJHxwDFACeAgAAAA==.Hockeylockz:BAABLgAECn8XAAMbAAYJrAsQGQDXAAAbAAUJ2w0QGQDXAAAcAAUJxgUa0AClAAABLgAECgkJOwAOAB8cAA==.Hockeysticks:BAAALgADCgMJAwABLgAECgkJOwAOAB8cAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAZANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8jAAMOAAgJ6BhUNgDvAQAOAAgJ6BhUNgDvAQAaAAEJMAlhOgArAAABLgAFFAQJCQAGAO8JAA==.',
['Hè']='Hèxen:BAAALgAECgQJBAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8ZAAIaAAYJnRC+EwAOAQAaAAYJnRC+EwAOAQAAAA==.',
Ig='Igneel:BAAALgAECgEJAgAAAA==.',
Im='Imasteward:BAAALgAECgIJAgAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgYJDgAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ju='Junii:BAAALgAECgIJAgAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEgACAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx2XCwBkAAAdAAIJ7A8GHACDAAABAAIJBSSXCwBkAAAuAAQKfywAAwEACQkSJl8AAFwDAAEACQkSJl8AAFwDAB0AAQmhFYNZAEAAAAEuAAUUBgkXABgAZyEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIJAAkJjSMKBADZAgAJAAkJjSMKBADZAgAAAA==.',
Ku='Kuzu:BAAALgAECgMJAwAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIeAAcJkw0TPgD8AAAeAAcJkw0TPgD8AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwACAAAAAA==.Laizee:BAABLgAECn8qAAMNAAkJtgUoWgAyAQANAAkJtgUoWgAyAQAIAAEJ4gOJpAAlAAAAAA==.Latrice:BAABLgAECn8lAAIDAAkJ6x2PKgBAAgADAAkJ6x2PKgBAAgAAAA==.Laveyan:BAEALgAFFAIJAwABLgAFFAUJDQAQAG4iAA==.',
Li='Liquidnitro:BAAALgADCgQJBAAAAA==.',
Lo='Loki:BAABLgAECn8fAAITAAYJKxzWDQDhAQATAAYJKxzWDQDhAQAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8xAAIPAAgJVhg0LwD2AQAPAAgJVhg0LwD2AQAAAA==.',
Ma='Mansamusa:BAAALgAECgcJBwAAAA==.Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIWAAkJPRp6DQCoAgAWAAkJPRp6DQCoAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJQAAVAO0gAA==.',
Me='Melander:BAABLgAECn8lAAMJAAkJwxuiBgDEAgAJAAkJwxuiBgDEAgAfAAQJUxU8SwAFAQAAAA==.Melandruid:BAAALgAECgEJAQABLgAECgkJJQAJAMMbAA==.',
Mh='Mhoram:BAAALgAECgYJBQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAQJDgARAIMXAA==.Missld:BAAALgAECgEJAgABLgAECgEJAgACAAAAAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAISAAIJeSBxOACqAAASAAIJeSBxOACqAAAuAAQKfyQAAhIACAl7JJwcAIoCABIACAl7JJwcAIoCAAAA.',
My='Myth:BAAALgAFFAIJAwAAAA==.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAABLgAECn8ZAAMJAAgJfRi4EQC6AQAJAAcJzhi4EQC6AQAfAAQJgwweXADKAAABLgAECgkJJQAJAMMbAA==.Nerzhuul:BAACLgAFFH8OAAIRAAQJgxdGBgA/AQARAAQJgxdGBgA/AQAuAAQKfzIAAhEACQmGINsCANUCABEACQmGINsCANUCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQACAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIEAAgJAxxcGQBIAgAEAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIZAAYJFxUMxgBbAQAZAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8gAAMgAAgJBBudKgDwAQAgAAYJuB2dKgDwAQAeAAgJcRBpMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
['Où']='Oùtcast:BAAALgADCgQJBAAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAFFAMJAwABLgAFFAcJEgAQAEMVAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8HAAIJAAIJRgXkIQBlAAAJAAIJRgXkIQBlAAAuAAQKfyAAAgkACQlyDO4YAGABAAkACQlyDO4YAGABAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgADCgIJAQABLgAFFAcJEgAQAEMVAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8kAAQVAAgJEx/fCwCTAgAVAAgJEx/fCwCTAgALAAUJOho5NwAYAQAKAAEJNRapZwA7AAABLgAFFAIJCAANAP8LAA==.Raggnarr:BAACLgAFFH8TAAIfAAUJVx7EFQBHAQAfAAUJVx7EFQBHAQAuAAQKfzYAAh8ACQmJJZYDACIDAB8ACQmJJZYDACIDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8SAAIVAAQJ6iCACgB7AQAVAAQJ6iCACgB7AQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AgAYAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Rimlin:BAAALgADCgMJAwAAAA==.Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgQJBQAAAA==.',
Ry='Rythevia:BAABLgAECn9HAAMUAAkJnRhVFQAYAgAUAAgJDRdVFQAYAgAhAAgJ6BL0EgCzAQAAAA==.',
Sa='Sanctified:BAABLgAECn8VAAIEAAgJyxPnJADMAQAEAAgJyxPnJADMAQAAAA==.Saphíra:BAEALgAECgUJCgABLgAFFAUJDQAQAG4iAA==.Satanick:BAAALgADCgEJAQABLgAFFAQJDgARAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAQJDgARAIMXAA==.',
Sc='Schwii:BAAALgAECgEJAQABLgAECggJIAAgAAQbAA==.',
Se='Seraph:BAABLgAECn8qAAIVAAkJFxSFGgDgAQAVAAkJFxSFGgDgAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAECgkJJQAJAMMbAA==.',
So='Sojourner:BAABLgAECn8eAAMEAAcJcBMxMwBzAQAEAAYJPhYxMwBzAQADAAUJCwrt2QDIAAAAAA==.',
Sp='Spoonzilla:BAABLgAECn8eAAIeAAYJFxKCOAAYAQAeAAYJFxKCOAAYAQAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIPAAgJ+R6hGgC0AgAPAAgJ+R6hGgC0AgABLgAECgkJEQACAAAAAA==.',
Su='Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8hAAMgAAkJsx7kLAD7AQAgAAkJsx7kLAD7AQAeAAcJWBLZMgA2AQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Sy='Sylphiett:BAAALgAECgMJAwABLgAFFAUJCQAUAOQIAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn84AAIaAAkJDSCZAgCwAgAaAAkJDSCZAgCwAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8kAAIgAAgJhA6FSABcAQAgAAgJhA6FSABcAQAAAA==.Thrasherzs:BAAALgAECgEJAwAAAA==.Thy:BAAALgAECgMJAwAAAA==.',
Ti='Tinydragon:BAABLgAFFH8JAAIUAAUJ5AhnMADpAAAUAAUJ5AhnMADpAAAAAA==.Tinyvoid:BAACLgAFFH8GAAIPAAMJewroWwC9AAAPAAMJewroWwC9AAAuAAQKfyoAAg8ACQkmGoodAFACAA8ACQkmGoodAFACAAEuAAUUBQkJABQA5AgA.',
To='Togdumburz:BAACLgAFFH8OAAIcAAQJuRNFRgAjAQAcAAQJuRNFRgAjAQAuAAQKfyUAAxwACQkhGu4iAEkCABwACQkhGu4iAEkCAAwAAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Tr='Travis:BAAALgADCgUJAgAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8XAAIYAAYJZyEzAwBDAgAYAAYJZyEzAwBDAgAuAAQKfxwABBgACAnkIeQJAOsCABgACAnPIeQJAOsCABcAAgnJFCpcAKAAABYAAgmdD1taAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAECgkJJQAJAMMbAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIAAiAPoRAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMJAAQJoxpYEAAUAQAJAAMJvSFYEAAUAQAjAAEJUwVrOgA0AAAuAAQKfxkAAwkACAmbIooKADUCAAkABwknJIoKADUCACMABgkSG9klACUBAAEuAAUUBgkXABgAZyEA.',
Vi='Vietsham:BAABLgAECn8vAAINAAkJJxpqEQCtAgANAAkJJxpqEQCtAgAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAAALgAECggJDgAAAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8SAAIQAAcJQxVwDAB7AQAQAAcJQxVwDAB7AQAuAAQKfyQAAhAACQk9HRQIAIQCABAACQk9HRQIAIQCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJIAAgAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn9AAAMVAAkJ7SD2BQAIAwAVAAkJ7SD2BQAIAwAKAAcJBBSFIACoAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8PAAIEAAYJ8RzKCwDaAQAEAAYJ8RzKCwDaAQAuAAQKfyIAAwQACQmGIw0FADIDAAQACQmGIw0FADIDAAMAAQkAAfeoAREAAAAA.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8lAAIjAAcJviPiAQBnAgAjAAcJviPiAQBnAgAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgUJEgAAAA==.',
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
