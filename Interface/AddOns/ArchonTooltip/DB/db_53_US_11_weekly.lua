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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Shadow','Warlock-Demonology','Shaman-Elemental','DeathKnight-Blood','Hunter-BeastMastery','Monk-Brewmaster','Priest-Holy','Mage-Arcane','Monk-Windwalker','Paladin-Holy','Unknown-Unknown','Warlock-Affliction','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Frost','Warrior-Arms','Mage-Frost','Warrior-Fury','DeathKnight-Unholy','Evoker-Devastation','Shaman-Restoration','Paladin-Protection','Evoker-Preservation',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=53,date='2026-10-20',data={Ag='Agerax:BAAANQAECgQIBAABNQAECgkJHwABADIXAA==.',
Ai='Aiedel:BAAANQADCgcIEAAAAA==.',
Al='Aldric:BAAANQADCgYIBgAAAA==.',
An='Anaura:BAAANQADCggIGwABNQAECggIIgACAPUWAA==.',
Ar='Arelith:BAAANQADCgYIBgAAAA==.Ariggs:BAAANQADCgMIAwAAAA==.Ariosx:BAABNQAECn8dAAQDAAkKqRL+CgCJAQADAAkKqRL+CgCJAQAEAAYKSA3gYQBHAQAFAAEKaAQ3cAAdAAABNQAECgkJHwABADIXAA==.Arlen:BAAANQAECggIEAAAAA==.Arma:BAACNQAFFH8HAAIGAAMKAyDiDAARAQAGAAMKAyDiDAARAQA1AAQKfyEAAgYACQraJDsIAFgDAAYACQraJDsIAFgDAAAA.Armaa:BAABNQAFFH8IAAIHAAQKQx4dBQAWAQAHAAQKQx4dBQAWAQAAAA==.',
As='Astoria:BAAANQADCggIDQABNQAECggIIgACAPUWAA==.',
Aw='Awnurneze:BAAANQADCgYIDAAAAA==.',
Ba='Balob:BAACNQAFFH8MAAIIAAUKoCRCBwAEAgAIAAUKoCRCBwAEAgA1AAQKfycAAggACQr/JRIFAMIDAAgACQr/JRIFAMIDAAAA.',
Bg='Bgz:BAAANQADCgUICQAAAA==.',
Bl='Bloodngore:BAABNQAECn8mAAIJAAcKixLJWACQAQAJAAcKixLJWACQAQAAAA==.Bluos:BAAANQADCgQIBgAAAA==.',
Bo='Boomba:BAABNQAECn9OAAIKAAoKbiXlAgDYAwAKAAoKbiXlAgDYAwABNQAECggIIAALAF0VAA==.',
Br='Brightghoulz:BAABNQAECn8bAAIMAAcKVCFUNQCSAgAMAAcKVCFUNQCSAgAAAA==.Broku:BAAANQAECgIIAgABNQAECggIHwABAMgTAA==.',
Bu='Bubblelove:BAABNQAECn8iAAIGAAkKzQu7MACeAQAGAAkKzQu7MACeAQAAAA==.Bubbly:BAABNQAECn8fAAIBAAgKyBMlQgBCAQABAAgKyBMlQgBCAQAAAA==.',
Cd='Cdogg:BAAANQAECgEIAQAAAA==.',
Ce='Censored:BAAANQAECgEIBAAAAA==.Cercal:BAAANQAECggICwABNQAFFAQIDgANAF0SAA==.',
Ch='Chopsy:BAABNQAECn8gAAMLAAgKXRVKBgAQAQAOAAUKuBeBPwAZAQALAAgKGhRKBgAQAQAAAA==.Chrunqq:BAAANQADCgIIAgAAAA==.',
Ci='Cinnabons:BAABNQAECn8oAAIPAAkKzyIjGAAaAwAPAAkKzyIjGAAaAwABNQAECgUIBQAQAAAAAA==.',
Co='Cobgoblin:BAAANQABCgIIAgAAAA==.Comeplay:BAABNQAECn8gAAIIAAkKaiI5FgBDAwAIAAkKaiI5FgBDAwAAAA==.',
Cr='Cronnos:BAAANQAECgEIAQAAAA==.',
Cu='Cursed:BAABNQAECn8xAAQRAAoKLhieAgDvAgARAAkKqRmeAgDvAgASAAcKyhQDGgCcAQAHAAUKuQzobQCnAAAAAA==.',
Da='Dabz:BAABNQAECn8jAAMHAAkKlh0gGwCEAQAHAAgKZx0gGwCEAQASAAIK+hSIUACNAAAAAA==.Daghma:BAABNQAECn8nAAITAAgKAiXUAgBKAwATAAgKAiXUAgBKAwAAAA==.',
De='Demonbubble:BAACNQAFFH8OAAIUAAQKzhXzAgD5AAAUAAQKzhXzAgD5AAA1AAQKfywAAhQACgo/Hp4LACUDABQACgo/Hp4LACUDAAAA.',
Di='Diizz:BAAANQADCgYICwAAAA==.',
Do='Dotomic:BAAANQAECgIIAgABNQAFFAgIHQAVAKkgAA==.',
Dr='Draesham:BAAANQAECgIIBAAAAA==.Drifthook:BAABNQAECn8iAAIWAAkK1hRBEACDAQAWAAkK1hRBEACDAQAAAA==.Drowarchon:BAAANQAECgQIBAAAAA==.Drownix:BAAANQADCgYIBgABNQAECgQIBAAQAAAAAA==.',
El='Elnaris:BAAANQAECgYIEAAAAA==.',
Em='Emiliow:BAAANQADCgUIBQAAAA==.',
En='Entropy:BAAANQAECggIBwAAAA==.',
Eo='Eon:BAAANQABCgYIBwAAAA==.',
Er='Eriu:BAABNQAECn8bAAIMAAgKIyAWDAAkAgAMAAgKIyAWDAAkAgABNQAECgkJHwABADIXAA==.',
Fa='Fatback:BAAANQABCgYICQAAAA==.',
['Fû']='Fûran:BAAANQAECgEIAQABNQAECgQIAgAQAAAAAA==.',
Ga='Ganryu:BAABNQAECn9TAAIEAAoKNyKXCgB4AwAEAAoKNyKXCgB4AwAAAA==.Garnio:BAAANQADCgUIBAAAAA==.',
Ge='Geosunholy:BAAANQAECgEIAQAAAA==.',
Gh='Ghoulbasher:BAAANQADCgMIAwAAAA==.',
Gi='Gitzi:BAABNQAECn9UAAIKAAoKJBsJEQDoAQAKAAoKJBsJEQDoAQAAAA==.',
Go='Goloki:BAAANQADCgIIAgAAAA==.',
Gr='Griever:BAAANQADCgEIAQAAAA==.Gripper:BAAANQADCgYIDAABNQAECggIIAALAF0VAA==.Groove:BAABNQAECn8mAAIXAAkKYx3fRAC7AgAXAAkKYx3fRAC7AgAAAA==.Groovexgroov:BAAANQADCggIBwABNQAECgoKIwABAFodAA==.Grìmm:BAAANQAECgQIBAAAAA==.',
Gw='Gwrath:BAAANQAECgEIAgAAAA==.',
Ha='Hallena:BAAANQABCggIGwAAAA==.Harlowe:BAAANQADCggICgAAAA==.Harsh:BAAANQADCgUJBQAAAA==.Harukã:BAAANQADCggIBgAAAA==.Harúka:BAAANQAECggIAgAAAA==.',
He='Headie:BAAANQADCgcICgAAAA==.',
Ho='Holyblast:BAAANQAECgQIBAAAAA==.Holyperineum:BAAANQABCgUIBgABNQAECgkJMAADACkiAA==.Hordend:BAAANQAECggIEQAAAA==.',
In='Incapable:BAAANQABCgQIBAABNQAECgkJMAADACkiAA==.Invisobull:BAAANQAECgYIBgABNQAECggIAgAQAAAAAA==.',
Ja='Jaam:BAAANQADCgUIBQAAAA==.Jaloe:BAAANQADCggIJQAAAA==.Jayjay:BAACNQAFFH8OAAMNAAQKXRIsDgDsAAANAAQKXRIsDgDsAAAYAAEKpAzREwBGAAA1AAQKfysAAxgACgp8HG0OAMQBAA0ACgohGO51AJICABgABQq7H20OAMQBAAAA.',
Jo='Johnparstina:BAABNQAECn89AAIKAAoK5iARCQA1AgAKAAoK5iARCQA1AgAAAA==.Jorb:BAAANQADCgQIBAABNQAECgIIAgAQAAAAAA==.',
Ka='Kainical:BAAANQAECgYIEQAAAA==.Kainicus:BAABNQAECn8yAAITAAoKJx3gBADuAgATAAoKJx3gBADuAgAAAA==.',
Ke='Kelador:BAAANQAECgIIAgAAAA==.',
Kh='Khaller:BAAANQABCgEIAQAAAA==.Khrism:BAAANQAECggICQAAAA==.',
Ki='Kismet:BAAANQADCggIIwABNQAECgkJMAADACkiAA==.',
Ko='Kohen:BAABNQAECn8dAAIMAAoKAhcwQQBmAgAMAAoKAhcwQQBmAgAAAA==.Kokobubbles:BAAANQAECgIIAgAAAA==.',
Kr='Krispa:BAAANQADCggIIgAAAA==.',
Ku='Kuyaa:BAAANQADCggICgAAAA==.',
La='Larryhoover:BAAANQADCgMIAwAAAA==.',
Lo='Loathrim:BAAANQADCgcIBwAAAA==.',
Lu='Luminusrayne:BAABNQAECn9OAAIMAAoKQxTCUwAoAgAMAAoKQxTCUwAoAgAAAA==.',
Ma='Malkamechka:BAAANQADCgQIAwAAAA==.Manafest:BAAANQAECgQIDAAAAA==.',
Me='Meheret:BAABNQAECn9BAAIYAAkKsQtwDQDaAQAYAAkKsQtwDQDaAQAAAA==.',
Mi='Mint:BAAANQAECgIIAgAAAA==.',
Mo='Molgrath:BAAANQADCgIIAgAAAA==.Moomu:BAAANQADCggICAAAAA==.Morganthe:BAAANQAECgcIEQAAAA==.Moìst:BAAANQADCgcIBwAAAA==.',
My='Mydkk:BAAANQADCgEIAQABNQAECgoKHQAYAL4UAA==.Mydrood:BAAANQAECgMIAwABNQAECgoKHQAYAL4UAA==.Myhunts:BAAANQAECgIIAgABNQAECgoKHQAYAL4UAA==.Mylock:BAAANQADCgMIAwABNQAECgoKHQAYAL4UAA==.Mymaage:BAABNQAECn8dAAMYAAoKvhTFBABeAQANAAcKzg/Y9gCeAQAYAAgK3RTFBABeAQAAAA==.Mymonkk:BAAANQADCggICAABNQAECgoKHQAYAL4UAA==.Mypally:BAAANQAECggICAABNQAECgoKHQAYAL4UAA==.Mypriiest:BAAANQAECgUIDQABNQAECgoKHQAYAL4UAA==.Myroguëë:BAAANQADCgYICwABNQAECgoKHQAYAL4UAA==.Mystx:BAABNQAECn8YAAMNAAgKfhZaKQB0AQANAAgKFBRaKQB0AQAYAAQKmhz0FQBPAQABNQAECgkJHwABADIXAA==.Mythx:BAABNQAECn8fAAMXAAkK1BvBGgCaAQAZAAgK6xZJCwAPAgAXAAkKARrBGgCaAQABNQAECgkJHwABADIXAA==.Mywarr:BAAANQADCgQIBgABNQAECgoKHQAYAL4UAA==.',
Na='Narushi:BAABNQAECn8oAAMNAAkKhBhTbgChAgANAAkKUxdTbgChAgAYAAUK6xedFABgAQAAAA==.Natâsi:BAABNQAECn8hAAIPAAoKgRB6VgAWAgAPAAoKgRB6VgAWAgAAAA==.',
Ne='Nebulis:BAABNQAECn8hAAIKAAcKIwrRsgCeAQAKAAcKIwrRsgCeAQAAAA==.',
Ni='Nielas:BAAANQAECgUIBQAAAA==.Nihilus:BAACNQAFFH8QAAQaAAYKyQxzCACRAQAaAAUKYw9zCACRAQAJAAMK3wb1IQB5AAAWAAEK7wC+IgAuAAA1AAQKfy4ABBoACgr/IhckALECABoACgr/IhckALECABYACApYGJg5AOwBAAkABAp4FP6PAMUAAAAA.',
No='Noctium:BAABNQAECn8rAAIbAAkKZCAXCQDjAgAbAAkKZCAXCQDjAgAAAA==.Nostrildamus:BAAANQADCgQIBAABNQAECgIIAgAQAAAAAA==.',
Oc='Octavior:BAAANQAECgQICAAAAA==.',
Ow='Owls:BAACNQAFFH8PAAIMAAQKWRAgCwATAQAMAAQKWRAgCwATAQA1AAQKfysAAgwACgrhH+EgAOsCAAwACgrhH+EgAOsCAAE1AAUUBAoPAAwAWRAA.Owly:BAAANQAECggIDwABNQAFFAQKDwAMAFkQAA==.',
Pi='Pily:BAAANQAECgEIAQAAAA==.',
Po='Poizonivy:BAAANQADCggIBwAAAA==.',
Pr='Prayxx:BAAANQAECgQIBwAAAA==.Proved:BAABNQAECn8gAAIMAAoKLBNbSgBGAgAMAAoKLBNbSgBGAgAAAA==.',
Ps='Psypal:BAAANQAECgQIBgAAAA==.',
Pu='Puddingface:BAABNQAECn8wAAMDAAkKKSLZCgAbAwADAAkKKSLZCgAbAwAEAAEKAABHrgA5AAAAAA==.Puggar:BAAANQADCgIJAgAAAA==.',
Ra='Ranessandi:BAAANQADCgYIBgAAAA==.Ratlemebonez:BAAANQAECgIIAgAAAA==.Ravèn:BAAANQADCgYIFAAAAA==.Razeal:BAAANQAECggIDQAAAA==.Razenal:BAAANQADCgIIAgAAAA==.Razenga:BAAANQADCgQICAAAAA==.',
Re='Regerax:BAABNQAECn8dAAIKAAkK0hiJEQDkAQAKAAkK0hiJEQDkAQABNQAECgkJHwABADIXAA==.Rendani:BAAANQADCggIDQAAAA==.',
Rh='Rhettpaladin:BAAANQAECgcIDwAAAA==.Rhysan:BAABNQAECn9SAAIcAAoK0BujOwBxAgAcAAoK0BujOwBxAgAAAA==.',
Ro='Rokki:BAAANQADCgQIBAAAAA==.',
Ru='Rudeus:BAAANQAECgEIAgAAAA==.',
Ry='Ryz:BAAANQAECgIIAgABNQAFFAcIGQACAN0jAA==.',
Sa='Sacerdote:BAABNQAECn8WAAMHAAkKeBagRwB8AgAHAAkKeBagRwB8AgARAAEKew2fKgBDAAAAAA==.Sangre:BAAANQADCgUIBQAAAA==.',
Sc='Scrat:BAAANQAECggICgAAAA==.',
Se='Seasalt:BAAANQAECgQIBgAAAA==.Sebnoth:BAABNQAECn8eAAIaAAgK6RYEQgAUAgAaAAgK6RYEQgAUAgAAAA==.Seyer:BAAANQADCgQIBAABNQAECgkJHgAXAIsPAA==.',
Sh='Shaldria:BAAANQADCgcIBwAAAA==.Shamadams:BAAANQAECgIIAgABNQAECggIAgAQAAAAAA==.Shamrox:BAAANQAECgMIBQAAAA==.Shaureille:BAAANQADCgQIBAAAAA==.Shiden:BAAANQAECggIEAAAAA==.Shiftingtom:BAAANQADCgQIBAAAAA==.Shurlock:BAAANQAECggJAgAAAA==.',
Si='Sidepiece:BAAANQAECgQICAAAAA==.Sillyderek:BAABNQAECn8UAAIdAAUKAQgGSQDJAAAdAAUKAQgGSQDJAAAAAA==.Simpletom:BAAANQAECgYICgAAAA==.',
Sk='Skulzulu:BAAANQADCgIIAgAAAA==.',
Sm='Smallpally:BAAANQAECgUIDQAAAA==.',
St='Stawk:BAAANQADCgYIBgAAAA==.Stevokerjobs:BAACNQAFFH8NAAMeAAUKTguRDwADAQAeAAUKTguRDwADAQAbAAMK+gngAgB8AAA1AAQKfx4AAxsACgpNFw8NAJECABsACQoTGQ8NAJECAB4ACAqxG10FAIgBAAAA.',
Su='Sunwa:BAABNQAECn8fAAMBAAkKMhfKkwD8AQABAAkKKRbKkwD8AQAdAAIKhhAgXABrAAAAAA==.Supzz:BAAANQADCgYICAAAAA==.Suunto:BAAANQAECggIEAAAAA==.',
Sy='Syndragosa:BAAANQAECgIIAgAAAA==.',
['Sï']='Sïmba:BAAANQADCgQIBAAAAA==.',
Te='Tealth:BAAANQADCggICwAAAA==.',
Th='Thepride:BAAANQAECgUIDAAAAA==.Thorz:BAAANQADCggIEwABNQAECggIHwARAB4TAA==.Thundy:BAAANQAECgEIAQAAAA==.',
Ti='Tired:BAAANQADCggICAABNQAECgoKHQAMAAIXAA==.',
To='Touchi:BAABNQAECn8fAAQRAAgKHhOiBwAgAgARAAgKcRKiBwAgAgAHAAUKyAla6wDzAAASAAIKLBAKWgByAAAAAA==.',
Tu='Tuo:BAAANQADCggIGQABNQAECggIHwARAB4TAA==.Turbid:BAABNQAECn8yAAIUAAkKdhugFQC3AgAUAAkKdhugFQC3AgAAAA==.',
Ty='Tytank:BAAANQADCgUIBQAAAA==.',
Va='Valkkx:BAAANQADCgYICgAAAA==.',
Ve='Vexous:BAAANQADCgMIAwAAAA==.',
Vo='Voutecomer:BAAANQADCgEIAQAAAA==.',
Vu='Vurty:BAAANQAECgQICgAAAA==.',
Wa='Walls:BAAANQAECgIIAgAAAA==.',
We='Westirras:BAABNQAECn8eAAMPAAcKkgzYswAWAQAPAAYKjwnYswAWAQABAAYKhwawpQCVAAAAAA==.',
Wh='Whistler:BAAANQAECggICAAAAA==.',
Ya='Yarrow:BAABNQAECn8iAAICAAgK9RYECgCBAQACAAgK9RYECgCBAQAAAA==.',
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
