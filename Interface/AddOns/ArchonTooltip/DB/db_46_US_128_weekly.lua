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

local lookup = {'Warrior-Protection','Mage-Frost','Hunter-Marksmanship','Warrior-Arms','Unknown-Unknown','Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Warrior-Fury','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Evoker-Preservation','Priest-Discipline','Paladin-Retribution','DemonHunter-Devourer','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Mage-Arcane','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Shadow','Shaman-Enhancement','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aaryn:BAAALgAECgcJEAABLgAECggJLwABAKsbAA==.',
Ab='Absynthia:BAABLgAECn8dAAICAAgJGwepfgA9AQACAAgJGwepfgA9AQAAAA==.',
Ac='Academe:BAABLgAECn8oAAICAAgJnxUcQgDTAQACAAgJnxUcQgDTAQAAAA==.Acrid:BAAALgAECgEJAQAAAA==.',
Ad='Ados:BAAALgAECgYJDwAAAA==.',
Ae='Aeity:BAAALgAECgYJCwAAAA==.Aellion:BAAALgADCgEJAQAAAA==.Aellopus:BAAALgAECgEJAQAAAA==.Aenas:BAABLgAECn8VAAIDAAgJmAXoEQD3AAADAAgJmAXoEQD3AAAAAA==.Aero:BAABLgAECn8vAAMBAAgJqxvdCAAhAgABAAgJqxvdCAAhAgAEAAYJZw6EFwA+AQAAAA==.',
Af='Afflictedd:BAAALgAECgEJAQAAAA==.',
Ag='Agapetus:BAAALgADCgYJBgAAAA==.',
Ah='Ahren:BAAALgAECgQJCwAAAA==.Ahuizott:BAAALgAECggJCAABLgAECggJCAAFAAAAAA==.',
Ak='Akata:BAAALgADCgcJBwAAAA==.',
Al='Alayder:BAAALgADCgYJBgAAAA==.Almighty:BAABLgAECn8WAAIGAAkJDxXaFwA2AgAGAAkJDxXaFwA2AgAAAA==.Alomeo:BAAALgADCggJDAAAAA==.',
Am='Amarí:BAAALgADCggJGAAAAA==.Amayêlle:BAAALgADCggJGAAAAA==.Amendos:BAAALgAECgYJCwAAAA==.Amiliane:BAABLgAECn8tAAQHAAgJjhTTBwCDAQAHAAcJmBbTBwCDAQAIAAUJmwxjlQDSAAAJAAUJIwpaHQCHAAAAAA==.Amunshi:BAAALgADCgQJBAAAAA==.Amz:BAAALgAECgYJDAAAAA==.',
An='Anadrien:BAABLgAECn8yAAMKAAgJWx8qCwDNAgAKAAgJWx8qCwDNAgALAAMJHQ+mRwCXAAAAAA==.Ancelagon:BAAALgADCgYJBgAAAA==.Andrae:BAAALgAECgcJCQAAAA==.Andrastae:BAAALgAECgYJBgAAAA==.Angrima:BAAALgAECgEJAQAAAA==.Angrimia:BAABLgAECn8vAAIMAAgJCx2RCQAqAgAMAAgJCx2RCQAqAgAAAA==.Anju:BAAALgAECgEJAgAAAA==.Ansticé:BAAALgADCgYJBgAAAA==.Antal:BAAALgAECgcJEwAAAA==.Anthelyn:BAAALgADCgcJBwAAAA==.',
Ar='Arannis:BAAALgADCgkJGQAAAA==.Arboria:BAAALgAECggJEwAAAA==.Archielgh:BAABLgAECn8YAAINAAcJ5ApjNQAjAQANAAcJ5ApjNQAjAQAAAA==.Areldor:BAAALgAECggJBQAAAA==.Aremethea:BAAALgADCgkJFwABLgAECgYJEQAFAAAAAA==.Ariaa:BAAALgADCggJDAAAAA==.Arkannah:BAAALgADCgcJBwAAAA==.Aronk:BAABLgAECn8tAAQOAAgJcxS9IQBcAQAOAAcJeBW9IQBcAQAPAAYJPQ3vLQACAQAQAAgJ1gOFPgDXAAAAAA==.Arore:BAAALgADCgEJAQABLgAECggJLQAOAHMUAA==.Aroreck:BAAALgADCgMJAwABLgAECggJLQAOAHMUAA==.Arorepriest:BAAALgADCgcJBwABLgAECggJLQAOAHMUAA==.Articulàte:BAAALgAECgQJBwAAAA==.Arzec:BAABLgAECn8eAAIRAAcJfAaqGAD/AAARAAcJfAaqGAD/AAAAAA==.Arîel:BAAALgAECgQJBQAAAA==.',
At='Atheania:BAAALgAECgkJCAAAAA==.',
Av='Avestara:BAABLgAECn8vAAISAAgJyBuBDQA/AgASAAgJyBuBDQA/AgAAAA==.',
Aw='Awenlock:BAEALgADCgcJCAAAAA==.',
Ay='Ayleesh:BAAALgADCgIJAgAAAA==.Ayleesha:BAAALgAECgUJBgAAAA==.Ayluid:BAAALgAECgUJEQAAAA==.',
Az='Azavtani:BAAALgADCgEJAgAAAA==.Azazill:BAAALgAECggJDgAAAA==.Azeralle:BAAALgADCgkJCgAAAA==.Azmodeus:BAAALgAECgMJBAAAAA==.Azoril:BAABLgAECn82AAITAAgJahJTUgCIAQATAAgJahJTUgCIAQAAAA==.Azùla:BAAALgADCgcJDQAAAA==.',
['Aí']='Aídeen:BAABLgAECn8UAAICAAYJ4gLj0ACpAAACAAYJ4gLj0ACpAAAAAA==.',
Ba='Baal:BAAALgADCgcJEQAAAA==.Babaspook:BAAALgAECggJCwAAAA==.Badseedz:BAAALgAECgcJBgAAAA==.Baelnorn:BAABLgAECn8mAAMIAAgJwB+zGABWAgAIAAgJwB+zGABWAgAHAAMJ+Rb1SgCNAAAAAA==.Bains:BAAALgADCgcJBwAAAA==.Baja:BAAALgAECgQJBwAAAA==.Bandit:BAAALgAECgUJCgAAAA==.Barress:BAAALgAECgEJAQAAAA==.Batrela:BAAALgAECgYJDwAAAA==.Battleturtle:BAAALgAECgYJCwAAAA==.Batôsai:BAAALgAECgEJAgAAAA==.Bazir:BAAALgAECgIJAgABLgAFFAUJEwACADIXAA==.',
Bd='Bddaddy:BAAALgAECgMJBAAAAA==.',
Be='Beardiso:BAAALgADCgEJAQAAAA==.Bearjuu:BAAALgAECgYJCQABLgAECgkJHwAUAPQbAA==.Bearpawz:BAABLgAECn8pAAIVAAkJ0xmsBABbAgAVAAkJ0xmsBABbAgAAAA==.Bearrel:BAAALgAECgYJCwAAAA==.Bearrier:BAAALgADCgEJAQAAAA==.Beastcleave:BAAALgAECgUJBQAAAA==.Bekens:BAABLgAECn8iAAIWAAgJIyFDFABnAgAWAAgJIyFDFABnAgAAAA==.Belaraariaae:BAAALgADCgQJBAAAAA==.Benastiel:BAAALgADCgYJBwAAAA==.Benwetta:BAAALgAECgMJAwAAAA==.Bernardboggs:BAABLgAECn8aAAIPAAcJ7xvXEwDNAQAPAAcJ7xvXEwDNAQAAAA==.Bethbathory:BAABLgAECn8wAAIJAAkJLRqTAgBBAgAJAAkJLRqTAgBBAgAAAA==.',
Bh='Bheefknight:BAABLgAECn8XAAMMAAYJgQ8BIQD1AAAMAAYJgQ8BIQD1AAAXAAMJzwLKAwFwAAAAAA==.',
Bi='Bibbee:BAAALgAECggJCAAAAA==.Bierbro:BAABLgAECn8VAAIXAAcJiRH+jABnAQAXAAcJiRH+jABnAQAAAA==.Bigbus:BAAALgADCgEJAQAAAA==.Bigfacts:BAAALgAECggJDQAAAA==.Bigoldee:BAAALgADCgUJBQAAAA==.Bigyk:BAAALgADCgYJBgAAAA==.Billié:BAABLgAECn8sAAQIAAkJyiOhAwAxAwAIAAgJyiOhAwAxAwAHAAMJ5iD/KAAfAQAJAAIJ1h3gLABFAAAAAA==.',
Bk='Bk:BAAALgADCgYJBgAAAA==.',
Bl='Blightheaded:BAAALgAECgQJBwABLgAECgcJCQAFAAAAAA==.Blindëye:BAAALgAECgYJDQAAAA==.Blumir:BAAALgAECgcJDQAAAA==.',
Bn='Bnththeocean:BAABLgAECn8YAAIGAAkJaRVcGgAhAgAGAAkJaRVcGgAhAgAAAA==.',
Bo='Bobmauley:BAAALgADCgQJBAAAAA==.Bombkin:BAABLgAECn8vAAIKAAgJ4yJ8DgCjAgAKAAgJ4yJ8DgCjAgAAAA==.Bonchonn:BAACLgAFFH8JAAIWAAMJXBoOLwAAAQAWAAMJXBoOLwAAAQAuAAQKfyAAAhYACAlPIHAOAMgCABYACAlPIHAOAMgCAAAA.Bonkfoo:BAAALgADCgcJBwAAAA==.Bonkula:BAABLgAECn8gAAIGAAcJZw6WSwAcAQAGAAcJZw6WSwAcAQAAAA==.Boondox:BAAALgAECgMJAwAAAA==.Bootyfeastr:BAAALgADCgEJAwAAAA==.Bopmedaddy:BAAALgAECgkJCQAAAA==.Bops:BAAALgADCgQJBAAAAA==.Boredumb:BAAALgAECgYJBgAAAA==.Borque:BAAALgAECgYJCwABLgAECggJEwAFAAAAAA==.Bouncy:BAAALgAECgUJBQABLgAECgkJNQAXAFAcAA==.',
Br='Brae:BAAALgAECgYJDAAAAA==.Bralitha:BAAALgADCgEJAQAAAA==.Braumbastic:BAAALgADCgUJBQAAAA==.Brazonk:BAAALgADCgkJCQAAAA==.Brewzco:BAABLgAECn88AAIOAAkJBCXGAABbAwAOAAkJBCXGAABbAwAAAA==.Bricifergoat:BAACLgAFFH8cAAIYAAYJMCaZAgAyAgAYAAYJMCaZAgAyAgAuAAQKfyEAAhgACAmqJWsIAJICABgACAmqJWsIAJICAAEuAAUUAwkQABcAhCYA.Briciferkong:BAACLgAFFH8QAAIXAAMJhCajMABRAQAXAAMJhCajMABRAQAuAAQKfxkAAxcABwluIHZQAAACABcABwluIHZQAAACABkAAQknCKAYAC0AAAAA.Briciferyeah:BAAALgADCgQJBAABLgAFFAMJEAAXAIQmAA==.Brightblayde:BAABLgAECn8vAAITAAgJXhpAMwDrAQATAAgJXhpAMwDrAQAAAA==.Brique:BAAALgADCggJDAABLgAECggJEwAFAAAAAA==.',
Bu='Buanto:BAAALgAECgMJCQAAAA==.Bubblegumm:BAABLgAECn8mAAIKAAgJ6hX1JQDYAQAKAAgJ6hX1JQDYAQAAAA==.Bubieh:BAAALgAECgQJBQABLgAECgkJJAAMAIgjAA==.Bullshatner:BAAALgADCgQJBAAAAA==.Bumpinlumps:BAAALgAECgQJBAAAAA==.Bushwookiee:BAAALgAECgcJDQAAAA==.Butterknight:BAACLgAFFH8NAAIXAAQJERVoNgBHAQAXAAQJERVoNgBHAQAuAAQKfyMAAhcACAnXI0cWAPYCABcACAnXI0cWAPYCAAAA.Buttertotem:BAABLgAFFH8FAAMYAAMJBgMOJgClAAAYAAMJBgMOJgClAAAGAAIJrgS3RQBsAAAAAA==.',
Ca='Caanu:BAAALgADCgUJBwAAAA==.Calypso:BAAALgAECgMJAwAAAA==.Candlelock:BAAALgAECgcJDQAAAA==.Carirmonk:BAAALgAECgEJAQAAAA==.Cattroll:BAABLgAECn8mAAIKAAgJkiMJCwDOAgAKAAgJkiMJCwDOAgAAAA==.',
Cd='Cdub:BAABLgAECn8aAAITAAYJdhACiQASAQATAAYJdhACiQASAQAAAA==.',
Ce='Celidori:BAABLgAECn8XAAIUAAkJyg+yMwCsAQAUAAkJyg+yMwCsAQABLgAECggJJgAKAJIjAA==.Celithila:BAABLgAECn8tAAMaAAgJbBaNEgD/AQAaAAgJbBaNEgD/AQASAAYJegqqMgDqAAAAAA==.Celithvia:BAABLgAECn8hAAITAAgJ3BFxVQCAAQATAAgJ3BFxVQCAAQAAAA==.Ceroin:BAAALgADCgEJAQAAAA==.Cervantés:BAABLgAECn80AAMbAAkJXyL3AwDAAgAbAAkJGyL3AwDAAgAcAAcJMBtLBgAVAgAAAA==.',
Ch='Chaia:BAABLgAECn8hAAIKAAgJMhkxGgAsAgAKAAgJMhkxGgAsAgAAAA==.Chelsea:BAAALgAECgEJAQAAAA==.Cherra:BAAALgAECgcJBwABLgAECgcJFgAOABUgAA==.Chillmeister:BAAALgAECgcJBwAAAA==.Chise:BAABLgAECn8aAAISAAkJUxJ4HQCpAQASAAkJUxJ4HQCpAQAAAA==.Chitanka:BAAALgADCgQJBAAAAA==.Chrispyloa:BAAALgAECgQJCwAAAA==.Chubs:BAABLgAECn8bAAMHAAcJhRhPDgDjAQAHAAcJqRdPDgDjAQAIAAUJVhRyvgDcAAAAAA==.',
Cl='Clann:BAABLgAECn8iAAICAAcJDxEzcABbAQACAAcJDxEzcABbAQAAAA==.Cly:BAABLgAECn8UAAIdAAYJISHqFAAbAgAdAAYJISHqFAAbAgABLgAECggJDwAFAAAAAA==.Clyde:BAAALgADCgcJBwAAAA==.Clydk:BAAALgAECggJDwAAAA==.',
Co='Coachbeard:BAABLgAECn82AAIdAAkJ6BUFEQBEAgAdAAkJ6BUFEQBEAgAAAA==.Colzamenta:BAACLgAFFH8JAAIUAAQJYw+QPgDhAAAUAAQJYw+QPgDhAAAuAAQKfxQAAhQABwmfI9wqAFUCABQABwmfI9wqAFUCAAAA.Colzaratha:BAABLgAFFH8GAAIZAAQJaR8zAgB4AQAZAAQJaR8zAgB4AQAAAA==.Contract:BAAALgAECgcJDAAAAA==.Corpsereth:BAAALgAECgkJAwAAAA==.',
Cr='Creamcicle:BAAALgADCgEJAQAAAA==.Crispytots:BAAALgAECgcJDAAAAA==.Crit:BAAALgAECgUJCQABLgAECggJHAAPAEgWAA==.Critmypantz:BAABLgAECn8cAAIPAAgJSBbiIADPAQAPAAgJSBbiIADPAQAAAA==.Crosby:BAAALgADCgUJBQAAAA==.Cruel:BAAALgAECgIJAgABLgAECgQJBgAFAAAAAA==.',
Cu='Cudguzzler:BAAALgADCggJCQAAAA==.Cursegoesmoo:BAACLgAFFH8MAAIXAAQJuBz6MQBPAQAXAAQJuBz6MQBPAQAuAAQKfx8AAhcACQmYJGkEADgDABcACQmYJGkEADgDAAAA.Cuzz:BAAALgAECgQJBAAAAA==.',
Cy='Cygna:BAABLgAECn84AAIWAAgJjiFTFQCNAgAWAAgJjiFTFQCNAgAAAA==.Cyntheria:BAABLgAECn8nAAITAAkJqB+AFACLAgATAAkJqB+AFACLAgAAAA==.Cyphex:BAAALgADCgkJCAABLgAECggJOAAWAI4hAA==.',
Da='Daddybeàr:BAAALgAECgQJBQAAAA==.Daendron:BAAALgADCgQJBAAAAA==.Dajubah:BAABLgAECn8wAAIBAAkJiR74AwCtAgABAAkJiR74AwCtAgAAAA==.Dammitdave:BAABLgAECn8fAAITAAYJgAvDmQD1AAATAAYJgAvDmQD1AAAAAA==.Dangereuse:BAAALgAECgUJCQAAAA==.Darbi:BAAALgADCgEJAQAAAA==.Darinell:BAAALgAECgUJCwAAAA==.Darksaxon:BAABLgAECn8gAAIBAAcJ3B2sCgD4AQABAAcJ3B2sCgD4AQAAAA==.Darthsidd:BAAALgAECgkJCAAAAA==.',
De='Deathnethal:BAABLgAECn8UAAIXAAYJ2AqqjwD8AAAXAAYJ2AqqjwD8AAAAAA==.Deathweaver:BAAALgAFFAEJAQAAAA==.Deebbz:BAAALgAFFAIJAgAAAA==.Deebbzmonk:BAABLgAFFH8GAAIQAAIJTwcDKgBwAAAQAAIJTwcDKgBwAAAAAA==.Deeneye:BAAALgADCgkJCQABLgAECgYJDwAFAAAAAA==.Deeno:BAAALgAECgEJBQAAAA==.Defrausted:BAAALgAECggJCAAAAA==.Deme:BAAALgADCgcJCgAAAA==.Demonica:BAABLgAECn8aAAQIAAcJEx6iLADoAQAIAAYJEx6iLADoAQAJAAMJeBJXFQCnAAAHAAIJYBQcaABAAAAAAA==.Demonseedz:BAAALgAECgEJAgAAAA==.Dendrax:BAABLgAECn8pAAIIAAgJggufWABVAQAIAAgJggufWABVAQAAAA==.Dented:BAABLgAECn8fAAITAAcJTAq7rgAmAQATAAcJTAq7rgAmAQAAAA==.Derivation:BAAALgAECgQJCwAAAA==.Destitute:BAAALgAECgUJBQAAAA==.Detaren:BAAALgADCgEJAQAAAA==.Dethwing:BAAALgAECgIJBAAAAA==.Devadeity:BAABLgAECn8nAAIaAAgJCROUIwBeAQAaAAgJCROUIwBeAQAAAA==.Deviance:BAAALgAECgcJEgAAAA==.Devola:BAAALgADCgkJFAAAAA==.Dextero:BAAALgAECgQJBAABLgAECgcJIgAWAOkiAA==.',
Di='Didntask:BAAALgADCgEJAQABLgAECggJGwAMAIQOAA==.Dienmage:BAABLgAECn8oAAIeAAkJ0R6JAADVAgAeAAkJ0R6JAADVAgAAAA==.Digìt:BAAALgAECgIJAgABLgAECgcJGgAaAC4dAA==.Dirtychai:BAABLgAECn8hAAIaAAcJ/SBCCgB4AgAaAAcJ/SBCCgB4AgAAAA==.Dissonance:BAAALgAECgcJCAAAAA==.Diurd:BAAALgAECgEJAQAAAA==.Divine:BAAALgADCgYJBgAAAA==.',
Dj='Djanga:BAABLgAECn8wAAMLAAkJiiTTAQA6AwALAAkJiiTTAQA6AwAKAAQJvRoeZAAlAQAAAA==.Djdazzle:BAAALgAECggJAQAAAA==.',
Dk='Dkchocobussy:BAAALgADCgMJAwAAAA==.Dkdiso:BAAALgAECgcJCgAAAA==.',
Do='Doctorevil:BAAALgAECgYJEAAAAA==.Dogglefrog:BAAALgADCgEJAQAAAA==.Dominance:BAAALgADCgkJCwAAAA==.Doranthsæ:BAAALgADCgcJBwABLgAECgkJKgALAGodAA==.Dorito:BAABLgAFFH8GAAIXAAQJ+R76HwB3AQAXAAQJ+R76HwB3AQAAAA==.Dothausen:BAAALgAECgcJEwAAAA==.',
Dr='Dracaaron:BAAALgAECgUJBwAAAA==.Dragonevil:BAAALgADCgYJBgAAAA==.Dragooned:BAACLgAFFH8NAAICAAUJAhgWNgBMAQACAAUJAhgWNgBMAQAuAAQKfxUAAgIABwklJBIuALkCAAIABwklJBIuALkCAAAA.Dragussy:BAAALgAECgQJBAAAAA==.Drakenallure:BAABLgAECn8YAAQRAAgJFBXTCwDPAQARAAgJFBXTCwDPAQAfAAIJKAzmGwA4AAAgAAEJmQjGdQAlAAAAAA==.Drakkisath:BAABLgAECn8gAAMgAAcJDBV7KQBCAQAgAAcJ9xR7KQBCAQAfAAUJPxNqEAC9AAAAAA==.Draknethal:BAAALgAECgIJAgAAAA==.Dramn:BAAALgADCgMJAwAAAA==.Drango:BAABLgAECn8bAAIfAAkJeARECwAfAQAfAAkJeARECwAfAQAAAA==.Draugdae:BAABLgAECn8tAAIhAAgJnB+zBABxAgAhAAgJnB+zBABxAgAAAA==.Drayslinger:BAAALgAECgUJCgAAAA==.Dreki:BAAALgADCgYJCQABLgAECgIJAgAFAAAAAA==.Drinksomuch:BAAALgAECgEJAgAAAA==.Drlechee:BAAALgADCgMJBQAAAA==.Drob:BAEALgAECgUJBQAAAA==.Droze:BAAALgADCgkJCQAAAA==.Drukhi:BAABLgAECn8lAAIWAAgJFx69GgA3AgAWAAgJFx69GgA3AgAAAA==.Drunkalicius:BAACLgAFFH8FAAIOAAIJKQe9OgB1AAAOAAIJKQe9OgB1AAAuAAQKfxUAAg4ABwlwDKwrAB8BAA4ABwlwDKwrAB8BAAAA.',
Du='Dudepriest:BAABLgAECn8UAAMaAAgJrBk4EAAdAgAaAAgJrBk4EAAdAgASAAYJhwWKOwDNAAAAAA==.Dungrough:BAAALgAECggJEwAAAA==.Durtkal:BAABLgAECn85AAMIAAkJGRUJJQANAgAIAAkJGRUJJQANAgAHAAYJZw7lHwBTAQAAAA==.',
Dw='Dwarlin:BAAALgADCgkJCQAAAA==.',
Dy='Dyonn:BAAALgADCgkJEgAAAA==.',
['Dê']='Dêädpool:BAAALgADCgYJBgAAAA==.',
Ed='Edgeboy:BAAALgAECgYJCgABLgAFFAUJEwACADIXAA==.',
Ef='Efarel:BAABLgAECn8vAAINAAkJGxaWFwDkAQANAAkJGxaWFwDkAQAAAA==.Efil:BAAALgAECgMJBwAAAA==.',
El='Eleantha:BAAALgADCgYJBwAAAA==.Elinisar:BAAALgAECgUJBgAAAA==.Elsa:BAABLgAECn8oAAICAAgJ4w5FWwCLAQACAAgJ4w5FWwCLAQAAAA==.Elzza:BAAALgADCgYJCQAAAA==.',
Em='Embear:BAAALgADCgcJEAAAAA==.',
En='Eneco:BAAALgAECgEJAQAAAA==.Enjaydin:BAAALgAECgUJBQAAAA==.Enjaydo:BAABLgAECn8uAAICAAgJgR8LJgBCAgACAAgJgR8LJgBCAgAAAA==.',
Ep='Epicfurry:BAAALgAECgUJCwAAAA==.',
Er='Ereile:BAAALgAECgUJCAAAAA==.Errlhickey:BAAALgADCgUJCQAAAA==.',
Es='Escanor:BAAALgADCgYJBgAAAA==.',
Eu='Eukelade:BAAALgADCgcJBwABLgAECgkJMwAQALEeAA==.Eurythmics:BAABLgAECn8gAAIWAAcJWBWgTQBfAQAWAAcJWBWgTQBfAQAAAA==.',
Ev='Evileen:BAAALgAECgEJAQAAAA==.Evonahh:BAAALgADCgcJEwAAAA==.',
Ex='Exelion:BAABLgAECn8nAAIaAAgJ7B81DABYAgAaAAgJ7B81DABYAgAAAA==.Explogan:BAAALgAECgYJBwAAAA==.',
Ez='Ezanah:BAAALgADCgUJBQAAAA==.Ezrack:BAAALgAECgMJAwABLgAECggJGwAiAA0ZAA==.',
Fa='Faaith:BAAALgADCgUJBQAAAA==.Faeyrin:BAABLgAECn8nAAIZAAkJvBF6BgC/AQAZAAkJvBF6BgC/AQAAAA==.Fahooquazaad:BAAALgAECgQJCgAAAA==.Falconsg:BAAALgADCgQJBAAAAA==.Fancie:BAAALgADCgEJAQAAAA==.Fancy:BAABLgAECn8UAAIPAAkJgxcZGQAZAgAPAAkJgxcZGQAZAgAAAA==.Faythlis:BAABLgAECn8bAAIIAAcJBAvTcgAYAQAIAAcJBAvTcgAYAQAAAA==.',
Fe='Feetlesmcdee:BAABLgAECn8bAAITAAkJngbcbQBHAQATAAkJngbcbQBHAQAAAA==.Felf:BAAALgADCgcJBwAAAA==.Felfáádaern:BAEBLgAECn8iAAQjAAgJ2AzoGgA+AQAjAAgJ2AzoGgA+AQAUAAIJKgEX3wAzAAAkAAEJsAXdLQAoAAAAAA==.Felporch:BAAALgAECgcJEwAAAA==.',
Fi='Filburt:BAAALgADCgEJAQAAAA==.',
Fk='Fkton:BAAALgADCgIJAgAAAA==.',
Fl='Flamediso:BAAALgAECgIJAwAAAA==.Fledermaus:BAAALgADCgEJAQAAAA==.Flourchild:BAAALgADCgEJAQAAAA==.Flowermound:BAAALgAECgQJBwAAAA==.Flowerrose:BAAALgADCgYJBgAAAA==.',
Fo='Forrester:BAABLgAECn8WAAILAAYJvRlyIQBhAQALAAYJvRlyIQBhAQAAAA==.Fourqto:BAAALgAECgcJEgAAAA==.Fox:BAACLgAFFH8SAAMaAAYJSSMpAQA7AgAaAAYJSSMpAQA7AgASAAIJ9QatKQB+AAAuAAQKfxoAAhoACAkXHgkLAJ4CABoACAkXHgkLAJ4CAAAA.',
Fr='Franklee:BAAALgAECgYJCwAAAA==.Freight:BAAALgADCgMJAwAAAA==.Friedcry:BAAALgADCgYJBgAAAA==.Fron:BAAALgAECgYJEQAAAA==.Fronie:BAAALgADCgcJAwAAAA==.',
Fu='Fujikujaku:BAABLgAECn8dAAIKAAgJBxTZJgDSAQAKAAgJBxTZJgDSAQAAAA==.Fulmetal:BAAALgAECgQJBAAAAA==.Funerris:BAAALgADCgEJAQABLgAFFAcJCwAgAIEIAA==.Funiris:BAACLgAFFH8JAAIlAAUJSAhhBQB3AQAlAAUJSAhhBQB3AQAuAAQKfxUAAyUABwnsFesoAJMBACUABwnsFesoAJMBABIABQmKDiQyABABAAEuAAUUBwkLACAAgQgA.Funkalicious:BAACLgAFFH8NAAIYAAMJ+BCoHwDYAAAYAAMJ+BCoHwDYAAAuAAQKfzgAAhgACQlNIkEJAIQCABgACQlNIkEJAIQCAAAA.',
['Fé']='Félo:BAABLgAECn8wAAMHAAgJHyQiAgBhAgAHAAcJhiQiAgBhAgAIAAUJEiEAMgDRAQAAAA==.',
Ga='Gabaghoul:BAAALgAECgYJBgAAAA==.Garathor:BAAALgAECgEJAgAAAA==.Garthoneeye:BAAALgAECgUJEAAAAA==.Gazreyna:BAABLgAECn8hAAIXAAgJhSHpGABuAgAXAAgJhSHpGABuAgAAAA==.',
Gc='Gcarne:BAABLgAECn8lAAMKAAkJVg2LRwAoAQAKAAgJKwqLRwAoAQALAAMJ9gWQTgB5AAAAAA==.',
Ge='Genz:BAAALgADCgEJAQAAAA==.Genós:BAABLgAECn8oAAMNAAgJWRyaFAAAAgANAAgJehuaFAAAAgABAAgJ+BdpDQDEAQAAAA==.Gerardo:BAAALgAECgYJDgAAAA==.',
Gh='Ghurri:BAAALgAECgUJBgAAAA==.',
Gi='Gibs:BAAALgAECgYJDAAAAA==.Ginnee:BAAALgAECgMJBwAAAA==.Ginnion:BAABLgAECn8UAAIRAAcJTRcyEAB8AQARAAcJTRcyEAB8AQAAAA==.Girthytail:BAAALgAECgYJEQAAAA==.',
Gl='Glaedor:BAAALgAECgQJBAAAAA==.Glakenspheal:BAABLgAECn8kAAQSAAgJQhDVHgB6AQASAAcJChHVHgB6AQAaAAEJxQqhVwAyAAAlAAEJsQKsbwAUAAAAAA==.Glamorous:BAAALgAECgYJCwAAAA==.Glein:BAAALgAECgQJBAABLgAECgkJJgAPAJAhAA==.',
Go='Gongfu:BAAALgADCgYJBgAAAA==.Gooeycreampi:BAAALgADCgEJAQAAAA==.Goonie:BAAALgAECgYJCAAAAA==.',
Gr='Graestoke:BAACLgAFFH8JAAICAAMJABkCVAD9AAACAAMJABkCVAD9AAAuAAQKfxgAAgIACAnWH2o0AKECAAIACAnWH2o0AKECAAAA.Graevana:BAAALgADCgEJAQAAAA==.Gregorizz:BAAALgAECgEJBAAAAA==.Greyaura:BAAALgAECgQJBAAAAA==.Greybeast:BAAALgAECgYJDAAAAA==.Greyfoxy:BAAALgAECgYJDAAAAA==.Grianick:BAAALgAECgUJCgABLgAECggJGwAiAA0ZAA==.Grimixtalis:BAAALgAECgcJEQAAAA==.Growls:BAABLgAECn8sAAQLAAgJKSBZCQB1AgALAAgJKSBZCQB1AgAKAAgJ8xTjIwDlAQAhAAcJHhGQFAA6AQAAAA==.',
Gu='Gurri:BAAALgAECgQJBgAAAA==.',
Gy='Gyaat:BAAALgADCggJDwAAAA==.',
['Gõ']='Gõldenchild:BAABLgAECn8XAAIdAAcJVAj4PwDwAAAdAAcJVAj4PwDwAAAAAA==.',
['Gü']='Gürri:BAAALgAECgkJCAAAAA==.',
Ha='Habenero:BAABLgAECn8eAAImAAcJVQ3+EAArAQAmAAcJVQ3+EAArAQAAAA==.Hagar:BAABLgAECn8XAAIVAAcJDBNMEABMAQAVAAcJDBNMEABMAQAAAA==.Hairycow:BAAALgAECgMJAwAAAA==.Hairypitts:BAABLgAECn8fAAIVAAkJ8BZlBQBBAgAVAAkJ8BZlBQBBAgAAAA==.Haittou:BAAALgAECgkJBQAAAA==.Halligan:BAAALgAECgcJDQAAAA==.Hammertime:BAAALgAECggJEAAAAA==.Harabrew:BAAALgADCgkJFQAAAA==.Haraniantha:BAABLgAECn8WAAIOAAcJFSBgEQDvAQAOAAcJFSBgEQDvAQAAAA==.Hardø:BAAALgADCgcJCAAAAA==.Hatean:BAAALgAECgYJBgABLgAECgYJBwAFAAAAAA==.Hazzbek:BAAALgADCgUJBQAAAA==.',
He='Heiboss:BAAALgAECgQJBQABLgAECgkJJAAMAIgjAA==.Heibub:BAAALgAECgIJAgABLgAECgkJJAAMAIgjAA==.Heipal:BAAALgADCgYJBgABLgAECgkJJAAMAIgjAA==.Heiranir:BAAALgADCgYJEgABLgAECgkJJAAMAIgjAA==.Heiretic:BAAALgAECgQJBAABLgAECgkJJAAMAIgjAA==.Hellbane:BAAALgAECgQJCgAAAA==.Hemit:BAAALgAECgMJAwABLgAFFAMJCQACAAAZAA==.Hempknight:BAAALgADCgQJBQAAAA==.',
Hi='Hickups:BAAALgAECgYJCQABLgAECgkJNgAdAOgVAA==.Highestorder:BAAALgADCgYJBgAAAA==.Hikikomori:BAAALgAECggJDAABLgAECgkJMgAMAOAiAA==.Hinomiko:BAAALgAECgYJEQABLgAECgYJFwAEAHEJAA==.',
Ho='Holycowch:BAABLgAECn8gAAMTAAgJ2Bw5LAAHAgATAAgJhRo5LAAHAgAiAAYJ6BfcEwA3AQAAAA==.Honeyb:BAAALgAECgQJCwAAAA==.Hoodieallen:BAAALgADCgQJBAAAAA==.Hoofthor:BAAALgADCgEJAQAAAA==.Hootiedixon:BAAALgAECgYJEwAAAA==.',
Hu='Hughjaculate:BAAALgAECgkJEgAAAA==.Huran:BAABLgAECn8kAAMMAAkJiCPPBACmAgAMAAkJiCPPBACmAgAXAAIJsBM28QBYAAAAAA==.',
Id='Idcritthat:BAABLgAECn8eAAMcAAcJVxkTBwChAQAcAAcJVxkTBwChAQAbAAMJFA8yVgB2AAABLgAECggJHAAPAEgWAA==.',
Ig='Ignignokt:BAEBLgAECn8oAAMWAAkJ6COyDADaAgAWAAkJ6COyDADaAgADAAEJzhr3hwA0AAAAAA==.Igvoker:BAEALgAECgYJBgABLgAECgkJKAAWAOgjAA==.',
Il='Illadont:BAAALgADCgEJAQAAAA==.Illith:BAAALgADCgEJAgAAAA==.',
Im='Imagine:BAAALgAECgcJBgAAAA==.Imirohe:BAABLgAECn8VAAMCAAcJrgg0uwBrAQACAAcJrgg0uwBrAQAeAAEJoQOUIgAcAAAAAA==.',
In='Inarush:BAABLgAECn8xAAIkAAkJBwolCgBtAQAkAAkJBwolCgBtAQAAAA==.Inuyahshi:BAAALgAECgkJCQAAAA==.',
Ir='Ira:BAAALgADCgIJAgAAAA==.Ironfistt:BAAALgADCgYJBgAAAA==.Ironknife:BAAALgADCggJGAAAAA==.Ironshield:BAACLgAFFH8OAAIWAAQJNxm7EwBbAQAWAAQJNxm7EwBbAQAuAAQKfyQAAhYACQlnIJcFADMDABYACQlnIJcFADMDAAAA.',
Iv='Ivie:BAAALgAECgQJBgAAAA==.',
Iw='Iwishiknew:BAABLgAECn8oAAINAAgJoBiBFwDlAQANAAgJoBiBFwDlAQAAAA==.',
Iz='Iztras:BAAALgAECgMJCAAAAA==.Izuras:BAAALgAECgkJBwAAAA==.Izzit:BAAALgAECgQJCwAAAA==.',
Ja='Ja:BAABLgAECn8cAAICAAkJERhrMQARAgACAAkJERhrMQARAgAAAA==.Jabbtrak:BAABLgAECn8dAAIQAAgJFBUMGADjAQAQAAgJFBUMGADjAQAAAA==.Jabtrakk:BAAALgADCggJCAAAAA==.Jacklowry:BAAALgAECggJDwAAAA==.Jacodin:BAABLgAECn8eAAIdAAgJBhuWDgBjAgAdAAgJBhuWDgBjAgAAAA==.Jacquestrapp:BAAALgADCgkJDAAAAA==.Jakiepoobear:BAAALgAECgcJEAAAAA==.Jambie:BAABLgAECn8bAAQIAAgJ1hWpUgBlAQAIAAYJVxepUgBlAQAHAAIJUQzPUQB5AAAJAAEJywy2LwA/AAAAAA==.',
Je='Jedery:BAABLgAECn8mAAIiAAcJUhRPEQBXAQAiAAcJUhRPEQBXAQAAAA==.',
Jg='Jgglephysyx:BAAALgAECgkJCQAAAA==.',
Ji='Jianyü:BAABLgAECn8fAAITAAgJ2RwHJQCTAgATAAgJ2RwHJQCTAgAAAA==.Jimbæn:BAAALgADCgYJCAAAAA==.',
Jo='Jollyandy:BAEBLgAECn8dAAICAAgJ2Rb0QADXAQACAAgJ2Rb0QADXAQAAAA==.Jolynn:BAABLgAECn8wAAInAAkJOg+zDgD9AQAnAAkJOg+zDgD9AQAAAA==.Joroldess:BAABLgAECn8lAAIiAAgJjhpRCwC6AQAiAAgJjhpRCwC6AQAAAA==.',
Ju='Juzam:BAAALgAECgMJAwAAAA==.',
['Jü']='Jüggernaut:BAAALgAECgMJAwABLgAECggJOAAWAI4hAA==.',
Ka='Kaenara:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Kahndumb:BAABLgAECn8dAAINAAgJYBBHIgCRAQANAAgJYBBHIgCRAQAAAA==.Kaida:BAAALgAECgUJCQAAAA==.Kaio:BAAALgADCgMJAwAAAA==.Kalahan:BAABLgAECn8YAAImAAcJlRCfDwBDAQAmAAcJlRCfDwBDAQAAAA==.Kalimaa:BAAALgAECgYJDwAAAA==.Kaotut:BAAALgADCgQJBAAAAA==.Kappakappa:BAAALgAECgMJAwAAAA==.Kardrion:BAAALgAECgQJBgAAAA==.Karigyn:BAABLgAECn8vAAIcAAgJ1iKkAQCsAgAcAAgJ1iKkAQCsAgAAAA==.Karun:BAABLgAECn8tAAIZAAgJahUqBwCrAQAZAAgJahUqBwCrAQAAAA==.Kaskaa:BAAALgAECggJDwAAAA==.Kasok:BAAALgAECgYJDgAAAA==.Kasumi:BAAALgAECgkJEgABLgAECgkJPAAOAAQlAA==.Katren:BAAALgAECgEJAQAAAA==.Katrienne:BAABLgAECn8WAAIiAAYJdgUeKQDBAAAiAAYJdgUeKQDBAAAAAA==.Katrya:BAAALgADCgkJFQABLgAECgYJFgAiAHYFAA==.Katsfood:BAAALgADCgkJFQAAAA==.Kauzarukus:BAAALgAECgcJBwAAAA==.Kaylid:BAABLgAECn8jAAIoAAgJYhtmAwAaAgAoAAgJYhtmAwAaAgAAAA==.Kaylou:BAAALgADCgcJBwABLgAECggJMQATAI4KAA==.Kazeralana:BAAALgAECgUJBQAAAA==.Kazzoth:BAABLgAECn8oAAIWAAgJARK3PACYAQAWAAgJARK3PACYAQAAAA==.',
Ke='Keeiras:BAAALgAECgkJEAAAAA==.Keilen:BAAALgADCgUJBAAAAA==.Kelasha:BAABLgAECn8nAAIXAAgJVB4hNgDgAQAXAAgJVB4hNgDgAQAAAA==.',
Kh='Khadgär:BAAALgAECgYJDwAAAA==.Khalika:BAAALgAECgUJCgAAAA==.Kharanys:BAAALgADCgcJBwAAAA==.',
Ki='Kilroar:BAAALgADCgkJCQAAAA==.Kinoplex:BAAALgAECgYJCQABLgAFFAEJAQAFAAAAAA==.',
Kl='Klassiq:BAAALgADCgUJBQAAAA==.Klax:BAAALgADCgkJDwAAAA==.Klokateer:BAABLgAECn8cAAMcAAgJIBimBQAuAgAcAAgJ4BemBQAuAgAbAAUJ4w/bOgBCAQAAAA==.Klzx:BAABLgAECn8sAAICAAgJ9xYBQADaAQACAAgJ9xYBQADaAQAAAA==.',
Ko='Kobold:BAAALgAECgMJAwABLgAECgcJDAAFAAAAAA==.Komo:BAAALgADCgcJBwAAAA==.Komoou:BAAALgAECgQJBAAAAA==.Komouo:BAAALgADCgMJAwABLgADCgcJBwAFAAAAAA==.Korbi:BAAALgADCgcJGAABLgAECggJLgAYAHIVAA==.Kortek:BAABLgAECn8gAAIgAAgJvwMiPQDgAAAgAAgJvwMiPQDgAAAAAA==.Korvold:BAAALgAECggJEQAAAA==.Kosmos:BAAALgAECggJEgAAAA==.Kozath:BAAALgAECgYJEAAAAA==.',
Kr='Kreckon:BAAALgAECgcJDwAAAA==.Kriandor:BAAALgAECgEJAgAAAA==.',
Ks='Kschnell:BAAALgAECgEJAQABLgAFFAUJEwACADIXAA==.',
Ku='Kukulkan:BAACLgAFFH8GAAIRAAMJ0wdXGACuAAARAAMJ0wdXGACuAAAuAAQKfxsAAhEABwm6Dw8fAIgBABEABwm6Dw8fAIgBAAAA.Kuulan:BAABLgAECn8oAAITAAgJxRT4SQCgAQATAAgJxRT4SQCgAQAAAA==.',
La='Lacertidae:BAAALgADCgEJAQAAAA==.Larwock:BAABLgAECn8UAAMIAAUJOws2mQDLAAAIAAUJOws2mQDLAAAHAAQJSAbHSACUAAAAAA==.Lathorâ:BAAALgADCgkJDgABLgAECgYJEAAFAAAAAA==.Latwiz:BAAALgADCgYJCQABLgAECggJGgATABYeAA==.',
Le='Leancuisine:BAAALgAECgcJDgAAAA==.Leetlebug:BAAALgAECgYJEQAAAA==.Lettÿ:BAAALgAECgYJEAAAAA==.',
Li='Lightheaded:BAAALgAECgcJCQAAAA==.Lightzwrath:BAAALgAECggJEgAAAA==.Linadra:BAAALgAECgQJBAAAAA==.Liquid:BAABLgAECn8ZAAIbAAcJiyT6CABKAgAbAAcJiyT6CABKAgAAAA==.',
Lo='Loankano:BAABLgAECn8bAAIbAAgJbAouGgBsAQAbAAgJbAouGgBsAQAAAA==.Lockbealady:BAABLgAECn8WAAMIAAgJIgu1YwA5AQAIAAgJIgu1YwA5AQAHAAEJFgYAeQAqAAAAAA==.Lohanoa:BAAALgAECgEJAQAAAA==.Longshanke:BAAALgAECgEJAQAAAA==.Lorebeard:BAAALgAECgYJCQAAAA==.Loreix:BAAALgAECgYJDQAAAA==.Lothlórien:BAAALgADCgcJCAAAAA==.Lozzo:BAAALgADCgYJCwAAAA==.',
Lr='Lrock:BAAALgADCgMJAgAAAA==.',
Lu='Luciferluxx:BAAALgADCgQJBgAAAA==.Lumena:BAAALgADCggJCAAAAA==.Luminai:BAABLgAECn8YAAIaAAgJmBrAEQBUAgAaAAgJmBrAEQBUAgAAAA==.Luminaris:BAAALgAECgEJAQAAAA==.Luminaugty:BAAALgADCgcJEwAAAA==.Lunalea:BAAALgADCgQJBAAAAA==.Lunarthas:BAAALgADCgkJEQAAAA==.Luvinez:BAAALgAECgEJBAAAAA==.Luvinz:BAAALgAECgYJDAAAAA==.Luxkilla:BAAALgADCgEJAQAAAA==.',
Ly='Lyllia:BAAALgADCgEJAQAAAA==.Lynchmeup:BAAALgADCgYJBgABLgAECgcJIgAUAPQcAA==.Lyrel:BAABLgAECn8rAAIUAAkJ5iKEBAAVAwAUAAkJ5iKEBAAVAwAAAA==.Lyshara:BAAALgADCgEJAQAAAA==.',
['Lî']='Lîllîth:BAAALgADCgMJAwAAAA==.',
['Lü']='Lümen:BAAALgADCggJCAABLgADCggJCAAFAAAAAA==.',
Ma='Maarc:BAABLgAECn8hAAIWAAcJng8ZTwBaAQAWAAcJng8ZTwBaAQAAAA==.Maddragon:BAAALgAECgMJAwAAAA==.Madfurion:BAAALgAECgQJBwAAAA==.Magebot:BAABLgAECn8hAAICAAgJZAkqcgBWAQACAAgJZAkqcgBWAQAAAA==.Maggotbag:BAAALgAECgQJBAAAAA==.Magistra:BAAALgADCgcJDwAAAA==.Majestic:BAACLgAFFH8TAAICAAUJMhdHNABPAQACAAUJMhdHNABPAQAuAAQKfygAAgIACQmxHl4nANUCAAIACQmxHl4nANUCAAAA.Malizar:BAAALgADCgEJAQAAAA==.Malvenue:BAAALgAECgkJAgAAAA==.Malygor:BAAALgAECgUJBwAAAA==.Marly:BAAALgAECgYJDQAAAA==.Mauwy:BAABLgAECn8eAAMYAAkJbxM9HwAWAgAYAAkJbxM9HwAWAgAGAAMJGQ25hgBVAAAAAA==.Mayabutreeks:BAAALgAECgYJBwAAAA==.Mazzerine:BAAALgAECgQJBAAAAA==.',
Mc='Mcbeardface:BAABLgAECn8WAAMSAAcJ/hXiGwC3AQASAAcJ/hXiGwC3AQAlAAEJAADnXABAAAAAAA==.Mcbullseye:BAAALgAECgUJBAAAAA==.',
Me='Meathole:BAAALgAECgMJBAAAAA==.Megarah:BAAALgAECgQJBgAAAA==.Mental:BAAALgAECgEJAQAAAA==.Mepkaelpto:BAAALgAFFAQJBAABLgAFFAUJCgACAHoSAA==.Mera:BAAALgADCgcJCAAAAA==.Mercury:BAABLgAECn8XAAIGAAcJJRgnJADeAQAGAAcJJRgnJADeAQAAAA==.Meretrix:BAABLgAECn8cAAITAAgJYgdjewAsAQATAAgJYgdjewAsAQAAAA==.Messatsu:BAAALgAECgcJEgAAAA==.Metanya:BAABLgAECn8WAAMVAAcJkgpKFAAWAQAVAAcJkgpKFAAWAQALAAMJHgPobwBfAAAAAA==.Mew:BAAALgAECgYJCgAAAA==.',
Mi='Miateh:BAAALgAECgYJCgAAAA==.Microdots:BAAALgADCgMJAwAAAA==.Midorí:BAAALgADCgYJBgAAAA==.Mimicme:BAABLgAECn8XAAIWAAgJkR37GABEAgAWAAgJkR37GABEAgAAAA==.Minorie:BAAALgADCgIJAgAAAA==.Mitchell:BAABLgAECn8mAAITAAgJxg7VXQBsAQATAAgJxg7VXQBsAQAAAA==.Miwah:BAABLgAECn8UAAICAAYJ1gNhwQDGAAACAAYJ1gNhwQDGAAAAAA==.',
Mj='Mjolnìr:BAAALgAECgMJDAAAAA==.',
Mo='Modeus:BAAALgADCgUJBgAAAA==.Modin:BAABLgAECn8bAAMiAAgJDRkuCwC9AQAiAAgJDRkuCwC9AQATAAQJ3QNi2gCOAAAAAA==.Mogarr:BAABLgAECn8YAAMBAAgJbQ0eHABpAQABAAgJbQ0eHABpAQAEAAEJtA+ZTwAxAAAAAA==.Mohgwyn:BAAALgADCgEJAQAAAA==.Momonk:BAAALgADCgcJBwABLgAECggJGwAiAA0ZAA==.Monkglein:BAABLgAECn8mAAMPAAkJkCHcBwCEAgAPAAgJUyHcBwCEAgAQAAMJBQftWABoAAAAAA==.Monkhei:BAAALgAECgQJBAABLgAECgkJJAAMAIgjAA==.Mooglewing:BAABLgAECn8UAAIcAAcJ/RWJBwCTAQAcAAcJ/RWJBwCTAQAAAA==.Moomoobrncow:BAABLgAECn8WAAIWAAcJpRW5RAB7AQAWAAcJpRW5RAB7AQAAAA==.Moondream:BAABLgAECn8tAAMWAAgJjRw4HwAcAgAWAAgJjRw4HwAcAgADAAIJLgi4ewBVAAAAAA==.Moraz:BAAALgAECgQJBwAAAA==.Mordicanta:BAABLgAECn8wAAIMAAkJiRcKCwAKAgAMAAkJiRcKCwAKAgAAAA==.Morphies:BAAALgADCgcJDQAAAA==.',
Mu='Muerr:BAABLgAECn8jAAIWAAkJ+iEzDgCZAgAWAAkJ+iEzDgCZAgAAAA==.Muerrizond:BAAALgAECgUJDgABLgAECgkJIwAWAPohAA==.Muerrlin:BAABLgAECn8VAAICAAYJHw2mkgAZAQACAAYJHw2mkgAZAQABLgAECgkJIwAWAPohAA==.Muggel:BAAALgADCgkJKwAAAA==.Muggruith:BAAALgADCgkJDwAAAA==.Mumraa:BAAALgAECgMJAwAAAA==.Mumrawr:BAAALgADCgcJCwAAAA==.Mushroohead:BAABLgAECn8fAAIYAAgJKhv+EQAOAgAYAAgJKhv+EQAOAgAAAA==.',
My='Mystbourn:BAAALgAECgEJAQAAAA==.Mysterbyrnes:BAAALgADCgYJEgAAAA==.Myykiel:BAABLgAECn8mAAQkAAcJhxhhEwAcAQAkAAYJUQxhEwAcAQAUAAUJrBkRYAAXAQAjAAQJ+xqLJQDlAAAAAA==.',
Na='Naina:BAABLgAECn8tAAMGAAgJYhjJGgAeAgAGAAgJYhjJGgAeAgAYAAUJIwwNQADaAAAAAA==.Najaja:BAAALgAECgQJBAAAAA==.Nakona:BAAALgADCgcJBwABLgAECggJHAAUAI4FAA==.Nalera:BAAALgADCgEJAQABLgAECgkJPAAOAAQlAA==.Nariely:BAAALgAECgYJCgAAAA==.Natacha:BAAALgAECgYJCwAAAA==.Native:BAAALgAECgUJCAAAAA==.Nayos:BAAALgADCgIJAgAAAA==.',
Ne='Necro:BAABLgAECn8yAAIMAAkJ4CIlAwDcAgAMAAkJ4CIlAwDcAgAAAA==.Neelothe:BAAALgAECgMJAwAAAA==.Neisa:BAAALgADCgIJAgAAAA==.Nekroz:BAAALgAECgEJAQAAAA==.Nelliel:BAAALgAECgcJEwAAAA==.Nephie:BAAALgAECgMJAwABLgAECgkJIQAjAM8cAA==.',
Ni='Nickodemus:BAAALgAECgIJAgAAAA==.Nienor:BAAALgADCgkJCQAAAA==.Nightle:BAAALgADCggJCwAAAA==.Nihil:BAABLgAECn8UAAIkAAcJ6xLBDQAfAQAkAAcJ6xLBDQAfAQABLgAECgkJMgAMAOAiAA==.Nikano:BAAALgADCgYJBgAAAA==.Ninmah:BAAALgADCgkJPAAAAA==.Niphredil:BAAALgAECgEJAQAAAA==.Nirø:BAABLgAECn8dAAIPAAkJLQqbIABVAQAPAAkJLQqbIABVAQAAAA==.',
No='Noah:BAAALgADCgcJDQAAAA==.Nooky:BAABLgAECn8oAAIQAAgJrB9uCQCiAgAQAAgJrB9uCQCiAgAAAA==.',
Nu='Nuatha:BAAALgAECgYJEQAAAA==.Numpty:BAAALgAECgMJBgAAAA==.',
Ny='Nyctero:BAABLgAECn8eAAImAAgJlR8vBQA/AgAmAAgJlR8vBQA/AgAAAA==.Nyrikah:BAAALgADCgcJBwAAAA==.',
['Nö']='Nöstrum:BAAALgADCgMJAwABLgAECgcJDAAFAAAAAA==.',
Ob='Obidiah:BAABLgAECn8tAAMCAAgJNho0OwDrAQACAAgJNho0OwDrAQAeAAEJThKYGgBDAAAAAA==.',
Oc='Ocnod:BAAALgAECgMJAwAAAA==.',
Oe='Oedipus:BAAALgAECgMJAwAAAA==.',
Oh='Ohioaug:BAAALgADCgEJAQAAAA==.',
Or='Orah:BAABLgAECn8eAAILAAcJiQ/BKAAvAQALAAcJiQ/BKAAvAQAAAA==.Orpheon:BAAALgAECgQJCQAAAA==.',
Os='Osorn:BAAALgADCgkJCgAAAA==.',
Ot='Otterdoodad:BAAALgAECgQJBAAAAA==.',
Ou='Ouicau:BAAALgAECgcJBwAAAA==.',
Oz='Ozzmosis:BAAALgADCgMJAwAAAA==.',
Pa='Palagem:BAAALgADCgYJBgAAAA==.Palinyes:BAABLgAECn8jAAIiAAgJNSXSAQDiAgAiAAgJNSXSAQDiAgAAAA==.Pancetta:BAAALgADCgUJCAAAAA==.Pandabits:BAAALgAECgUJBQAAAA==.Pandussy:BAAALgAECgEJAQAAAA==.Papabill:BAABLgAECn8yAAITAAgJshPnVwB6AQATAAgJshPnVwB6AQAAAA==.Paperscissor:BAAALgADCgIJAgAAAA==.Paragorn:BAABLgAECn8mAAITAAgJfgl0cwA7AQATAAgJfgl0cwA7AQAAAA==.Pasiphae:BAAALgADCgIJAgABLgAECgkJMwAQALEeAA==.Pattee:BAABLgAECn8jAAIDAAcJ6iLIAwBHAgADAAcJ6iLIAwBHAgAAAA==.',
Pe='Peachums:BAAALgADCgEJAQAAAA==.Pech:BAAALgAFFAEJAQAAAA==.Peenidin:BAABLgAECn8oAAIdAAgJfCOjCwCLAgAdAAgJfCOjCwCLAgAAAA==.Pemerd:BAABLgAECn8hAAILAAcJjBtAFgDGAQALAAcJjBtAFgDGAQAAAA==.Petite:BAAALgADCgMJAwAAAA==.',
Ph='Phoenixfires:BAAALgADCgYJCAAAAA==.Phoze:BAABLgAECn8gAAIiAAgJOBZVDACpAQAiAAgJOBZVDACpAQAAAA==.Phyai:BAABLgAECn8cAAICAAcJPxPwbABiAQACAAcJPxPwbABiAQAAAA==.',
Pi='Pirotanaxdos:BAABLgAECn8XAAIfAAcJfgObEAC5AAAfAAcJfgObEAC5AAAAAA==.Pizzarollzz:BAABLgAECn8jAAIWAAgJ+A5CQgCDAQAWAAgJ+A5CQgCDAQAAAA==.',
Pn='Pnutt:BAAALgAECgQJBAAAAA==.',
Po='Pocco:BAAALgAECgEJAQAAAA==.Ponymalta:BAABLgAECn8lAAILAAgJ5xdRGwApAgALAAgJ5xdRGwApAgAAAA==.Popeaganda:BAAALgAECgQJBwAAAA==.Poutine:BAAALgAECgQJCwAAAA==.',
Pr='Prizren:BAAALgAECgYJDQAAAA==.Promethyus:BAABLgAECn8eAAMTAAgJNQZUuwC+AAATAAgJNQZUuwC+AAAiAAUJwAEIMgBRAAAAAA==.Promidan:BAAALgAECgcJBwABLgAFFAQJDwATAOUOAA==.Pryxi:BAABLgAECn8nAAICAAgJ/QdtfABCAQACAAgJ/QdtfABCAQAAAA==.',
Pu='Puffichu:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Punchline:BAAALgADCgcJBwAAAA==.',
Py='Pyrogar:BAAALgADCgIJAgAAAA==.Pythius:BAAALgAECgYJBwAAAA==.',
['Pó']='Pótatò:BAAALgAECgYJEAAAAA==.',
Qi='Qiara:BAAALgAECgcJBwAAAA==.',
Qu='Quandaale:BAABLgAECn8WAAMKAAcJuhPfSAAjAQAKAAYJMxTfSAAjAQAhAAUJNxfmGAAKAQABLgAFFAEJAQAFAAAAAA==.Quell:BAAALgADCgEJAQAAAA==.Quepinga:BAAALgADCgUJCAAAAA==.Quiksylver:BAABLgAECn8yAAMdAAgJGRmsIQCrAQAdAAgJGRmsIQCrAQATAAYJyhFZaABTAQAAAA==.',
Ra='Rabblerousin:BAAALgAECgEJAgAAAA==.Raegnar:BAAALgADCgYJBgAAAA==.Raggnnar:BAAALgADCgEJAgAAAA==.Rainmakers:BAAALgAECgcJBQAAAA==.Rakael:BAAALgADCgMJAwAAAA==.Rava:BAAALgAECgEJAQAAAA==.',
Re='Rea:BAAALgAECgQJBAAAAA==.Reckoner:BAAALgAECgUJEAAAAA==.Red:BAABLgAECn84AAQXAAkJ2SP9DQDBAgAXAAkJkSL9DQDBAgAZAAcJZCP5BQDQAQAMAAcJzRNcFgBeAQAAAA==.Rellster:BAAALgAECgUJCgAAAA==.Renix:BAAALgAECgQJBQAAAA==.Rennyo:BAABLgAECn8lAAMPAAgJAxk7GgCOAQAOAAgJVBNFKgC4AQAPAAYJfhw7GgCOAQAAAA==.Resonance:BAAALgAECgUJBwAAAA==.Retsu:BAAALgADCgUJBQAAAA==.Rettbull:BAAALgADCgMJAwAAAA==.Reyujin:BAAALgAECgEJBAAAAA==.',
Rh='Rhyash:BAABLgAECn8VAAIaAAYJ+gbNNQDfAAAaAAYJ+gbNNQDfAAAAAA==.',
Ri='Riaana:BAAALgADCgEJAQAAAA==.Rickdaddty:BAAALgADCgkJCQABLgAECgcJGgAIABMeAA==.Ricoz:BAAALgAECgQJBQAAAA==.Ridicutie:BAABLgAECn8aAAIhAAcJJiCLBwAZAgAhAAcJJiCLBwAZAgAAAA==.Rigg:BAABLgAECn8iAAIUAAcJ9BxPKgDXAQAUAAcJ9BxPKgDXAQAAAA==.Riggz:BAAALgADCgQJBAABLgAECgcJIgAUAPQcAA==.Rivetro:BAAALgAECgQJCwAAAA==.',
Ro='Rocknroll:BAABLgAECn83AAIWAAkJkBoREwCeAgAWAAkJkBoREwCeAgAAAA==.Roll:BAACLgAFFH8FAAIiAAIJORvKCACXAAAiAAIJORvKCACXAAAuAAQKfyoAAiIACAnEIMQFAEUCACIACAnEIMQFAEUCAAAA.Rozgrez:BAABLgAECn8nAAQIAAkJhxxSJgAHAgAIAAkJ5hVSJgAHAgAJAAQJXhqXDQASAQAHAAUJyBUoEADxAAAAAA==.',
Ru='Rufus:BAAALgADCgkJDgAAAA==.Rumlidorgah:BAABLgAECn8fAAQJAAgJ6AtQDQAXAQAIAAgJVwkIXgBHAQAJAAYJWQpQDQAXAQAHAAQJVQ0tHACIAAAAAA==.Runem:BAAALgAECgIJAwAAAA==.Russbus:BAABLgAECn8fAAMTAAkJHg7ZRACvAQATAAkJHg7ZRACvAQAdAAgJEQf9XAAJAQAAAA==.Ruune:BAAALgAECgUJBwAAAA==.',
Ry='Rynmorelle:BAAALgAECgEJAgAAAA==.',
['Ré']='Réven:BAABLgAECn8iAAIUAAgJIRwTIQAJAgAUAAgJIRwTIQAJAgAAAA==.',
Sa='Sadiebella:BAAALgAECgYJCAAAAA==.Sadienna:BAABLgAECn8eAAMlAAkJhQYQJABSAQAlAAkJhQYQJABSAQAaAAgJXQWsRgAfAQAAAA==.Salvidali:BAAALgAECgIJAgABLgAECggJHQACABsHAA==.Sandrï:BAABLgAECn8hAAQJAAgJjxH5CABqAQAJAAYJmRL5CABqAQAIAAcJqA6wXgBFAQAHAAEJAADvPgAAAAAAAA==.Sane:BAABLgAECn8cAAIXAAkJzhRRNwDbAQAXAAkJzhRRNwDbAQAAAA==.Saoiirse:BAABLgAECn8hAAMUAAcJ4Rc2QAB6AQAUAAcJ4Rc2QAB6AQAjAAIJ1hMZOAByAAAAAA==.Saraella:BAAALgAECggJAgAAAA==.Sasso:BAAALgADCgIJAgAAAA==.Sawako:BAABLgAECn8mAAIlAAkJLhnACgBZAgAlAAkJLhnACgBZAgAAAA==.',
Sc='Scalar:BAAALgADCgEJAQAAAA==.Scalyboi:BAAALgADCgMJAwABLgAFFAUJEwACADIXAA==.Scalycrit:BAAALgAECgQJBQABLgAECggJHAAPAEgWAA==.Scarletts:BAAALgADCgUJBgABLgAECgUJBQAFAAAAAA==.Schlitzie:BAAALgADCgIJAgAAAA==.Scrapes:BAAALgADCgMJAwAAAA==.Scuba:BAAALgAECgYJCwAAAA==.',
Se='Seraphyne:BAAALgAECgIJAgABLgAFFAQJCAAQADkMAA==.Sevencharlie:BAABLgAECn8ZAAITAAcJwQgjigAQAQATAAcJwQgjigAQAQAAAA==.',
Sh='Shadowho:BAAALgAECgQJCgAAAA==.Shadowrican:BAAALgAECgMJAwAAAA==.Shaladro:BAAALgADCgUJCAAAAA==.Shalanaz:BAAALgAECgEJAQAAAA==.Shamiqua:BAAALgAECgUJBQAAAA==.Shamutty:BAAALgAECgMJBAABLgAFFAMJCQACAAAZAA==.Sharasdal:BAAALgAECgEJAQABLgAECggJAgAFAAAAAA==.Sherief:BAAALgADCgQJBAAAAA==.Shieldz:BAAALgAECgEJAQAAAA==.Shinjô:BAAALgAECgQJCwAAAA==.Shiroishi:BAAALgADCgcJBwABLgAECgcJHgARAHwGAA==.Shivaray:BAAALgADCgUJBQAAAA==.Shiveria:BAAALgADCgYJCwAAAA==.Shocklesner:BAAALgAECggJEwAAAA==.Shorkaan:BAAALgAECgEJAQAAAA==.Shouganai:BAABLgAECn8UAAIWAAcJYhHXUQBSAQAWAAcJYhHXUQBSAQAAAA==.Shupaz:BAAALgAECgUJBgAAAA==.',
Si='Siddha:BAAALgADCgYJBgABLgAECgYJDwAFAAAAAA==.Sieria:BAAALgAECgYJDQAAAA==.Sifu:BAAALgAECgcJCwAAAA==.Siieerr:BAABLgAFFH8JAAIVAAQJdBmrAgBxAQAVAAQJdBmrAgBxAQAAAA==.Silvermind:BAAALgAECgcJEwAAAA==.Sinaar:BAAALgAECgIJAwAAAA==.Sindena:BAACLgAFFH8FAAIIAAMJXQfqbwCXAAAIAAMJXQfqbwCXAAAuAAQKfxsAAggABwk9FK1cALIBAAgABwk9FK1cALIBAAAA.Sixsanity:BAAALgAECgQJCgAAAA==.',
Sk='Skavos:BAAALgAECgYJBwAAAA==.Skillcommand:BAAALgAECgQJCgAAAA==.Skipperino:BAAALgADCggJDQAAAA==.Skyemage:BAAALgAECgEJAgAAAA==.',
Sl='Sloked:BAAALgADCgEJAQAAAA==.Slokem:BAAALgAECgIJAgAAAA==.Slotz:BAABLgAECn8uAAIdAAcJghtgLQDPAQAdAAcJghtgLQDPAQAAAA==.',
Sm='Smallcoomer:BAAALgAECggJDwAAAA==.Smallss:BAAALgAECgUJBgAAAA==.Smike:BAABLgAECn8xAAITAAgJjgrkbwBDAQATAAgJjgrkbwBDAQAAAA==.',
Sn='Snappie:BAAALgAECgUJBQAAAA==.Sneeze:BAAALgAECgQJBgAAAA==.Snek:BAAALgAECgEJAQAAAA==.Snuggles:BAAALgADCgUJBwAAAA==.',
So='Soferan:BAABLgAECn8bAAIXAAYJjhxDbABDAQAXAAYJjhxDbABDAQAAAA==.Softpaws:BAAALgAECgEJAQAAAA==.Sonarr:BAAALgAECgUJCQAAAA==.Sosukeaizen:BAAALgAECgEJAQAAAA==.Sourdeizal:BAAALgADCgEJAQAAAA==.',
Sp='Spacemilk:BAABLgAECn8UAAMSAAkJNwlUMQAWAQASAAYJdAZUMQAWAQAlAAQJNQYQQwCpAAAAAA==.Spark:BAAALgAECgEJAQAAAA==.Spicymeat:BAAALgAECgIJAgABLgAFFAUJEwACADIXAA==.Sputty:BAAALgAECgYJEwABLgAFFAMJCQACAAAZAA==.',
Sq='Squishee:BAAALgAECgcJDQAAAA==.',
St='Stankmouth:BAABLgAECn8ZAAIQAAQJwwUHWABrAAAQAAQJwwUHWABrAAAAAA==.Stellas:BAAALgADCgUJCAABLgAECgkJEgAFAAAAAA==.Stesha:BAAALgAECgUJBQABLgAECggJHAAUAI4FAA==.Steviewonder:BAABLgAECn8fAAIUAAcJihUnTABSAQAUAAcJihUnTABSAQAAAA==.Stinkerton:BAABLgAFFH8HAAISAAQJQCECDwCLAQASAAQJQCECDwCLAQAAAA==.Stonedfrog:BAAALgADCgcJBwAAAA==.Stonefather:BAABLgAECn8kAAIQAAgJeQyMLgAxAQAQAAgJeQyMLgAxAQAAAA==.Stonewall:BAAALgADCgEJAgAAAA==.Strangelets:BAAALgAECgQJBQAAAA==.Strangewayes:BAAALgADCgMJAwAAAA==.Stïtches:BAABLgAECn8XAAMXAAcJWAmMngDiAAAXAAYJ3wqMngDiAAAMAAYJ7ANvMACLAAAAAA==.Stönk:BAABLgAECn8fAAIHAAgJpBShBwCIAQAHAAgJpBShBwCIAQAAAA==.',
Su='Succulentman:BAACLgAFFH8FAAIUAAIJPSTqQwDQAAAUAAIJPSTqQwDQAAAuAAQKfy4AAhQACAkcI7kRAHQCABQACAkcI7kRAHQCAAAA.Sufferyn:BAAALgADCgcJBwAAAA==.Sunreaver:BAAALgADCgYJCgAAAA==.Supoz:BAAALgAECgEJAQAAAA==.Surolath:BAABLgAECn8xAAIhAAkJpx7lAgC7AgAhAAkJpx7lAgC7AgAAAA==.Suvaun:BAAALgAECgEJAQAAAA==.',
Sw='Swaggles:BAABLgAECn8wAAInAAkJeCN0AQAdAwAnAAkJeCN0AQAdAwAAAA==.Swatguymg:BAAALgADCgQJBAAAAA==.Swiftcast:BAAALgAECgYJBgAAAA==.Swiftpalms:BAAALgAECgYJBgAAAA==.Swompfox:BAAALgAECggJEwAAAA==.',
Sy='Sygon:BAABLgAECn8vAAIDAAkJxxidBAAjAgADAAkJxxidBAAjAgAAAA==.Sylenceikilu:BAAALgADCgEJAQAAAA==.Sylvannaa:BAAALgAECgYJBwAAAA==.Syntherizena:BAAALgAECgYJCQAAAA==.Synthesized:BAAALgAECgcJEgAAAA==.',
['Só']='Sóng:BAABLgAECn8aAAMaAAcJLh3eEwBAAgAaAAcJLh3eEwBAAgAlAAEJSQ7wXgA7AAAAAA==.',
Ta='Tacitus:BAABLgAECn8gAAINAAgJkRPnHwChAQANAAgJkRPnHwChAQAAAA==.Tairrad:BAAALgAECgYJCAAAAA==.Takeru:BAAALgAECgMJBQAAAA==.Talasmar:BAAALgAECgEJAQAAAA==.Tapkora:BAAALgAECgQJCAAAAA==.Tapsum:BAAALgADCgUJBQAAAA==.Tarirn:BAAALgADCgEJAQAAAA==.Taurtem:BAAALgAECgQJBQAAAA==.Taylia:BAAALgAECgQJDAABLgAECgkJGgASAFMSAA==.Tayona:BAAALgAECgIJAgAAAA==.Tazildek:BAAALgAECgEJAQAAAA==.',
Te='Technique:BAAALgAECggJEwAAAA==.Tergrid:BAAALgAECgMJAwAAAA==.Terial:BAABLgAECn8qAAIdAAgJySInBwDYAgAdAAgJySInBwDYAgAAAA==.Textoffender:BAAALgAECgQJBgAAAA==.',
Th='Thajeebus:BAAALgADCgEJAQAAAA==.Thatsneat:BAAALgAECgQJBQAAAA==.Thecapt:BAABLgAECn8nAAINAAkJFhv1DgA9AgANAAkJFhv1DgA9AgAAAA==.Theôdöræ:BAABLgAECn8XAAIjAAgJTAyPGQBMAQAjAAgJTAyPGQBMAQAAAA==.Thorinfel:BAABLgAECn8hAAIUAAkJ1xR7NgAdAgAUAAkJ1xR7NgAdAgAAAA==.Thsaemage:BAAALgAECgQJBAABLgAECgkJKgALAGodAA==.Thunderkiss:BAAALgAECgYJBgAAAA==.Thunran:BAAALgAECgQJBgAAAA==.',
Ti='Tiaoma:BAAALgAECgEJAQAAAA==.Tieria:BAABLgAECn8jAAIlAAgJISDVCQBoAgAlAAgJISDVCQBoAgAAAA==.Tikao:BAABLgAECn8yAAMkAAgJ8g9EDgAWAQAkAAgJ8g9EDgAWAQAjAAYJpAVlQwDqAAABLgAECgkJAQAFAAAAAA==.Tinna:BAAALgAECgcJBgAAAA==.',
Tj='Tjhookèr:BAAALgAECgYJEgAAAA==.',
To='Tobajal:BAABLgAECn8wAAIaAAkJLSGDAgBFAwAaAAkJLSGDAgBFAwAAAA==.Toletheus:BAABLgAECn8jAAQVAAkJZxg5DACVAQALAAgJBhPHGACtAQAVAAcJZxc5DACVAQAhAAEJzSWYLgBrAAAAAA==.Tomin:BAABLgAECn8eAAITAAgJOCTzCwDRAgATAAgJOCTzCwDRAgAAAA==.Totemique:BAAALgADCgcJDgABLgAECggJEwAFAAAAAA==.Totumfknpole:BAAALgADCgEJAQAAAA==.',
Tr='Treeperson:BAABLgAECn8jAAIKAAgJmSL+BwD8AgAKAAgJmSL+BwD8AgAAAA==.Treyni:BAAALgADCgIJAgAAAA==.Trickyric:BAAALgAECgUJCwAAAA==.Trilgy:BAAALgADCgkJCgAAAA==.Trowel:BAABLgAECn8cAAILAAcJlx+bGQA6AgALAAcJlx+bGQA6AgABLgAFFAMJCQACAAAZAA==.',
Ts='Tsuyoimono:BAABLgAECn8XAAMEAAYJcQmdJgDWAAAEAAYJcQmdJgDWAAANAAQJxATqgwCvAAAAAA==.',
Tu='Tubkins:BAAALgADCgkJCQAAAA==.Turisx:BAAALgADCgQJBQAAAA==.Turtleclap:BAAALgAECgQJBAAAAA==.',
Tw='Twiddydh:BAAALgAECgYJEAAAAA==.Twylan:BAAALgAECgEJAQAAAA==.',
Ty='Tydroin:BAAALgADCgMJAwAAAA==.Tytoalba:BAAALgAFFAIJAwAAAA==.',
Uk='Ukiru:BAAALgADCgMJAwAAAA==.',
Ul='Ulfarr:BAAALgAECgcJBwAAAA==.',
Un='Ungonelilith:BAAALgADCgkJGAAAAA==.Unicrom:BAAALgAECgkJCQAAAA==.',
Ur='Uratsukasama:BAAALgAECgYJDAAAAA==.Urion:BAABLgAECn8ZAAQnAAcJHR1SFAC6AQAnAAcJfxtSFAC6AQAWAAMJsh/PlwCmAAADAAEJ7Q4piQAyAAAAAA==.',
Va='Vacaite:BAAALgAECgIJAwAAAA==.Vagiant:BAABLgAECn8cAAIVAAcJaRToEgAoAQAVAAcJaRToEgAoAQAAAA==.Valyna:BAAALgADCgEJAQAAAA==.Vampirica:BAAALgAECgkJBgAAAA==.Vanya:BAABLgAECn8iAAMWAAcJ6SL/GgA2AgAWAAcJ0iL/GgA2AgAnAAYJfxiiDgDdAQAAAA==.Vash:BAAALgADCgYJBgABLgAECgkJEgAFAAAAAA==.Vasso:BAAALgAECgQJBgAAAA==.',
Ve='Velinae:BAAALgAECgkJBgAAAA==.Velint:BAAALgAECgEJAQAAAA==.Velveen:BAABLgAECn8uAAMYAAgJchXyHACkAQAYAAgJchXyHACkAQAGAAEJtQczmAA0AAAAAA==.Vexxia:BAAALgAECggJCQAAAA==.',
Vi='Viallure:BAAALgAECgcJDQABLgAECgkJGAARABQVAA==.Vilebloom:BAEBLgAECn8lAAIKAAcJkSH8DgCcAgAKAAcJkSH8DgCcAgAAAA==.Viridius:BAAALgAECgUJDQAAAA==.Vitamind:BAAALgADCgEJAQAAAA==.',
Vo='Voluga:BAAALgAECgEJAQAAAA==.Vonmortis:BAAALgADCgkJFwAAAA==.',
Wa='Wagguslight:BAABLgAECn8pAAITAAcJVREpZABcAQATAAcJVREpZABcAQAAAA==.Warzak:BAABLgAECn8UAAINAAcJqxYKJQB/AQANAAcJqxYKJQB/AQAAAA==.Wayne:BAAALgADCgUJBQAAAA==.',
We='Wendybacon:BAABLgAECn8YAAIUAAYJmhU+bABeAQAUAAYJmhU+bABeAQAAAA==.',
Wh='Whateverdude:BAAALgAECgQJCAAAAA==.Whiskeyshots:BAAALgADCgIJAgAAAA==.Whytè:BAABLgAECn8tAAIKAAgJ/SJgBwAHAwAKAAgJ/SJgBwAHAwAAAA==.',
Wi='Wigeon:BAAALgADCggJCAABLgAECggJGwAiADMVAA==.Wiickett:BAABLgAECn8fAAMfAAgJtB2/BAC5AgAfAAgJcx2/BAC5AgAgAAYJrh+UIwChAQAAAA==.Wilbur:BAAALgAECgQJCAAAAA==.Wildebeard:BAACLgAFFH8MAAIdAAQJSSRXCwCbAQAdAAQJSSRXCwCbAQAuAAQKfygAAh0ACQmeJDoFABgDAB0ACQmeJDoFABgDAAAA.Wilferal:BAAALgAECgQJBAAAAA==.Willaá:BAABLgAECn8WAAIXAAcJTwlMfgAdAQAXAAcJTwlMfgAdAQAAAA==.Willowyn:BAABLgAECn8yAAMQAAkJ5BbrFAADAgAQAAkJ5BbrFAADAgAPAAkJXBHAFQC2AQAAAA==.Wingmans:BAAALgAECgQJBwAAAA==.Wizzpeaver:BAABLgAECn8VAAIQAAcJgQ0BLwAuAQAQAAcJgQ0BLwAuAQAAAA==.',
Wo='Wonderwizard:BAABLgAECn8fAAICAAcJmxNhagBnAQACAAcJmxNhagBnAQAAAA==.Wonglow:BAAALgAECgYJBgAAAA==.',
Wr='Wraeth:BAAALgADCgYJBgAAAA==.Wrathhoof:BAAALgAECggJDwABLgAECggJEgAFAAAAAA==.',
Xa='Xahra:BAAALgADCgcJBwAAAA==.Xaralyss:BAAALgAECgQJBwAAAA==.',
Xh='Xhine:BAAALgAECgEJAgAAAA==.',
Xi='Xin:BAAALgAECgUJCAAAAA==.',
Xy='Xylias:BAAALgADCgcJEAAAAA==.',
Ya='Yamon:BAAALgADCggJEAAAAA==.',
Yo='Yodef:BAACLgAFFH8LAAIXAAQJMhJvQQA1AQAXAAQJMhJvQQA1AQAuAAQKfyEAAhcACAnlI7YRAKACABcACAnlI7YRAKACAAAA.Yorri:BAAALgAECgMJAwAAAA==.Yorril:BAAALgAECgcJBwAAAA==.',
Yu='Yucca:BAACLgAFFH8FAAMMAAIJChDQJgA5AAAXAAIJzgt+kQCZAAAMAAEJyhLQJgA5AAAuAAQKfzMAAxcACQnoFwwlACkCABcACQnoFwwlACkCAAwABAmcBm82AGgAAAAA.Yuda:BAAALgAECgEJBQABLgAECgEJAQAFAAAAAA==.Yudaneyo:BAAALgAECgEJBgABLgAECgEJAQAFAAAAAA==.Yukiteru:BAABLgAECn8nAAMUAAkJvB1GEACAAgAUAAkJvB1GEACAAgAjAAIJ2xUHNwB5AAAAAA==.Yurito:BAABLgAECn8nAAIlAAcJaRs+FgDHAQAlAAcJaRs+FgDHAQAAAA==.',
Yz='Yzernara:BAAALgAECgEJAQABLgAECggJAgAFAAAAAA==.',
Za='Zabrina:BAABLgAECn8cAAIUAAgJjgU9dwDeAAAUAAgJjgU9dwDeAAAAAA==.Zaiel:BAAALgADCgMJAwAAAA==.Zakutin:BAAALgAECgEJAQABLgAECgcJFAANAKsWAA==.Zappybains:BAABLgAECn8wAAIGAAkJKx46CADkAgAGAAkJKx46CADkAgAAAA==.Zarakii:BAABLgAECn8dAAIWAAcJ/CA0JQD8AQAWAAcJ/CA0JQD8AQAAAA==.',
Ze='Zekken:BAAALgADCgMJBAAAAA==.Zelaina:BAABLgAECn8UAAITAAcJ8RYeVACDAQATAAcJ8RYeVACDAQAAAA==.',
Zi='Zi:BAAALgADCgQJBQABLgAECgkJPAAOAAQlAA==.',
Zu='Zuda:BAAALgAECgEJBgABLgAECgEJAQAFAAAAAA==.Zupaz:BAAALgADCgEJAQAAAA==.',
Zy='Zylluz:BAAALgAECggJDgAAAA==.Zylos:BAAALgAECgYJEwAAAA==.',
['Zì']='Zìnn:BAAALgAECgIJAgAAAA==.',
['Äs']='Äshébringer:BAACLgAFFH8NAAITAAUJyxx0CABuAQATAAUJyxx0CABuAQAuAAQKfyMAAhMACQlNJL8HAPsCABMACQlNJL8HAPsCAAAA.Ästen:BAAALgAECgIJAgAAAA==.',
['Æt']='Æthelred:BAAALgAECgEJAQABLgAECgYJFgALAL0ZAA==.',
['Ðr']='Ðragøn:BAAALgAECgcJBwAAAA==.',
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
