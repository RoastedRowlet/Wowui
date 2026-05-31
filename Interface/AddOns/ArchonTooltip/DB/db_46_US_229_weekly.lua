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

local lookup = {'DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Unknown-Unknown','Paladin-Protection','Paladin-Holy','Warrior-Protection','Druid-Feral','Priest-Holy','Mage-Frost','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Warlock-Demonology','DemonHunter-Vengeance','Shaman-Enhancement','Evoker-Devastation','Hunter-Survival','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Warrior-Fury','Mage-Fire','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Warrior-Arms','Mage-Arcane',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-05-31',data={Aa='Aaralyn:BAAALgAECgYJCAAAAA==.',
Ab='Abmikaze:BAAALgAECgkJDgAAAA==.Abor:BAAALgADCgMJAwAAAA==.',
Ad='Addition:BAAALgAECgYJBgABLgAECggJIQABADwgAA==.Adimus:BAAALgADCgIJAgAAAA==.Adorean:BAABLgAECn8vAAICAAkJAx6rFwCgAgACAAkJAx6rFwCgAgAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn8oAAICAAgJfhl/QwDkAQACAAgJfhl/QwDkAQAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAABLgAECn8XAAICAAYJxA8HtgD7AAACAAYJxA8HtgD7AAAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akaril:BAAALgADCgQJBAABLgAFFAIJBgADAIMTAA==.Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alaileath:BAAALgADCgEJAQAAAA==.Alaryk:BAAALgAECgEJAQAAAA==.Alburm:BAABLgAECn8aAAMEAAgJBiGBIAB1AgAEAAgJBiGBIAB1AgAFAAEJHwr1MgAtAAAAAA==.Alexstraxsa:BAAALgAECgUJBQAAAA==.Aliine:BAABLgAECn81AAIDAAkJlRgPDAAzAgADAAkJlRgPDAAzAgAAAA==.Ally:BAAALgAECgQJBwABLgAECggJIQABADwgAA==.Althaea:BAABLgAECn8VAAIGAAgJ0wG1WwB8AAAGAAgJ0wG1WwB8AAAAAA==.',
Am='Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAACLgAFFH8NAAIHAAMJxhH4KgDKAAAHAAMJxhH4KgDKAAAuAAQKf0YAAgcACQnQIJkHANMCAAcACQnQIJkHANMCAAAA.',
An='Anahana:BAAALgAECgYJDQAAAA==.Anali:BAAALgADCggJGAAAAA==.Andi:BAAALgAECgcJEAAAAA==.Andorelia:BAABLgAECn8qAAICAAkJExCmTQDHAQACAAkJExCmTQDHAQAAAA==.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAAALgAECgcJEgAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAcJGQAIAK4jAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAABLgAECn8ZAAICAAgJNAfPpwARAQACAAgJNAfPpwARAQAAAA==.Appleborne:BAAALgADCgcJBwABLgADCgMJBQAJAAAAAA==.Appleseed:BAAALgADCgMJBQAAAA==.Apprentice:BAABLgAECn80AAIKAAkJBgL4KAC4AAAKAAkJBgL4KAC4AAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCgAAAA==.Aramos:BAABLgAECn8wAAILAAkJvBnnFwA0AgALAAkJvBnnFwA0AgAAAA==.Aramôs:BAABLgAECn8mAAILAAgJphIDJADSAQALAAgJphIDJADSAQAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDAAJAAAAAA==.Arlowhite:BAAALgAECgMJAwAAAA==.Arta:BAABLgAECn8jAAIMAAgJrRneEQC4AQAMAAgJrRneEQC4AQAAAA==.Artachoke:BAAALgAECgMJAwAAAA==.Aruncusdio:BAABLgAECn8cAAINAAgJbAZfHQD7AAANAAgJbAZfHQD7AAAAAA==.',
As='Ashhealz:BAABLgAECn8wAAIOAAgJ2RQuGQDtAQAOAAgJ2RQuGQDtAQAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgUJBgAAAA==.Astronomical:BAAALgAECgEJAQABLgAECgUJBgAJAAAAAA==.',
At='Atelwen:BAAALgAECgYJEwAAAA==.',
Av='Aveme:BAABLgAECn8wAAIPAAkJCiMtGQAUAwAPAAkJCiMtGQAUAwAAAA==.',
Aw='Awartedpeen:BAABLgAECn8mAAIQAAgJiwooYQACAQAQAAgJiwooYQACAQAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAAJAAAAAA==.Aznarak:BAAALgAECgYJBgAAAA==.Azuleon:BAABLgAECn8eAAMRAAkJgxRXHQDwAQARAAYJ6B1XHQDwAQASAAkJNg5XMACOAQAAAA==.Azuresky:BAAALgADCgEJAgAAAA==.',
Ba='Badsnapple:BAAALgAECgkJDwABLgADCgMJBQAJAAAAAA==.Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgAECgUJBQAAAA==.Balbit:BAAALgADCgQJBAAAAA==.Bamber:BAAALgADCggJDQAAAA==.Barrywhite:BAAALgAECgcJCgAAAA==.Bast:BAAALgAECgEJAgAAAA==.Battar:BAAALgAECgEJAgAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn82AAMTAAkJ+BqiDQBqAgATAAkJRBmiDQBqAgAUAAYJ+hAsKQDsAAAAAA==.Beakerstime:BAAALgAECgIJAwAAAA==.Beastmode:BAABLgAECn8tAAIQAAkJaxvaFQCIAgAQAAkJaxvaFQCIAgAAAA==.Beckyg:BAAALgADCgEJAQAAAA==.Bedlem:BAABLgAECn8bAAIEAAcJzAixoQAWAQAEAAcJzAixoQAWAQAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwAJAAAAAA==.Bernard:BAABLgAECn8mAAMVAAgJRQaFXwAOAQAVAAgJRQaFXwAOAQAHAAcJFQkKSgDzAAAAAA==.',
Bi='Bidoof:BAABLgAECn8mAAMWAAgJvRaDCwARAgAWAAgJvRaDCwARAgAXAAcJRg8fQQAGAQAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAABLgAECn8lAAMYAAgJTA09WACFAQAYAAgJTA09WACFAQAZAAYJnAFjawCRAAAAAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAECgkJLQAOAOsaAA==.Blackgrace:BAAALgAECggJDQAAAA==.Blacklisted:BAABLgAECn8tAAQOAAkJ6xqpDACFAgAOAAkJ6xqpDACFAgAaAAEJgwr6bwAuAAAGAAEJdQYxgAArAAAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAAALgADCggJCgAAAA==.Blessurheart:BAAALgADCgIJAgAAAA==.Bloodbladesz:BAAALgADCgEJAQABLgAECggJFQARAJceAA==.Bloodybloodz:BAAALgAECgUJCAABLgAECggJFQARAJceAA==.Bloodyburst:BAAALgAECgEJAQABLgAECggJFQARAJceAA==.Bloodyfistz:BAABLgAECn8VAAMRAAgJlx4zOgACAQARAAcJnh0zOgACAQASAAUJegsPQwDSAAAAAA==.Blueboost:BAAALgADCgQJBAAAAA==.Blueshift:BAABLgAECn8WAAIBAAkJChc+QwDnAQABAAkJChc+QwDnAQAAAA==.Bluethreetwo:BAABLgAECn8YAAQEAAYJ5AfEwwDjAAAEAAYJ5AfEwwDjAAADAAEJXgNAWgAiAAAFAAEJxQSSOgARAAAAAA==.Blurry:BAAALgADCgUJBgAAAA==.',
Bo='Bookofzeref:BAABLgAECn8UAAIbAAgJWBLpYwBtAQAbAAgJWBLpYwBtAQAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAABLgAECn8fAAIcAAYJmhwADQBtAQAcAAYJmhwADQBtAQAAAA==.Brayend:BAABLgAECn8lAAIdAAgJQhq6CQAJAgAdAAgJQhq6CQAJAgAAAA==.Brewbelly:BAAALgADCgcJCQAAAA==.Brimscythe:BAABLgAECn8xAAIeAAkJIB/9AQCkAgAeAAkJIB/9AQCkAgAAAA==.Brutälity:BAAALgAECggJBgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.Bulish:BAAALgADCgMJAwAAAA==.',
Ca='Caliandis:BAABLgAECn8ZAAIMAAgJxQqBIAAWAQAMAAgJxQqBIAAWAQAAAA==.Calvey:BAAALgAECgUJCgAAAA==.Cambrai:BAABLgAECn8XAAIRAAcJLBFjLwA1AQARAAcJLBFjLwA1AQAAAA==.Cannabelle:BAACLgAFFH8JAAIfAAMJoR/ZEwAjAQAfAAMJoR/ZEwAjAQAuAAQKfzgAAh8ACQlAJQMBAGcDAB8ACQlAJQMBAGcDAAAA.Cannabeth:BAAALgAFFAEJAQAAAA==.Canto:BAAALgAECgQJBAAAAA==.Captpickle:BAAALgAECggJDgAAAA==.Carclias:BAACLgAFFH8FAAMgAAMJKQ08CwDCAAAgAAMJKQ08CwDCAAAbAAEJkA/brgBFAAAuAAQKfxoAAyAACQl0Gi4HAFcCACAACAl+Gy4HAFcCABsAAwnmCYcQAUUAAAAA.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAAALgAECgYJEgAAAA==.Catmove:BAAALgAECgUJBQAAAA==.Cattlerage:BAAALgAECgYJEwAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.Cerdelz:BAAALgAECgYJBgAAAA==.Cerena:BAAALgAECgIJAwAAAA==.',
Ch='Chaoscookies:BAABLgAECn82AAMgAAkJ7xkKDABjAQAgAAYJlx0KDABjAQAbAAUJSRXeggAqAQAAAA==.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAABLgAECn8UAAIdAAYJYBlLEwBlAQAdAAYJYBlLEwBlAQAAAA==.Cheechee:BAAALgAECgYJEAAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Choofi:BAABLgAECn8bAAIQAAcJKBQRPQCOAQAQAAcJKBQRPQCOAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAFFAUJFQAHAHoTAA==.',
Ci='Ciená:BAAALgAECgQJBQAAAA==.Cin:BAABLgAECn8YAAIEAAgJSiHEGgCUAgAEAAgJSiHEGgCUAgAAAA==.Cinderpetal:BAAALgAECgQJBQAAAA==.',
Co='Cohemew:BAAALgAECgIJAwABLgAECggJCwAJAAAAAA==.Comlock:BAABLgAECn8WAAMbAAYJMQaB1wCYAAAbAAYJugSB1wCYAAAgAAIJSwgUQQAaAAAAAA==.Complacent:BAABLgAECn82AAIUAAkJ7wFiPACPAAAUAAkJ7wFiPACPAAAAAA==.Comrage:BAAALgADCgQJBAAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgQJBQAAAA==.Corik:BAAALgADCgMJAwAAAA==.',
Cr='Cragn:BAABLgAECn8dAAICAAgJxRKsXgCcAQACAAgJxRKsXgCcAQAAAA==.Crownman:BAAALgADCgkJFwAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuddilz:BAABLgAECn8dAAMhAAgJlRYsDwAhAQAiAAgJwBLnIgBlAQAhAAYJ3RIsDwAhAQAAAA==.Cursedchild:BAAALgAFFAMJBAAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8vAAIbAAkJjR2eEQC0AgAbAAkJjR2eEQC0AgAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAABLgAECn8/AAIDAAkJUB4CBwCaAgADAAkJUB4CBwCaAgAAAA==.',
['Cé']='Cécé:BAABLgAECn8qAAICAAcJJCN6KgBAAgACAAcJJCN6KgBAAgAAAA==.',
Da='Daciana:BAABLgAECn8nAAIYAAgJDiAHHgBeAgAYAAgJDiAHHgBeAgAAAA==.Dagaroonie:BAAALgAECgkJEAAAAA==.Dagevas:BAABLgAECn8lAAIbAAkJ1RK8QgDJAQAbAAkJ1RK8QgDJAQAAAA==.Darinius:BAAALgAECgEJAQAAAA==.Darkeznite:BAABLgAECn8ZAAIYAAgJ1BgKQADNAQAYAAgJ1BgKQADNAQAAAA==.Darksoldier:BAABLgAFFH8FAAIYAAQJBgwcPAAZAQAYAAQJBgwcPAAZAQAAAA==.Dartoy:BAACLgAFFH8FAAIjAAMJlh1cJAAJAQAjAAMJlh1cJAAJAQAuAAQKfzkAAiMACQljDr8hANIBACMACQljDr8hANIBAAAA.Davriell:BAAALgAECgcJDQAAAA==.Dax:BAABLgAECn8dAAIYAAgJghkhNgDwAQAYAAgJghkhNgDwAQAAAA==.Dazling:BAAALgAECggJEQAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAABLgAECn8VAAIgAAYJSh8eDwDZAQAgAAYJSh8eDwDZAQAAAA==.Deeppurple:BAABLgAECn8ZAAIkAAYJBgmACADiAAAkAAYJBgmACADiAAAAAA==.Deezmons:BAABLgAECn8rAAIlAAkJTRA7GQCZAQAlAAkJTRA7GQCZAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn82AAIcAAkJTSY0AABzAwAcAAkJTSY0AABzAwAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAAALgAECgcJDwAAAA==.Demonkirby:BAAALgADCgUJBwAAAA==.Demonlarrik:BAAALgAECgEJAQAAAA==.Derale:BAABLgAECn8aAAMXAAgJiw0EJgCNAQAXAAgJiA0EJgCNAQAeAAcJXQQyIgAZAQAAAA==.Destoroyah:BAAALgADCgQJBAAAAA==.',
Dh='Dhargal:BAACLgAFFH8HAAIHAAMJch8FJADzAAAHAAMJch8FJADzAAAuAAQKfzsAAgcACQk+JOACADYDAAcACQk+JOACADYDAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAABLgAECn8dAAIQAAgJHA2XRgBjAQAQAAgJHA2XRgBjAQAAAA==.',
Dk='Dkfaros:BAABLgAECn8fAAIEAAkJeB8cGQCeAgAEAAkJeB8cGQCeAgAAAA==.',
Do='Dommenica:BAAALgADCgYJBgAAAA==.Donko:BAAALgADCggJCAABLgAECgcJEgAJAAAAAA==.Dontcarebear:BAABLgAECn8dAAIUAAgJIAXVNQCsAAAUAAgJIAXVNQCsAAAAAA==.Doofnshmirtz:BAABLgAECn8vAAIdAAkJ4BwZBgBjAgAdAAkJ4BwZBgBjAgAAAA==.Dorkwiz:BAAALgADCgMJAwAAAA==.Dorow:BAAALgAECggJEAAAAA==.Dotpocket:BAABLgAECn8qAAIbAAkJ4RisKQAnAgAbAAkJ4RisKQAnAgAAAA==.',
Dr='Dragonash:BAAALgAECgUJBgAAAA==.Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECggJEQAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dreams:BAABLgAECn9IAAMYAAkJ9R8zDQDXAgAYAAkJ9R8zDQDXAgAZAAMJ1QZNdABtAAAAAA==.Dremmy:BAAALgAECgYJEQAAAA==.Drey:BAAALgADCgEJAQAAAA==.Drinkme:BAAALgAECgMJAwAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAACLgAFFH8KAAIdAAMJMBRECgDwAAAdAAMJMBRECgDwAAAuAAQKfy8AAh0ACQlAIfQBAP0CAB0ACQlAIfQBAP0CAAAA.',
Du='Dunsel:BAAALgAECggJEgABLgAECgkJMQAeACAfAA==.Dunwich:BAAALgADCgcJIAAAAA==.Durostan:BAAALgAECgEJAgAAAA==.',
Dv='Dvali:BAABLgAECn8UAAIBAAcJWwhjjQDpAAABAAcJWwhjjQDpAAAAAA==.',
Dy='Dyorra:BAABLgAECn8gAAMLAAgJRwngRwAJAQALAAcJXQbgRwAJAQACAAYJ1AQr7wCtAAAAAA==.',
['Dä']='Dämon:BAAALgADCgIJAgAAAA==.',
Eb='Ebonshade:BAAALgAECgUJCAAAAA==.',
Ed='Edgardapoe:BAAALgAECgMJAwABLgAECggJCwAJAAAAAA==.Edginglord:BAAALgAECgYJBwAAAA==.',
Eh='Ehmill:BAABLgAECn8pAAIEAAkJoxmMKABNAgAEAAkJoxmMKABNAgAAAA==.',
El='Elesrya:BAAALgAECgEJAQABLgAECggJKAACAH4ZAA==.Elgringo:BAAALgAECgcJAwAAAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAAALgAECgYJDwAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgkJAQAAAA==.',
Er='Ernest:BAAALgADCgUJCQAAAA==.Errani:BAABLgAECn8XAAIPAAcJeQsHngAlAQAPAAcJeQsHngAlAQAAAA==.',
Es='Eskers:BAABLgAECn8dAAIeAAkJ9Ry/AgBzAgAeAAkJ9Ry/AgBzAgAAAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8nAAIBAAkJwg3aVABxAQABAAkJwg3aVABxAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8bAAIPAAcJKgLz9ACbAAAPAAcJKgLz9ACbAAAAAA==.Evocane:BAABLgAECn8VAAIPAAYJDA44sAAHAQAPAAYJDA44sAAHAQAAAA==.Evocati:BAAALgAECgUJBgABLgAFFAYJDgACAHsWAA==.Evocatis:BAACLgAFFH8OAAMCAAYJexaNGwB2AQACAAYJexaNGwB2AQALAAEJRAvrQwA2AAAuAAQKfyUAAwIACQkZITUeALYCAAIACAl5IzUeALYCAAsAAwkOCxF2AKIAAAAA.Evoorc:BAAALgAECggJDwAAAA==.',
Ex='Ex:BAABLgAECn8jAAIgAAgJqQzpDwArAQAgAAgJqQzpDwArAQAAAA==.',
Fa='Faasht:BAAALgAECgEJAQAAAA==.Faoris:BAAALgAECgUJBgAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Feebs:BAAALgAECgMJBQAAAA==.Felheart:BAAALgAECgMJAwABLgAFFAMJCwACAIoWAA==.Felzbirt:BAAALgAECgUJCQAAAA==.Fenehdis:BAAALgAECgcJDQAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgAECgYJBgABLgAECggJIgABAPALAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAYJDgAQALsSAA==.Firebirdz:BAACLgAFFH8OAAIQAAYJuxL4EADDAQAQAAYJuxL4EADDAQAuAAQKfycAAxAACQnVIbAIAAMDABAACQnVIbAIAAMDABMACAnPFmUaAN8BAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAYJDgAQALsSAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzledust:BAAALgAECgEJAgAAAA==.Fizzystomps:BAAALgAECgQJBgAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forginn:BAAALgAECgEJAQABLgAFFAcJJQAOAIQZAA==.Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Friargark:BAAALgADCgkJDwAAAA==.Frostatute:BAAALgADCgcJBwAAAA==.Frostypaw:BAAALgADCgYJCgAAAA==.Frostzilla:BAAALgAECgYJCQAAAA==.',
Fu='Fuzzybut:BAABLgAECn8nAAIUAAgJCBwaCgAnAgAUAAgJCBwaCgAnAgAAAA==.',
Fy='Fyuna:BAAALgAFFAIJAgAAAA==.',
Ga='Gandalph:BAAALgAECgQJBQAAAA==.Gark:BAAALgAECgYJEQAAAA==.Garkk:BAAALgADCgcJDwAAAA==.Gazzi:BAAALgAECgkJEgAAAA==.',
Ge='Geargust:BAAALgAECgkJAgAAAA==.Georgebenson:BAAALgADCgQJBAAAAA==.',
Gi='Gióvanna:BAAALgAECgQJCQAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECggJHgAmAI0eAA==.',
Go='Goblndeznutz:BAAALgAECgEJAQAAAA==.Goobow:BAACLgAFFH8RAAIEAAQJ3BWITgA4AQAEAAQJ3BWITgA4AQAuAAQKf0QAAgQACQlcIT4IACQDAAQACQlcIT4IACQDAAAA.Goodheavens:BAAALgAECgQJBwAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJCAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8lAAIPAAkJ9Q3NdwDiAQAPAAkJ9Q3NdwDiAQAAAA==.',
Gr='Gr:BAABLgAECn8bAAIQAAcJThbMNQCxAQAQAAcJThbMNQCxAQAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8kAAIUAAgJxBkpDQDxAQAUAAgJxBkpDQDxAQAAAA==.Grody:BAAALgAECgEJAQAAAA==.Grumpias:BAAALgAECgcJCQABLgAECgkJJgANAH8cAA==.',
Gu='Guroo:BAABLgAECn80AAIYAAkJ7xLNOgDfAQAYAAkJ7xLNOgDfAQAAAA==.',
['Gá']='Gárp:BAAALgAECggJDgAAAA==.',
['Gø']='Gødoth:BAACLgAFFH8HAAIHAAIJthqGMQCrAAAHAAIJthqGMQCrAAAuAAQKfyQAAwcACAlhIAgUADUCAAcACAlhIAgUADUCABUABQkQIvM7AJIBAAAA.',
Ha='Hagarn:BAACLgAFFH8MAAICAAQJPQknRgAJAQACAAQJPQknRgAJAQAuAAQKfzkAAgIACQkZF5kzABsCAAIACQkZF5kzABsCAAAA.Haithem:BAAALgAECgEJAgAAAA==.Halimah:BAAALgAECgEJAgAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Harbek:BAAALgAECgcJCwAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harleysmol:BAAALgAECgkJAgAAAA==.Harlydorable:BAABLgAECn8YAAInAAUJWCBXJQByAQAnAAUJWCBXJQByAQAAAA==.Harryphotter:BAAALgADCgEJAQAAAA==.Hazan:BAABLgAECn8VAAIoAAYJlxuYFgCRAQAoAAYJlxuYFgCRAQABLgAFFAQJCgAdADAUAA==.Hazystar:BAAALgAECgcJDQAAAA==.',
He='Healmemaybe:BAABLgAECn8ZAAICAAYJCxJFswD/AAACAAYJCxJFswD/AAAAAA==.Hemogoblin:BAAALgAECgIJAgABLgAECgkJFwAPACkdAA==.Hemour:BAABLgAECn8fAAIEAAgJEAtAdQBnAQAEAAgJEAtAdQBnAQAAAA==.Hexmachine:BAAALgAFFAIJAgAAAA==.Hexyou:BAAALgAECgIJAgAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAcJJQAOAIQZAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAABLgAECn8dAAIOAAcJ2BaMHwCzAQAOAAcJ2BaMHwCzAQAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.Huntzcatzup:BAAALgADCgYJBgAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAABLgAECn8xAAIHAAkJgA2KKgCHAQAHAAkJgA2KKgCHAQAAAA==.Iamthanatos:BAAALgAECgcJEgAAAA==.',
Id='Idblastdat:BAABLgAECn8zAAIPAAkJURy6HgCRAgAPAAkJURy6HgCRAgAAAA==.',
Ig='Ignite:BAABLgAECn8bAAIPAAgJLx/aIwB4AgAPAAgJLx/aIwB4AgAAAA==.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8+AAICAAkJBxlPLAA4AgACAAkJBxlPLAA4AgAAAA==.Illumiscotty:BAABLgAECn84AAQPAAkJ9CXUAwBdAwAPAAkJ9CXUAwBdAwApAAUJtB7tBwAKAQAkAAEJ3BAuEQAxAAAAAA==.Ilwey:BAAALgAECgcJEAAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAInAAYJPB9JJgDSAQAnAAYJPB9JJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAnADwfAA==.Imodium:BAAALgADCgEJAQAAAA==.',
In='Insania:BAABLgAECn82AAMVAAkJNRtwIAA0AgAVAAgJuxpwIAA0AgAdAAIJjQUWLABkAAAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgAECgEJAQAAAA==.',
Ir='Ironhands:BAAALgAECgcJDgAAAA==.',
Iz='Izara:BAAALgAECgEJAQAAAA==.',
Ja='Jarlmaxim:BAAALgAECgYJDAABLgAECggJDQAJAAAAAA==.Jasindra:BAAALgAECgcJDwABLgAECgkJQAAVABgkAA==.Jaspally:BAAALgAECgcJDAABLgAECgkJQAAVABgkAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.',
Jo='Johnnycash:BAAALgAECgEJAQAAAA==.Jolinascrubs:BAABLgAECn9CAAIKAAkJ2xBvEQCXAQAKAAkJ2xBvEQCXAQABLgAFFAUJGwAYAAcOAA==.Jonjee:BAABLgAECn8YAAICAAkJIR1QMQBdAgACAAkJIR1QMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn80AAICAAkJcSDbEQDFAgACAAkJcSDbEQDFAgAAAA==.',
Ka='Kahekili:BAAALgAECgMJBQAAAA==.Kain:BAABLgAECn8VAAIPAAcJrBwVUwDMAQAPAAcJrBwVUwDMAQAAAA==.Kalagren:BAABLgAECn8XAAIYAAUJHQffvgCoAAAYAAUJHQffvgCoAAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAACLgAFFH8PAAIiAAQJKCBbDQCEAQAiAAQJKCBbDQCEAQAuAAQKfz8AAyIACQm2JJEFAMkCACIACAlwJJEFAMkCACEAAgkaFMoaAHIAAAAA.Kavaria:BAAALgAECgIJAgAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAABLgAECn8fAAIjAAgJEQmqOgBIAQAjAAgJEQmqOgBIAQAAAA==.',
Ke='Keerah:BAABLgAECn8aAAMBAAkJuAPekADiAAABAAkJuAPekADiAAAcAAUJmQF6JgBXAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgEJAQAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8eAAIbAAcJoBxrCwAXAgAbAAcJoBxrCwAXAgAuAAQKfywAAhsACQlbJVAEAHYDABsACQlbJVAEAHYDAAAA.Kexkan:BAABLgAECn8kAAIjAAgJNhz7EwA/AgAjAAgJNhz7EwA/AgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8VAAINAAkJtx47BgCaAgANAAkJtx47BgCaAgAAAA==.',
Ki='Kiarah:BAABLgAECn8bAAILAAYJ0wpQSQACAQALAAYJ0wpQSQACAQAAAA==.Killerbuster:BAAALgAECgMJAwABLgAECgMJAwAJAAAAAA==.Killplz:BAAALgADCgcJEgAAAA==.Kirr:BAAALgAECgcJDQAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgcJCQAAAA==.Kitchenstink:BAABLgAECn8YAAIoAAkJ4B4VBAC0AgAoAAkJ4B4VBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8wAAIBAAkJ/xRzNADfAQABAAkJ/xRzNADfAQAAAA==.',
Ko='Kordh:BAABLgAECn81AAQdAAcJbg9CEQCjAQAdAAcJew5CEQCjAQAVAAcJVQ0eXgAmAQAHAAcJyg51QwAMAQAAAA==.Kordiza:BAABLgAECn8YAAQlAAYJ9weeNgDBAAAlAAYJ9weeNgDBAAAcAAUJmQPKIQBzAAABAAQJAQLG/wAwAAABLgAECgcJNQAdAG4PAA==.',
Kr='Kritanta:BAABLgAECn8pAAIDAAkJ5QxtHwBCAQADAAkJ5QxtHwBCAQAAAA==.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8fAAITAAYJyhK5OwAIAQATAAYJyhK5OwAIAQAAAA==.',
Ku='Kurnea:BAABLgAECn8ZAAILAAgJsh8aHQAGAgALAAgJsh8aHQAGAgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8RAAIXAAQJ0RQTJwALAQAXAAQJ0RQTJwALAQAuAAQKfyQABBcACQlPHcsTACcCABcACQkTHMsTACcCAB4ABglRE2wXAH8BABYAAQkcFBY2ADoAAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8WAAQIAAQJzSQEAgCIAQAIAAQJzSQEAgCIAQAhAAIJ+RWlAwC9AAAiAAEJACBWMQBeAAAuAAQKfywABAgACAkAJr0BALgCACIABwmqI2MLAN8CACEABwlWJUkCANcCAAgACAnJJb0BALgCAAEuAAUUBwkbAAMA0iAA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAAALgAECgYJEgAAAA==.Leonedis:BAABLgAECn8vAAIjAAgJYBCdLACPAQAjAAgJYBCdLACPAQAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8bAAQPAAcJzAxPpgAYAQAPAAcJzAxPpgAYAQAkAAIJZgSfDwBBAAApAAEJdQH5IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.Levious:BAAALgAFFAEJAQAAAA==.Lexo:BAAALgADCgkJCgABLgAECgcJEgAJAAAAAA==.',
Li='Liain:BAAALgADCgQJBAABLgAECgIJAgAJAAAAAA==.Lianara:BAAALgAECgQJBAABLgAECgYJEgAJAAAAAA==.Litenkuk:BAACLgAFFH8GAAIZAAMJzw6IFgDnAAAZAAMJzw6IFgDnAAAuAAQKfyEAAxkACAnYHyERALICABkACAnYHyERALICAB8AAgkPD2BJAHgAAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJBwAHAHIfAA==.',
Lo='Lohin:BAABLgAFFH8FAAIVAAMJmxtVNQDvAAAVAAMJmxtVNQDvAAABLgAFFAYJCgAWAMoLAA==.Lonelycougar:BAAALgADCgcJDwAAAA==.Lothstein:BAABLgAECn8WAAIVAAcJ0Q9WRwB3AQAVAAcJ0Q9WRwB3AQAAAA==.Lovely:BAAALgAECgcJDQAAAA==.',
Lu='Luan:BAAALgADCgUJBQAAAA==.Lukri:BAAALgAECgYJBwAAAA==.Luminate:BAABLgAECn81AAIVAAkJqyGzBwAjAwAVAAkJqyGzBwAjAwAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn8xAAIcAAkJRwQyEgASAQAcAAkJRwQyEgASAQAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAAALgAFFAIJAgAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgAECgEJAQAAAA==.Magicmoose:BAAALgADCgEJAQAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQAJAAAAAA==.Malachor:BAABLgAECn8hAAMDAAgJVBRMGACIAQADAAgJVBRMGACIAQAFAAEJfgWnNwAhAAAAAA==.Maligned:BAABLgAECn8tAAIDAAkJGRzvCABzAgADAAkJGRzvCABzAgAAAA==.Malphias:BAAALgAECgQJBAAAAA==.Marsilea:BAAALgADCgcJCgABLgAECgIJAgAJAAAAAA==.Martichoux:BAABLgAECn8XAAIPAAkJKR2xPwB6AgAPAAkJKR2xPwB6AgAAAA==.Marvyy:BAAALgAECgYJCgAAAA==.Mash:BAAALgAECgIJAgABLgAFFAQJBAAJAAAAAA==.Mathas:BAABLgAECn8pAAILAAkJ2SEpEQCJAgALAAkJ2SEpEQCJAgAAAA==.Mathilda:BAAALgAECgYJEQAAAA==.Maxpower:BAAALgAECgMJAwAAAA==.Mazes:BAACLgAFFH8GAAIiAAMJmCEvGgAsAQAiAAMJmCEvGgAsAQAuAAQKfz8AAyIACQnAII0DAP8CACIACQnAII0DAP8CACEAAQmoBOIhACgAAAAA.',
Mc='Mccholock:BAABLgAECn8nAAMjAAgJnhlWHQDyAQAjAAgJ+xhWHQDyAQAoAAIJfBT2SwCBAAAAAA==.Mcllovin:BAAALgAECgEJAQAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Meddox:BAAALgADCgYJBgAAAA==.Mediocrepaly:BAAALgAECgcJEgAAAA==.Mehaoloka:BAAALgADCgkJCQAAAA==.Mekanthis:BAACLgAFFH8bAAIDAAcJ0iBsBQAFAgADAAcJ0iBsBQAFAgAuAAQKfygAAgMACQmEJTsCAFEDAAMACQmEJTsCAFEDAAAA.Menith:BAAALgAECgQJBQAAAA==.Menoah:BAABLgAECn8fAAIUAAgJsRIZFwB4AQAUAAgJsRIZFwB4AQAAAA==.Menopaws:BAAALgADCggJCAAAAA==.Menotthatorc:BAAALgAECgUJBgABLgAECggJCwAJAAAAAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAABLgAECn8UAAIOAAgJOxo7FAAgAgAOAAgJOxo7FAAgAgAAAA==.Mesilana:BAAALgAECgYJBgAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECgcJEgAJAAAAAA==.Mirenna:BAABLgAECn8fAAIOAAgJ8xlIEABRAgAOAAgJ8xlIEABRAgAAAA==.Mirra:BAAALgAECgIJAgAAAA==.Misseymiss:BAAALgAECgUJBgAAAA==.Missnewbooty:BAAALgAECgIJAQABLgAECgkJLwADAH4QAA==.',
Mo='Mogwhy:BAABLgAECn8tAAIhAAkJIxZrBAA5AgAhAAkJIxZrBAA5AgAAAA==.Molbeato:BAAALgAECgEJAgAAAA==.Monichan:BAAALgAECgQJBwAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Monkfu:BAAALgADCgcJAQAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAABLgAECn8XAAInAAkJ+BWKHQCpAQAnAAkJ+BWKHQCpAQAAAA==.Moralekillas:BAABLgAFFH8NAAMhAAQJJxQpBAA8AQAhAAQJwhIpBAA8AQAiAAEJfhUiMgBTAAAAAA==.Morecowbell:BAAALgAECgIJAgAAAA==.Morganna:BAAALgAECgEJAgAAAA==.Morior:BAABLgAECn8eAAIgAAgJvwzHDgA6AQAgAAgJvwzHDgA6AQAAAA==.Motorcade:BAABLgAECn8xAAInAAkJrgIfOgAEAQAnAAkJrgIfOgAEAQAAAA==.Mouthhugs:BAAALgAECgEJAQAAAA==.',
Mu='Muchoblades:BAAALgAECgcJEgAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAABLgAECn8UAAIQAAkJbhscGgBkAgAQAAkJbhscGgBkAgAAAA==.',
My='Myronastus:BAAALgADCgEJAQAAAA==.',
Na='Naimaa:BAAALgAECgEJAQAAAA==.Najira:BAAALgAECgUJBQAAAA==.Narinn:BAAALgADCggJCAAAAA==.',
Ne='Neather:BAABLgAECn8mAAIPAAgJYxSdVQDFAQAPAAgJYxSdVQDFAQAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgUJCAAAAA==.Nexeon:BAAALgAECgUJBwABLgAECgkJHgARAIMUAA==.',
Ni='Niare:BAAALgAECgMJAwAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAABLgAECn8nAAIBAAgJhh9nHwBFAgABAAgJhh9nHwBFAgAAAA==.Nira:BAABLgAECn8cAAIaAAkJRhwVBwDxAgAaAAkJRhwVBwDxAgAAAA==.',
No='Nockturne:BAAALgADCgMJAwAAAA==.Nonetoo:BAAALgAECgkJAQAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8uAAMCAAkJ0SBAFQCvAgACAAkJ0SBAFQCvAgAKAAMJIROWKQC1AAAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAABLgAECn8kAAIYAAgJiBSkPgDRAQAYAAgJiBSkPgDRAQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nyseria:BAAALgADCgEJAQAAAA==.Nyxion:BAAALgAECgEJAQABLgAECgUJCAAJAAAAAA==.',
Oa='Oakarm:BAAALgAECgkJAgAAAA==.Oasis:BAAALgAECgEJAgAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJEgAAAA==.',
Od='Odyssius:BAABLgAECn8UAAIbAAYJhg6EkwAMAQAbAAYJhg6EkwAMAQAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECggJJgAVAEUGAA==.',
Ol='Oldandblind:BAAALgAECgYJCwAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAAALgAECgYJEgAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8cAAMYAAgJ0RtUYABHAQAYAAYJFhtUYABHAQAZAAUJNRjISgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn88AAMMAAkJkSSkAQA2AwAMAAkJkSSkAQA2AwAjAAgJJw91MwDdAQAAAA==.',
Ow='Owlpha:BAAALgAECgYJCwAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAICAAgJUxF5cQCZAQACAAgJUxF5cQCZAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgAECgEJAQABLgAECggJJwACAG0XAA==.Panax:BAAALgADCgcJBwAAAA==.Parabellum:BAAALgADCgYJBgAAAA==.Parkér:BAAALgAECgMJBQAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECgkJJgAJAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAABLgAECn8ZAAIQAAYJfhJ5SwBPAQAQAAYJfhJ5SwBPAQAAAA==.Perpetrator:BAABLgAECn8yAAIDAAkJxQZ2JQAQAQADAAkJxQZ2JQAQAQAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.',
Po='Poepwn:BAABLgAECn8sAAISAAcJMRRTLwCUAQASAAcJMRRTLwCUAQAAAA==.',
Pr='Priestbot:BAAALgADCgcJCwAAAA==.Prokerz:BAAALgADCgkJCQAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgADCgQJBwAAAA==.',
Pu='Puffypanda:BAAALgAECgQJBAAAAA==.Putnamehere:BAAALgAECgEJAQAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAECgMJAwAAAA==.',
Qu='Quelude:BAABLgAECn8UAAIXAAkJJQoVNABDAQAXAAkJJQoVNABDAQAAAA==.Quill:BAABLgAECn8VAAMQAAkJxRXwKQAKAgAQAAkJxRXwKQAKAgAUAAMJwRMSIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQABLgAECgkJAQAJAAAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Rancidgreen:BAAALgAECgMJBAAAAA==.Rannick:BAABLgAECn8dAAIdAAcJxhIEEwBpAQAdAAcJxhIEEwBpAQAAAA==.Ranua:BAABLgAECn9AAAQVAAkJGCT6AgCBAwAVAAkJGCT6AgCBAwAHAAcJTg/gPgAfAQAdAAEJiQmfNgAyAAAAAA==.Ratio:BAABLgAECn8hAAIBAAgJPCDBGQBoAgABAAgJPCDBGQBoAgAAAA==.Ravenhunt:BAAALgAECgcJEQAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgkJEAAAAA==.Razlee:BAAALgADCgEJAgAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAFFAMJAwAAAA==.Redbreastman:BAABLgAECn8ZAAQWAAYJ5hrNDgDPAQAWAAYJ5hrNDgDPAQAeAAQJkAu7FgCUAAAXAAMJmgNJVQBvAAAAAA==.Reiner:BAAALgAECggJDwAAAA==.Rekka:BAAALgAECgQJBAAAAA==.Reoshe:BAAALgAECgEJAgAAAA==.',
Ri='Ripdvanwinkl:BAABLgAECn8hAAMBAAgJgRI6UwB2AQABAAgJvBE6UwB2AQAcAAQJyQ1iIAB/AAAAAA==.',
Ro='Roachpocket:BAAALgAECgYJCQAAAA==.Ronyn:BAABLgAECn8cAAMVAAgJuRpeJwAKAgAVAAcJiRpeJwAKAgAHAAIJ4xJUdABwAAAAAA==.Rozefire:BAAALgAECgUJBQABLgAECggJFAAOADsaAA==.',
Ru='Rudolf:BAAALgAECgQJBQAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAABLgAECn8XAAIPAAYJuhIQpAAbAQAPAAYJuhIQpAAbAQAAAA==.',
['Rö']='Rötthgard:BAAALgADCgkJCgAAAA==.',
Sa='Salacake:BAAALgAECgEJAgAAAA==.Salacakei:BAABLgAECn8vAAMiAAkJgxsmDABMAgAiAAkJgxsmDABMAgAhAAQJBwv7EwC/AAAAAA==.Salin:BAAALgAECgcJEgAAAA==.Salithril:BAAALgADCgMJBQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgcJEAAJAAAAAA==.Sarthiy:BAABLgAECn8fAAMKAAkJdh1pBwBpAgAKAAcJKiNpBwBpAgACAAYJqRSMfwBWAQABLgAFFAcJHAAKANYbAA==.Sarthy:BAACLgAFFH8cAAIKAAcJ1hvxAADaAQAKAAcJ1hvxAADaAQAuAAQKfzUAAwoACQk5JGcAAJcDAAoACQk5JGcAAJcDAAIAAQlmDtphATkAAAAA.Sassaphras:BAABLgAECn8VAAIOAAcJNx/kEQBSAgAOAAcJNx/kEQBSAgAAAA==.Satheron:BAAALgAECgYJDwAAAA==.Satyric:BAAALgAECggJEAAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECggJEAAAAA==.Schnuggie:BAAALgAECgMJAwAAAA==.Scoobie:BAAALgAECgMJBAABLgAECggJIwAYAG8dAA==.Scoobydo:BAAALgAECgQJBgABLgAECggJIwAYAG8dAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8bAAIYAAUJBw5KDQD1AAAYAAUJBw5KDQD1AAAuAAQKfzEAAhgACQkvHVQfAEkCABgACQkvHVQfAEkCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgkJAgAAAA==.Shamyaltak:BAAALgAECgkJDAAAAA==.Shandralore:BAABLgAECn8fAAIZAAgJThn1BwDuAQAZAAgJThn1BwDuAQAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAABLgAECn8nAAINAAgJ2xiICQAOAgANAAgJ2xiICQAOAgAAAA==.Shockdoctor:BAABLgAECn8lAAMVAAkJoCTvFQCDAgAVAAcJPSTvFQCDAgAHAAIJdRKFcQB4AAAAAA==.Shockzillah:BAAALgADCgkJCQAAAA==.Shogunasasin:BAABLgAECn8bAAMSAAgJBQ23KQBnAQASAAgJBQ23KQBnAQARAAMJuxqVTQDbAAAAAA==.Shortrange:BAABLgAECn8XAAIZAAcJlyG+BgAOAgAZAAcJlyG+BgAOAgAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAABLgAECn8YAAIMAAUJywpXMwCYAAAMAAUJywpXMwCYAAAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.',
Sl='Sleples:BAABLgAECn8jAAMYAAgJbx3uGwBqAgAYAAgJbx3uGwBqAgAfAAYJVRWhKQBGAQAAAA==.Sleyalias:BAABLgAFFH8FAAIlAAMJ9QOPGACjAAAlAAMJ9QOPGACjAAAAAA==.Slufgor:BAAALgAECgYJEAAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAABLgAECn8eAAQmAAgJjR7ICAC7AQAbAAcJlRpfQQDNAQAmAAYJcB7ICAC7AQAgAAEJnxLEawA8AAAAAA==.Snoogon:BAAALgAECgUJBgABLgAECggJHgAmAI0eAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.Snowingout:BAAALgAECgEJAgAAAA==.',
So='Solarlite:BAAALgAECgYJEQAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8VAAIaAAkJXSAFCAC/AgAaAAkJXSAFCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgYJCQAAAA==.Spony:BAABLgAECn8cAAIhAAYJ+wz4DwATAQAhAAYJ+wz4DwATAQAAAA==.',
St='Starbrow:BAAALgAECgQJCgABLgAECgkJHwAEAHgfAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJEQAAAA==.Stormlight:BAABLgAECn8VAAIQAAgJOgyVSgBTAQAQAAgJOgyVSgBTAQAAAA==.',
Su='Summernight:BAAALgAECgEJAgAAAA==.Sushistryke:BAABLgAECn8YAAIYAAcJpxBSXwByAQAYAAcJpxBSXwByAQAAAA==.',
Sv='Svend:BAAALgADCgEJAQAAAA==.',
Sy='Syland:BAABLgAECn8kAAIYAAgJWReSMgD9AQAYAAgJWReSMgD9AQAAAA==.Sylanis:BAAALgAECgEJAQAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAAALgAECgkJEQAAAA==.Sylvenna:BAABLgAECn8UAAMCAAcJDwsIqwAMAQACAAcJDwsIqwAMAQALAAQJQQcydgCiAAAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAABLgAECn8uAAIGAAgJTCRTBwDEAgAGAAgJTCRTBwDEAgAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Talley:BAABLgAECn8oAAIVAAkJ+BREMQDWAQAVAAkJ+BREMQDWAQAAAA==.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAAALgAECgcJEgAAAA==.Tazanaz:BAAALgAECgQJCAABLgAECgkJQAAVABgkAA==.',
Te='Templeton:BAAALgAECgYJDQABLgAECggJJgAVAEUGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAABLgAECn8aAAIPAAYJDQoHyQDfAAAPAAYJDQoHyQDfAAAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8eAAIKAAcJkBm6EwB4AQAKAAcJkBm6EwB4AQAAAA==.Theemedic:BAAALgADCgYJBQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAABLgAECn8wAAMVAAgJGSA3DADjAgAVAAgJGSA3DADjAgAHAAYJuRsVNwBDAQAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgMJAwAAAA==.',
To='Tomma:BAABLgAECn8WAAIDAAkJ9CCABgDOAgADAAkJ9CCABgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8ZAAIVAAQJQR1iHgBTAQAVAAQJQR1iHgBTAQAuAAQKf0sAAhUACQmqH6MMAN4CABUACQmqH6MMAN4CAAAA.',
Tr='Trailerpark:BAAALgAECgYJEQAAAA==.Tratre:BAABLgAECn83AAQXAAkJxBaZGAD7AQAXAAkJxBaZGAD7AQAWAAcJ7gmaGgAeAQAeAAEJYxIZPQA6AAAAAA==.Treynof:BAABLgAECn8cAAITAAgJ1Aw7MABDAQATAAgJ1Aw7MABDAQAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAABLgAECn8jAAIlAAgJUQmvJgAjAQAlAAgJUQmvJgAjAQAAAA==.',
Tu='Tulsiice:BAABLgAECn8YAAIPAAgJ/BeRTwDXAQAPAAgJ/BeRTwDXAQAAAA==.',
Tw='Twoglaivez:BAAALgAECgcJEgABLgAFFAcJHgAjAMEgAA==.',
Ty='Tytaniormu:BAAALgAECgkJEgAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAAJAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulanybelle:BAAALgADCgkJCQAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJBwAHAHIfAA==.',
Un='Undeathtwoy:BAACLgAFFH8GAAMDAAIJgxNqNgAuAAAEAAIJgxPHsQCUAAADAAEJTg9qNgAuAAAuAAQKfx8AAwQABwmlHWloAL0BAAQABwk/GmloAL0BAAMABQkmFLQvAMoAAAAA.Undos:BAAALgAECgEJAgAAAA==.Unholyveri:BAAALgAECgYJBwAAAA==.',
Va='Vaelraen:BAABLgAECn8gAAICAAkJyRi3MAAmAgACAAkJyRi3MAAmAgAAAA==.Valcher:BAABLgAECn8bAAMQAAYJdQc5dQDGAAAQAAYJdQc5dQDGAAATAAUJDAQrWQCTAAAAAA==.Valendera:BAABLgAECn8VAAIbAAkJEQsLYACpAQAbAAkJEQsLYACpAQAAAA==.Valerius:BAAALgAECgEJAQAAAA==.Valhri:BAAALgAECgYJCgAAAA==.Valifadin:BAABLgAECn8fAAIfAAgJ0BvdDABLAgAfAAgJ0BvdDABLAgAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valkenstein:BAAALgAECgEJAQABLgAFFAMJCwACAIoWAA==.Valmoria:BAAALgADCgkJFwAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJDAABLgAECgkJQAAVABgkAA==.Varch:BAABLgAECn8bAAIQAAkJJSGzBABjAwAQAAkJJSGzBABjAwAAAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMFAAkJFB6qBABTAgAFAAkJFB6qBABTAgAEAAMJ4AoF/ACDAAAAAA==.Vera:BAAALgAECgEJAQAAAA==.',
Vi='Viktir:BAAALgADCgkJFQABLgAECgYJGQAQAH4SAA==.Vintage:BAACLgAFFH8LAAIIAAMJjQ4VAQDsAAAIAAMJjQ4VAQDsAAAuAAQKfyIAAggACQnpGfYAAAMDAAgACQnpGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAABLgAECn8UAAIEAAgJmyAtJgBYAgAEAAgJmyAtJgBYAgAAAA==.Volkareth:BAABLgAECn8VAAIeAAkJyhPRDQD9AQAeAAkJyhPRDQD9AQAAAA==.Vorkath:BAABLgAECn82AAQeAAkJNCP3AAAGAwAeAAkJNCP3AAAGAwAWAAgJrRyECABXAgAXAAMJqSBUPQAWAQAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAABLgAECn8ZAAIYAAgJygxIXgB1AQAYAAgJygxIXgB1AQAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQACAFMRAA==.Wars:BAAALgADCgIJAgAAAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn86AAMQAAgJZxv6GQBlAgAQAAgJZxv6GQBlAgANAAEJNxBwQwA5AAAAAA==.',
Wi='Wilderbeast:BAABLgAECn8fAAIQAAkJdAWQWwAUAQAQAAkJdAWQWwAUAQAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECggJJgAVAEUGAA==.Woxkal:BAABLgAECn8rAAMDAAcJIAvYLQDXAAADAAcJIAvYLQDXAAAEAAEJ0AGwNwEhAAAAAA==.',
Wu='Wubblebubble:BAABLgAECn8vAAMDAAkJfhAPGgB1AQADAAkJWw4PGgB1AQAEAAUJFxHCtgD2AAAAAA==.',
Xa='Xaelin:BAABLgAECn8kAAIOAAgJ0w+9JQCDAQAOAAgJ0w+9JQCDAQAAAA==.',
Ye='Yeimx:BAAALgAECgMJAwAAAA==.',
Yi='Yisús:BAAALgAECgUJCQAAAA==.',
Yl='Ylvis:BAABLgAECn8tAAIYAAkJSBVpLgAOAgAYAAkJSBVpLgAOAgAAAA==.',
Yo='Yoshymi:BAAALgAECgkJJgAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECggJCwAAAA==.',
Za='Zacco:BAABLgAECn8xAAICAAgJtw5QcwBuAQACAAgJtw5QcwBuAQAAAA==.Zalaric:BAAALgAECgEJAgABLgAFFAYJCgAWAMoLAA==.Zaleth:BAACLgAFFH8KAAIWAAYJyguqFgANAQAWAAYJyguqFgANAQAuAAQKfykAAhYABwkYIakIALACABYABwkYIakIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAABLgAECn8lAAIEAAkJXgwyVgCxAQAEAAkJXgwyVgCxAQAAAA==.Zargar:BAAALgADCggJCQAAAA==.Zarion:BAAALgAECgYJCAABLgAFFAYJCgAWAMoLAA==.Zarra:BAAALgAECgYJDAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.',
Ze='Zeroz:BAAALgAFFAEJAQAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAABLgAECn8fAAILAAcJiSNaDAC2AgALAAcJiSNaDAC2AgABLgAFFAYJCgAWAMoLAA==.',
Zo='Zocorro:BAAALgAECgYJEQAAAA==.Zodiack:BAAALgAECgcJCgAAAA==.Zombe:BAABLgAECn8VAAIEAAgJCAmzegCPAQAEAAgJCAmzegCPAQAAAA==.',
Zu='Zuelmst:BAAALgAECgQJBgAAAA==.',
Zy='Zypherdius:BAAALgADCgUJCgAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQABLgAECgkJGQAgAMgWAA==.',
['Ðe']='Ðecision:BAACLgAFFH8NAAICAAMJsSQsNQArAQACAAMJsSQsNQArAQAuAAQKfyoAAgIACQkNJfAFADIDAAIACQkNJfAFADIDAAAA.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQACAFMRAA==.',
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
