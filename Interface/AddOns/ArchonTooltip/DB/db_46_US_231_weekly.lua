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
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abelle:BAAALgAECgUJDgAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgMJBQAAAA==.',
Al='Aldduin:BAAALgADCgYJBgAAAA==.Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgAECgYJDAABLgAECgkJGwABAIwdAA==.Anonymoose:BAAALgAECgYJDQABLgAFFAEJAwACAAAAAA==.Antrus:BAAALgAECgkJDgAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arx:BAAALgAECgIJAgAAAA==.Arxracc:BAAALgADCgYJBgAAAA==.Arykiel:BAABLgAECn8oAAIDAAkJ1R7NEgDKAgADAAkJ1R7NEgDKAgAAAA==.',
As='Asthar:BAAALgADCgkJDgAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAcJEwAEACgcAA==.',
Au='Auhsoj:BAAALgAECgEJAQABLgAFFAcJFgAFAEMVAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgAECgEJAQAAAA==.Ballisticboo:BAABLgAECn8ZAAIGAAgJfBCTIgBzAQAGAAgJfBCTIgBzAQAAAA==.Banality:BAAALgAECgQJBQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAACLgAFFH8JAAIHAAQJ7wlOGAC0AAAHAAQJ7wlOGAC0AAAuAAQKfzAAAwcACAlXGJkPAN0BAAcACAlXGJkPAN0BAAgABQl5DlcdAP8AAAAA.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIJAAcJ+BcYMACfAQAJAAcJ+BcYMACfAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadadin:BAAALgAECgEJAgAAAA==.Breadbull:BAAALgAECgUJCAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJCAAKAEYFAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgcJDwABLgAECgkJEQACAAAAAA==.',
Bu='Bubbies:BAABLgAECn8iAAMLAAkJnhRpGQD6AQALAAkJnhRpGQD6AQAMAAUJewtDQgD/AAAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAABLgAECn8dAAIDAAkJLhK/ZQCaAQADAAkJLhK/ZQCaAQAAAA==.Chiste:BAACLgAFFH8FAAINAAIJkgYhFQB+AAANAAIJkgYhFQB+AAAuAAQKfyIAAg0ACAmjDo0OAEgBAA0ACAmjDo0OAEgBAAAA.',
Co='Cobrah:BAAALgADCggJDQABLgAECgYJCwACAAAAAA==.Coredellion:BAAALgADCgYJEQAAAA==.Corypheus:BAAALgADCggJEAAAAA==.Covak:BAAALgAECggJCAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn86AAIOAAkJoRsMEADGAgAOAAkJoRsMEADGAgABLgAFFAgJHgAPAPYSAA==.Dannica:BAAALgAECgkJEQAAAA==.Dantedragon:BAAALgAECgQJBQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAABLgAECn8WAAIMAAYJxw0WQgD/AAAMAAYJxw0WQgD/AAAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAABLgAECn8YAAMBAAYJFxJrFwDaAAABAAYJFxJrFwDaAAAQAAYJUQWQrgCwAAABLgAFFAcJFgAFAEMVAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8kAAIDAAkJnROBPgABAgADAAkJnROBPgABAgAAAA==.',
Do='Dobledas:BAAALgAECggJDgAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAUJDwARAIMXAA==.Donut:BAACLgAFFH8FAAISAAMJRgxlngDNAAASAAMJRgxlngDNAAAuAAQKfxwAAhIACQk+FNc5ABICABIACQk+FNc5ABICAAEuAAQKBwkWAAgASg8A.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgcJCgAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAACLgAFFH8MAAMTAAMJThsnGQDuAAATAAMJThsnGQDuAAAUAAEJqQF9ZQAxAAAuAAQKfz0AAxMACQmkIvoBAGADABMACQmkIvoBAGADABQABwleFDkvAHIBAAAA.Elizalynn:BAABLgAECn8nAAIVAAkJyRFjHwC7AQAVAAkJyRFjHwC7AQAAAA==.',
Ev='Eveycakes:BAACLgAFFH8IAAMLAAQJfgkvLADQAAALAAQJWQQvLADQAAAVAAEJeBorMQBCAAAuAAQKfxsAAxUABgllH0AZAPYBABUABgllH0AZAPYBAAsABglbCslFAOIAAAEuAAUUBwkTAAQAKBwA.',
Fe='Fengshui:BAABLgAECn8WAAIJAAkJrxFXJQCxAQAJAAkJrxFXJQCxAQAAAA==.Ferritin:BAABLgAECn8yAAIFAAkJESTcAQBjAwAFAAkJESTcAQBjAwAAAA==.Fester:BAAALgAECgEJBAAAAA==.',
Fi='Fish:BAAALgAECgQJBwAAAA==.Fishguts:BAACLgAFFH8TAAIWAAYJ+RldEwDCAQAWAAYJ+RldEwDCAQAuAAQKf0QABBYACQmEG/AOAGgCABYACQmEG/AOAGgCABcACQkNHLYQADcCABgABwkhGVccALsBAAAA.',
Fo='Focaccia:BAABLgAECn8dAAIZAAkJAB3TIwCHAgAZAAkJAB3TIwCHAgAAAA==.Foxthisup:BAAALgAFFAEJAwAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgcJIAAaAL4WAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAgJHgAPAPYSAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECgkJEQACAAAAAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgAECgYJDQAAAA==.Gruff:BAAALgAECgYJBgAAAA==.Grultock:BAABLgAECn8YAAIKAAcJ6ReTFACeAQAKAAcJ6ReTFACeAQAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8kAAIOAAkJAR3jDgDSAgAOAAkJAR3jDgDSAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgQJBQABLgAECggJCAACAAAAAA==.',
Ha='Hapday:BAAALgAECgMJAwAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.Heymage:BAAALgAECgUJCgAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAABLgAECn8UAAIbAAgJDQ/uLQBdAQAbAAgJDQ/uLQBdAQABLgAFFAQJBgAPAEwPAA==.Hockeyhunter:BAACLgAFFH8GAAIPAAQJTA8vPAAoAQAPAAQJTA8vPAAoAQAuAAQKfz8AAg8ACQmDHGwTAK0CAA8ACQmDHGwTAK0CAAAA.Hockeylockz:BAABLgAECn8XAAMcAAYJrAvuGgDXAAAcAAUJ2w3uGgDXAAAdAAUJxgW11wCgAAABLgAFFAQJBgAPAEwPAA==.Hockeysticks:BAAALgADCgMJAwABLgAFFAQJBgAPAEwPAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBQAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgMJCAABLgAECgkJIgAZANAPAA==.',
Hu='Hunthunthunt:BAABLgAECn8jAAMPAAgJ6BiIOwDnAQAPAAgJ6BiIOwDnAQAaAAEJMAnBPgAnAAABLgAFFAQJCQAHAO8JAA==.',
['Hè']='Hèxen:BAAALgAECgQJBwAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAABLgAECn8gAAIaAAcJvhY1DACUAQAaAAcJvhY1DACUAQAAAA==.',
Ig='Igneel:BAAALgAECgEJAgABLgAECgEJAwACAAAAAA==.',
Im='Imasteward:BAAALgAECgUJBgABLgAECggJCAACAAAAAA==.',
In='Indigø:BAAALgADCgEJAQAAAA==.',
Io='Ioch:BAAALgADCgYJBgAAAA==.',
Ja='Jasmireon:BAAALgAECgYJBgAAAA==.',
Je='Jedem:BAAALgADCgYJDgAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ju='Junii:BAAALgAECgIJAgAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECgkJEgACAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJCQAAAA==.Kazum:BAAALgAECgEJAwAAAA==.',
Ke='Keralan:BAACLgAFFH8IAAMBAAMJbx30DABjAAAeAAIJ7A9GIAB+AAABAAIJBST0DABjAAAuAAQKfywAAwEACQkSJnMAAFYDAAEACQkSJnMAAFYDAB4AAQmhFSVgAD8AAAEuAAUUBgkXABgAZyEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8jAAIKAAkJjSOqBADPAgAKAAkJjSOqBADPAgAAAA==.',
Ku='Kuzu:BAAALgAECgMJAwAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIbAAcJkw1QQQD7AAAbAAcJkw1QQQD7AAAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgYJCwACAAAAAA==.Laizee:BAABLgAECn8qAAMOAAkJtgWsXgAyAQAOAAkJtgWsXgAyAQAJAAEJ4gPbrAAlAAAAAA==.Latrice:BAABLgAECn8lAAIDAAkJ6x0ILgA/AgADAAkJ6x0ILgA/AgAAAA==.Laveyan:BAEBLgAECn8UAAIQAAgJuRqaIwA4AgAQAAgJuRqaIwA4AgABLgAFFAUJEQAFAKUiAA==.',
Ld='Ldshunter:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
Li='Liquidnitro:BAAALgAECgYJBgAAAA==.',
Lo='Loki:BAABLgAECn8jAAITAAcJnBqFCwAcAgATAAcJnBqFCwAcAgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8xAAIQAAgJVhiuMQD1AQAQAAgJVhiuMQD1AQAAAA==.',
Ma='Mansamusa:BAAALgAECgcJBwAAAA==.Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8jAAIWAAkJPRp7DgCpAgAWAAkJPRp7DgCpAgAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJQAAVAO0gAA==.',
Me='Melander:BAACLgAFFH8GAAIKAAQJrho/DQBIAQAKAAQJrho/DQBIAQAuAAQKfywAAwoACQnDG6IGAMQCAAoACQnDG6IGAMQCAB8ABAlTFT1PAAQBAAAA.Melandruid:BAAALgAECgEJAQABLgAFFAQJBgAKAK4aAA==.',
Mh='Mhoram:BAAALgAECgYJBwAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAUJDwARAIMXAA==.Missld:BAAALgAECgEJAwAAAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Monkraga:BAAALgAECgUJBQAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.Mordracon:BAAALgAECgIJAgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAISAAIJeSBxOACqAAASAAIJeSBxOACqAAAuAAQKfyQAAhIACAl7JBIfAIcCABIACAl7JBIfAIcCAAAA.',
My='Myth:BAACLgAFFH8GAAIZAAMJbhncbwD3AAAZAAMJbhncbwD3AAAuAAQKfxcAAhkACAnUGus1ADsCABkACAnUGus1ADsCAAEuAAUUBAkVABkATxcA.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nelflander:BAABLgAECn8fAAMKAAgJoBr3DwDfAQAKAAcJhxr3DwDfAQAfAAYJEBXgPABLAQABLgAFFAQJBgAKAK4aAA==.Nerzhuul:BAACLgAFFH8PAAIRAAUJgxfDBwAyAQARAAUJgxfDBwAyAQAuAAQKfzIAAhEACQmGICYDANECABEACQmGICYDANECAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noobtank:BAAALgAECgEJAQABLgAECgkJEQACAAAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIEAAgJAxxcGQBIAgAEAAgJAxxcGQBIAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIZAAYJFxUMxgBbAQAZAAYJFxUMxgBbAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8gAAMgAAgJBBs6LADwAQAgAAYJuB06LADwAQAbAAgJcRBpMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
['Où']='Oùtcast:BAAALgADCgQJBAAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pamnais:BAAALgAECgEJAgABLgAECgEJAwACAAAAAA==.Pandastryker:BAAALgAFFAMJBAABLgAFFAcJFgAFAEMVAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAACLgAFFH8IAAIKAAIJRgVuJABgAAAKAAIJRgVuJABgAAAuAAQKfyAAAgoACQlyDMcaAFcBAAoACQlyDMcaAFcBAAAA.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgcJDgAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
Py='Pyrostryker:BAAALgAECgIJAgABLgAFFAcJFgAFAEMVAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8mAAQVAAgJEx/iDACMAgAVAAgJEx/iDACMAgAMAAYJrRmrLQBkAQALAAEJNRbTbgA6AAABLgAFFAIJCwAOAHgVAA==.Raggnarr:BAACLgAFFH8VAAIfAAYJ/h0WCwCcAQAfAAYJ/h0WCwCcAQAuAAQKfzYAAh8ACQmJJTQEAB0DAB8ACQmJJTQEAB0DAAAA.Raina:BAAALgAECggJCQAAAA==.Rainesagé:BAABLgAFFH8XAAIVAAUJSh6yBwC8AQAVAAUJSh6yBwC8AQAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBsDQC8AgAYAAgJ1CBsDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Rimlin:BAAALgADCgMJAwAAAA==.Riqitan:BAAALgAECgYJCwAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgQJBQAAAA==.',
Ry='Rythevia:BAABLgAECn9HAAMUAAkJnRiLFgAdAgAUAAgJDReLFgAdAgAhAAgJ6BL0EgCzAQAAAA==.',
Sa='Sanctified:BAABLgAECn8aAAIEAAgJNRQZJgDPAQAEAAgJNRQZJgDPAQAAAA==.Saphíra:BAEALgAECgUJCgABLgAFFAUJEQAFAKUiAA==.Satanick:BAAALgADCgEJAQABLgAFFAUJDwARAIMXAA==.Satanickk:BAAALgAECgUJBQABLgAFFAUJDwARAIMXAA==.',
Sc='Schwii:BAAALgAECgEJAQABLgAECggJIAAgAAQbAA==.',
Se='Seraph:BAABLgAECn8qAAIVAAkJFxRvHADWAQAVAAkJFxRvHADWAQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shadowwes:BAAALgAECgQJBAAAAA==.Shoc:BAAALgADCgIJAgAAAA==.Shotsforbots:BAAALgAECggJCAAAAA==.',
Sj='Sjoralina:BAAALgAECgMJAwAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.Slyphoïd:BAAALgADCgcJDwAAAA==.',
Sn='Snikit:BAAALgAECgEJAgABLgAFFAQJBgAKAK4aAA==.',
So='Sojourner:BAABLgAECn8iAAMEAAcJDBj7IgDjAQAEAAcJDBj7IgDjAQADAAUJFg6vuwADAQAAAA==.',
Sp='Spoonzilla:BAABLgAECn8eAAIbAAYJFxJXOwAXAQAbAAYJFxJXOwAXAQAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIQAAgJ+R6hGgC0AgAQAAgJ+R6hGgC0AgABLgAECgkJEQACAAAAAA==.',
Su='Supersham:BAAALgAECgQJBAAAAA==.Superspam:BAABLgAECn8jAAMgAAkJsx7kLAD7AQAgAAkJsx7kLAD7AQAbAAcJWBKoNQA0AQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Sy='Sylphiett:BAAALgAECgQJBAABLgAFFAUJDwAUAAMJAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn85AAIaAAkJDSDbAgCqAgAaAAkJDSDbAgCqAgAAAA==.',
Th='Thatswild:BAAALgAECgEJAQAAAA==.Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8lAAIgAAkJqQ5oPQCVAQAgAAkJqQ5oPQCVAQAAAA==.Thrasherzs:BAAALgAECgEJBAAAAA==.Thy:BAAALgAECgMJAwAAAA==.',
Ti='Tinydragon:BAABLgAFFH8PAAIUAAUJAwlgNQDlAAAUAAUJAwlgNQDlAAAAAA==.Tinyvoid:BAACLgAFFH8GAAIQAAMJewoXZAC2AAAQAAMJewoXZAC2AAAuAAQKfyoAAhAACQkmGlgfAE8CABAACQkmGlgfAE8CAAEuAAUUBQkPABQAAwkA.',
To='Togdumburz:BAACLgAFFH8PAAIdAAUJuRPBTQAgAQAdAAUJuRPBTQAgAQAuAAQKfyUAAx0ACQkhGqglAEECAB0ACQkhGqglAEECAA0AAQkAAElnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Tr='Travis:BAAALgADCgUJAgAAAA==.',
Ty='Typhoid:BAAALgADCgUJBQAAAA==.Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.Unnamedhydra:BAAALgAECgEJAQAAAA==.',
Va='Vaelhyra:BAACLgAFFH8XAAIYAAYJZyFvBAA5AgAYAAYJZyFvBAA5AgAuAAQKfxwABBgACAnkIeQJAOsCABgACAnPIeQJAOsCABcAAgnJFCpcAKAAABYAAgmdD1taAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Valyndor:BAAALgAECgUJBgABLgAFFAQJBgAKAK4aAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgkJIQAiADUTAA==.',
Ve='Velascrimaz:BAAALgAECgEJAQAAAA==.Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAACLgAFFH8GAAMKAAQJoxoxEgAJAQAKAAMJvSExEgAJAQAjAAEJUwXCQAA0AAAuAAQKfxkAAwoACAmbIl0LAC8CAAoABwknJF0LAC8CACMABgkSGy8oACUBAAEuAAUUBgkXABgAZyEA.',
Vi='Vietsham:BAABLgAECn8vAAIOAAkJJxrvEgCrAgAOAAkJJxrvEgCrAgAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vokevokevoke:BAABLgAECn8UAAIUAAgJjgvBNwBDAQAUAAgJjgvBNwBDAQABLgAFFAQJCQAHAO8JAA==.Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8WAAIFAAcJQxUjDwB0AQAFAAcJQxUjDwB0AQAuAAQKfyQAAgUACQk9HdkIAH8CAAUACQk9HdkIAH8CAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Warspite:BAAALgAECgUJBQABLgAECggJIAAgAAQbAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgcJDQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgAECgEJAQABLgAECgEJAwACAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn9AAAMVAAkJ7SCRBgAAAwAVAAkJ7SCRBgAAAwALAAcJBBRaIwCnAQAAAA==.',
Ye='Yetlian:BAACLgAFFH8TAAIEAAcJKBxUCAAdAgAEAAcJKBxUCAAdAgAuAAQKfyIAAwQACQmGI4cFADADAAQACQmGI4cFADADAAMAAQkAAS++ARAAAAAA.',
Yo='You:BAAALgADCgMJAwABLgAFFAQJBgAPAEwPAA==.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8mAAIjAAgJmyM2AQC8AgAjAAgJmyM2AQC8AgAuAAQKfyAAAiMACAmrIWUCAAADACMACAmrIWUCAAADAAAA.',
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
