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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Mage-Arcane','DemonHunter-Vengeance','Hunter-BeastMastery','Warrior-Arms','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Druid-Balance','Unknown-Unknown','Warrior-Protection','DeathKnight-Unholy','DeathKnight-Frost','Priest-Holy','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','DeathKnight-Blood','Hunter-Survival','Druid-Guardian','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Evoker-Preservation','Rogue-Outlaw','Paladin-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Holy','Mage-Frost','Shaman-Enhancement','Priest-Discipline','Druid-Feral','Warrior-Fury','Mage-Fire',}
local provider = {region='US',realm='Darkspear',name='US',type='weekly',zone=53,date='2026-10-20',data={Ab='Abssorath:BAAANQADCgYICQAAAA==.',
Ae='Aerouant:BAABNQAECn8tAAMBAAoKyRaXBgBWAgABAAkKeReXBgBWAgACAAgKfAwuCADvAAAAAA==.',
Ai='Aidix:BAAANQAECgIIAQAAAA==.Aimassist:BAAANQAECgQIBAAAAA==.',
Al='Alaliix:BAAANQADCgEIAQAAAA==.Alcyone:BAABNQAECn8wAAIDAAoKQRt5DwDfAgADAAoKQRt5DwDfAgAAAA==.Alexstanna:BAAANQAECgEIAQAAAA==.Allophone:BAAANQADCgIIAgAAAA==.Almightyhunt:BAAANQADCgMIAwAAAA==.Altimys:BAAANQADCgIIAgAAAA==.Alwaysbroke:BAAANQAECgUIBQAAAA==.',
An='Andrena:BAAANQAECgUIBQABNQAECggIIQAEAJEVAA==.Andycat:BAAANQAECgEIAQAAAA==.Annarchy:BAAANQADCgQIBAAAAA==.Antakata:BAAANQADCgcIBwAAAA==.Antapathy:BAABNQAECn8wAAIFAAoKQBTJCQBEAgAFAAoKQBTJCQBEAgAAAA==.Anthross:BAABNQAECn8kAAIGAAgKmA9/hgD+AQAGAAgKmA9/hgD+AQAAAA==.',
Ap='Apollovon:BAABNQAECn8hAAIHAAgKcCGkLQAGAwAHAAgKcCGkLQAGAwAAAA==.Applebees:BAAANQAECgEIAQAAAA==.',
Ar='Arcanemage:BAAANQADCgYIBwAAAA==.Arcanenug:BAAANQADCgQJBAAAAA==.Arcbnonez:BAAANQAECgQIBAAAAA==.Arguxx:BAAANQAECggIDgAAAA==.Armiggy:BAABNQAECn82AAIIAAoKkhGlBADOAQAIAAoKkhGlBADOAQAAAA==.Aro:BAACNQAFFH8TAAMJAAcKcCALCgCiAQAJAAYKYB8LCgCiAQAGAAIK4huxIACwAAA1AAQKfycAAwkACgpXIhEhAEUCAAkACAofIBEhAEUCAAYABgpkH6OZANQBAAAA.Arrowraen:BAABNQAECn8rAAIGAAkK/SMfBwCkAwAGAAkK/SMfBwCkAwAAAA==.',
As='Asavera:BAAANQAECgQIBgAAAA==.Asd:BAAANQADCgQIBAAAAA==.Asecond:BAAANQADCgYJBgAAAA==.Asträl:BAAANQAECgEIAQAAAA==.',
Au='Audomere:BAABNQAECn8iAAMKAAkK2gn+dQCpAQAKAAkK2gn+dQCpAQALAAIKlgFXLQE7AAAAAA==.Auurwarr:BAAANQAECgUIBQAAAA==.',
Av='Avawrath:BAAANQAECggIDwAAAA==.Avelm:BAAANQAECggIAgAAAA==.Avraellia:BAAANQADCgYIBQAAAA==.',
Az='Azkaellon:BAAANQADCgQIBAABNQAECgoKJAAFAO0TAA==.',
Ba='Bagool:BAAANQADCgYIBgAAAA==.Ballstench:BAAANQADCgIIAgAAAA==.Barbåtos:BAAANQADCggIFwAAAA==.Baskthyr:BAAANQADCgQIBAAAAA==.Bathory:BAAANQADCgYIBgAAAA==.',
Be='Bearboi:BAABNQAECn8XAAIMAAgKSBQ1OQAmAgAMAAgKSBQ1OQAmAgABNQADCgUIBQANAAAAAA==.Bearbomblolz:BAAANQADCgQIBQABNQAECgcIDwANAAAAAA==.Bearmanakin:BAAANQADCgYICQAAAA==.Bearypotter:BAAANQADCgQICAAAAA==.Beastbane:BAAANQAECggIEgAAAA==.Beastly:BAAANQAECgUICgAAAA==.Beastmandes:BAAANQADCggIFAAAAA==.Bejeezus:BAABNQAECn8xAAMHAAoKcBeyRQC4AgAHAAoKcBeyRQC4AgAOAAgKVhTyFQDJAQAAAA==.Bel:BAAANQABCgYIDAAAAA==.Bellion:BAABNQAECn9KAAMPAAgKoBc6QgATAgAPAAgKoBc6QgATAgAQAAYKrw4AWQBHAQAAAA==.Berijar:BAAANQADCgYIBgABNQAECgIIAgANAAAAAA==.Bewslee:BAAANQAECgEIAwAAAA==.Bexx:BAAANQADCggJGQAAAA==.',
Bi='Biblehumping:BAABNQAECn8yAAMRAAoKQRaZSgBFAgARAAoKQRaZSgBFAgASAAYKEQkMQgAhAQAAAA==.Bietk:BAAANQADCgQIBwABNQAECgcIDQANAAAAAA==.Bigbonks:BAAANQAECgQIBgAAAA==.Bigoldpumper:BAAANQAECgEIAQAAAA==.Billclintun:BAAANQADCgYIBgAAAA==.',
Bl='Blackplague:BAAANQADCgQIBQAAAA==.Blaezèr:BAAANQAECgEIAQAAAA==.Bleaknight:BAAANQADCgUIBQAAAA==.Blessedbuns:BAAANQAECggICwAAAA==.Blueshamoo:BAAANQAECgEJAQAAAA==.Blupl:BAAANQABCgYIBgAAAA==.Blãezer:BAAANQAECgQIAwAAAA==.',
Bo='Bonex:BAAANQAECgEIAgAAAA==.Boomshroom:BAAANQAECgMIBAABNQAECgoKLQAIAA8cAA==.Bootsie:BAAANQADCggICAAAAA==.',
Br='Brewtoe:BAABNQAECn8UAAIIAAgKXhA2BQC/AQAIAAgKXhA2BQC/AQAAAA==.Brisketz:BAAANQADCgUIAQAAAA==.Broshunteri:BAAANQAECgEIAQAAAA==.Bruegard:BAAANQADCgIIAgAAAA==.Bruneau:BAAANQABCgUIBQAAAA==.',
Bs='Bshoutbot:BAAANQADCgUIBQABNQAFFAcIFQAJAPoaAA==.',
Bu='Bubblemehard:BAABNQAECn8cAAITAAgKMhibewAzAgATAAgKMhibewAzAgAAAA==.Bushky:BAAANQAECgUIBgAAAA==.',
By='Byahnbreath:BAACNQAFFH8FAAIQAAIK7waxGAB7AAAQAAIK7waxGAB7AAA1AAQKfyAAAhAACgocGOYEABgCABAACgocGOYEABgCAAAA.',
Ca='Cakeiko:BAAANQAECgQIBQAAAA==.Cannabinoide:BAAANQAECgIIAgAAAA==.Cannatonic:BAAANQAECgEIAQAAAA==.Carolaine:BAAANQADCgQIAgAAAA==.Casmiralda:BAAANQABCgUIBQAAAA==.Castielx:BAABNQAECn8ZAAIUAAcKthIcQQDHAQAUAAcKthIcQQDHAQAAAA==.Catnips:BAAANQAECgQIBgABNQAECgoKMgARAEEWAA==.',
Ce='Celestraza:BAAANQADCggIGwAAAA==.Celirra:BAABNQAECn8vAAIPAAoKtR9vDwA7AwAPAAoKtR9vDwA7AwAAAA==.Cennerus:BAAANQADCgIIAwAAAA==.',
Ch='Chaosreign:BAAANQADCggICwAAAA==.Cheekybaby:BAABNQAECn8nAAIHAAgKFQvbZADPAAAHAAgKFQvbZADPAAAAAA==.Cherrypoplol:BAAANQADCgUIDAAAAA==.Chocopaati:BAABNQAECn8WAAMUAAgKKxyANwD6AQAUAAcKKxyANwD6AQAVAAEKAAA3TwBDAAAAAA==.Chokma:BAABNQAECn8bAAILAAkKWhJ+HwA9AQALAAkKWhJ+HwA9AQAAAA==.Chunkyfists:BAAANQADCgMIAwAAAA==.Chëeks:BAAANQADCgUIBQAAAA==.Chìefponbury:BAAANQAECgcIEQAAAA==.',
Ci='Cinnaa:BAAANQAECgUICQAAAA==.',
Cl='Clawdog:BAAANQADCgIIAgABNQAECgIIBAANAAAAAQ==.Clawwz:BAAANQAECgIIAQAAAA==.Cleisthenes:BAAANQAECgEIAQAAAA==.Clors:BAABNQAECn8kAAIDAAkKPRz+AgB/AgADAAkKPRz+AgB/AgAAAA==.',
Co='Compressed:BAAANQAECgEIAQAAAA==.Conflux:BAAANQADCggIFAAAAA==.',
Cr='Crager:BAAANQAECgUICgAAAA==.Crawlah:BAAANQADCggIDgAAAA==.Crazegideon:BAAANQABCgIIAgAAAA==.Crazespawnz:BAAANQABCgIIAgAAAA==.Cruelbeam:BAAANQADCgQIBAAAAA==.',
Cu='Curzondax:BAAANQAECggIEQAAAA==.',
Cy='Cyberfairy:BAAANQAECgEJAQAAAA==.Cyphinx:BAAANQAECgUIBQAAAA==.',
['Câ']='Câraxes:BAAANQAECgEIAQAAAA==.',
['Cä']='Cät:BAAANQAECgEIAQAAAA==.',
Da='Dahelzforyou:BAAANQADCgcICAAAAA==.Dalìnar:BAAANQAECgUICgAAAA==.Damadafacker:BAABNQAECn8ZAAIHAAoKahXZaABVAgAHAAoKahXZaABVAgAAAA==.Darkclôud:BAAANQAECgQIBAAAAA==.Darkkatriden:BAAANQADCgYIBgABNQAECgYIFwAWALgKAA==.Darklia:BAABNQAECn8XAAIWAAYKuAq3VgDVAAAWAAYKuAq3VgDVAAAAAA==.Darthjae:BAABNQAECn9GAAMXAAkKhRnpQQD1AQAXAAkKhRnpQQD1AQAQAAEKAABQvgAfAAAAAA==.Darthmikkey:BAAANQADCgYIBgAAAA==.Darthrakk:BAABNQAECn8qAAIYAAoKZhrUAwDBAgAYAAoKZhrUAwDBAgAAAA==.Davina:BAAANQADCgcIBwABNQAFFAQIBwATAAMOAA==.Daykwan:BAABNQAECn8VAAMRAAkK8BmNJgDQAgARAAkK8BmNJgDQAgASAAEKjhEALQBIAAAAAA==.Daïn:BAAANQAECgcICgAAAA==.',
De='Deadestmoonb:BAAANQADCgIIBAAAAA==.Deathalimon:BAABNQAECn8rAAQPAAkKchfUUgDHAQAPAAgKVxLUUgDHAQAXAAcKqxe8UgCqAQAQAAEKTBBerQA0AAABNQAECgoKKAALABoSAA==.Degion:BAAANQADCgEIAQAAAA==.Deltonn:BAAANQADCgUIBQAAAA==.Demonarian:BAAANQAECgcICQABNQAECgoKKAALABoSAA==.Demonpotato:BAAANQADCggJCAAAAA==.Denardath:BAAANQADCgUIBQAAAA==.Denerrollin:BAAANQADCgIIAgAAAA==.Depthcharge:BAABNQAECn8XAAMLAAkKTwqTogBQAQALAAcKJAyTogBQAQAKAAcKsQaCuQD4AAAAAA==.Deroc:BAABNQAECn8dAAITAAgKkQbU4ABaAQATAAgKkQbU4ABaAQAAAA==.Deáthtáxi:BAAANQAECggICAAAAA==.',
Di='Digweeds:BAAANQAECggIEAABNQAFFAEIAQANAAAAAA==.Dinfarmer:BAAANQAECgUIBgAAAA==.Dirtycheese:BAAANQAECgYICwAAAA==.',
Dj='Djgha:BAAANQAECgIIBAAAAA==.',
Dm='Dmptrukdonna:BAAANQADCgEIAQAAAA==.',
Do='Dogfärts:BAAANQAECgEIAgAAAA==.Doombap:BAAANQAECgcICQAAAA==.Dorunter:BAABNQAECn8pAAMJAAgKuBJMMwCzAQAJAAcKYBJMMwCzAQAGAAMKGRITRgFTAAAAAA==.Dottíe:BAAANQAECgUIBwAAAA==.Doubledosage:BAABNQAECn8UAAIGAAYKWgcf7gAlAQAGAAYKWgcf7gAlAQAAAA==.',
Dr='Dragonbnonez:BAAANQAECgQIBAAAAA==.Dragonforge:BAAANQADCgYIDQAAAA==.Drakujin:BAAANQADCgMIBQAAAA==.Drboomboom:BAABNQAECn8VAAIEAAgKFwjbBAGFAQAEAAgKFwjbBAGFAQAAAA==.Drdoitall:BAAANQAECgYICwAAAA==.Dreadnpain:BAAANQADCgEIAQAAAA==.Dreynick:BAAANQADCgQIBAAAAA==.Dripfarming:BAAANQAECgMIAwABNQAFFAcIFAAQAMEfAA==.Drnastea:BAAANQADCgYIBgAAAA==.Drstorm:BAAANQADCgYICwAAAA==.',
Du='Duuid:BAABNQAECn8nAAIZAAkKYRjEAQBtAgAZAAkKYRjEAQBtAgAAAA==.',
Ed='Edaladalrian:BAAANQADCgUIBQAAAA==.',
El='Ella:BAAANQADCgIIAgAAAA==.Elysiá:BAAANQADCggICAAAAA==.',
En='Enhydra:BAAANQADCggICwAAAA==.Enough:BAAANQADCgcIDAAAAA==.',
Eq='Eqv:BAACNQAFFH8QAAQaAAUKohnEAQCyAAAaAAIKtBfEAQCyAAAbAAIKfR0iBQCaAAAWAAIK6AHBIAAAAAA1AAQKfyUAAxsACgqGJKoDALYCABsACApCJaoDALYCABoAAgpQIm5BAL4AAAAA.',
Er='Erayr:BAAANQAECgUICAABNQAECgUICwANAAAAAA==.Ericolson:BAABNQAECn8jAAIHAAkK1hNbVgDuAAAHAAkK1hNbVgDuAAAAAA==.Erze:BAAANQAECgUICQAAAA==.Erôman:BAAANQADCgQIBAAAAA==.',
Ev='Evosolz:BAEANQAECggICgAAAA==.Evé:BAAANQAECgMIAwABNQAECgoKLQAIAA8cAA==.',
Ey='Eyehealu:BAAANQADCgIIAgABNQAECgoKJAAbAIoPAA==.',
Ez='Ezzartkal:BAAANQAECgEIAgAAAA==.',
Fa='Faeloria:BAAANQADCgMIAwAAAA==.Farmerdragon:BAAANQADCggIDgAAAA==.Favabean:BAAANQADCgUIBQABNQAECgkJRgAXAIUZAA==.',
Fe='Feathring:BAAANQADCgYIBgABNQAECgoKKwAcAP4gAA==.Fefra:BAAANQADCgQIBAAAAA==.Felicious:BAAANQAECggIEgAAAA==.Fengshui:BAAANQADCggIGwAAAA==.Feralco:BAAANQAECgQIBAAAAA==.Fertra:BAAANQADCgYIBgAAAA==.',
Fh='Fhedrah:BAAANQADCgEIAgAAAA==.',
Fi='Fixiation:BAAANQAECgEIAQAAAA==.Fiz:BAAANQADCgYIBgAAAA==.',
Fl='Flashdance:BAAANQADCggIFAAAAA==.Fleepo:BAAANQAECgIIAwAAAA==.Fleshnbones:BAAANQADCgEIAQAAAA==.Flourie:BAABNQAECn8wAAMdAAoKYQx1DAD9AAAdAAoKYQx1DAD9AAACAAEKAAC7PgAvAAAAAA==.Flöör:BAAANQADCgUIBQAAAA==.',
Fu='Fullmetal:BAAANQAECgUICAAAAA==.Funkadelfic:BAAANQAECgYIBwAAAA==.',
['Fé']='Fénrír:BAAANQADCggIDwABNQAECggIKAALAIsiAA==.',
['Fò']='Fòxxy:BAAANQAECgMIAQAAAA==.',
Ga='Galadri:BAABNQAECn8ZAAMKAAgK/BuUQQBaAgAKAAgK/BuUQQBaAgALAAUKCxAXwwAMAQAAAA==.Garu:BAAANQADCgIIAgAAAA==.',
Ge='Geared:BAAANQAECgcIEAAAAA==.Geartryx:BAAANQADCggIDQAAAA==.Geodood:BAAANQAECgUIBwAAAA==.',
Gh='Ghoshshadow:BAAANQADCgYIEAAAAA==.Ghostinz:BAAANQAECgcIDwAAAA==.',
Gi='Gimpripper:BAAANQAECggICQAAAA==.Giztron:BAAANQADCgYIDgAAAA==.',
Gl='Glitterp:BAAANQADCgQIBAABNQAECggJIAAXAGcaAA==.Globalcold:BAABNQAECn8bAAIHAAgKLBoLdAA4AgAHAAgKLBoLdAA4AgAAAA==.Globb:BAABNQAECn8wAAIHAAgKVxSIlwDhAQAHAAgKVxSIlwDhAQAAAA==.Globius:BAABNQAECn8sAAITAAoKAxpNSgC2AgATAAoKAxpNSgC2AgAAAA==.Gloriouscole:BAAANQAECgUIDwAAAA==.Glower:BAAANQADCgEIAQAAAA==.',
Go='Gooly:BAAANQADCgIIAgAAAA==.Goombit:BAAANQADCgEIAQAAAA==.',
Gr='Greekorc:BAAANQABCgYJBwAAAA==.Greenyheals:BAAANQADCgUIBQAAAA==.Grimby:BAAANQAECgMIAwAAAA==.Grimdisney:BAAANQAECgEIAQAAAA==.Groceries:BAAANQADCgMIAwAAAA==.Gromol:BAAANQADCggIHwAAAA==.Grumby:BAAANQAECgMIBAAAAA==.',
Gu='Guifu:BAAANQADCgIIAgAAAA==.',
Gw='Gwendolÿn:BAAANQAECgQIBQAAAA==.',
['Gê']='Gêralt:BAAANQADCgQIBAAAAA==.',
Ha='Hacknhaf:BAAANQADCgYIDAAAAA==.Hakubar:BAAANQAECgQIBgAAAA==.Hatebrêêd:BAAANQADCgQIBQAAAA==.Hawaahh:BAAANQAECgUIBQAAAA==.',
He='Healman:BAAANQADCgcIGQAAAA==.Healsatute:BAAANQADCgMIAwAAAA==.Healylady:BAAANQADCgcIDAAAAA==.Heiden:BAAANQADCgYJBgAAAA==.Hel:BAAANQAECgEIAQAAAA==.Hellyas:BAAANQAECgQICAAAAA==.Herbs:BAAANQAECgEIAQABNQAECgoKMQAeAOIWAA==.Herenorthere:BAABNQAECn8vAAMSAAoKgxn6GgBxAgASAAgKEhz6GgBxAgARAAcK2xo3dQC8AQABNQAFFAQICgAbAOgVAA==.Hermippe:BAAANQAECgMIAwAAAA==.Hexstraits:BAACNQAFFH8GAAIXAAIKRBMsIACIAAAXAAIKRBMsIACIAAA1AAQKfycAAhcACgrHIiMQACwDABcACgrHIiMQACwDAAAA.',
Hi='Hia:BAACNQAFFH8TAAIXAAUKBR+hCgCtAQAXAAUKBR+hCgCtAQA1AAQKfzoAAhcACgq2ItEAACMDABcACgq2ItEAACMDAAAA.Highriskbr:BAAANQAECggICAAAAA==.Hitlist:BAAANQADCgUJBQAAAA==.',
Ho='Holycow:BAAANQAECgIIBAAAAA==.Holyfits:BAAANQADCgEIAQAAAA==.Hondacervix:BAAANQAECgYIBgAAAA==.Hondaimpala:BAAANQAECgQIBgABNQAECgkJRgAXAIUZAA==.Hoofmaster:BAAANQAECgEIAQAAAA==.Howardyou:BAAANQADCgEIAgAAAA==.',
Hu='Huffy:BAAANQAECggICgABNQAECgoKJAAHAKIhAA==.Huffyy:BAABNQAECn8kAAIHAAoKoiFeKAAYAwAHAAoKoiFeKAAYAwAAAA==.Huhdean:BAABNQAECn8hAAMQAAgKDCQMHACqAgAQAAcKsiMMHACqAgAPAAQKzyF1hQALAQAAAA==.Hulxamus:BAAANQAECgYICgAAAA==.Hunterramen:BAAANQADCgEJAQAAAA==.Hunterryan:BAAANQAECggIAQAAAA==.Hunterz:BAAANQAECgQJCQAAAA==.',
['Hé']='Héåthcliff:BAABNQAECn9BAAMfAAoKwiHUBABnAwAfAAoKLSHUBABnAwATAAgKdRzaRQDDAgABNQAECgkJHgAXAMoeAA==.',
Ic='Icyblaze:BAAANQAECggIEAAAAA==.',
Id='Idareu:BAABNQAECn8WAAIMAAgKbwTrhwC0AAAMAAgKbwTrhwC0AAAAAA==.',
If='Ifstar:BAAANQAECgMIBAAAAA==.',
Il='Illumi:BAAANQADCgQIBwABNQAECgUICQANAAAAAA==.',
Im='Immigrant:BAAANQADCggICAAAAA==.',
In='Indominus:BAAANQADCgIIAgAAAA==.',
Ir='Ires:BAAANQADCgUIBQAAAA==.',
Is='Ishadow:BAAANQAECgUIBgAAAA==.Issalis:BAAANQADCgYIBgAAAA==.',
It='Itheusvalles:BAAANQADCggIEgAAAA==.Itsjerry:BAAANQADCgYICQAAAA==.',
Iw='Iwillcrushyo:BAAANQAECgcICwAAAA==.',
Iz='Izonie:BAAANQAECgUIBQABNQAFFAMICgALAFsVAA==.',
Ja='Jaimerrek:BAAANQAECgUICwAAAA==.Jainalynn:BAAANQADCgYIEwAAAA==.Jalenbrunson:BAAANQADCgEIAQAAAA==.Jazira:BAABNQAECn8uAAMDAAoKkAy+CQCbAQADAAgKxwy+CQCbAQAMAAgKxwIeOAB7AAAAAA==.',
Jd='Jdarkside:BAAANQAECgYIDwAAAA==.',
Je='Jebediahmoon:BAAANQAECggIEAABNQAECgkJRgAXAIUZAA==.Jeremmiah:BAAANQADCgcIEwAAAA==.',
Jh='Jhacobo:BAABNQAECn8mAAIMAAoKqBXzEABSAQAMAAoKqBXzEABSAQAAAA==.',
Jo='Jojupobu:BAAANQADCggICAAAAA==.Jorkinit:BAABNQAECn8cAAIEAAkKZxE6RQAyAQAEAAkKZxE6RQAyAQAAAA==.',
Jr='Jragon:BAABNQAECn8hAAIWAAgKbQoFlwCtAQAWAAgKbQoFlwCtAQAAAA==.',
Ju='Judis:BAAANQABCgYICwAAAA==.Juicedh:BAAANQADCgUIBQAAAA==.Juicy:BAABNQAECn8cAAIEAAoKFBwVKQB1AQAEAAoKFBwVKQB1AQAAAA==.Junipur:BAAANQAECgMICQAAAA==.',
Jx='Jxxy:BAACNQAFFH8MAAMGAAQKYRsAFQAXAQAGAAQKYRsAFQAXAQAJAAIKjxAxHACPAAA1AAQKfxoAAwYACgouH+fSAFsBAAYACQp/IefSAFsBAAkAAgqJGXpiAJ8AAAE1AAUUBAoMAAYAYRsA.',
['Jú']='Júnjúnwälä:BAABNQAECn8dAAIDAAgKqSQHDgDwAgADAAgKqSQHDgDwAgAAAA==.',
Ka='Kalories:BAAANQAECgUICwAAAA==.Kalvoid:BAAANQAECgQIBAABNQAECgUICwANAAAAAA==.Kandance:BAAANQAECggIEQAAAA==.Karlmagnus:BAAANQADCgcIBwAAAA==.',
Ke='Kelvintwo:BAAANQADCgQIAwAAAA==.',
Ki='Kimbopable:BAAANQAECgUIBQABNQAECgkJRgAXAIUZAA==.Kittyÿ:BAAANQAECgYICwAAAA==.',
Kn='Knurl:BAAANQADCgMIAwAAAA==.',
Ko='Korak:BAAANQADCgUIBQABNQADCgYIBgANAAAAAA==.Korgh:BAAANQAECgEIAQAAAA==.Kosari:BAAANQAECgEIAQABNQAECgQIBQANAAAAAA==.',
Kr='Krystall:BAABNQAECn8kAAIbAAoKig/NBwAbAgAbAAoKig/NBwAbAgAAAA==.',
Ku='Kuarahy:BAAANQAECgcIEAAAAA==.Kunfugrip:BAABNQAECn8tAAIIAAoKDxxsBgCoAQAIAAoKDxxsBgCoAQAAAA==.Kurizmuh:BAAANQADCgUIBwAAAA==.',
['Kà']='Kàl:BAAANQAECgIIAgABNQAECgUICwANAAAAAA==.',
['Kã']='Kãl:BAAANQADCgYIBgABNQAECgUICwANAAAAAA==.',
['Kì']='Kìngknìghts:BAABNQAECn8XAAMQAAYK5gz5LwDcAAAQAAUKBQr5LwDcAAAPAAQKYA/ANwB8AAAAAA==.',
La='Lanthos:BAABNQAECn86AAIgAAoKcB3WCwAiAwAgAAoKcB3WCwAiAwAAAA==.Lapulapu:BAAANQADCgYIBgAAAA==.Larthal:BAAANQAECgQIBgAAAA==.Latinpapi:BAABNQAECn8oAAMTAAoK5hNydABFAgATAAoK5hNydABFAgAfAAEKAAB5aQBAAAAAAA==.Lawlita:BAAANQAECgEIAQAAAA==.',
Le='Leemiez:BAAANQADCgUIDgAAAA==.Lexìe:BAAANQAECgEIAQAAAA==.Leyära:BAAANQAECgIIBAAAAA==.',
Li='Lielys:BAAANQAECgIIAgABNQAECgUIFQAJAPETAA==.Lilina:BAABNQAECn8eAAMFAAgKlBXACwAQAgAFAAcKtBnACwAQAgAhAAEK9wBGWQATAAAAAA==.Liljaejae:BAAANQADCgEIAQAAAA==.',
Lm='Lmn:BAAANQADCgUIBwAAAA==.',
Lo='Lonweh:BAAANQAECgMIBAAAAA==.Lousmage:BAAANQADCgUIBQAAAA==.Loza:BAAANQADCgUICwABNQAECggIFgAGAGMNAA==.',
Lu='Lucith:BAABNQAECn8wAAIQAAoKZCFJBgB+AwAQAAoKZCFJBgB+AwAAAA==.Luckie:BAAANQABCgQIBwABNQAFFAYIDwAiABEQAA==.Lulafairy:BAAANQAECgEJAQAAAA==.Lumador:BAAANQAECgQIBwABNQAECgcIIAASAIQUAA==.Lunatick:BAABNQAECn8lAAQQAAoKMg37HQAvAQAQAAoKaAr7HQAvAQAXAAMKzRuphwDgAAAPAAUK6wMSpwCqAAAAAA==.Lunawa:BAACNQAFFH8IAAIEAAUKSx3DGQCsAQAEAAUKSx3DGQCsAQA1AAQKf0wAAwQACgoWJsUAAFoDAAQACgoWJsUAAFoDACMAAwpLETMtAJQAAAAA.Lustbót:BAABNQAECn8bAAIEAAkKGweA6AC5AQAEAAkKGweA6AC5AQAAAA==.Luvnrdjr:BAAANQADCgYIBgAAAA==.',
Ly='Lynnai:BAAANQAECgQIBQAAAA==.Lynxmi:BAAANQADCgEIAQAAAA==.Lyse:BAACNQAFFH8SAAIhAAUK8CAOBwDPAQAhAAUK8CAOBwDPAQA1AAQKfy4AAiEACgp9JM0FAJgDACEACgp9JM0FAJgDAAAA.',
['Lê']='Lêvak:BAAANQADCgIIAgAAAA==.',
['Lí']='Líllith:BAAANQADCgYJBgAAAA==.',
['Lô']='Lôuku:BAABNQAECn8tAAIWAAgK0BtCQwCIAgAWAAgK0BtCQwCIAgAAAA==.',
Ma='Maahn:BAAANQADCgcICAAAAA==.Macalob:BAAANQAECgQIBgAAAA==.Madallar:BAABNQAECn8WAAIHAAgKow9+rQCrAQAHAAgKow9+rQCrAQAAAA==.Magdagni:BAABNQAECn8XAAIkAAcKDRHqHACVAQAkAAcKDRHqHACVAQAAAA==.Mageji:BAACNQAFFH8MAAIEAAUK8iAwIACFAQAEAAUK8iAwIACFAQA1AAQKfzoAAgQACgqnJfcWAHgDAAQACgqnJfcWAHgDAAE1AAMKBggGAA0AAAAA.Magepies:BAAANQAECgQIBgABNQAECgQICAANAAAAAA==.Magicfurry:BAAANQAECgUICgABNQAECgoKMgARAEEWAA==.Mainveinz:BAABNQAFFH8KAAIXAAUKCQF3DQB/AAAXAAUKCQF3DQB/AAAAAA==.Malicelx:BAAANQAECgIIAgABNQAECggIDgANAAAAAA==.Mallgoth:BAABNQAECn8VAAIGAAYK9gVX+gAPAQAGAAYK9gVX+gAPAQAAAA==.Manohar:BAABNQAECn8tAAMKAAoKkh0tKwC2AgAKAAoKkh0tKwC2AgALAAcKzw7MggCeAQAAAA==.Mardtard:BAABNQAECn8XAAMGAAcKtx+zCwAWAgAGAAcKtx+zCwAWAgAJAAMKigksZQCWAAABNQAECgUIBgANAAAAAA==.Marximilian:BAAANQAECgMIAwAAAA==.',
Mc='Mcflurryz:BAAANQADCgUIBQAAAA==.Mcgrubert:BAAANQAECgIJAgABNQAFFAUICgAJAFsXAA==.',
Me='Mechachad:BAAANQAECgMIAwAAAA==.Medmasters:BAAANQABCgIIAgAAAA==.Megamango:BAAANQAECgUIBQABNQAFFAIIBQAjANUfAA==.Mehiel:BAAANQAECgcIDQAAAA==.Meive:BAAANQADCgMIAwAAAA==.Menime:BAAANQADCgYIBgAAAA==.Meraxes:BAAANQAECgEIAQAAAA==.Merdune:BAAANQADCgEIAQAAAA==.Merkén:BAAANQAECggIDwAAAA==.Metaloclypse:BAAANQADCgcIDgAAAA==.Meteas:BAAANQAECgQIBAAAAA==.Mezaryn:BAABNQAECn8VAAITAAoKxAfoEQEBAQATAAoKxAfoEQEBAQABNQAECgoKLQADACQHAA==.Mezgrim:BAAANQAECggIAgABNQAECgoKLQADACQHAA==.Mezzoo:BAABNQAECn8tAAIDAAoKJAf7RwD0AAADAAoKJAf7RwD0AAAAAA==.',
Mi='Midger:BAAANQADCgQIBAAAAA==.Mikitaju:BAAANQAECgEIAQABNQAECgcIDwANAAAAAA==.Millic:BAABNQAECn8pAAMlAAkK/hTjAADjAQAlAAkK/hTjAADjAQASAAEKYQf6dgA5AAAAAA==.Millish:BAAANQADCgQIBAAAAA==.Minax:BAAANQAECgMIBAAAAA==.Missionsena:BAAANQAECgEJAQAAAA==.Mitzrael:BAAANQADCgYICAAAAA==.',
Mo='Mongolious:BAAANQAECgEIAQAAAA==.Moozx:BAAANQAECgEIAQAAAA==.Mosfeat:BAAANQADCggICAABNQAECgkJGgAkACUYAA==.',
Mu='Muckdile:BAAANQAECgQIBAAAAA==.Muckstab:BAAANQAFFAEIAQAAAA==.Mux:BAAANQADCggIDQAAAA==.',
Na='Narayeda:BAABNQAECn8aAAIhAAgKKwc6UQBRAQAhAAgKKwc6UQBRAQAAAA==.Nasuadia:BAAANQADCggIIQABNQAECgoKKwAQANIcAA==.',
Ne='Necrolysis:BAAANQAECgQIBAAAAA==.Necromansorz:BAAANQAECggICAAAAA==.Nekkash:BAAANQAECgYICgAAAA==.Neredir:BAAANQADCgYIBgAAAA==.Netoraresan:BAAANQAECggIAQAAAA==.Newwt:BAAANQAECgQIBgAAAA==.Neytiri:BAAANQABCgQJBQAAAA==.Nezelle:BAABNQAECn8YAAIdAAgKPg1rKQBmAQAdAAgKPg1rKQBmAQABNQAECgoKMQAeAOIWAA==.',
Ni='Nimou:BAAANQADCggICAAAAA==.',
No='Nomaa:BAAANQADCgQIBAAAAA==.Noris:BAAANQAECggIDgAAAA==.Norros:BAAANQAECgIIBAAAAA==.Novacaine:BAAANQADCgcIBwAAAA==.',
Nu='Nuvi:BAAANQAECgQIDAAAAA==.Nuvostaph:BAABNQAECn8cAAImAAkKmR0aAgDhAQAmAAkKmR0aAgDhAQAAAA==.',
Od='Odecias:BAAANQADCgUICQAAAA==.',
Og='Ogbrew:BAAANQADCgcIEAAAAA==.',
Oh='Ohiyaa:BAAANQADCgQIBAAAAA==.',
Or='Orcboken:BAAANQAECgMIBAAAAA==.Orezn:BAAANQAECgQICgAAAA==.',
Pa='Pabby:BAAANQABCgIIBAAAAA==.Painting:BAAANQAECgEIAQABNQAECgcIHgAhAGQgAA==.Pallypusher:BAAANQADCgQICAAAAA==.Papiace:BAAANQAECgYIDgAAAA==.Pato:BAABNQAECn8UAAMHAAgKnBxVeQAsAgAHAAgKnBxVeQAsAgAOAAEKBhhlQQA6AAAAAA==.',
Ph='Phatnips:BAABNQAECn8vAAMWAAoK1A3CZQApAgAWAAoK1A3CZQApAgAaAAEKxgONhAAmAAAAAA==.',
Pi='Piesniper:BAAANQABCgIIAgABNQADCgYIDAANAAAAAA==.Pigeon:BAAANQADCgUIBgAAAA==.',
Pn='Pnuts:BAACNQAFFH8RAAISAAYKRg88AgA5AQASAAYKRg88AgA5AQA1AAQKfzMAAhIACgruGZQRAOMCABIACgruGZQRAOMCAAAA.',
Po='Popedragon:BAAANQAECgEIAgAAAA==.Poshh:BAAANQADCgQIBAAAAA==.',
Pr='Prayihealu:BAAANQADCgYIBwAAAA==.Pres:BAAANQADCgIIAgAAAA==.Prisonmike:BAABNQAECn8XAAIUAAkKAxksKwA9AgAUAAkKAxksKwA9AgAAAA==.Promisa:BAAANQAECggICQAAAA==.Promise:BAAANQAFFAEIAQAAAA==.Prophets:BAAANQADCgMIBQAAAA==.Prucifix:BAAANQAECgEIAQAAAA==.Pryome:BAABNQAECn8YAAIEAAgKmQpL3gDLAQAEAAgKmQpL3gDLAQABNQAECgoKKAALABoSAA==.',
Pu='Puddiñ:BAAANQADCgMIAwAAAA==.Puffindaboof:BAAANQAECgIIAgAAAA==.Punchju:BAAANQAECgEIAQAAAA==.Punkz:BAAANQADCgYICAABNQAECggIGQAKAPwbAA==.Punpal:BAAANQADCgYIBgAAAA==.Pushmaa:BAAANQAECgYJCwAAAA==.',
Py='Pyromortis:BAAANQAECgYIEAABNQAECgoKMgARAEEWAA==.Pytorch:BAABNQAECn9XAAIEAAkK6x9nAgDzAgAEAAkK6x9nAgDzAgAAAA==.',
['Pø']='Pø:BAAANQAECgQIBAAAAA==.',
Qu='Queelex:BAAANQAECgcIDAABNQAECggIGQAKAPwbAA==.Quigzz:BAACNQAFFH8FAAIVAAMKyQdYDQDHAAAVAAMKyQdYDQDHAAA1AAQKfywAAhUACgqkHV8GABsDABUACgqkHV8GABsDAAAA.Quinnie:BAAANQAECgcIEAABNQAECggIEQANAAAAAA==.',
Ra='Raganarok:BAAANQAECgIIAgAAAA==.Rahja:BAAANQAECgYICQAAAA==.Ramss:BAAANQAECggIEAAAAA==.Ranch:BAAANQADCgUIBQAAAA==.',
Re='Realtrendy:BAAANQADCggICAABNQAECggIJAAWANYSAA==.Redranse:BAAANQADCgQIBAAAAA==.Reebs:BAAANQAECggICwAAAA==.Resa:BAAANQAECgQICAAAAA==.Restomania:BAAANQADCgMIAwAAAA==.',
Ri='Ricasti:BAAANQAECgYICwAAAA==.Ritsu:BAAANQAECgQIBwAAAA==.',
Ro='Robinsonic:BAABNQAECn8eAAIZAAkKEhjkBgCVAQAZAAkKEhjkBgCVAQAAAA==.Rokenn:BAAANQADCggICAAAAA==.Rosabetsy:BAAANQADCgIIAgAAAA==.Rosetastoned:BAAANQADCgIIAgAAAA==.',
Ru='Rukiè:BAAANQAFFAEIAQAAAA==.Runmyrkr:BAAANQAECgcIEgAAAA==.',
['Rô']='Rôbert:BAAANQAECgYICQAAAA==.',
Sa='Saberyn:BAAANQAECgcIEAAAAA==.Sacredsassy:BAAANQAECgYIDAAAAA==.Saenya:BAABNQAECn8YAAISAAcK7RWWKgDSAQASAAcK7RWWKgDSAQAAAA==.Sageofwampa:BAAANQADCgEIAQAAAA==.Sahra:BAAANQADCggICAAAAA==.Samavanas:BAAANQADCggIBgAAAA==.Sassynova:BAAANQADCgYICQAAAA==.',
Sc='Schvitz:BAABNQAECn8aAAIGAAoKdRNIGAC5AQAGAAoKdRNIGAC5AQAAAA==.Scopeftis:BAABNQAECn8ZAAIPAAoKTx6MJQCoAgAPAAoKTx6MJQCoAgAAAA==.',
Se='Seano:BAAANQAECgMIAwAAAA==.Seberology:BAABNQAECn8oAAIiAAkKEBJ8SgA+AgAiAAkKEBJ8SgA+AgAAAA==.Segagamecube:BAAANQADCgMIAwAAAA==.Sepatown:BAAANQADCggICAAAAA==.Sephi:BAAANQADCgQIBAAAAA==.Sergal:BAAANQADCggICAABNQAECgMICQANAAAAAA==.',
Sh='Shaco:BAAANQAECgMIAwAAAA==.Shamanpizza:BAAANQADCgMIAwAAAA==.Shamjam:BAAANQAECgQICQABNQAECggIDgANAAAAAA==.Shamownage:BAABNQAECn8oAAMLAAoKGhJRgQChAQALAAcKABJRgQChAQAKAAoKFxLLHgBvAQAAAA==.Shankyews:BAAANQADCgQJBAAAAA==.Sheev:BAAANQADCgEIAQAAAA==.Shepling:BAACNQAFFH8KAAIXAAUKMg2WEwAhAQAXAAUKMg2WEwAhAQA1AAQKfxQAAhcACAp7FfZGAN0BABcACAp7FfZGAN0BAAAA.Shifterella:BAAANQAECgMIBQAAAA==.Shifu:BAACNQAFFH8HAAIIAAIKghuvBgCMAAAIAAIKghuvBgCMAAA1AAQKfxsAAwgACQqMHvAaAGYCAAgABwoJIvAaAGYCABwABwqEFU4VAI8BAAAA.Shivàh:BAACNQAFFH8PAAMPAAUKOBrkBwCbAQAPAAUKOBrkBwCbAQAQAAMKexLDEADTAAA1AAQKfyMAAxAACgpHIjghAIQCABAACgpHIjghAIQCAA8AAwqkIViDABEBAAAA.Shneezleberg:BAABNQAECn8mAAMHAAoK+xoBOADkAgAHAAoK+xoBOADkAgAnAAQKvgrJIwCVAAAAAA==.Shädowcraft:BAAANQADCgUIBQAAAA==.',
Si='Sildormi:BAAANQAECgEIAQAAAA==.Sithrage:BAAANQADCgQIBAAAAA==.Sizzlinghots:BAAANQAECggIEgAAAA==.',
Sk='Skateboardp:BAAANQADCgYIBgAAAA==.Skiddlywinks:BAAANQADCgYIFAABNQAECgcIDwANAAAAAA==.Sko:BAABNQAECn8fAAIHAAkKPRkKVwCGAgAHAAkKPRkKVwCGAgAAAA==.Skár:BAAANQADCggICwAAAA==.',
Sl='Sladak:BAAANQAECgIIAgAAAA==.Slimjimm:BAAANQAECgUIBwABNQAECgcIDAANAAAAAA==.',
Sn='Snackdad:BAAANQADCgMIBAAAAA==.Sneakyky:BAAANQADCggIEgAAAA==.Sneakymoomoo:BAAANQADCgYJBgABNQAECgoKMgARAEEWAA==.Snipagooly:BAAANQAECgEIAQAAAA==.Snowyrain:BAAANQAECgUICgAAAA==.',
So='Sojourner:BAAANQAECgcIEgAAAA==.Solanum:BAAANQADCgQIBAABNQAECgQIBQANAAAAAA==.Solkar:BAAANQADCgcJCwAAAA==.Solo:BAABNQAECn8pAAITAAoKShPUbQBVAgATAAoKShPUbQBVAgAAAA==.Soupsandwich:BAAANQAECgMIBAAAAA==.Sourless:BAAANQAECgEIAQAAAA==.',
St='Stagg:BAABNQAECn8qAAIEAAoKphNjnABIAgAEAAoKphNjnABIAgAAAA==.Stankazz:BAAANQABCgQIBAAAAA==.Stankytotems:BAAANQADCgcIEQAAAA==.Stinkcheese:BAAANQAECgEIAQAAAA==.Stkk:BAAANQAECggICAAAAA==.Stonedkritz:BAAANQABCgMIAwAAAA==.',
Su='Sunarii:BAABNQAECn8UAAISAAgKmxREIQAtAgASAAgKmxREIQAtAgAAAA==.Sunroof:BAAANQADCgMIBgAAAA==.Superbroke:BAAANQABCgIIAgAAAA==.Superpoor:BAAANQABCgEIAQAAAA==.',
Sw='Swagalito:BAAANQADCgUIBgAAAA==.',
['Sà']='Sàviorself:BAAANQAECgIIAwAAAA==.',
['Sý']='Sýlvanàs:BAAANQADCgMIAwAAAA==.',
Ta='Taelian:BAAANQADCgYICQAAAA==.Talanath:BAABNQAECn8jAAIdAAoKmAhyCwAMAQAdAAoKmAhyCwAMAQAAAA==.Taldor:BAAANQABCgMIAwAAAA==.Talwayn:BAAANQADCgUICgABNQAECgcIDwANAAAAAA==.Tanarran:BAAANQADCgUIBQAAAA==.Tatooth:BAAANQADCgQIBAAAAA==.Tazoo:BAABNQAECn8aAAMkAAgKqQKPIgAzAQAkAAgKqQKPIgAzAQAKAAEKygi4KQEkAAAAAA==.',
Te='Teamfluffer:BAAANQADCgUICQAAAA==.Tee:BAAANQADCgcIDQAAAA==.Tehzuurmx:BAAANQADCggICAAAAA==.Telps:BAAANQADCgIIAgAAAA==.Teranosouth:BAAANQABCgMIAwAAAA==.Terebitha:BAAANQABCgMIAgAAAA==.Termina:BAAANQAECgEIAQAAAA==.Teruulos:BAAANQAECgYICwAAAA==.',
Th='Thabeast:BAAANQAECgEIAQAAAA==.Thadeouss:BAABNQAECn8sAAIRAAoKkh2nGACuAQARAAoKkh2nGACuAQAAAA==.Thadiusx:BAAANQABCgIIAgAAAA==.Tharon:BAABNQAECn8dAAIGAAkKhRYeZgBIAgAGAAkKhRYeZgBIAgAAAA==.Thebigboom:BAABNQAECn8yAAIZAAoKKhk7CgDNAgAZAAoKKhk7CgDNAgAAAA==.Thecarter:BAAANQAECgIIAgAAAA==.Thoomahawk:BAAANQADCgIIAgAAAA==.Threnody:BAABNQAECn8cAAMJAAcKXQ4CEQAAAQAJAAcKcQ0CEQAAAQAGAAIKDBMtNAGAAAAAAA==.',
Ti='Tichalock:BAAANQADCgIIAgABNQAECgEIAQANAAAAAA==.Tichemort:BAAANQADCgcICwAAAA==.Tigerchimon:BAAANQADCgUIBQABNQAECgoKKAALABoSAA==.Tinglem:BAAANQADCgYICwAAAA==.',
To='Toeclipper:BAAANQADCgYIBgAAAA==.Tolivold:BAAANQAECgQICAAAAA==.Tomeoz:BAAANQAECgEIAQAAAA==.Toxicsocks:BAACNQAFFH8GAAMoAAMK9QOnAACIAAAoAAIK6ASnAACIAAAEAAIK5AOaUACBAAA1AAQKfzMAAygACgoVHOsAAAoDACgACgoVHOsAAAoDAAQABAprCgKQAacAAAAA.',
Tr='Trapscallion:BAAANQAECgQIEAAAAA==.Trashcaster:BAAANQADCgcIDAAAAA==.Treeknight:BAABNQAECn8fAAIPAAgKOBRISQDxAQAPAAgKOBRISQDxAQAAAA==.Treelimbs:BAAANQAECgcIDwAAAA==.Tridity:BAAANQAECgYIDwAAAA==.Trollolollz:BAAANQAECgIIAwAAAA==.',
Ts='Tsuuna:BAABNQAECn8rAAMHAAoKaB9xDwDdAQAHAAoKaB9xDwDdAQAOAAEKAABxPgBIAAAAAA==.',
Tu='Turtleqt:BAAANQABCgEIAQAAAA==.',
Ty='Tylanar:BAAANQADCgYIBgABNQAECgIIBAANAAAAAA==.Tylandon:BAAANQAECgYICQAAAA==.Tyralthas:BAAANQADCgQIAwAAAA==.',
['Tê']='Tênaciousv:BAAANQAECgIJAwAAAA==.',
['Të']='Tëhzoo:BAAANQABCgIIAgAAAA==.',
['Tì']='Tìnnitus:BAAANQABCgMIBAAAAA==.',
Ug='Uglyboyryan:BAAANQAECgMIAwAAAA==.',
Un='Unavaluable:BAAANQAECgEIAgAAAA==.Ungodlyy:BAAANQAECgUIDQAAAA==.Untöuchable:BAABNQAECn86AAMTAAoKCSGAAwDWAgATAAoKCSGAAwDWAgAiAAEK4gEwNgEhAAAAAA==.',
Ur='Urskrog:BAAANQADCggIEwAAAA==.',
Va='Vanthelos:BAAANQADCgQIBQAAAA==.',
Ve='Velachlan:BAAANQAECgUIDwAAAA==.Verdtual:BAAANQADCgMIAwAAAA==.Veredelyse:BAABNQAECn8xAAQeAAoK4habBwA3AgAeAAgKbRmbBwA3AgAVAAcKzA8rLQBYAQAUAAMK9RLXfQC8AAAAAA==.Verxl:BAABNQAECn8cAAIEAAcKFRTBPgA/AQAEAAcKFRTBPgA/AQAAAA==.',
Vi='Vihn:BAAANQADCgYIBgAAAA==.',
Vo='Voidnyou:BAAANQADCgQJCAAAAA==.Volumes:BAAANQAECgUIBwAAAA==.Volund:BAABNQAECn8tAAIkAAoKkwbjDAAsAQAkAAoKkwbjDAAsAQAAAA==.',
Vy='Vynsong:BAABNQAECn8fAAIiAAkKsR/uDwDYAQAiAAkKsR/uDwDYAQAAAA==.Vyz:BAAANQADCgQIBAABNQAECgQIBAANAAAAAA==.',
Wa='Warwalkerz:BAAANQADCggIFgAAAA==.Watchmebløck:BAAANQAECgQIBAAAAA==.Watermalorne:BAAANQAECgMIAwAAAA==.',
We='Weemies:BAAANQAECgUIBgAAAA==.Wetmonk:BAAANQAECgcIDQAAAA==.',
Wh='Whoyerdaddy:BAAANQAECgUIBgAAAA==.Whywhybecuz:BAAANQADCgQIBAAAAA==.',
Wi='Wickedal:BAAANQADCgIIAgAAAA==.Winndfurry:BAAANQADCgMIAwAAAA==.Winnototem:BAABNQAECn8wAAMKAAoKJBJ3WwD9AQAKAAoKJBJ3WwD9AQALAAUKMBRdqwA9AQAAAA==.Wisakedjak:BAAANQADCggIGwAAAA==.',
Wo='Wombatman:BAAANQAECgQICQAAAA==.Wong:BAAANQAECgUIBgAAAA==.',
Wu='Wutpuddle:BAAANQADCggIAQAAAA==.',
Xi='Xiaoshui:BAAANQADCgYIBgAAAA==.',
Xu='Xugos:BAABNQAECn8cAAIWAAoKBxUbZgAoAgAWAAoKBxUbZgAoAgAAAA==.',
Ya='Yatagarasu:BAAANQAECggIAgAAAA==.',
Ye='Yenafer:BAAANQADCggICAAAAA==.',
Yo='Yochill:BAAANQAECgIIAgABNQAECgUICgANAAAAAA==.Yolokin:BAAANQADCgcIGAAAAA==.Yooper:BAAANQADCgcIBgAAAA==.Yota:BAAANQAECgMIAwAAAA==.',
Yr='Yrgg:BAAANQAECgYICwAAAA==.',
Yt='Ytgamezoned:BAAANQADCgQIBAAAAA==.',
Za='Zadanthra:BAAANQAECgcIDwAAAA==.Zapadin:BAABNQAECn8pAAITAAkKvhQeHwCmAQATAAkKvhQeHwCmAQAAAA==.Zaphodè:BAAANQAECgQIBAAAAA==.',
Ze='Zeenie:BAAANQAECggIBQABNQAECgkJIAAHAOgRAA==.Zephian:BAAANQAECgMIAwAAAA==.Zephsham:BAAANQADCgYIDAAAAA==.Zerokool:BAAANQABCgMIAwAAAA==.',
Zi='Zimone:BAAANQADCgMIAwAAAA==.',
Zo='Zoerik:BAABNQAECn8gAAQlAAgKAAubCwCFAQAlAAgKAAubCwCFAQARAAYK2wN8sQACAQASAAUKNgWpUQDKAAAAAA==.Zotoperen:BAABNQAECn8rAAMcAAoK/iBkAwBdAwAcAAoK/iBkAwBdAwAIAAMKFhHoUgClAAAAAA==.',
Zy='Zylergy:BAABNQAECn8cAAITAAoKPgnZZQD6AAATAAoKPgnZZQD6AAAAAA==.',
['Zì']='Zìfu:BAAANQADCggICQAAAA==.',
['Àv']='Àvicant:BAAANQAECgUJBwABNQAFFAQICAAGAFMiAA==.',
['Än']='Ändo:BAAANQAECgUIDgAAAA==.',
['Äy']='Äy:BAAANQABCgEIAQAAAA==.',
['Çy']='Çyrin:BAABNQAECn8wAAMiAAkKsBPMCgAXAgAiAAkKsBPMCgAXAgATAAEK5QhHpwEzAAAAAA==.',
['Çø']='Çørpsë:BAAANQABCgIJAgAAAA==.',
['Ëu']='Ëuphoria:BAAANQADCgQIBAAAAA==.',
['Ün']='Üna:BAAANQADCggIEAAAAA==.',
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
