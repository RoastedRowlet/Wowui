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

local lookup = {'DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','Shaman-Elemental','Warrior-Protection','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Devourer','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Hunter-Marksmanship','Druid-Balance','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Warrior-Fury','Druid-Restoration','Evoker-Devastation','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-06-14',data={Ab='Abelle:BAAALgAECgUJDgAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgcJEwABLgAECgkJGwABAIwdAA==.Anonymoose:BAAALgAECgYJDQABLgAFFAMJAwACAAAAAA==.Antrus:BAAALgAECgkJDgAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgAECgIJAgAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8oAAIDAAkJ1R5OFADHAgADAAkJ1R5OFADHAgAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAFFAEJAQABLgAFFAcJEwAEACgcAA==.',
Au='Auhsoj:BAAALgAECgEJAgABLgAFFAcJFgAFAEMVAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIGAAgJfBDjIwBzAQAGAAgJfBDjIwBzAQAAAA==.Banality:BAAALgAECgUJCAAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8MAAIHAAQJzgrrGgCyAAAHAAQJzgrrGgCyAAAuAAQKfzAAAwcACAlXGJ4QANwBAAcACAlXGJ4QANwBAAgABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIJAAcJ+BcYMACfAQAJAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAgAAAA==.Breadbull:BAAALgAECgUJCAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAMJCwAKAFIEAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQACAAAAAA==.',
Bu='Bubbies:BAABLgAECn8iAAMLAAkJnhS+GgD5AQALAAkJnhS+GgD5AQAMAAUJewu4QwD/AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIDAAkJLhJAagCZAQADAAkJLhJAagCZAQAAAA==.Chiste:BAACLgAFFH8FAAINAAIJkgZxFgB+AAANAAIJkgZxFgB+AAAuAAQKfyIAAg0ACAmjDmwPAEYBAA0ACAmjDmwPAEYBAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwACAAAAAA==.Coredellion:BAAALgADCgkJFgAAAA==.Corypheus:BAAALgADCggJEAAAAA==.Covak:BAAALgAFFAIJAgAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn86AAIOAAkJoRv9EADFAgAOAAkJoRv9EADFAgABLgAFFAgJHgAPAPYSAA==.Dannica:BAAALgAECgkJEQAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAIMAAYJxw2ORQD4AAAMAAYJxw2ORQD4AAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAABLgAECn8YAAMBAAYJFxJmGADaAAABAAYJFxJmGADaAAAQAAYJUQWQrgCwAAABLgAFFAcJFgAFAEMVAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8kAAIDAAkJnRPIQQAAAgADAAkJnRPIQQAAAgAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAUJDwARAIMXAA==.Donut:BAACLgAFFH8FAAISAAMJRgyzqgDFAAASAAMJRgyzqgDFAAAuAAQKfxwAAhIACQk+FII8AA0CABIACQk+FII8AA0CAAEuAAQKBwkWAAgASg8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8NAAMTAAMJThtKGgDqAAATAAMJThtKGgDqAAAUAAEJqQFUagAuAAAuAAQKfz0AAxMACQmkIhgCAFwDABMACQmkIhgCAFwDABQABwleFAwxAHEBAAAA.Elizalynn:BAABLgAECn8nAAIVAAkJyRGpIAC6AQAVAAkJyRGpIAC6AQAAAA==.',
Ev='Eveycakes:BAACLgAFFH8IAAMLAAQJfgnkLwDNAAALAAQJWQTkLwDNAAAVAAEJeBotNABBAAAuAAQKfxsAAxUABgllH4waAPMBABUABgllH4waAPMBAAsABglbCj5JAN8AAAEuAAUUBwkTAAQAKBwA.',
Fa='Father:BAAALgADCgUJBQAAAA==.',
Fe='Fengshui:BAABLgAECn8WAAIJAAkJrxEfJwCxAQAJAAkJrxEfJwCxAQAAAA==.Ferritin:BAABLgAECn8yAAIFAAkJESTcAQBjAwAFAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8TAAIWAAYJ+RnKFgC8AQAWAAYJ+RnKFgC8AQAuAAQKf0QABBYACQmEG/AOAGgCABYACQmEG/AOAGgCABcACQkNHL4RADMCABgABwkhGT4dALkBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIZAAkJAB38JQCBAgAZAAkJAB38JQCBAgAAAA==.Foxthisup:BAAALgAFFAEJAwABLgAFFAMJAwACAAAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECggJJgAaAOgZAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAgJHgAPAPYSAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQACAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJDQAAAA==.Gruff:BAAALgAECgYJBgAAAA==.Grultock:BAABLgAECn8fAAIKAAgJ7RfYDwDnAQAKAAgJ7RfYDwDnAQAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8kAAIOAAkJAR2zDwDRAgAOAAkJAR2zDwDRAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgQJBQABLgAFFAIJAgACAAAAAA==.',
Ha='Hapday:BAAALgAECgQJBAAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgUJDQAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAABLgAECn8bAAIbAAgJ6hJ4IwCrAQAbAAgJ6hJ4IwCrAQABLgAFFAQJCAAPAKgQAA==.Hockeyhunter:BAACLgAFFH8IAAIPAAQJqBBwQAAoAQAPAAQJqBBwQAAoAQAuAAQKf0gAAg8ACQnIHVcOANwCAA8ACQnIHVcOANwCAAAA.Hockeylockz:BAABLgAECn8bAAMcAAYJrAtAHADZAAAcAAUJ2w1AHADZAAAdAAUJIAZ22gCjAAABLgAFFAQJCAAPAKgQAA==.Hockeysticks:BAAALgADCgMJAwABLgAFFAQJCAAPAKgQAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooky:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgMJCAABLgAECgkJIgAZANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8jAAMPAAgJ6BhHPwDiAQAPAAgJ6BhHPwDiAQAaAAEJMAk7QQAnAAABLgAFFAQJDAAHAM4KAA==.',
['Hè']='Hèxen:BAAALgAECgQJBwAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8mAAMaAAgJ6Bk2CQDhAQAaAAgJNxc2CQDhAQAPAAMJQx4wxwC1AAAAAA==.',
Ig='Igneel:BAAALgAECgEJAwABLgAECgEJBAACAAAAAA==.',
Im='Imasteward:BAAALgAECgUJBgABLgAFFAIJAgACAAAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgYJDgAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ju='Junii:BAAALgAECgIJAgAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEgACAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx0QDgBjAAAeAAIJ7A+DIwB+AAABAAIJBSQQDgBjAAAuAAQKfywAAwEACQkSJo8AAFQDAAEACQkSJo8AAFQDAB4AAQmhFXZlAD8AAAEuAAUUBgkXABgAZyEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIKAAkJjSMaBQDJAgAKAAkJjSMaBQDJAgAAAA==.',
Ku='Kuzu:BAAALgAECgMJAwAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIbAAcJkw3LQwD6AAAbAAcJkw3LQwD6AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwACAAAAAA==.Laizee:BAABLgAECn8qAAMOAAkJtgWDYgAwAQAOAAkJtgWDYgAwAQAJAAEJ4gPWtAAlAAAAAA==.Latrice:BAABLgAECn8lAAIDAAkJ6x15MAA9AgADAAkJ6x15MAA9AgAAAA==.Laveyan:BAEBLgAECn8UAAIQAAgJuRoUJQA4AgAQAAgJuRoUJQA4AgABLgAFFAUJEQAFAKUiAA==.',
Ld='Ldshunter:BAAALgAECgEJAgABLgAECgEJBAACAAAAAA==.',
Li='Liquidnitro:BAAALgAECgYJBgAAAA==.',
Lo='Loki:BAABLgAECn8nAAITAAcJnBq7CwAaAgATAAcJnBq7CwAaAgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn82AAIQAAgJVhibMwD1AQAQAAgJVhibMwD1AQAAAA==.',
Ma='Mansamusa:BAAALgAECgcJCwAAAA==.Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIWAAkJPRpcDwCqAgAWAAkJPRpcDwCqAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJQAAVAO0gAA==.',
Me='Melander:BAACLgAFFH8IAAIKAAQJrhqADgBAAQAKAAQJrhqADgBAAQAuAAQKfy4AAwoACQnDG6IGAMQCAAoACQnDG6IGAMQCAB8ABgk4FaExAIYBAAAA.Melandruid:BAAALgAECgEJAQABLgAFFAQJCAAKAK4aAA==.',
Mh='Mhoram:BAAALgAECgYJCAAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAUJDwARAIMXAA==.Missld:BAAALgAECgEJBAAAAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Monkraga:BAAALgAECgUJBQAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.Mordracon:BAAALgAECggJCAAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAISAAIJeSBxOACqAAASAAIJeSBxOACqAAAuAAQKfyQAAhIACAl7JNUgAIMCABIACAl7JNUgAIMCAAAA.',
My='Myth:BAACLgAFFH8GAAIZAAMJbhlDdgDyAAAZAAMJbhlDdgDyAAAuAAQKfx0AAhkACAkPG1otAGICABkACAkPG1otAGICAAEuAAUUBAkWABkATxcA.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAABLgAECn8gAAMKAAgJoBquEADcAQAKAAcJhxquEADcAQAfAAYJEBXnPwBFAQABLgAFFAQJCAAKAK4aAA==.Nerzhuul:BAACLgAFFH8PAAIRAAUJgxfsCAArAQARAAUJgxfsCAArAQAuAAQKfzIAAhEACQmGIG0DAM4CABEACQmGIG0DAM4CAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQACAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIEAAgJAxxcGQBIAgAEAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIZAAYJFxUMxgBbAQAZAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAACLgAFFH8FAAMbAAQJWw4WNQCmAAAbAAMJpwkWNQCmAAAgAAEJ7wUDdQAvAAAuAAQKfyAAAyAACAkEG0QtAPABACAABgm4HUQtAPABABsACAlxEGkwAIUBAAAA.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
['Où']='Oùtcast:BAAALgADCgQJBAAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pamnais:BAAALgAECgEJAwABLgAECgEJBAACAAAAAA==.Pandastryker:BAABLgAFFH8GAAMYAAMJHA0/OgC6AAAYAAMJHA0/OgC6AAAXAAEJywISSQApAAABLgAFFAcJFgAFAEMVAA==.Patrickstâr:BAAALgADCgUJBQAAAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8LAAIKAAMJUgTMIwB1AAAKAAMJUgTMIwB1AAAuAAQKfyEAAgoACQlyDPQbAFQBAAoACQlyDPQbAFQBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgAECgIJAgABLgAFFAcJFgAFAEMVAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAACLgAFFH8HAAMVAAMJaR9IFgAJAQAVAAMJaR9IFgAJAQALAAEJyhdpRwBHAAAuAAQKfyoABBUACAkTH7oNAIgCABUACAkTH7oNAIgCAAwABgmtGX0tAGwBAAsAAQk1FmN0ADoAAAAA.Raggnarr:BAACLgAFFH8VAAIfAAYJ/h3PDACbAQAfAAYJ/h3PDACbAQAuAAQKfzYAAh8ACQmJJa4EABkDAB8ACQmJJa4EABkDAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8cAAIVAAUJfyIlBgDwAQAVAAUJfyIlBgDwAQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AgAYAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgAECgEJAQAAAA==.',
Ri='Rimlin:BAAALgADCgMJAwAAAA==.Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgQJBQAAAA==.',
Ry='Rythevia:BAABLgAECn9HAAMUAAkJnRglFwAeAgAUAAgJDRclFwAeAgAhAAgJ6BL0EgCzAQAAAA==.',
Sa='Sanctified:BAABLgAECn8bAAIEAAgJNRRWJwDOAQAEAAgJNRRWJwDOAQAAAA==.Saphíra:BAEALgAECgUJCgABLgAFFAUJEQAFAKUiAA==.Satanick:BAAALgADCgEJAQABLgAFFAUJDwARAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAUJDwARAIMXAA==.',
Sc='Schwii:BAAALgAECgEJAgABLgAFFAQJBQAbAFsOAA==.',
Se='Seraph:BAABLgAECn8qAAIVAAkJFxSmHQDVAQAVAAkJFxSmHQDVAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shadowwes:BAAALgAECgQJBAAAAA==.Shoc:BAAALgADCgIJAgAAAA==.Shotsforbots:BAAALgAFFAIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAFFAQJCAAKAK4aAA==.',
So='Sojourner:BAABLgAECn8qAAMEAAgJ4BkhFgBZAgAEAAgJ4BkhFgBZAgADAAUJFg5vwgADAQAAAA==.',
Sp='Spoonzilla:BAABLgAECn8eAAIbAAYJFxJ0PQAXAQAbAAYJFxJ0PQAXAQAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIQAAgJ+R6hGgC0AgAQAAgJ+R6hGgC0AgABLgAECgkJEQACAAAAAA==.',
Su='Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8jAAMgAAkJsx7kLAD7AQAgAAkJsx7kLAD7AQAbAAcJWBK9NwAyAQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Sy='Sylphiett:BAAALgAECgQJBAABLgAFFAUJDwAUAAMJAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn85AAIaAAkJDSAfAwCmAgAaAAkJDSAfAwCmAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8nAAIgAAkJqQ4MPwCUAQAgAAkJqQ4MPwCUAQAAAA==.Thrasherzs:BAAALgAECgEJBAAAAA==.Thy:BAAALgAECgMJBgAAAA==.',
Ti='Tinydragon:BAABLgAFFH8PAAIUAAUJAwnYOQDbAAAUAAUJAwnYOQDbAAAAAA==.Tinyvoid:BAACLgAFFH8GAAIQAAMJewrYagCxAAAQAAMJewrYagCxAAAuAAQKfyoAAhAACQkmGpMgAE8CABAACQkmGpMgAE8CAAEuAAUUBQkPABQAAwkA.',
To='Togdumburz:BAACLgAFFH8PAAIdAAUJuROWUwAcAQAdAAUJuROWUwAcAQAuAAQKfyUAAx0ACQkhGiQnAEACAB0ACQkhGiQnAEACAA0AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Tr='Travis:BAAALgADCgUJAgAAAA==.',
Ty='Typhoid:BAAALgADCgUJBQAAAA==.Typhon:BAAALgAECgEJAQAAAA==.',
Ud='Udderlymad:BAAALgAFFAMJAwAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8XAAIYAAYJZyGgBQA0AgAYAAYJZyGgBQA0AgAuAAQKfx4ABBgACAnkIeQJAOsCABgACAnPIeQJAOsCABYAAwkoHSlxAL8AABcAAgnJFCpcAKAAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAFFAQJCAAKAK4aAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIQAiADUTAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMKAAQJoxrMEwAAAQAKAAMJvSHMEwAAAQAjAAEJUwWTRgAzAAAuAAQKfxkAAwoACAmbIvkLACsCAAoABwknJPkLACsCACMABgkSG0opACUBAAEuAAUUBgkXABgAZyEA.',
Vi='Vietsham:BAABLgAECn8vAAIOAAkJJxr0EwCqAgAOAAkJJxr0EwCqAgAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAABLgAECn8UAAIUAAgJjgvKOQBDAQAUAAgJjgvKOQBDAQABLgAFFAQJDAAHAM4KAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8WAAIFAAcJQxVkEQBrAQAFAAcJQxVkEQBrAQAuAAQKfyQAAgUACQk9HXwJAHoCAAUACQk9HXwJAHoCAAAA.',
Vy='Vynch:BAAALgAECgMJAwABLgAFFAQJCAAKAK4aAA==.Vynstan:BAAALgADCgEJAQAAAA==.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAFFAQJBQAbAFsOAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.Wooloolooloo:BAAALgAECgMJBAAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJBAACAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn9AAAMVAAkJ7SAcBwD9AgAVAAkJ7SAcBwD9AgALAAcJBBQkJQClAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8TAAIEAAcJKBxDCgAIAgAEAAcJKBxDCgAIAgAuAAQKfyIAAwQACQmGI+wFAC8DAAQACQmGI+wFAC8DAAMAAQkAAXbOARAAAAAA.',
Yo='You:BAAALgADCgMJAwABLgAFFAQJCAAPAKgQAA==.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8mAAIjAAgJmyPrAQCqAgAjAAgJmyPrAQCqAgAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
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
