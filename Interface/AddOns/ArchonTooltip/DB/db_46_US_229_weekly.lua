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

local lookup = {'Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Devourer','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Warrior-Protection','Druid-Feral','Priest-Holy','Mage-Frost','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','Mage-Fire','DemonHunter-Havoc','Warlock-Affliction','Mage-Arcane','Monk-Brewmaster','Warrior-Arms',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-05-17',data={Ab='Abmikaze:BAAALgAECgkJDAAAAA==.Abor:BAAALgADCgMJAwAAAA==.',
Ad='Adimus:BAAALgADCgIJAgAAAA==.Adorean:BAABLgAECn8oAAIBAAgJ9hyfJgArAgABAAgJ9hyfJgArAgAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn8fAAIBAAcJRxumSgCrAQABAAcJRxumSgCrAQAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAABLgAECn8XAAIBAAYJxA/okAATAQABAAYJxA/okAATAQAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alaileath:BAAALgADCgEJAQAAAA==.Alburm:BAABLgAECn8aAAMCAAgJBSFVFwCDAgACAAgJBSFVFwCDAgADAAEJHwquJAAxAAAAAA==.Alexstraxsa:BAAALgADCgkJLQAAAA==.Aliine:BAABLgAECn8mAAIEAAgJChOiFgBnAQAEAAgJChOiFgBnAQAAAA==.Ally:BAAALgAECgMJBAABLgAECgcJIAAFAIkhAA==.Althaea:BAABLgAECn8VAAIGAAgJ0wGDSgCTAAAGAAgJ0wGDSgCTAAAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAACLgAFFH8HAAIHAAIJNQ/KKgCTAAAHAAIJNQ/KKgCTAAAuAAQKfzgAAgcACQl3IJ4IAJkCAAcACQl3IJ4IAJkCAAAA.',
An='Anahana:BAAALgAECgYJDQAAAA==.Anali:BAAALgADCggJGAAAAA==.Andi:BAAALgAECgcJEAAAAA==.Andorelia:BAABLgAECn8cAAIBAAkJtwz0UwCRAQABAAkJtwz0UwCRAQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAAALgAECgcJDQAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAYJFQAIAGUlAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAAALgAECgcJEgAAAA==.Appleborne:BAAALgADCgcJBwABLgAECgYJBgAJAAAAAA==.Appleseed:BAAALgADCgMJBQABLgAECgYJBgAJAAAAAA==.Apprentice:BAABLgAECn8kAAIKAAgJDQIPJgCfAAAKAAgJDQIPJgCfAAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCgAAAA==.Aramos:BAABLgAECn8wAAILAAkJuxncEQBFAgALAAkJuxncEQBFAgAAAA==.Aramôs:BAABLgAECn8aAAILAAcJYhIlKwB3AQALAAcJYhIlKwB3AQAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDAAJAAAAAA==.Arta:BAABLgAECn8aAAIMAAcJixjIEwBuAQAMAAcJixjIEwBuAQAAAA==.Artachoke:BAAALgAECgMJAwAAAA==.Aruncusdio:BAABLgAECn8cAAINAAgJbAZRFgANAQANAAgJbAZRFgANAQAAAA==.',
As='Ashhealz:BAABLgAECn8lAAIOAAgJThIkGwCyAQAOAAgJThIkGwCyAQAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgUJBgAAAA==.',
At='Atelwen:BAAALgAECgYJEwAAAA==.',
Av='Aveme:BAABLgAECn8wAAIPAAkJCiOVEQDBAgAPAAkJCiOVEQDBAgAAAA==.',
Aw='Awartedpeen:BAABLgAECn8ZAAIQAAcJbAv8XwDeAAAQAAcJbAv8XwDeAAAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAAJAAAAAA==.Aznarak:BAAALgAECgYJBgAAAA==.Azuleon:BAABLgAECn8aAAMRAAkJghRXHQDwAQARAAYJ6B1XHQDwAQASAAkJNA3YJACHAQAAAA==.Azuresky:BAAALgADCgEJAQAAAA==.',
Ba='Badsnapple:BAAALgAECgYJBgAAAA==.Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgAECgUJBQAAAA==.Balbit:BAAALgADCgQJBAAAAA==.Bamber:BAAALgADCggJDQAAAA==.Bast:BAAALgAECgEJAgAAAA==.Battar:BAAALgAECgEJAgAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn8vAAMTAAkJ2hktEgACAgATAAkJJhgtEgACAgAUAAYJ+hC3HQDxAAAAAA==.Beakerstime:BAAALgAECgIJAwAAAA==.Beastmode:BAABLgAECn8sAAIQAAkJaxtrEQCLAgAQAAkJaxtrEQCLAgAAAA==.Bedlem:BAABLgAECn8bAAICAAcJywgliAAbAQACAAcJywgliAAbAQAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwAJAAAAAA==.Bernard:BAABLgAECn8kAAMVAAgJRQaFXwAOAQAVAAgJRQaFXwAOAQAHAAYJBwlTRgDRAAAAAA==.',
Bi='Bidoof:BAABLgAECn8gAAMWAAcJGhf3DADFAQAWAAcJGhf3DADFAQAXAAYJQw9tOQAOAQAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAABLgAECn8dAAMYAAcJgQr9XQBCAQAYAAcJgQr9XQBCAQAZAAYJnAFjawCRAAAAAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJJwAOAFUaAA==.Blackgrace:BAAALgAECggJDQAAAA==.Blacklisted:BAABLgAECn8nAAMOAAkJVRqFCgCAAgAOAAkJVRqFCgCAAgAaAAEJgwrkXAAuAAAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgADCggJCgAAAA==.Blessurheart:BAAALgADCgIJAgAAAA==.Bloodybloodz:BAAALgAECgUJCAABLgAECggJEwAJAAAAAA==.Bloodyburst:BAAALgAECgEJAQABLgAECggJEwAJAAAAAA==.Bloodyfistz:BAAALgAECggJEwAAAA==.Blueshift:BAABLgAECn8WAAIFAAkJChc+QwDnAQAFAAkJChc+QwDnAQAAAA==.Bluethreetwo:BAAALgAECgYJEwAAAA==.Blurry:BAAALgADCgUJBgAAAA==.',
Bo='Bookofzeref:BAABLgAECn8UAAIbAAgJVxIYVQBsAQAbAAgJVxIYVQBsAQAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAABLgAECn8aAAIcAAYJGhysCwBVAQAcAAYJGhysCwBVAQAAAA==.Brayend:BAABLgAECn8XAAIdAAcJyBVXDgBuAQAdAAcJyBVXDgBuAQAAAA==.Brewbelly:BAAALgADCgcJCQAAAA==.Brimscythe:BAABLgAECn8tAAIeAAkJWx77AQCEAgAeAAkJWx77AQCEAgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.Bulish:BAAALgADCgMJAwAAAA==.',
Ca='Caliandis:BAAALgAECgcJEgAAAA==.Calvey:BAAALgAECgQJCQAAAA==.Cambrai:BAABLgAECn8WAAIRAAcJ5BB6JQBBAQARAAcJ5BB6JQBBAQAAAA==.Cannabelle:BAACLgAFFH8FAAIfAAMJxRXoGgClAAAfAAMJxRXoGgClAAAuAAQKfzgAAh8ACQlAJTQBADUDAB8ACQlAJTQBADUDAAAA.Canto:BAAALgAECgQJBAAAAA==.Captpickle:BAAALgAECgcJBwAAAA==.Carclias:BAABLgAECn8aAAMgAAkJbxouBwBXAgAgAAgJdxsuBwBXAgAbAAMJ5glb7ABIAAAAAA==.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAAALgAECgYJEgAAAA==.Catmove:BAAALgAECgUJBQAAAA==.Cattlerage:BAAALgAECgYJBgAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.',
Ch='Chaoscookies:BAABLgAECn8vAAMgAAkJWRcQHgBfAQAgAAUJtBkQHgBfAQAbAAUJgxT2dAAiAQAAAA==.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAAALgAECgYJEQAAAA==.Cheechee:BAAALgAECgYJEAAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8bAAIQAAcJKBTUNACMAQAQAAcJKBTUNACMAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAFFAUJEAAHAHoTAA==.',
Ci='Ciená:BAAALgAECgQJBQAAAA==.Cin:BAAALgAECgcJEQAAAA==.Cinderpetal:BAAALgAECgQJBQAAAA==.',
Co='Comlock:BAAALgAECgYJEwAAAA==.Complacent:BAABLgAECn8oAAIUAAgJtwE2MgBtAAAUAAgJtwE2MgBtAAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgQJBQAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAAALgAECgcJEgAAAA==.Crownman:BAAALgADCgYJDgAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuddilz:BAABLgAECn8cAAMhAAcJeBhaDAAuAQAiAAcJ/xOIIQA4AQAhAAYJ3RJaDAAuAQAAAA==.Cursedchild:BAAALgAFFAEJAQAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8oAAIbAAgJnB50HQBBAgAbAAgJnB50HQBBAgAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAABLgAECn85AAIEAAkJThx/BwBlAgAEAAkJThx/BwBlAgAAAA==.',
['Cé']='Cécé:BAABLgAECn8oAAIBAAcJJCM0HgBYAgABAAcJJCM0HgBYAgAAAA==.',
Da='Daciana:BAABLgAECn8aAAIYAAcJth83KAD6AQAYAAcJth83KAD6AQAAAA==.Dagaroonie:BAAALgAECgcJCwAAAA==.Dagevas:BAABLgAECn8lAAIbAAkJ1BLeNgDKAQAbAAkJ1BLeNgDKAQAAAA==.Darkeznite:BAABLgAECn8YAAIYAAgJghfpMwDIAQAYAAgJghfpMwDIAQAAAA==.Darksoldier:BAAALgAFFAMJBAAAAA==.Dartoy:BAABLgAECn8vAAIjAAkJHwi2KAB2AQAjAAkJHwi2KAB2AQAAAA==.Davriell:BAAALgAECgcJDQAAAA==.Dax:BAABLgAECn8XAAIYAAYJrhlyUwBfAQAYAAYJrhlyUwBfAQAAAA==.Dazling:BAAALgAECgcJCgAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAABLgAECn8VAAIgAAYJSh+8BgCmAQAgAAYJSh+8BgCmAQAAAA==.Deeppurple:BAABLgAECn8UAAIkAAYJBglbBgD3AAAkAAYJBglbBgD3AAAAAA==.Deezmons:BAABLgAECn8iAAIlAAgJhRCVGABjAQAlAAgJhRCVGABjAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn8vAAIcAAkJSiYcAAB1AwAcAAkJSiYcAAB1AwAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgQJBgAAAA==.Demonkirby:BAAALgADCgUJBQAAAA==.Demonlarrik:BAAALgAECgEJAQAAAA==.Derale:BAABLgAECn8aAAMXAAgJiw0EJgCNAQAXAAgJiA0EJgCNAQAeAAcJXQQyIgAZAQAAAA==.Destoroyah:BAAALgADCgQJBAAAAA==.',
Dh='Dhargal:BAACLgAFFH8FAAIHAAMJ6BhIHgDnAAAHAAMJ6BhIHgDnAAAuAAQKfzQAAgcACQmwIwIEAPsCAAcACQmwIwIEAPsCAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAABLgAECn8WAAIQAAYJGQO3eACWAAAQAAYJGQO3eACWAAAAAA==.',
Dk='Dkfaros:BAABLgAECn8dAAICAAkJdx9EEgCmAgACAAkJdx9EEgCmAgAAAA==.',
Do='Donko:BAAALgADCggJCAABLgAECgQJCAAJAAAAAA==.Dontcarebear:BAABLgAECn8UAAIUAAYJGQWQMAB2AAAUAAYJGQWQMAB2AAAAAA==.Doofnshmirtz:BAABLgAECn8vAAIdAAkJ3xzrAwB5AgAdAAkJ3xzrAwB5AgAAAA==.Dorkwiz:BAAALgADCgMJAwAAAA==.Dorow:BAAALgAECggJEAAAAA==.Dotpocket:BAABLgAECn8jAAIbAAgJ+BYnOgC+AQAbAAgJ+BYnOgC+AQAAAA==.',
Dr='Dragonash:BAAALgADCgEJAQAAAA==.Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECggJDwAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dremmy:BAAALgAECgYJEQAAAA==.Drey:BAAALgADCgEJAQAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAABLgAECn8oAAIdAAgJ/CCbBABfAgAdAAgJ/CCbBABfAgAAAA==.',
Du='Dunsel:BAAALgAECgcJCwABLgAECgkJLQAeAFseAA==.Dunwich:BAAALgADCgcJIAAAAA==.',
Dv='Dvali:BAAALgAECgcJDQAAAA==.',
Dy='Dyorra:BAABLgAECn8aAAMBAAYJ1ARiwQDFAAABAAYJ1ARiwQDFAAALAAUJNAYKTwC0AAAAAA==.',
Eb='Ebonshade:BAAALgAECgMJBgAAAA==.',
Ed='Edgardapoe:BAAALgAECgIJAgABLgAECgUJBgAJAAAAAA==.Edginglord:BAAALgAECgYJBwAAAA==.',
Eh='Ehmill:BAABLgAECn8nAAICAAkJpBkIHwBVAgACAAkJpBkIHwBVAgAAAA==.',
El='Elesrya:BAAALgAECgEJAQABLgAECgcJHwABAEcbAA==.Elgringo:BAAALgAECgcJAQAAAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAAALgAECgYJBgAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgcJAQABLgAECgcJAQAJAAAAAA==.',
Er='Ernest:BAAALgADCgUJCQAAAA==.Errani:BAAALgAECgYJEAAAAA==.',
Es='Eskers:BAABLgAECn8UAAIeAAgJxhpqBAD5AQAeAAgJxhpqBAD5AQAAAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8nAAIFAAkJwQ3yRgBxAQAFAAkJwQ3yRgBxAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8bAAIPAAcJKgLB1gCtAAAPAAcJKgLB1gCtAAAAAA==.Evocane:BAAALgAECgYJDAAAAA==.Evocati:BAAALgAECgUJBQABLgAFFAUJDAABABYaAA==.Evocatis:BAACLgAFFH8MAAMBAAUJFhrLIABFAQABAAUJFhrLIABFAQALAAEJRAuXOQA2AAAuAAQKfyUAAwEACQkZITUeALYCAAEACAl5IzUeALYCAAsAAwkOCxF2AKIAAAAA.Evoorc:BAAALgAECggJDwAAAA==.',
Ex='Ex:BAABLgAECn8jAAIgAAgJqAzbDAAsAQAgAAgJqAzbDAAsAQAAAA==.',
Fa='Faasht:BAAALgAECgEJAQAAAA==.Faoris:BAAALgADCgMJAwAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Feebs:BAAALgADCgIJAgAAAA==.Felheart:BAAALgAECgEJAQABLgAFFAMJCQABALgUAA==.Felzbirt:BAAALgADCgYJCwAAAA==.Fenehdis:BAAALgAECgcJDQAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgADCgEJAgABLgAECggJGwAFAPALAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAUJDAAQAKESAA==.Firebirdz:BAACLgAFFH8MAAIQAAUJoRLEEgBwAQAQAAUJoRLEEgBwAQAuAAQKfycAAxAACQnVIbAIAAMDABAACQnVIbAIAAMDABMACAnQFi8UAOoBAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAUJDAAQAKESAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzystomps:BAAALgAECgEJAwAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Frostypaw:BAAALgADCgYJCgAAAA==.Frostzilla:BAAALgADCggJEwAAAA==.',
Fu='Fuzzybut:BAABLgAECn8bAAIUAAYJIBphEwBcAQAUAAYJIBphEwBcAQAAAA==.',
Ga='Gandalph:BAAALgAECgMJAwAAAA==.Gark:BAAALgAECgYJDQAAAA==.Garkk:BAAALgADCgcJDwAAAA==.Gazzi:BAAALgAECgkJEgAAAA==.',
Gi='Gióvanna:BAAALgAECgQJBAAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECgYJFwAmADEfAA==.',
Go='Goblndeznutz:BAAALgAECgEJAQAAAA==.Goobow:BAACLgAFFH8KAAICAAMJQhWPZADyAAACAAMJQhWPZADyAAAuAAQKfzMAAgIACQnxGbAhAEcCAAIACQnxGbAhAEcCAAAA.Goodheavens:BAAALgAECgQJBwAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJBAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8lAAIPAAkJ9Q3NdwDiAQAPAAkJ9Q3NdwDiAQAAAA==.',
Gr='Gr:BAABLgAECn8ZAAIQAAcJThYuLgCwAQAQAAcJThYuLgCwAQAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8kAAIUAAgJwxl1CQD4AQAUAAgJwxl1CQD4AQAAAA==.Grody:BAAALgADCgYJBgAAAA==.Grumpias:BAAALgAECgUJBgABLgAECgkJJAANAP0bAA==.',
Gu='Guroo:BAABLgAECn8tAAIYAAkJ4RJBLwDbAQAYAAkJ4RJBLwDbAQAAAA==.',
['Gá']='Gárp:BAAALgAECgcJCwAAAA==.',
['Gø']='Gødoth:BAABLgAECn8iAAMHAAgJYSCaDgBCAgAHAAgJYSCaDgBCAgAVAAUJECLzOwCSAQAAAA==.',
Ha='Hagarn:BAABLgAECn8zAAIBAAkJDBadKAAiAgABAAkJDBadKAAiAgAAAA==.Haithem:BAAALgAECgEJAQAAAA==.Halimah:BAAALgAECgEJAQAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harlydorable:BAAALgAECgkJDgAAAA==.Harryphotter:BAAALgADCgEJAQAAAA==.Hazystar:BAAALgAECgcJDAAAAA==.',
He='Healmemaybe:BAABLgAECn8XAAIBAAYJCxKMkAAUAQABAAYJCxKMkAAUAQAAAA==.Hemour:BAABLgAECn8YAAICAAcJCQrVgwAjAQACAAcJCQrVgwAjAQAAAA==.Hexmachine:BAAALgAECgkJBQAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAcJHQAOAEQXAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAAALgAECgYJEQAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.Huntzcatzup:BAAALgADCgYJBgAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAABLgAECn8uAAIHAAkJaww9JQB2AQAHAAkJaww9JQB2AQAAAA==.Iamthanatos:BAAALgAECgcJDAAAAA==.',
Id='Idblastdat:BAABLgAECn8sAAIPAAkJxRi4KAA9AgAPAAkJxRi4KAA9AgAAAA==.',
Ig='Ignite:BAABLgAECn8ZAAIPAAgJSx34PADvAQAPAAgJSx34PADvAQAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8uAAIBAAkJBBfENQDtAQABAAkJBBfENQDtAQAAAA==.Illumiscotty:BAABLgAECn8yAAQPAAkJXiWHBABJAwAPAAkJNSWHBABJAwAnAAUJtB6MBgAXAQAkAAEJ3BAsDQA4AAAAAA==.Ilwey:BAAALgAECgcJEAAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAIoAAYJPB9JJgDSAQAoAAYJPB9JJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAoADwfAA==.Imodium:BAAALgADCgEJAQAAAA==.',
In='Insania:BAABLgAECn8tAAMVAAkJNRt5GAA9AgAVAAgJuxp5GAA9AgAdAAEJ3wM/KQAxAAAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgADCgQJBAAAAA==.',
Ir='Ironhands:BAAALgAECgYJBwAAAA==.',
Iz='Izara:BAAALgAECgEJAQAAAA==.',
Ja='Jarlmaxim:BAAALgAECgYJDAABLgAECggJDQAJAAAAAA==.Jasindra:BAAALgAECgcJCwABLgAECgkJOAAVABgkAA==.Jaspally:BAAALgAECgUJBQABLgAECgkJOAAVABgkAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Johnnycash:BAAALgAECgEJAQAAAA==.Jolinascrubs:BAABLgAECn8yAAIKAAkJ2RC7DQCcAQAKAAkJ2RC7DQCcAQABLgAFFAQJEwAYAPAJAA==.Jonjee:BAABLgAECn8YAAIBAAkJIR1QMQBdAgABAAkJIR1QMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn8tAAIBAAkJjh2oEQCoAgABAAkJjh2oEQCoAgAAAA==.',
Ka='Kahekili:BAAALgAECgMJBQAAAA==.Kain:BAAALgAECgkJDgAAAA==.Kalagren:BAABLgAECn8XAAIYAAUJHQc0ngCpAAAYAAUJHQc0ngCpAAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAACLgAFFH8IAAIiAAIJeCRmHADcAAAiAAIJeCRmHADcAAAuAAQKfzcAAyIACQmwJPUEAK0CACIACAlpJPUEAK0CACEAAgkaFAgXAHMAAAAA.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAABLgAECn8YAAIjAAcJKQjiPwADAQAjAAcJKQjiPwADAQAAAA==.',
Ke='Keerah:BAABLgAECn8aAAMFAAkJtwPRegDlAAAFAAkJtwPRegDlAAAcAAUJmQFGHwBaAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgEJAQAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8bAAIbAAYJTRrNDQC2AQAbAAYJTRrNDQC2AQAuAAQKfyoAAhsACQkYJFAEAHYDABsACQkYJFAEAHYDAAAA.Kexkan:BAABLgAECn8VAAIjAAcJ5xghJACTAQAjAAcJ5xghJACTAQAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8VAAINAAkJtx47BgCaAgANAAkJtx47BgCaAgAAAA==.',
Ki='Kiarah:BAABLgAECn8bAAILAAYJ0wrmPgAFAQALAAYJ0wrmPgAFAQAAAA==.Killplz:BAAALgADCgYJBgAAAA==.Kirr:BAAALgAECgUJBgAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgYJCAAAAA==.Kitchenstink:BAABLgAECn8YAAIpAAkJ4B4VBAC0AgApAAkJ4B4VBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8pAAIFAAkJ+hSCLwDLAQAFAAkJ+hSCLwDLAQAAAA==.',
Ko='Kordh:BAABLgAECn8uAAQdAAcJOg9CEQCjAQAdAAcJew5CEQCjAQAVAAcJSQpkVAA0AQAHAAcJKA5lOQAGAQAAAA==.Kordiza:BAAALgAECgYJDwABLgAECgcJLgAdADoPAA==.',
Kr='Kritanta:BAABLgAECn8pAAIEAAkJ5AyMGABRAQAEAAkJ5AyMGABRAQAAAA==.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8aAAITAAYJAhHwNAD4AAATAAYJAhHwNAD4AAAAAA==.',
Ku='Kurnea:BAABLgAECn8YAAILAAgJsR+bFgAUAgALAAgJsR+bFgAUAgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8QAAIXAAQJnhMlGwAqAQAXAAQJnhMlGwAqAQAuAAQKfyEABBcACAnEHZYbALUBABcACAlbHJYbALUBAB4ABglRE2wXAH8BABYAAQkcFIQvADoAAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8SAAMIAAQJbSM9AQCRAQAIAAQJbSM9AQCRAQAhAAIJ+RWlAwC9AAAuAAQKfyoABAgACAm9JVMBALoCACIABwmqI2MLAN8CACEABwlWJUkCANcCAAgACAmGJVMBALoCAAEuAAUUBgkZAAQAgCQA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAAALgAECgYJEgAAAA==.Leonedis:BAABLgAECn8gAAIjAAYJ8BChNwAoAQAjAAYJ8BChNwAoAQAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8bAAQPAAcJzAz3kAAlAQAPAAcJzAz3kAAlAQAkAAIJZgS+CwBKAAAnAAEJdQH5IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.Levious:BAAALgAECgEJAgAAAA==.',
Li='Liain:BAAALgADCgQJBAABLgAECgIJAgAJAAAAAA==.Lianara:BAAALgAECgQJBAABLgAECgYJEgAJAAAAAA==.Litenkuk:BAACLgAFFH8GAAIZAAMJzw6IFgDnAAAZAAMJzw6IFgDnAAAuAAQKfyEAAxkACAnYHyERALICABkACAnYHyERALICAB8AAgkPD889AH4AAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJBQAHAOgYAA==.',
Lo='Lohin:BAAALgAFFAIJAgABLgAFFAYJCgAWAMoLAA==.Lonelycougar:BAAALgADCgcJDwAAAA==.Lore:BAAALgAECgkJNwAAAQ==.Lothstein:BAAALgAECgYJEQAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Lukri:BAAALgAECgEJAQAAAA==.Luminate:BAABLgAECn8uAAIVAAgJHSTQBwDyAgAVAAgJHSTQBwDyAgAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn8iAAIcAAgJDAMkFADHAAAcAAgJDAMkFADHAAAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgAECgQJBwAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgAECgEJAQAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQAJAAAAAA==.Malachor:BAABLgAECn8bAAMEAAYJPhOFIAAFAQAEAAYJPhOFIAAFAQADAAEJfgX5JgApAAAAAA==.Maligned:BAABLgAECn8mAAIEAAkJWRqlCABHAgAEAAkJWRqlCABHAgAAAA==.Marsilea:BAAALgADCgcJCgABLgAECgIJAgAJAAAAAA==.Martichoux:BAABLgAECn8XAAIPAAkJKR2xPwB6AgAPAAkJKR2xPwB6AgAAAA==.Marvyy:BAAALgADCggJCQAAAA==.Mash:BAAALgAECgIJAgABLgAFFAQJBAAJAAAAAA==.Mathas:BAABLgAECn8mAAILAAkJyyEpEQCJAgALAAkJyyEpEQCJAgAAAA==.Mathilda:BAAALgAECgUJBQAAAA==.Mazes:BAABLgAECn8kAAMiAAYJhSCuEwC8AQAiAAYJhSCuEwC8AQAhAAEJqATiIQAoAAAAAA==.',
Mc='Mccholock:BAABLgAECn8bAAIjAAYJ8RtTJgCFAQAjAAYJ8RtTJgCFAQAAAA==.Mcllovin:BAAALgAECgEJAQAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Meddox:BAAALgADCgYJBgAAAA==.Mediocrepaly:BAAALgAECgcJEgAAAA==.Mehaoloka:BAAALgADCgkJCQAAAA==.Mekanthis:BAACLgAFFH8ZAAIEAAYJgCQhAwDzAQAEAAYJgCQhAwDzAQAuAAQKfygAAgQACQmEJTsCAFEDAAQACQmEJTsCAFEDAAAA.Menith:BAAALgAECgQJBAAAAA==.Menoah:BAABLgAECn8YAAIUAAcJBBLlFwAoAQAUAAcJBBLlFwAoAQAAAA==.Menotthatorc:BAAALgAECgUJBgAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAAALgAECgcJEgAAAA==.Mesilana:BAAALgAECgYJBgAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECgcJEgAJAAAAAA==.Mirenna:BAABLgAECn8YAAIOAAcJ4hl9EgAMAgAOAAcJ4hl9EgAMAgAAAA==.Mirra:BAAALgAECgIJAgAAAA==.Misseymiss:BAAALgAECgQJBQAAAA==.',
Mo='Mogwhy:BAABLgAECn8mAAIhAAkJVBFqBQDmAQAhAAkJVBFqBQDmAQAAAA==.Molbeato:BAAALgAECgEJAgAAAA==.Monichan:BAAALgAECgQJBwAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Monkfu:BAAALgADCgcJAQAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAABLgAECn8VAAIoAAgJORZkIABxAQAoAAgJORZkIABxAQAAAA==.Moralekillas:BAABLgAFFH8FAAIhAAQJzguNAwA9AQAhAAQJzguNAwA9AQAAAA==.Morganna:BAAALgAECgEJAgAAAA==.Morior:BAABLgAECn8XAAIgAAcJnwn8EADwAAAgAAcJnwn8EADwAAAAAA==.Motorcade:BAABLgAECn8hAAIoAAgJrwH/QQDDAAAoAAgJrwH/QQDDAAAAAA==.',
Mu='Muchoblades:BAAALgAECgYJCwAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAABLgAECn8UAAIQAAkJbRthFQBiAgAQAAkJbRthFQBiAgAAAA==.',
My='Myronastus:BAAALgADCgEJAQAAAA==.',
Ne='Neather:BAABLgAECn8eAAIPAAgJMhHDYACGAQAPAAgJMhHDYACGAQAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgMJAwAAAA==.Nexeon:BAAALgAECgEJAgABLgAECgkJGgARAIIUAA==.',
Ni='Niare:BAAALgAECgIJAgAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAABLgAECn8nAAIFAAgJhB/fFwBPAgAFAAgJhB/fFwBPAgAAAA==.Nira:BAABLgAECn8VAAIaAAkJuheQCgCAAgAaAAkJuheQCgCAAgAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8rAAIBAAkJ0iCIDQDJAgABAAkJ0iCIDQDJAgAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAABLgAECn8YAAIYAAYJBxbaWABQAQAYAAYJBxbaWABQAQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.',
Oa='Oakarm:BAAALgAECgkJAgAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJEgAAAA==.',
Od='Odyssius:BAAALgAECgUJEQAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECggJJAAVAEUGAA==.',
Ol='Oldandblind:BAAALgAECgYJCwAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAAALgAECgYJEgAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8cAAMYAAgJ0RtUYABHAQAYAAYJFhtUYABHAQAZAAUJNRjISgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn8yAAMMAAkJySO3AQAcAwAMAAkJySO3AQAcAwAjAAgJJw91MwDdAQAAAA==.',
Ow='Owlpha:BAAALgAECgYJCwAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIBAAgJUxGxbABYAQABAAgJUxGxbABYAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgAECgEJAQABLgAECgcJHQABAMgYAA==.Panax:BAAALgADCgcJBwAAAA==.Parabellum:BAAALgADCgYJBgAAAA==.Parkér:BAAALgAECgMJBQAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECggJIwAJAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAABLgAECn8UAAIQAAYJARApSQAuAQAQAAYJARApSQAuAQAAAA==.Perpetrator:BAABLgAECn8hAAIEAAgJXAOrKADEAAAEAAgJXAOrKADEAAAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.',
Po='Poepwn:BAABLgAECn8hAAISAAcJshFyMAA5AQASAAcJshFyMAA5AQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgADCgQJBwAAAA==.',
Pu='Putnamehere:BAAALgAECgEJAQAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAECgMJAwAAAA==.',
Qu='Quelude:BAAALgAECggJEAAAAA==.Quill:BAABLgAECn8VAAMQAAkJxRXwKQAKAgAQAAkJxRXwKQAKAgAUAAMJwRMSIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rancidgreen:BAAALgAECgMJBAAAAA==.Rannick:BAABLgAECn8WAAIdAAYJBhE6FAANAQAdAAYJBhE6FAANAQAAAA==.Ranua:BAABLgAECn84AAMVAAkJGCShAQCMAwAVAAkJGCShAQCMAwAHAAYJqwxGQgDgAAAAAA==.Ratio:BAABLgAECn8gAAIFAAcJiSHtHQAnAgAFAAcJiSHtHQAnAgAAAA==.Ravenhunt:BAAALgAECgQJBAAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgcJBwAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAECgYJCwAAAA==.Redbreastman:BAABLgAECn8UAAMWAAYJ5hpCDADSAQAWAAYJ5hpCDADSAQAXAAMJmgNJVQBvAAAAAA==.Reiner:BAAALgAECggJCAAAAA==.Rekka:BAAALgAECgQJBAAAAA==.Reoshe:BAAALgAECgEJAQAAAA==.',
Ri='Ripdvanwinkl:BAABLgAECn8aAAIFAAcJShD2XQArAQAFAAcJShD2XQArAQAAAA==.',
Ro='Roachpocket:BAAALgAECgYJCQAAAA==.Ronyn:BAABLgAECn8aAAMVAAcJiRpcHgARAgAVAAcJiRpcHgARAgAHAAEJVQhrhgAnAAAAAA==.',
Ru='Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAAALgAECgUJCwAAAA==.',
['Rö']='Rötthgard:BAAALgADCgkJCgAAAA==.',
Sa='Salacakei:BAABLgAECn8vAAMiAAkJgRvMCABWAgAiAAkJgRvMCABWAgAhAAQJBwv7EwC/AAAAAA==.Salin:BAAALgAECgcJDAAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgcJEAAJAAAAAA==.Sarthiy:BAABLgAECn8ZAAIKAAcJKiNpBwBpAgAKAAcJKiNpBwBpAgABLgAFFAYJGgAKACcgAA==.Sarthy:BAACLgAFFH8aAAIKAAYJJyDJAACzAQAKAAYJJyDJAACzAQAuAAQKfzEAAgoACQkeJGcAAJcDAAoACQkeJGcAAJcDAAAA.Sassaphras:BAABLgAECn8VAAIOAAcJNx/kEQBSAgAOAAcJNx/kEQBSAgAAAA==.Satheron:BAAALgAECgYJDgAAAA==.Satyric:BAAALgAECgIJAwAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECgUJCAAAAA==.Scoobie:BAAALgAECgMJAwABLgAECggJGgAYAE8VAA==.Scoobydo:BAAALgAECgEJAwABLgAECggJGgAYAE8VAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8TAAIYAAQJ8AlKDQD1AAAYAAQJ8AlKDQD1AAAuAAQKfywAAhgACQkvHVQfAEkCABgACQkvHVQfAEkCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgcJAgAAAA==.Shamyaltak:BAAALgAECgkJDAAAAA==.Shandralore:BAABLgAECn8YAAIZAAcJ6BZhCwBsAQAZAAcJ6BZhCwBsAQAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAABLgAECn8bAAINAAYJzRWWEQBIAQANAAYJzRWWEQBIAQAAAA==.Shockdoctor:BAABLgAECn8jAAIVAAcJPSQrEACLAgAVAAcJPSQrEACLAgAAAA==.Shogunasasin:BAABLgAECn8bAAMSAAgJBQ23KQBnAQASAAgJBQ23KQBnAQARAAMJuxqVTQDbAAAAAA==.Shortrange:BAABLgAECn8VAAIZAAcJByBQBgDyAQAZAAcJByBQBgDyAQAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAAALgAECgQJDgAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAABLgAECn8aAAMYAAgJTxWYPQC4AQAYAAgJJhWYPQC4AQAfAAYJVRXmIQBQAQAAAA==.Sleyalias:BAAALgAFFAMJAwAAAA==.Slufgor:BAAALgAECgYJDAAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAABLgAECn8XAAQmAAYJMR8dDwAOAQAbAAUJDxsiaQA7AQAmAAQJOR4dDwAOAQAgAAEJnxLEawA8AAAAAA==.Snoogon:BAAALgAECgUJBgABLgAECgYJFwAmADEfAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.Snowingout:BAAALgAECgEJAQAAAA==.',
So='Solarlite:BAAALgAECgYJBwAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8VAAIaAAkJXSAFCAC/AgAaAAkJXSAFCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgYJCQAAAA==.Spony:BAAALgAECgUJEAAAAA==.',
St='Starbrow:BAAALgAECgQJCQABLgAECgkJHQACAHcfAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJEQAAAA==.Stormlight:BAABLgAECn8UAAIQAAgJKwwVQQBSAQAQAAgJKwwVQQBSAQAAAA==.',
Su='Summernight:BAAALgAECgEJAgAAAA==.Sushistryke:BAAALgAECgYJDAAAAA==.',
Sv='Svend:BAAALgADCgEJAQAAAA==.',
Sy='Syland:BAABLgAECn8aAAIYAAYJ6xkTSwB3AQAYAAYJ6xkTSwB3AQAAAA==.Sylanis:BAAALgADCgcJBwAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAAALgAECgkJEAAAAA==.Sylvenna:BAAALgAECgYJEgAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAABLgAECn8iAAIGAAgJ4yKmBgCyAgAGAAgJ4yKmBgCyAgAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAABLgAECn8oAAIVAAkJ+BSXJgDbAQAVAAkJ+BSXJgDbAQAAAA==.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAAALgAECgQJCAAAAA==.Tazanaz:BAAALgAECgQJCAABLgAECgkJOAAVABgkAA==.',
Te='Templeton:BAAALgAECgYJCwABLgAECggJJAAVAEUGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAABLgAECn8UAAIPAAYJ1wnOpwD9AAAPAAYJ1wnOpwD9AAAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8eAAIKAAcJkBlHDwCDAQAKAAcJkBlHDwCDAQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAABLgAECn8lAAMVAAgJKh0MGABBAgAVAAgJKh0MGABBAgAHAAYJQRibMwAiAQAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8WAAIEAAkJ9CCABgDOAgAEAAkJ9CCABgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8RAAIVAAQJFBaxGgAwAQAVAAQJFBaxGgAwAQAuAAQKf0EAAhUACQlmH0IJAN0CABUACQlmH0IJAN0CAAAA.',
Tr='Trailerpark:BAAALgAECgYJEQAAAA==.Tratre:BAABLgAECn83AAQXAAkJwxa3EwD/AQAXAAkJwxa3EwD/AQAWAAcJ7QnFFgAjAQAeAAEJYxIZPQA6AAAAAA==.Treynof:BAABLgAECn8bAAITAAgJ1Az+JwBCAQATAAgJ1Az+JwBCAQAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAABLgAECn8aAAIlAAcJaQleIwAFAQAlAAcJaQleIwAFAQAAAA==.',
Tu='Tulsiice:BAABLgAECn8XAAIPAAgJ2hVcSQDFAQAPAAgJ2hVcSQDFAQAAAA==.',
Tw='Twoglaivez:BAAALgAECgYJDQABLgAFFAcJHgAjAMEgAA==.',
Ty='Tytaniormu:BAAALgAECgkJEgAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAAJAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJBQAHAOgYAA==.',
Un='Undeathtwoy:BAABLgAECn8fAAMCAAcJpR1paAC9AQACAAcJPxppaAC9AQAEAAUJJhTiJgDRAAAAAA==.Undos:BAAALgAECgEJAgAAAA==.Unholyveri:BAAALgAECgYJBgAAAA==.',
Va='Vaelraen:BAABLgAECn8dAAIBAAgJMxpeMgD6AQABAAgJMxpeMgD6AQAAAA==.Valcher:BAAALgAECgUJDwAAAA==.Valendera:BAABLgAECn8VAAIbAAkJEQsLYACpAQAbAAkJEQsLYACpAQAAAA==.Valhri:BAAALgAECgYJCgAAAA==.Valifadin:BAABLgAECn8YAAIfAAcJABqoFQC+AQAfAAcJABqoFQC+AQAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valmoria:BAAALgADCgkJFwAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJCQABLgAECgkJOAAVABgkAA==.Varch:BAAALgAECggJDgAAAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMDAAkJFB7mAgBtAgADAAkJFB7mAgBtAgACAAMJ4AoF/ACDAAAAAA==.Vera:BAAALgAECgEJAQAAAA==.',
Vi='Viktir:BAAALgADCgcJBgABLgAECgYJFAAQAAEQAA==.Vintage:BAACLgAFFH8LAAIIAAMJjQ4VAQDsAAAIAAMJjQ4VAQDsAAAuAAQKfyIAAggACQnpGfYAAAMDAAgACQnpGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAABLgAECn8UAAICAAgJmiDEGwBnAgACAAgJmiDEGwBnAgAAAA==.Volkareth:BAABLgAECn8VAAIeAAkJyhPRDQD9AQAeAAkJyhPRDQD9AQAAAA==.Vorkath:BAABLgAECn8vAAQeAAkJxCKqAAAPAwAeAAkJxCKqAAAPAwAWAAcJ0h6xCAAlAgAXAAEJmx+dWABcAAAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAABLgAECn8YAAIYAAgJhAyiSwB1AQAYAAgJhAyiSwB1AQAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQABAFMRAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn8pAAIQAAcJBBtLHwAQAgAQAAcJBBtLHwAQAgAAAA==.',
Wi='Wilderbeast:BAABLgAECn8dAAIQAAkJLwWGUAATAQAQAAkJLwWGUAATAQAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECggJJAAVAEUGAA==.Woxkal:BAABLgAECn8eAAMEAAcJDQpxJgDUAAAEAAcJDQpxJgDUAAACAAEJ0AGwNwEhAAAAAA==.',
Wu='Wubblebubble:BAABLgAECn8kAAMEAAkJKgveGABNAQAEAAkJygreGABNAQACAAQJBgYHzQCkAAAAAA==.',
Xa='Xaelin:BAABLgAECn8YAAIOAAYJfhF9KgA3AQAOAAYJfhF9KgA3AQAAAA==.',
Yi='Yisús:BAAALgAECgQJBwAAAA==.',
Yl='Ylvis:BAABLgAECn8mAAIYAAgJ9BbwNADEAQAYAAgJ9BbwNADEAQAAAA==.',
Yo='Yoshymi:BAAALgAECggJIwAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECgIJAwABLgAECgUJBgAJAAAAAA==.',
Za='Zacco:BAABLgAECn8dAAIBAAgJ1gNqqgDpAAABAAgJ1gNqqgDpAAAAAA==.Zaleth:BAACLgAFFH8KAAIWAAYJygtQEQAjAQAWAAYJygtQEQAjAQAuAAQKfykAAhYABwkYIakIALACABYABwkYIakIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAABLgAECn8jAAICAAkJSAweRgC4AQACAAkJSAweRgC4AQAAAA==.Zargar:BAAALgADCggJCQAAAA==.Zarion:BAAALgAECgYJCAABLgAFFAYJCgAWAMoLAA==.Zarra:BAAALgAECgYJDAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.',
Ze='Zeroz:BAAALgAFFAEJAQAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAABLgAECn8aAAILAAcJ0yIOCwCdAgALAAcJ0yIOCwCdAgABLgAFFAYJCgAWAMoLAA==.',
Zo='Zocorro:BAAALgAECgYJEAAAAA==.Zodiack:BAAALgAECgcJCQAAAA==.Zombe:BAABLgAECn8VAAICAAgJCAmzegCPAQACAAgJCAmzegCPAQAAAA==.',
Zu='Zuelmst:BAAALgAECgQJBgAAAA==.',
Zy='Zypherdius:BAAALgADCgUJBQAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQAAAA==.',
['Ðe']='Ðecision:BAACLgAFFH8JAAIBAAMJsSSmIQBDAQABAAMJsSSmIQBDAQAuAAQKfygAAgEACQnIJKsDAD8DAAEACQnIJKsDAD8DAAAA.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQABAFMRAA==.',
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
