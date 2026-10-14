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

local lookup = {'Druid-Balance','Warrior-Protection','Mage-Arcane','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','Evoker-Preservation','Paladin-Protection','DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Shaman-Elemental','Monk-Brewmaster','Hunter-BeastMastery','Warrior-Arms','Druid-Restoration','Shaman-Restoration','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Priest-Holy','Warrior-Fury','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Unholy','Mage-Frost','Druid-Feral','Shaman-Enhancement','Evoker-Devastation','Hunter-Survival','Priest-Discipline','Priest-Shadow','Evoker-Augmentation','Monk-Mistweaver','Druid-Guardian',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abaz:BAAANQAECgQIBgAAAA==.Aberdus:BAABNQAECn8hAAIBAAgKQRF6QgDpAQABAAgKQRF6QgDpAQAAAA==.Abysswalker:BAAANQADCgQIBAAAAA==.',
Ac='Accalon:BAABNQAECn8ZAAICAAcKlSQnBwDpAgACAAcKlSQnBwDpAgAAAA==.',
Ad='Advacus:BAACNQAFFH8JAAIDAAMKkR0dLwAOAQADAAMKkR0dLwAOAQA1AAQKfyQAAgMACQogJE8UAIIDAAMACQogJE8UAIIDAAAA.',
Ag='Agamar:BAAANQAECgEIAQAAAA==.Ageina:BAAANQADCggICAABNQAFFAQIBwAEABgeAA==.Agnostec:BAAANQADCgIIAwAAAA==.',
Ak='Akrama:BAABNQAECn8bAAMFAAcKxyBBMwCVAgAFAAcKxyBBMwCVAgAEAAEKAACyzQEbAAAAAA==.',
Al='Alatáriel:BAAANQAECgEJAQAAAA==.Alectrona:BAAANQADCgYICAAAAA==.Althenot:BAAANQADCgcIDwABNQAECgMICAAGAAAAAA==.',
Am='Amari:BAAANQADCgEIAQAAAA==.Amegoracy:BAAANQAECgYIEwAAAA==.',
An='Andalorian:BAAANQAECgMJAwAAAA==.Anderthel:BAAANQAECgIIAgAAAA==.Anruu:BAAANQAECgcIDgAAAA==.',
Ar='Araleth:BAAANQADCggIEwAAAA==.Aratol:BAAANQAECgUIBQABNQAECgkJIAAHABoTAA==.Archolaoch:BAABNQAECn8lAAIIAAkKqBV7GQAmAgAIAAkKqBV7GQAmAgAAAA==.Arconite:BAAANQADCgQIBQABNQAECgcIEQAGAAAAAA==.Arizonatea:BAAANQAECgEIAQAAAA==.Arkthurus:BAAANQAECgIIAgAAAA==.',
As='Ashenknight:BAAANQADCgEJAQAAAA==.Ashijin:BAACNQAFFH8HAAIEAAQKZg9yEwAYAQAEAAQKZg9yEwAYAQA1AAQKfyEAAwQACQpWG7RhAHECAAQACQpWG7RhAHECAAUAAQoCAW85ARIAAAAA.Astei:BAAANQADCgUIBQAAAA==.',
At='Athelos:BAAANQAECgEIAQAAAA==.Atroce:BAABNQAECn8rAAMJAAkKTSJ+DwASAwAJAAgKeyN+DwASAwAKAAgK8hzGKgBtAgAAAA==.',
Au='Aura:BAAANQAECgYIDwAAAA==.Auxilium:BAAANQADCggIDgAAAA==.',
Aw='Awnen:BAAANQAECgQIBwAAAA==.',
Ax='Axes:BAAANQAECgIIAgAAAA==.Axkicker:BAABNQAECn82AAILAAgKzxUTJgAYAgALAAgKzxUTJgAYAgAAAA==.',
Ay='Aystic:BAAANQAECgEIAQABNQAECggICgAGAAAAAA==.',
Ba='Balethar:BAAANQAECgUICgABNQAECgkJHQAEAFoYAA==.Ballador:BAAANQAECgcIDQAAAA==.Balluh:BAAANQAECgYIEAAAAA==.Balzluzzak:BAABNQAECn8fAAMMAAcKYAvtDACMAQAMAAcKYAvtDACMAQANAAUKmAVJAQHDAAAAAA==.Baughter:BAAANQABCgcICwAAAA==.',
Be='Beetledeww:BAAANQADCgQIBAAAAA==.Beetledont:BAAANQADCgYIBgAAAA==.Beezbonk:BAAANQAECggICAAAAA==.Bellemorte:BAAANQABCgQIBAAAAA==.Bellmage:BAABNQAECn8gAAIDAAgKcx1aaACtAgADAAgKcx1aaACtAgAAAA==.Belttoash:BAAANQAECgQIBAAAAA==.Beneficiary:BAAANQADCgYIBgAAAA==.Bestricer:BAACNQAFFH8uAAIOAAkKHR47AACQAwAOAAkKHR47AACQAwA1AAQKfzAAAg4ACQqLJgYCAMMDAA4ACQqLJgYCAMMDAAAA.Bevis:BAABNQAECn8fAAINAAkKzR+2DwBSAwANAAkKzR+2DwBSAwABNQAFFAQICQAPAF0bAA==.',
Bi='Bigmayex:BAABNQAECn8gAAIQAAgKRCWUAwBTAwAQAAgKRCWUAwBTAwAAAA==.Bilmuri:BAABNQAECn8cAAMRAAkKah5+IwAHAwARAAgKjCB+IwAHAwALAAUKiRUWSwAFAQAAAA==.Bippot:BAABNQAECn8rAAIEAAkKkB+AOADrAgAEAAkKkB+AOADrAgAAAA==.',
Bl='Blackbride:BAAANQADCggICgAAAA==.Blastetta:BAAANQAECgIIAgABNQAFFAQICwASAAsMAA==.Bloodybill:BAAANQADCgUJBQAAAA==.Blort:BAAANQADCggICAAAAA==.',
Bo='Bombadormu:BAAANQADCgcIBwAAAA==.Bonezs:BAABNQAECn8pAAITAAgKoiQHBwBQAwATAAgKoiQHBwBQAwAAAA==.Boredfordays:BAAANQAECgEIAQAAAA==.Borislav:BAAANQADCggIEQAAAA==.Bossvega:BAAANQADCggINAAAAA==.',
Br='Bruhkakke:BAAANQAECggIBAABNQAFFAUIDAAUAIwJAA==.Brutagon:BAAANQADCgQIBAABNQAECgYIDwAGAAAAAA==.',
Bu='Bucon:BAAANQADCgYIDAAAAA==.Bufferbug:BAAANQADCgEIAQAAAA==.Bugbear:BAAANQAECgQIBQAAAA==.Bumbly:BAAANQAECgYIEgAAAA==.Bunny:BAAANQADCgMIAwAAAA==.Bushybrowsy:BAABNQAECn80AAQMAAkKShGxBwAbAgAMAAgKAhOxBwAbAgANAAIK/Ab4LAFaAAAVAAEK2gOSeQAzAAAAAA==.Buttermeupz:BAABNQAECn8gAAIFAAkKEBJbTgAvAgAFAAkKEBJbTgAvAgAAAA==.Buttsnorkle:BAAANQAECgIIAgAAAA==.',
['Bá']='Bámboo:BAAANQAECgQICAAAAA==.',
Ca='Cacho:BAAANQAECgcIEQAAAA==.Cactuss:BAAANQAECgUIDQABNQAECgkJJQADAOoJAA==.Caothand:BAAANQAECgQIBwAAAA==.',
Cc='Ccyll:BAAANQADCgcIEAAAAA==.',
Ce='Celindri:BAAANQADCgcIBwAAAA==.Cerridwen:BAAANQABCgIIAgAAAA==.',
Ch='Chazandi:BAAANQADCgQIBAABNQAECgkJLQADAEoWAA==.Chazpriest:BAAANQAECgcIDQABNQAECgkJLQADAEoWAA==.Chazzbadgurl:BAAANQAECgcICwABNQAECgkJLQADAEoWAA==.Chazzie:BAAANQAECgcIBwABNQAECgkJLQADAEoWAA==.Chexmix:BAABNQAECn8ZAAMWAAYKtgwOLQBUAQAWAAYKxQsOLQBUAQAXAAQKMAtoeQDDAAAAAA==.Chicho:BAAANQAECgMIAwABNQAECgkJMAATAFUcAA==.Chomboslice:BAAANQAECggIEQAAAA==.',
Ci='Cinnamon:BAABNQAECn8rAAIYAAkKOxwNHQD7AgAYAAkKOxwNHQD7AgAAAA==.',
Cm='Cmil:BAACNQAFFH8OAAMFAAUKbxJfDACUAQAFAAUKbxJfDACUAQAEAAEKwgE1NABAAAA1AAQKfysABAUACQqHH7YZAA8DAAUACQqHH7YZAA8DAAQABwo+DubPAHYBAAgAAgqDFy1dAGIAAAAA.',
Co='Coffeegin:BAAANQADCgMIAwAAAA==.',
Cr='Crittingbull:BAAANQAECgYIDwAAAA==.Cruiddeath:BAAANQAECgQIDAABNQAECgkJJwAZAAkMAA==.',
Cu='Curserodlock:BAABNQAECn8nAAMZAAkKCQyJEQCJAQAZAAgKIgyJEQCJAQASAAYKFwdi7QAAAQAAAA==.',
Cy='Cyanide:BAAANQAECgYICwAAAA==.',
Da='Dabbinshamin:BAAANQADCggIDwAAAA==.Dads:BAACNQAFFH8VAAIPAAcKRxjGAwBhAgAPAAcKRxjGAwBhAgA1AAQKfx8AAw8ACQq9I9kTAFEDAA8ACQq9I9kTAFEDABQAAwpKAQX8AGwAAAAA.Daedra:BAAANQAECgYIEQABNQAECggIFwALAOQKAA==.Daillin:BAAANQADCgEIAQAAAA==.Dakadakadaka:BAABNQAECn8iAAMLAAgKjh8nIABLAgALAAcK9R8nIABLAgARAAEKiR03QAFWAAAAAA==.Darcdk:BAAANQAECgUICwABNQAFFAYIFAAFACQNAA==.Darcevoker:BAAANQADCgcIBwABNQAFFAYIFAAFACQNAA==.Darcpaladin:BAACNQAFFH8UAAIFAAYKJA17CQDEAQAFAAYKJA17CQDEAQA1AAQKfyYAAgUACQrLGSIpAMECAAUACQrLGSIpAMECAAAA.Darcpriest:BAAANQAECgQIBQABNQAFFAYIFAAFACQNAA==.Darkrune:BAAANQAECgIIAwAAAA==.Darkschneide:BAABNQAECn8XAAINAAkK1BAIbAAWAgANAAkK1BAIbAAWAgAAAA==.Darthboo:BAAANQAECgQIBgAAAA==.Darthknight:BAAANQAECgQIBAABNQAECgkJJgAEACcgAA==.Darthtemplar:BAABNQAECn8mAAQEAAkKJyDOMwD7AgAEAAkKJyDOMwD7AgAFAAEKBgfMIgEvAAAIAAEKAADZdQAmAAAAAA==.',
De='Deathbug:BAAANQADCggIEQAAAA==.Deckaye:BAAANQAECgUIBQABNQAECgUICgAGAAAAAA==.Deimoes:BAAANQAECgQICAAAAA==.Demodorn:BAACNQAFFH8OAAIaAAQK+wLWAwCwAAAaAAQK+wLWAwCwAAA1AAQKfzIAAhoACQqRCosRAJMBABoACQqRCosRAJMBAAAA.Demyst:BAACNQAFFH8NAAIUAAUK7Rf8CgCZAQAUAAUK7Rf8CgCZAQA1AAQKfyYAAxQACQprHYIhAOACABQACQprHYIhAOACAA8AAgo+DroRAWIAAAAA.Demön:BAAANQAECgMIAwAAAA==.Dewwarrior:BAAANQAECgUIDwAAAA==.Dezeraz:BAEANQAECgYIBgABNQAFFAYIFwAYANscAA==.',
Dh='Dhecaye:BAAANQAECgUICgAAAA==.',
Di='Diomedes:BAAANQABCgIIAgAAAA==.Disengage:BAAANQAECgUICAABNQAFFAQICQADAFYSAA==.',
Do='Dohdan:BAAANQAECgUIAgAAAA==.Donkey:BAABNQAECn8iAAIFAAgKOB5ZJQDTAgAFAAgKOB5ZJQDTAgAAAA==.Donmega:BAAANQADCggILwAAAA==.Dougalleone:BAACNQAFFH8LAAIXAAUK4ht5BQDQAQAXAAUK4ht5BQDQAQA1AAQKfx8AAxcACQpnImcNABUDABcACQpnImcNABUDABYABgp2GWgoAH4BAAAA.Dougallmaki:BAAANQAECgIIAgAAAA==.',
Dr='Drekkwarr:BAAANQAECgEIAQABNQAECggIJAAPAPUeAA==.Drentalth:BAAANQADCgEIAQAAAA==.Drezzakzdh:BAAANQAECgYIDAABNQAECgYIDgAGAAAAAA==.Drezzakzz:BAAANQAECgYIDgAAAA==.Drezzpally:BAAANQADCgMIAwAAAA==.',
Du='Dugren:BAAANQAECgIIAQAAAA==.Duracreate:BAAANQAECgMIBgAAAA==.',
Ea='Eamil:BAAANQADCgcJBwAAAA==.',
Ek='Ekaterin:BAACNQAFFH8IAAIDAAUKrBnyHACTAQADAAUKrBnyHACTAQA1AAQKfy4AAgMACQpLIpAmAEYDAAMACQpLIpAmAEYDAAAA.Ekewa:BAAANQAECgMIAwAAAA==.',
El='Elaidine:BAABNQAECn8lAAMaAAgKoh5IBgC1AgAaAAgKoh5IBgC1AgAbAAEKRgFfowAMAAAAAA==.Electraknub:BAAANQADCgYICwAAAA==.Electroh:BAAANQAECgYIDgAAAA==.Eliseda:BAAANQAECgQIBgABNQAECgkJJAAUAIAWAA==.',
Em='Emerald:BAAANQABCgYICgAAAA==.',
Ev='Evilnapkin:BAAANQAECgQICAAAAA==.Evion:BAABNQAECn8dAAIRAAcK5xngcgAoAgARAAcK5xngcgAoAgAAAA==.Evoke:BAAANQAECgcICwAAAA==.',
Fa='Falconsha:BAAANQAECgIIBAAAAA==.Fattynattyy:BAAANQADCgYIBgAAAA==.',
Fe='Fendis:BAAANQADCggIDgABNQAECgkJNQADANQcAA==.',
Fi='Fiercia:BAAANQAECgUICgABNQAECgkJKQAcAGQkAA==.Firefrost:BAABNQAECn9BAAMdAAkKbyP1AACdAwAdAAkKbyP1AACdAwADAAEKgQY6wwE0AAAAAA==.Firescrotum:BAABNQAECn8uAAIPAAkKmRQJSgBLAgAPAAkKmRQJSgBLAgAAAA==.',
Fl='Flashquinaz:BAAANQADCgYIBgAAAA==.',
Fo='Fourimborniy:BAAANQAECggIEgAAAA==.',
Fr='Frenzi:BAAANQADCgYICQAAAA==.',
Fu='Fundipme:BAAANQAECgQIBAABNQAFFAcIEgAIAJ4VAA==.',
['Fá']='Fáelen:BAABNQAECn8cAAIeAAkKFx55BQAhAwAeAAkKFx55BQAhAwAAAA==.',
Ga='Galasmina:BAAANQAECgYIDAAAAA==.Galaxius:BAAANQADCgEIAQABNQAECgcIEQAGAAAAAA==.Ganda:BAAANQADCgEJAQAAAA==.Gangactivity:BAAANQADCgUIBQABNQAECgkJNAAOACQlAA==.Garm:BAABNQAECn8fAAIDAAkK3SK0GwBoAwADAAkK3SK0GwBoAwAAAA==.Gavinrad:BAAANQAECgcIDgAAAA==.',
Ge='Generaname:BAAANQADCgcJDQAAAA==.Generanancy:BAAANQADCgIJAgAAAA==.Gep:BAAANQAECgMIBAABNQAFFAEIAgAGAAAAAA==.',
Gh='Ghostshadow:BAAANQAECgIIBAAAAA==.',
Gi='Gilene:BAAANQADCgcIDwAAAA==.Girthfury:BAABNQAFFH8MAAIUAAUKjAnIDwBNAQAUAAUKjAnIDwBNAQAAAA==.',
Gl='Glaalinix:BAAANQADCgMIBgAAAA==.',
Gn='Gnew:BAAANQADCgUICgAAAA==.Gnumchuck:BAABNQAECn8XAAICAAgK4QsSHAB2AQACAAgK4QsSHAB2AQAAAA==.',
Go='Goat:BAAANQAECgMIAwAAAA==.Goku:BAABNQAECn8nAAMUAAkKayHeEgAxAwAUAAkKayHeEgAxAwAPAAEKAAAXRAEqAAAAAA==.Goodman:BAABNQAECn8bAAMEAAcKgBOvrQC+AQAEAAcKgBOvrQC+AQAIAAIKsg9VYwBOAAAAAA==.Goom:BAAANQAECggIEAABNQAFFAcIGgAOAOoXAA==.Goomei:BAACNQAFFH8aAAIOAAcK6hc+AgBlAgAOAAcK6hc+AgBlAgA1AAQKfyEAAg4ACQpnIb8WAJQCAA4ACQpnIb8WAJQCAAAA.Goomkin:BAACNQAFFH8KAAMTAAUK1gtQCwAKAQATAAQKCgZQCwAKAQABAAQKaAOgFwDqAAA1AAQKfyIAAwEACQo3GBoxAFYCAAEACQo3GBoxAFYCABMABQrkGRQzAH0BAAE1AAUUBwgaAA4A6hcA.Gordanramsey:BAAANQADCgUIBQAAAA==.Gorok:BAAANQAECgQIBAAAAA==.',
Gr='Gravymonk:BAABNQAECn8ZAAIOAAkKYgiiMgB8AQAOAAkKYgiiMgB8AQAAAA==.Greatbooty:BAAANQAECgYICQAAAA==.Gremmi:BAAANQADCgYIBgAAAA==.Grishy:BAAANQAECggICAABNQAFFAQICQADAFYSAA==.Grombeefdal:BAAANQADCgYICwAAAA==.Grosgland:BAAANQAECgEIAQAAAA==.Groundbeéf:BAACNQAFFH8VAAIfAAYK7xlOAQAVAgAfAAYK7xlOAQAVAgA1AAQKfyUAAh8ACQocJUAFADcDAB8ACQocJUAFADcDAAAA.Grovoath:BAAANQADCgcIDQAAAA==.Grumpypally:BAAANQAECggIBwAAAA==.',
Gu='Gurthon:BAAANQADCggIDwAAAA==.',
Ha='Halligan:BAAANQAECgYIDQAAAA==.Hallowfear:BAAANQAECgUJDgAAAA==.Handadinite:BAAANQADCgUICAAAAA==.Handysummons:BAABNQAECn8bAAINAAgKSx3pRACBAgANAAgKSx3pRACBAgAAAA==.Harie:BAAANQAECgUIDgAAAA==.Harydotter:BAAANQAECgYIDAAAAA==.Hawtsoss:BAAANQABCgQIBwAAAA==.',
He='Hein:BAAANQAECgQICAAAAA==.Heiny:BAABNQAECn8zAAQKAAkKQiYpAgDRAwAKAAkKQiYpAgDRAwAJAAgKYCEAEwDyAgAcAAYKRyOYNgBKAgAAAA==.Heinyheinyho:BAAANQADCgMIBAABNQAECgkJMwAKAEImAA==.',
Ho='Hoid:BAAANQAECggICgAAAA==.Holeybeef:BAAANQAECgYIDgAAAA==.Holymoly:BAAANQADCgMIAQABNQAECgkJQQAdAG8jAA==.Holynoodles:BAEBNQAECn8WAAIEAAgK9hxibwBNAgAEAAgK9hxibwBNAgAAAA==.Holytest:BAACNQAFFH8IAAIYAAMKix7NGgAQAQAYAAMKix7NGgAQAQA1AAQKfzEAAhgACQoSIlgWAB4DABgACQoSIlgWAB4DAAAA.Hoofmetoo:BAABNQAECn8ZAAMJAAcKCR0ALQAzAgAJAAcK9hwALQAzAgAcAAQKJBxDjwDmAAAAAA==.Howboudah:BAAANQADCgcIBwAAAA==.',
Hu='Hulzar:BAABNQAECn8XAAISAAgKEQ4wowDAAQASAAgKEQ4wowDAAQAAAA==.',
Hy='Hypernova:BAAANQAECgUIBQAAAA==.Hypocrisy:BAAANQAECggICAAAAA==.',
['Hô']='Hôlyblight:BAACNQAFFH8JAAIFAAUK9BY4CwCkAQAFAAUK9BY4CwCkAQA1AAQKfzAAAwUACQpnGa0vAKUCAAUACQpnGa0vAKUCAAQACQqsE52GABUCAAAA.',
Ib='Ibis:BAAANQAECggIDQABNQAFFAMIBQAHAA4EAA==.',
Id='Idotyouto:BAAANQADCgcIBwAAAA==.',
Ih='Iheartdemons:BAEANQAECgEIAQABNQAECggIFgAEAPYcAA==.',
Il='Ilbryen:BAAANQAECgQIBQABNQAFFAUIDQASAH4XAA==.Illaam:BAAANQADCggIDAAAAA==.Illidrag:BAAANQAECggIEQAAAA==.Ilovejacky:BAAANQADCgcIDQAAAA==.',
Im='Immørtlzed:BAACNQAFFH8WAAIUAAcKiyNgAQC5AgAUAAcKiyNgAQC5AgA1AAQKfysAAxQACQq+JdoDAKwDABQACQq+JdoDAKwDAA8AAgpUFUr/AIoAAAAA.',
In='Inara:BAAANQAECgEIAQABNQAECgkJKgAOAEQYAA==.Insurion:BAAANQAECgQIBgAAAA==.Invective:BAAANQAECgUIDgAAAA==.',
Ir='Ironstorm:BAAANQADCgQIBAAAAA==.',
Iz='Izzyumi:BAAANQADCgYIBgAAAA==.',
Ja='Jarizard:BAACNQAFFH8SAAIHAAUK0AsGDABXAQAHAAUK0AsGDABXAQA1AAQKfygAAwcACQpbFNsXADsCAAcACQpbFNsXADsCACAAAQrzB4c/ACsAAAAA.Jarrie:BAAANQAECgQIBAAAAA==.Jassar:BAAANQAECgEJAgAAAA==.Jaxdk:BAAANQAECgIIAgAAAA==.Jaxek:BAABNQAECn8yAAIeAAkKFiO9AQCtAwAeAAkKFiO9AQCtAwAAAA==.Jaxs:BAACNQAFFH8QAAIUAAYKwA8oCQC6AQAUAAYKwA8oCQC6AQA1AAQKfyQAAhQACQoIGoo8AGsCABQACQoIGoo8AGsCAAAA.Jaylen:BAAANQAECgQICQAAAA==.Jaymo:BAABNQAECn8VAAICAAgKFhlTDQBaAgACAAgKFhlTDQBaAgAAAA==.',
Je='Jebke:BAAANQAECgcIEwAAAA==.Jeneke:BAAANQAECgIIAgAAAA==.',
Jo='Johnwick:BAAANQADCgQIBAAAAA==.Jopha:BAACNQAFFH8VAAISAAYKfxxbCAArAgASAAYKfxxbCAArAgA1AAQKfyQAAxIACQoFJTQhADIDABIACQoFJTQhADIDABkAAQoAADAqAFwAAAAA.Jophr:BAAANQAECgUICwABNQAFFAYIFQASAH8cAA==.Jore:BAAANQAECgIIAwAAAA==.',
Jp='Jpbruiser:BAABNQAECn80AAIEAAkKqRjsZwBgAgAEAAkKqRjsZwBgAgAAAA==.',
Ju='Jumpndeath:BAACNQAFFH8LAAIKAAUKfxe+DACCAQAKAAUKfxe+DACCAQA1AAQKfx4AAwoACQo9H2gUAAcDAAoACQo9H2gUAAcDAAkAAQoEDb6nADcAAAE1AAUUAggCAAYAAAAA.Jumpnjudge:BAAANQAFFAIIAgAAAA==.Jumpnpray:BAAANQAECggIEgABNQAFFAIIAgAGAAAAAA==.Justgetme:BAABNQAECn8dAAMEAAkKWhjfewAvAgAEAAkKRhjfewAvAgAIAAIKpyWiTgCoAAAAAA==.',
Ka='Kaan:BAAANQADCgEIAQAAAA==.Kaariel:BAAANQADCgYIBgAAAA==.Kabo:BAACNQAFFH8LAAISAAQKfA2NHQAcAQASAAQKfA2NHQAcAQA1AAQKfygAAhIACQqVGSBQAJYCABIACQqVGSBQAJYCAAAA.Kadela:BAAANQADCgcIFwAAAA==.Kagger:BAACNQAFFH8GAAIEAAIK/hedIACaAAAEAAIK/hedIACaAAA1AAQKfxoAAgQACQokIgYfAEUDAAQACQokIgYfAEUDAAAA.Kardoroth:BAACNQAFFH8JAAIcAAUKIiKPBQDKAQAcAAUKIiKPBQDKAQA1AAQKfx0AAhwACQqwJCwPADwDABwACQqwJCwPADwDAAAA.Karib:BAAANQAECgEIAQABNQAFFAQICgAcAKQZAA==.Karîba:BAACNQAFFH8KAAQcAAQKpBmnDgAdAQAcAAMK0ySnDgAdAQAKAAMKZAqwHACnAAAJAAIKURp4EwCeAAA1AAQKfzUABBwACQr9JSYJAHUDABwACQoIJSYJAHUDAAkABwr+IiEhAIACAAoABAocGrh/APgAAAAA.',
Ke='Keld:BAEANQAECggIEwAAAA==.Kellienna:BAAANQAECgQIBgABNQAECgkJJgAEACcgAA==.Kelsaz:BAACNQAFFH8QAAQRAAUKVhxVFAAZAQARAAMKBSFVFAAZAQALAAMKew5sGAC7AAAhAAEKAAB7AgBRAAA1AAQKfyQAAxEACQrtJGAiAAwDABEACQrtJGAiAAwDAAsABgpnGvI9AF0BAAAA.Kelshock:BAAANQAECgEIAgAAAA==.Kelsi:BAABNQAECn8qAAIOAAkKRBhiHQBHAgAOAAkKRBhiHQBHAgAAAA==.Kenný:BAAANQAECgQIBAAAAA==.Kerrìgàn:BAACNQAFFH8NAAMbAAUKLBAqCwBpAQAbAAUKLBAqCwBpAQAaAAEKlgq2CAAwAAA1AAQKfzoAAxsACQqIISwOADIDABsACQqIISwOADIDABoABQrsGpkSAIABAAAA.Kestral:BAACNQAFFH8FAAIHAAMKDgRpEgCzAAAHAAMKDgRpEgCzAAA1AAQKfxsAAgcACQoRDUUeAOoBAAcACQoRDUUeAOoBAAAA.',
Kh='Khalisi:BAAANQAECgEIAwAAAA==.',
Ki='Kickyboots:BAAANQAECgQIBAABNQAECgcICQAGAAAAAA==.Kitara:BAAANQADCgIIAgAAAA==.',
Ko='Koochlathom:BAAANQAECgEIAQABNQAECggIGgAFAEYeAA==.Kookiie:BAACNQAFFH8VAAIbAAYKdBt7AwBIAgAbAAYKdBt7AwBIAgA1AAQKfyQAAhsACQqUJfwLAEkDABsACQqUJfwLAEkDAAAA.Koom:BAAANQAECgMIBAAAAA==.Korgoroth:BAAANQABCgIIAwAAAA==.Kosian:BAAANQAECgIIAwABNQAECgkJNQADANQcAA==.Kosigan:BAAANQADCgUIBQABNQAFFAUICAADAKwZAA==.',
Kr='Krepuscular:BAABNQAECn8gAAISAAgKgxwhUgCQAgASAAgKgxwhUgCQAgAAAA==.Kryptiq:BAACNQAFFH8OAAICAAUKBh59AQDCAQACAAUKBh59AQDCAQA1AAQKfyEAAgIACQoCJcgCAH8DAAIACQoCJcgCAH8DAAAA.Kryptìq:BAAANQAECgUIBgABNQAFFAUIDgACAAYeAA==.',
Ku='Kurisami:BAAANQAECgcIDAAAAA==.',
La='Larielin:BAAANQADCgYIBgAAAA==.Larra:BAACNQAFFH8NAAIYAAUKVRWqDgCgAQAYAAUKVRWqDgCgAQA1AAQKfx8ABCIACQoSE0wHAAICACIACQpcD0wHAAICABgABAqtEyexAP4AACMAAQoAAPqAACcAAAAA.',
Le='Leeha:BAAANQADCgMIAwAAAA==.Leman:BAAANQAECgMIAwAAAA==.Lemondonut:BAAANQADCgUIBQAAAA==.Leomessi:BAAANQADCgQIAwABNQAECgkJKQARANEWAA==.Levitas:BAABNQAECn8iAAICAAgKRRHwFwCrAQACAAgKRRHwFwCrAQAAAA==.Leyron:BAABNQAECn8UAAIXAAgKaRSALwAgAgAXAAgKaRSALwAgAgABNQAECgkJJgAEACcgAA==.',
Li='Likkhan:BAAANQAECgEIAQAAAA==.Lithel:BAAANQADCggIGwAAAA==.',
Lo='Lockdragoon:BAAANQABCgIIBAAAAA==.Logics:BAABNQAECn8rAAMjAAkKNiFfDQAUAwAjAAkKNiFfDQAUAwAYAAYKMQOkvwDWAAAAAA==.Longsham:BAAANQADCgUIBgAAAA==.Lostmyvigor:BAAANQAECgQICAAAAA==.Lostvoker:BAABNQAECn8kAAMkAAkK5BKtCAAEAgAkAAkK5BKtCAAEAgAgAAIKYAWCNABmAAAAAA==.',
Lu='Lucarad:BAAANQAECgUIBgAAAA==.Lucivia:BAABNQAECn8eAAIMAAgKZRprBQBqAgAMAAgKZRprBQBqAgAAAA==.Lumafist:BAABNQAECn80AAIOAAkKJCV3AQDTAwAOAAkKJCV3AQDTAwAAAA==.Lunär:BAAANQAECgIIAgAAAA==.',
['Lè']='Lènneth:BAABNQAECn8qAAMjAAkKSw7+KQDUAQAjAAkKSw7+KQDUAQAYAAUKtRvrfACeAQAAAA==.',
Ma='Maddelyn:BAACNQAFFH8QAAIDAAcKRxVQBgBXAgADAAcKRxVQBgBXAgA1AAQKfyYAAgMACQpLJTQSAIoDAAMACQpLJTQSAIoDAAAA.Magicdaddy:BAAANQADCgEIAQAAAA==.Majaer:BAAANQADCgYIBgAAAA==.Mapp:BAABNQAECn8dAAMLAAkKMBTzLADhAQALAAgKfxHzLADhAQARAAYKxxWItACWAQAAAA==.Mashanu:BAACNQAFFH8NAAIPAAUKZxknCwC0AQAPAAUKZxknCwC0AQA1AAQKfxkAAg8ACQq7HnQnAOICAA8ACQq7HnQnAOICAAE1AAUUBQoNAA8AZxkA.Mashpriest:BAAANQADCgIIAgAAAA==.Mazur:BAAANQAECgcIDgAAAA==.',
Mc='Mcmonkton:BAAANQADCgIIAgAAAA==.',
Me='Meanssa:BAECNQAFFH8JAAIKAAUKIBpPDACLAQAKAAUKIBpPDACLAQA1AAQKfyMAAgoACQp9GOApAHMCAAoACQp9GOApAHMCAAAA.Megamaxamx:BAAANQADCgIIAgAAAA==.Melaan:BAABNQAECn8fAAMTAAgKuxmaGgBhAgATAAgKuxmaGgBhAgAeAAEKAABdRgApAAAAAA==.Meldatonin:BAAANQAECgIIAgAAAA==.Metaslave:BAAANQAECgIIAQAAAA==.Mewreck:BAAANQADCgIIAgAAAA==.',
Mi='Mindleseye:BAAANQAECggIDQAAAA==.Misosalty:BAABNQAECn82AAQlAAkKPBiLDwCDAgAlAAkKPBiLDwCDAgAOAAUKqxEAQAARAQAQAAMK+BLKIADXAAAAAA==.',
Mo='Mohjito:BAABNQAECn8YAAIlAAgKEhPUGgDQAQAlAAgKEhPUGgDQAQAAAA==.Monica:BAAANQAECgEIAQAAAA==.Moojinbuu:BAAANQAECgMIBQAAAA==.Mooshanu:BAAANQABCgMIBAABNQAFFAUKDQAPAGcZAA==.Mootini:BAAANQAECgEIAQAAAA==.Morguth:BAACNQAFFH8MAAIRAAUK4Q7qCwCNAQARAAUK4Q7qCwCNAQA1AAQKfxgAAhEACQr0HD5CAKICABEACQr0HD5CAKICAAAA.Moripally:BAABNQAECn8bAAIEAAkK6x13OQDoAgAEAAkK6x13OQDoAgABNQAFFAQICwAjADohAA==.Moripriest:BAACNQAFFH8LAAIjAAQKOiEhCACKAQAjAAQKOiEhCACKAQA1AAQKfzMAAiMACQqyI8IDAJwDACMACQqyI8IDAJwDAAAA.Moriwarrior:BAABNQAECn8ZAAISAAcKWRsuggASAgASAAcKWRsuggASAgABNQAFFAQICwAjADohAA==.',
Mu='Murky:BAAANQAECggIDwAAAA==.Murnemerch:BAAANQADCgYIJQAAAA==.Musclewizard:BAABNQAECn8dAAISAAcKfxnnfgAaAgASAAcKfxnnfgAaAgAAAA==.',
My='Myrthael:BAAANQADCgUIBQAAAA==.Mythiks:BAAANQADCgIIAgABNQAECggIFwALAOQKAA==.',
['Mï']='Mïlo:BAAANQAECgcIEwAAAA==.',
['Mô']='Môon:BAAANQAECgEIAQAAAA==.',
['Mø']='Mønsters:BAAANQAECgMIAwAAAA==.',
Na='Nancybrew:BAABNQAECn8hAAIOAAkKshqKGAB/AgAOAAkKshqKGAB/AgAAAA==.Natalie:BAAANQADCggICAABNQAECggICgAGAAAAAA==.',
Ne='Nesqwik:BAAANQADCggIHQAAAA==.Nevan:BAABNQAECn8kAAIFAAkKjR53GAAWAwAFAAkKjR53GAAWAwAAAA==.',
Ni='Nidalee:BAAANQAECgcIDgAAAA==.Nineball:BAABNQAECn8hAAMWAAgKnRu0HADrAQAWAAYKUhy0HADrAQAXAAYK9xf3QADCAQAAAA==.Niyx:BAAANQAECgYIDgAAAA==.',
No='Noochallange:BAABNQAECn8dAAIXAAgKnB0JGAC4AgAXAAgKnB0JGAC4AgAAAA==.Norex:BAACNQAFFH8MAAMKAAUKUAnHGADVAAAJAAQKVweuDQD6AAAKAAQKNwnHGADVAAA1AAQKfyAABAkACQr0GI00AAQCAAkACAr0GI00AAQCABwABgqbDZWBABQBAAoAAwpOFP6VAK8AAAAA.Notgood:BAAANQAECgMIBAAAAA==.',
Nu='Nuggie:BAAANQAECgYIEgAAAA==.',
Ny='Nylariaa:BAAANQADCgYIBgAAAA==.Nymia:BAAANQAECgcICQAAAA==.',
Ol='Oldmagic:BAAANQAECgQIEAAAAA==.Olzpot:BAAANQAECgEIAQAAAA==.',
Oo='Ooglaboogla:BAABNQAECn8nAAMPAAgK+h4iPgB6AgAPAAcK/CAiPgB6AgAUAAYK3hnAbgC7AQAAAA==.',
Or='Orbitguy:BAAANQADCgUIBQAAAA==.Orbutt:BAAANQADCgYICgAAAA==.Orillian:BAAANQADCgYIBwAAAA==.',
Ov='Overtime:BAAANQAECgcIEQAAAA==.',
Ox='Oxyrotten:BAAANQAECgIJAgAAAA==.',
Pa='Palablort:BAABNQAECn8aAAMFAAgKRh63LgCpAgAFAAgKRh63LgCpAgAEAAUKdRXR8wAvAQAAAA==.Panzeria:BAABNQAECn8cAAIjAAkKfiNIDgAIAwAjAAkKfiNIDgAIAwAAAA==.Pawsome:BAABNQAECn8YAAImAAgKSxjpEQA+AgAmAAgKSxjpEQA+AgAAAA==.',
Pi='Pixel:BAAANQAECgMIBwAAAA==.',
Pl='Plinkie:BAAANQADCgEIAQAAAA==.',
Pm='Pmon:BAAANQADCgYIBgAAAA==.',
Pr='Predofdisney:BAAANQADCgUIBQAAAA==.Prlestest:BAAANQAECgYIEQABNQAECgkJQQAdAG8jAA==.Proowee:BAAANQAECggIDwAAAA==.Propayne:BAAANQAECggIBQAAAA==.',
Ps='Pseudoholy:BAAANQAECgUICQAAAA==.',
Pu='Pukebreath:BAAANQADCgEIAQAAAA==.Putridvigor:BAABNQAECn8kAAIKAAgKRSMrEAAqAwAKAAgKRSMrEAAqAwAAAA==.',
['Pä']='Pälii:BAABNQAECn8bAAIEAAcKMw8iwACWAQAEAAcKMw8iwACWAQAAAA==.',
Qi='Qizai:BAAANQAECgEIAQAAAA==.',
Ra='Ramaan:BAAANQAECgIIAgAAAA==.Rastaa:BAABNQAECn8XAAMLAAgK5AoWNgCZAQALAAgK5AoWNgCZAQARAAEKAADqWQE1AAAAAA==.Ravette:BAABNQAECn8cAAIbAAgKqh9AGQDNAgAbAAgKqh9AGQDNAgAAAA==.Ravissante:BAAANQAECgEIAQAAAA==.Ravyndrath:BAAANQADCgMIAwAAAA==.Rawranator:BAAANQAECgQIBgAAAA==.',
Rh='Rhonis:BAAANQADCgEIAQAAAA==.',
Ri='Ricksancheez:BAAANQAECggIDwAAAA==.',
Ro='Roidgnome:BAAANQAECgEIBAAAAA==.Ronnycoleman:BAAANQADCgIIAgAAAA==.',
Ru='Runeka:BAAANQAECgEIAQABNQAECgkJIQAaAEUhAA==.',
Ry='Ryleth:BAAANQADCggIDQAAAA==.',
Sa='Safehaven:BAAANQAECgYIDwAAAA==.Samwìse:BAACNQAFFH8OAAIYAAQKOhN+FgA+AQAYAAQKOhN+FgA+AQA1AAQKf0IAAxgACQp9IKwTAC4DABgACQp9IKwTAC4DACMABgpTDQJBACQBAAAA.Sarenrae:BAAANQAECgQIBgABNQAECggIHwATALsZAA==.Sarranidan:BAAANQAECgYIEwABNQAECgkJNQADANQcAA==.Sathelyn:BAAANQADCgcIBwABNQAECgkJJwAZAAkMAA==.Sato:BAAANQABCgIIAgAAAA==.',
Sc='Scatman:BAAANQADCgUIBQAAAA==.Scire:BAAANQAECgMIBAAAAA==.Scopenrage:BAAANQAECgQIBAABNQAECgkJFgAcAO4cAA==.',
Se='Sedontas:BAAANQAECgQIBQAAAA==.Senggolbacok:BAAANQAECgQICgAAAA==.Serengenuity:BAACNQAFFH8VAAMYAAYKPBdLCAABAgAYAAYK8BZLCAABAgAiAAMK0xDhAQDzAAA1AAQKfyMABBgACQqpInwkANgCABgACQp8InwkANgCACIABgqhH1YHAAACACMABAp0IAZEABEBAAAA.Serenidin:BAAANQADCgYIBgAAAA==.',
Sh='Shampane:BAAANQADCgUIBQABNQAECgkJQQAdAG8jAA==.Shark:BAAANQAECgcJEQAAAA==.Sheera:BAAANQADCgEIAQAAAA==.Shiggles:BAAANQAECggIDAABNQAFFAUIDAAUAIwJAA==.Shiggyll:BAAANQAECgMIBAABNQAFFAMICAAYAIseAA==.Shiryunuri:BAAANQADCgYIBgAAAA==.Shizzo:BAAANQADCgQIBAAAAA==.Shmoople:BAAANQADCgcIDAAAAA==.Shockin:BAABNQAECn8dAAIfAAkKWhDnEwAnAgAfAAkKWhDnEwAnAgAAAA==.Shootin:BAAANQAECgIJBAAAAA==.Shypoke:BAAANQABCgEIAQAAAA==.Shøstákovich:BAAANQAECgEIAQAAAA==.',
Si='Sifen:BAABNQAECn8cAAMFAAgKJBUjVAAbAgAFAAgKJBUjVAAbAgAEAAEKSQcwwgEkAAABNQAFFAQICQAPAF0bAA==.Sifting:BAABNQAECn8xAAIDAAkKGRyyQQABAwADAAkKGRyyQQABAwAAAA==.Sinsheretic:BAAANQAECgQIBAAAAA==.Sinswrath:BAACNQAFFH8VAAIEAAYKLCH5AgBQAgAEAAYKLCH5AgBQAgA1AAQKfyQAAgQACQqmJbcZAFwDAAQACQqmJbcZAFwDAAAA.',
Sk='Skidxx:BAAANQADCgYIDQAAAA==.Skulker:BAAANQADCgMIBgAAAA==.Skygnome:BAACNQAFFH8IAAMHAAMK9gbnEQDAAAAHAAMK9gbnEQDAAAAkAAEKrwCgDQAuAAA1AAQKfyMAAgcACQrPGQsPALYCAAcACQrPGQsPALYCAAAA.Skyhørn:BAAANQAECgIIAgAAAA==.',
Sl='Slaye:BAAANQAECgQICAAAAA==.Slimjjim:BAAANQAECgcIEQAAAA==.',
Sm='Smiteheal:BAAANQADCgYIBgAAAA==.Smores:BAAANQADCgEIAQABNQAFFAcIGQATAH8iAA==.',
Sn='Snake:BAAANQADCgUIBQAAAA==.Sneakyteeth:BAABNQAECn8xAAIWAAkKjxobCQDiAgAWAAkKjxobCQDiAgAAAA==.',
So='Songi:BAABNQAECn8rAAIcAAkKnSRMDwA7AwAcAAkKnSRMDwA7AwAAAA==.Soulstout:BAAANQADCgYIBwAAAA==.Soulwhisper:BAACNQAFFH8RAAIcAAYKIBYhBADuAQAcAAYKIBYhBADuAQA1AAQKfyYAAhwACQrLIQwYAPwCABwACQrLIQwYAPwCAAAA.',
Sp='Spanda:BAABNQAECn8dAAIQAAgKvRfqDgABAgAQAAgKvRfqDgABAgAAAA==.Sparrkel:BAAANQAECgQIBQAAAA==.Splageras:BAAANQAECgEIAQAAAA==.Splagzhul:BAAANQAECgQICAAAAA==.Splendi:BAAANQAECgQIBAABNQAECggIHQAQAL0XAA==.Sprogg:BAAANQAECgEIAQAAAA==.Spyropaly:BAABNQAECn8pAAIFAAkKaCFlDgBWAwAFAAkKaCFlDgBWAwAAAA==.Spyroshaman:BAAANQADCgUICQABNQAECgkJKQAFAGghAA==.',
St='Stampede:BAAANQADCggIDwAAAA==.Stepzlol:BAAANQADCgYICwABNQADCgcIDQAGAAAAAA==.Stormsinger:BAABNQAECn8kAAMUAAkKgBZISgA2AgAUAAkKgBZISgA2AgAPAAgK7wtYdwC4AQAAAA==.',
Su='Sugarblast:BAACNQAFFH8OAAIPAAYKCxmLBgAOAgAPAAYKCxmLBgAOAgA1AAQKfzcAAw8ACQp/JL8LAIgDAA8ACQp/JL8LAIgDAB8ABQr1HuEaALEBAAAA.Sukaii:BAAANQAECgcIDQAAAA==.Summonuber:BAAANQAECgIIAQAAAA==.Suou:BAACNQAFFH8NAAISAAUKfhcLEACzAQASAAUKfhcLEACzAQA1AAQKfyQAAxIACQrMH6tAAMUCABIACQrMH6tAAMUCABkAAQqcILQrAFMAAAAA.',
Sv='Svekkê:BAAANQAECgcIAQAAAA==.',
Sy='Sylint:BAAANQADCgYICwAAAA==.Sylliseas:BAAANQADCgYIBgAAAA==.',
Ta='Tandaley:BAAANQADCgQIBQABNQAECgkJJAAUAIAWAA==.Tandea:BAAANQAECgYIBgAAAA==.Tanthyr:BAAANQADCgQIBQABNQAECgkJJAAUAIAWAA==.Targon:BAAANQADCgcIDQAAAA==.',
Te='Terallaa:BAAANQAECgUIBQABNQAECgYIBgAGAAAAAA==.Testme:BAAANQADCggICwAAAA==.Textaco:BAAANQADCgEIAQAAAA==.',
Th='Thedevilssin:BAAANQAECgYICwAAAA==.Theodas:BAAANQAECgcIDQAAAA==.Thiccgnome:BAACNQAFFH8IAAIYAAMKbQ/5HwDbAAAYAAMKbQ/5HwDbAAA1AAQKfxQAAhgACAq9GVU5AIACABgACAq9GVU5AIACAAAA.Thiccthighs:BAAANQAECgEIAQAAAA==.Thirdlegolas:BAAANQAECgEIAQAAAA==.Thuuros:BAABNQAECn8qAAIcAAkKSBqJKQCQAgAcAAkKSBqJKQCQAgAAAA==.',
Ti='Tikariia:BAAANQAECgQIBAAAAA==.Tiktok:BAAANQAECgUIBQAAAA==.Tipsygypsy:BAABNQAECn8VAAMdAAYKvxHTHQD7AAADAAYKCArHKgFBAQAdAAQKShTTHQD7AAAAAA==.Tirent:BAAANQAECgQICQAAAA==.',
To='Tokenbeef:BAAANQAECgcIEgAAAA==.Tokenshaman:BAABNQAECn8oAAIfAAkKoRKZEABeAgAfAAkKoRKZEABeAgAAAA==.Tokentrees:BAAANQADCgUJBQAAAA==.Touchspell:BAABNQAECn8lAAIDAAkK6gkH2QDSAQADAAkK6gkH2QDSAQAAAA==.Toxicdk:BAABNQAECn8eAAQJAAkKpiEVLgAsAgAJAAkKlxoVLgAsAgAKAAYKhR+1RwDWAQAcAAQK6iPkWwCcAQAAAA==.Toxicshamy:BAAANQAECggICwABNQAECgkJHgAJAKYhAA==.',
Tr='Traylay:BAACNQAFFH8NAAIEAAUKJRejCgCaAQAEAAUKJRejCgCaAQA1AAQKfx8AAgQACQpXIgZAANICAAQACQpXIgZAANICAAAA.Trixaintime:BAAANQADCgcIBwAAAA==.Trommel:BAAANQAECgUIBgAAAA==.Trydoom:BAAANQADCgYIBgAAAA==.Trèè:BAAANQADCgMIBQAAAA==.',
Tt='Ttocs:BAACNQAFFH8JAAIPAAQKXRsfDwB3AQAPAAQKXRsfDwB3AQA1AAQKfzcAAg8ACQrgJFEEAMgDAA8ACQrgJFEEAMgDAAAA.',
Tu='Tujori:BAACNQAFFH8VAAIYAAYKrQtWDADAAQAYAAYKrQtWDADAAQA1AAQKfyMAAhgACQoAGMdGAE8CABgACQoAGMdGAE8CAAAA.',
Tw='Twherk:BAABNQAECn8jAAIFAAgKFB5rKADFAgAFAAgKFB5rKADFAgABNQAFFAUIDAAUAIwJAA==.Twoeye:BAAANQADCgYIBgAAAA==.',
Ug='Uglydorf:BAABNQAECn8pAAMRAAkK0RbZPwCpAgARAAkK0RbZPwCpAgALAAEKwANomQAkAAAAAA==.',
Um='Umokthra:BAAANQAECgEIAQAAAA==.',
Us='Ustoo:BAABNQAECn8eAAMdAAcKYhUpDQDcAQAdAAcKYhUpDQDcAQADAAEKMwIE1QEpAAAAAA==.',
Va='Vae:BAAANQAECgMJAwAAAA==.Vaeros:BAABNQAECn8cAAIkAAcK8Qv9DQBmAQAkAAcK8Qv9DQBmAQAAAA==.Valanteil:BAAANQABCgYIBAABNQAECgkJJAAUAIAWAA==.Varcina:BAABNQAECn8eAAINAAkKBRifLADQAgANAAkKBRifLADQAgABNQAFFAQICgAcAKQZAA==.Variana:BAABNQAECn8hAAMaAAkKRSEPBAAOAwAaAAgK5iEPBAAOAwAbAAMKqhiCZADiAAAAAA==.Vaylle:BAAANQADCgQJBAAAAA==.',
Ve='Vekz:BAABNQAECn8nAAIFAAgKAB62LwClAgAFAAgKAB62LwClAgAAAA==.Veles:BAAANQAECgEIAQAAAA==.Velicia:BAAANQAECgMIAwAAAA==.Velytia:BAAANQAECgcIEQAAAA==.Verytight:BAAANQAECgUIBQAAAA==.Vexøs:BAAANQADCggIDwAAAA==.',
Vi='Vitiliga:BAABNQAECn8XAAIZAAcKtAdhFwAmAQAZAAcKtAdhFwAmAQAAAA==.',
Vo='Volcanicbird:BAAANQAECgQIBQAAAA==.Vomax:BAAANQADCgEIAQAAAA==.',
Wa='Wasteofpants:BAAANQAECgUIBwAAAA==.Waterbôy:BAAANQAECgUICwABNQAFFAUICQAFAPQWAA==.',
Wh='Whoasked:BAAANQADCgMIAwABNQAFFAUICAADAKwZAA==.Whîrly:BAAANQADCgUIBgAAAA==.',
Wo='Wolf:BAAANQAECgIIAgAAAA==.',
Wt='Wtfheal:BAAANQAECggIEwABNQAFFAUIDAAUAIwJAA==.',
Wu='Wumbology:BAAANQAECgIIAgAAAA==.',
['Wà']='Wàrrior:BAAANQADCgUICQAAAA==.',
Ya='Yakimandu:BAAANQADCggICAABNQAECgkJHwAUAHQcAA==.Yamashaman:BAABNQAECn8fAAIUAAkKdBy/IwDVAgAUAAkKdBy/IwDVAgAAAA==.Yamo:BAAANQADCggIFQAAAA==.Yardgnome:BAABNQAECn8aAAMTAAgKfxkwHQBEAgATAAcKjxswHQBEAgABAAYKlRNITACuAQAAAA==.',
Yu='Yuna:BAABNQAECn8dAAIYAAcKcRxoRQBTAgAYAAcKcRxoRQBTAgAAAA==.',
Za='Zacheris:BAABNQAECn8WAAIDAAgKpBvukABdAgADAAgKpBvukABdAgAAAA==.Zafod:BAAANQAECgIIAgAAAA==.Zalvator:BAAANQABCggIEgABNQAECggICgAGAAAAAA==.Zamasu:BAAANQAECgIJAwAAAA==.Zapped:BAAANQAECgEIAQAAAA==.Zaszadin:BAEBNQAECn8bAAIEAAgKzxyHWQCHAgAEAAgKzxyHWQCHAgAAAA==.Zaszhadoom:BAEANQADCgYIBgABNQAECggIGwAEAM8cAA==.',
Ze='Zekt:BAAANQADCgcICQAAAA==.Zeltron:BAAANQADCgUICgAAAA==.Zephyre:BAAANQADCggIDgAAAA==.Zerax:BAABNQAECn8gAAIHAAkKGhOQFQBZAgAHAAkKGhOQFQBZAgAAAA==.Zerolinkin:BAAANQAECgEIAQAAAA==.',
Zi='Zillagoth:BAAANQADCggICQAAAA==.Zira:BAABNQAECn8iAAIlAAcKPhW9GwDDAQAlAAcKPhW9GwDDAQAAAA==.',
Zo='Zombidruid:BAAANQAECgIIBAAAAA==.Zombiebubble:BAAANQAECgcICAAAAA==.Zoìdberg:BAACNQAFFH8GAAIUAAIKRRBrIgCAAAAUAAIKRRBrIgCAAAA1AAQKfx8AAhQACQrqHbQgAOQCABQACQrqHbQgAOQCAAAA.',
Zs='Zselk:BAAANQADCgUIBQAAAA==.Zshot:BAAANQAECgYIDAAAAA==.',
Zu='Zubzer:BAAANQADCgYIBgAAAA==.',
Zz='Zzor:BAACNQAFFH8MAAIDAAQKwRoxJQBVAQADAAQKwRoxJQBVAQA1AAQKfzQAAgMACQrPIrUhAFQDAAMACQrPIrUhAFQDAAAA.',
['Är']='Ärtemìs:BAAANQADCgQIBAAAAA==.',
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
