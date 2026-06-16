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

local lookup = {'Priest-Holy','DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Shaman-Elemental','Hunter-BeastMastery','Rogue-Outlaw','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Warrior-Protection','Druid-Feral','Mage-Frost','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Priest-Discipline','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-06-14',data={Aa='Aaralyn:BAABLgAECn8WAAIBAAcJIxC1JwCFAQABAAcJIxC1JwCFAQAAAA==.',
Ab='Abmikaze:BAAALgAECgkJDgAAAA==.Abor:BAAALgADCgMJAwAAAA==.',
Ad='Addition:BAAALgAECgYJBgABLgAECgkJIgACAAkgAA==.Adimus:BAAALgADCgMJAwAAAA==.Adorean:BAABLgAECn8vAAIDAAkJAx7lGwCcAgADAAkJAx7lGwCcAgAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn8wAAIDAAkJRxt3JwBkAgADAAkJRxt3JwBkAgAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAABLgAECn8XAAIDAAYJxA98xgD+AAADAAYJxA98xgD+AAAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akaril:BAAALgAFFAEJAQABLgAFFAIJBwAEAGofAA==.Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alaileath:BAAALgADCgEJAQAAAA==.Alaryk:BAAALgAECgEJAQAAAA==.Alburm:BAABLgAECn8aAAMFAAgJBiEHJQBvAgAFAAgJBiEHJQBvAgAGAAEJHwo0PgAoAAAAAA==.Alexstraxsa:BAAALgAECgYJEQAAAA==.Aliine:BAABLgAECn86AAIEAAkJtRjDDQAtAgAEAAkJtRjDDQAtAgAAAA==.Ally:BAAALgAECgQJBwABLgAECgkJIgACAAkgAA==.Althaea:BAABLgAECn8VAAIHAAgJ0wFWYwCKAAAHAAgJ0wFWYwCKAAAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAACLgAFFH8UAAIIAAQJRRNHIgANAQAIAAQJRRNHIgANAQAuAAQKf0wAAggACQkOIUEHAOYCAAgACQkOIUEHAOYCAAAA.',
An='Anahana:BAAALgAECgYJDQAAAA==.Anali:BAAALgADCggJGAAAAA==.Anatomxx:BAAALgAECgEJAQAAAA==.Andi:BAAALgAECgcJEAAAAA==.Andorelia:BAABLgAECn8zAAIDAAkJZRE4TQDeAQADAAkJZRE4TQDeAQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAABLgAECn8WAAIJAAcJwgymegBHAQAJAAcJwgymegBHAQAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAgJGgAKAB0jAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAABLgAECn8bAAIDAAkJ1AdMjwBSAQADAAkJ1AdMjwBSAQAAAA==.Appleborne:BAAALgADCgcJBwABLgADCgMJBQALAAAAAA==.Appleseed:BAAALgADCgMJBQAAAA==.Apprentice:BAABLgAECn9FAAIMAAkJRgKiLAC3AAAMAAkJRgKiLAC3AAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCgAAAA==.Aramos:BAACLgAFFH8JAAINAAMJuRR6KwDMAAANAAMJuRR6KwDMAAAuAAQKfzAAAg0ACQm8GX4aAC8CAA0ACQm8GX4aAC8CAAAA.Aramôs:BAABLgAECn8xAAINAAgJXxPCJADfAQANAAgJXxPCJADfAQAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDgALAAAAAA==.Arlowhite:BAAALgAECgMJAwAAAA==.Arta:BAABLgAECn8oAAIOAAgJrRnxDwDlAQAOAAgJrRnxDwDlAQAAAA==.Artachoke:BAAALgAECgYJCQAAAA==.Aruncusdio:BAABLgAECn8cAAIPAAgJbAYIIgD0AAAPAAgJbAYIIgD0AAAAAA==.Arysta:BAAALgAECgQJBQAAAA==.',
As='Ashhealz:BAABLgAECn83AAIBAAgJgRbmFwAMAgABAAgJgRbmFwAMAgAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgUJBgAAAA==.Astronomical:BAAALgAECgIJAgABLgAECgUJBgALAAAAAA==.',
At='Atelwen:BAAALgAECgYJEwAAAA==.',
Av='Aveme:BAABLgAECn8wAAIQAAkJCiMtGQAUAwAQAAkJCiMtGQAUAwAAAA==.',
Aw='Awartedpeen:BAABLgAECn8qAAIRAAgJiwrFZwD7AAARAAgJiwrFZwD7AAAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAALAAAAAA==.Aznarak:BAAALgAECgYJBgAAAA==.Azuleon:BAABLgAECn8eAAMSAAkJgxRXHQDwAQASAAYJ6B1XHQDwAQATAAkJNg7QNwCOAQAAAA==.',
Ba='Badsnapple:BAAALgAECgkJDwABLgADCgMJBQALAAAAAA==.Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgAECgUJBQAAAA==.Balbit:BAAALgADCgQJBAAAAA==.Bamber:BAAALgADCggJDQAAAA==.Bamboo:BAAALgAECgEJAQAAAA==.Barrywhite:BAAALgAECgcJDwAAAA==.Bast:BAAALgAECgEJAgAAAA==.Battar:BAAALgAECgEJAwAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn82AAMUAAkJ+BqjDwBjAgAUAAkJRBmjDwBjAgAVAAYJ+hCvLwDpAAAAAA==.Beakerstime:BAAALgAECgIJAwAAAA==.Beastmode:BAABLgAECn8tAAIRAAkJaxu4FwCGAgARAAkJaxu4FwCGAgAAAA==.Beckyg:BAAALgADCgEJAQAAAA==.Bedlem:BAABLgAECn8bAAIFAAcJzAgPsQARAQAFAAcJzAgPsQARAQAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwALAAAAAA==.Belwas:BAAALgADCgkJCQABLgAECgkJMAADAEcbAA==.Bernard:BAABLgAECn8pAAMWAAgJRQaFXwAOAQAWAAgJRQaFXwAOAQAIAAcJIQuYSgAHAQAAAA==.',
Bi='Bidoof:BAABLgAECn8mAAMXAAgJvRZGDAAPAgAXAAgJvRZGDAAPAgAYAAcJRg+VRgAOAQAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAACLgAFFH8HAAIJAAMJXgl1aQDKAAAJAAMJXgl1aQDKAAAuAAQKfygAAwkACAmDD95WAJwBAAkACAmDD95WAJwBABkABgmcAWNrAJEAAAAA.Bishop:BAAALgADCgUJBQABLgAECggJFgAJAMIMAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJLQABAOsaAA==.Blackgrace:BAAALgAECggJDQAAAA==.Blacklisted:BAABLgAECn8tAAQBAAkJ6xqvDgB7AgABAAkJ6xqvDgB7AgAaAAEJgwrDfQAsAAAHAAEJdQZhjgAqAAAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgAECgcJDAAAAA==.Blessurheart:BAAALgADCgIJAgAAAA==.Bloodbladesz:BAAALgADCgEJAQABLgAFFAEJAQALAAAAAA==.Bloodybloodz:BAAALgAFFAEJAQAAAA==.Bloodyburst:BAAALgAECgcJCAABLgAFFAEJAQALAAAAAA==.Bloodyfistz:BAABLgAECn8VAAMSAAgJlx6tPwD+AAASAAcJnh2tPwD+AAATAAUJegsPQwDSAAABLgAFFAEJAQALAAAAAA==.Blueboost:BAAALgAECgkJCQAAAA==.Blueshift:BAABLgAECn8WAAICAAkJChc+QwDnAQACAAkJChc+QwDnAQAAAA==.Bluethreetwo:BAABLgAECn8eAAQFAAYJCAjG1ADgAAAFAAYJ5AfG1ADgAAAGAAQJHgMLOQA0AAAEAAEJXgNZYwAhAAAAAA==.Blurry:BAAALgADCgUJBgAAAA==.',
Bo='Bookofzeref:BAABLgAECn8UAAIbAAgJWBLfawBkAQAbAAgJWBLfawBkAQAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAABLgAECn8rAAIcAAgJ3RsOBwAVAgAcAAgJ3RsOBwAVAgAAAA==.Brayend:BAABLgAECn8yAAIdAAkJYht6BgBvAgAdAAkJYht6BgBvAgAAAA==.Brewbelly:BAAALgADCgcJCQAAAA==.Brimscythe:BAABLgAECn8xAAIeAAkJIB9OAgCdAgAeAAkJIB9OAgCdAgAAAA==.Brutälity:BAAALgAECgkJBgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.Bulish:BAAALgADCgMJAwAAAA==.',
Ca='Caliandis:BAABLgAECn8bAAIOAAkJJAuYHABPAQAOAAkJJAuYHABPAQAAAA==.Calvey:BAAALgAECgUJCgAAAA==.Cambrai:BAABLgAECn8YAAISAAgJnhGbKABzAQASAAgJnhGbKABzAQAAAA==.Cannabelle:BAACLgAFFH8LAAIfAAMJSCRCEwAuAQAfAAMJSCRCEwAuAQAuAAQKfzgAAh8ACQlAJQMBAGcDAB8ACQlAJQMBAGcDAAAA.Cannabeth:BAABLgAFFH8HAAIGAAMJghAvFQDaAAAGAAMJghAvFQDaAAAAAA==.Canto:BAAALgAECgQJBAAAAA==.Captpickle:BAAALgAECgkJEQAAAA==.Carclias:BAACLgAFFH8GAAMgAAQJ/w1QCAAQAQAgAAQJ/w1QCAAQAQAbAAEJkA/pwQBEAAAuAAQKfxoAAyAACQl0Gi4HAFcCACAACAl+Gy4HAFcCABsAAwnmCeMhAUQAAAAA.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAABLgAECn8UAAIhAAcJVBNKQwCXAQAhAAcJVBNKQwCXAQAAAA==.Catmove:BAAALgAECgUJBQAAAA==.Cattlerage:BAAALgAECgYJEwAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.Cerdelz:BAAALgAECgYJBgAAAA==.Cerena:BAAALgAECgIJAwAAAA==.',
Ch='Chaoscookies:BAACLgAFFH8JAAMgAAMJCxTwGgBcAAAbAAIJmQ5hoACHAAAgAAEJ7x7wGgBcAAAuAAQKfzYAAyAACQnvGacNAF8BACAABgmXHacNAF8BABsABQlJFXiMACIBAAAA.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAABLgAECn8YAAIdAAcJQhzaDADhAQAdAAcJQhzaDADhAQAAAA==.Cheechee:BAAALgAECgYJEAAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8bAAIRAAcJKBTJQACMAQARAAcJKBTJQACMAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAFFAYJFgAIAMgTAA==.',
Ci='Ciená:BAAALgAECgQJBQAAAA==.Cin:BAABLgAECn8aAAIFAAkJGSLLDAAFAwAFAAkJGSLLDAAFAwAAAA==.Cinderpetal:BAAALgAECgQJBQAAAA==.',
Ck='Ckay:BAAALgAECgMJAwAAAA==.',
Co='Cohemew:BAAALgAECggJCwABLgAFFAEJAQALAAAAAA==.Comlock:BAABLgAECn8cAAMbAAYJpwYw5QCSAAAbAAYJugQw5QCSAAAgAAMJOQjbOgA8AAAAAA==.Complacent:BAABLgAECn9DAAIVAAkJNwTjOQC6AAAVAAkJNwTjOQC6AAAAAA==.Comrage:BAAALgADCgQJBAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgQJBQAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAABLgAECn8nAAIDAAgJ3BbqTQDcAQADAAgJ3BbqTQDcAQAAAA==.Crimsonlight:BAAALgAECggJEAAAAA==.Crownman:BAAALgADCgkJFwAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuckpov:BAAALgAECgEJAgAAAA==.Cuddilz:BAABLgAECn8eAAMiAAkJXBZXHACxAQAiAAkJARNXHACxAQAjAAYJ3RJyEAAcAQAAAA==.Cursedchild:BAAALgAFFAMJBAAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8vAAIbAAkJjR0uFACsAgAbAAkJjR0uFACsAgAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAABLgAECn8/AAIEAAkJUB5QCACPAgAEAAkJUB5QCACPAgAAAA==.',
['Cé']='Cécé:BAABLgAECn8wAAIDAAcJpCNEKwBTAgADAAcJpCNEKwBTAgAAAA==.',
Da='Daciana:BAABLgAECn8yAAIJAAgJxyDyGQCGAgAJAAgJxyDyGQCGAgAAAA==.Dagaroonie:BAAALgAECgkJEAAAAA==.Dagevas:BAABLgAECn8lAAIbAAkJ1RLNSQC9AQAbAAkJ1RLNSQC9AQAAAA==.Danyella:BAAALgAECgEJAQAAAA==.Darinius:BAAALgAECgEJAgAAAA==.Darkeznite:BAABLgAECn8aAAIJAAkJhhnVLwAaAgAJAAkJhhnVLwAaAgAAAA==.Darksoldier:BAABLgAFFH8FAAIJAAQJBgzhSwAPAQAJAAQJBgzhSwAPAQAAAA==.Dartoy:BAACLgAFFH8JAAIhAAMJTR9DKAAQAQAhAAMJTR9DKAAQAQAuAAQKfzoAAiEACQljDpslAMoBACEACQljDpslAMoBAAAA.Davriell:BAAALgAECgcJDQAAAA==.Dax:BAABLgAECn8eAAIJAAgJghm3PgDkAQAJAAgJghm3PgDkAQAAAA==.Daxing:BAAALgAECgUJBQABLgAFFAMJBQAWAKYMAA==.Dazling:BAAALgAECggJEQAAAA==.Dazz:BAAALgAECgEJAQAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAABLgAECn8VAAIgAAYJSh8eDwDZAQAgAAYJSh8eDwDZAQAAAA==.Deeppurple:BAABLgAECn8gAAIkAAcJ4wlSCAAIAQAkAAcJ4wlSCAAIAQAAAA==.Deezmons:BAABLgAECn8rAAIlAAkJTRC6HACTAQAlAAkJTRC6HACTAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn82AAIcAAkJTSZMAABsAwAcAAkJTSZMAABsAwAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgcJEwAAAA==.Demonkirby:BAAALgADCgUJBwAAAA==.Demonlarrik:BAAALgAECgEJAQAAAA==.Demostache:BAAALgAFFAEJAQAAAA==.Derale:BAABLgAECn8aAAMYAAgJiw0EJgCNAQAYAAgJiA0EJgCNAQAeAAcJXQQyIgAZAQAAAA==.Despot:BAAALgAECgQJBAAAAA==.Destoroyah:BAAALgADCgQJBAAAAA==.',
Dh='Dhargal:BAACLgAFFH8JAAIIAAMJlx8EJwD1AAAIAAMJlx8EJwD1AAAuAAQKfzsAAggACQk+JJcDADADAAgACQk+JJcDADADAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAABLgAECn8dAAIRAAgJHA0bTABdAQARAAgJHA0bTABdAQAAAA==.',
Dk='Dkfaros:BAABLgAECn8fAAIFAAkJeB//HACXAgAFAAkJeB//HACXAgAAAA==.',
Do='Dommenica:BAAALgADCgYJBgAAAA==.Donko:BAAALgADCggJCAABLgAECgcJFwAWAE0NAA==.Dontcarebear:BAABLgAECn8fAAIVAAgJJwaNOwCzAAAVAAgJJwaNOwCzAAAAAA==.Doofnshmirtz:BAACLgAFFH8FAAIdAAMJFxEkDgDaAAAdAAMJFxEkDgDaAAAuAAQKfy8AAh0ACQngHDUHAFkCAB0ACQngHDUHAFkCAAAA.Dorkwiz:BAAALgADCgMJAwAAAA==.Dorow:BAAALgAECggJEAAAAA==.Dotpocket:BAABLgAECn8tAAIbAAkJfhm1KwAqAgAbAAkJfhm1KwAqAgAAAA==.',
Dr='Dragonash:BAAALgAECgYJDAAAAA==.Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECgkJEgAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dreams:BAACLgAFFH8KAAIJAAMJ6xHRXADlAAAJAAMJ6xHRXADlAAAuAAQKf0sAAwkACQn1H10QAMsCAAkACQn1H10QAMsCABkAAwnVBk10AG0AAAAA.Dremmy:BAAALgAECgYJEQAAAA==.Drey:BAAALgADCgEJAQAAAA==.Drinkme:BAAALgAECgMJAwAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAACLgAFFH8NAAIdAAMJ9R2RCgAVAQAdAAMJ9R2RCgAVAQAuAAQKfzAAAh0ACQlAIXcCAPICAB0ACQlAIXcCAPICAAAA.Drokigos:BAAALgAECgIJAgABLgAFFAQJDQAdAPUdAA==.',
Du='Dunsel:BAAALgAECggJEgABLgAECgkJMQAeACAfAA==.Dunwich:BAAALgADCgcJIAAAAA==.Durostan:BAAALgAECgEJBAAAAA==.',
Dv='Dvali:BAABLgAECn8UAAICAAcJWwjnlAD0AAACAAcJWwjnlAD0AAAAAA==.',
Dy='Dyorra:BAABLgAECn8iAAMNAAgJRwl0TAAIAQANAAcJXQZ0TAAIAQADAAYJ1AR+/wC2AAAAAA==.',
['Dä']='Dämon:BAAALgADCgIJAgAAAA==.',
Eb='Ebonshade:BAAALgAECgcJCwAAAA==.',
Ed='Edgardapoe:BAAALgAECgMJAwABLgAFFAEJAQALAAAAAA==.Edginglord:BAAALgAECgYJBwAAAA==.',
Eh='Ehmill:BAABLgAECn8pAAIFAAkJoxkULgBFAgAFAAkJoxkULgBFAgAAAA==.',
El='Elesrya:BAAALgAECgEJAQABLgAECgkJMAADAEcbAA==.Elgringo:BAAALgAECgcJAwAAAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAABLgAECn8VAAIDAAYJwQ2sxgD+AAADAAYJwQ2sxgD+AAAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgkJAQAAAA==.',
Er='Ernest:BAAALgAECgEJAQAAAA==.Errani:BAABLgAECn8fAAIQAAgJTAycgwBuAQAQAAgJTAycgwBuAQAAAA==.',
Es='Eskers:BAABLgAECn8eAAIeAAkJ9RwdAwBtAgAeAAkJ9RwdAwBtAgAAAA==.Esterlia:BAAALgAECgEJAQABLgAFFAMJBQAWAKYMAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8nAAICAAkJwg0NXABxAQACAAkJwg0NXABxAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8bAAIQAAcJKgKAAQGnAAAQAAcJKgKAAQGnAAAAAA==.Evocane:BAABLgAECn8WAAIQAAYJDA4JvAANAQAQAAYJDA4JvAANAQAAAA==.Evocati:BAAALgAECgUJBgABLgAFFAYJDwADAHsWAA==.Evocatis:BAACLgAFFH8PAAMDAAYJexZjKABkAQADAAYJexZjKABkAQANAAEJRAskSwAxAAAuAAQKfyUAAwMACQkZITUeALYCAAMACAl5IzUeALYCAA0AAwkOCxF2AKIAAAAA.Evodruid:BAAALgAECgEJAQAAAA==.Evoorc:BAAALgAECggJDwAAAA==.',
Ex='Ex:BAABLgAECn8jAAIgAAgJqQw3EgAiAQAgAAgJqQw3EgAiAQAAAA==.',
Ey='Eyesdeadeyed:BAAALgAECgEJAQAAAA==.',
Fa='Faasht:BAAALgAECgEJAQAAAA==.Faoris:BAAALgAECgYJDQAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Feebs:BAAALgAECgMJBQAAAA==.Feebzykun:BAAALgADCgUJBQAAAA==.Felheart:BAAALgAECgQJBgABLgAFFAUJFAADAIwaAA==.Felzbirt:BAAALgAECgUJCQAAAA==.Fenehdis:BAAALgAECgcJDQAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgAECggJCgAAAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAYJEAARALsSAA==.Firebirdz:BAACLgAFFH8QAAIRAAYJuxI1GACXAQARAAYJuxI1GACXAQAuAAQKfycAAxEACQnVIbAIAAMDABEACQnVIbAIAAMDABQACAnPFgQdAN0BAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAYJEAARALsSAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzledust:BAAALgAECgEJAgAAAA==.Fizzystomps:BAAALgAECgQJBgAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forginn:BAAALgAECgEJAQABLgAFFAcJKQABAA0aAA==.Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Friargark:BAAALgAECgIJAgAAAA==.Frostatute:BAAALgADCgcJBwAAAA==.Frostypaw:BAAALgADCgYJCgAAAA==.Frostzilla:BAAALgAECgYJCQAAAA==.',
Fu='Fuzzybut:BAABLgAECn8rAAIVAAgJCBzHCwAiAgAVAAgJCBzHCwAiAgAAAA==.',
Fy='Fyuna:BAAALgAFFAIJBAAAAA==.',
Ga='Gandalph:BAAALgAECgQJBQAAAA==.Gark:BAAALgAECgYJEwAAAA==.Garkk:BAAALgADCgcJDwAAAA==.Garrumn:BAAALgAECgEJAQABLgAFFAEJAQALAAAAAA==.Gazzi:BAAALgAECgkJEgAAAA==.',
Ge='Geargust:BAAALgAECgkJAgAAAA==.Georgebenson:BAAALgADCgQJBAAAAA==.',
Gi='Giuseppee:BAAALgAECgQJBAABLgAECggJHQAbAEMZAA==.Gióvanna:BAAALgAECgQJDQAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECggJIgAmAI0eAA==.',
Go='Goblndeznutz:BAAALgAECgEJAgAAAA==.Goobow:BAACLgAFFH8YAAIFAAUJMB0CSABeAQAFAAUJMB0CSABeAQAuAAQKf1kAAgUACQmLJXACAHgDAAUACQmLJXACAHgDAAAA.Goodheavens:BAAALgAECgQJBwAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJCAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8lAAIQAAkJ9Q3NdwDiAQAQAAkJ9Q3NdwDiAQAAAA==.',
Gr='Gr:BAABLgAECn8fAAIRAAcJtRe/MwDMAQARAAcJtRe/MwDMAQAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8kAAIVAAgJxBlLDwDuAQAVAAgJxBlLDwDuAQAAAA==.Grody:BAAALgAECgEJAQAAAA==.Grumpias:BAAALgAECgcJCQABLgAECgkJJwAPAH8cAA==.',
Gu='Guroo:BAABLgAECn80AAIJAAkJ7xJZRADRAQAJAAkJ7xJZRADRAQAAAA==.',
['Gá']='Gárp:BAABLgAECn8UAAMOAAkJQh5oDQASAgAOAAUJ5yRoDQASAgAhAAkJuhKhIwDWAQABLgAECgkJFAAOAEIeAA==.',
['Gø']='Gødoth:BAACLgAFFH8IAAMIAAMJHRzHOwCbAAAIAAIJthrHOwCbAAAWAAEJqhQoewBCAAAuAAQKfyQAAwgACAlhIK4WAC8CAAgACAlhIK4WAC8CABYABQkQIvM7AJIBAAAA.',
Ha='Hagarn:BAACLgAFFH8VAAIDAAUJlw3GSwASAQADAAUJlw3GSwASAQAuAAQKfzkAAgMACQkZFzY6ABkCAAMACQkZFzY6ABkCAAAA.Haithem:BAAALgAECgEJAgAAAA==.Halimah:BAAALgAECgcJDwAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harbek:BAAALgAECggJEwAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harleysmol:BAAALgAECgkJAgAAAA==.Harlydorable:BAABLgAECn8dAAInAAUJWCAFKABvAQAnAAUJWCAFKABvAQAAAA==.Harryphotter:BAAALgADCgEJAQAAAA==.Hazan:BAABLgAECn8XAAIoAAYJDhwIGACXAQAoAAYJDhwIGACXAQABLgAFFAQJDQAdAPUdAA==.Hazystar:BAAALgAECgcJDQAAAA==.',
He='Healmemaybe:BAABLgAECn8aAAIDAAYJgxI3wgAEAQADAAYJgxI3wgAEAQAAAA==.Hemogoblin:BAAALgAECgIJAgABLgAECgkJFwAQACkdAA==.Hemour:BAABLgAECn8hAAIFAAkJbQywXACvAQAFAAkJbQywXACvAQAAAA==.Hexmachine:BAAALgAFFAIJAgAAAA==.Hexyou:BAAALgAECgIJAgAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAcJKQABAA0aAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAABLgAECn8jAAIBAAgJDBZgGwDqAQABAAgJDBZgGwDqAQAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.Huntzcatzup:BAAALgADCgYJBgAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAACLgAFFH8JAAIIAAMJAgVaPQCUAAAIAAMJAgVaPQCUAAAuAAQKfzEAAggACQmADdYvAH4BAAgACQmADdYvAH4BAAAA.Iamthanatos:BAABLgAECn8dAAIDAAcJjwiRwgADAQADAAcJjwiRwgADAQAAAA==.',
Id='Idblastdat:BAABLgAECn8zAAIQAAkJURz4IwCLAgAQAAkJURz4IwCLAgAAAA==.',
Ig='Ignite:BAABLgAECn8cAAMQAAgJQiH1JwB5AgAQAAgJLx/1JwB5AgApAAEJDh4KEgBaAAAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8+AAIDAAkJBxmvMgA0AgADAAkJBxmvMgA0AgAAAA==.Illumiscotty:BAABLgAECn84AAQQAAkJ9CXKBABeAwAQAAkJ9CXKBABeAwApAAUJtB78CAAEAQAkAAEJ3BASFAAwAAAAAA==.Ilwey:BAAALgAECgcJEAAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAInAAYJPB9JJgDSAQAnAAYJPB9JJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAnADwfAA==.Imodium:BAAALgADCgEJAQAAAA==.',
In='Incognonetoo:BAAALgAECgkJBwAAAA==.Insania:BAABLgAECn8/AAMWAAkJNRtKJAAyAgAWAAgJuxpKJAAyAgAdAAIJpAXMMgBhAAAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgAECgEJAQAAAA==.',
Ir='Ironhands:BAAALgAECggJDwAAAA==.',
Iz='Izara:BAAALgAECgQJBQAAAA==.',
Ja='Jarlmaxim:BAAALgAECgYJDAABLgAECggJDQALAAAAAA==.Jasindra:BAAALgAECgcJDwABLgAFFAMJBQAWAKYMAA==.Jaspally:BAAALgAECgcJEAABLgAFFAMJBQAWAKYMAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Johnnycash:BAAALgAECgEJAQAAAA==.Jolinascrubs:BAABLgAECn9CAAIMAAkJ2xBYEwCSAQAMAAkJ2xBYEwCSAQABLgAFFAYJIwAJACgOAA==.Jonjee:BAABLgAECn8YAAIDAAkJIR1QMQBdAgADAAkJIR1QMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn80AAIDAAkJcSB6FQDAAgADAAkJcSB6FQDAAgAAAA==.',
Ka='Kahekili:BAAALgAECgMJBQAAAA==.Kain:BAABLgAECn8aAAIQAAcJrBxNWQDPAQAQAAcJrBxNWQDPAQAAAA==.Kalagren:BAABLgAECn8XAAIJAAUJHQdi0gChAAAJAAUJHQdi0gChAAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAACLgAFFH8XAAIiAAQJCiEDEQCDAQAiAAQJCiEDEQCDAQAuAAQKfz8AAyIACQm2JMUGAMECACIACAlwJMUGAMECACMAAgkaFM8cAHIAAAAA.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAABLgAECn8fAAIhAAgJEQk1QABEAQAhAAgJEQk1QABEAQAAAA==.',
Ke='Keerah:BAABLgAECn8aAAMCAAkJuANTnQDlAAACAAkJuANTnQDlAAAcAAUJmQFrKgBXAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgIJAwAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8fAAIbAAgJ/hwJCgBnAgAbAAgJ/hwJCgBnAgAuAAQKfywAAhsACQlbJVAEAHYDABsACQlbJVAEAHYDAAAA.Kexkan:BAABLgAECn8oAAIhAAkJLh0fDACnAgAhAAkJLh0fDACnAgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8VAAIPAAkJtx47BgCaAgAPAAkJtx47BgCaAgAAAA==.',
Ki='Kiarah:BAABLgAECn8bAAINAAYJ0woVTgABAQANAAYJ0woVTgABAQAAAA==.Killerbuster:BAAALgAECgMJAwABLgAECgMJAwALAAAAAA==.Killplz:BAAALgADCgcJHAAAAA==.Kirr:BAAALgAECgcJDwAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgcJCQAAAA==.Kitchenstink:BAABLgAECn8YAAIoAAkJ4B4VBAC0AgAoAAkJ4B4VBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8wAAICAAkJ/xTmOgDZAQACAAkJ/xTmOgDZAQAAAA==.',
Ko='Kordh:BAABLgAECn86AAQdAAcJbg9CEQCjAQAdAAcJew5CEQCjAQAWAAcJUg4uYgAxAQAIAAcJyg69SgAHAQAAAA==.Kordiza:BAABLgAECn8YAAQlAAYJ9weuPQC7AAAlAAYJ9weuPQC7AAAcAAUJmQMhJQBzAAACAAQJAQLBEAE1AAABLgAECgcJOgAdAG4PAA==.',
Kr='Kritanta:BAACLgAFFH8GAAIEAAMJrA3wKQClAAAEAAMJrA3wKQClAAAuAAQKfykAAgQACQnlDDcjADcBAAQACQnlDDcjADcBAAAA.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8gAAIUAAcJ/RBSNwA1AQAUAAcJ/RBSNwA1AQAAAA==.',
Ku='Kurnea:BAABLgAECn8aAAINAAkJsR08GQA7AgANAAkJsR08GQA7AgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.Kyipp:BAAALgADCgcJCAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Lachlann:BAAALgAECgIJAgAAAA==.Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8TAAMYAAUJ9hjwLAAMAQAYAAQJnRXwLAAMAQAXAAEJ4whTKQBJAAAuAAQKfyQABBgACQlPHWcVAC4CABgACQkTHGcVAC4CAB4ABglRE2wXAH8BABcAAQkcFKU5ADoAAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8XAAQKAAQJzST4AgB8AQAKAAQJzST4AgB8AQAjAAIJ+RWlAwC9AAAiAAEJACAuOQBWAAAuAAQKfywABAoACAkAJgQCALcCACIABwmqI2MLAN8CACMABwlWJUkCANcCAAoACAnJJQQCALcCAAEuAAUUCAkdAAQANCEA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAABLgAECn8VAAIEAAcJ2hVjIABNAQAEAAcJ2hVjIABNAQAAAA==.Leonedis:BAABLgAECn87AAIhAAgJ1BTFJADPAQAhAAgJ1BTFJADPAQAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8bAAQQAAcJzAyGswAaAQAQAAcJzAyGswAaAQAkAAIJZgRyEgA+AAApAAEJdQH5IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.Levious:BAAALgAFFAEJAQAAAA==.Lexo:BAAALgADCgkJCgABLgAECgcJFwAWAE0NAA==.',
Li='Liain:BAAALgADCgQJBAABLgAECgIJAgALAAAAAA==.Lianara:BAAALgAECgYJBwABLgAECgcJFwAWAEkHAA==.Lirazel:BAAALgAECgMJAwAAAA==.Litenkuk:BAACLgAFFH8GAAIZAAMJzw6IFgDnAAAZAAMJzw6IFgDnAAAuAAQKfyEAAxkACAnYHyERALICABkACAnYHyERALICAB8AAgkPD1ROAHUAAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJCQAIAJcfAA==.',
Lo='Lohin:BAABLgAFFH8FAAIWAAMJmxvgPgDkAAAWAAMJmxvgPgDkAAABLgAFFAYJCgAXAMoLAA==.Lonelycougar:BAAALgADCgcJDwAAAA==.Lothstein:BAABLgAECn8XAAIWAAgJGhA6PwCuAQAWAAgJGhA6PwCuAQAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Luan:BAAALgAECgcJDwAAAA==.Lukri:BAAALgAECggJDwAAAA==.Luminate:BAABLgAECn81AAIWAAkJqyEMCQAfAwAWAAkJqyEMCQAfAwAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn9DAAIcAAkJPwaLEwAXAQAcAAkJPwaLEwAXAQAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgAFFAMJBAAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgAECgEJAQAAAA==.Magicmoose:BAAALgADCgEJAQAAAA==.Magicwillow:BAAALgAECgUJBQAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQALAAAAAA==.Malachor:BAABLgAECn8jAAMEAAgJVBZzFwCpAQAEAAgJVBZzFwCpAQAGAAEJfgVePwAmAAAAAA==.Maligned:BAABLgAECn8tAAIEAAkJGRxpCgBqAgAEAAkJGRxpCgBqAgAAAA==.Malphias:BAAALgAECgUJCAAAAA==.Marsilea:BAAALgADCgcJCgABLgAECgIJAgALAAAAAA==.Martichoux:BAABLgAECn8XAAIQAAkJKR2xPwB6AgAQAAkJKR2xPwB6AgAAAA==.Marvyy:BAAALgAECgcJEAAAAA==.Mash:BAAALgAECgIJAgABLgAFFAQJBAALAAAAAA==.Mathas:BAABLgAECn8pAAINAAkJ2SEpEQCJAgANAAkJ2SEpEQCJAgAAAA==.Mathilda:BAABLgAECn8XAAIDAAcJpAE6QwFmAAADAAcJpAE6QwFmAAAAAA==.Maxpower:BAAALgAECgMJAwAAAA==.Mazes:BAACLgAFFH8GAAIiAAMJmCG8IAAaAQAiAAMJmCG8IAAaAQAuAAQKf0QAAyIACQnUIVYDABUDACIACQnUIVYDABUDACMAAQmoBOIhACgAAAAA.',
Mc='Mccholock:BAABLgAECn8rAAMhAAgJ7BlpHQACAgAhAAgJ7BlpHQACAgAoAAIJfBTmVAB+AAAAAA==.Mcllovin:BAAALgAECgEJAQAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Meddox:BAAALgADCgYJBgAAAA==.Mediocrepaly:BAAALgAECgcJEgAAAA==.Mehaoloka:BAAALgADCgkJCQAAAA==.Mekanthis:BAACLgAFFH8dAAMEAAgJNCE1BABbAgAEAAgJNCE1BABbAgAFAAEJWgPeEwE7AAAuAAQKfygAAgQACQmEJTsCAFEDAAQACQmEJTsCAFEDAAAA.Memelle:BAAALgAECgEJAQAAAA==.Menith:BAAALgAECgQJBwAAAA==.Menoah:BAABLgAECn8hAAIVAAkJshHtFQChAQAVAAkJshHtFQChAQAAAA==.Menopaws:BAAALgADCggJCAAAAA==.Menotthatorc:BAAALgAECgUJCAABLgAFFAEJAQALAAAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAABLgAECn8WAAIBAAkJKxpUEABjAgABAAkJKxpUEABjAgAAAA==.Mesilana:BAAALgAECgYJBgAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECgcJEgALAAAAAA==.Mirenna:BAABLgAECn8hAAIBAAkJdRj2DgB3AgABAAkJdRj2DgB3AgAAAA==.Mirra:BAAALgAECgIJAgAAAA==.Misseymiss:BAAALgAECgUJCAAAAA==.Missnewbooty:BAAALgAECgIJAQABLgAECgkJLwAEAH4QAA==.',
Mo='Mogwhy:BAABLgAECn8tAAIjAAkJIxboBAA3AgAjAAkJIxboBAA3AgAAAA==.Molbeato:BAAALgAECgEJAgAAAA==.Monichan:BAAALgAECgYJCgAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Monkfu:BAAALgADCgcJAQAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAABLgAECn8YAAInAAkJDRemHQC2AQAnAAkJDRemHQC2AQAAAA==.Moralekillas:BAABLgAFFH8PAAMjAAUJJxQIBQAwAQAjAAQJwhIIBQAwAQAiAAMJ8g1cMgCUAAAAAA==.Morecowbell:BAAALgAECgIJAgAAAA==.Morganna:BAAALgAECgEJAgAAAA==.Morior:BAABLgAECn8gAAIgAAkJhw1QDAB4AQAgAAkJhw1QDAB4AQAAAA==.Motorcade:BAABLgAECn8/AAInAAkJtgJvPQAEAQAnAAkJtgJvPQAEAQAAAA==.Mouthhugs:BAAALgAECgEJAQAAAA==.',
Mu='Muchoblades:BAABLgAECn8UAAIlAAgJpA3iJgA/AQAlAAgJpA3iJgA/AQAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAABLgAECn8UAAIRAAkJbhsXHABjAgARAAkJbhsXHABjAgABLgAFFAIJBgATAFkgAA==.',
My='Myronastus:BAAALgADCgEJAQAAAA==.',
Na='Naimaa:BAAALgAECgEJAgAAAA==.Najira:BAAALgAECgUJBQAAAA==.Narinn:BAAALgADCggJCAAAAA==.',
Ne='Neather:BAABLgAECn8pAAIQAAkJGRfgNwA3AgAQAAkJGRfgNwA3AgAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgUJDAAAAA==.Nexeon:BAAALgAECgUJBwABLgAECgkJHgASAIMUAA==.Nezkima:BAAALgAECgcJBwAAAA==.',
Nf='Nfg:BAAALgADCgYJCgAAAA==.',
Ni='Niare:BAAALgAECgMJAwAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAACLgAFFH8HAAICAAMJSxV4XADVAAACAAMJSxV4XADVAAAuAAQKfycAAgIACAmGH14iAEUCAAIACAmGH14iAEUCAAAA.Nira:BAABLgAECn8cAAIaAAkJRhxHCADwAgAaAAkJRhxHCADwAgAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Nonetoo:BAAALgAECgkJBAABLgAECgkJBwALAAAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8wAAMDAAkJISHSFwCzAgADAAkJISHSFwCzAgAMAAMJIRNCLQC0AAAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAABLgAECn8oAAIJAAgJPBZ/QQDbAQAJAAgJPBZ/QQDbAQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.Nyxion:BAAALgAECgEJAQABLgAECgcJCwALAAAAAA==.',
Oa='Oakarm:BAAALgAECgkJAgAAAA==.Oasis:BAAALgAECgEJAwAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJEgAAAA==.',
Od='Odielleb:BAAALgAECgUJBQAAAA==.Odyssius:BAABLgAECn8VAAIbAAcJJQ1biQAnAQAbAAcJJQ1biQAnAQAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECggJKQAWAEUGAA==.',
Ol='Oldandblind:BAAALgAECgYJCwAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAABLgAECn8XAAIWAAcJSQeGjwC2AAAWAAcJSQeGjwC2AAAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8eAAMJAAkJ0hpUYABHAQAJAAcJ4RlUYABHAQAZAAUJNRjISgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn88AAMOAAkJkSQuAgAoAwAOAAkJkSQuAgAoAwAhAAgJJw91MwDdAQAAAA==.',
Ov='Oversoul:BAAALgAECgEJAgAAAA==.',
Ow='Owlpha:BAAALgAECgYJCwAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIDAAgJUxF5cQCZAQADAAgJUxF5cQCZAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgAECgEJAQABLgAECggJMgADAG0XAA==.Panax:BAAALgADCgcJBwAAAA==.Pansolo:BAAALgADCgUJBQAAAA==.Parabellum:BAAALgADCgYJBgAAAA==.Parkér:BAAALgAECgMJBQAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECgkJJgALAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAABLgAECn8dAAIRAAcJlRSJOQCuAQARAAcJlRSJOQCuAQAAAA==.Pellito:BAAALgADCgkJDAAAAA==.Perpetrator:BAABLgAECn8+AAIEAAkJUwdRKAAQAQAEAAkJUwdRKAAQAQAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.Pikii:BAAALgAECgQJBwAAAA==.',
Po='Poepwn:BAABLgAECn84AAITAAcJHhdZKgDVAQATAAcJHhdZKgDVAQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Prokerz:BAAALgADCgkJCQAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgAECgIJAgAAAA==.',
Pu='Puffypanda:BAAALgAECgcJBwAAAA==.Putnamehere:BAAALgAECgEJAQAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pá']='Párker:BAAALgADCgYJBgAAAA==.',
['Pû']='Pûrplehaze:BAAALgAFFAIJAgAAAA==.',
Qu='Quelude:BAABLgAECn8UAAIYAAkJJQq6NwBOAQAYAAkJJQq6NwBOAQAAAA==.Quill:BAABLgAECn8VAAMRAAkJxRXwKQAKAgARAAkJxRXwKQAKAgAVAAMJwRMSIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQABLgAECgkJAQALAAAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rancidgreen:BAAALgAECgMJBAAAAA==.Rannick:BAABLgAECn8fAAIdAAgJrxMHDwC+AQAdAAgJrxMHDwC+AQAAAA==.Ranua:BAACLgAFFH8FAAIWAAMJpgxeWACZAAAWAAMJpgxeWACZAAAuAAQKf0IABBYACQkYJOQDAHwDABYACQkYJOQDAHwDAAgABwlOD25FABsBAB0AAQmJCSc+ADIAAAAA.Ratio:BAABLgAECn8iAAICAAkJCSCtDwDEAgACAAkJCSCtDwDEAgAAAA==.Ravenhunt:BAAALgAECgcJEQAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgkJEAAAAA==.Razlee:BAAALgADCgEJAgAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAFFAMJBAAAAA==.Redbreastman:BAABLgAECn8bAAQXAAcJshccDgDqAQAXAAcJshccDgDqAQAeAAQJkAuYGACQAAAYAAMJmgNJVQBvAAAAAA==.Reiner:BAAALgAECggJDwAAAA==.Rekka:BAAALgAFFAIJBAAAAA==.Reoshe:BAAALgAECgcJCQAAAA==.',
Ri='Ripdvanwinkl:BAABLgAECn8mAAMCAAgJgRJcVQCEAQACAAgJexJcVQCEAQAcAAQJyQ2FIwB/AAAAAA==.',
Ro='Roachpocket:BAAALgAECgYJCQAAAA==.Ronyn:BAABLgAECn8eAAMWAAkJhhoxHwBTAgAWAAgJVxoxHwBTAgAIAAIJ4xKdfwBuAAAAAA==.Rozefire:BAAALgAECgUJBQABLgAECgkJFgABACsaAA==.',
Ru='Rude:BAAALgADCgEJAQAAAA==.Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAABLgAECn8XAAIQAAYJuhIIrAAlAQAQAAYJuhIIrAAlAQAAAA==.',
['Rö']='Rötthgard:BAAALgADCgkJCgAAAA==.',
Sa='Salacake:BAAALgAECgEJAwAAAA==.Salacakei:BAABLgAECn8vAAMiAAkJgxvkDQBHAgAiAAkJgxvkDQBHAgAjAAQJBwv7EwC/AAAAAA==.Salin:BAAALgAECgcJEwAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Santarock:BAAALgADCgEJAQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgcJEAALAAAAAA==.Sarthiy:BAABLgAECn8fAAMMAAkJdh1pBwBpAgAMAAcJKiNpBwBpAgADAAYJqRSzjgBTAQABLgAFFAgJHQAMAIQZAA==.Sarthy:BAACLgAFFH8dAAIMAAgJhBn7AAAdAgAMAAgJhBn7AAAdAgAuAAQKfzUAAwwACQk5JGcAAJcDAAwACQk5JGcAAJcDAAMAAQlmDtuAATkAAAAA.Sassaphras:BAABLgAECn8VAAIBAAcJNx/kEQBSAgABAAcJNx/kEQBSAgAAAA==.Satheron:BAAALgAECgYJDwAAAA==.Satyric:BAAALgAECggJEgAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECggJEAAAAA==.Schnuggie:BAAALgAECgMJAwAAAA==.Scoobie:BAAALgAECgMJBQABLgAECggJJQAJAPYdAA==.Scoobydo:BAAALgAECgQJBgABLgAECggJJQAJAPYdAA==.Scratches:BAAALgAECgEJAgAAAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8jAAIJAAYJKA6bJABsAQAJAAYJKA6bJABsAQAuAAQKfzoAAgkACQneHvIbAHoCAAkACQneHvIbAHoCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.Sevrum:BAAALgADCgYJBwAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shadynastie:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgkJAgAAAA==.Shamyaltak:BAAALgAECgkJDgAAAA==.Shandralore:BAABLgAECn8hAAIZAAkJ0hncBQA8AgAZAAkJ0hncBQA8AgAAAA==.Shanleigh:BAAALgAECgEJAgAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAABLgAECn8rAAIPAAgJihl2CgAVAgAPAAgJihl2CgAVAgAAAA==.Shockdoctor:BAABLgAECn8mAAMWAAkJQyKGEgC3AgAWAAgJsiGGEgC3AgAIAAIJdRJIfAB3AAAAAA==.Shockzillah:BAAALgADCgkJCQAAAA==.Shogunasasin:BAABLgAECn8bAAMTAAgJBQ23KQBnAQATAAgJBQ23KQBnAQASAAMJuxqVTQDbAAAAAA==.Shortrange:BAABLgAECn8XAAIZAAcJlyGcBwAIAgAZAAcJlyGcBwAIAgAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAABLgAECn8mAAIOAAYJLAvaLwC+AAAOAAYJLAvaLwC+AAAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAABLgAECn8lAAMJAAgJ9h0zIABkAgAJAAgJ9h0zIABkAgAfAAYJVRXgLAA/AQAAAA==.Sleyalias:BAABLgAFFH8FAAIlAAMJ9QMFHwCfAAAlAAMJ9QMFHwCfAAAAAA==.Slufgor:BAAALgAECgYJEAAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAABLgAECn8iAAQmAAgJjR5rCgC2AQAbAAcJlRofRwDEAQAmAAYJcB5rCgC2AQAgAAEJnxLEawA8AAAAAA==.Snoogon:BAAALgAECgUJBgABLgAECggJIgAmAI0eAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.Snowcaine:BAAALgAECgEJAgAAAA==.',
So='Solarlite:BAABLgAECn8XAAIRAAYJLRPkTQBVAQARAAYJLRPkTQBVAQAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8VAAIaAAkJXSAFCAC/AgAaAAkJXSAFCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgYJCQAAAA==.Spony:BAABLgAECn8lAAIjAAcJ0A46DQBUAQAjAAcJ0A46DQBUAQAAAA==.',
St='Starbrow:BAAALgAECgQJCgABLgAECgkJHwAFAHgfAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJEQAAAA==.Stormlight:BAABLgAECn8WAAIRAAkJTQtVRwBwAQARAAkJTQtVRwBwAQAAAA==.Stárrk:BAAALgAECgEJAQAAAA==.',
Su='Sulevin:BAAALgAECgQJBAABLgAECgcJDQALAAAAAA==.Summernight:BAAALgAECgEJAgAAAA==.Sushistryke:BAABLgAECn8dAAIJAAcJBRVrVACjAQAJAAcJBRVrVACjAQAAAA==.',
Sv='Svend:BAAALgADCgEJAQAAAA==.',
Sy='Syland:BAABLgAECn8oAAIJAAgJUhigNgAAAgAJAAgJUhigNgAAAgAAAA==.Sylanis:BAAALgAECgEJAQAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAABLgAECn8bAAIJAAcJehf6WACWAQAJAAcJehf6WACWAQAAAA==.Sylvenna:BAABLgAECn8UAAMDAAcJDwuJtwATAQADAAcJDwuJtwATAQANAAQJQQcydgCiAAAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAABLgAECn80AAIHAAkJxSRFAgBLAwAHAAkJxSRFAgBLAwAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAACLgAFFH8GAAIWAAMJFAgjXQCNAAAWAAMJFAgjXQCNAAAuAAQKfygAAhYACQn4FPI1ANYBABYACQn4FPI1ANYBAAAA.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAABLgAECn8XAAMWAAcJTQ2JVQBcAQAWAAcJTQ2JVQBcAQAIAAcJTw54VwDbAAAAAA==.Tazanaz:BAAALgAECgQJCAABLgAFFAMJBQAWAKYMAA==.',
Te='Templeton:BAAALgAECgYJDQABLgAECggJKQAWAEUGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAABLgAECn8gAAIQAAYJgg35vwAHAQAQAAYJgg35vwAHAQAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8eAAIMAAcJkBnWFQB1AQAMAAcJkBnWFQB1AQAAAA==.Theemedic:BAAALgADCgYJBQAAAA==.Thegreatkhal:BAAALgADCggJCAABLgAECgkJGQAQABYYAA==.Thomasza:BAAALgAECgEJAQAAAA==.Thomii:BAAALgAECgEJAQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAABLgAECn83AAMWAAgJPSHeCwD6AgAWAAgJPSHeCwD6AgAIAAYJuRu8PAA/AQAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8WAAIEAAkJ9CCABgDOAgAEAAkJ9CCABgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8hAAIWAAQJaCBTIQBmAQAWAAQJaCBTIQBmAQAuAAQKf0sAAhYACQmqH8MOANsCABYACQmqH8MOANsCAAAA.',
Tr='Trailerpark:BAAALgAECgYJEgAAAA==.Tratre:BAACLgAFFH8IAAMYAAMJORVnPwDEAAAYAAMJORVnPwDEAAAeAAEJ2gWpDwA8AAAuAAQKf0UABBgACQnnGuoPAGkCABgACQnnGuoPAGkCABcABwkdDLQZADkBAB4ABAnJEaoaAHUAAAAA.Treynof:BAABLgAECn8dAAIUAAkJXQzLKwB1AQAUAAkJXQzLKwB1AQAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAABLgAECn8uAAIlAAgJNwvBJwA5AQAlAAgJNwvBJwA5AQAAAA==.',
Tu='Tulsiice:BAABLgAECn8ZAAIQAAkJFhhbPAAnAgAQAAkJFhhbPAAnAgAAAA==.',
Tw='Twoglaivez:BAAALgAECgcJEgABLgAFFAgJHwAhAPYeAA==.',
Ty='Tytaniormu:BAAALgAECgkJEgAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAALAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulanybelle:BAAALgADCgkJCQAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJCQAIAJcfAA==.',
Un='Undeathtwoy:BAACLgAFFH8HAAMEAAIJah+YQAAsAAAFAAIJah8suQCvAAAEAAEJTg+YQAAsAAAuAAQKfx8AAwUABwmlHWloAL0BAAUABwk/GmloAL0BAAQABQkmFDE0AMYAAAAA.Undos:BAAALgAECgEJAgAAAA==.Unholyveri:BAAALgAECgYJBwAAAA==.',
Va='Vaelraen:BAABLgAECn8jAAIDAAkJyRhYNwAjAgADAAkJyRhYNwAjAgAAAA==.Valcher:BAABLgAECn8lAAMRAAcJVAlKegDGAAARAAYJ/QdKegDGAAAUAAYJuwPUWwCiAAAAAA==.Valendera:BAABLgAECn8VAAIbAAkJEQsLYACpAQAbAAkJEQsLYACpAQAAAA==.Valerius:BAAALgAECgEJAQAAAA==.Valhri:BAAALgAECgYJCgAAAA==.Valifadin:BAABLgAECn8hAAIfAAkJxxwCBwCvAgAfAAkJxxwCBwCvAgAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valkenstein:BAAALgAECgIJAgABLgAFFAUJFAADAIwaAA==.Valmoria:BAAALgADCgkJFwAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJDAABLgAFFAMJBQAWAKYMAA==.Varch:BAABLgAECn8bAAIRAAkJJSFXBQBhAwARAAkJJSFXBQBhAwAAAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMGAAkJFB7oBQBNAgAGAAkJFB7oBQBNAgAFAAMJ4AoF/ACDAAAAAA==.Vera:BAAALgAECgEJAQAAAA==.',
Vi='Viktir:BAAALgAECgQJBAABLgAECgcJHQARAJUUAA==.Vintage:BAACLgAFFH8LAAIKAAMJjQ4VAQDsAAAKAAMJjQ4VAQDsAAAuAAQKfyIAAgoACQnpGfYAAAMDAAoACQnpGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAABLgAECn8UAAIFAAgJmyB2KwBRAgAFAAgJmyB2KwBRAgAAAA==.Volkareth:BAABLgAECn8VAAIeAAkJyhPRDQD9AQAeAAkJyhPRDQD9AQAAAA==.Vorkath:BAABLgAECn82AAQeAAkJNCMdAQAAAwAeAAkJNCMdAQAAAwAXAAgJrRwoCQBVAgAYAAMJqSB6QgAeAQAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAABLgAECn8aAAIJAAkJKAxuUwCmAQAJAAkJKAxuUwCmAQAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQADAFMRAA==.Wars:BAAALgADCgIJAgAAAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn9LAAMRAAkJQBsBEwCxAgARAAkJQBsBEwCxAgAPAAEJehLpTgA4AAAAAA==.',
Wi='Wilderbeast:BAABLgAECn8fAAIRAAkJdAXMYQAOAQARAAkJdAXMYQAOAQAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECggJKQAWAEUGAA==.Woxkal:BAABLgAECn8rAAMEAAcJIAuVMgDQAAAEAAcJIAuVMgDQAAAFAAEJ0AGwNwEhAAAAAA==.',
Wu='Wubblebubble:BAABLgAECn8vAAMEAAkJfhA8HQBsAQAEAAkJWw48HQBsAQAFAAUJFxGZxQD1AAAAAA==.',
Xa='Xaelin:BAABLgAECn8oAAIBAAgJ5BEvJACfAQABAAgJ5BEvJACfAQAAAA==.',
Ye='Yeimx:BAAALgAECgYJDAAAAA==.',
Yi='Yisús:BAAALgAECgUJCwAAAA==.',
Yl='Ylvis:BAABLgAECn8tAAIJAAkJSBWLNgABAgAJAAkJSBWLNgABAgAAAA==.',
Yo='Yoshymi:BAAALgAECgkJJgAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECggJDAABLgAFFAEJAQALAAAAAA==.',
Za='Zacco:BAABLgAECn8xAAIDAAgJtw4bgABtAQADAAgJtw4bgABtAQAAAA==.Zalaric:BAAALgAFFAIJAgABLgAFFAYJCgAXAMoLAA==.Zaleth:BAACLgAFFH8KAAIXAAYJygvIGQDzAAAXAAYJygvIGQDzAAAuAAQKfykAAhcABwkYIakIALACABcABwkYIakIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAABLgAECn8lAAIFAAkJXgyPXwCoAQAFAAkJXgyPXwCoAQAAAA==.Zargar:BAAALgADCggJCQAAAA==.Zarion:BAAALgAECgYJCAABLgAFFAYJCgAXAMoLAA==.Zarra:BAAALgAECgYJDAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.Zatre:BAAALgAECgUJBQAAAA==.',
Ze='Zeroz:BAAALgAFFAEJAQAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAABLgAECn8hAAINAAcJiSPuDQCzAgANAAcJiSPuDQCzAgABLgAFFAYJCgAXAMoLAA==.',
Zo='Zocorro:BAABLgAECn8UAAIHAAcJqhMYLwBjAQAHAAcJqhMYLwBjAQAAAA==.Zodiack:BAAALgAECgcJCgAAAA==.Zombe:BAABLgAECn8VAAIFAAgJCAmzegCPAQAFAAgJCAmzegCPAQAAAA==.',
Zu='Zuelmst:BAAALgAECgQJBgAAAA==.',
Zy='Zypherdius:BAAALgADCgYJDwAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQABLgAFFAQJCAAgANgGAA==.',
['Ðe']='Ðecision:BAACLgAFFH8VAAIDAAUJpSScGQCdAQADAAUJpSScGQCdAQAuAAQKfyoAAgMACQkNJa8HAC4DAAMACQkNJa8HAC4DAAAA.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQADAFMRAA==.',
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
