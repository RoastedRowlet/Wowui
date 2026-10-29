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

local lookup = {'Paladin-Retribution','Rogue-Assassination','Druid-Restoration','Druid-Balance','Druid-Guardian','Priest-Shadow','Warlock-Demonology','Shaman-Elemental','DeathKnight-Blood','Hunter-BeastMastery','Monk-Brewmaster','Priest-Holy','Mage-Arcane','Monk-Windwalker','Paladin-Holy','Unknown-Unknown','Warlock-Affliction','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Marksmanship','DeathKnight-Frost','Evoker-Preservation','Warrior-Arms','Mage-Frost','Warrior-Fury','DeathKnight-Unholy','Evoker-Devastation','Shaman-Restoration','Paladin-Protection',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=53,date='2026-10-27',data={Ag='Agerax:BAAANQAECggIDwABNQAECgkJJQABAHkZAA==.',
Ai='Aiedel:BAAANQADCgcIEAAAAA==.',
Al='Aldric:BAAANQADCgYIBgAAAA==.',
An='Anaura:BAAANQADCggIGwABNQAECggIJQACACsXAA==.',
Ar='Arelith:BAAANQADCgYIBgAAAA==.Ariggs:BAAANQADCgMIAwAAAA==.Ariosx:BAABNQAECn8kAAQDAAkKPBk4DABxAgADAAkKPBk4DABxAgAEAAYKSA3gYQBHAQAFAAEKaAQ3cAAdAAABNQAECgkJJQABAHkZAA==.Arlen:BAAANQAECggIEAAAAA==.Arma:BAACNQAFFH8HAAIGAAMKAyDiDAARAQAGAAMKAyDiDAARAQA1AAQKfyEAAgYACQraJDsIAFgDAAYACQraJDsIAFgDAAAA.Armaa:BAABNQAFFH8IAAIHAAQKQx4xCgAHAQAHAAQKQx4xCgAHAQAAAA==.',
As='Astoria:BAAANQADCggIDQABNQAECggIJQACACsXAA==.',
Aw='Awnurneze:BAAANQADCgYIDAAAAA==.',
Ba='Balob:BAACNQAFFH8MAAIIAAUKoCRCBwAEAgAIAAUKoCRCBwAEAgA1AAQKfycAAggACQr/JRIFAMIDAAgACQr/JRIFAMIDAAAA.',
Bg='Bgz:BAAANQADCgUICQAAAA==.',
Bl='Bloodngore:BAABNQAECn8tAAIJAAgKehEKMAAtAQAJAAgKehEKMAAtAQAAAA==.Bluos:BAAANQADCgQIBgAAAA==.',
Bo='Boomba:BAACNQAFFH8GAAIKAAMKDxomFQCgAAAKAAMKDxomFQCgAAA1AAQKf1gAAgoACgrkJeUCANgDAAoACgrkJeUCANgDAAE1AAQKCAggAAsAZhUA.',
Br='Brightghoulz:BAABNQAECn8cAAIMAAcKVCFUNQCSAgAMAAcKVCFUNQCSAgAAAA==.Broku:BAAANQAECgIIAgABNQAECggIHwABAMgTAA==.',
Bu='Bubblelove:BAABNQAECn8iAAIGAAkKzQu7MACeAQAGAAkKzQu7MACeAQAAAA==.Bubbly:BAABNQAECn8fAAIBAAgKyBOEpQDVAQABAAgKyBOEpQDVAQAAAA==.',
Cd='Cdogg:BAAANQAECgEIAQAAAA==.',
Ce='Censored:BAAANQAECgEIBAAAAA==.Cercal:BAAANQAECggIDAABNQAFFAUIDwANADEPAA==.',
Ch='Chopsy:BAABNQAECn8gAAMLAAgKZhXTEwClAQALAAgKIxTTEwClAQAOAAUKuBeBPwAZAQAAAA==.',
Ci='Cinnabons:BAABNQAECn8sAAIPAAoKwSIjGAAaAwAPAAoKwSIjGAAaAwABNQAECgUICQAQAAAAAA==.',
Co='Cobgoblin:BAAANQABCgIIAgAAAA==.Comeplay:BAABNQAECn8iAAIIAAoKsSE5FgBDAwAIAAoKsSE5FgBDAwAAAA==.',
Cr='Cronnos:BAAANQAECgEIAQAAAA==.',
Cu='Cursed:BAABNQAECn88AAQRAAoKaRueAgDvAgARAAoKVRueAgDvAgASAAcK5BQDGgCcAQAHAAUKuQwsqgCdAAAAAA==.',
Da='Dabz:BAABNQAECn8uAAMHAAoKxh3UHwA/AgAHAAkKpB3UHwA/AgASAAIK+hSIUACNAAAAAA==.Daddyslaps:BAAANQAECgMIAwAAAA==.Daghma:BAABNQAECn8vAAITAAkKyyTUAgBKAwATAAkKyyTUAgBKAwAAAA==.',
De='Demonbubble:BAACNQAFFH8PAAIUAAUKDRL8AgAyAQAUAAUKDRL8AgAyAQA1AAQKfzMAAhQACgrrHp4LACUDABQACgrrHp4LACUDAAAA.',
Di='Diizz:BAAANQADCgYICwAAAA==.',
Do='Dotomic:BAAANQAECgIIAgABNQAFFAgIHQAVAKkgAA==.',
Dr='Draesham:BAAANQAECgIIBAAAAA==.Drifthook:BAABNQAECn8qAAIWAAkK1hTyKACOAQAWAAkK1hTyKACOAQAAAA==.Drowarchon:BAAANQAECgQIBAAAAA==.Drownix:BAAANQADCgYIBgABNQAECgQIBAAQAAAAAA==.',
El='Elnaris:BAABNQAECn8aAAIBAAgKrgRbCwEMAQABAAgKrgRbCwEMAQAAAA==.',
Em='Emiliow:BAAANQADCgUIBQAAAA==.',
En='Entropy:BAAANQAECggIBwAAAA==.',
Er='Eriu:BAABNQAECn8kAAIMAAkKtR4MDQAUAwAMAAkKtR4MDQAUAwABNQAECgkJJQABAHkZAA==.Erõs:BAAANQAECgEIAQABNQAFFAUIEQAXAPEOAA==.',
Fa='Fatback:BAAANQABCgYICQAAAA==.',
['Fû']='Fûran:BAAANQAECgEIAQABNQAECggICAAQAAAAAA==.',
Ga='Ganryu:BAACNQAFFH8FAAIEAAMKMg27EQCOAAAEAAMKMg27EQCOAAA1AAQKf1oAAgQACgq/IpcKAHgDAAQACgq/IpcKAHgDAAAA.Garnio:BAAANQADCgUIBAAAAA==.',
Ge='Geosunholy:BAAANQAECgMIAwAAAA==.',
Gh='Ghoulbasher:BAAANQADCgQIBQAAAA==.',
Gi='Gitzi:BAABNQAECn9eAAIKAAoKcRsUHgBzAgAKAAoKcRsUHgBzAgAAAA==.',
Go='Goloki:BAAANQADCgIIAgAAAA==.',
Gr='Griever:BAAANQADCgEIAQAAAA==.Gripper:BAAANQADCgYIDAABNQAECggIIAALAGYVAA==.Groove:BAABNQAECn8oAAIYAAkKHh/fRAC7AgAYAAkKHh/fRAC7AgAAAA==.Groovexgroov:BAAANQADCggIBwABNQAECgoKKwABAGkfAA==.Grìmm:BAAANQAECgQIBAAAAA==.',
Gw='Gwrath:BAAANQAECgEIAgAAAA==.',
Ha='Hallena:BAAANQABCggIGwAAAA==.Harlowe:BAAANQADCggICgAAAA==.Harsh:BAAANQADCgUJBQAAAA==.Harukã:BAAANQADCggIBgAAAA==.Harúka:BAAANQAECggIAgAAAA==.',
Ho='Holyblast:BAAANQAECgQIBAAAAA==.Holyperineum:BAAANQABCgUIBgABNQAECgoKOQADACciAA==.Hordend:BAAANQAECggIEQAAAA==.',
In='Incapable:BAAANQABCgQIBAABNQAECgoKOQADACciAA==.Invisobull:BAAANQAECgYIDQABNQAECggIAwAQAAAAAA==.',
Ja='Jaam:BAAANQADCgUIBQAAAA==.Jaloe:BAAANQADCggIKwAAAA==.Jayjay:BAACNQAFFH8PAAMNAAUKMQ95DAA1AQANAAUKMQ95DAA1AQAZAAEKpAzREwBGAAA1AAQKfzMAAw0ACgrZHCYxAC0CAA0ACgr1GyYxAC0CABkABQq7H20OAMQBAAAA.',
Jo='Johnparstina:BAABNQAECn9EAAIKAAoKIiFyFgBBAwAKAAoKIiFyFgBBAwAAAA==.Jorb:BAAANQADCgQIBAABNQAECgIIAgAQAAAAAA==.',
Ka='Kainical:BAAANQAECgYIEQABNQAFFAMIBQATACYXAA==.Kainicus:BAACNQAFFH8FAAITAAMKJhfVAgB3AAATAAMKJhfVAgB3AAA1AAQKfzwAAhMACgoXHuAEAO4CABMACgoXHuAEAO4CAAAA.',
Ke='Kelador:BAAANQAECgEIAgAAAA==.',
Kh='Khaller:BAAANQABCgEIAQAAAA==.Khrism:BAAANQAECggICQAAAA==.',
Ki='Kismet:BAAANQADCggIIwABNQAECgoKOQADACciAA==.',
Ko='Kohen:BAABNQAECn8fAAIMAAoKahgwQQBmAgAMAAoKahgwQQBmAgAAAA==.Kokobubbles:BAAANQAECgIIAgAAAA==.',
Kr='Krispa:BAAANQADCggIIgAAAA==.',
Ku='Kuyaa:BAAANQADCggICgAAAA==.',
La='Larryhoover:BAAANQADCgMIAwAAAA==.',
Lo='Loathrim:BAAANQADCgcIBwAAAA==.',
Lu='Luminusrayne:BAABNQAECn9SAAIMAAoKQxTCUwAoAgAMAAoKQxTCUwAoAgAAAA==.',
Ma='Malkamechka:BAAANQADCgQIAwAAAA==.Manafest:BAAANQAECgQIEAAAAA==.',
Me='Meheret:BAABNQAECn9BAAIZAAkKsQtwDQDaAQAZAAkKsQtwDQDaAQAAAA==.',
Mi='Mint:BAAANQAECgIIAgAAAA==.',
Mo='Molgrath:BAAANQADCgIIAgAAAA==.Moomu:BAAANQADCggICAAAAA==.Morganthe:BAAANQAECgcIEQAAAA==.Moìst:BAAANQADCgcIBwAAAA==.',
My='Mydkk:BAAANQADCgEIAQABNQAECgoKIAAZAMEUAA==.Mydrood:BAAANQAECgMIAwABNQAECgoKIAAZAMEUAA==.Myhunts:BAAANQAECgIIAgABNQAECgoKIAAZAMEUAA==.Mylock:BAAANQADCgMIAwABNQAECgoKIAAZAMEUAA==.Mymaage:BAABNQAECn8gAAMZAAoKwRQ4DQDfAQAZAAgK3RQ4DQDfAQANAAgK1RDY9gCeAQAAAA==.Mymonkk:BAAANQADCggICAABNQAECgoKIAAZAMEUAA==.Mypally:BAAANQAECggICAABNQAECgoKIAAZAMEUAA==.Mypriiest:BAAANQAECgUIDQABNQAECgoKIAAZAMEUAA==.Myshammy:BAAANQAECgQIBAABNQAECgoKIAAZAMEUAA==.Mystx:BAABNQAECn8gAAMNAAkKaxa6RADlAQANAAkKTxS6RADlAQAZAAQKmhz0FQBPAQABNQAECgkJJQABAHkZAA==.Mythx:BAABNQAECn8lAAMaAAkKHBxJCwAPAgAaAAgK6xZJCwAPAgAYAAkKtRq0OwDiAQABNQAECgkJJQABAHkZAA==.Mywarr:BAAANQADCgQIBgABNQAECgoKIAAZAMEUAA==.',
Na='Narushi:BAABNQAECn8xAAMNAAoKqxp5LwAzAgANAAoKqxp5LwAzAgAZAAYKThWdFABgAQAAAA==.Natâsi:BAABNQAECn8oAAIPAAoKwhF6VgAWAgAPAAoKwhF6VgAWAgAAAA==.',
Ne='Nebulis:BAABNQAECn8sAAIKAAgKHQzxawBhAQAKAAgKHQzxawBhAQAAAA==.',
Ni='Nielas:BAAANQAECggIDQAAAA==.Nihilus:BAACNQAFFH8QAAQbAAYKyQxzCACRAQAbAAUKYw9zCACRAQAJAAMK3wb1IQB5AAAWAAEK7wC+IgAuAAA1AAQKfzgABBsACgoNIxckALECABsACgoNIxckALECABYACApYGJg5AOwBAAkABwqaF5Q1ABABAAAA.',
No='Noctium:BAABNQAECn81AAIcAAoKdh9yAwBgAgAcAAoKdh9yAwBgAgAAAA==.Nostrildamus:BAAANQADCgQIBAABNQAECgIIAgAQAAAAAA==.',
Oc='Octavior:BAAANQAECgcIDgAAAA==.',
Ow='Owls:BAACNQAFFH8PAAIMAAQKWRAaEgAPAQAMAAQKWRAaEgAPAQA1AAQKfzQAAgwACgpoIiYIAFwDAAwACgpoIiYIAFwDAAE1AAUUBAoPAAwAWRAA.Owly:BAABNQAECn8bAAIPAAoKnBzHIgDhAgAPAAoKnBzHIgDhAgABNQAFFAQKDwAMAFkQAA==.',
Pi='Pily:BAAANQAECgEIAQAAAA==.',
Po='Poizonivy:BAAANQADCggIBwAAAA==.',
Pr='Prayxx:BAAANQAECgQIBwAAAA==.Proved:BAABNQAECn8lAAIMAAoKTRRbSgBGAgAMAAoKTRRbSgBGAgAAAA==.',
Ps='Psypal:BAAANQAECgQIBgAAAA==.',
Pu='Puddingface:BAABNQAECn85AAMDAAoKJyKjBwDdAgADAAoKJyKjBwDdAgAEAAEKAABHrgA5AAAAAA==.Puggar:BAAANQADCgIJAgAAAA==.',
Ra='Ranessandi:BAAANQADCgYIBgAAAA==.Ratlemebonez:BAAANQAECgIIAgAAAA==.Ravèn:BAAANQADCgYIFwAAAA==.Razeal:BAAANQAECggIEQAAAA==.Razenal:BAAANQADCgUIBQAAAA==.Razenga:BAAANQADCgQICAAAAA==.',
Re='Regerax:BAABNQAECn8jAAIKAAkK0xgqSADGAQAKAAkK0xgqSADGAQABNQAECgkJJQABAHkZAA==.Rendani:BAAANQADCggIDQAAAA==.',
Rh='Rhettpaladin:BAAANQAECgcIDwAAAA==.Rhysan:BAABNQAECn9WAAIdAAoK0BujOwBxAgAdAAoK0BujOwBxAgAAAA==.',
Ro='Rokki:BAAANQADCgQIBAAAAA==.',
Ru='Rudeus:BAAANQAECgEIAgAAAA==.',
Ry='Rynhart:BAAANQAECgUIBQAAAA==.Ryz:BAAANQAECgIIAgABNQAFFAcIGQACAN0jAA==.',
Sa='Sacerdote:BAABNQAECn8WAAMHAAkKeBagRwB8AgAHAAkKeBagRwB8AgARAAEKew2fKgBDAAAAAA==.Sangre:BAAANQADCgUIBQAAAA==.',
Sc='Scrat:BAAANQAECggICgAAAA==.',
Se='Seasalt:BAAANQAECgQIBgAAAA==.Sebnoth:BAABNQAECn8gAAIbAAgKihcEQgAUAgAbAAgKihcEQgAUAgAAAA==.Seyer:BAAANQADCggIBAABNQAECgkJIgAYAO8QAA==.',
Sh='Shaldria:BAAANQADCgcIBwAAAA==.Shamadams:BAAANQAECgIIAgABNQAECggIAwAQAAAAAA==.Shamrox:BAAANQAECgMIBQAAAA==.Shaureille:BAAANQADCgQIBAAAAA==.Shiden:BAABNQAECn8WAAIHAAkKhRJbeQAFAQAHAAkKhRJbeQAFAQAAAA==.Shiftingtom:BAAANQADCgQIBAAAAA==.Shurlock:BAAANQAECggIAgAAAA==.',
Si='Sidepiece:BAAANQAECgQICQAAAA==.Sillyderek:BAABNQAECn8UAAIeAAUKAQgGSQDJAAAeAAUKAQgGSQDJAAAAAA==.Simpletom:BAAANQAECgYICwAAAA==.',
Sk='Skulzulu:BAAANQADCgQIAwAAAA==.',
Sm='Smallpally:BAABNQAECn8aAAIBAAgKnBHneQBeAQABAAgKnBHneQBeAQAAAA==.',
St='Stawk:BAAANQADCgYIBgAAAA==.Stellium:BAAANQAECggIAQAAAA==.Stevokerjobs:BAACNQAFFH8RAAMXAAUK8Q7JBwAjAQAXAAUK8Q7JBwAjAQAcAAMK+glYBAB6AAA1AAQKfygAAxcACgo2HDIEAOcCABcACgo2HDIEAOcCABwACQoTGQ8NAJECAAAA.',
Su='Sunwa:BAABNQAECn8lAAMBAAkKeRl+XACjAQABAAkKcBh+XACjAQAeAAIKhhAgXABrAAAAAA==.Supzz:BAAANQADCgYICAAAAA==.Suunto:BAAANQAECggIEAAAAA==.',
Sy='Syndragosa:BAAANQAECgIIAgAAAA==.',
['Sï']='Sïmba:BAAANQADCgQIBAAAAA==.',
Te='Tealth:BAAANQADCggICwAAAA==.',
Th='Thepride:BAAANQAECgUIDAAAAA==.Thicchalupa:BAAANQABCgEIAQAAAA==.Thorz:BAAANQADCggIGAABNQAECggIJQARAB4TAA==.Thundy:BAAANQAECgEIAQAAAA==.',
Ti='Tired:BAAANQADCggICAABNQAECgoKHwAMAGoYAA==.',
To='Tooms:BAAANQAECgIIAgAAAA==.Touchi:BAABNQAECn8lAAQRAAgKHhOiBwAgAgARAAgKcRKiBwAgAgAHAAUKyAla6wDzAAASAAIKLBAKWgByAAAAAA==.',
Tu='Tuo:BAAANQADCggIGQABNQAECggIJQARAB4TAA==.Turbid:BAABNQAECn87AAIUAAoK2R04CQBqAgAUAAoK2R04CQBqAgAAAA==.',
Ty='Tytank:BAAANQADCgUIBQAAAA==.',
Va='Valkkx:BAAANQADCgYICgAAAA==.',
Ve='Vexous:BAAANQADCgMIAwAAAA==.',
Vo='Voutecomer:BAAANQADCgEIAQAAAA==.',
Vu='Vurty:BAAANQAECgQICgAAAA==.',
Wa='Walls:BAAANQAECgIIAgAAAA==.',
We='Westirras:BAABNQAECn8kAAMPAAcKmwzYswAWAQAPAAYKjwnYswAWAQABAAcKpQqxqQADAQAAAA==.',
Wh='Whistler:BAAANQAECggICAAAAA==.',
Ya='Yarrow:BAABNQAECn8lAAICAAgKKxe2DAC0AQACAAgKKxe2DAC0AQAAAA==.',
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
