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

local lookup = {'Warrior-Protection','Mage-Frost','Hunter-Marksmanship','Warrior-Arms','Unknown-Unknown','Evoker-Preservation','Shaman-Restoration','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Shaman-Elemental','Warrior-Fury','Hunter-BeastMastery','Monk-Brewmaster','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','Druid-Feral','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DeathKnight-Unholy','Evoker-Devastation','Priest-Shadow','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Mage-Arcane','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Enhancement','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='Kargath',name='US',type='weekly',zone=46,date='2026-05-23',data={Aa='Aaryn:BAAALgAECgcJEAABLgAECggJOAABADcdAA==.',
Ab='Absynthia:BAABLgAECn8gAAICAAgJYQhbhABSAQACAAgJYQhbhABSAQAAAA==.',
Ac='Academe:BAABLgAECn8xAAICAAgJUBYLTwDSAQACAAgJUBYLTwDSAQAAAA==.Acrid:BAAALgAECgEJAQAAAA==.',
Ad='Ados:BAAALgAECgYJEQAAAA==.Advanced:BAAALgADCgEJAQAAAA==.',
Ae='Aeity:BAAALgAECgYJEAAAAA==.Aellion:BAAALgADCgEJAQAAAA==.Aellopus:BAAALgAECgEJAQAAAA==.Aenas:BAABLgAECn8VAAIDAAgJmQWcFADzAAADAAgJmQWcFADzAAAAAA==.Aero:BAABLgAECn84AAMBAAgJNx1aCQA8AgABAAgJNx1aCQA8AgAEAAYJ8Q6EFwA+AQAAAA==.',
Af='Afflictedd:BAAALgAECgEJAQAAAA==.',
Ag='Agapetus:BAAALgADCgYJBgAAAA==.',
Ah='Ahren:BAAALgAECgQJCwAAAA==.Ahuizott:BAAALgAECggJCAABLgAECggJCAAFAAAAAA==.',
Ak='Akata:BAAALgADCgcJBwAAAA==.',
Al='Alayder:BAAALgADCgYJBgAAAA==.Allured:BAAALgAECgkJCAABLgAECgkJGAAGABMVAA==.Almighty:BAABLgAECn8fAAIHAAkJGhZiHAA7AgAHAAkJGhZiHAA7AgAAAA==.Alocane:BAAALgADCgYJBgABLgAECggJHQAIAA8ZAA==.Alomeo:BAAALgADCggJDAAAAA==.',
Am='Amarí:BAAALgADCggJGAAAAA==.Amayêlle:BAAALgADCggJGAAAAA==.Amendos:BAAALgAECgYJCwAAAA==.Amiliane:BAABLgAECn8zAAQJAAgJjhTiCQB5AQAJAAcJmBbiCQB5AQAKAAYJBQ0MjAANAQALAAUJIwpaHQCHAAAAAA==.Amilmean:BAAALgADCggJCAAAAA==.Amunshi:BAAALgADCgQJBAAAAA==.Amz:BAAALgAECgYJDAAAAA==.',
An='Anadrien:BAABLgAECn8zAAMMAAkJLh4ACQAMAwAMAAkJLh4ACQAMAwANAAMJHQ8NVACOAAAAAA==.Ancelagon:BAAALgADCgYJBgAAAA==.Andrae:BAAALgAECgcJDAAAAA==.Andrastae:BAAALgAECgYJBgAAAA==.Angrima:BAAALgAECgEJAQAAAA==.Angrimia:BAABLgAECn84AAIOAAgJYyClBwB6AgAOAAgJYyClBwB6AgAAAA==.Anju:BAAALgAECgEJAgAAAA==.Annussa:BAAALgADCgIJAgAAAA==.Ansticé:BAAALgADCgYJBgAAAA==.Antal:BAAALgAECgcJEwAAAA==.Anthelyn:BAAALgAECgYJCQAAAA==.',
Ar='Arannis:BAAALgAECgYJBgAAAA==.Arboria:BAABLgAECn8UAAMHAAcJOSCLFQBxAgAHAAcJOSCLFQBxAgAPAAEJvw/aiAAwAAAAAA==.Archielgh:BAABLgAECn8cAAMQAAgJgw1iPgAjAQAQAAcJyApiPgAjAQABAAQJ4Q4bKQDDAAAAAA==.Areldor:BAAALgAECggJBQAAAA==.Aremethea:BAAALgADCgkJFwABLgAECgYJHQARAN4NAA==.Ariaa:BAAALgADCggJDAAAAA==.Arkannah:BAAALgADCgcJBwAAAA==.Aronk:BAABLgAECn81AAQSAAgJdBQWKABRAQASAAcJeBUWKABRAQATAAcJ4RDLLgAkAQAUAAgJ4ANyTgDVAAAAAA==.Arore:BAAALgADCgkJCQABLgAECggJNQASAHQUAA==.Aroreck:BAAALgADCgMJAwABLgAECggJNQASAHQUAA==.Arorepriest:BAAALgADCgcJBwABLgAECggJNQASAHQUAA==.Articulàte:BAAALgAECgQJCwAAAA==.Arzec:BAABLgAECn8kAAIGAAcJjwyvFQBMAQAGAAcJjwyvFQBMAQAAAA==.Arîel:BAAALgAECgQJBQAAAA==.',
At='Atheania:BAAALgAECgkJCgAAAA==.Atheanos:BAAALgAECgkJBgAAAA==.',
Av='Avestara:BAABLgAECn84AAIVAAgJBB1TDAB8AgAVAAgJBB1TDAB8AgAAAA==.',
Aw='Awenlock:BAEALgADCgcJCAAAAA==.',
Ay='Ayleesh:BAAALgAECgQJBAAAAA==.Ayleesha:BAAALgAECgUJBgAAAA==.Ayluid:BAABLgAECn8ZAAMWAAYJpwztGwAQAQAWAAUJiQ7tGwAQAQAXAAYJ8wZvNwB+AAAAAA==.',
Az='Azavtani:BAAALgADCgEJAgAAAA==.Azazill:BAAALgAECgkJEwAAAA==.Azeralle:BAAALgADCgkJCgAAAA==.Azmodeus:BAAALgAECgMJBAAAAA==.Azoril:BAABLgAECn88AAIYAAkJ7BIWPwDqAQAYAAkJ7BIWPwDqAQAAAA==.Azùla:BAAALgADCggJFQAAAA==.',
['Aí']='Aídeen:BAABLgAECn8aAAICAAgJjQIhxwDhAAACAAgJjQIhxwDhAAAAAA==.',
Ba='Baal:BAAALgADCgcJEQAAAA==.Babaspook:BAAALgAECggJCwAAAA==.Badseedz:BAAALgAECgcJCgAAAA==.Baelnorn:BAABLgAECn8oAAMKAAgJayC7GwBjAgAKAAgJayC7GwBjAgAJAAMJ9xb1SgCNAAAAAA==.Bains:BAAALgAECgQJBgAAAA==.Baja:BAAALgAECgQJBwAAAA==.Bambalamm:BAAALgAECgYJBgAAAA==.Bandit:BAAALgAECgYJDwAAAA==.Barress:BAAALgAECgEJAQAAAA==.Batrela:BAAALgAECgYJDwAAAA==.Battleturtle:BAAALgAECgYJCwAAAA==.Batôsai:BAAALgAECgMJBAAAAA==.Bazir:BAAALgAECgIJAgABLgAFFAYJGQACALEWAA==.',
Bd='Bddaddy:BAAALgAECgMJBAAAAA==.',
Be='Beardiso:BAAALgAECgEJAQAAAA==.Bearjuu:BAAALgAECgYJCQABLgAECgkJHwAZAPQbAA==.Bearpawz:BAABLgAECn8pAAIWAAkJ0xkYBgBWAgAWAAkJ0xkYBgBWAgAAAA==.Bearrel:BAAALgAECgYJCwAAAA==.Bearrier:BAAALgADCgEJAQAAAA==.Beastcleave:BAAALgAECgYJBgAAAA==.Beelz:BAAALgAECgcJBwAAAA==.Bekens:BAABLgAECn8kAAIRAAkJWSAGEQCgAgARAAkJWSAGEQCgAgAAAA==.Belaraariaae:BAAALgAECgQJBAABLgAECgcJFgASABUgAA==.Benastiel:BAAALgADCgYJBwAAAA==.Benwetta:BAAALgAECgMJAwAAAA==.Bernardboggs:BAABLgAECn8gAAMTAAgJ8hmjGADDAQATAAcJ7xujGADDAQASAAYJNQ6eNgAFAQAAAA==.Bethbathory:BAABLgAECn8wAAILAAkJLhoaBAAtAgALAAkJLhoaBAAtAgAAAA==.',
Bh='Bheefknight:BAABLgAECn8YAAMOAAcJgw7KIAAdAQAOAAcJgw7KIAAdAQAaAAMJzwLKAwFwAAAAAA==.Bheeftotemz:BAAALgAECgcJBwAAAA==.',
Bi='Bibbee:BAAALgAECggJEAAAAA==.Bierbro:BAABLgAECn8VAAIaAAcJiRH+jABnAQAaAAcJiRH+jABnAQAAAA==.Bigbus:BAAALgAECgkJAQAAAA==.Bigfacts:BAAALgAECggJDQAAAA==.Bigoldee:BAAALgADCgUJBQAAAA==.Bigyk:BAAALgADCgYJBgAAAA==.Billié:BAABLgAECn8sAAQKAAkJvyNeBQAmAwAKAAgJvyNeBQAmAwAJAAMJ5iD/KAAfAQALAAIJ1h3gLABFAAAAAA==.',
Bk='Bk:BAAALgAECgMJAwAAAA==.',
Bl='Blightheaded:BAAALgAECgQJBwABLgAECgcJCQAFAAAAAA==.Blindëye:BAAALgAECgYJDQAAAA==.Blumir:BAABLgAECn8WAAMGAAkJohbeBgBvAgAGAAkJohbeBgBvAgAbAAUJ4h0TEQDVAAAAAA==.',
Bn='Bnththeocean:BAABLgAECn8bAAIHAAkJaRUtIQAaAgAHAAkJaRUtIQAaAgAAAA==.',
Bo='Bobmauley:BAAALgADCgQJBAAAAA==.Bombdormu:BAAALgAECgUJBQAAAA==.Bombkin:BAABLgAECn84AAIMAAgJUSPaEACqAgAMAAgJUSPaEACqAgAAAA==.Bonchonn:BAACLgAFFH8MAAIRAAQJDBgSHgBNAQARAAQJDBgSHgBNAQAuAAQKfyAAAhEACAlPIHAOAMgCABEACAlPIHAOAMgCAAAA.Bonefister:BAAALgAECgEJAQAAAA==.Bonkfoo:BAAALgADCgcJBwAAAA==.Bonkula:BAABLgAECn8pAAIHAAgJfA46SgBSAQAHAAgJfA46SgBSAQAAAA==.Boondox:BAAALgAECgMJAwAAAA==.Bootyfeastr:BAAALgADCgEJAwAAAA==.Bopmedaddy:BAAALgAECgkJCQAAAA==.Bops:BAAALgADCgQJBAAAAA==.Boredumb:BAAALgAECgYJBgAAAA==.Borque:BAAALgAECgcJDAABLgAECgkJFAAcAIwWAA==.Bouncy:BAAALgAECgcJDAABLgAECgkJNwAaAFEcAA==.',
Br='Brae:BAAALgAECggJDwAAAA==.Bralitha:BAAALgADCgEJAQAAAA==.Braumbastic:BAAALgADCgUJBQAAAA==.Brazonk:BAAALgADCgkJCQAAAA==.Brewzco:BAABLgAECn9EAAISAAkJBSUbAQBXAwASAAkJBSUbAQBXAwAAAA==.Briciferdawg:BAAALgAECgUJBQABLgAFFAMJEwAaALomAA==.Bricifergoat:BAACLgAFFH8dAAIPAAcJtSInAgB8AgAPAAcJtSInAgB8AgAuAAQKfyEAAg8ACAmqJRoKAPMCAA8ACAmqJRoKAPMCAAEuAAUUAwkTABoAuiYA.Briciferkong:BAACLgAFFH8TAAIaAAMJuiYrOQBRAQAaAAMJuiYrOQBRAQAuAAQKfyUAAxoACAmXI5gOANgCABoACAmXI5gOANgCAB0AAQknCKAYAC0AAAAA.Briciferyeah:BAAALgADCgQJBAABLgAFFAMJEwAaALomAA==.Brightblayde:BAABLgAECn84AAIYAAgJzBueMQAYAgAYAAgJzBueMQAYAgAAAA==.Brique:BAAALgADCggJDAABLgAECgkJFAAcAIwWAA==.',
Bu='Buanto:BAAALgAECgQJCgAAAA==.Bubblegumm:BAABLgAECn8pAAMMAAgJSRbtKQDjAQAMAAgJSRbtKQDjAQANAAEJrgNChwAgAAAAAA==.Bubieh:BAAALgAECgQJBQABLgAECgkJLAAOAMYkAA==.Bullshatner:BAAALgAECgEJAQAAAA==.Bumpinlumps:BAAALgAECgQJBAAAAA==.Bushwookiee:BAAALgAECgcJDQAAAA==.Butterknight:BAACLgAFFH8PAAIaAAQJ3Bo0OwBNAQAaAAQJ3Bo0OwBNAQAuAAQKfyQAAhoACQmRI0cWAPYCABoACQmRI0cWAPYCAAAA.Buttertotem:BAABLgAFFH8FAAMPAAMJBgOXLQChAAAPAAMJBgOXLQChAAAHAAIJrgSzVABpAAAAAA==.',
Ca='Caanu:BAAALgADCgUJBwAAAA==.Calypso:BAAALgAECgMJAwAAAA==.Candlelock:BAABLgAECn8aAAMLAAgJIgtLCwByAQALAAgJIgtLCwByAQAJAAEJRQaOOgAjAAAAAA==.Carirmonk:BAAALgAECgEJAQAAAA==.Cattroll:BAABLgAECn80AAMMAAkJjCEnCQAKAwAMAAkJjCEnCQAKAwAXAAYJmxVUGgA5AQAAAA==.Caxianx:BAAALgADCgYJBgAAAA==.',
Cd='Cdub:BAABLgAECn8gAAIYAAYJwBJnlwAlAQAYAAYJwBJnlwAlAQAAAA==.',
Ce='Celidori:BAABLgAECn8XAAIZAAkJyg8qPAC2AQAZAAkJyg8qPAC2AQABLgAECgkJNAAMAIwhAA==.Celithila:BAABLgAECn81AAMeAAgJXBn5DQBfAgAeAAgJXBn5DQBfAgAVAAYJegpGPADmAAAAAA==.Celithvia:BAABLgAECn8vAAIYAAkJ3xJoPwDpAQAYAAkJ3xJoPwDpAQAAAA==.Ceroin:BAAALgADCgEJAQAAAA==.Cervantés:BAABLgAECn81AAMfAAkJYiImBgCqAgAfAAkJHiImBgCqAgAgAAcJMBtLBgAVAgAAAA==.',
Ch='Chaia:BAABLgAECn8iAAIMAAgJMxnmHgAsAgAMAAgJMxnmHgAsAgAAAA==.Chelsea:BAAALgAECgEJAQAAAA==.Cherra:BAAALgAECgcJBwABLgAECgcJFgASABUgAA==.Chillmeister:BAAALgAECgcJBwAAAA==.Chise:BAABLgAECn8hAAIVAAkJoxSEFgD0AQAVAAkJoxSEFgD0AQAAAA==.Chitanka:BAAALgADCgkJDQAAAA==.Chrispyloa:BAAALgAECgQJCwAAAA==.Chubs:BAABLgAECn8bAAMJAAcJiBhPDgDjAQAJAAcJsxdPDgDjAQAKAAUJWRRyvgDcAAAAAA==.',
Cl='Clann:BAABLgAECn8nAAICAAgJeg/ZagCJAQACAAgJeg/ZagCJAQAAAA==.Cly:BAABLgAECn8dAAMhAAgJZh9fCgDBAgAhAAgJZh9fCgDBAgAYAAEJeBA0UAE3AAAAAA==.Clyde:BAAALgAECgMJAwAAAA==.Clydk:BAAALgAECggJDwABLgAECggJHQAhAGYfAA==.',
Co='Coachbeard:BAABLgAECn83AAIhAAkJ9hXSFQA2AgAhAAkJ9hXSFQA2AgAAAA==.Colzamenta:BAACLgAFFH8JAAIZAAQJYw97SgDZAAAZAAQJYw97SgDZAAAuAAQKfx8AAhkACAlbILwSAI8CABkACAlbILwSAI8CAAAA.Colzaratha:BAABLgAFFH8KAAIdAAQJcyNmAgCYAQAdAAQJcyNmAgCYAQAAAA==.Contract:BAAALgAECgcJDAAAAA==.Corpsereth:BAAALgAECgkJAwAAAA==.',
Cr='Creamcicle:BAAALgADCgEJAQAAAA==.Crispytots:BAAALgAECgcJDAAAAA==.Critmypantz:BAABLgAECn8cAAITAAgJSRbiIADPAQATAAgJSRbiIADPAQAAAA==.Critthat:BAAALgAECgUJCQAAAA==.Crosby:BAAALgADCgUJBQAAAA==.Cruel:BAAALgAECgMJBAABLgAECgQJBwAFAAAAAA==.',
Cu='Cudguzzler:BAAALgADCggJCQAAAA==.Cursegoesmoo:BAACLgAFFH8NAAIaAAQJuByqQgBAAQAaAAQJuByqQgBAAQAuAAQKfx8AAhoACQmaJHgGACsDABoACQmaJHgGACsDAAAA.Cuzz:BAAALgAECgQJBAAAAA==.',
Cy='Cygna:BAABLgAECn89AAIRAAkJDCKSEgCTAgARAAkJDCKSEgCTAgAAAA==.Cyntheria:BAABLgAECn8uAAMYAAkJWSACDgDbAgAYAAkJWSACDgDbAgAIAAEJ8BFNQQA2AAAAAA==.Cyphex:BAAALgADCgkJCAABLgAECgkJPQARAAwiAA==.',
Da='Daddybeàr:BAAALgAECgQJBQAAAA==.Daendron:BAAALgADCgQJBAAAAA==.Dajubah:BAABLgAECn8wAAIBAAkJih6iBQCZAgABAAkJih6iBQCZAgAAAA==.Dammitdave:BAABLgAECn8jAAIYAAYJmwxFpAAPAQAYAAYJmwxFpAAPAQAAAA==.Dangereuse:BAAALgAECgYJDQAAAA==.Darbi:BAAALgADCgEJAQAAAA==.Darinell:BAAALgAECgUJCwAAAA==.Darksaxon:BAABLgAECn8lAAIBAAgJ2R3MCABIAgABAAgJ2R3MCABIAgAAAA==.Darkseid:BAAALgAECgkJCAAAAA==.Darthsidd:BAAALgAECgkJDQAAAA==.',
De='Deathnethal:BAABLgAECn8YAAIaAAYJnAvhpgD5AAAaAAYJnAvhpgD5AAAAAA==.Deathweaver:BAAALgAFFAMJBAAAAA==.Deebbz:BAAALgAFFAIJBAAAAA==.Deebbzmonk:BAACLgAFFH8GAAIUAAIJTwetNQBoAAAUAAIJTwetNQBoAAAuAAQKfxQAAhQABwmoFPgqAF4BABQABwmoFPgqAF4BAAAA.Deeneye:BAAALgADCgkJCQABLgAECgYJGwAPABIQAA==.Deeno:BAAALgAECgEJBQAAAA==.Defrausted:BAAALgAECggJCAAAAA==.Deme:BAAALgADCgcJCgAAAA==.Demonica:BAABLgAECn8iAAQKAAgJaR6SIgA+AgAKAAcJSiKSIgA+AgALAAMJqxlkFgDXAAAJAAMJwA0dOQAnAAAAAA==.Demonscythe:BAAALgADCgcJAgABLgAECgIJAgAFAAAAAA==.Demonseedz:BAAALgAECgEJAgAAAA==.Dendrax:BAABLgAECn8rAAIKAAkJ6gpNUACTAQAKAAkJ6gpNUACTAQAAAA==.Dented:BAABLgAECn8fAAIYAAcJTAq7rgAmAQAYAAcJTAq7rgAmAQAAAA==.Derivation:BAAALgAECgQJCwAAAA==.Destitute:BAAALgAECgUJBQAAAA==.Detaren:BAAALgADCgEJAQAAAA==.Dethwing:BAAALgAECgIJBAAAAA==.Devadeity:BAABLgAECn8sAAIeAAgJCBPuIgCJAQAeAAgJCBPuIgCJAQAAAA==.Deviance:BAABLgAECn8aAAIHAAgJph9dFQBzAgAHAAgJph9dFQBzAgAAAA==.Devola:BAAALgADCgkJFAAAAA==.Dextero:BAAALgAECgQJBAABLgAECggJJwARAHkiAA==.',
Di='Didntask:BAAALgADCgEJAQABLgAECggJGwAOAIQOAA==.Dienmage:BAABLgAECn8xAAIiAAkJrB/GAADOAgAiAAkJrB/GAADOAgAAAA==.Digìt:BAAALgAECgIJAgABLgAECgcJGgAeAC4dAA==.Dirtychai:BAABLgAECn8kAAIeAAgJiR/FCQCoAgAeAAgJiR/FCQCoAgAAAA==.Dissonance:BAAALgAECgkJDAAAAA==.Diurd:BAAALgAECgEJAQAAAA==.Divine:BAAALgADCgYJBgAAAA==.',
Dj='Djanga:BAABLgAECn85AAMNAAkJLCW3AQBVAwANAAkJLCW3AQBVAwAMAAQJvRoeZAAlAQAAAA==.Djdazzle:BAAALgAECggJAwAAAA==.',
Dk='Dkchocobussy:BAAALgADCgMJAwAAAA==.Dkdiso:BAAALgAECgcJCgAAAA==.',
Do='Doctorevil:BAAALgAECgYJEAAAAA==.Dogbearcat:BAAALgAFFAIJAgABLgAFFAIJBQAIADkbAA==.Dogglefrog:BAAALgADCgEJAQAAAA==.Dominance:BAAALgAECgEJAgAAAA==.Doranthsæ:BAAALgADCgcJBwABLgAFFAIJBgANAA8aAA==.Dorito:BAABLgAFFH8GAAIaAAQJ+R6UMABjAQAaAAQJ+R6UMABjAQAAAA==.Dothausen:BAABLgAECn8UAAQJAAcJ2AxrEQADAQAJAAcJ2AxrEQADAQALAAYJYgTOGQC2AAAKAAEJAABVPQEAAAAAAA==.',
Dr='Dracaaron:BAAALgAECgUJBwAAAA==.Dragonevil:BAAALgADCgYJBgAAAA==.Dragooned:BAACLgAFFH8QAAICAAUJ+BojMwBdAQACAAUJ+BojMwBdAQAuAAQKfxYAAgIABwklJBIuALkCAAIABwklJBIuALkCAAAA.Dragussy:BAAALgAECgQJBAAAAA==.Drakenallure:BAABLgAECn8YAAQGAAgJExUWDgDJAQAGAAgJExUWDgDJAQAbAAIJKAyGHwA4AAAjAAEJmgglfAAzAAAAAA==.Drakkisath:BAABLgAECn8gAAMjAAcJDBX4MgA+AQAjAAcJ9xT4MgA+AQAbAAUJPxPoEgC5AAAAAA==.Draknethal:BAAALgAECgIJAgAAAA==.Dramn:BAAALgADCgMJAwAAAA==.Drango:BAABLgAECn8eAAIbAAkJ0QQADQAgAQAbAAkJ0QQADQAgAQAAAA==.Draugdae:BAABLgAECn81AAIXAAgJ7SADBQCOAgAXAAgJ7SADBQCOAgAAAA==.Drayslinger:BAAALgAECgUJCwAAAA==.Dreki:BAAALgADCgYJCQABLgAECgIJAgAFAAAAAA==.Drinksomuch:BAAALgAECgkJCwAAAA==.Drlechee:BAAALgADCgMJBQAAAA==.Drob:BAEALgAECgUJBQAAAA==.Drome:BAAALgADCggJCAABLgAECggJNQARANQeAA==.Droze:BAAALgADCgkJCQAAAA==.Drukhi:BAABLgAECn8oAAIRAAkJzB1rEgCVAgARAAkJzB1rEgCVAgAAAA==.Drunkalicius:BAACLgAFFH8HAAISAAIJKQf3QAB1AAASAAIJKQf3QAB1AAAuAAQKfxYAAhIABwlwDD4xAB8BABIABwlwDD4xAB8BAAAA.',
Du='Dudepriest:BAABLgAECn8WAAMeAAkJbhmeDgBWAgAeAAkJbhmeDgBWAgAVAAYJhwWKOwDNAAAAAA==.Dungrough:BAAALgAECggJEwAAAA==.Durtkal:BAABLgAECn9CAAMKAAkJGxW0LQAJAgAKAAkJGxW0LQAJAgAJAAYJZw7lHwBTAQAAAA==.',
Dw='Dwarlin:BAAALgADCgkJCQAAAA==.',
Dy='Dyonn:BAAALgADCgkJEgAAAA==.',
['Dê']='Dêädpool:BAAALgADCgYJBgAAAA==.',
Ed='Edgeboy:BAAALgAECgYJDwABLgAFFAYJGQACALEWAA==.',
Ef='Efarel:BAABLgAECn8vAAIQAAkJGxZMHgDYAQAQAAkJGxZMHgDYAQAAAA==.Efil:BAAALgAECgMJBwAAAA==.Efu:BAAALgAECgYJBgAAAA==.',
El='Eleantha:BAAALgADCgYJBwAAAA==.Elinisar:BAAALgAECgcJCwAAAA==.Elsa:BAABLgAECn8rAAICAAkJ5A97SQDjAQACAAkJ5A97SQDjAQAAAA==.Elzza:BAAALgADCgYJCQAAAA==.',
Em='Embear:BAAALgADCgcJEAAAAA==.Emmersblade:BAAALgAECgcJCAAAAA==.',
En='Eneco:BAAALgAECgEJAgAAAA==.Enjaydin:BAAALgAECgUJBQAAAA==.Enjaydo:BAABLgAECn8uAAICAAgJgh8gMgAyAgACAAgJgh8gMgAyAgAAAA==.',
Ep='Epicfurry:BAAALgAECgUJCwAAAA==.',
Er='Ereile:BAAALgAECgUJCAAAAA==.Errlhickey:BAAALgADCgUJCQAAAA==.',
Es='Escanor:BAAALgADCgYJBgAAAA==.',
Eu='Eukelade:BAAALgADCgcJBwABLgAECgkJMwAUALEeAA==.Eurythmics:BAABLgAECn8gAAIRAAcJWBWrRwCTAQARAAcJWBWrRwCTAQAAAA==.',
Ev='Evileen:BAAALgAECgEJAQAAAA==.Evonahh:BAAALgADCgcJEwAAAA==.',
Ex='Exelion:BAABLgAECn8qAAIeAAkJ5x01DAB7AgAeAAkJ5x01DAB7AgAAAA==.Explogan:BAAALgAECgYJBwAAAA==.',
Ez='Ezanah:BAAALgADCgUJBQAAAA==.Ezrack:BAAALgAECgMJAwABLgAECggJHQAIAA8ZAA==.',
Fa='Faaith:BAAALgADCgcJCwAAAA==.Faeyrin:BAABLgAECn8wAAIdAAkJeRPNBwDTAQAdAAkJeRPNBwDTAQAAAA==.Fahooquazaad:BAAALgAECgQJDgAAAA==.Falconsg:BAAALgADCgQJBAAAAA==.Fancie:BAAALgADCgEJAQAAAA==.Fancy:BAABLgAECn8UAAITAAkJgxcZGQAZAgATAAkJgxcZGQAZAgAAAA==.Faythlis:BAABLgAECn8gAAIKAAgJ0wpKagBRAQAKAAgJ0wpKagBRAQAAAA==.',
Fe='Feetlesmcdee:BAABLgAECn8gAAIYAAkJqQeGegBZAQAYAAkJqQeGegBZAQAAAA==.Felf:BAAALgADCgcJBwAAAA==.Felfáádaern:BAEBLgAECn8qAAQkAAgJFg7vHwA9AQAkAAgJ5QzvHwA9AQAZAAIJKgEX3wAzAAAlAAIJegrpKgAyAAAAAA==.Felporch:BAABLgAECn8WAAIlAAgJRQylDgA4AQAlAAgJRQylDgA4AQAAAA==.',
Fi='Filburt:BAAALgADCgEJAQAAAA==.',
Fk='Fkton:BAAALgADCgIJAgAAAA==.',
Fl='Flamediso:BAAALgAECgIJAwAAAA==.Fledermaus:BAAALgADCgEJAQAAAA==.Flourchild:BAAALgADCgEJAQAAAA==.Flowermound:BAAALgAECgQJCAAAAA==.Flowerrose:BAAALgADCgYJBgAAAA==.',
Fo='Forrester:BAABLgAECn8XAAINAAcJfBpaHQCwAQANAAcJfBpaHQCwAQAAAA==.Fourqto:BAABLgAECn8aAAMJAAgJqQo3DwAgAQAJAAgJqQo3DwAgAQAKAAcJkQMKsgDIAAAAAA==.Fox:BAACLgAFFH8UAAMeAAcJOiO6AACTAgAeAAcJOiO6AACTAgAVAAIJ9QZXMQB+AAAuAAQKfxoAAh4ACAkXHgkLAJ4CAB4ACAkXHgkLAJ4CAAAA.',
Fr='Franklee:BAAALgAECgYJDAAAAA==.Freight:BAAALgADCgMJAwAAAA==.Friedcry:BAAALgADCgYJBgAAAA==.Fron:BAABLgAECn8XAAIeAAYJdRUIIwCIAQAeAAYJdRUIIwCIAQAAAA==.Fronie:BAAALgADCgcJAwAAAA==.',
Fu='Fujikujaku:BAABLgAECn8lAAIMAAgJMRZ1JAAFAgAMAAgJMRZ1JAAFAgAAAA==.Fulmetal:BAAALgAECgQJBAAAAA==.Funerris:BAAALgADCgEJAQABLgAFFAcJDQAjAKsJAA==.Funiris:BAACLgAFFH8JAAIcAAUJSAhhBQB3AQAcAAUJSAhhBQB3AQAuAAQKfxUAAxwABwnsFesoAJMBABwABwnsFesoAJMBABUABQmKDiQyABABAAEuAAUUBwkNACMAqwkA.Funkalicious:BAACLgAFFH8PAAIPAAMJfRLCJgDNAAAPAAMJfRLCJgDNAAAuAAQKfzsAAg8ACQlOIigFAPMCAA8ACQlOIigFAPMCAAAA.',
['Fé']='Félo:BAABLgAECn8yAAMJAAkJ0iLSAgBVAgAJAAcJhiTSAgBVAgAKAAYJciAUJwAmAgAAAA==.',
Ga='Gabaghoul:BAAALgAECgYJBgAAAA==.Gaila:BAAALgADCgUJBgABLgAECgkJLAAKAL8jAA==.Garathor:BAAALgAECgEJAgAAAA==.Garthoneeye:BAABLgAECn8VAAIiAAYJ9gPGCgClAAAiAAYJ9gPGCgClAAAAAA==.Gazreyna:BAABLgAECn8uAAIaAAgJsCIMFACvAgAaAAgJsCIMFACvAgAAAA==.',
Gc='Gcarne:BAABLgAECn8rAAMMAAkJVg39UAAoAQAMAAgJLAr9UAAoAQANAAgJzwUhOAACAQAAAA==.',
Ge='Gemmy:BAAALgADCggJCAAAAA==.Genz:BAAALgADCgEJAQAAAA==.Genós:BAABLgAECn8rAAMQAAkJQR28DgBlAgAQAAkJfhy8DgBlAgABAAgJ+xfbEACyAQAAAA==.Gerardo:BAABLgAECn8VAAIQAAYJthhtLQB2AQAQAAYJthhtLQB2AQAAAA==.',
Gh='Ghurri:BAAALgAECgYJDAAAAA==.',
Gi='Gibs:BAAALgAECgYJDAAAAA==.Ginnee:BAAALgAECgQJCgAAAA==.Ginnion:BAABLgAECn8UAAIGAAcJTRfREgB4AQAGAAcJTRfREgB4AQAAAA==.Girthytail:BAAALgAECgYJEQAAAA==.',
Gl='Glaedor:BAAALgAECgQJBAAAAA==.Glakenspheal:BAABLgAECn8kAAQVAAgJQhCIJQB0AQAVAAcJChGIJQB0AQAeAAEJyAqAYAAyAAAcAAEJrALYfQAbAAAAAA==.Glamorous:BAAALgAECgYJDAAAAA==.Glein:BAAALgAECgYJCgABLgAECgkJNAATAJYiAA==.',
Go='Gongfu:BAAALgADCgYJBgAAAA==.Gooeycreampi:BAAALgADCgEJAQAAAA==.Goonie:BAAALgAECgYJCAAAAA==.',
Gr='Graestoke:BAACLgAFFH8OAAICAAQJ9BX0QgA/AQACAAQJ9BX0QgA/AQAuAAQKfxgAAgIACAnWH2o0AKECAAIACAnWH2o0AKECAAAA.Graevana:BAAALgADCgEJAQAAAA==.Gregorizz:BAAALgAECgEJBAAAAA==.Greyaura:BAAALgAECgQJBAAAAA==.Greybeast:BAAALgAECgYJDAAAAA==.Greyfoxy:BAAALgAECgYJDAAAAA==.Grianick:BAAALgAECgYJCwABLgAECggJHQAIAA8ZAA==.Grimixtalis:BAAALgAECgcJEQAAAA==.Growls:BAABLgAECn8uAAQNAAkJaB0+DABsAgANAAgJKSA+DABsAgAMAAkJ5RP/IAAdAgAXAAcJGhGdGgA3AQAAAA==.',
Gu='Gurri:BAAALgAECgQJBgAAAA==.',
Gy='Gyaat:BAAALgADCggJDwAAAA==.',
['Gõ']='Gõldenchild:BAABLgAECn8cAAIhAAcJ8AhXRwD2AAAhAAcJ8AhXRwD2AAAAAA==.',
['Gü']='Gürri:BAAALgAECgkJCAAAAA==.',
Ha='Habenero:BAABLgAECn8fAAImAAcJWA32FAArAQAmAAcJWA32FAArAQAAAA==.Hagar:BAABLgAECn8ZAAIWAAcJFROREwBLAQAWAAcJFROREwBLAQAAAA==.Hairycow:BAAALgAECgMJAwAAAA==.Hairypitts:BAABLgAECn8gAAIWAAkJORelBgBEAgAWAAkJORelBgBEAgAAAA==.Haittou:BAAALgAECgkJBQAAAA==.Halfwyz:BAAALgAECgEJAQAAAA==.Halligan:BAABLgAECn8VAAMaAAcJbgZ+yQDEAAAaAAcJKQN+yQDEAAAOAAUJ3Qf9NwCHAAAAAA==.Hammertime:BAAALgAECggJEAAAAA==.Harabrew:BAAALgADCgkJFQAAAA==.Haraniantha:BAABLgAECn8WAAISAAcJFSBuFADsAQASAAcJFSBuFADsAQAAAA==.Hardø:BAAALgADCgcJCAAAAA==.Hatean:BAAALgAECgcJCAAAAA==.Hazzbek:BAAALgADCgUJBQAAAA==.',
He='Heiboss:BAAALgAECgQJBQABLgAECgkJLAAOAMYkAA==.Heibub:BAAALgAECgIJAgABLgAECgkJLAAOAMYkAA==.Heipal:BAAALgADCgYJBgABLgAECgkJLAAOAMYkAA==.Heiranir:BAAALgAECgQJBAABLgAECgkJLAAOAMYkAA==.Heiretic:BAAALgAECgQJBAABLgAECgkJLAAOAMYkAA==.Hellbane:BAAALgAECgQJCgAAAA==.Hemit:BAAALgAECgMJAwABLgAFFAQJDgACAPQVAA==.Hempknight:BAAALgADCgQJBQAAAA==.',
Hi='Hickups:BAAALgAECgYJCQABLgAECgkJNwAhAPYVAA==.Highestorder:BAAALgADCgYJBgAAAA==.Hikikomori:BAABLgAECn8aAAISAAgJaCJuBgC2AgASAAgJaCJuBgC2AgABLgAECgkJMgAOAOAiAA==.Hinomiko:BAABLgAECn8XAAMHAAYJHBBQbgDXAAAHAAUJhQtQbgDXAAAPAAYJBgh1UADFAAABLgAECggJGgAEAEYJAA==.',
Ho='Holycowch:BAABLgAECn8mAAMYAAkJOB1bHQB3AgAYAAkJDRxbHQB3AgAIAAYJ6BclGAAvAQAAAA==.Honeyb:BAAALgAECgQJCwAAAA==.Hoodieallen:BAAALgADCgQJBAAAAA==.Hoofthor:BAAALgADCgEJAQAAAA==.Hootiedixon:BAABLgAECn8ZAAIaAAYJhBZbggA5AQAaAAYJhBZbggA5AQAAAA==.',
Hu='Hughjaculate:BAABLgAECn8YAAInAAkJwQqOGQC0AQAnAAkJwQqOGQC0AQAAAA==.Huran:BAABLgAECn8sAAMOAAkJxiRpAQA8AwAOAAkJxiRpAQA8AwAaAAIJsBOqFQFUAAAAAA==.',
Id='Idcritthat:BAABLgAECn8eAAMgAAcJVxnPCACWAQAgAAcJVxnPCACWAQAfAAMJFA8yVgB2AAABLgAECggJHAATAEkWAA==.',
Ig='Ignignokt:BAEBLgAECn8rAAMRAAkJ6SOyDADaAgARAAkJ6SOyDADaAgADAAEJzhr3hwA0AAAAAA==.Igvoker:BAEALgAECgYJBgABLgAECgkJKwARAOkjAA==.',
Il='Illadont:BAAALgADCgEJAQAAAA==.Illith:BAAALgADCgEJAgAAAA==.',
Im='Imagine:BAABLgAECn8UAAIHAAkJniGlAwBdAwAHAAkJniGlAwBdAwAAAA==.Imirohe:BAABLgAECn8VAAMCAAcJrgg0uwBrAQACAAcJrgg0uwBrAQAiAAEJoQOUIgAcAAAAAA==.',
In='Inarush:BAABLgAECn8xAAIlAAkJ7AlPDABmAQAlAAkJ7AlPDABmAQAAAA==.Inuyahshi:BAAALgAECgkJCgAAAA==.',
Ir='Ira:BAAALgADCgIJAgAAAA==.Ironfistt:BAAALgADCgYJBgAAAA==.Ironknife:BAAALgADCggJGAAAAA==.Ironshield:BAACLgAFFH8SAAIRAAQJeR2lGQBaAQARAAQJeR2lGQBaAQAuAAQKfyQAAhEACQlnIJcFADMDABEACQlnIJcFADMDAAAA.',
Iv='Ivie:BAAALgAECgUJDwAAAA==.',
Iw='Iwishiknew:BAABLgAECn8pAAIQAAkJexcRFgAbAgAQAAkJexcRFgAbAgAAAA==.',
Iz='Iztras:BAAALgAECgQJCQAAAA==.Izuras:BAAALgAECgkJBwAAAA==.Izzit:BAAALgAECgQJCwAAAA==.',
Ja='Ja:BAACLgAFFH8FAAICAAMJ+xP5YQDyAAACAAMJ+xP5YQDyAAAuAAQKfxwAAgIACQkSGEg7ABECAAIACQkSGEg7ABECAAAA.Jabbtrak:BAABLgAECn8dAAIUAAgJFRVJHgDlAQAUAAgJFRVJHgDlAQAAAA==.Jabtrakk:BAAALgADCggJCAAAAA==.Jacklowry:BAAALgAECggJEAAAAA==.Jacodin:BAABLgAECn8lAAIhAAgJkx5VCQDRAgAhAAgJkx5VCQDRAgAAAA==.Jacquestrapp:BAAALgADCgkJDAAAAA==.Jakiepoobear:BAAALgAECgcJEQAAAA==.Jambie:BAABLgAECn8lAAQKAAgJvhZOTACfAQAKAAcJWRdOTACfAQAJAAIJUQzPUQB5AAALAAEJGxO+KwBEAAAAAA==.',
Je='Jedery:BAABLgAECn8rAAIIAAgJ1hK5EACLAQAIAAgJ1hK5EACLAQAAAA==.',
Jg='Jgglephysyx:BAAALgAECgkJDgAAAA==.',
Ji='Jianyü:BAABLgAECn8fAAIYAAgJ2RwHJQCTAgAYAAgJ2RwHJQCTAgAAAA==.Jimbæn:BAAALgADCgYJCAAAAA==.',
Jo='Jollyandy:BAEBLgAECn8lAAICAAgJ1xtFLgBCAgACAAgJ1xtFLgBCAgAAAA==.Jolynn:BAABLgAECn8wAAInAAkJOg+REgD6AQAnAAkJOg+REgD6AQAAAA==.Joroldess:BAABLgAECn8oAAIIAAkJDxrzCQD+AQAIAAkJDxrzCQD+AQAAAA==.',
Ju='Juzam:BAAALgAECgMJAwAAAA==.',
['Jü']='Jüggernaut:BAAALgAECgMJBAABLgAECgkJPQARAAwiAA==.',
Ka='Kaenara:BAAALgADCgEJAQABLgAECgIJAgAFAAAAAA==.Kahndumb:BAABLgAECn8lAAIQAAgJxRF/JgCgAQAQAAgJxRF/JgCgAQAAAA==.Kaida:BAAALgAECgUJCQAAAA==.Kaio:BAAALgADCgMJAwAAAA==.Kalahan:BAABLgAECn8gAAImAAgJlRJlDQCjAQAmAAgJlRJlDQCjAQAAAA==.Kalimaa:BAAALgAECgYJDwAAAA==.Kanara:BAAALgAECgkJBwAAAA==.Kaotut:BAAALgADCgQJBAAAAA==.Kappakappa:BAAALgAECgMJAwAAAA==.Kardrion:BAAALgAECgQJCAAAAA==.Karigyn:BAABLgAECn8vAAIgAAgJ0SI5AgCcAgAgAAgJ0SI5AgCcAgAAAA==.Karun:BAABLgAECn8tAAIdAAgJaBUYCgCaAQAdAAgJaBUYCgCaAQAAAA==.Kaskaa:BAABLgAECn8XAAMHAAgJVxF1NwChAQAHAAgJVxF1NwChAQAPAAgJBw9jKgByAQAAAA==.Kasok:BAAALgAECgYJDgAAAA==.Kasumi:BAAALgAECgkJEgABLgAECgkJRAASAAUlAA==.Katren:BAAALgAECgEJAQAAAA==.Katrienne:BAABLgAECn8ZAAIIAAYJdgUeKQDBAAAIAAYJdgUeKQDBAAAAAA==.Katrya:BAAALgADCgkJFQABLgAECgYJGQAIAHYFAA==.Katsfood:BAAALgADCgkJFQAAAA==.Kauzarukus:BAAALgAECgcJCgAAAA==.Kaylid:BAABLgAECn8kAAIoAAkJFRr1AgBZAgAoAAkJFRr1AgBZAgAAAA==.Kaylou:BAAALgADCgcJBwABLgAECgkJMgAYADcKAA==.Kazeralana:BAAALgAECgUJBQAAAA==.Kazzoth:BAABLgAECn8rAAIRAAkJbxNkMADxAQARAAkJbxNkMADxAQAAAA==.',
Ke='Keeiras:BAAALgAECgkJEwAAAA==.Keilen:BAAALgADCgUJBAAAAA==.Kelasha:BAABLgAECn8uAAIaAAgJVR6yPQDpAQAaAAgJVR6yPQDpAQAAAA==.Kellrun:BAAALgADCgYJBgAAAA==.Kelzie:BAAALgADCgcJBwAAAA==.',
Kh='Khadgär:BAAALgAECgYJDwAAAA==.Khalika:BAAALgAECgUJCgAAAA==.Kharanys:BAAALgADCgcJBwAAAA==.',
Ki='Kilroar:BAAALgADCgkJCQAAAA==.Kinoplex:BAAALgAECgYJCQABLgAFFAMJBAAFAAAAAA==.',
Kl='Klassiq:BAAALgADCgUJBQAAAA==.Klax:BAAALgAECgYJBgAAAA==.Klokateer:BAABLgAECn8fAAMgAAgJ/RimBQAuAgAgAAgJvBimBQAuAgAfAAUJ4w/bOgBCAQAAAA==.Klzx:BAABLgAECn80AAICAAgJjxvMNwAdAgACAAgJjxvMNwAdAgAAAA==.',
Ko='Kobold:BAAALgAECgMJAwABLgAECgcJDAAFAAAAAA==.Komo:BAAALgADCgcJBwAAAA==.Komoou:BAAALgAECgQJBAAAAA==.Komouo:BAAALgADCgMJAwABLgADCgcJBwAFAAAAAA==.Korbi:BAAALgADCgcJGAABLgAECgkJMAAPABAVAA==.Kortek:BAABLgAECn8gAAIjAAgJwAMCRgDpAAAjAAgJwAMCRgDpAAAAAA==.Korvold:BAABLgAECn8ZAAIQAAkJChu+DwBZAgAQAAkJChu+DwBZAgAAAA==.Kosmos:BAABLgAECn8ZAAMOAAgJZBgAEQDLAQAaAAgJJhJbWgDiAQAOAAcJjRkAEQDLAQAAAA==.Kozath:BAABLgAECn8cAAIGAAYJAwWFIADJAAAGAAYJAwWFIADJAAAAAA==.',
Kr='Kreckon:BAABLgAECn8VAAIWAAcJEg7BFgAmAQAWAAcJEg7BFgAmAQAAAA==.Kriandor:BAAALgAECgEJAgAAAA==.Kronn:BAAALgAECgMJAwAAAA==.',
Ks='Kschnell:BAAALgAECgUJBgABLgAFFAYJGQACALEWAA==.',
Ku='Kukulkan:BAACLgAFFH8JAAIGAAMJlAkMGwC0AAAGAAMJlAkMGwC0AAAuAAQKfxwAAgYABwm6Dw8fAIgBAAYABwm6Dw8fAIgBAAAA.Kuulan:BAABLgAECn8rAAIYAAkJjRZIOAAAAgAYAAkJjRZIOAAAAgAAAA==.',
La='Lacertidae:BAAALgADCgEJAQAAAA==.Larwock:BAABLgAECn8UAAMKAAUJOwulsADKAAAKAAUJOwulsADKAAAJAAQJSAbHSACUAAAAAA==.Lathorâ:BAAALgADCgkJDgABLgAECgYJHAAkAGgWAA==.Latwiz:BAAALgADCgYJCQABLgAECggJGgAYABYeAA==.',
Le='Leancuisine:BAABLgAECn8XAAMHAAcJOxypHgArAgAHAAcJOxypHgArAgAPAAEJ4wHmnQAbAAAAAA==.Leetlebug:BAAALgAECgYJEQAAAA==.Lettÿ:BAABLgAECn8cAAIkAAYJaBZrHgBKAQAkAAYJaBZrHgBKAQAAAA==.',
Li='Lightheaded:BAAALgAECgcJCQAAAA==.Lightzwrath:BAABLgAECn8WAAMYAAgJkhEyXACaAQAYAAgJkhEyXACaAQAIAAQJwwJBOABgAAABLgAECgkJEwAFAAAAAA==.Linadra:BAAALgAECgQJBAAAAA==.Liquid:BAABLgAECn8lAAIfAAgJhSMZBQDGAgAfAAgJhSMZBQDGAgAAAA==.Liraelie:BAAALgADCgEJAQAAAA==.Littlenewt:BAAALgADCgMJAwAAAA==.',
Lo='Loankano:BAABLgAECn8cAAIfAAgJ/godHgB6AQAfAAgJ/godHgB6AQAAAA==.Lockbealady:BAABLgAECn8XAAMKAAkJTAqTVACIAQAKAAkJTAqTVACIAQAJAAEJFgYAeQAqAAAAAA==.Lohanoa:BAAALgAECgEJAQAAAA==.Longshanke:BAAALgAECgEJAQAAAA==.Lorebeard:BAAALgAECgcJCwAAAA==.Loreix:BAAALgAECgYJEwAAAA==.Lothlórien:BAAALgADCggJDQAAAA==.Lozzo:BAAALgADCgYJCwAAAA==.',
Lr='Lrock:BAAALgADCgMJAgAAAA==.',
Lu='Luciferluxx:BAAALgAECgUJBQAAAA==.Lumena:BAAALgADCggJCAAAAA==.Luminai:BAABLgAECn8YAAIeAAgJmBrAEQBUAgAeAAgJmBrAEQBUAgAAAA==.Luminaris:BAAALgAECgEJAQAAAA==.Luminaugty:BAAALgADCgcJEwAAAA==.Lunalea:BAAALgADCgQJBAAAAA==.Lunarthas:BAAALgADCgkJEQAAAA==.Luvinez:BAAALgAECgEJBAAAAA==.Luvinz:BAABLgAECn8YAAIUAAYJ/xdtKQCTAQAUAAYJ/xdtKQCTAQAAAA==.Luxkilla:BAAALgADCgEJAQAAAA==.',
Ly='Lyllia:BAAALgADCgEJAQAAAA==.Lynchmeup:BAAALgADCgYJBgABLgAECggJKwAZAPscAA==.Lyrel:BAABLgAECn80AAIZAAkJuiOjAwA9AwAZAAkJuiOjAwA9AwAAAA==.Lyshara:BAAALgADCgEJAQAAAA==.',
['Lî']='Lîllîth:BAAALgADCgMJAwAAAA==.',
['Lü']='Lümen:BAAALgADCggJCAABLgADCggJCAAFAAAAAA==.',
Ma='Maarc:BAABLgAECn8oAAIRAAcJng/5XgBcAQARAAcJng/5XgBcAQAAAA==.Maddragon:BAAALgAECgYJCAAAAA==.Madfurion:BAAALgAECgUJCwAAAA==.Magebot:BAABLgAECn8hAAICAAgJZAlAgQBYAQACAAgJZAlAgQBYAQAAAA==.Maggotbag:BAAALgAECgQJBAAAAA==.Magistra:BAAALgADCgcJDwAAAA==.Majestic:BAACLgAFFH8ZAAICAAYJsRZnHgCpAQACAAYJsRZnHgCpAQAuAAQKfygAAgIACQmxHl4nANUCAAIACQmxHl4nANUCAAAA.Malizar:BAAALgADCgEJAQAAAA==.Malvenue:BAAALgAECgkJAgAAAA==.Malygor:BAAALgAECgUJCQAAAA==.Marly:BAAALgAECgYJDQAAAA==.Mauwy:BAABLgAECn8jAAMPAAkJbxM9HwAWAgAPAAkJbxM9HwAWAgAHAAUJmA2fcQDMAAAAAA==.Mayabutreeks:BAAALgAECgYJBwAAAA==.Mazzerine:BAAALgAECgQJBAAAAA==.',
Mc='Mcbeardface:BAABLgAECn8WAAMVAAcJ/hXiGwC3AQAVAAcJ/hXiGwC3AQAcAAEJAADnXABAAAAAAA==.Mcbullseye:BAAALgAECgUJBAAAAA==.',
Me='Meathole:BAAALgAECgMJBAAAAA==.Megacon:BAAALgAECgkJAgAAAA==.Megarah:BAAALgAECgQJBgAAAA==.Mental:BAAALgAECgEJAgAAAA==.Mepkaelpto:BAAALgAFFAQJBAABLgAFFAYJDgAZAF4LAA==.Mera:BAAALgAECgEJAQAAAA==.Mercury:BAABLgAECn8YAAIHAAgJaRdbIwANAgAHAAgJaRdbIwANAgAAAA==.Meretrix:BAABLgAECn8kAAIYAAgJkQfNjAA3AQAYAAgJkQfNjAA3AQAAAA==.Messatsu:BAABLgAECn8aAAMeAAcJaghjNAAOAQAeAAcJaghjNAAOAQAcAAYJCgR3TACuAAABLgAFFAQJDgAJAAIFAA==.Metanya:BAABLgAECn8cAAMWAAgJ/gpwFABAAQAWAAgJ/gpwFABAAQANAAMJHgPobwBfAAAAAA==.Mew:BAAALgAECgYJCgAAAA==.',
Mi='Miateh:BAAALgAECgYJEAAAAA==.Microdots:BAAALgADCgMJAwAAAA==.Midorí:BAAALgADCgYJBgAAAA==.Mimicme:BAABLgAECn8XAAIRAAgJkR04IwAsAgARAAgJkR04IwAsAgAAAA==.Minorie:BAAALgADCgIJAgAAAA==.Mitchell:BAABLgAECn8uAAIYAAgJ2A4qawB5AQAYAAgJ2A4qawB5AQAAAA==.Miwah:BAABLgAECn8ZAAICAAYJ8AWpywDZAAACAAYJ8AWpywDZAAAAAA==.',
Mj='Mjolnìr:BAAALgAECgMJDQAAAA==.',
Mo='Modeus:BAAALgADCgUJBgAAAA==.Modin:BAABLgAECn8dAAMIAAgJDxkaDgCzAQAIAAgJDxkaDgCzAQAYAAQJ3QPS/QCMAAAAAA==.Mogarr:BAABLgAECn8YAAMBAAgJbQ0eHABpAQABAAgJbQ0eHABpAQAEAAEJtA/qXwAxAAAAAA==.Mohgwyn:BAAALgADCgEJAQAAAA==.Momonk:BAAALgAECgIJAgABLgAECggJHQAIAA8ZAA==.Monkglein:BAABLgAECn80AAMTAAkJliInAwAYAwATAAkJliInAwAYAwAUAAMJBQfMbwBjAAAAAA==.Monkhei:BAAALgAECgQJBAABLgAECgkJLAAOAMYkAA==.Mooglewing:BAABLgAECn8XAAIgAAcJ/RUiCQCNAQAgAAcJ/RUiCQCNAQAAAA==.Moomoobrncow:BAABLgAECn8eAAIRAAgJjBXyOgDIAQARAAgJjBXyOgDIAQAAAA==.Moondream:BAABLgAECn81AAMRAAgJ1B5fHQBMAgARAAgJ1B5fHQBMAgADAAIJLgi4ewBVAAAAAA==.Moraz:BAAALgAECgUJCwAAAA==.Mordicanta:BAABLgAECn85AAIOAAkJvRckDQAIAgAOAAkJvRckDQAIAgAAAA==.Morphies:BAAALgADCgcJDQAAAA==.',
Mu='Muerr:BAABLgAECn8qAAIRAAkJQyLfBwD8AgARAAkJQyLfBwD8AgAAAA==.Muerrizond:BAAALgAECgYJEgABLgAECgkJKgARAEMiAA==.Muerrlin:BAABLgAECn8ZAAICAAYJkQ5NogAdAQACAAYJkQ5NogAdAQABLgAECgkJKgARAEMiAA==.Muggel:BAAALgADCgkJKwAAAA==.Muggruith:BAAALgADCgkJFgAAAA==.Mumraa:BAAALgAECgUJCQAAAA==.Mumrawr:BAAALgAECgEJAQAAAA==.Mushroohead:BAABLgAECn8fAAIPAAgJKhs6FwD/AQAPAAgJKhs6FwD/AQAAAA==.',
My='Mystbourn:BAAALgAECgEJAQAAAA==.Mysterbyrnes:BAAALgADCgYJEgAAAA==.Myykiel:BAABLgAECn8rAAQkAAgJGhixIwAfAQAZAAYJ5BY0YQBBAQAkAAUJPxmxIwAfAQAlAAYJnQxhEwAcAQAAAA==.',
Na='Nadravia:BAAALgAECgUJBQAAAA==.Naina:BAABLgAECn81AAMHAAgJbRllHQA0AgAHAAgJbRllHQA0AgAPAAUJmxF9PwAFAQAAAA==.Najaja:BAAALgAECgQJBAAAAA==.Nakona:BAAALgAECgIJAgABLgAECggJHgAZAB4HAA==.Nalera:BAAALgADCgEJAQABLgAECgkJRAASAAUlAA==.Nariely:BAAALgAECgYJCgAAAA==.Natacha:BAABLgAECn8UAAIZAAYJiAWupACuAAAZAAYJiAWupACuAAAAAA==.Native:BAAALgAECgUJCAAAAA==.Nayos:BAAALgADCgIJAgAAAA==.',
Ne='Necro:BAABLgAECn8yAAIOAAkJ4CLVBADBAgAOAAkJ4CLVBADBAgAAAA==.Neelothe:BAAALgAECgMJAwAAAA==.Neisa:BAAALgADCgIJAgAAAA==.Nekroz:BAAALgAECgEJAQAAAA==.Nelliel:BAAALgAECgcJEwAAAA==.Nephie:BAAALgAECgMJAwABLgAECgkJJQAkAIIeAA==.',
Ni='Nickodemus:BAAALgAECgIJAgAAAA==.Nienor:BAAALgADCgkJCQAAAA==.Nightle:BAAALgADCggJCwAAAA==.Nihil:BAABLgAECn8UAAIlAAcJ6xJ0EAAZAQAlAAcJ6xJ0EAAZAQABLgAECgkJMgAOAOAiAA==.Nikano:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.Ninmah:BAAALgADCgkJRQAAAA==.Niphredil:BAAALgAECgQJBQAAAA==.Nirø:BAABLgAECn8dAAITAAkJLwqKJgBUAQATAAkJLwqKJgBUAQAAAA==.',
No='Noah:BAAALgADCgcJDQAAAA==.Nooky:BAABLgAECn8oAAIUAAgJrB9vDACfAgAUAAgJrB9vDACfAgAAAA==.',
Nu='Nuatha:BAABLgAECn8dAAIRAAYJ3g0jewAaAQARAAYJ3g0jewAaAQAAAA==.Numpty:BAAALgAECgMJBgAAAA==.',
Ny='Nyctero:BAABLgAECn8eAAImAAgJlR9vBwAlAgAmAAgJlR9vBwAlAgAAAA==.Nyrikah:BAAALgADCggJDwAAAA==.',
['Nö']='Nöstrum:BAAALgADCgMJAwABLgAECgcJDAAFAAAAAA==.',
Ob='Obidiah:BAABLgAECn8uAAMCAAgJNBr4QgD3AQACAAgJNBr4QgD3AQAiAAEJThKYGgBDAAAAAA==.',
Oc='Ocnod:BAAALgAECgMJAwAAAA==.',
Od='Oddearth:BAAALgAECgMJAwAAAA==.',
Oe='Oedipus:BAAALgAECgMJAwAAAA==.',
Oh='Ohioaug:BAAALgADCgEJAQAAAA==.',
Or='Orah:BAABLgAECn8mAAINAAgJvhH/IwB8AQANAAgJvhH/IwB8AQAAAA==.Ordinance:BAAALgAECgEJAgAAAA==.Orpheon:BAAALgAECgQJCQAAAA==.',
Os='Osorn:BAAALgADCgkJCgAAAA==.',
Ot='Otterdoodad:BAAALgAECgQJBwAAAA==.',
Ou='Ouicau:BAAALgAECgcJBwAAAA==.',
Oz='Ozzmosis:BAAALgADCgMJAwAAAA==.',
Pa='Palagem:BAAALgADCgYJBgAAAA==.Palinyes:BAABLgAECn8jAAIIAAgJNSWRAgDcAgAIAAgJNSWRAgDcAgAAAA==.Pancetta:BAAALgADCgUJCAAAAA==.Pandabits:BAAALgAECgUJCgAAAA==.Pandussy:BAAALgAECgEJAQAAAA==.Papabill:BAABLgAECn87AAIYAAkJTxLNVACtAQAYAAkJTxLNVACtAQAAAA==.Papaharny:BAAALgAECgcJAwAAAA==.Paperscissor:BAAALgADCgIJAgAAAA==.Paragorn:BAABLgAECn8mAAIYAAgJfwmChQBDAQAYAAgJfwmChQBDAQAAAA==.Pasiphae:BAAALgADCgIJAgABLgAECgkJMwAUALEeAA==.Pattee:BAABLgAECn8oAAIDAAgJACLnAgCQAgADAAgJACLnAgCQAgAAAA==.',
Pe='Peachums:BAAALgADCgEJAQAAAA==.Pech:BAAALgAFFAIJAgAAAA==.Peenidin:BAABLgAECn8rAAIhAAkJ9CPrBgD8AgAhAAkJ9CPrBgD8AgAAAA==.Pemerd:BAABLgAECn8pAAINAAgJshzODwA7AgANAAgJshzODwA7AgAAAA==.Petite:BAAALgADCgMJAwAAAA==.Pewpewnotqq:BAAALgAECgkJAQABLgAECgkJJgASAJ4TAA==.',
Ph='Phoenixfires:BAAALgADCgYJCAAAAA==.Phoze:BAABLgAECn8nAAIIAAgJ/BnWCQABAgAIAAgJ/BnWCQABAgAAAA==.Phyai:BAABLgAECn8hAAICAAcJPxOieQBoAQACAAcJPxOieQBoAQAAAA==.',
Pi='Pirotanaxdos:BAABLgAECn8jAAIbAAgJkQWhDQAVAQAbAAgJkQWhDQAVAQAAAA==.Pizzarollzz:BAABLgAECn8kAAIRAAgJTA+kTwCFAQARAAgJTA+kTwCFAQAAAA==.',
Pn='Pnutt:BAAALgAECgQJBAAAAA==.',
Po='Pocadot:BAAALgAECgIJAgAAAA==.Pocco:BAAALgAECgEJAgAAAA==.Ponymalta:BAABLgAECn8oAAINAAgJZxhRGwApAgANAAgJZxhRGwApAgAAAA==.Popeaganda:BAAALgAECgQJBwAAAA==.Poutine:BAAALgAECgQJCwAAAA==.',
Pr='Priestglein:BAAALgAECgMJAwABLgAECgkJNAATAJYiAA==.Prizren:BAABLgAECn8ZAAIgAAYJ/RKDDABBAQAgAAYJ/RKDDABBAQAAAA==.Promethyus:BAABLgAECn8eAAMYAAgJNQZu1gDEAAAYAAgJNQZu1gDEAAAIAAUJwAFSOQBRAAAAAA==.Promidan:BAAALgAECgcJBwABLgAFFAQJEAAYAOUOAA==.Pryxi:BAABLgAECn8pAAICAAkJewdqcAB8AQACAAkJewdqcAB8AQAAAA==.',
Pu='Puffichu:BAAALgADCgMJAwABLgAECgMJAwAFAAAAAA==.Punchline:BAAALgADCgcJBwAAAA==.',
Py='Pyrogar:BAAALgADCgIJAgAAAA==.Pythius:BAAALgAECgYJBwAAAA==.',
['Pó']='Pótatò:BAABLgAECn8XAAIYAAYJnBdyeABdAQAYAAYJnBdyeABdAQAAAA==.',
Qi='Qiara:BAAALgAECgcJEwAAAA==.',
Qu='Quandaale:BAABLgAECn8WAAMMAAcJuxMjUgAkAQAMAAYJMxQjUgAkAQAXAAUJOBfgHwAKAQABLgAFFAIJAgAFAAAAAA==.Quell:BAAALgADCgEJAQAAAA==.Quepinga:BAAALgADCgUJCAAAAA==.Quiksylver:BAABLgAECn87AAMhAAkJIhpLIgDLAQAhAAgJGhlLIgDLAQAYAAcJ5xBUgQBLAQAAAA==.',
Ra='Rabblerousin:BAAALgAECgEJAgAAAA==.Radu:BAAALgAECgMJAwAAAA==.Raegnar:BAAALgADCgYJBgAAAA==.Raggnnar:BAAALgADCgEJAgAAAA==.Rainmakers:BAAALgAECgcJBQAAAA==.Rakael:BAAALgADCgMJAwAAAA==.Rantar:BAAALgADCgEJAQAAAA==.Ranum:BAAALgAECgYJBgABLgAECgkJEwAFAAAAAA==.Rava:BAAALgAECgEJAQAAAA==.',
Re='Rea:BAAALgAECgQJBAAAAA==.Reckoner:BAAALgAECgUJEAAAAA==.Red:BAABLgAECn84AAQaAAkJ2SNvEwC0AgAaAAkJkSJvEwC0AgAdAAcJZCOBCAC+AQAOAAcJzROSGwBOAQAAAA==.Rellster:BAAALgAECgUJCgAAAA==.Renix:BAAALgAECgQJBQAAAA==.Rennyo:BAABLgAECn8nAAMTAAkJMxkXFgDeAQATAAcJKRwXFgDeAQASAAgJVBNFKgC4AQAAAA==.Resonance:BAAALgAECgUJCAAAAA==.Retsu:BAAALgADCgUJBQAAAA==.Rettbull:BAAALgADCgMJAwAAAA==.Reyujin:BAAALgAECgEJBAAAAA==.',
Rh='Rhyash:BAABLgAECn8bAAIeAAYJDAeuPADcAAAeAAYJDAeuPADcAAAAAA==.',
Ri='Riaana:BAAALgADCgEJAQAAAA==.Rickdaddty:BAAALgAECgUJBQABLgAECggJIgAKAGkeAA==.Rickie:BAAALgADCgMJAwAAAA==.Ricoz:BAAALgAECgQJBQAAAA==.Ridicutie:BAABLgAECn8iAAIXAAgJWiBKBQCFAgAXAAgJWiBKBQCFAgAAAA==.Rigg:BAABLgAECn8rAAIZAAgJ+xz3HwA3AgAZAAgJ+xz3HwA3AgAAAA==.Riggz:BAAALgADCgQJBAABLgAECggJKwAZAPscAA==.Riggzbuffs:BAAALgADCggJCAABLgAECggJKwAZAPscAA==.Rivetro:BAAALgAECgQJCwAAAA==.',
Ro='Ro:BAAALgAECgMJAwAAAA==.Rocknroll:BAABLgAECn88AAIRAAkJcxwREwCeAgARAAkJcxwREwCeAgAAAA==.Roll:BAACLgAFFH8FAAIIAAIJORseCwCSAAAIAAIJORseCwCSAAAuAAQKfysAAggACQnWHlwFAHQCAAgACQnWHlwFAHQCAAAA.Rozgrez:BAABLgAECn8nAAQKAAkJhxxwLgAHAgAKAAkJ6xVwLgAHAgALAAQJXRpaEgAIAQAJAAUJxxVoEgD0AAAAAA==.',
Ru='Ruadun:BAAALgADCgEJAQAAAA==.Rufus:BAAALgADCgkJDgAAAA==.Rumlidorgah:BAABLgAECn8lAAQLAAgJFgz7DwApAQAKAAgJhAmdaQBSAQALAAYJjQr7DwApAQAJAAQJVQ3MHwCIAAAAAA==.Runem:BAAALgAECgMJBgAAAA==.Russbus:BAACLgAFFH8LAAIYAAQJ8wXNPgAKAQAYAAQJ8wXNPgAKAQAuAAQKfyEAAxgACQkeDstSALIBABgACQkeDstSALIBACEACAkRB/1cAAkBAAAA.Ruune:BAAALgAECgUJBwAAAA==.',
Ry='Rynmorelle:BAAALgAECgcJCgAAAA==.',
['Ré']='Réven:BAABLgAECn8lAAIZAAkJpBsOHABPAgAZAAkJpBsOHABPAgAAAA==.',
Sa='Sadiebella:BAAALgAECgYJCAAAAA==.Sadienna:BAABLgAECn8eAAMcAAkJhgYdKgBYAQAcAAkJhgYdKgBYAQAeAAgJXgWsRgAfAQAAAA==.Salvidali:BAAALgAECgMJBAABLgAECggJIAACAGEIAA==.Sandrï:BAABLgAECn8nAAQLAAgJFxLNCwBpAQALAAYJnxLNCwBpAQAKAAcJQA+PbQBJAQAJAAEJAABiRgAAAAAAAA==.Sane:BAABLgAECn8jAAIaAAkJVRXMMgAQAgAaAAkJVRXMMgAQAgAAAA==.Saoiirse:BAABLgAECn8pAAMZAAgJihXPQQChAQAZAAgJihXPQQChAQAkAAIJ1hPiQQBuAAAAAA==.Saraella:BAAALgAECggJAgAAAA==.Sasso:BAAALgADCgIJAgAAAA==.Sawako:BAABLgAECn8vAAIcAAkJKxuNDABnAgAcAAkJKxuNDABnAgAAAA==.',
Sc='Scalar:BAAALgADCgEJAQAAAA==.Scalyboi:BAAALgAECgIJAwABLgAFFAYJGQACALEWAA==.Scalycrit:BAAALgAECgQJBQABLgAECggJHAATAEkWAA==.Scarletts:BAAALgADCgUJBgABLgAECgUJBQAFAAAAAA==.Schlitzie:BAAALgADCgIJAgAAAA==.Scrapes:BAAALgADCgMJAwAAAA==.Scuba:BAAALgAECgYJCwAAAA==.',
Se='Searlock:BAAALgADCgYJBgAAAA==.Seraphyne:BAAALgAECgIJAgABLgAFFAcJIgAMACQdAA==.Sevencharlie:BAABLgAECn8iAAIYAAcJLQzdjQA1AQAYAAcJLQzdjQA1AQAAAA==.',
Sh='Shadowho:BAAALgAECgQJDQAAAA==.Shadowrican:BAAALgAECgUJBgAAAA==.Shaladro:BAAALgADCgUJCAAAAA==.Shalanaz:BAAALgAECgEJAQAAAA==.Shamiqua:BAAALgAECgYJBwAAAA==.Shamutty:BAAALgAECgMJBAABLgAFFAQJDgACAPQVAA==.Sharasdal:BAAALgAECgEJAQABLgAECggJAgAFAAAAAA==.Sherief:BAAALgADCgQJBAAAAA==.Shieldz:BAAALgAECgEJAQAAAA==.Shinjô:BAAALgAECgQJCwAAAA==.Shiroishi:BAAALgADCgcJBwABLgAECgcJJAAGAI8MAA==.Shivaray:BAAALgAECgcJAwAAAA==.Shiveria:BAAALgADCgYJCwAAAA==.Shocklesner:BAABLgAECn8VAAIPAAgJNBWNJQCQAQAPAAgJNBWNJQCQAQAAAA==.Shorkaan:BAAALgAECgEJAQAAAA==.Shouganai:BAABLgAECn8XAAIRAAcJMhIDYABZAQARAAcJMhIDYABZAQAAAA==.Shupas:BAAALgAECgcJAQAAAA==.Shupaz:BAAALgAECgUJBgAAAA==.',
Si='Siddha:BAAALgADCgYJBgABLgAECgYJDwAFAAAAAA==.Sieria:BAAALgAECgYJDQAAAA==.Sifu:BAAALgAECgcJCwAAAA==.Siieerr:BAACLgAFFH8MAAIWAAQJuxrfAwBYAQAWAAQJuxrfAwBYAQAuAAQKfxQAAxYACQnHIaIDAPYCABYACQnHIaIDAPYCAAwAAgksCkK+AEoAAAAA.Silvermind:BAAALgAECgcJEwAAAA==.Sinaar:BAAALgAECgIJAwAAAA==.Sindena:BAACLgAFFH8IAAIKAAMJSAgaaADGAAAKAAMJSAgaaADGAAAuAAQKfxwAAgoABwngFK1cALIBAAoABwngFK1cALIBAAAA.Sixsanity:BAAALgAECgUJCwAAAA==.',
Sk='Skavos:BAAALgAECgYJBwABLgAECgcJCAAFAAAAAA==.Skillcommand:BAAALgAECgQJCgAAAA==.Skipperino:BAAALgADCggJDQAAAA==.Skyemage:BAAALgAECgEJAgAAAA==.',
Sl='Sloked:BAAALgADCgEJAQAAAA==.Slokem:BAAALgAECgcJCQAAAA==.Slotz:BAABLgAECn83AAIhAAgJ5BmrHwDfAQAhAAgJ5BmrHwDfAQAAAA==.',
Sm='Smallcoomer:BAAALgAECggJEgAAAA==.Smallss:BAAALgAECgUJBgAAAA==.Smike:BAABLgAECn8yAAIYAAkJNwrdZQCEAQAYAAkJNwrdZQCEAQAAAA==.Smitepanda:BAAALgAECgEJAQAAAA==.',
Sn='Snappie:BAAALgAECgUJBQAAAA==.Sneeze:BAAALgAECgQJCQAAAA==.Snek:BAAALgAECgUJCQAAAA==.Snuggles:BAAALgADCgUJBwAAAA==.',
So='Soferan:BAABLgAECn8bAAIaAAYJjhxZdQCbAQAaAAYJjhxZdQCbAQAAAA==.Softpaws:BAAALgAECgEJAgAAAA==.Sonarr:BAAALgAECgUJCQAAAA==.Sosukeaizen:BAAALgAECgEJAQAAAA==.Sourdeizal:BAAALgADCgEJAQAAAA==.Sozzle:BAAALgAECgYJBgABLgAFFAYJGQACALEWAA==.',
Sp='Spacemilk:BAABLgAECn8UAAMVAAkJNwlUMQAWAQAVAAYJdAZUMQAWAQAcAAQJNAZ8TACtAAAAAA==.Spark:BAAALgAECgEJAQAAAA==.Spicymeat:BAAALgAECgUJBwABLgAFFAYJGQACALEWAA==.Sputty:BAABLgAECn8ZAAMcAAYJeBumIQCSAQAcAAYJeBumIQCSAQAeAAEJVh8LWABPAAABLgAFFAQJDgACAPQVAA==.',
Sq='Squishee:BAAALgAECgcJDgAAAA==.',
St='Stankmouth:BAABLgAECn8ZAAIUAAQJwwVUbQBqAAAUAAQJwwVUbQBqAAAAAA==.Stanktoe:BAAALgADCgEJAQAAAA==.Stellas:BAAALgAECgYJBgABLgAECgkJGAAnAMEKAA==.Stesha:BAAALgAECgYJBgABLgAECggJHgAZAB4HAA==.Steviewonder:BAABLgAECn8nAAIZAAgJjxXfQgCdAQAZAAgJjxXfQgCdAQAAAA==.Stinkerton:BAABLgAFFH8HAAIVAAQJQCERFACBAQAVAAQJQCERFACBAQAAAA==.Stonedfrog:BAAALgADCggJDwAAAA==.Stonefather:BAABLgAECn8kAAIUAAgJewxFOQA1AQAUAAgJewxFOQA1AQAAAA==.Stonewall:BAAALgADCgEJAgAAAA==.Strangelets:BAAALgAECgQJBQAAAA==.Strangewayes:BAAALgADCgMJAwAAAA==.Stïtches:BAABLgAECn8gAAMaAAgJVAzddABUAQAaAAgJVAzddABUAQAOAAYJYARKNwCKAAAAAA==.Stönk:BAABLgAECn8rAAIJAAgJMBVfBwCwAQAJAAgJMBVfBwCwAQAAAA==.',
Su='Succulentman:BAACLgAFFH8GAAIZAAIJPSQWTwDMAAAZAAIJPSQWTwDMAAAuAAQKfy4AAhkACAkcIycWAHUCABkACAkcIycWAHUCAAAA.Sufferyn:BAAALgADCgcJBwAAAA==.Sunreaver:BAAALgADCgYJCgAAAA==.Supoz:BAAALgAECgEJAQAAAA==.Surolath:BAABLgAECn8xAAIXAAkJph68AwC+AgAXAAkJph68AwC+AgAAAA==.Suvaun:BAAALgAECgEJAQAAAA==.',
Sw='Swaggles:BAABLgAECn85AAInAAkJhyTOAQAkAwAnAAkJhyTOAQAkAwAAAA==.Swatguymg:BAAALgADCgQJBAAAAA==.Swiftcast:BAAALgAECgYJBgAAAA==.Swiftpalms:BAAALgAECgcJDgAAAA==.Swompfox:BAABLgAECn8aAAIRAAgJFAkzXABjAQARAAgJFAkzXABjAQAAAA==.',
Sy='Sygon:BAABLgAECn8wAAIDAAkJyBj1BQAUAgADAAkJyBj1BQAUAgAAAA==.Sylenceikilu:BAAALgADCgEJAQAAAA==.Sylvannaa:BAAALgAECgYJCgAAAA==.Syntherizena:BAAALgAECgYJCQAAAA==.Synthesized:BAAALgAECgcJEwAAAA==.',
['Só']='Sóng:BAABLgAECn8aAAMeAAcJLh3eEwBAAgAeAAcJLh3eEwBAAgAcAAEJSQ7wXgA7AAAAAA==.',
Ta='Tacitus:BAABLgAECn8oAAIQAAgJyxN8JQCmAQAQAAgJyxN8JQCmAQAAAA==.Tairrad:BAAALgAECgYJCAAAAA==.Takeru:BAAALgAECgMJBQAAAA==.Talasmar:BAAALgAECgQJBQAAAA==.Tapkar:BAAALgADCgYJBgAAAA==.Tapkora:BAAALgAECgQJCAAAAA==.Tapsum:BAAALgADCgUJBQAAAA==.Tarirn:BAAALgADCgEJAQAAAA==.Taurtem:BAAALgAECgQJBQAAAA==.Taylia:BAAALgAECgQJDAABLgAECgkJIQAVAKMUAA==.Tayona:BAAALgAECgIJAgAAAA==.Tazildek:BAAALgAECgEJAQAAAA==.',
Te='Technique:BAABLgAECn8UAAIcAAkJjBZrGwDDAQAcAAkJjBZrGwDDAQAAAA==.Tergrid:BAAALgAECgMJAwAAAA==.Terial:BAABLgAECn8qAAIhAAgJyiKKCQDNAgAhAAgJyiKKCQDNAgAAAA==.Textoffender:BAAALgAECgQJBgAAAA==.',
Th='Thajeebus:BAAALgADCgEJAQAAAA==.Thatsneat:BAAALgAECgQJBQAAAA==.Thecapt:BAABLgAECn8nAAIQAAkJFhulEwAwAgAQAAkJFhulEwAwAgAAAA==.Theôdöræ:BAABLgAECn8cAAIkAAgJUA3xHABXAQAkAAgJUA3xHABXAQAAAA==.Thorinfel:BAABLgAECn8hAAIZAAkJ1xR7NgAdAgAZAAkJ1xR7NgAdAgAAAA==.Thsaemage:BAAALgAECgQJBAABLgAFFAIJBgANAA8aAA==.Thunderkiss:BAAALgAECgYJBgAAAA==.Thunran:BAAALgAECgQJBgAAAA==.',
Ti='Tiaoma:BAAALgAECgEJAQAAAA==.Tiarlena:BAAALgAECgEJAQAAAA==.Tieria:BAABLgAECn8rAAIcAAgJ2SAkCgCLAgAcAAgJ2SAkCgCLAgAAAA==.Tikao:BAABLgAECn80AAMlAAkJvw5vDQBNAQAlAAkJvw5vDQBNAQAkAAYJpAVlQwDqAAAAAA==.Tinna:BAAALgAECgcJBgAAAA==.',
Tj='Tjhookèr:BAABLgAECn8UAAIHAAYJ1SChIwALAgAHAAYJ1SChIwALAgAAAA==.',
To='Tobajal:BAABLgAECn8wAAIeAAkJLSGeAwA3AwAeAAkJLSGeAwA3AwAAAA==.Toletheus:BAABLgAECn8sAAQWAAkJFhvmCAAIAgAWAAgJ+BjmCAAIAgANAAgJBhPeHgCiAQAXAAEJyyW4OwBrAAAAAA==.Tomin:BAABLgAECn8mAAIYAAgJdSSYDQDeAgAYAAgJdSSYDQDeAgAAAA==.Totemique:BAAALgADCgcJDgABLgAECgkJFAAcAIwWAA==.Totumfknpole:BAAALgADCgEJAQAAAA==.',
Tr='Treeperson:BAABLgAECn8rAAIMAAgJmiMqCAAbAwAMAAgJmiMqCAAbAwAAAA==.Trevelyan:BAAALgADCgEJAQABLgAECggJJgAYAHUkAA==.Treyni:BAAALgADCgIJAgAAAA==.Trickyric:BAAALgAECgUJCwAAAA==.Trilgy:BAAALgADCgkJCgAAAA==.Trinak:BAAALgAECgMJAwAAAA==.Trowel:BAABLgAECn8dAAINAAcJlx+bGQA6AgANAAcJlx+bGQA6AgABLgAFFAQJDgACAPQVAA==.',
Ts='Tsuyoimono:BAABLgAECn8aAAMEAAgJRglbIQAqAQAEAAgJRglbIQAqAQAQAAQJxATqgwCvAAAAAA==.',
Tu='Tubkins:BAAALgADCgkJCQAAAA==.Turisx:BAAALgADCgQJBQAAAA==.Turtleclap:BAAALgAECgYJCgAAAA==.',
Tw='Twiddydh:BAAALgAECgYJEAAAAA==.Twistandgrip:BAAALgAECgcJAgAAAA==.Twylan:BAAALgAECgEJAQAAAA==.',
Ty='Tydroin:BAAALgADCgMJAwAAAA==.Tylan:BAAALgADCgMJAwAAAA==.Tytoalba:BAABLgAFFH8GAAMhAAMJ+BXoIQDiAAAhAAMJ+BXoIQDiAAAYAAIJxgBUfQBjAAAAAA==.',
Uk='Ukiru:BAAALgADCgMJAwAAAA==.',
Ul='Ulfarr:BAAALgAECgcJBwAAAA==.',
Un='Ungonelilith:BAAALgADCgkJGAAAAA==.Unicrom:BAAALgAECgkJDAAAAA==.',
Ur='Uratsukasama:BAABLgAECn8YAAIYAAYJ/Qs6qwAEAQAYAAYJ/Qs6qwAEAQAAAA==.Urion:BAABLgAECn8bAAQnAAgJNhycEgD5AQAnAAgJ0xqcEgD5AQARAAMJsh/PlwCmAAADAAEJ7Q4piQAyAAAAAA==.',
Va='Vacaite:BAAALgAECgIJAwAAAA==.Vagiant:BAABLgAECn8fAAIWAAgJjxXqDwCBAQAWAAgJjxXqDwCBAQAAAA==.Valyna:BAAALgADCgEJAQAAAA==.Vampirica:BAAALgAECgkJCAAAAA==.Vanya:BAABLgAECn8nAAMRAAgJeSKZEwCLAgARAAgJZSKZEwCLAgAnAAYJfxiiDgDdAQAAAA==.Vash:BAAALgADCgYJBgABLgAECgkJGAAnAMEKAA==.Vasso:BAAALgAECgQJBgAAAA==.',
Ve='Velinae:BAAALgAECgkJBgAAAA==.Velint:BAAALgAECgEJAQAAAA==.Velveen:BAABLgAECn8wAAMPAAkJEBVKIgCmAQAPAAgJchVKIgCmAQAHAAIJzAndkgBnAAAAAA==.Verickk:BAAALgAECgEJAQAAAA==.Vexxia:BAAALgAECggJCQAAAA==.',
Vi='Viallure:BAAALgAECgcJDQABLgAECgkJGAAGABMVAA==.Vilebloom:BAEBLgAECn8mAAIMAAgJryCvCwDmAgAMAAgJryCvCwDmAgAAAA==.Vilesilencer:BAEALgAECgQJBAABLgAECggJJgAMAK8gAA==.Viridius:BAAALgAECgUJEgAAAA==.Vitamind:BAAALgADCgEJAQAAAA==.',
Vo='Voidmulan:BAAALgAECgEJAQAAAA==.Voluga:BAAALgAECgEJAQAAAA==.Vonmortis:BAAALgADCgkJFwAAAA==.',
Wa='Wagguslight:BAABLgAECn8pAAIYAAcJVRGkfQBSAQAYAAcJVRGkfQBSAQAAAA==.Warzak:BAABLgAECn8UAAIQAAcJqxYkLgByAQAQAAcJqxYkLgByAQABLgAECggJDAAFAAAAAA==.Wayne:BAAALgADCgUJBQAAAA==.',
We='Wendybacon:BAABLgAECn8cAAIZAAgJCRYXTAB/AQAZAAgJCRYXTAB/AQAAAA==.',
Wh='Whateverdude:BAAALgAECgQJCQAAAA==.Whiskeyshots:BAAALgADCgIJAgAAAA==.Whytè:BAABLgAECn8vAAIMAAkJ1iDmBQBBAwAMAAkJ1iDmBQBBAwAAAA==.',
Wi='Wigeon:BAAALgADCggJCAABLgAECggJGwAIADMVAA==.Wiickett:BAABLgAECn8fAAMbAAgJtB2/BAC5AgAbAAgJcx2/BAC5AgAjAAYJrh+UIwChAQAAAA==.Wilbur:BAAALgAECgQJCgAAAA==.Wildebeard:BAACLgAFFH8NAAIhAAQJRSRnDgCSAQAhAAQJRSRnDgCSAQAuAAQKfygAAiEACQmeJDoFABgDACEACQmeJDoFABgDAAAA.Wildeshock:BAAALgAECgEJAQABLgAFFAQJDQAhAEUkAA==.Wilferal:BAAALgAECgQJBAAAAA==.Willaá:BAABLgAECn8kAAIaAAgJrAtxagBsAQAaAAgJrAtxagBsAQAAAA==.Willowyn:BAABLgAECn8yAAMUAAkJ5BbrGQAJAgAUAAkJ5BbrGQAJAgATAAkJXREtGgC0AQAAAA==.Wingmans:BAAALgAECgQJBwAAAA==.Wizzpeaver:BAABLgAECn8WAAIUAAgJYQ5gLwBtAQAUAAgJYQ5gLwBtAQAAAA==.',
Wo='Wonderwizard:BAABLgAECn8hAAICAAgJ3hEkZgCUAQACAAgJ3hEkZgCUAQAAAA==.Wonglow:BAAALgAECgYJBgAAAA==.',
Wr='Wraeth:BAAALgADCgYJBgAAAA==.Wrathhoof:BAAALgAECgkJEwAAAA==.',
Xa='Xahra:BAAALgADCgcJBwAAAA==.Xaralyss:BAAALgAECgQJBwAAAA==.',
Xh='Xhine:BAAALgAECgEJAgAAAA==.',
Xi='Xin:BAAALgAECgcJEwAAAA==.',
Xy='Xylias:BAAALgADCggJGAAAAA==.',
Ya='Yamon:BAAALgADCggJEAAAAA==.',
Yo='Yodef:BAACLgAFFH8RAAMaAAUJPhb5QwA+AQAaAAQJPhb5QwA+AQAOAAEJAAAoRgAAAAAuAAQKfyEAAhoACAnmIwgYAJUCABoACAnmIwgYAJUCAAAA.Yodelnir:BAAALgAECgYJBgABLgAFFAUJEQAaAD4WAA==.Yorri:BAAALgAECgMJAwAAAA==.Yorril:BAAALgAECgcJBwAAAA==.',
Yu='Yucca:BAACLgAFFH8IAAMOAAMJwA4fJAB8AAAaAAIJ0gs6rACPAAAOAAIJew8fJAB8AAAuAAQKfzUAAxoACQmMGG4sACsCABoACQmMGG4sACsCAA4ABAmdBkZAAF4AAAAA.Yuda:BAAALgAECgEJBgABLgAECgEJAgAFAAAAAA==.Yudaneyo:BAAALgAECgEJBgABLgAECgEJAgAFAAAAAA==.Yukiteru:BAABLgAECn8wAAMZAAkJmB7PEQCXAgAZAAkJmB7PEQCXAgAkAAIJ2xVvQAB1AAAAAA==.Yurito:BAABLgAECn8sAAIcAAgJnxrkEwAMAgAcAAgJnxrkEwAMAgAAAA==.',
Yz='Yzernara:BAAALgAECgEJAQABLgAECggJAgAFAAAAAA==.',
Za='Zabrina:BAABLgAECn8eAAIZAAgJHgetewABAQAZAAgJHgetewABAQAAAA==.Zaiel:BAAALgADCgMJAwAAAA==.Zakutin:BAAALgAECggJDAAAAA==.Zappybains:BAABLgAECn85AAIHAAkJeyClBwAPAwAHAAkJeyClBwAPAwAAAA==.Zarakii:BAABLgAECn8dAAIRAAcJ/SAOMwDmAQARAAcJ/SAOMwDmAQAAAA==.',
Ze='Zekken:BAAALgADCgMJBAAAAA==.Zelaina:BAABLgAECn8UAAIYAAcJ8hYaZACIAQAYAAcJ8hYaZACIAQAAAA==.',
Zi='Zi:BAAALgADCgQJBQABLgAECgkJRAASAAUlAA==.',
Zu='Zuda:BAAALgAECgEJBgABLgAECgEJAgAFAAAAAA==.Zupaz:BAAALgADCgEJAQAAAA==.',
Zy='Zylluz:BAAALgAECgkJEQAAAA==.Zylos:BAAALgAECgYJEwAAAA==.Zyphros:BAAALgAFFAEJAQAAAA==.',
['Zì']='Zìnn:BAAALgAECgIJAgAAAA==.',
['Äs']='Äshébringer:BAACLgAFFH8NAAIYAAUJyxx0CABuAQAYAAUJyxx0CABuAQAuAAQKfyMAAhgACQlNJOsHAFYDABgACQlNJOsHAFYDAAAA.Ästen:BAAALgAECgIJAgAAAA==.',
['Æt']='Æthelred:BAAALgAECgEJAQABLgAECgcJFwANAHwaAA==.',
['Ðr']='Ðragøn:BAAALgAECgcJDAAAAA==.',
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
