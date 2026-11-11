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

local lookup = {'Paladin-Protection','Mage-Arcane','DemonHunter-Havoc','Paladin-Holy','Priest-Holy','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','Priest-Discipline','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Warrior-Arms','Druid-Balance','DemonHunter-Vengeance','Warrior-Protection','Mage-Frost','Druid-Restoration','Priest-Shadow','Warrior-Fury','Warlock-Demonology','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Devourer','Warlock-Destruction',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=53,date='2026-11-10',data={Aa='Aalana:BAABNQAECn87AAIBAAoKiCJlCACvAgABAAoKiCJlCACvAgAAAA==.',
Ab='Abelle:BAAANQADCggIGwAAAA==.',
Ad='Adrialortial:BAAANQADCgcICgAAAA==.',
Ae='Aegis:BAAANQAECgYIEgAAAA==.',
Al='Aliantha:BAAANQAECgEIAgAAAA==.',
Am='Amaryllys:BAAANQADCgYIBgAAAA==.',
An='Animalstyle:BAAANQAECgQICQABNQAECgoKHQACANYWAA==.Antrus:BAABNQAECn8bAAIDAAcKsRWHOQBEAQADAAcKsRWHOQBEAQAAAA==.',
Ar='Arakhne:BAAANQADCgYIBgABNQAECgoKOAAEADogAA==.',
As='Asthar:BAAANQAECgEIAQAAAA==.',
Ba='Babyoda:BAAANQADCgIIAwAAAA==.Babysnatcher:BAAANQADCgYICgAAAA==.Banthos:BAABNQAECn9gAAIFAAoKFSPiBgC2AwAFAAoKFSPiBgC2AwAAAA==.Baroudos:BAAANQAECgEIAQAAAA==.',
Be='Bearbearbear:BAABNQAECn8lAAIGAAkKigrtJQBnAQAGAAkKigrtJQBnAQABNQAECgoKPwAHADYZAA==.',
Bi='Bifpowsplat:BAAANQAECgEIAQAAAA==.Bigguap:BAAANQAECgEIAQABNQAECgIIBAAIAAAAAA==.',
Bo='Bolla:BAABNQAECn8lAAIJAAoKLQNdiADmAAAJAAoKLQNdiADmAAAAAA==.Boundless:BAAANQAECgEIAQAAAA==.',
Br='Breadadin:BAAANQADCgQIBAAAAA==.Breadshank:BAAANQADCgUIBQAAAA==.Brtiki:BAAANQABCggIIQAAAA==.',
Bu='Bulldozer:BAAANQAECgUIBwABNQAECgoKPAAGAGsXAA==.Butchflowers:BAAANQADCgUIEAAAAA==.',
Cf='Cfodder:BAABNQAECn8nAAIHAAoKbhYjWwD7AQAHAAoKbhYjWwD7AQAAAA==.',
Ch='Chiste:BAAANQAECgIICAAAAA==.',
Co='Condemner:BAAANQABCggICwAAAA==.Covak:BAACNQAFFH8FAAMHAAQKVAg8JACjAAAHAAIKmAs8JACjAAAKAAMKAAJCIABtAAA1AAQKfykAAwoACgrjGnIRABkCAAoACQpIF3IRABkCAAcAAwqDIJnyABwBAAAA.',
Cr='Crixis:BAAANQADCgUIBQAAAA==.',
Cu='Cutcutcut:BAABNQAECn8aAAMLAAgKLwm5UAB7AQALAAcKZgm5UAB7AQAMAAcK2wVljADeAAAAAA==.',
Da='Daeleth:BAAANQABCgYIBgAAAA==.Dahlia:BAABNQAECn8xAAINAAoKpx1hGQDXAgANAAoKpx1hGQDXAgABNQAFFAcIFwAHAJUcAA==.Dalaye:BAAANQADCgcICAAAAA==.Dannica:BAAANQAECggIBAAAAA==.Dantedragon:BAAANQAECgIIAgAAAA==.Dargho:BAABNQAECn8aAAMFAAkKXR2DKQCRAgAFAAkK3ByDKQCRAgAOAAEKeiGmEQBiAAABNQAFFAQIBQAHAFQIAA==.Dastypop:BAAANQADCgUICAAAAA==.',
De='Deadpanda:BAABNQAECn86AAMPAAoKNg5tOgDoAQAPAAoKNg5tOgDoAQAQAAEKAAAGoQAAAAAAAA==.',
Dk='Dkillin:BAABNQAECn8xAAIRAAoKswuXkQCUAQARAAoKswuXkQCUAQAAAA==.',
Dr='Dreadheirark:BAAANQAECgEIAQAAAA==.',
Du='Durlag:BAABNQAECn8bAAIEAAoKIRLQLwBQAgAEAAoKIRLQLwBQAgAAAA==.',
Eb='Ebonbeef:BAAANQAECggIDwABNQAECgoKPAAGAGsXAA==.Ebonrite:BAAANQAECggIDgABNQAECgoKPAAGAGsXAA==.',
Eg='Eggosa:BAAANQADCgIIAgAAAA==.',
El='Elizalynn:BAABNQAECn8nAAIFAAoK8B4zLAC4AgAFAAoK8B4zLAC4AgAAAA==.',
Em='Emulord:BAAANQAECgcICwAAAA==.',
Ev='Everli:BAAANQADCgUICAAAAA==.',
Fa='Father:BAAANQAECgcIDAAAAA==.',
Fi='Fidgita:BAAANQAECgMIAwAAAA==.Fishguts:BAACNQAFFH8QAAISAAcKKRAIBQB5AQASAAcKKRAIBQB5AQA1AAQKf1oABBIACgpRH+gGAAEDABIACgpRH+gGAAEDABMACQq9GCkhACMCABQABgqOCscfAOoAAAAA.',
Fo='Focaccia:BAAANQAECgcIBwAAAA==.Foxthisup:BAAANQAECgQICQABNQAECgkJFAAVAIcSAA==.',
Ge='Gelid:BAAANQABCgIIAgAAAA==.',
Gl='Glasscannon:BAAANQAECgQIBAAAAA==.',
Go='Goburin:BAAANQAECgEIAQAAAA==.Goldmoorn:BAEANQAFFAEIAQAAAA==.',
Gr='Granuaile:BAABNQAECn8WAAIWAAgK+AmvQAARAQAWAAgK+AmvQAARAQAAAA==.',
Gu='Gula:BAAANQADCgYJBgAAAA==.',
Gw='Gwenianna:BAAANQADCgEIAQABNQAECgoKKQANAFsZAA==.Gwenquaya:BAABNQAECn8pAAINAAoKWxnhSAA/AgANAAoKWxnhSAA/AgAAAA==.',
Ha='Haazar:BAAANQADCggICQAAAA==.',
He='Healhealheal:BAAANQAECgUIBQAAAA==.Healohunter:BAAANQADCgYIBgAAAA==.',
Ho='Hockeydruid:BAAANQAECgYICAABNQAECgoKMQAHAJcVAA==.Hockeyhunter:BAABNQAECn8xAAIHAAoKlxWBVQAKAgAHAAoKlxWBVQAKAgAAAA==.Hoewhrmymoni:BAAANQABCgcICAAAAA==.Hoistbro:BAAANQAECgUICgAAAA==.Holydps:BAAANQADCgcIEQAAAA==.',
Hu='Huntdrath:BAAANQAECgEIBAAAAA==.Hunthunthunt:BAABNQAECn8/AAIHAAoKNhnpOgBSAgAHAAoKNhnpOgBSAgAAAA==.',
['Hè']='Hèxen:BAAANQAECgEIAQAAAA==.',
Ic='Ichaival:BAAANQAECgQIEAABNQAECgoKHgADABUNAA==.',
Ir='Irox:BAAANQADCgYIAQAAAA==.',
Je='Jedem:BAAANQADCgUIEAAAAA==.',
Ka='Kazu:BAABNQAECn8nAAIVAAoK6RC7VQDrAQAVAAoK6RC7VQDrAQAAAA==.Kazum:BAAANQAECgUIDwAAAA==.',
Ke='Keralan:BAABNQAECn8fAAIXAAkKniW3AADMAwAXAAkKniW3AADMAwAAAA==.',
Ki='Kimk:BAAANQADCgMIAwAAAA==.',
Kj='Kjevoke:BAAANQAECggIAwAAAA==.',
Kl='Klhank:BAAANQADCgEIAQAAAA==.',
Ko='Kosuke:BAAANQAECgQIBwAAAA==.',
Kr='Kromwel:BAABNQAECn8zAAIYAAoK5yTwAQA5AwAYAAoK5yTwAQA5AwAAAA==.',
Ky='Ky:BAAANQADCgUIDAAAAA==.',
La='Labrubrew:BAAANQAECggIDQAAAA==.Laizee:BAABNQAECn80AAINAAoKMgu7YQB7AQANAAoKMgu7YQB7AQAAAA==.Latrice:BAAANQAECgMIBQAAAA==.Laveyan:BAEANQAECgUICwABNQAFFAEIAQAIAAAAAA==.',
Le='Lezal:BAAANQAECggICwAAAA==.',
Li='Lilcrittêr:BAAANQAECgYIBgAAAA==.Liquidnitro:BAAANQAECggIDwAAAA==.Livsfara:BAAANQADCgUIBQABNQAECgoKOgAYAEoeAA==.',
Lo='Lone:BAABNQAECn8WAAIVAAkKgRt9IQCzAgAVAAkKgRt9IQCzAgABNQAECgoKNgAMAH8lAA==.',
Lu='Lucyreborn:BAAANQAECgUIBwAAAA==.',
Ly='Lyam:BAAANQAECgEIAQAAAA==.Lylboo:BAAANQAECgMIBAAAAA==.',
Ma='Mansamusa:BAAANQAECgIIBAAAAA==.Mawikiea:BAAANQAECgEIAQABNQAECgoKOQAFAFgdAA==.',
Me='Melander:BAABNQAECn86AAMYAAoKSh4IBwBzAgAYAAoKSh4IBwBzAgAVAAkKehDxgABwAQAAAA==.Meltman:BAAANQAECgYICwAAAA==.',
Mh='Mhoram:BAAANQAECgEIAQAAAA==.',
Mi='Micur:BAAANQAECgYICwAAAA==.Mightborne:BAABNQAECn8UAAMVAAkKhxIxnwDOAQAVAAkKhxIxnwDOAQAYAAEK5gNbSQAiAAAAAA==.Mike:BAAANQADCgEIAQAAAA==.',
Mo='Morbus:BAAANQAECgIIAwAAAA==.Mordracon:BAABNQAECn8fAAIYAAkKJRiHEAAgAgAYAAkKJRiHEAAgAgAAAA==.',
My='Myth:BAABNQAECn9mAAMZAAoKySG1AQATAwAZAAoKliG1AQATAwACAAoKCxcpZQC0AgAAAA==.',
Na='Nami:BAACNQAFFH8LAAMMAAUKZQltCAB7AQAMAAUKZQltCAB7AQALAAEK2AoJEgBBAAA1AAQKfxoAAgwACgpiFE4YABoCAAwACgpiFE4YABoCAAAA.Nazareths:BAAANQAECgEIAgAAAA==.',
Ne='Nelflander:BAAANQAECgMIAwABNQAECgoKOgAYAEoeAA==.Nemble:BAAANQABCgYIFAAAAA==.',
Og='Ogou:BAABNQAECn88AAQGAAoKaxfDEQAGAgAWAAgKixPFPQAKAgAGAAoKcxXDEQAGAgAaAAcKOQ1fRgDQAAAAAA==.',
Ok='Okorg:BAAANQADCgQIBAAAAA==.',
Om='Omnimage:BAABNQAECn8jAAICAAoKEAfHjgB2AQACAAoKEAfHjgB2AQAAAA==.',
On='Onyxz:BAABNQAECn80AAIWAAkKeRi9LAB2AgAWAAkKeRi9LAB2AgAAAA==.',
['Où']='Oùtcast:BAAANQABCggICgAAAA==.',
Pa='Panla:BAAANQADCgQIBAAAAA==.Patrickstâr:BAABNQAECn8eAAQEAAoKIhpbMgBEAgAEAAgKIB1bMgBEAgABAAQKjghOUQCgAAARAAMK2wujbQFxAAAAAA==.',
Po='Pollywag:BAAANQADCgMIAwAAAA==.',
Pr='Promethus:BAABNQAECn8UAAIRAAkKxA4VtgBOAQARAAkKxA4VtgBOAQAAAA==.',
Ra='Raedaldra:BAABNQAECn9GAAQbAAoKIB+YCADOAgAbAAoKIB+YCADOAgAFAAUKVxXErgAKAQAOAAQKAxaSEwDvAAAAAA==.Raggnarr:BAACNQAFFH8JAAMVAAUK0hfFGwA1AQAVAAUK3BLFGwA1AQAcAAIKGRRnAwCVAAA1AAQKf0AAAxwACgrKIWIDACMDABwACQoaImIDACMDABUACQqXHT8yAGgCAAAA.Ragnaroc:BAAANQABCgEIAQAAAA==.Rainesagé:BAACNQAFFH8GAAIFAAMKBQZ+IgDNAAAFAAMKBQZ+IgDNAAA1AAQKfyQAAgUACgruFblAAGgCAAUACgruFblAAGgCAAAA.Ranar:BAABNQAECn8eAAIDAAoKFQ23LwCBAQADAAoKFQ23LwCBAQAAAA==.',
Re='Remiel:BAAANQAECgEIAQAAAA==.Renatnom:BAABNQAECn8VAAIdAAQKjgJF7wBlAAAdAAQKjgJF7wBlAAAAAA==.Reäper:BAAANQABCgIIBgAAAA==.',
Ri='Rimlin:BAAANQADCgYIDAAAAA==.Rizzhashira:BAABNQAECn8vAAIBAAkKSh07EgDxAQABAAkKSh07EgDxAQAAAA==.',
Ro='Ronji:BAAANQADCgEIAQAAAA==.Rowge:BAABNQAECn8oAAIMAAoKUCFSDAANAwAMAAoKUCFSDAANAwAAAA==.Rox:BAAANQABCgQIDgAAAA==.',
Ry='Rythevia:BAABNQAECn9BAAMeAAoKzBifCwCtAgAeAAoKzBifCwCtAgAfAAcK4RRMDACTAQAAAA==.',
Sa='Sadgirls:BAABNQAECn8qAAMPAAoKyiKrDwATAwAPAAoKyiKrDwATAwAQAAEKAAAWzQBSAAAAAA==.Sandoriel:BAAANQABCgIIAwAAAA==.Satanickk:BAABNQAECn8VAAMbAAgKrBZUIwAXAgAbAAgKrBZUIwAXAgAOAAEK9gRPKwAuAAAAAA==.Satanos:BAAANQAECgEIAQAAAA==.',
Sc='Scora:BAAANQABCgEIAgAAAA==.',
Sh='Shadowraven:BAAANQADCggIBwAAAA==.Shamshamsham:BAABNQAECn8gAAIJAAkKtQ3OcwDGAQAJAAkKtQ3OcwDGAQABNQAECgoKPwAHADYZAA==.',
Sk='Skillzz:BAAANQADCgYIBgAAAA==.',
Sl='Slamcheeks:BAAANQAECggIDQAAAA==.',
Sn='Sneakybeef:BAAANQADCgYIBgABNQAECgoKOgAYAEoeAA==.Snikit:BAAANQAECgUICQABNQAECgoKOgAYAEoeAA==.',
So='Sojourner:BAABNQAECn8kAAMEAAoKsRqoGgDTAgAEAAoKsRqoGgDTAgARAAYKLxRG8gA4AQAAAA==.',
Sp='Speedy:BAAANQADCgEIAQABNQAECgoKMQAHAJcVAA==.Spellstyle:BAABNQAECn8dAAMCAAoK1hYlmgBeAQACAAkK+hYlmgBeAQAZAAEK3hU1PwBGAAAAAA==.',
St='Starblossom:BAAANQADCgEIAQAAAA==.Stimpack:BAAANQAECggICAAAAA==.',
Su='Sundaystyle:BAAANQAECgQIBwABNQAECgoKHQACANYWAA==.Sunsol:BAAANQADCggICQAAAA==.Sunspeaker:BAAANQAECggICAABNQAECgoKPAAGAGsXAA==.Superfire:BAAANQAECgQIBAAAAA==.Superspam:BAABNQAECn8iAAMWAAoKixfVOQAiAgAWAAkKzBnVOQAiAgAaAAYK3h9QNAB4AQAAAA==.',
Sy='Sylphiett:BAABNQAECn86AAICAAoKZhI/awDLAQACAAoKZhI/awDLAQABNQAFFAMIBgAgAGsFAA==.',
Ta='Tanktanktank:BAAANQAECgUIBQAAAA==.Taze:BAAANQAECgIIBAAAAA==.',
Te='Teinaras:BAABNQAECn81AAIKAAoKDhqNEAAnAgAKAAoKDhqNEAAnAgAAAA==.',
Th='Thefloydster:BAAANQAECgEIAgAAAA==.Thistledewit:BAABNQAECn8YAAIWAAgKcglMYwBBAQAWAAgKcglMYwBBAQAAAA==.Thorandodin:BAAANQADCgYIBgAAAA==.',
Ti='Tinydragon:BAACNQAFFH8FAAIeAAMKPgSYCgCvAAAeAAMKPgSYCgCvAAA1AAQKfycAAh4ACQowFB4RAEMCAB4ACQowFB4RAEMCAAE1AAUUAwgGACAAawUA.Tinyvoid:BAACNQAFFH8GAAIgAAMKawU4CgCtAAAgAAMKawU4CgCtAAA1AAQKfyIAAiAACgoIFlMaAIYCACAACgoIFlMaAIYCAAAA.Tirok:BAAANQADCgMIAwAAAA==.',
To='Togdumburz:BAABNQAECn8iAAMdAAkKURr7QwCGAgAdAAgKaBr7QwCGAgAhAAEKxBl7agBMAAAAAA==.Tortillalock:BAAANQADCgEIAQAAAA==.',
Ty='Tyberth:BAAANQABCgIIBAAAAA==.Typhon:BAABNQAECn8sAAMNAAoKCBrNKQC8AgANAAoKCBrNKQC8AgAJAAEKCwVlQAEuAAAAAA==.',
Ud='Udderlymad:BAAANQADCggIBwABNQAECgkJFAAVAIcSAA==.',
Un='Undeåd:BAABNQAECn8WAAIdAAUKSARx4gB6AAAdAAUKSARx4gB6AAAAAA==.',
Va='Vaelhyra:BAAANQAECgIIAgABNQAECgkJHwAXAJ4lAA==.Vameera:BAAANQAECgEIAQAAAA==.',
Ve='Velirine:BAABNQAECn80AAIZAAoKEBU8CQBDAgAZAAoKEBU8CQBDAgAAAA==.',
Vi='Vietsham:BAAANQAECgYICAAAAA==.Vilkas:BAACNQAFFH8HAAIKAAcKQQchDQBtAQAKAAcKQQchDQBtAQA1AAQKfxcAAgoACQqbGZcXAJwCAAoACQqbGZcXAJwCAAE1AAQKCgowACAA/SQA.Viralmessiah:BAAANQABCgIIAgAAAA==.',
Vo='Vokevokevoke:BAAANQADCgYICAABNQAECgoKPwAHADYZAA==.Vorpalite:BAAANQADCgYIBgAAAA==.',
Wa='Warspite:BAAANQADCgIIAgABNQAECgkJNAAWAHkYAA==.Warwarwar:BAABNQAECn8lAAQYAAgKGgzJHwBRAQAYAAgKGQvJHwBRAQAcAAQKzwWZIgChAAAVAAUKYQJCIwGTAAABNQAECgoKPwAHADYZAA==.',
Wo='Wolffangfist:BAAANQADCgEIAQAAAA==.',
['Xä']='Xänthe:BAABNQAECn85AAQFAAoKWB1dJADbAgAFAAoKWB1dJADbAgAOAAEKrAxmGAAyAAAbAAEK2gZhfwAsAAAAAA==.',
Yo='You:BAAANQADCgUIBgABNQAECgoKMQAHAJcVAA==.',
Za='Zarron:BAAANQADCgUIBQAAAA==.',
Zi='Zife:BAACNQAFFH8OAAITAAYKQCQFBgCyAQATAAYKQCQFBgCyAQA1AAQKfysAAhMACgo+JukHAFEDABMACgo+JukHAFEDAAAA.',
Zu='Zultarra:BAAANQADCggIIAAAAA==.',
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
