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

local lookup = {'DemonHunter-Vengeance','Priest-Holy','Rogue-Assassination','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Shadow','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','DeathKnight-Blood','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Retribution','Mage-Arcane','Monk-Windwalker','Paladin-Holy','Evoker-Preservation','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Frost','Unknown-Unknown','Warrior-Arms','Mage-Frost','DemonHunter-Havoc','Priest-Discipline','Warrior-Fury','DeathKnight-Unholy','Evoker-Devastation','Paladin-Protection','Shaman-Restoration','Evoker-Augmentation',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=53,date='2026-11-10',data={Ag='Agerax:BAABNQAECn8cAAIBAAkKpxEtCQDBAQABAAkKpxEtCQDBAQABNQAECgoKMgACANgeAA==.',
Ai='Aiedel:BAAANQADCgcIEAAAAA==.',
Al='Aldric:BAAANQADCgYIBgAAAA==.',
An='Anaura:BAAANQADCggIGwABNQAECgkJJgADALgVAA==.Anì:BAAANQADCggIDgAAAA==.',
Ar='Arelith:BAAANQADCgYIBgAAAA==.Ariggs:BAAANQAECgUIBQABNQAECgoKNAABAFglAA==.Ariosx:BAABNQAECn8uAAQEAAoK6BpgEQCYAgAEAAkKnRlgEQCYAgAFAAcKSA3gYQBHAQAGAAEKaAQ3cAAdAAABNQAECgoKMgACANgeAA==.Arlen:BAAANQAECggIEQAAAA==.Arma:BAACNQAFFH8HAAIHAAMKAyDiDAARAQAHAAMKAyDiDAARAQA1AAQKfyEAAgcACQraJDsIAFgDAAcACQraJDsIAFgDAAAA.Armaa:BAACNQAFFH8JAAMIAAUKOR2yEgD7AAAIAAQKQx6yEgD7AAAJAAEKGhrFDgBWAAA1AAQKfx0ABAgACQo9IhcZAKsCAAgACQoJIhcZAKsCAAkAAwr0HSISAPgAAAoAAgpsHdwUAKkAAAAA.',
As='Astoria:BAAANQADCggIDQABNQAECgkJJgADALgVAA==.',
Aw='Awnurneze:BAAANQADCgYIDAAAAA==.',
['Aë']='Aëgis:BAAANQADCgQIBAAAAA==.',
Ba='Balob:BAACNQAFFH8MAAILAAUKoCRCBwAEAgALAAUKoCRCBwAEAgA1AAQKfycAAgsACQr/JRIFAMIDAAsACQr/JRIFAMIDAAAA.',
Bg='Bgz:BAAANQADCgUICQAAAA==.',
Bl='Bloodngore:BAABNQAECn8uAAIMAAkK3xDAOQBOAQAMAAkK3xDAOQBOAQAAAA==.Bluos:BAAANQADCgQIBgAAAA==.',
Bo='Boomba:BAACNQAFFH8JAAINAAUKyxwfDwAAAQANAAUKyxwfDwAAAQA1AAQKf2kAAg0ACgqhJpMBAIkDAA0ACgqhJpMBAIkDAAE1AAQKCgolAA4A9hUA.',
Br='Brightghoulz:BAABNQAECn8iAAICAAkKzyFUNQCSAgACAAkKzyFUNQCSAgAAAA==.Broku:BAAANQAECgcICAABNQAECggIJQAPAMgTAA==.',
Bu='Bubblelove:BAABNQAECn8lAAIHAAoKBQu7MACeAQAHAAoKBQu7MACeAQAAAA==.Bubbly:BAABNQAECn8lAAIPAAgKyBOEpQDVAQAPAAgKyBOEpQDVAQAAAA==.',
Cd='Cdogg:BAAANQAECgEIAQAAAA==.',
Ce='Censored:BAAANQAECgEIBAAAAA==.Cercal:BAAANQAECggIDAABNQAFFAYIEAAQACwRAA==.',
Ch='Chopsy:BAABNQAECn8lAAMOAAoK9hXTEwClAQAOAAgKIxTTEwClAQARAAgKqBb6LQATAQAAAA==.Chrunqq:BAAANQADCgIIAgAAAA==.',
Ci='Cinnabons:BAABNQAECn8wAAISAAoKCiMjGAAaAwASAAoKCiMjGAAaAwABNQAECgkJFQATAEASAA==.',
Co='Cobgoblin:BAAANQABCgIIAgAAAA==.Comeplay:BAABNQAECn8jAAILAAoKsiE5FgBDAwALAAoKsiE5FgBDAwAAAA==.',
Cr='Cronnos:BAAANQAECgEIAQAAAA==.',
Cu='Cursed:BAABNQAECn9MAAQJAAoKER2eAgDvAgAJAAoKFRyeAgDvAgAKAAcK6RkDGgCcAQAIAAUKuQyC7ADxAAAAAA==.',
Da='Dabz:BAABNQAECn85AAMIAAoKrR/HKwBRAgAIAAkK0R/HKwBRAgAKAAIK+hSIUACNAAAAAA==.Daddyslaps:BAAANQAECgMIAwABNQAECgoKNAABAFglAA==.Daghma:BAABNQAECn80AAIBAAoKWCX1AQAJAwABAAoKWCX1AQAJAwAAAA==.',
De='Demonbubble:BAACNQAFFH8QAAIUAAYKHw9OAwBoAQAUAAYKHw9OAwBoAQA1AAQKf0UAAhQACgrwIIsHANoCABQACgrwIIsHANoCAAAA.',
Di='Diizz:BAAANQADCgYICwAAAA==.',
Do='Dotomic:BAAANQAECgIIAgABNQAFFAkJJgAVAAMhAA==.',
Dr='Draesham:BAAANQAECgIIBAAAAA==.Drifthook:BAABNQAECn8tAAMWAAoKYxRtPQCQAQAWAAoKaBJtPQCQAQAMAAEKDRP9lgA5AAAAAA==.Drowarchon:BAAANQAECgQIBAAAAA==.Drownix:BAAANQADCgYIBgABNQAECgQIBAAXAAAAAA==.',
El='Elnaris:BAABNQAECn8nAAIPAAgKqQUO6gD3AAAPAAgKqQUO6gD3AAAAAA==.',
Em='Emiliow:BAAANQADCgUIBQAAAA==.',
En='Entropy:BAAANQAECggIBwAAAA==.',
Eo='Eon:BAAANQABCgYIBwAAAA==.',
Er='Eriu:BAABNQAECn8yAAICAAoK2B62DQBiAwACAAoK2B62DQBiAwAAAA==.Erõs:BAAANQAECgYICAABNQAFFAYIGwATABkQAA==.',
Fa='Fatback:BAAANQABCgYICQAAAA==.',
['Fû']='Fûran:BAAANQAECgEIAQABNQAECgYICgAXAAAAAA==.',
Ga='Ganryu:BAACNQAFFH8IAAIFAAUK/gv8EgDGAAAFAAUK/gv8EgDGAAA1AAQKf1sAAgUACgq+IpcKAHgDAAUACgq+IpcKAHgDAAAA.Garnio:BAAANQADCgUIBAAAAA==.',
Ge='Geosunholy:BAAANQAECgYIBwAAAA==.',
Gh='Ghoulbasher:BAAANQADCgQIBQAAAA==.',
Gi='Gitzi:BAABNQAECn9kAAINAAoKWR3oJwD4AgANAAoKWR3oJwD4AgAAAA==.',
Go='Goloki:BAAANQADCgIIAgAAAA==.',
Gr='Griever:BAAANQADCgEIAQAAAA==.Gripper:BAAANQADCgYIDAABNQAECgoKJQAOAPYVAA==.Groove:BAABNQAECn8sAAIYAAkKyx/fRAC7AgAYAAkKyx/fRAC7AgAAAA==.Groovexgroov:BAAANQADCgcIBwABNQAECgoKNgAPABsgAA==.Grìmm:BAAANQAECgQIBAAAAA==.',
Gw='Gwrath:BAAANQAECgEIAgAAAA==.',
Ha='Hallena:BAAANQABCggIHAAAAA==.Harlowe:BAAANQADCggICgAAAA==.Harsh:BAAANQADCgUJBQAAAA==.Harukã:BAAANQADCggIBgAAAA==.Harúka:BAAANQAECggIAgAAAA==.',
Ho='Holyblast:BAAANQAECgQIBAAAAA==.Holyperineum:BAAANQAECgEIAgABNQAECgoKSgAEANAiAA==.Hordend:BAAANQAECggIEQAAAA==.',
In='Incapable:BAAANQAECgEIAQABNQAECgoKSgAEANAiAA==.Invisobull:BAAANQAECgYIDQABNQAECggIAwAXAAAAAA==.',
Ja='Jaam:BAAANQADCgUIBQAAAA==.Jaloe:BAAANQAECgQIBAAAAA==.Jayjay:BAACNQAFFH8QAAMQAAYKLBH+FgAjAQAQAAUKMQ/+FgAjAQAZAAIK3RI9DQBVAAA1AAQKfzUAAxkACgo1Hm0OAMQBABAACgpSHbVGACsCABkABQq7H20OAMQBAAAA.',
Jo='Johnparstina:BAABNQAECn9IAAINAAoKRSJyFgBBAwANAAoKRSJyFgBBAwAAAA==.Jorb:BAAANQADCgQIBAABNQAECgIIAgAXAAAAAA==.',
Ka='Kainical:BAABNQAECn8WAAMPAAgK/Ad7DgEHAQAPAAcK/Ad7DgEHAQASAAYK9QnNjgD6AAABNQAFFAUICAABAI8XAA==.Kainicus:BAACNQAFFH8IAAIBAAUKjxc2AgDFAAABAAUKjxc2AgDFAAA1AAQKf0UAAwEACgrzIOAEAO4CAAEACgrzIOAEAO4CABoAAgrfExdkAIAAAAAA.',
Ke='Kelador:BAAANQAECgEIAgAAAA==.',
Kh='Khaller:BAAANQABCgEIAQAAAA==.Khrism:BAAANQAECggICQAAAA==.',
Ki='Kismet:BAAANQAECgUIBQABNQAECgoKSgAEANAiAA==.',
Ko='Kohen:BAABNQAECn8fAAICAAoKahgwQQBmAgACAAoKahgwQQBmAgAAAA==.Kokobubbles:BAAANQAECgIIAgAAAA==.',
Kr='Kreaiden:BAAANQAECgIIAgAAAA==.',
Ku='Kuyaa:BAAANQADCggICgAAAA==.',
La='Larryhoover:BAAANQADCgMIAwAAAA==.',
Lo='Loathrim:BAAANQADCgcIBwAAAA==.',
Lu='Luminusrayne:BAACNQAFFH8GAAICAAQKJQcbHAD5AAACAAQKJQcbHAD5AAA1AAQKf1kAAgIACgpDFMJTACgCAAIACgpDFMJTACgCAAAA.',
Ma='Manafest:BAABNQAECn8XAAIKAAYKKhHFDADkAAAKAAYKKhHFDADkAAAAAA==.',
Me='Meheret:BAABNQAECn9FAAIZAAoKJQtwDQDaAQAZAAoKJQtwDQDaAQAAAA==.',
Mi='Micheladar:BAAANQABCgIIAgAAAA==.Mint:BAAANQAECgIIAgAAAA==.',
Mo='Molgrath:BAAANQADCgIIAgAAAA==.Moomu:BAAANQADCggICAAAAA==.Morganthe:BAABNQAECn8XAAQCAAkKcBSdfABLAQACAAkKNROdfABLAQAbAAMKVBPrDwB4AAAHAAEK0QWcgQApAAAAAA==.Moìst:BAAANQAECgQIBAABNQAECggIBQAXAAAAAA==.',
Mu='Murdafest:BAAANQAECgQICAAAAA==.',
My='Mydkk:BAAANQADCgEIAQABNQAECgoKIAAZAMEUAA==.Mydrood:BAAANQAECgMIAwABNQAECgoKIAAZAMEUAA==.Myhunts:BAAANQAECgIIAgABNQAECgoKIAAZAMEUAA==.Mylock:BAAANQADCgMIAwABNQAECgoKIAAZAMEUAA==.Mymaage:BAABNQAECn8gAAMZAAoKwRQ4DQDfAQAZAAgK3RQ4DQDfAQAQAAgK1RDY9gCeAQAAAA==.Mymonkk:BAAANQADCggICAABNQAECgoKIAAZAMEUAA==.Mypally:BAAANQAECggICAABNQAECgoKIAAZAMEUAA==.Mypriiest:BAAANQAECgUIDQABNQAECgoKIAAZAMEUAA==.Myshammy:BAAANQAECgQIBAABNQAECgoKIAAZAMEUAA==.Mystx:BAABNQAECn8sAAMQAAkKaxiERAAyAgAQAAkKThaERAAyAgAZAAQKmhz0FQBPAQABNQAECgoKMgACANgeAA==.Mythx:BAABNQAECn8yAAMYAAkKGx5ULACBAgAYAAkKGx5ULACBAgAcAAgK6xZJCwAPAgABNQAECgoKMgACANgeAA==.Mywarr:BAAANQADCgQIBgABNQAECgoKIAAZAMEUAA==.',
Na='Narushi:BAABNQAECn8xAAMQAAoKqxrOTQAXAgAQAAoKqxrOTQAXAgAZAAYKThWdFABgAQAAAA==.Natâsi:BAABNQAECn8sAAISAAoKPxJ6VgAWAgASAAoKPxJ6VgAWAgAAAA==.',
Ne='Nebulis:BAABNQAECn8vAAINAAkKvwvcgQCbAQANAAkKvwvcgQCbAQAAAA==.Nerva:BAAANQAECggIBQAAAA==.',
Ni='Nielas:BAABNQAECn8WAAMdAAkKXxwfGAAXAgAdAAkKXxwfGAAXAgAMAAMKwQz9awCSAAABNQAECgoKNAABAFglAA==.Nihilus:BAACNQAFFH8RAAQdAAcKQhBzCACRAQAdAAYKFBNzCACRAQAMAAMK3wb1IQB5AAAWAAEK7wC+IgAuAAA1AAQKfzoABB0ACgoNIxckALECAB0ACgoNIxckALECABYACApYGJg5AOwBAAwABwqaF1NKAAYBAAAA.',
No='Noctium:BAABNQAECn8/AAIeAAoKuyKuAQAcAwAeAAoKuyKuAQAcAwAAAA==.Nostrildamus:BAAANQADCgQIBAABNQAECgIIAgAXAAAAAA==.',
Oc='Octavior:BAABNQAECn8bAAIfAAoKIhqnDgAsAgAfAAoKIhqnDgAsAgAAAA==.',
Ow='Owls:BAACNQAFFH8QAAICAAUKhhIgEwBfAQACAAUKhhIgEwBfAQA1AAQKfzcAAgIACgpoIsIRADsDAAIACgpoIsIRADsDAAE1AAUUBQoQAAIAhhIA.Owly:BAABNQAECn8dAAISAAoKBx3HIgDhAgASAAoKBx3HIgDhAgABNQAFFAUKEAACAIYSAA==.',
Pa='Pallywhacker:BAAANQAECggICAAAAA==.',
Pi='Pily:BAAANQAECgEIAQAAAA==.',
Po='Poizonivy:BAAANQADCgcIBwAAAA==.',
Pr='Prayxx:BAAANQAECgQIBwAAAA==.Proved:BAABNQAECn8tAAICAAoKxhVbSgBGAgACAAoKxhVbSgBGAgAAAA==.',
Ps='Psypal:BAAANQAECgQIBgAAAA==.',
Pu='Puddingface:BAABNQAECn9KAAMEAAoK0CJmBwBXAwAEAAoK0CJmBwBXAwAFAAEKAABHrgA5AAAAAA==.Puggar:BAAANQADCgIJAgAAAA==.',
Ra='Ranessandi:BAAANQADCgYIBgAAAA==.Ratlemebonez:BAAANQAECgUICAAAAA==.Ravèn:BAAANQADCgYIFwAAAA==.Razeal:BAABNQAECn8cAAIUAAkK1AViNQDcAAAUAAkK1AViNQDcAAAAAA==.Razenal:BAAANQADCgYIBgAAAA==.Razenga:BAAANQADCgQICAAAAA==.',
Re='Regerax:BAABNQAECn8lAAINAAkK0xhtYwBPAgANAAkK0xhtYwBPAgABNQAECgoKMgACANgeAA==.Rendani:BAAANQADCggIDQAAAA==.',
Rh='Rhaok:BAAANQAECgYIBAABNQAECggIBQAXAAAAAA==.Rhettpaladin:BAAANQAECgcIDwAAAA==.Rhysan:BAACNQAFFH8IAAIgAAUKkQzkDwA+AQAgAAUKkQzkDwA+AQA1AAQKf10AAiAACgrQG6M7AHECACAACgrQG6M7AHECAAAA.',
Ro='Rokki:BAAANQADCgQIBAAAAA==.',
Ru='Rudeus:BAAANQAECgEIAgAAAA==.',
Ry='Rynhart:BAAANQAECgcIDQABNQAECgoKNAABAFglAA==.Ryz:BAAANQAECgMIAgABNQAFFAgIGwADAJofAA==.',
Sa='Sacerdote:BAABNQAECn8WAAMIAAkKeBagRwB8AgAIAAkKeBagRwB8AgAJAAEKew2fKgBDAAAAAA==.Sangre:BAAANQADCgUIBQAAAA==.',
Sc='Scrat:BAAANQAECggICgAAAA==.',
Se='Seasalt:BAAANQAECgQIBgAAAA==.Sebnoth:BAABNQAECn8nAAIdAAoKwxUEQgAUAgAdAAoKwxUEQgAUAgAAAA==.Seyer:BAAANQADCggIBQABNQAECgkJKgAYAOYSAA==.',
Sh='Shaldria:BAAANQADCgcIBwAAAA==.Shamadams:BAAANQAECgIIAgABNQAECggIAwAXAAAAAA==.Shamrox:BAAANQAECgMIBQAAAA==.Shaureille:BAAANQAECgEIAQAAAA==.Shiden:BAABNQAECn8dAAIIAAkKRxXimQAQAQAIAAkKRxXimQAQAQAAAA==.Shiftingtom:BAAANQADCgQIBAAAAA==.Shurlock:BAAANQAECggIAgAAAA==.',
Si='Sidepiece:BAAANQAECgUICwAAAA==.Sillyderek:BAABNQAECn8UAAIfAAUKAQgGSQDJAAAfAAUKAQgGSQDJAAAAAA==.Simpletom:BAABNQAECn8XAAIIAAgKmgkzrADoAAAIAAgKmgkzrADoAAAAAA==.',
Sk='Skulzulu:BAAANQAECgUICQAAAA==.',
Sm='Smallpally:BAABNQAECn8cAAIPAAgKABLurwBaAQAPAAgKABLurwBaAQAAAA==.',
St='Stawk:BAAANQADCgYIBgAAAA==.Stellium:BAAANQAECggIAQAAAA==.Stevokerjobs:BAACNQAFFH8bAAQTAAYKGRASCQB2AQATAAYKGRASCQB2AQAeAAMK+gnrBQByAAAhAAEK5QetDQBGAAA1AAQKfzEAAxMACgo9HG0FABMDABMACgo9HG0FABMDAB4ACQoTGQ8NAJECAAAA.',
Su='Sunwa:BAABNQAECn8tAAMPAAkKvRrIhQCsAQAPAAkKsxnIhQCsAQAfAAQKkw4gXABrAAABNQAECgoKMgACANgeAA==.Supzz:BAAANQADCgYICAAAAA==.Suunto:BAABNQAECn8gAAMVAAgKkgEMSABwAAAVAAgKVwEMSABwAAANAAgKxQD2SQEpAAAAAA==.',
Sy='Syndragosa:BAAANQAECgIIAgAAAA==.',
['Sï']='Sïmba:BAAANQADCgQIBAAAAA==.',
Th='Thepride:BAAANQAECgUIDAAAAA==.Thicchalupa:BAAANQABCgEIAQAAAA==.Thorz:BAAANQADCggIGAABNQAECgoKLQAJAEsSAA==.Thundy:BAAANQAECgEIAQAAAA==.',
Ti='Tired:BAAANQADCggICAABNQAECgoKHwACAGoYAA==.',
To='Tooms:BAAANQAECgIIAgAAAA==.Touchi:BAABNQAECn8tAAQJAAoKSxLpBgDrAQAJAAoKyhHpBgDrAQAIAAUKyAla6wDzAAAKAAIKLBAKWgByAAAAAA==.',
Tu='Tuo:BAAANQAECgUIBQABNQAECgoKLQAJAEsSAA==.Turbid:BAABNQAECn9OAAIUAAoKRCD9BgDlAgAUAAoKRCD9BgDlAgAAAA==.',
Ty='Tytank:BAAANQADCgUIBQAAAA==.',
Va='Valkkx:BAAANQADCgYICgAAAA==.',
Ve='Vexous:BAAANQADCgMIAwAAAA==.',
Vo='Voutecomer:BAAANQADCgEIAQAAAA==.',
Vu='Vurty:BAAANQAECgQICgAAAA==.',
Wa='Walls:BAAANQAECgIIAgAAAA==.',
We='Westirras:BAABNQAECn8xAAMPAAgKxAqGwwA3AQAPAAgKxAqGwwA3AQASAAYKjwnYswAWAQAAAA==.',
Wh='Whistler:BAAANQAECggICAAAAA==.',
Wo='Wobblepox:BAAANQAECggICAAAAA==.',
Ya='Yarrow:BAABNQAECn8mAAIDAAkKuBVqDwDEAQADAAkKuBVqDwDEAQAAAA==.',
Zu='Zunden:BAAANQADCgcICwAAAA==.',
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
