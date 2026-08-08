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

local lookup = {'DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Holy','Paladin-Retribution','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Druid-Balance','Warlock-Affliction','Warlock-Demonology','Hunter-Marksmanship','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','Mage-Arcane','Evoker-Devastation','Paladin-Protection','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-08-04',data={Ab='Abelle:BAAALgAECgUJEQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliantha:BAAALgAECgYJDAAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgcJEwABLgAECgkJGwABAIwdAA==.Anonymoose:BAAALgAECgYJDQABLgAFFAMJCAACALESAA==.Antrus:BAAALgAECgkJDgAAAA==.',
Ar='Arakhne:BAAALgAECgUJBQABLgAECgkJMQADAGoeAA==.Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgAECgUJBgAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAACLgAFFH8JAAIEAAMJUgVvgQCzAAAEAAMJUgVvgQCzAAAuAAQKfygAAgQACQnVHrQUAMYCAAQACQnVHrQUAMYCAAAA.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAFFAEJAQABLgAFFAgJFAADAFUZAA==.',
Au='Auhsoj:BAAALgAFFAIJAgABLgAFFAgJGAAFABgVAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Babysnatcher:BAAALgADCgMJAwAAAA==.Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIGAAgJfBA0JABzAQAGAAgJfBA0JABzAQAAAA==.Banality:BAAALgAECgcJEgAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8MAAIHAAQJzgqsHACtAAAHAAQJzgqsHACtAAAuAAQKfzAAAwcACAlXGOYQANwBAAcACAlXGOYQANwBAAgABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIJAAcJ+BcYMACfAQAJAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAgAAAA==.Breadbull:BAAALgAECgUJCAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAQJEAAKAGQEAA==.Briarmaul:BAAALgAECgIJAwAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQALAAAAAA==.',
Bu='Bubbies:BAABLgAECn8iAAMMAAkJnhQAGwD3AQAMAAkJnhQAGwD3AQANAAUJewuERQD5AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Cf='Cfodder:BAAALgAECggJCwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIEAAkJLhJPawCYAQAEAAkJLhJPawCYAQAAAA==.Chiste:BAACLgAFFH8FAAIOAAIJkgYWFwB5AAAOAAIJkgYWFwB5AAAuAAQKfyIAAg4ACAmjDp8PAEYBAA4ACAmjDp8PAEYBAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwALAAAAAA==.Coredellion:BAAALgADCgkJHAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.Covak:BAAALgAFFAIJAwAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dagdadonn:BAAALgAECgUJBQAAAA==.Dahlia:BAABLgAECn87AAIPAAkJoRtIEQDEAgAPAAkJoRtIEQDEAgABLgAFFAkJJwAQAA8TAA==.Dannica:BAAALgAECgkJEgAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darknessoup:BAAALgADCgEJAQABLgAFFAQJEAAKAGQEAA==.Darthen:BAABLgAECn8WAAINAAYJxw2lRgD1AAANAAYJxw2lRgD1AAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deadpanda:BAAALgADCgUJBQAAAA==.Deathmantis:BAABLgAECn8YAAMBAAYJFxK1GADaAAABAAYJFxK1GADaAAARAAYJUQWQrgCwAAABLgAFFAgJGAAFABgVAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.Deremar:BAAALgAECgEJAQAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8kAAIEAAkJnRNyQgD/AQAEAAkJnRNyQgD/AQAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAYJEAASABMVAA==.Donut:BAACLgAFFH8FAAICAAMJRgx1rgDFAAACAAMJRgx1rgDFAAAuAAQKfxwAAgIACQk+FGo9AAwCAAIACQk+FGo9AAwCAAEuAAQKBwkWAAgASg8A.Doodle:BAAALgAECgYJBgAAAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgAECgcJBgAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8PAAMTAAMJThu7GgDqAAATAAMJThu7GgDqAAAUAAIJDw4yMwBIAAAuAAQKf0EAAxMACQkAIxsCAFwDABMACQkAIxsCAFwDABQACAmzFWIxAHEBAAAA.Elizalynn:BAABLgAECn8rAAIVAAkJyRH4IAC6AQAVAAkJyRH4IAC6AQAAAA==.Elunarlian:BAAALgAFFAQJBAABLgAFFAgJFAADAFUZAA==.',
Ev='Eveycakes:BAACLgAFFH8IAAMMAAQJfgn6MADMAAAMAAQJWQT6MADMAAAVAAEJeBo1NQBBAAAuAAQKfx0AAxUACAnKHdkaAPMBABUABgllH9kaAPMBAAwACAkDDnkUAJMAAAEuAAUUCAkUAAMAVRkA.',
Fa='Father:BAAALgADCgUJBQAAAA==.',
Fe='Fengshui:BAABLgAECn8WAAIJAAkJrxGfJwCwAQAJAAkJrxGfJwCwAQAAAA==.Ferritin:BAABLgAECn8yAAIFAAkJESTcAQBjAwAFAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8ZAAIWAAgJOhf7FwC7AQAWAAgJOhf7FwC7AQAuAAQKf0wABBYACQkqIRMCAKgCABYACQkqIRMCAKgCABcACQkPHe8RADMCABgABwkhGXUdALkBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIZAAkJAB1+JgCBAgAZAAkJAB1+JgCBAgAAAA==.Foxthisup:BAAALgAFFAEJAwABLgAFFAMJCAACALESAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgkJMwAQAKgdAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Gelid:BAAALgAECgQJBAAAAA==.Geneviève:BAAALgAFFAIJBAABLgAFFAkJJwAQAA8TAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQALAAAAAA==.',
Go='Goon:BAAALgAECgEJAQAAAA==.Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAABLgAECn8dAAIaAAgJxw6uBwBFAQAaAAgJxw6uBwBFAQAAAA==.Gruff:BAAALgAECgYJBgAAAA==.Grultock:BAABLgAECn8fAAIKAAgJ7RcSEADmAQAKAAgJ7RcSEADmAQAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8rAAIPAAkJxh39DwDRAgAPAAkJxh39DwDRAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgQJBQABLgAFFAUJBQAQALwEAA==.',
Ha='Hapday:BAAALgAECgUJDAAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECggJEwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAABLgAECn8fAAIaAAgJShToIwCrAQAaAAgJShToIwCrAQABLgAFFAQJCAAQAKgQAA==.Hockeyhunter:BAACLgAFFH8IAAIQAAQJqBCyQgAoAQAQAAQJqBCyQgAoAQAuAAQKf1EAAhAACQlRIc8NAOMCABAACQlRIc8NAOMCAAAA.Hockeylockz:BAABLgAECn8bAAMbAAYJrAvPHADYAAAbAAUJ2w3PHADYAAAcAAUJIAam3ACgAAABLgAFFAQJCAAQAKgQAA==.Hockeysticks:BAAALgADCgQJCgABLgAFFAQJCAAQAKgQAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooky:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgMJCAABLgAECgkJIgAZANAPAA==.',
Hu='Huntdrath:BAABLgAECn8VAAIQAAYJcA2tHADvAAAQAAYJcA2tHADvAAAAAA==.Hunthunthunt:BAABLgAECn8jAAMQAAgJ6BhcQADhAQAQAAgJ6BhcQADhAQAdAAEJMAnmQQAnAAABLgAFFAQJDAAHAM4KAA==.',
['Hè']='Hèxen:BAAALgAECgUJCAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8zAAMQAAkJqB2zBgAhAgAQAAkJ3RyzBgAhAgAdAAgJNxdbCQDhAQAAAA==.',
Ig='Igneel:BAAALgAECgEJAwABLgAECgEJBAALAAAAAA==.',
Il='Illidaniel:BAAALgAECgMJAwABLgAFFAMJCAACALESAA==.',
Im='Imasteward:BAABLgAFFH8FAAIeAAMJOQPeIQBnAAAeAAMJOQPeIQBnAAABLgAFFAUJBQAQALwEAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgYJDgAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ju='Junii:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEgALAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgQJDQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx2ADgBiAAAfAAIJ7A+qJAB+AAABAAIJBSSADgBiAAAuAAQKfy8AAwEACQkSJpIAAFQDAAEACQkSJpIAAFQDAB8AAQmhFV5nAD8AAAEuAAUUCAkdABgAaR8A.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.Kimk:BAABLgAECn8VAAMVAAcJ6g8oBwBRAQAVAAYJ+hEoBwBRAQANAAQJ7wXzGQBiAAAAAA==.',
Kl='Klhank:BAAALgAECgYJCgAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIKAAkJjSMzBQDIAgAKAAkJjSMzBQDIAgAAAA==.',
Ku='Kuzu:BAAALgAECgMJAwAAAA==.Kuzul:BAAALgAECgEJAwAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIaAAcJkw2HRAD6AAAaAAcJkw2HRAD6AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwALAAAAAA==.Laizee:BAABLgAECn8qAAMPAAkJtgW6YwAwAQAPAAkJtgW6YwAwAQAJAAEJ4gN7twAlAAAAAA==.Latrice:BAABLgAECn8lAAIEAAkJ6x0GMQA8AgAEAAkJ6x0GMQA8AgAAAA==.Laveyan:BAECLgAFFH8HAAIRAAQJSRJ0ZADEAAARAAQJSRJ0ZADEAAAuAAQKfxgAAhEACAm+HIUlADgCABEACAm+HIUlADgCAAEuAAUUBQkRAAUApSIA.',
Ld='Ldshunter:BAAALgAECgEJAgABLgAECgEJBAALAAAAAA==.',
Li='Liquidnitro:BAABLgAFFH8FAAICAAMJoAPPXwCWAAACAAMJoAPPXwCWAAAAAA==.Livsfara:BAAALgAECgEJAQABLgAFFAQJCQAKAK4aAA==.',
Lo='Loki:BAABLgAECn8oAAITAAgJuxnXCwAaAgATAAgJuxnXCwAaAgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn89AAIRAAgJuhkWNAD2AQARAAgJuhkWNAD2AQAAAA==.',
Ma='Mansamusa:BAAALgAECgcJCwAAAA==.Masayoshi:BAAALgAECgIJAgAAAA==.Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIWAAkJPRqQDwCrAgAWAAkJPRqQDwCrAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJQgAVAO0gAA==.',
Me='Me:BAAALgAECgUJDQABLgAFFAQJCAAQAKgQAA==.Melander:BAACLgAFFH8JAAIKAAQJrhomDwA+AQAKAAQJrhomDwA+AQAuAAQKfy8AAwoACQlzHKIGAMQCAAoACQlzHKIGAMQCACAABgk4FRoyAIMBAAAA.Melandruid:BAAALgAECgEJAQABLgAFFAQJCQAKAK4aAA==.',
Mh='Mhoram:BAAALgAECgYJCQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAYJEAASABMVAA==.Missld:BAAALgAECgEJBAAAAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgQJBQAAAA==.Monkraga:BAAALgAECgUJBQAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.Mordracon:BAAALgAECgkJEgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAICAAIJeSBxOACqAAACAAIJeSBxOACqAAAuAAQKfyQAAgIACAl7JEohAIMCAAIACAl7JEohAIMCAAAA.',
My='Myth:BAACLgAFFH8HAAIZAAQJbhmYdwDrAAAZAAQJbhmYdwDrAAAuAAQKfyYAAxkACAk6G+wtAGECABkACAkPG+wtAGECACEAAwk2I68CADgBAAAA.',
Na='Nachotaco:BAAALgAECgkJCQAAAA==.Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAABLgAECn8pAAMKAAkJyx6wCwAyAgAKAAkJyx6wCwAyAgAgAAYJEBVgQABDAQABLgAFFAQJCQAKAK4aAA==.Nerzhuul:BAACLgAFFH8QAAISAAYJExUbCQAoAQASAAYJExUbCQAoAQAuAAQKfzIAAhIACQmGIH8DAM0CABIACQmGIH8DAM0CAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQALAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxxcGQBIAgADAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIZAAYJFxUMxgBbAQAZAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAACLgAFFH8IAAMaAAQJxgklNgCmAAAaAAQJxgklNgCmAAAeAAMJtAOILQA+AAAuAAQKfyAAAx4ACAkEG5ctAPABAB4ABgm4HZctAPABABoACAlxEGkwAIUBAAAA.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
['Où']='Oùtcast:BAAALgADCgQJBAAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pamnais:BAAALgAECgEJAwABLgAECgEJBAALAAAAAA==.Pandastryker:BAABLgAFFH8HAAMYAAMJUBGANwDIAAAYAAMJUBGANwDIAAAXAAEJywKpSgApAAABLgAFFAgJGAAFABgVAA==.Panla:BAAALgADCgEJAQAAAA==.Patrickstâr:BAAALgAFFAEJAgAAAA==.Pawsforeffkt:BAAALgAECgEJAgAAAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8QAAIKAAQJZAQAFACFAAAKAAQJZAQAFACFAAAuAAQKfycAAgoACQlpDjocAFUBAAoACQlpDjocAFUBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAABLgAECn8bAAIEAAkJSRlzBQBNAgAEAAkJSRlzBQBNAgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgAECgIJAgABLgAFFAgJGAAFABgVAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAACLgAFFH8OAAQVAAMJaR/nFgAHAQAVAAMJaR/nFgAHAQAMAAMJQxTyGgCvAAANAAIJ9hE7GQCHAAAuAAQKfysABBUACAkTH+ENAIgCABUACAkTH+ENAIgCAA0ABgmtGaAtAGwBAAwAAQk1Fhl2ADoAAAAA.Raggnarr:BAACLgAFFH8dAAIgAAgJPh17BAANAgAgAAgJPh17BAANAgAuAAQKfzsAAiAACQnBJUUEACEDACAACQnBJUUEACEDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8gAAIVAAYJFSGfBgDuAQAVAAYJFSGfBgDuAQAAAA==.Ranar:BAAALgADCggJCAAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AgAYAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAABLgAECn8XAAIcAAYJ2gXbGwCQAAAcAAYJ2gXbGwCQAAAAAA==.',
Ri='Rimlin:BAAALgADCgcJCgAAAA==.Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgQJCQAAAA==.',
Ry='Rythevia:BAABLgAECn9HAAMUAAkJnRg/FwAeAgAUAAgJDRc/FwAeAgAiAAgJ6BL0EgCzAQAAAA==.',
Sa='Sanctified:BAABLgAECn8hAAIDAAkJORUfBwBYAQADAAkJORUfBwBYAQAAAA==.Saphíra:BAEALgAECgUJDQABLgAFFAUJEQAFAKUiAA==.Satanick:BAAALgADCgEJAQABLgAFFAYJEAASABMVAA==.Satanickk:BAAALgAECgUJCgABLgAFFAYJEAASABMVAA==.',
Sc='Schwii:BAAALgAECgQJBwABLgAFFAQJCAAaAMYJAA==.',
Se='Seraph:BAABLgAECn8qAAIVAAkJFxT8HQDVAQAVAAkJFxT8HQDVAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shadowwes:BAAALgAECgUJCQAAAA==.Shirakami:BAAALgAECgYJEgAAAA==.Shoc:BAAALgADCgIJAgAAAA==.Shotsforbots:BAABLgAFFH8FAAIQAAUJvARDewChAAAQAAUJvARDewChAAAAAA==.',
Sj='Sjoralina:BAAALgAECgMJBQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAwABLgAFFAQJCQAKAK4aAA==.',
So='Sojourner:BAABLgAECn86AAQDAAkJcB2eAwDqAQADAAgJXxyeAwDqAQAEAAgJixMHEgBFAQAjAAMJSRD1CwCRAAAAAA==.',
Sp='Speedy:BAABLgAECn8aAAIfAAcJJRrIAwDKAQAfAAcJJRrIAwDKAQABLgAFFAQJCAAQAKgQAA==.Spoonzilla:BAABLgAECn8jAAIaAAYJvxJ+DgDHAAAaAAYJvxJ+DgDHAAAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stoned:BAAALgADCgUJBQABLgAFFAQJCAAQAKgQAA==.Stormm:BAABLgAECn8kAAIRAAgJ+R6hGgC0AgARAAgJ+R6hGgC0AgABLgAECgkJEQALAAAAAA==.',
Su='Superfire:BAAALgADCgUJBQAAAA==.Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8jAAMeAAkJsx7kLAD7AQAeAAkJsx7kLAD7AQAaAAcJWBJWOAAzAQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Sy='Sylphiett:BAAALgAFFAIJAgABLgAFFAUJEwAUAAMJAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn85AAIdAAkJDSAtAwCmAgAdAAkJDSAtAwCmAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8nAAIeAAkJqQ5jPwCUAQAeAAkJqQ5jPwCUAQAAAA==.Thrasherzs:BAAALgAECgEJBAAAAA==.Thy:BAAALgAECgUJCAAAAA==.',
Ti='Tinydragon:BAABLgAFFH8TAAIUAAUJAwlVOwDaAAAUAAUJAwlVOwDaAAAAAA==.Tinyvoid:BAACLgAFFH8GAAIRAAMJewrxbACxAAARAAMJewrxbACxAAAuAAQKfzAAAhEACQnOGuwgAE8CABEACQnOGuwgAE8CAAEuAAUUBQkTABQAAwkA.Tirok:BAAALgADCgIJAgAAAA==.',
To='Togdumburz:BAACLgAFFH8RAAIcAAcJExAjVQAcAQAcAAcJExAjVQAcAQAuAAQKfyUAAxwACQkhGponAD4CABwACQkhGponAD4CAA4AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Tr='Travis:BAAALgADCgUJAgAAAA==.',
Ty='Typhoid:BAAALgADCgUJBQAAAA==.Typhon:BAAALgAECgEJAQAAAA==.',
Ud='Udderlymad:BAABLgAFFH8IAAICAAMJsRILZgCJAAACAAMJsRILZgCJAAAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8dAAMYAAgJaR8mBgAyAgAYAAYJZyEmBgAyAgAWAAUJrAs8MgDoAAAuAAQKfx4ABBgACAnkIeQJAOsCABgACAnPIeQJAOsCABYAAwkoHbBzAL8AABcAAgnJFCpcAKAAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJCAABLgAFFAQJCQAKAK4aAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIQAkADUTAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMKAAQJoxqKFAD9AAAKAAMJvSGKFAD9AAAlAAEJUwVqSAAzAAAuAAQKfxkAAwoACAmbIioMACsCAAoABwknJCoMACsCACUABgkSG+EpACUBAAEuAAUUCAkdABgAaR8A.',
Vi='Vietsham:BAABLgAECn8zAAIPAAkJShw4FACqAgAPAAkJShw4FACqAgAAAA==.Vincenarius:BAAALgAECgQJBAABLgAFFAYJEAASABMVAA==.Viralmessiah:BAAALgAECgEJAQAAAA==.',
Vo='Vokevokevoke:BAABLgAECn8aAAIUAAkJNQvUCgC+AAAUAAkJNQvUCgC+AAABLgAFFAQJDAAHAM4KAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8YAAIFAAgJGBVXEgBmAQAFAAgJGBVXEgBmAQAuAAQKfyYAAgUACQlDHagJAHgCAAUACQlDHagJAHgCAAAA.',
Vy='Vynch:BAAALgAECgUJCQABLgAFFAQJCQAKAK4aAA==.Vynstan:BAAALgAFFAIJBAAAAA==.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgYJCQABLgAFFAQJCAAaAMYJAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.Wooloolooloo:BAAALgAECgMJBAAAAA==.',
Wu='Wulfriic:BAAALgADCgYJAwAAAA==.Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJBAALAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn9CAAMVAAkJ7SA5BwD9AgAVAAkJ7SA5BwD9AgAMAAcJBBR9JQCkAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8UAAIDAAgJVRnqCgAHAgADAAgJVRnqCgAHAgAuAAQKfyIAAwMACQmGIwsGAC0DAAMACQmGIwsGAC0DAAQAAQkAAXPUARAAAAAA.',
Yo='You:BAAALgAECgQJBAABLgAFFAQJCAAQAKgQAA==.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8nAAIlAAkJwiMxAgCmAgAlAAkJwiMxAgCmAgAuAAQKfyAAAiUACAmrIWUCAAADACUACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAABLgAECn8UAAIeAAUJjggqhQCuAAAeAAUJjggqhQCuAAAAAA==.',
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
