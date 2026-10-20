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

local lookup = {'Shaman-Enhancement','DemonHunter-Havoc','Monk-Brewmaster','Evoker-Augmentation','Druid-Balance','DeathKnight-Blood','Warrior-Arms','Mage-Arcane','Mage-Frost','Unknown-Unknown','Warrior-Protection','Shaman-Elemental','Evoker-Devastation','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','DemonHunter-Vengeance','Paladin-Retribution','Druid-Guardian','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Evoker-Preservation','Rogue-Subtlety','Hunter-BeastMastery','Priest-Shadow','Rogue-Outlaw','Rogue-Assassination','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Devourer','Paladin-Protection','Hunter-Survival','Priest-Discipline','Druid-Feral',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-10-20',data={Ad='Adam:BAAANQAECgUIBQABNQAECggIJgABAHglAA==.Adroc:BAAANQAECgUIBQAAAA==.',
Ah='Ahpuch:BAABNQAECn8xAAICAAoKqhq2FgDmAgACAAoKqhq2FgDmAgAAAA==.',
Ai='Aidasul:BAABNQAECn8YAAIDAAcKQRf2DwDuAQADAAcKQRf2DwDuAQAAAA==.',
Al='Alarin:BAAANQADCgcIBwAAAA==.Aldesca:BAABNQAECn8VAAIEAAcKqxKGDACMAQAEAAcKqxKGDACMAQAAAA==.Allarie:BAAANQADCggIDgAAAA==.',
Am='Amarilli:BAAANQADCgUICAABNQAECgoKMgAFAH0cAA==.',
An='Ancile:BAAANQAECgYIBwAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgcIDgAAAA==.',
Ar='Armstrõng:BAAANQAECgQIBQAAAA==.',
As='Ashaxxi:BAACNQAFFH8OAAIGAAUKUQj0CgCmAAAGAAUKUQj0CgCmAAA1AAQKfxYAAgYABQo+FXcfAP8AAAYABQo+FXcfAP8AAAAA.Ashpaw:BAABNQAECn8XAAIDAAgKhgo+GABfAQADAAgKhgo+GABfAQABNQAFFAUIDgAGAFEIAA==.Aspen:BAAANQAECgEIAQAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAABNQAECn8YAAIHAAkKRyCOLQAHAwAHAAkKRyCOLQAHAwABNQAFFAcIJAAIANIlAA==.Atmospherez:BAACNQAFFH8kAAMIAAcK0iU6BwBQAgAIAAYKsCU6BwBQAgAJAAEKWybMAwBwAAA1AAQKfyQAAggACgq4JZweAF4DAAgACgq4JZweAF4DAAAA.',
Au='Aurzon:BAAANQADCgUIBwABNQADCgcIDgAKAAAAAA==.',
Av='Avaniah:BAABNQAECn8iAAILAAkKQx6JAwCsAQALAAkKQx6JAwCsAQAAAA==.',
Az='Azhara:BAAANQAECgIIAQAAAA==.Azmodan:BAAANQADCgcIBwAAAA==.Azraelor:BAACNQAFFH8JAAMBAAQKSBhEBAACAQABAAMKSBhEBAACAQAMAAEKAACzLwBMAAA1AAQKf0IAAwEACgrzI+EDAFsDAAEACgrzI+EDAFsDAAwACQqRGidLAEoCAAAA.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQAECgUIBgAAAA==.Badhealz:BAAANQADCggIDgAAAA==.Baep:BAAANQAECgUICQAAAA==.Bandrago:BAABNQAECn8tAAINAAkKcQndBwD4AAANAAkKcQndBwD4AAAAAA==.Barracuda:BAAANQAECgMIAwAAAA==.Batmeng:BAAANQAECgYIAwAAAA==.',
Bb='Bbirog:BAAANQAECggIDQABNQAECgkJHQAOADgdAA==.',
Be='Bearione:BAAANQAECggIAwAAAA==.Beaulioh:BAABNQAECn8dAAIOAAkKOB0OFQDJAQAOAAkKOB0OFQDJAQAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgcIFQAFAM4hAA==.Belegmor:BAAANQAECgIIAgABNQAECgcIGAADAEEXAA==.Benfrank:BAABNQAECn8gAAIFAAgKoxasPgAEAgAFAAgKoxasPgAEAgAAAA==.Bernthul:BAAANQAECgcIDgAAAA==.Bethan:BAABNQAECn8UAAIJAAcK1Qk0FQBZAQAJAAcK1Qk0FQBZAQAAAA==.',
Bl='Blaart:BAABNQAECn8eAAQPAAgKsRa8hgDVAQAPAAcKyhW8hgDVAQAQAAIKrxbVUgCGAAARAAEKAAA/MwAtAAAAAA==.Blackwaters:BAABNQAECn8mAAMBAAgKeCXQBABEAwABAAgKeCXQBABEAwAMAAUKdxUcrAA7AQAAAA==.Blax:BAABNQAECn8kAAMSAAoKFRoLAgDPAQASAAgKExwLAgDPAQAHAAYK2BKeyQBkAQAAAA==.Blindcow:BAACNQAFFH8FAAIHAAQKrwxfJgDNAAAHAAQKrwxfJgDNAAA1AAQKfzAAAgcACgqBHFk5AOACAAcACgqBHFk5AOACAAAA.Blindhugs:BAABNQAECn8YAAMCAAgKwRFDNwD3AQACAAgKdBFDNwD3AQATAAQKDgXOJgCCAAAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgYIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECgoKLAAUAOYfAA==.',
Bo='Bodytypebig:BAABNQAECn85AAIVAAoKxRvrCwCqAgAVAAoKxRvrCwCqAgAAAA==.Boicrystian:BAAANQAECgYIDgAAAA==.Bolillo:BAAANQADCggIDwABNQAECgkJHQAOADgdAA==.Bomie:BAAANQADCgUIBQAAAA==.Bookitty:BAAANQADCggIGAAAAA==.Boosty:BAABNQAECn80AAIHAAkKjx/hBwBBAgAHAAkKjx/hBwBBAgAAAA==.Bossladie:BAAANQAECgUIBgAAAA==.Bossladìe:BAABNQAECn84AAIWAAoK0xqMBACgAgAWAAoK0xqMBACgAgAAAA==.Boston:BAAANQAECgIIAwAAAA==.',
Br='Brenagain:BAAANQAECgQIBAAAAA==.Brewholic:BAABNQAECn8eAAIXAAgKiiOQBwAZAwAXAAgKiiOQBwAZAwAAAA==.Brip:BAAANQAECggICAAAAA==.Bristle:BAABNQAECn83AAMBAAoKJyBVAQBzAgAMAAkKhyCIGAA1AwABAAgKrhxVAQBzAgAAAA==.Brommix:BAAANQADCgMIBgAAAA==.Brotem:BAAANQAECggIBwAAAA==.Broxy:BAAANQAECgEIBAAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAABNQAECn8WAAIWAAgK+w7YdAC5AQAWAAgK+w7YdAC5AQAAAA==.',
['Bö']='Bönezone:BAAANQADCgQIBAAAAA==.',
Ca='Calaglin:BAABNQAECn8bAAQPAAgKDxXgjwC/AQAPAAcKuhPgjwC/AQAQAAEKvBtLagBMAAARAAEKsgH1NgAWAAAAAA==.Calelorian:BAAANQADCgcIGwAAAA==.Catstack:BAAANQAECgEIAQAAAA==.',
Ce='Celdiirn:BAAANQADCggIJwAAAA==.Celesti:BAABNQAECn8iAAIUAAgKIxBIQQBEAQAUAAgKIxBIQQBEAQAAAA==.',
Ch='Chaos:BAAANQAECgUICQABNQAECggICgAKAAAAAA==.Chiky:BAAANQAECgIIAwAAAA==.Choom:BAABNQAECn8ZAAIPAAgK7RAfmACrAQAPAAgK7RAfmACrAQAAAA==.Chubsy:BAABNQAECn8VAAMFAAkKXQlDWQBvAQAFAAYKMBBDWQBvAQAYAAgKowEcXwCKAAAAAA==.Chuckkyd:BAABNQAECn8qAAIUAAkKUBPqjgAHAgAUAAkKUBPqjgAHAgAAAA==.',
Cl='Claugh:BAABNQAECn8bAAMZAAkKexpYLAA8AgAZAAkKexpYLAA8AgAaAAEKTRSG2gA7AAAAAA==.Cleb:BAABNQAECn8cAAMUAAoKhCbsAQDzAwAUAAoKhCbsAQDzAwAWAAIKeR6C6gCsAAAAAA==.Clocker:BAABNQAECn8fAAIbAAgKCg9IKgA5AQAbAAgKCg9IKgA5AQAAAA==.Clumbsykoala:BAABNQAECn8bAAIFAAcKvw4RUgCTAQAFAAcKvw4RUgCTAQAAAA==.',
Co='Coldlikemyex:BAAANQAECgEIAQAAAA==.Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAACNQAFFH8dAAIcAAgKjRYMAgChAgAcAAgKjRYMAgChAgA1AAQKfy0AAhwACgryHiwFAI4BABwACgryHiwFAI4BAAAA.Combatcow:BAABNQAECn8dAAISAAgKHyL/BADdAgASAAgKHyL/BADdAgAAAA==.Contagion:BAABNQAECn8YAAMQAAgKoQNKSwCeAAAQAAgKoQNKSwCeAAAPAAEKywEDyAAOAAAAAA==.Coorona:BAAANQADCgcIEwAAAA==.Cozmic:BAABNQAECn8xAAMJAAoKlSLwAABJAgAIAAgKXyHtSwDpAgAJAAYKciHwAABJAgAAAA==.',
Cr='Craftymidget:BAAANQAECggIDwAAAA==.Crucifixd:BAAANQAECgEIAQAAAA==.Cryptonic:BAAANQAECggICAAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAABNQAECn8zAAIHAAgKTCC0CgATAgAHAAgKTCC0CgATAgAAAA==.',
Cu='Curandero:BAABNQAECn8XAAIMAAQKvBH40gDuAAAMAAQKvBH40gDuAAAAAA==.Curie:BAAANQAECgEIAQABNQAECgkJNAAdAA0cAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUICAAAAA==.Dameck:BAABNQAECn82AAIHAAoKcxaMDwDcAQAHAAoKcxaMDwDcAQAAAA==.Dankula:BAAANQABCgQIAQAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCggICgABNQAECggIHQAaAH4bAA==.Dasdots:BAABNQAECn8dAAQQAAkK1xqzAwAEAQARAAYKdhguAwA7AQAQAAMKAx6zAwAEAQAPAAEKcAdfTQEqAAAAAA==.Dasmuro:BAAANQADCgIIAgABNQAECgYIHwAGAOYFAA==.Davy:BAAANQADCgYIBgAAAA==.Dazzeler:BAABNQAECn8dAAIaAAgKfhugMABsAgAaAAgKfhugMABsAgAAAA==.',
De='Deadeenside:BAAANQAECgQIBgABNQAECgkJIAACAIsVAA==.Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAABNQAECn8iAAIeAAcKUhIJHwCbAQAeAAcKUhIJHwCbAQAAAA==.Delver:BAAANQAECgQICQAAAA==.Demongirly:BAAANQADCgQICAAAAA==.Demonsue:BAAANQAECgQIAwAAAA==.Demorlize:BAAANQADCgQIBAABNQAECgcIFQAdAFEPAA==.Denathria:BAABNQAECn8cAAMWAAkKDB8NGAAaAwAWAAkKDB8NGAAaAwAUAAEKYRJfkwFBAAAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAACNQAFFH8cAAMfAAgKpRWYAgBgAgAfAAgKpRWYAgBgAgAOAAIKPQXrJACvAAA1AAQKfycAAh8ACgrkIc8IAFEDAB8ACgrkIc8IAFEDAAAA.Deviourer:BAAANQABCgIIAgAAAA==.Devo:BAAANQABCgIIAgAAAA==.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.Difflect:BAAANQADCgYIBgAAAA==.Diio:BAAANQADCggICAAAAA==.',
Do='Doak:BAABNQAECn80AAQdAAkKDRwUDwCJAgAdAAkKDRwUDwCJAgAgAAQK8wh/EwDIAAAhAAIKigkjkABxAAAAAA==.Dotz:BAACNQAFFH8HAAMQAAMKAxayCwChAAAQAAIKbheyCwChAAAPAAEKLxPGPwBMAAA1AAQKfyEAAxAACQp0HgUlAEsBAA8ABwpKHgduABQCABAABgq5EAUlAEsBAAAA.Douchec:BAAANQAECgUIBgAAAA==.',
Dr='Draconius:BAAANQADCgYIGQAAAA==.Draenor:BAAANQAECgMIBgAAAA==.Dragondilly:BAAANQAECgMIBAAAAA==.Dragonette:BAAANQAECgQIBAABNQAECgkJKgAPAAAYAA==.Dragonforce:BAABNQAECn8fAAINAAcKNBmeFAADAgANAAcKNBmeFAADAgAAAA==.Dragonhaze:BAABNQAECn8ZAAIIAAYKGR4VvAAMAgAIAAYKGR4VvAAMAgAAAA==.Dragonskull:BAAANQAECgYIBgAAAA==.Drawkcab:BAACNQAFFH8FAAIhAAMKuAddEQDUAAAhAAMKuAddEQDUAAA1AAQKfxUAAiEACgqWGYMBAJICACEACgqWGYMBAJICAAAA.Drazentar:BAABNQAECn8fAAIGAAYK5gVwhgDkAAAGAAYK5gVwhgDkAAAAAA==.Dream:BAAANQAECgEIAQABNQAECgoKIAAbAAUUAA==.Drevox:BAABNQAECn8pAAIaAAgKnRllPQAqAgAaAAgKnRllPQAqAgAAAA==.Druiddruid:BAAANQADCgYICQAAAA==.',
Du='Dulgar:BAABNQAECn83AAMbAAoKzxkCFgClAQAbAAoKzxkCFgClAQAMAAEKdw4lLQE8AAAAAA==.Dumami:BAAANQAECgEJAQABNQAECgYIAwAKAAAAAA==.',
Dw='Dwarfasaurus:BAAANQAECgQIBAAAAA==.',
['Dë']='Dëlilah:BAAANQAECgYICAAAAA==.',
Ea='Eaglewarrior:BAAANQADCggIDgAAAA==.Eatmydisc:BAAANQAECgYICwAAAA==.',
Ec='Eclipselock:BAABNQAFFH8GAAIPAAYKOARDCQDbAAAPAAYKOARDCQDbAAAAAA==.',
Eg='Egwaine:BAAANQAECgcIDAABNQAECgoKMgAFAH0cAA==.',
El='Elind:BAAANQAECgQICAAAAA==.Elisha:BAAANQAECggIAQAAAA==.Elisyum:BAAANQAECgIIAgAAAA==.Elleduff:BAABNQAECn8ZAAIiAAcK2QnTOQBFAQAiAAcK2QnTOQBFAQAAAA==.Eloragon:BAAANQABCgMIAwAAAA==.Elspeth:BAAANQAECgEIAQAAAA==.Elydra:BAAANQAECgcIBwAAAA==.Elyssabeta:BAAANQADCgQJBAAAAA==.Elysstaa:BAABNQAECn83AAMOAAoKvxhrCwAuAgAOAAoKvxhrCwAuAgAfAAYK0RGTNgBvAQAAAA==.',
En='Endeavor:BAAANQAECgQIBQABNQAECgoKHwAaALYbAA==.Entïty:BAAANQAECgEIAQABNQAECgUIFwAbAIUjAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAABNQAECn8iAAIfAAgKlxmABAC6AQAfAAgKlxmABAC6AQAAAA==.',
Er='Erida:BAAANQAECgIJAgAAAA==.Ers:BAAANQADCgYIBgABNQAECgkJHwAHAA0hAA==.',
Es='Eskuf:BAAANQADCgMIAwAAAA==.',
Et='Etienne:BAAANQADCgEIAQAAAA==.Etík:BAAANQAECgUICAAAAA==.',
Ev='Evocative:BAACNQAFFH8FAAINAAIKwhe5CwCNAAANAAIKwhe5CwCNAAA1AAQKfxwAAg0ACQp6HcsKAL8CAA0ACQp6HcsKAL8CAAAA.',
Ex='Exaltso:BAAANQADCgYIDwAAAA==.',
Ey='Eyebright:BAAANQAFFAEIAQAAAA==.Eyye:BAAANQADCgQIBgABNQAECggIEQAKAAAAAA==.',
Fa='Farns:BAACNQAFFH8QAAMJAAYK9R0bAwDyAAAIAAUK3hyMGAC0AQAJAAMK2RgbAwDyAAA1AAQKfysAAwgACgplJf0XAHQDAAgACgoTJf0XAHQDAAkABgq1Jf0IAEkCAAAA.Fawndolynn:BAAANQAECgYIDAAAAA==.',
Fe='Felinepriest:BAABNQAECn8XAAMOAAgKeQ/wRgDyAAAOAAgKeQ/wRgDyAAAfAAUKvAKhXACTAAAAAA==.Felovan:BAAANQAECgEIAQAAAA==.Felsoaked:BAAANQAECgQIBQAAAA==.Felstehr:BAABNQAECn8aAAIPAAcKPgspnQCdAQAPAAcKPgspnQCdAQAAAA==.Feltotes:BAAANQAECgQIBAAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAABNQAECn8aAAIbAAkKbSBGHQD4AgAbAAkKbSBGHQD4AgAAAA==.Firebäne:BAABNQAECn8eAAIQAAoKvxxIAwAUAwAQAAoKvxxIAwAUAwAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAACNQAFFH8QAAMIAAcKgRdyEADzAQAIAAYKKhhyEADzAQAJAAEK3RTqBABhAAA1AAQKfyQAAwkACApZIpcZACkBAAgACAolIgOWAFQCAAkAAwrjIZcZACkBAAAA.',
Fr='Franklin:BAAANQAECggIDQAAAA==.Frankotronic:BAABNQAECn8iAAIIAAkKvhaQjgBiAgAIAAkKvhaQjgBiAgAAAA==.Fraynetrain:BAAANQAECgQIBAABNQAECgYIEgAKAAAAAA==.Frayniac:BAAANQAECgYIEgAAAA==.Freakies:BAAANQADCgQIBgAAAA==.Freightfrayn:BAAANQAECgEIAQAAAA==.Freyin:BAABNQAECn80AAIeAAoKMxuCEADsAQAeAAoKMxuCEADsAQAAAA==.Fridays:BAAANQAECgEIAQAAAA==.Frie:BAAANQADCgYIBgAAAA==.Frierin:BAAANQAECgIIAQAAAA==.Frolgar:BAAANQADCgYICAAAAA==.Frostyflakez:BAAANQAECgEJAQAAAA==.',
Fu='Fullclangg:BAACNQAFFH8HAAIWAAMKviQmEgA/AQAWAAMKviQmEgA/AQA1AAQKfxgAAhYACAp3HRs1AI8CABYACAp3HRs1AI8CAAE1AAUUCgonABwAxxYA.Fulldracarys:BAACNQAFFH8nAAIcAAoKxxa2AQC4AgAcAAoKxxa2AQC4AgA1AAQKfygAAhwACgoKI+0HACcDABwACgoKI+0HACcDAAAA.Fullgabagool:BAABNQAECn8eAAIOAAkKeB2uJADZAgAOAAkKeB2uJADZAgABNQAFFAoKJwAcAMcWAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAoKJwAcAMcWAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCggIGQAAAA==.Ganster:BAAANQAECgYICwAAAA==.Gaya:BAAANQADCgYIEAAAAA==.',
Ge='Gearsz:BAEANQAECgIIAgAAAA==.Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAABNQAFFH8SAAIHAAUKKAheGwA5AQAHAAUKKAheGwA5AQAAAA==.',
Gi='Ginyeng:BAABNQAFFH8LAAMMAAQKxA0jCADRAAAMAAQKxA0jCADRAAAbAAIKZQJvJQB3AAAAAA==.',
Gl='Glimpse:BAABNQAECn8kAAIJAAoKQCJgAQCDAwAJAAoKQCJgAQCDAwAAAA==.',
Gn='Gnomebody:BAAANQAECgIIAwAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBgAAAA==.',
Gr='Greenmonsta:BAAANQADCggICwAAAA==.Grimknight:BAABNQAECn88AAIUAAoKnSUoBADZAwAUAAoKnSUoBADZAwAAAA==.Groovi:BAAANQADCgUIBQAAAA==.Grîmmjòw:BAAANQADCgQIBAABNQAECgkJLAAaAPYPAA==.',
Gu='Guycow:BAABNQAECn8cAAIWAAkK9R6HHQD8AgAWAAkK9R6HHQD8AgAAAA==.',
['Gî']='Gîn:BAAANQADCgMIAwABNQAECgkJLAAaAPYPAA==.',
Ha='Haldur:BAAANQABCgIIAgAAAA==.Hambonë:BAACNQAFFH8bAAIFAAgKOB4WAwCYAgAFAAgKOB4WAwCYAgA1AAQKfykAAgUACgpPJvACAM8DAAUACgpPJvACAM8DAAAA.Hardballs:BAAANQAECgIIAwAAAA==.Hashbrowns:BAABNQAECn83AAIUAAoKMCUyAwDjAgAUAAoKMCUyAwDjAgAAAA==.Havdk:BAAANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECggIDwAAAA==.Hazreil:BAABNQAECn83AAIVAAoKDxgTBADbAQAVAAoKDxgTBADbAQAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIEQAAAA==.Heavenlee:BAABNQAECn8cAAIOAAcKNAq7lgBRAQAOAAcKNAq7lgBRAQABNQAECgMIAwAKAAAAAA==.Hecklefish:BAACNQAFFH8GAAIeAAQKpySvCQCuAQAeAAQKpySvCQCuAQA1AAQKfyoAAx4ACQq2JiECAOUDAB4ACQq2JiECAOUDACMAAgqqGKplAJUAAAAA.Hellik:BAAANQABCgMIAwAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAABNQAECn8uAAIMAAoKqxIfIwAvAQAMAAoKqxIfIwAvAQAAAA==.Highdegrees:BAAANQAECgQIBQAAAA==.Hinatta:BAAANQAECgEIAQABNQAECgcIKQAOACgbAA==.Hitagi:BAABNQAECn8dAAIIAAkKShfoJwB4AQAIAAkKShfoJwB4AQAAAA==.',
Ho='Hole:BAAANQAECgEIAgAAAA==.Hollo:BAAANQAECgQICgAAAA==.Holyblasts:BAABNQAECn8pAAIUAAkKjCEtKgAeAwAUAAkKjCEtKgAeAwAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgYIBwAKAAAAAA==.Horsey:BAAANQAECgYIBwABNQAECggIFwAZAKIeAA==.',
Hu='Huler:BAAANQADCgYICwAAAA==.Hummingbird:BAAANQAECgcICgABNQAECgkJHAAWAAwfAA==.Hungus:BAAANQAECgQIBgAAAA==.Hurtszick:BAAANQAECgcIDwAAAA==.',
Hy='Hydrotiger:BAAANQAECgYIBwABNQAECgoKNAABAAYgAA==.',
['Hä']='Härasou:BAAANQADCgYIEwAAAA==.',
['Hï']='Hïñåtä:BAAANQADCgEIAQABNQAECgkJLAAaAPYPAA==.',
Il='Illiturtle:BAABNQAECn8hAAMkAAgKeRwcJgAVAgAkAAgKeRwcJgAVAgATAAEKRgsHMwAwAAAAAA==.',
In='Indever:BAAANQABCgcICAAAAA==.Indigolemon:BAABNQAECn8kAAQFAAgKJBuILwBkAgAFAAgKJBqILwBkAgAVAAMKHhwyNQD7AAAYAAEKxwchfQAkAAAAAA==.Inkenhancer:BAABNQAECn8kAAIMAAgKjSDuIwD3AgAMAAgKjSDuIwD3AgAAAA==.Inscissor:BAABNQAFFH8IAAIhAAUKGwWVAwDMAAAhAAUKGwWVAwDMAAAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Iy='Iyari:BAAANQADCgYIDwAAAA==.',
Ja='Jaffaar:BAAANQADCggICAAAAA==.Jamie:BAABNQAECn8hAAMlAAoKvhJKEwDxAAAUAAcKrRDAuwClAQAlAAUK+hJKEwDxAAAAAA==.',
Je='Jeynsa:BAAANQAECgcIDgABNQAECgoKMgAFAH0cAA==.',
Ji='Jingadingado:BAAANQADCgYIBgAAAA==.',
Jo='Jollyollie:BAAANQADCgQIBQAAAA==.Joppy:BAAANQADCgIIAgAAAA==.',
Ju='Judojudy:BAAANQAECgQICQAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jë']='Jëf:BAAANQADCgIIAgAAAA==.',
['Jô']='Jôker:BAAANQAECgYIDwAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQAECggIDgAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kalano:BAAANQAECgMIAwAAAA==.Kaorii:BAAANQAECgUIBgAAAA==.Kappo:BAABNQAECn8bAAIHAAgK7BP5HwCEAQAHAAgK7BP5HwCEAQAAAA==.Karryn:BAAANQADCgQIAwAAAA==.Kathorall:BAABNQAECn8mAAIeAAkKYw81fQATAgAeAAkKYw81fQATAgAAAA==.Kawaiihealer:BAABNQAECn8pAAMOAAcKKBvODwD7AQAOAAcKKBvODwD7AQAfAAIKzgPDbwBJAAAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIBQAAAA==.Keledril:BAAANQAECggIDwAAAA==.Kemper:BAABNQAECn8iAAMmAAcKcA9oCADOAQAmAAcKcA9oCADOAQAeAAMKlQcZMgGGAAAAAA==.Kerrs:BAAANQAECgMIDAAAAA==.Kerrst:BAAANQAECgQIBwAAAA==.Kerrz:BAAANQAECgQIBAAAAA==.',
Ki='Kiamonk:BAAANQAECggICAAAAA==.Kiddyl:BAAANQADCgYIFAAAAA==.Kidneypopper:BAAANQAECgUIBgABNQAECgoKMQAJAJUiAA==.Kidyll:BAAANQADCgYICgAAAA==.Kievit:BAAANQAECgYIBwAAAA==.Kir:BAABNQAECn8gAAMCAAkKixUZLABCAgACAAgKTRcZLABCAgAkAAcKbhLuOQB2AQAAAA==.Kittana:BAABNQAECn8qAAIWAAkKzRy/MQCeAgAWAAkKzRy/MQCeAgAAAA==.Kittyhawke:BAABNQAECn8bAAIQAAoKCBguBgCrAgAQAAoKCBguBgCrAgABNQAECggIJAAFACQbAA==.',
Kk='Kkelhus:BAABNQAECn8dAAMLAAkKghMPEQAWAgALAAgKLhUPEQAWAgAHAAEK0wcZyAAxAAABNQAFFAUICgAdAKAOAA==.Kkonetica:BAAANQAECgIIAgABNQAFFAUICgAdAKAOAA==.Kkrantuq:BAACNQAFFH8KAAMdAAUKoA71BgDZAAAdAAUKoA71BgDZAAAhAAEKcwJOIwA7AAA1AAQKfy8AAh0ACgpGHBkJAOQCAB0ACgpGHBkJAOQCAAAA.Kkylar:BAABNQAECn8bAAMaAAoK5hCkFAA5AQAaAAkK5hCkFAA5AQAZAAYKygQPbwDiAAABNQAFFAUICgAdAKAOAA==.',
Kl='Klariityy:BAABNQAECn8oAAMOAAkKixVWQQBmAgAOAAkKixVWQQBmAgAfAAEKAABJfwAsAAAAAA==.Klarity:BAABNQAECn8VAAIBAAgKfwaeGwCqAQABAAgKfwaeGwCqAQAAAA==.Klarityqt:BAAANQAECgQIBAAAAA==.Klarityx:BAACNQAFFH8PAAIIAAQKVwqbLAAqAQAIAAQKVwqbLAAqAQA1AAQKf0sAAggACgqjILEYAHIDAAgACgqjILEYAHIDAAAA.',
Kn='Knownentity:BAABNQAECn8XAAIbAAUKhSMHGgCLAQAbAAUKhSMHGgCLAQAAAA==.',
Ko='Koma:BAAANQADCggJCAABNQAFFAcIHwAMANklAA==.Komatos:BAACNQAFFH8fAAIMAAcK2SWdAAAFAwAMAAcK2SWdAAAFAwA1AAQKfzcAAgwACgrAJtwCANwDAAwACgrAJtwCANwDAAAA.Koreantacos:BAAANQADCgcIDQAAAA==.Koronus:BAAANQADCgcIFwAAAA==.',
Kr='Kracklin:BAAANQAECgcIDgAAAA==.Kraygoth:BAAANQABCgUICgAAAA==.',
Ku='Kurisutina:BAAANQAECgQICAAAAA==.',
['Kâ']='Kânamë:BAAANQADCggIEQABNQAECgkJLAAaAPYPAA==.',
['Kê']='Kênsêi:BAABNQAECn8sAAMaAAkK9g/aFgArAQAaAAkK9g/aFgArAQAGAAMKgwuFlwCvAAAAAA==.',
['Kô']='Kôan:BAAANQAECgYIDwAAAA==.',
['Kû']='Kûkâkü:BAAANQAECgQIBAABNQAECgkJLAAaAPYPAA==.',
La='Largetimmy:BAAANQAECgQIBQABNQAECgkJHQAOADgdAA==.',
Le='Leafyjoe:BAABNQAECn8pAAIFAAoK+BsTJwCbAgAFAAoK+BsTJwCbAgAAAA==.Lechencaja:BAAANQADCgYJBgABNQAECgcIFAALAKwRAA==.Led:BAAANQAECgEIAQAAAA==.Legendarybob:BAAANQADCgYIBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAABNQAECn8jAAQaAAgKTQjqfAApAQAaAAcKFAbqfAApAQAZAAYK3wgRZAATAQAGAAcKBwZWfwD9AAAAAA==.Legö:BAAANQAECggIBgABNQAECggIIwAaAE0IAA==.Leitbur:BAAANQAECggICQAAAA==.Leviluxx:BAAANQABCggIFQAAAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECgoKKgAhAMUcAA==.',
Li='Libidine:BAAANQADCgIIAgABNQAECgcIFQAEAKsSAA==.Lido:BAABNQAECn8cAAMFAAkKWwVmeQDlAAAFAAgKWwVmeQDlAAAYAAkKGQi+TADaAAAAAA==.Lilcowdk:BAAANQAECgIIAgABNQAECgoKLgAQADkXAA==.Lildeemon:BAABNQAECn8uAAMQAAoKORfVCABuAgAQAAgKrhbVCABuAgAPAAkKzBX4YwAuAgAAAA==.Lilspyro:BAAANQAECgQIBAAAAA==.Lionsinpride:BAAANQADCgYIBgAAAA==.Livathian:BAABNQAECn8iAAIUAAgKNA2TwQCZAQAUAAgKNA2TwQCZAQAAAA==.Lizwiz:BAAANQAECgYICgAAAA==.',
Lo='Lokrah:BAAANQABCgMIBgAAAA==.Lothuial:BAAANQADCgcIBwAAAA==.',
Lu='Lucerubis:BAABNQAECn8gAAIdAAoKaAwwCQCfAQAdAAoKaAwwCQCfAQAAAA==.Lucifiux:BAABNQAECn8XAAQaAAgKawgpcgBNAQAaAAgKUAcpcgBNAQAGAAIKUwtFuQBVAAAZAAEKdQagvAAhAAAAAA==.Lunavel:BAABNQAECn8fAAMUAAcKmhL+0AB5AQAUAAYKYBX+0AB5AQAlAAUK9A3IRgDUAAAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Macaria:BAAANQAECgQIBAAAAA==.Maggette:BAAANQADCgYIBgABNQAECgkJKgAPAAAYAA==.Magicdan:BAAANQADCgYICAAAAA==.Magistrate:BAAANQADCgMIAwAAAA==.Malnorr:BAABNQAECn8oAAMPAAoKCBZqEgCxAQAPAAkKjRVqEgCxAQAQAAIKRhaVUgCHAAAAAA==.Manatarm:BAAANQADCgIIAgAAAA==.Mandragon:BAAANQADCgUIBQABNQAECgkJHAAWAPUeAA==.Mangol:BAABNQAECn8cAAMUAAkKZyQjDQCaAwAUAAkKZyQjDQCaAwAWAAMKGxQs2ADNAAAAAA==.Manudei:BAABNQAECn8dAAMWAAkK+yHRDwDaAQAWAAkK+yHRDwDaAQAUAAIKbwNc2QBSAAAAAA==.Marryg:BAAANQAECgIIAgABNQAECgoKHAAiALIYAA==.Maryillo:BAACNQAFFH8ZAAIFAAgKthp4BABpAgAFAAgKthp4BABpAgA1AAQKfygAAgUACgrQJOANAFsDAAUACgrQJOANAFsDAAAA.Mattdaemon:BAABNQAECn8ZAAIPAAkK8BiIDwDGAQAPAAkK8BiIDwDGAQAAAA==.',
Mc='Mcmannis:BAAANQAECggIEwAAAA==.Mcpoltrain:BAABNQAECn8WAAMLAAgKvwvxDgDJAAALAAgKqgrxDgDJAAASAAQKVQoXIgCnAAAAAA==.',
Me='Mennil:BAABNQAECn8VAAIeAAcKTwRj2ABQAQAeAAcKTwRj2ABQAQAAAA==.Mental:BAAANQAECgQIBgABNQAFFAYIEQAkAAwPAA==.Meolater:BAABNQAECn8vAAIcAAoKnR3kAADsAgAcAAoKnR3kAADsAgAAAA==.Mesmerise:BAAANQAECggIEgAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgoKKgAhAMUcAA==.Mindgoblinn:BAABNQAECn8lAAIOAAcKaxZSPwALAQAOAAcKaxZSPwALAQAAAA==.Minicookie:BAAANQAECgQIBAAAAA==.Minyaw:BAAANQAECgYIDQABNQAECgkJNAAdAA0cAA==.Mishrakthul:BAAANQAECgMIAwAAAA==.Missfearfact:BAAANQAECgYIDAAAAA==.',
Mm='Mmchocolat:BAAANQAECgYIAwAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEBNQAECn83AAImAAoK5B9lAACJAgAmAAoK5B9lAACJAgAAAA==.Mon:BAAANQAECgEIAQAAAA==.Moolissa:BAABNQAECn8bAAIMAAgKmAqIgQChAQAMAAgKmAqIgQChAQAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgMIBgAAAA==.Morbidchaos:BAACNQAFFH8kAAIkAAcKJCZbAADmAgAkAAcKJCZbAADmAgA1AAQKfyoAAyQACgowIj0JAEMDACQACgowIj0JAEMDAAIAAgq7H9xwALUAAAAA.Morkels:BAAANQAECgcIDAABNQAFFAkJJgAEAAclAA==.',
Mu='Muddyshark:BAABNQAECn8bAAMZAAkKPwcEYAAlAQAZAAgKGAcEYAAlAQAaAAYKIAWtjgDsAAAAAA==.Mukatsuku:BAAANQAECgYIDwAAAA==.Muscida:BAAANQAECgQIBQAAAA==.',
My='Mykhawk:BAAANQADCgUICAAAAA==.',
['Mâ']='Mâyüri:BAAANQAECgUICQABNQAECgkJLAAaAPYPAA==.',
Na='Naeth:BAABNQAECn8pAAIUAAgKDiFUTQCtAgAUAAgKDiFUTQCtAgAAAA==.Nalrot:BAAANQAECgEIAQABNQAECggIEgAKAAAAAA==.Nanahoshi:BAAANQAECgIIAgAAAA==.Narcine:BAABNQAECn8kAAIeAAoKnh8DIwALAwAeAAoKnh8DIwALAwAAAA==.',
Ne='Neciecakes:BAABNQAECn83AAMWAAoK4BjDBgBeAgAWAAoK4BjDBgBeAgAUAAEK4BCHnwE3AAAAAA==.Nee:BAABNQAECn8oAAMMAAoKgBbbkAB6AQAMAAYKuBDbkAB6AQAbAAoKmxUwIgBeAQAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nekus:BAAANQADCgcIBwAAAA==.Nelor:BAABNQAECn8iAAIkAAgKChOQDgBAAQAkAAgKChOQDgBAAQAAAA==.Nerftitty:BAAANQADCgUIBQAAAA==.Nettles:BAAANQAECgQICgAAAA==.Neverheal:BAAANQADCgEIAQAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ng='Ngàymai:BAAANQADCgQIBAAAAA==.',
Ni='Nicelikerice:BAAANQAECgQIBAAAAA==.Nightwatchr:BAAANQAECggIDgAAAA==.Nitashal:BAABNQAECn8iAAMcAAkKch2zDQDLAgAcAAkKch2zDQDLAgANAAEKAAAePAA2AAABNQAFFAQICwAMAMQNAA==.',
No='Nokthro:BAAANQADCgYJBgABNQAFFAUIDAANADccAA==.',
Nu='Nubsaiboot:BAABNQAECn8UAAMhAAYKKxUtXQBCAQAhAAUK1hMtXQBCAQAdAAQKqBCmMgCOAAABNQAECgkJIAACAIsVAA==.',
Ny='Nythariel:BAAANQADCggIHQAAAA==.',
['Në']='Nëzükõ:BAAANQADCgYICgABNQAECgkJLAAaAPYPAA==.',
Od='Odi:BAAANQAECgUIDQAAAA==.',
Ok='Okiaat:BAAANQAECgYIBwAAAA==.',
Ol='Oliviawildè:BAABNQAECn8mAAMWAAoK3BpEHgD4AgAWAAoK3BpEHgD4AgAUAAEKAACvzQEhAAAAAA==.',
On='Onezero:BAAANQAECgIIAgAAAA==.Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAABNQAECn8VAAMFAAcKziHfMQBUAgAFAAYKQyXfMQBUAgAYAAYKdRahNAB2AQAAAA==.Pallyforhire:BAAANQAECgQICQAAAA==.Panfriedrice:BAAANQAECggIDAAAAA==.Pantyblossom:BAABNQAECn8hAAIOAAkKtxxoGQCpAQAOAAkKtxxoGQCpAQABNQAECgkJKgAPAAAYAA==.',
Pe='Peaches:BAAANQAECggICgAAAA==.Peewees:BAAANQADCgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAABNQAECn8wAAIQAAgK6h5FBgCpAgAQAAgK6h5FBgCpAgAAAA==.Peladin:BAAANQABCgcJDAAAAA==.Pelado:BAAANQABCgIIAgAAAA==.Pelito:BAAANQADCgUJBQAAAA==.Pell:BAAANQADCgEIAQAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQAECgMIAgABNQAECgkJLgAHAI4RAA==.',
Ph='Phaeddrus:BAAANQAECgQIBQAAAA==.Phobos:BAABNQAECn8lAAIEAAkKjQqUAgBBAQAEAAkKjQqUAgBBAQAAAA==.Phogood:BAAANQAECgMIAwAAAA==.Phrix:BAAANQAECgUICgABNQAFFAUIDAANADccAA==.',
Pi='Pinecone:BAABNQAECn8bAAIFAAkKsyNNGgD2AgAFAAkKsyNNGgD2AgAAAA==.',
Pl='Ploppster:BAAANQAECgMIAwAAAA==.Plot:BAAANQAECggIEwAAAA==.Plsno:BAAANQADCgcICQAAAA==.',
Po='Poekimaw:BAAANQAECgMIAwAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAACNQAFFH8PAAIUAAQKQSSaBAAUAQAUAAQKQSSaBAAUAQA1AAQKfykAAhQACgouJFQSAH4DABQACgouJFQSAH4DAAAA.Poppinin:BAABNQAECn8kAAIUAAgKCBEunwDkAQAUAAgKCBEunwDkAQAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAABNQAECn8VAAQfAAcK7AYlPQBCAQAfAAcK7AYlPQBCAQAnAAYKvQhXEgABAQAOAAIKcgJs8wBKAAABNQAECggIGAACAMERAA==.',
Pr='Praedo:BAAANQADCgYIBgAAAA==.Prevaleon:BAAANQAECgEIAQAAAA==.',
Ps='Psychaos:BAABNQAECn8aAAIZAAkKTR4DBAA0AgAZAAkKTR4DBAA0AgAAAA==.Psychostorm:BAAANQAECgcIDgAAAA==.Psychritic:BAABNQAECn8YAAIIAAoKxRrAlQBUAgAIAAoKxRrAlQBUAgAAAA==.Psyence:BAAANQADCgcIDgAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purpletotem:BAABNQAECn8UAAIBAAgK+RVzEABiAgABAAgK+RVzEABiAgAAAA==.Purrsnikitty:BAAANQAECgMIAwAAAA==.Pus:BAAANQADCgYIBgABNQAECgkJNAAHAI8fAA==.',
Qo='Qookd:BAAANQAECgQICgAAAA==.',
Qu='Quillmane:BAAANQAECggIEAABNQAFFAUIDAANADccAA==.Quzaster:BAAANQAECgQIBAAAAA==.',
Ra='Ragebate:BAABNQAECn8iAAIkAAkKCh2zFQC2AgAkAAkKCh2zFQC2AgAAAA==.Ragingdeath:BAAANQADCgYIBwAAAA==.Rainakamugi:BAAANQAECgQICQABNQAFFAUICwAOAH4JAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAABNQAECn8VAAIGAAYKMhuiUACyAQAGAAYKMhuiUACyAQAAAA==.Ralphanir:BAABNQAECn8hAAMbAAcK7xK9ggCEAQAbAAcK7xK9ggCEAQAMAAMKnQ+18AC0AAAAAA==.Raskreia:BAAANQADCggICQAAAA==.Raygyu:BAAANQADCgQIBAABNQAECgkJHQAeAEggAA==.Rayvoker:BAAANQADCgYJDAABNQAECgkJHQAeAEggAA==.',
Re='Reek:BAABNQAECn8gAAIhAAkKHxG/MgASAgAhAAkKHxG/MgASAgAAAA==.Reignz:BAAANQAECgcIBwAAAA==.Rexari:BAABNQAECn8eAAMnAAgKLx0eCADpAQAnAAcK2RweCADpAQAfAAYKuRZXNgBxAQAAAA==.Rezmae:BAAANQAECgMIBgAAAA==.',
Rh='Rhaiordan:BAAANQAECgIIAgAAAA==.',
Ri='Riniedaze:BAAANQAECgEIAQAAAA==.',
Ro='Rockandstone:BAACNQAFFH8NAAIWAAUKjwy+DwBqAQAWAAUKjwy+DwBqAQA1AAQKfzcAAxYACgr1GJ4VAKgBABYACgr1GJ4VAKgBABQAAQoAAHIfAQAAAAAA.Rocki:BAAANQAECgEJAQABNQAFFAMIBwAQAAMWAA==.Rondrous:BAAANQADCggIEAABNQAECggIEgAKAAAAAA==.Rooty:BAAANQAECgUIDAABNQAECgkJGwAZAHsaAA==.Roron:BAAANQAECgQIBAAAAA==.',
Ru='Rundatrain:BAAANQADCgEIAQAAAA==.',
['Rì']='Rìmûrü:BAAANQADCggIDAABNQAECgkJLAAaAPYPAA==.',
Sa='Safetyspork:BAAANQAECggIEQAAAA==.Sagë:BAAANQAECgUIDgAAAA==.Sakonutz:BAABNQAECn8vAAIYAAkKvw1eCQChAQAYAAkKvw1eCQChAQAAAA==.Salsa:BAAANQADCgcIDwAAAA==.Saresh:BAACNQAFFH8PAAIOAAUK4BJYBwBkAQAOAAUK4BJYBwBkAQA1AAQKfxQAAg4ACAodFIs/AAoBAA4ACAodFIs/AAoBAAAA.Sathariel:BAAANQABCgIJAgAAAA==.Sauron:BAAANQADCgQIBAAAAA==.Savages:BAAANQAECgEIAQABNQAECgoKIAAbAAUUAA==.',
Sc='Schlee:BAAANQABCgYJCAAAAA==.Screeps:BAAANQABCgcIDgABNQADCgYIBwAKAAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAABNQAECn8qAAIPAAkKABh5SgB0AgAPAAkKABh5SgB0AgAAAA==.Selceor:BAAANQADCggIDgAAAA==.Sendh:BAABNQAECn8VAAIkAAcK2RMUMgCwAQAkAAcK2RMUMgCwAQAAAA==.Sermet:BAABNQAECn8WAAMiAAgKAxx4JQD4AQAiAAYKTh94JQD4AQAXAAMKyAx5HABgAAABNQAECgoKJgAkAJUcAA==.Sermonn:BAAANQAECgQIBgAAAA==.Serous:BAABNQAECn8dAAISAAcKIRWjDwCvAQASAAcKIRWjDwCvAQAAAA==.Serwellmet:BAAANQAECgMIAwABNQAECgoKJgAkAJUcAA==.Seshin:BAAANQAECggIIgAAAQ==.Set:BAAANQAECgEIAQABNQAFFAUIDAANADccAA==.Setal:BAACNQAFFH8MAAINAAUKNxz5AADxAAANAAUKNxz5AADxAAA1AAQKfzQAAw0ACgr/IFMFAD4DAA0ACgr/IFMFAD4DAAQAAQqjCVcjADkAAAAA.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgkJNAAdAA0cAA==.Shammoo:BAAANQAECgMIAgAAAA==.Shawz:BAAANQADCgYIBgAAAA==.Shcho:BAAANQAECgYICQAAAA==.Sheepe:BAABNQAECn8fAAMSAAcKdBeJDgDGAQASAAcKdBeJDgDGAQAHAAEK+QNHYAEmAAAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgQIBAAAAA==.Shinyscalp:BAABNQAECn8jAAIHAAkKtiN2DQCOAwAHAAkKtiN2DQCOAwAAAA==.Shkanna:BAAANQAECggIDQAAAA==.Shogunz:BAAANQAECgUJBgAAAA==.',
Si='Simaria:BAAANQAECgEIAQAAAA==.Sinapaladin:BAABNQAECn8eAAMUAAkK/hR+eQA5AgAUAAkK/hR+eQA5AgAlAAYKTBFtOAAoAQABNQAECgkJIAACAIsVAA==.Siomara:BAABNQAECn8qAAMfAAkKtxGiAwDYAQAfAAkKtxGiAwDYAQAOAAYKcg/UlgBRAQAAAA==.Sivanya:BAAANQADCgYJBgAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgYIBwAAAA==.Skrepz:BAAANQABCgIJAgABNQADCgYIBwAKAAAAAA==.Skypri:BAAANQAECgQIBgAAAA==.',
Sl='Slabbcrakle:BAAANQADCgcICAAAAA==.Slabbhammer:BAAANQADCgYIBgAAAA==.Slabbster:BAABNQAECn8aAAIeAAgKSBh3UwB2AgAeAAgKSBh3UwB2AgAAAA==.',
Sm='Smooshednewt:BAABNQAECn80AAIBAAoKBiBqBQA1AwABAAoKBiBqBQA1AwAAAA==.',
Sn='Sne:BAABNQAECn8WAAIZAAUKwA/RKQD4AAAZAAUKwA/RKQD4AAAAAA==.Snoop:BAABNQAECn8mAAIIAAoKpQ9LFQC/AQAIAAoKpQ9LFQC/AQAAAA==.',
So='Soloa:BAAANQAECgQICAAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAABNQAECn8yAAIFAAoKfRzWGAABAwAFAAoKfRzWGAABAwAAAA==.Sosneaky:BAAANQADCgMICAAAAA==.Soulfuria:BAAANQAECggIBwAAAA==.',
Sp='Spekk:BAAANQADCgYICgAAAA==.Speknawz:BAACNQAFFH8FAAMdAAQK7AUHDQDXAAAdAAMKvAIHDQDXAAAhAAEKSwygIABHAAA1AAQKfyMAAx0ACgoCFs4RAGUCAB0ACQpvFc4RAGUCACEABApqGGt1ANsAAAAA.Splatzill:BAAANQADCgIIAgABNQAFFAMIBwAHALYKAA==.Spoiledangel:BAABNQAECn8cAAMOAAYKbhiDfwCaAQAOAAYKbhiDfwCaAQAfAAIKzgT2cABGAAAAAA==.Spoonhat:BAAANQAECgQIBAABNQAECggIEQAKAAAAAA==.Springz:BAAANQAECgUICwAAAA==.',
Sr='Srwednesday:BAAANQAECgQIBQAAAA==.',
St='Staggering:BAABNQAECn8oAAIMAAkKExbGRABiAgAMAAkKExbGRABiAgAAAA==.Starryniight:BAABNQAECn8bAAIPAAYK/gWXYwC7AAAPAAYK/gWXYwC7AAAAAA==.Stephsux:BAABNQAECn8ZAAIQAAkKFxLJCwA7AgAQAAkKFxLJCwA7AgAAAA==.Stickers:BAAANQAECgMJBAAAAA==.Stormbringer:BAAANQAECgQIBAAAAA==.Struck:BAAANQAECgIIAgAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgYIBwAAAA==.Suika:BAAANQAECgQIBAAAAA==.Sunaellia:BAAANQADCgEIAQAAAA==.Supanova:BAABNQAECn8zAAMfAAoKLBiXGACNAgAfAAkKERqXGACNAgAOAAgKwxvWPQBzAgABNQAECgoKNAABAAYgAA==.Surwick:BAABNQAECn8lAAIUAAkKug0zKACHAQAUAAkKug0zKACHAQAAAA==.',
Sv='Svelus:BAACNQAFFH8XAAIUAAcKHCXBAADdAgAUAAcKHCXBAADdAgA1AAQKfy4AAhQACgrmIlcNAJkDABQACgrmIlcNAJkDAAAA.',
Sw='Swingin:BAABNQAECn8iAAIlAAcKsRDvDQAoAQAlAAcKsRDvDQAoAQAAAA==.',
Sy='Sycophancy:BAAANQAECgIIBQABNQAECgoKNAABAAYgAA==.Synaptichole:BAAANQAECgQICAAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tachealz:BAABNQAECn8gAAMbAAoKBRTDXQD2AQAbAAoKBRTDXQD2AQABAAQKxgSvKgC9AAAAAA==.Talos:BAAANQAECgEIAQAAAA==.Tanurhide:BAAANQAECgIIAgAAAA==.Taropie:BAAANQAECgQICAAAAA==.Tartan:BAACNQAFFH8LAAIjAAUKAxspEgAcAQAjAAUKAxspEgAcAQA1AAQKfxkAAiMACAqlG8MLADMBACMACAqlG8MLADMBAAAA.Taurenmill:BAAANQADCgIIAgAAAA==.Taylorswif:BAAANQADCgEIAQABNQAECgkJIgAJAJQgAA==.',
Te='Tearal:BAAANQAECgIIAgAAAA==.Techi:BAAANQADCgIIAgAAAA==.Teewat:BAAANQAECgUICQAAAA==.Temres:BAABNQAECn8mAAQkAAoKlRw9EwDQAgAkAAgKCCE9EwDQAgACAAcK5BdHSACHAQATAAEKFx2ELABRAAAAAA==.Tendermulva:BAABNQAECn8dAAMRAAkKeQiVCwCxAQARAAkKeQiVCwCxAQAPAAIK9ABMvAAyAAAAAA==.Terekk:BAAANQADCggIHwAAAA==.Teshtara:BAAANQAECgUICgABNQAECgoKMgAFAH0cAA==.',
Th='Theod:BAAANQADCgYIBwAAAA==.Thesauce:BAACNQAFFH8VAAMiAAYKsyMMBgCwAQAiAAUKsyMMBgCwAQADAAQKxxmfBABKAQA1AAQKfyQAAyIACgqKIRQHAF8DACIACgowIRQHAF8DAAMABwrlJHkIAKMCAAAA.Theusaus:BAAANQAECggICwAAAA==.Thiaw:BAAANQAECgQICQAAAA==.Thickette:BAAANQADCgQIBAABNQAECgkJKgAPAAAYAA==.Thimo:BAAANQADCgEIAQABNQADCggICQAKAAAAAA==.Thrikal:BAABNQAECn83AAICAAoKnREDCgCoAQACAAoKnREDCgCoAQAAAA==.Thugd:BAAANQAECggIDAABNQAECgoKJgAIAKUPAA==.',
Ti='Tibernius:BAAANQADCgMIAwABNQAECgkJHQAoAPAaAA==.',
To='Tomsmg:BAACNQAFFH8HAAIIAAMK4Q4qGgCXAAAIAAMK4Q4qGgCXAAA1AAQKfygAAwgACQovG3B9AIMCAAgACQovG3B9AIMCAAkAAQp0B3xOACoAAAAA.Toofs:BAABNQAECn8fAAMHAAkKDSEPEgDHAQAHAAkKPCAPEgDHAQASAAIKwyQEHwDHAAAAAA==.Totemsh:BAAANQAECgIIAwABNQAECgkJHAAWAAwfAA==.Toxifay:BAABNQAECn8WAAIdAAcKIQYALQBZAQAdAAcKIQYALQBZAQAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAFFAMIBgACANEhAA==.Trd:BAAANQABCggICgAAAA==.Treehuggles:BAAANQAECgUIBwABNQAECggIGAACAMERAA==.Trollbanæ:BAAANQADCgUIBQAAAA==.Trousersnake:BAAANQADCggICAABNQAECggIHgAXAIojAA==.Truedat:BAAANQADCgQIBwAAAA==.',
Ts='Tsûñådê:BAAANQADCgQIAwABNQAECgkJLAAaAPYPAA==.',
['Tì']='Tìõ:BAAANQADCgYICgABNQAECgkJLAAaAPYPAA==.',
Ug='Ughtismo:BAAANQADCgUJBQAAAA==.',
Un='Undeadban:BAAANQAECgMIAgAAAA==.Unfiltered:BAAANQAECgEIAQAAAA==.',
Ur='Uranium:BAAANQAECgIIAgAAAA==.',
Us='Usagiknight:BAAANQAECgcIDwAAAA==.Ushii:BAAANQAECgQIEQAAAA==.',
Va='Valdemort:BAAANQADCgQIBAABNQAECggIEQAKAAAAAA==.Valei:BAAANQAECgMIAwAAAA==.',
Ve='Veganforlife:BAAANQADCgIIAwAAAA==.',
Vi='Vinda:BAABNQAECn83AAIfAAoKSRdkAwDkAQAfAAoKSRdkAwDkAQAAAA==.Vivixia:BAAANQAECgYIEAAAAA==.',
Vo='Volgrath:BAAANQAECggIEAAAAA==.Voodoolock:BAAANQAECgQIDwABNQAECgoKIAAbAAUUAA==.',
Vu='Vuletronix:BAAANQADCgIIAgAAAA==.',
Wa='Walkingboot:BAAANQADCgQIBAAAAA==.Wallo:BAABNQAECn8uAAMHAAkKjhG6nADUAQAHAAkK+w+6nADUAQASAAEKHxp6EwBSAAAAAA==.Washedbolt:BAAANQAECgIIBAAAAA==.Washedpyro:BAAANQAECgMIBgAAAA==.Washedzebu:BAABNQAECn8kAAMhAAgK5Bc0NgAAAgAhAAgK5Bc0NgAAAgAdAAUKzA87NgAHAQAAAA==.Watsatotem:BAAANQAECggIDAAAAA==.Wayfairkid:BAAANQAECgEIAQAAAA==.',
We='Weeb:BAACNQAFFH8mAAIEAAkKByUrAAC8AwAEAAkKByUrAAC8AwA1AAQKfyIAAwQACgo6JikBAJgDAAQACgo6JikBAJgDAA0ACArSF8YVAO8BAAAA.Werken:BAAANQAECgIIAgAAAA==.',
Wh='Whatsthis:BAAANQAECgcIDAAAAA==.Whiterabbitt:BAAANQADCggILwAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQAECggIDAAAAA==.Woofwoofwoof:BAAANQAECgUICwAAAA==.',
Wr='Writhe:BAAANQABCgQICAABNQAFFAgIGgADAJ0iAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xe='Xermet:BAAANQAECgMIAwABNQAECgoKJgAkAJUcAA==.',
Xq='Xquori:BAAANQADCggICwAAAA==.',
Ye='Yeeloow:BAAANQADCgYIDQAAAA==.',
Ys='Yshaarj:BAAANQADCggIEgAAAA==.',
Yu='Yulok:BAACNQAFFH8aAAMDAAgKnSJVAACyAgADAAcK3yJVAACyAgAiAAgKbRefAwAnAgA1AAQKfyYAAwMACgqYJuMAAM8DAAMACQqgJuMAAM8DACIABAoyJAM9AC4BAAAA.Yuukí:BAAANQADCggICAABNQAECgoKLAAUAOYfAA==.',
['Yâ']='Yâmamôto:BAAANQADCgQICwABNQAECgkJLAAaAPYPAA==.',
['Yú']='Yúúki:BAABNQAECn8eAAIGAAoKTh0uIQCrAgAGAAoKTh0uIQCrAgABNQAECgoKLAAUAOYfAA==.',
Za='Zaberra:BAABNQAECn8vAAIRAAoK1RXQAwCwAgARAAoK1RXQAwCwAgABNQAECgoKMgAFAH0cAA==.Zanarkand:BAABNQAECn8cAAIUAAcKSAYEBAEYAQAUAAcKSAYEBAEYAQAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zerofort:BAAANQAECgYIBgAAAA==.Zexexe:BAAANQAECggIDQABNQAFFAgIGwAFADgeAA==.',
Zi='Zibroth:BAABNQAECn8qAAMYAAoKUhPgDABsAQAYAAoKUhPgDABsAQAFAAIKcAYjnwBhAAAAAA==.Zieg:BAAANQAECgcICwABNQAFFAUICAAhABsFAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Áo']='Áodh:BAAANQAECgYICQAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQAECgQIEAAAAA==.',
['Ýu']='Ýuuki:BAABNQAECn8sAAIUAAoK5h8MKQAiAwAUAAoK5h8MKQAiAwAAAA==.',
['ßr']='ßrß:BAABNQAECn8cAAIBAAkKaxgmAQCKAgABAAkKaxgmAQCKAgABNQAECgkJNAAHAI8fAA==.',
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
