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

local lookup = {'DemonHunter-Vengeance','DeathKnight-Unholy','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Hunter-Marksmanship','Druid-Balance','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Warrior-Fury','Druid-Restoration','Evoker-Devastation','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-06-21',data={Ab='Abelle:BAAALgAECgUJDwAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgcJEwABLgAECgkJGwABAIwdAA==.Anonymoose:BAAALgAECgYJDQABLgAFFAMJBQACAKcKAA==.Antrus:BAAALgAECgkJDgAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgAECgUJBgAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8oAAIDAAkJ1R6zFADGAgADAAkJ1R6zFADGAgAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAFFAEJAQABLgAFFAcJEwAEACgcAA==.',
Au='Auhsoj:BAAALgAFFAIJAgABLgAFFAcJFwAFAEMVAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIGAAgJfBAzJABzAQAGAAgJfBAzJABzAQAAAA==.Banality:BAAALgAECgUJCgAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8MAAIHAAQJzgqpHACtAAAHAAQJzgqpHACtAAAuAAQKfzAAAwcACAlXGOcQANwBAAcACAlXGOcQANwBAAgABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIJAAcJ+BcYMACfAQAJAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAgAAAA==.Breadbull:BAAALgAECgUJCAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAMJDQAKAFIEAA==.Briarmaul:BAAALgAECgIJAgAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQALAAAAAA==.',
Bu='Bubbies:BAABLgAECn8iAAMMAAkJnhT/GgD3AQAMAAkJnhT/GgD3AQANAAUJewuARQD5AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIDAAkJLhJRawCYAQADAAkJLhJRawCYAQAAAA==.Chiste:BAACLgAFFH8FAAIOAAIJkgYUFwB5AAAOAAIJkgYUFwB5AAAuAAQKfyIAAg4ACAmjDp8PAEYBAA4ACAmjDp8PAEYBAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwALAAAAAA==.Coredellion:BAAALgADCgkJFgAAAA==.Corypheus:BAAALgADCggJEAAAAA==.Covak:BAAALgAFFAIJAgAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn86AAIPAAkJoRtHEQDEAgAPAAkJoRtHEQDEAgABLgAFFAgJJgAQAPgUAA==.Dannica:BAAALgAECgkJEgAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAINAAYJxw2iRgD1AAANAAYJxw2iRgD1AAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAABLgAECn8YAAMBAAYJFxK1GADaAAABAAYJFxK1GADaAAARAAYJUQWQrgCwAAABLgAFFAcJFwAFAEMVAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8kAAIDAAkJnRNxQgD/AQADAAkJnRNxQgD/AQAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAUJDwASAIMXAA==.Donut:BAACLgAFFH8FAAICAAMJRgx1rgDFAAACAAMJRgx1rgDFAAAuAAQKfxwAAgIACQk+FGc9AAwCAAIACQk+FGc9AAwCAAEuAAQKBwkWAAgASg8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8OAAMTAAMJThu8GgDqAAATAAMJThu8GgDqAAAUAAEJqQGNbAAuAAAuAAQKfz8AAxMACQkAIxsCAFwDABMACQkAIxsCAFwDABQABwkyFmQxAHEBAAAA.Elizalynn:BAABLgAECn8nAAIVAAkJyRH1IAC6AQAVAAkJyRH1IAC6AQAAAA==.Elunarlian:BAAALgAFFAQJBAABLgAFFAcJEwAEACgcAA==.',
Ev='Eveycakes:BAACLgAFFH8IAAMMAAQJfgn5MADMAAAMAAQJWQT5MADMAAAVAAEJeBozNQBBAAAuAAQKfxsAAxUABgllH9caAPMBABUABgllH9caAPMBAAwABglbCuVKANkAAAEuAAUUBwkTAAQAKBwA.',
Fa='Father:BAAALgADCgUJBQAAAA==.',
Fe='Fengshui:BAABLgAECn8WAAIJAAkJrxGeJwCwAQAJAAkJrxGeJwCwAQAAAA==.Ferritin:BAABLgAECn8yAAIFAAkJESTcAQBjAwAFAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8TAAIWAAYJ+Rn7FwC7AQAWAAYJ+Rn7FwC7AQAuAAQKf0QABBYACQmEG/AOAGgCABYACQmEG/AOAGgCABcACQkNHO8RADMCABgABwkhGXQdALkBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIZAAkJAB2BJgCBAgAZAAkJAB2BJgCBAgAAAA==.Foxthisup:BAAALgAFFAEJAwABLgAFFAMJBQACAKcKAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECggJKwAaADMaAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAgJJgAQAPgUAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQALAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJEgAAAA==.Gruff:BAAALgAECgYJBgAAAA==.Grultock:BAABLgAECn8fAAIKAAgJ7RcSEADmAQAKAAgJ7RcSEADmAQAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8nAAIPAAkJzh39DwDRAgAPAAkJzh39DwDRAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgQJBQABLgAFFAMJAwALAAAAAA==.',
Ha='Hapday:BAAALgAECgUJDAAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECggJEwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAABLgAECn8bAAIbAAgJ6hLkIwCrAQAbAAgJ6hLkIwCrAQABLgAFFAQJCAAQAKgQAA==.Hockeyhunter:BAACLgAFFH8IAAIQAAQJqBCzQgAoAQAQAAQJqBCzQgAoAQAuAAQKf0oAAhAACQlQIdENAOMCABAACQlQIdENAOMCAAAA.Hockeylockz:BAABLgAECn8bAAMcAAYJrAvQHADYAAAcAAUJ2w3QHADYAAAdAAUJIAap3ACgAAABLgAFFAQJCAAQAKgQAA==.Hockeysticks:BAAALgADCgQJCgABLgAFFAQJCAAQAKgQAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooky:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgMJCAABLgAECgkJIgAZANAPAA==.',
Hu='Huntdrath:BAAALgAECgYJBgAAAA==.Hunthunthunt:BAABLgAECn8jAAMQAAgJ6BhdQADhAQAQAAgJ6BhdQADhAQAaAAEJMAnmQQAnAAABLgAFFAQJDAAHAM4KAA==.',
['Hè']='Hèxen:BAAALgAECgQJBwAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8rAAMaAAgJMxpbCQDhAQAaAAgJNxdbCQDhAQAQAAYJTRfYBQDzAAAAAA==.',
Ig='Igneel:BAAALgAECgEJAwABLgAECgEJBAALAAAAAA==.',
Im='Imasteward:BAAALgAECgUJBgABLgAFFAMJAwALAAAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgYJDgAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ju='Junii:BAAALgAECgIJAgABLgAECgUJBQALAAAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEgALAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx1/DgBiAAAeAAIJ7A+mJAB+AAABAAIJBSR/DgBiAAAuAAQKfywAAwEACQkSJpIAAFQDAAEACQkSJpIAAFQDAB4AAQmhFVpnAD8AAAEuAAUUBwkbABgAZyEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.Kimk:BAAALgAECgYJCQAAAA==.',
Kl='Klhank:BAAALgAECgYJBwAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIKAAkJjSM1BQDIAgAKAAkJjSM1BQDIAgAAAA==.',
Ku='Kuzu:BAAALgAECgMJAwAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIbAAcJkw2FRAD6AAAbAAcJkw2FRAD6AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwALAAAAAA==.Laizee:BAABLgAECn8qAAMPAAkJtgW4YwAwAQAPAAkJtgW4YwAwAQAJAAEJ4gN3twAlAAAAAA==.Latrice:BAABLgAECn8lAAIDAAkJ6x0HMQA8AgADAAkJ6x0HMQA8AgAAAA==.Laveyan:BAECLgAFFH8GAAIRAAMJNhF2ZADEAAARAAMJNhF2ZADEAAAuAAQKfxQAAhEACAm5GoglADgCABEACAm5GoglADgCAAEuAAUUBQkRAAUApSIA.',
Ld='Ldshunter:BAAALgAECgEJAgABLgAECgEJBAALAAAAAA==.',
Li='Liquidnitro:BAAALgAECgYJBgAAAA==.',
Lo='Loki:BAABLgAECn8oAAITAAgJuxnXCwAaAgATAAgJuxnXCwAaAgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn89AAIRAAgJuhkQAgA7AQARAAgJuhkQAgA7AQAAAA==.',
Ma='Mansamusa:BAAALgAECgcJCwAAAA==.Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIWAAkJPRqSDwCrAgAWAAkJPRqSDwCrAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJQQAVAO0gAA==.',
Me='Melander:BAACLgAFFH8IAAIKAAQJrhomDwA+AQAKAAQJrhomDwA+AQAuAAQKfy4AAwoACQnDG6IGAMQCAAoACQnDG6IGAMQCAB8ABgk4FRcyAIMBAAAA.Melandruid:BAAALgAECgEJAQABLgAFFAQJCAAKAK4aAA==.',
Mh='Mhoram:BAAALgAECgYJCAAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAUJDwASAIMXAA==.Missld:BAAALgAECgEJBAAAAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgMJBAAAAA==.Monkraga:BAAALgAECgUJBQAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.Mordracon:BAAALgAECgkJCgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAICAAIJeSBxOACqAAACAAIJeSBxOACqAAAuAAQKfyQAAgIACAl7JEshAIMCAAIACAl7JEshAIMCAAAA.',
My='Myth:BAACLgAFFH8GAAIZAAMJbhmXdwDrAAAZAAMJbhmXdwDrAAAuAAQKfyAAAhkACAkPG+4tAGECABkACAkPG+4tAGECAAEuAAUUBAkWABkATxcA.',
Na='Nachotaco:BAAALgAECgkJCQAAAA==.Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAABLgAECn8iAAMKAAgJ2huxCwAyAgAKAAgJMRuxCwAyAgAfAAYJEBVeQABDAQABLgAFFAQJCAAKAK4aAA==.Nerzhuul:BAACLgAFFH8PAAISAAUJgxcbCQAoAQASAAUJgxcbCQAoAQAuAAQKfzIAAhIACQmGIIADAM0CABIACQmGIIADAM0CAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQALAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIEAAgJAxxcGQBIAgAEAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIZAAYJFxUMxgBbAQAZAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAACLgAFFH8FAAMbAAQJWw4mNgCmAAAbAAMJpwkmNgCmAAAgAAEJ7wXhdgAvAAAuAAQKfyAAAyAACAkEG5ktAPABACAABgm4HZktAPABABsACAlxEGkwAIUBAAAA.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
['Où']='Oùtcast:BAAALgADCgQJBAAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pamnais:BAAALgAECgEJAwABLgAECgEJBAALAAAAAA==.Pandastryker:BAABLgAFFH8HAAMYAAMJUBGBNwDIAAAYAAMJUBGBNwDIAAAXAAEJywKnSgApAAABLgAFFAcJFwAFAEMVAA==.Patrickstâr:BAAALgAECgIJAgAAAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8NAAIKAAMJUgRqBQBnAAAKAAMJUgRqBQBnAAAuAAQKfyEAAgoACQlyDDscAFUBAAoACQlyDDscAFUBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgAECgIJAgABLgAFFAcJFwAFAEMVAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAACLgAFFH8HAAMVAAMJaR/mFgAHAQAVAAMJaR/mFgAHAQAMAAEJyhcxSQBHAAAuAAQKfyoABBUACAkTH+ENAIgCABUACAkTH+ENAIgCAA0ABgmtGZ4tAGwBAAwAAQk1Fhh2ADoAAAAA.Raggnarr:BAACLgAFFH8WAAIfAAcJQR52DQCbAQAfAAcJQR52DQCbAQAuAAQKfzkAAh8ACQmpJUUEACEDAB8ACQmpJUUEACEDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8cAAIVAAUJfyKfBgDuAQAVAAUJfyKfBgDuAQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AgAYAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgAECgEJAQAAAA==.',
Ri='Rimlin:BAAALgADCgMJAwAAAA==.Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgQJBQAAAA==.',
Ry='Rythevia:BAABLgAECn9HAAMUAAkJnRhAFwAeAgAUAAgJDRdAFwAeAgAhAAgJ6BL0EgCzAQAAAA==.',
Sa='Sanctified:BAABLgAECn8bAAIEAAgJNRSrJwDNAQAEAAgJNRSrJwDNAQAAAA==.Saphíra:BAEALgAECgUJCgABLgAFFAUJEQAFAKUiAA==.Satanick:BAAALgADCgEJAQABLgAFFAUJDwASAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAUJDwASAIMXAA==.',
Sc='Schwii:BAAALgAECgEJAgABLgAFFAQJBQAbAFsOAA==.',
Se='Seraph:BAABLgAECn8qAAIVAAkJFxT6HQDVAQAVAAkJFxT6HQDVAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shadowwes:BAAALgAECgUJCQAAAA==.Shoc:BAAALgADCgIJAgAAAA==.Shotsforbots:BAAALgAFFAMJAwAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAFFAQJCAAKAK4aAA==.',
So='Sojourner:BAABLgAECn8vAAMEAAgJXxyzAADQAQAEAAgJXxyzAADQAQADAAUJFg6EwwADAQAAAA==.',
Sp='Spoonzilla:BAABLgAECn8jAAIbAAYJvxJdAgDeAAAbAAYJvxJdAgDeAAAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIRAAgJ+R6hGgC0AgARAAgJ+R6hGgC0AgABLgAECgkJEQALAAAAAA==.',
Su='Superfire:BAAALgADCgUJBQAAAA==.Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8jAAMgAAkJsx7kLAD7AQAgAAkJsx7kLAD7AQAbAAcJWBJUOAAzAQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Sy='Sylphiett:BAAALgAFFAIJAgABLgAFFAUJDwAUAAMJAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn85AAIaAAkJDSAtAwCmAgAaAAkJDSAtAwCmAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8nAAIgAAkJqQ5lPwCUAQAgAAkJqQ5lPwCUAQAAAA==.Thrasherzs:BAAALgAECgEJBAAAAA==.Thy:BAAALgAECgMJBgAAAA==.',
Ti='Tinydragon:BAABLgAFFH8PAAIUAAUJAwlQOwDaAAAUAAUJAwlQOwDaAAAAAA==.Tinyvoid:BAACLgAFFH8GAAIRAAMJewrzbACxAAARAAMJewrzbACxAAAuAAQKfyoAAhEACQkmGu4gAE8CABEACQkmGu4gAE8CAAEuAAUUBQkPABQAAwkA.Tirok:BAAALgADCgIJAgAAAA==.',
To='Togdumburz:BAACLgAFFH8PAAIdAAUJuRMgVQAcAQAdAAUJuRMgVQAcAQAuAAQKfyUAAx0ACQkhGponAD4CAB0ACQkhGponAD4CAA4AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Tr='Travis:BAAALgADCgUJAgAAAA==.',
Ty='Typhoid:BAAALgADCgUJBQAAAA==.Typhon:BAAALgAECgEJAQAAAA==.',
Ud='Udderlymad:BAABLgAFFH8FAAICAAMJpworGQBzAAACAAMJpworGQBzAAAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8bAAMYAAcJZyEpBgAyAgAYAAYJZyEpBgAyAgAWAAQJsg03MgDoAAAuAAQKfx4ABBgACAnkIeQJAOsCABgACAnPIeQJAOsCABYAAwkoHa1zAL8AABcAAgnJFCpcAKAAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAFFAQJCAAKAK4aAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIQAiADUTAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMKAAQJoxqGFAD9AAAKAAMJvSGGFAD9AAAjAAEJUwVrSAAzAAAuAAQKfxkAAwoACAmbIisMACsCAAoABwknJCsMACsCACMABgkSG+ApACUBAAEuAAUUBwkbABgAZyEA.',
Vi='Vietsham:BAABLgAECn8zAAIPAAkJShw3FACqAgAPAAkJShw3FACqAgAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAABLgAECn8aAAIUAAkJMQvDAQDvAAAUAAkJMQvDAQDvAAABLgAFFAQJDAAHAM4KAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8XAAIFAAcJQxVVEgBmAQAFAAcJQxVVEgBmAQAuAAQKfyQAAgUACQk9HaoJAHgCAAUACQk9HaoJAHgCAAAA.',
Vy='Vynch:BAAALgAECgMJAwABLgAFFAQJCAAKAK4aAA==.Vynstan:BAAALgAFFAIJAgAAAA==.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgYJBgABLgAFFAQJBQAbAFsOAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.Wooloolooloo:BAAALgAECgMJBAAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJBAALAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn9BAAMVAAkJ7SA5BwD9AgAVAAkJ7SA5BwD9AgAMAAcJBBR5JQCkAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8TAAIEAAcJKBzrCgAHAgAEAAcJKBzrCgAHAgAuAAQKfyIAAwQACQmGIwwGAC0DAAQACQmGIwwGAC0DAAMAAQkAAW/UARAAAAAA.',
Yo='You:BAAALgADCgMJAwABLgAFFAQJCAAQAKgQAA==.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8mAAIjAAgJmyMzAgCmAgAjAAgJmyMzAgCmAgAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgUJEwAAAA==.',
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
