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

local lookup = {'Priest-Holy','Hunter-BeastMastery','DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Priest-Shadow','Shaman-Elemental','Rogue-Outlaw','Priest-Discipline','Paladin-Protection','Paladin-Holy','Unknown-Unknown','Warrior-Protection','Druid-Feral','Mage-Frost','Druid-Restoration','Monk-Windwalker','Monk-Mistweaver','Shaman-Enhancement','Druid-Balance','Druid-Guardian','Shaman-Restoration','Evoker-Preservation','Evoker-Augmentation','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','DemonHunter-Vengeance','Evoker-Devastation','Hunter-Survival','Warrior-Fury','Mage-Arcane','Rogue-Subtlety','Rogue-Assassination','Mage-Fire','DemonHunter-Havoc','Warlock-Affliction','Monk-Brewmaster','Warrior-Arms',}
local provider = {region='US',realm='Uldum',name='US',type='weekly',zone=46,date='2026-07-05',data={Aa='Aaralyn:BAABLgAECn8XAAIBAAcJIxAkKACFAQABAAcJIxAkKACFAQAAAA==.',
Ab='Abmikaze:BAAALgAECgkJDgAAAA==.Abor:BAAALgADCgMJAwAAAA==.Absolon:BAAALgAECgUJBQABLgAECggJGAACAFEcAA==.',
Ad='Addition:BAAALgAECgYJBgABLgAECgkJIwADAFwgAA==.Adimus:BAAALgADCgMJAwAAAA==.Adorean:BAABLgAECn8vAAIEAAkJAx5THACbAgAEAAkJAx5THACbAgAAAA==.',
Ae='Aeginau:BAAALgAECgMJAwAAAA==.Aenymbria:BAABLgAECn88AAIEAAkJEx4fBAD2AQAEAAkJEx4fBAD2AQAAAA==.Aerbear:BAAALgADCgUJCAAAAA==.',
Ag='Age:BAABLgAECn8XAAIEAAYJxA/JyQD7AAAEAAYJxA/JyQD7AAAAAA==.',
Ai='Aimnskin:BAAALgADCggJEgAAAA==.',
Ak='Akaril:BAAALgAFFAEJAQABLgAFFAMJDAAFANocAA==.Akuaa:BAAALgADCgMJAwAAAA==.',
Al='Alaileath:BAAALgADCgEJAQAAAA==.Alaryk:BAAALgAECgEJAQAAAA==.Alburm:BAACLgAFFH8IAAIFAAMJtBLjLwDeAAAFAAMJtBLjLwDeAAAuAAQKfxoAAwUACAkGIX0lAG4CAAUACAkGIX0lAG4CAAYAAQkfCio/ACgAAAAA.Alexstraxsa:BAABLgAECn8YAAIEAAgJowkCEQDtAAAEAAgJowkCEQDtAAAAAA==.Aliine:BAABLgAECn86AAIHAAkJtRj+DQAqAgAHAAkJtRj+DQAqAgAAAA==.Ally:BAAALgAECgQJBwABLgAECgkJIwADAFwgAA==.Althaea:BAABLgAECn8VAAIIAAgJ0wGQZACJAAAIAAgJ0wGQZACJAAAAAA==.',
Am='Ambchan:BAAALgAECgMJAwAAAA==.Ameiisaa:BAAALgADCgcJCgAAAA==.Amytiel:BAACLgAFFH8fAAIJAAQJehX6CwAQAQAJAAQJehX6CwAQAQAuAAQKf1IAAgkACQlTIWsHAOUCAAkACQlTIWsHAOUCAAAA.',
An='Anabelle:BAAALgADCggJGAAAAA==.Anahana:BAAALgAECgYJDQAAAA==.Anatomxx:BAAALgAECgYJCAAAAA==.Andi:BAAALgAECgcJEAAAAA==.Andorelia:BAACLgAFFH8FAAIEAAIJVQRAOwBtAAAEAAIJVQRAOwBtAAAuAAQKfzMAAgQACQllEQVOAN0BAAQACQllEQVOAN0BAAAA.Andronocus:BAAALgADCggJFQAAAA==.Anko:BAAALgADCgQJAwAAAA==.Anxie:BAABLgAECn8aAAICAAgJGwwsfABHAQACAAgJGwwsfABHAQAAAA==.Anìtamaxwynn:BAAALgAECgYJCwABLgAFFAgJGgAKAB0jAA==.',
Ao='Aoifae:BAAALgAECgEJAgAAAA==.',
Ap='Apally:BAAALgAECgQJCQAAAA==.Apexmaster:BAABLgAECn8bAAIEAAkJ1AflkQBPAQAEAAkJ1AflkQBPAQAAAA==.Appleborne:BAAALgADCgcJBwABLgAFFAUJCwALAFUFAA==.Applecider:BAABLgAFFH8LAAILAAUJVQXZDQD9AAALAAUJVQXZDQD9AAAAAA==.Appleseed:BAAALgADCgMJBQABLgAFFAUJCwALAFUFAA==.Apprentice:BAABLgAECn9SAAIMAAkJNQMpBgCjAAAMAAkJNQMpBgCjAAAAAA==.',
Ar='Aragorn:BAAALgAECgYJCgAAAA==.Aramos:BAACLgAFFH8MAAINAAMJ5RSYEQCXAAANAAMJ5RSYEQCXAAAuAAQKfzAAAg0ACQm8GcMaAC8CAA0ACQm8GcMaAC8CAAAA.Aramôs:BAABLgAECn82AAINAAkJnhQZJQDeAQANAAkJnhQZJQDeAQAAAA==.Ares:BAAALgADCgYJDwAAAA==.Arinathia:BAAALgAECgcJAQABLgAECgkJDgAOAAAAAA==.Arlowhite:BAAALgAECgMJAwAAAA==.Arta:BAABLgAECn8tAAIPAAkJEhorEADkAQAPAAkJEhorEADkAQAAAA==.Artachoke:BAAALgAECgYJCQAAAA==.Aruncusdio:BAABLgAECn8cAAIQAAgJbAaVIgD1AAAQAAgJbAaVIgD1AAAAAA==.Arysta:BAAALgAECgQJBQAAAA==.',
As='Ashhealz:BAABLgAECn88AAIBAAkJnhcvGAAMAgABAAkJnhcvGAAMAgAAAA==.Ashlei:BAAALgADCgEJAQAAAA==.Asteroid:BAAALgAECgUJBgAAAA==.Astronomical:BAAALgAECgIJAgABLgAECgUJBgAOAAAAAA==.',
At='Atelwen:BAAALgAECgYJEwAAAA==.',
Av='Aveme:BAABLgAECn8wAAIRAAkJCiMtGQAUAwARAAkJCiMtGQAUAwAAAA==.',
Aw='Awartedpeen:BAABLgAECn8vAAISAAkJBQtjaAD7AAASAAkJBQtjaAD7AAAAAA==.',
Az='Azael:BAAALgAECgEJAQABLgAECgIJBAAOAAAAAA==.Aznarak:BAAALgAECgYJBgAAAA==.Azuleon:BAABLgAECn8eAAMTAAkJgxRXHQDwAQATAAYJ6B1XHQDwAQAUAAkJNg69OACPAQAAAA==.',
Ba='Badsnapple:BAABLgAECn8WAAIVAAkJUw+PDgDIAQAVAAkJUw+PDgDIAQABLgAFFAUJCwALAFUFAA==.Bagelmancer:BAAALgADCgUJBQAAAA==.Bageluwu:BAAALgAECgUJBQAAAA==.Balbit:BAAALgADCgQJBAAAAA==.Bamber:BAAALgADCggJDQAAAA==.Bamboo:BAAALgAECgEJAQAAAA==.Barrywhite:BAAALgAECgcJDwAAAA==.Basicampfire:BAAALgAECggJCAABLgAECgkJDAAOAAAAAA==.Bast:BAAALgAECgEJAgAAAA==.Battar:BAAALgAECgEJAwAAAA==.Bayraktar:BAAALgADCgkJDgAAAA==.',
Bb='Bbads:BAAALgADCgIJAgAAAA==.',
Be='Beaker:BAABLgAECn83AAMWAAkJKBzXDwBjAgAWAAkJcxrXDwBjAgAXAAYJ+hB2MADpAAAAAA==.Beakerstime:BAAALgAECgIJAwAAAA==.Beastmode:BAABLgAECn8tAAISAAkJaxv/FwCHAgASAAkJaxv/FwCHAgAAAA==.Beckyg:BAAALgADCgEJAQAAAA==.Bedlem:BAABLgAECn8cAAIFAAgJIgmRswAPAQAFAAgJIgmRswAPAQAAAA==.Beerchaplain:BAAALgADCgcJFgABLgAECgcJBwAOAAAAAA==.Belwas:BAAALgAECgEJAQABLgAECgkJPAAEABMeAA==.Bernard:BAABLgAECn8rAAMYAAkJ2waFXwAOAQAYAAkJ2waFXwAOAQAJAAcJIQuRSwAHAQAAAA==.',
Bi='Bidoof:BAABLgAECn8nAAMZAAgJLhdjDAAPAgAZAAgJLhdjDAAPAgAaAAcJRg/qRwALAQAAAA==.Bigolman:BAAALgAECgEJAQAAAA==.Biochemguy:BAAALgAECgUJAQAAAA==.Birgitte:BAACLgAFFH8KAAICAAQJAgrYTQAQAQACAAQJAgrYTQAQAQAuAAQKfygAAwIACAmDDwxYAJwBAAIACAmDDwxYAJwBABsABgmcAWNrAJEAAAAA.Bishop:BAAALgADCgUJBQABLgAECggJGgACABsMAA==.',
Bl='Blackelvis:BAAALgADCgcJBwABLgAFFAQJBwAYAOkWAA==.Blackgrace:BAAALgAECggJDQAAAA==.Blacklisted:BAABLgAECn8tAAQBAAkJ6xrfDgB6AgABAAkJ6xrfDgB6AgALAAEJgwqOfwAsAAAIAAEJdQYnkAAqAAABLgAFFAQJBwAYAOkWAA==.Blackpanthxr:BAABLgAFFH8HAAIYAAQJ6RbhDwAQAQAYAAQJ6RbhDwAQAQAAAA==.Blackup:BAAALgAECgMJAwAAAA==.Blackvortex:BAABLgAECn8VAAIcAAgJHxEJAgBAAQAcAAgJHxEJAgBAAQAAAA==.Blessurheart:BAAALgADCgIJAgAAAA==.Bloodbladesz:BAAALgADCgEJAQABLgAFFAEJAQAOAAAAAA==.Bloodybloodz:BAAALgAFFAEJAQAAAA==.Bloodyburst:BAAALgAECgcJCAABLgAFFAEJAQAOAAAAAA==.Bloodyfistz:BAABLgAECn8VAAMTAAgJlx5EQAD+AAATAAcJnh1EQAD+AAAUAAUJegsPQwDSAAABLgAFFAEJAQAOAAAAAA==.Blueboost:BAAALgAECgkJCQAAAA==.Blueshift:BAABLgAECn8WAAIDAAkJChc+QwDnAQADAAkJChc+QwDnAQAAAA==.Bluethreetwo:BAABLgAECn8fAAQFAAYJFgmS1wDeAAAFAAYJ5AeS1wDeAAAGAAQJ4QQNCwA2AAAHAAEJXgNXZAAhAAAAAA==.Blurry:BAAALgADCgUJBgAAAA==.',
Bo='Bookofzeref:BAABLgAECn8VAAIdAAkJ1hA5bABjAQAdAAkJ1hA5bABjAQAAAA==.',
Br='Brahruhanu:BAEALgADCgUJCAAAAA==.Braile:BAABLgAECn8rAAIeAAgJ3RslBwAUAgAeAAgJ3RslBwAUAgAAAA==.Brayend:BAABLgAECn8zAAIVAAkJYhubBgBvAgAVAAkJYhubBgBvAgAAAA==.Brewbelly:BAAALgADCgcJCQAAAA==.Brimscythe:BAABLgAECn8xAAIfAAkJIB9cAgCdAgAfAAkJIB9cAgCdAgAAAA==.Brutälity:BAAALgAECgkJBgAAAA==.',
Bu='Bubbleup:BAAALgADCgUJBQAAAA==.Bulish:BAAALgADCgMJAwAAAA==.',
Ca='Caliandis:BAABLgAECn8cAAIPAAkJPAvWHABPAQAPAAkJPAvWHABPAQAAAA==.Calvey:BAAALgAECgcJDQAAAA==.Cambrai:BAABLgAECn8YAAITAAgJnhFWKQBwAQATAAgJnhFWKQBwAQAAAA==.Cannabelle:BAACLgAFFH8PAAIgAAMJSCTsEwAsAQAgAAMJSCTsEwAsAQAuAAQKfzgAAiAACQlAJQMBAGcDACAACQlAJQMBAGcDAAAA.Cannabeth:BAABLgAFFH8LAAIGAAMJghADFgDaAAAGAAMJghADFgDaAAAAAA==.Canto:BAAALgAECgQJBAAAAA==.Captpickle:BAAALgAECgkJEgAAAA==.Carclias:BAACLgAFFH8IAAMcAAQJ/w3iCAAKAQAcAAQJ/w3iCAAKAQAdAAEJkA/HTABGAAAuAAQKfxoAAxwACQl0Gi4HAFcCABwACAl+Gy4HAFcCAB0AAwnmCRMkAUQAAAAA.Carmenere:BAAALgADCgUJCQAAAA==.Carthrix:BAABLgAECn8jAAIhAAkJxBTIAQAEAgAhAAkJxBTIAQAEAgAAAA==.Catmove:BAAALgAECgUJBQAAAA==.Cattlerage:BAABLgAECn8hAAICAAcJjxKzCABwAQACAAcJjxKzCABwAQAAAA==.',
Ce='Cedo:BAAALgADCgUJBQAAAA==.Celéste:BAAALgADCgcJBwAAAA==.Cerdelz:BAAALgAECgYJBgAAAA==.Cerena:BAAALgAECgIJAwAAAA==.',
Ch='Chaoscookies:BAACLgAFFH8MAAMdAAMJARhtMgCPAAAdAAIJihRtMgCPAAAcAAEJ7x76GwBbAAAuAAQKfzYAAxwACQnvGdANAF8BABwABgmXHdANAF8BAB0ABQlJFbCOAB0BAAAA.Chaotik:BAAALgADCgcJDAAAAA==.Chaplain:BAAALgAECgcJBwAAAA==.Chartkov:BAABLgAECn8bAAIVAAcJhhwNDQDgAQAVAAcJhhwNDQDgAQAAAA==.Cheechee:BAAALgAECgYJEAAAAA==.Cheekichik:BAAALgADCgQJBAAAAA==.Cheeseballer:BAAALgAFFAQJBAAAAA==.Cheesebur:BAAALgADCgcJBwAAAA==.Chighas:BAAALgADCgQJBwAAAA==.Chiji:BAAALgAECgEJAQABLgAFFAMJCQAiAAYVAA==.Choofi:BAABLgAECn8bAAISAAcJKBQoQQCNAQASAAcJKBQoQQCNAQAAAA==.Chubbytoyboy:BAAALgADCgUJBQABLgAFFAYJFgAJAMgTAA==.',
Ci='Ciená:BAAALgAECgQJBQAAAA==.Cin:BAABLgAECn8aAAIFAAkJGSIUDQAEAwAFAAkJGSIUDQAEAwAAAA==.Cinderpetal:BAAALgAECgQJBQAAAA==.',
Ck='Ckay:BAAALgAECgMJAwAAAA==.',
Co='Cohemew:BAAALgAECggJCwABLgAFFAUJCgAdAKwWAA==.Comlock:BAABLgAECn8hAAMdAAYJYweq5wCPAAAdAAYJ7AWq5wCPAAAcAAMJOQizOwA8AAAAAA==.Complacent:BAABLgAECn9TAAIXAAkJmARuCQCPAAAXAAkJmARuCQCPAAAAAA==.Comrage:BAAALgADCgQJBAAAAA==.Coolwhip:BAAALgAECgIJAgAAAA==.Coomtheory:BAAALgAECgYJCAAAAA==.Coriander:BAAALgAECgQJBQAAAA==.Corik:BAAALgADCgMJAwAAAA==.Corrumpere:BAAALgAECgMJAwAAAA==.',
Cr='Cragn:BAABLgAECn8nAAIEAAgJ3BanTgDcAQAEAAgJ3BanTgDcAQAAAA==.Crimsonlight:BAAALgAECggJEAAAAA==.Crownman:BAAALgAECgQJBAAAAA==.Crunchyblue:BAAALgADCgUJBgAAAA==.',
Cu='Cuckpov:BAAALgAFFAIJAgABLgAFFAMJCQAiAAYVAA==.Cuddilz:BAABLgAECn8eAAMjAAkJXBbNHACvAQAjAAkJARPNHACvAQAkAAYJ3RKOEAAcAQAAAA==.Cursedchild:BAAALgAFFAMJBAAAAA==.',
Cy='Cyclonic:BAAALgADCgYJBwAAAA==.Cyonicus:BAABLgAECn8vAAIdAAkJjR2KFACqAgAdAAkJjR2KFACqAgAAAA==.Cyradis:BAAALgADCgEJAQAAAA==.Cyska:BAACLgAFFH8JAAIHAAQJnQ+vCgDrAAAHAAQJnQ+vCgDrAAAuAAQKfz8AAgcACQlQHnYIAI0CAAcACQlQHnYIAI0CAAAA.',
['Cé']='Cécé:BAABLgAECn8wAAIEAAcJpCPVKwBSAgAEAAcJpCPVKwBSAgAAAA==.',
Da='Daciana:BAABLgAECn83AAICAAkJsh+cGgCFAgACAAkJsh+cGgCFAgAAAA==.Dagaroonie:BAAALgAECgkJEAAAAA==.Dagevas:BAABLgAECn8lAAIdAAkJ1RJJSwC4AQAdAAkJ1RJJSwC4AQAAAA==.Danyella:BAAALgAECgEJAQAAAA==.Darinius:BAAALgAECgEJBQAAAA==.Darkeznite:BAACLgAFFH8FAAICAAMJYgzGKgC9AAACAAMJYgzGKgC9AAAuAAQKfxoAAgIACQmGGZswABkCAAIACQmGGZswABkCAAAA.Darksoldier:BAABLgAFFH8FAAICAAQJBgxRTgAPAQACAAQJBgxRTgAPAQAAAA==.Dartoy:BAACLgAFFH8LAAIhAAMJoiJ3KQAPAQAhAAMJoiJ3KQAPAQAuAAQKfzoAAiEACQljDjsmAMYBACEACQljDjsmAMYBAAAA.Davriell:BAAALgAECgcJDQAAAA==.Dax:BAABLgAECn8fAAICAAkJlRmsPwDjAQACAAkJlRmsPwDjAQAAAA==.Daxing:BAAALgAECgUJBQABLgAFFAMJBgAYACQQAA==.Dazling:BAAALgAECggJEQAAAA==.Dazz:BAAALgAECgEJAQAAAA==.',
De='Deathkess:BAAALgAECgcJBwAAAA==.Deathlokk:BAABLgAECn8VAAIcAAYJSh8eDwDZAQAcAAYJSh8eDwDZAQAAAA==.Deeppurple:BAABLgAECn8iAAIlAAcJ4wmCCAAIAQAlAAcJ4wmCCAAIAQAAAA==.Deezmons:BAABLgAECn8rAAImAAkJTRA/HQCSAQAmAAkJTRA/HQCSAQAAAA==.Deholybagel:BAAALgAECgQJBQAAAA==.Del:BAABLgAECn83AAIeAAkJTSZRAABrAwAeAAkJTSZRAABrAwAAAA==.Demoncheese:BAAALgADCgYJCAAAAA==.Demondag:BAAALgADCgcJDAAAAA==.Demoniaca:BAABLgAECn8WAAImAAkJ1RG/HwB7AQAmAAkJ1RG/HwB7AQAAAA==.Demonkirby:BAAALgADCgUJBwAAAA==.Demonlarrik:BAAALgAECgEJAQAAAA==.Demostache:BAABLgAFFH8KAAIdAAUJrBYpFAAtAQAdAAUJrBYpFAAtAQAAAA==.Derale:BAABLgAECn8aAAMaAAgJiw0EJgCNAQAaAAgJiA0EJgCNAQAfAAcJXQQyIgAZAQAAAA==.Despot:BAAALgAECgQJCQAAAA==.Destik:BAAALgAECgIJBAAAAA==.Destoroyah:BAAALgADCgQJBAAAAA==.Dewover:BAAALgADCgMJAwAAAA==.',
Dh='Dhargal:BAACLgAFFH8JAAIJAAMJlx9YKAD0AAAJAAMJlx9YKAD0AAAuAAQKfzwAAgkACQm2JK8DAC8DAAkACQm2JK8DAC8DAAAA.',
Di='Dial:BAAALgADCgkJGQAAAA==.Dichotomy:BAAALgADCgQJBAAAAA==.Divinebi:BAAALgAECgUJBQAAAA==.Divus:BAABLgAECn8dAAISAAgJHA1/TABdAQASAAgJHA1/TABdAQAAAA==.',
Dk='Dkfaros:BAABLgAECn8fAAIFAAkJeB9gHQCXAgAFAAkJeB9gHQCXAgAAAA==.',
Do='Dominatrixia:BAAALgADCgkJCQAAAA==.Dommenica:BAAALgADCgYJBgAAAA==.Donko:BAAALgADCggJCAABLgAECgcJFwAYAE0NAA==.Dontcarebear:BAABLgAECn8fAAIXAAgJJwaaPACzAAAXAAgJJwaaPACzAAAAAA==.Doofnshmirtz:BAACLgAFFH8FAAIVAAMJFxG4DgDVAAAVAAMJFxG4DgDVAAAuAAQKfy8AAhUACQngHF4HAFgCABUACQngHF4HAFgCAAAA.Doorofdreamz:BAAALgAECgMJAwABLgAECgQJBQAOAAAAAA==.Dorkwiz:BAAALgAECgEJAQAAAA==.Dorow:BAAALgAFFAEJAQAAAA==.Dotpocket:BAABLgAECn8tAAIdAAkJfhncLAAmAgAdAAkJfhncLAAmAgAAAA==.',
Dr='Dragonash:BAAALgAECgcJDQAAAA==.Drakenn:BAAALgAECgcJDgAAAA==.Draéne:BAAALgAECgkJEgAAAA==.Dreadly:BAAALgADCgUJCAAAAA==.Dreadp:BAAALgADCgIJAgAAAA==.Dreamfyre:BAAALgAECgEJAQAAAA==.Dreams:BAACLgAFFH8QAAICAAMJehPpHwDwAAACAAMJehPpHwDwAAAuAAQKf0sAAwIACQn1H9IQAMoCAAIACQn1H9IQAMoCABsAAwnVBk10AG0AAAAA.Dremmy:BAAALgAECgYJEQAAAA==.Drey:BAAALgAECgUJBwAAAA==.Drinkme:BAAALgAECgQJBQAAAA==.Dripdasini:BAAALgADCgUJBQAAAA==.Droki:BAACLgAFFH8NAAIVAAMJ9R3WCgASAQAVAAMJ9R3WCgASAQAuAAQKfzEAAhUACQlwI4oCAPECABUACQlwI4oCAPECAAAA.Drokigos:BAAALgAECgIJAgABLgAFFAQJDQAVAPUdAA==.',
Du='Dunsel:BAAALgAECggJEgABLgAECgkJMQAfACAfAA==.Dunwich:BAAALgAECgMJAwAAAA==.Durostan:BAAALgAECgEJBAAAAA==.',
Dv='Dvali:BAABLgAECn8UAAIDAAcJWwh9lgD0AAADAAcJWwh9lgD0AAAAAA==.',
Dy='Dyorra:BAABLgAECn8iAAMNAAgJRwkvTQAGAQANAAcJXQYvTQAGAQAEAAYJ1ARnAwG0AAAAAA==.',
['Dä']='Dämon:BAAALgADCgIJAgAAAA==.',
Eb='Ebonshade:BAAALgAECggJDAAAAA==.',
Ed='Edgardapoe:BAAALgAECgMJAwABLgAFFAUJCgAdAKwWAA==.Edginglord:BAAALgAECgYJBwAAAA==.',
Eh='Ehmill:BAABLgAECn8pAAIFAAkJoxmSLgBFAgAFAAkJoxmSLgBFAgAAAA==.',
El='Elesrya:BAAALgAECgEJAQABLgAECgkJPAAEABMeAA==.Elgringo:BAAALgAECgcJAwAAAA==.Elosien:BAAALgAECgEJAQABLgAECgkJIgABAHUYAA==.Elventhing:BAAALgAECgYJCQAAAA==.',
Em='Emmå:BAAALgADCgEJAQAAAA==.Emshady:BAABLgAECn8VAAIEAAYJwQ03ygD6AAAEAAYJwQ03ygD6AAAAAA==.',
Eo='Eomær:BAAALgAECgEJAgAAAA==.',
Ep='Epsilòn:BAEALgAECgkJAQAAAA==.',
Er='Ernest:BAAALgAECgUJBQAAAA==.Errani:BAABLgAECn8xAAIRAAkJNBOOBADoAQARAAkJNBOOBADoAQAAAA==.',
Es='Eskers:BAABLgAECn8eAAIfAAkJ9RwtAwBtAgAfAAkJ9RwtAwBtAgAAAA==.Esterlia:BAAALgAECgYJBwABLgAFFAMJBgAYACQQAA==.Estralla:BAAALgADCgQJBAAAAA==.',
Eu='Eureki:BAABLgAECn8oAAIDAAkJwg38XABxAQADAAkJwg38XABxAQAAAA==.',
Ev='Evilkarma:BAABLgAECn8bAAIRAAcJKgKsAwGnAAARAAcJKgKsAwGnAAAAAA==.Evocane:BAABLgAECn8WAAIRAAYJDA6nvQANAQARAAYJDA6nvQANAQAAAA==.Evocati:BAAALgAECgUJBgABLgAFFAcJFAAEAP8XAA==.Evocatis:BAACLgAFFH8UAAMEAAcJ/xdIDwA4AQAEAAcJ/xdIDwA4AQANAAEJRAtaTAAxAAAuAAQKfyUAAwQACQkZITUeALYCAAQACAl5IzUeALYCAA0AAwkOCxF2AKIAAAAA.Evodruid:BAAALgAECgEJAQAAAA==.Evoorc:BAAALgAECggJDwAAAA==.',
Ex='Ex:BAABLgAECn8jAAIcAAgJqQyIEgAhAQAcAAgJqQyIEgAhAQAAAA==.',
Ey='Eyesdeadeyed:BAAALgAFFAEJAgAAAA==.',
Fa='Faasht:BAAALgAECgEJAQAAAA==.Faoris:BAAALgAECgYJEQAAAA==.Fayde:BAAALgADCgUJBAAAAA==.',
Fe='Feaster:BAAALgAECgMJAwABLgAFFAMJDAAFANocAA==.Feebs:BAAALgAECgMJBQAAAA==.Feebzykun:BAAALgADCgYJBgAAAA==.Felheart:BAAALgAECgQJBgABLgAFFAYJGgAEAIwZAA==.Felzbirt:BAAALgAECgUJCQAAAA==.Fenehdis:BAAALgAECgcJDQAAAA==.Ferg:BAAALgADCgcJBwAAAA==.Ferula:BAAALgAECgkJDAAAAA==.',
Fi='Fiftycaliber:BAAALgAECgQJBAAAAA==.Firebirdxx:BAAALgADCgcJBwABLgAFFAcJFQASAEQTAA==.Firebirdz:BAACLgAFFH8VAAISAAcJRBMUGQCVAQASAAcJRBMUGQCVAQAuAAQKfycAAxIACQnVIbAIAAMDABIACQnVIbAIAAMDABYACAnPFlsdAN4BAAAA.Firebirdzx:BAAALgADCgYJBwABLgAFFAcJFQASAEQTAA==.Firebirdzz:BAAALgAECgQJBwAAAA==.Fizzledust:BAAALgAECgEJAgAAAA==.Fizzystomps:BAAALgAECgQJBgAAAA==.',
Fl='Fleabàg:BAAALgAECggJBwAAAA==.',
Fo='Forginn:BAAALgAECgEJAQABLgAFFAkJNAALAOAXAA==.Forque:BAAALgADCgQJAwAAAA==.Fortybelow:BAAALgAECgQJCAAAAA==.',
Fr='Freidas:BAAALgADCgkJCQABLgAECgkJQAAYADUbAA==.Friargark:BAAALgAECgQJBQAAAA==.Frostatute:BAAALgAECgEJAQAAAA==.Frostypaw:BAAALgADCgYJCgAAAA==.Frostypaws:BAAALgADCgMJAwAAAA==.Frostzilla:BAABLgAECn8bAAIRAAYJDA5nEAD4AAARAAYJDA5nEAD4AAAAAA==.',
Fu='Fuzzybut:BAABLgAECn8tAAIXAAkJ3xvwCwAiAgAXAAkJ3xvwCwAiAgAAAA==.',
Fy='Fyuna:BAAALgAFFAIJBAAAAA==.',
Ga='Gandalph:BAAALgAECgQJBQAAAA==.Gark:BAABLgAECn8XAAICAAgJmApLpwD0AAACAAgJmApLpwD0AAAAAA==.Garkk:BAAALgADCgcJDwAAAA==.Garrumn:BAAALgAECgEJAQABLgAFFAUJCgAdAKwWAA==.Gazzi:BAAALgAECgkJEgAAAA==.',
Ge='Geargust:BAAALgAECgkJAgAAAA==.Genevieve:BAAALgAECgEJAQABLgAECgkJFgABACsaAA==.Georgebenson:BAAALgADCgQJBAAAAA==.',
Gi='Giuseppee:BAAALgAECgUJCQABLgAFFAIJBQAdAGIMAA==.Gióvanna:BAAALgAECgQJEAAAAA==.',
Gl='Glaivedigger:BAAALgADCgIJAwABLgAECgkJIwAnAHwfAA==.',
Go='Goblndeznutz:BAAALgAECgIJBAAAAA==.Goobow:BAACLgAFFH8eAAIFAAcJGxgNSwBcAQAFAAcJGxgNSwBcAQAuAAQKf14AAgUACQmLJYsCAHcDAAUACQmLJYsCAHcDAAAA.Goodheavens:BAAALgAECgQJBwAAAA==.Goonlock:BAAALgADCgYJCwAAAA==.Gorbb:BAAALgADCgQJBAAAAA==.Gotenk:BAAALgAECgQJCAAAAA==.Goudafel:BAAALgADCgcJDgAAAA==.Goyim:BAABLgAECn8lAAIRAAkJ9Q3NdwDiAQARAAkJ9Q3NdwDiAQAAAA==.',
Gr='Gr:BAABLgAECn8hAAISAAcJnRjTMADeAQASAAcJnRjTMADeAQAAAA==.Graveconvert:BAAALgADCgMJAwAAAA==.Gremory:BAAALgAECgIJAgABLgAECgQJBQAOAAAAAA==.Grewbacca:BAAALgADCgMJAwAAAA==.Grimkrieg:BAABLgAECn8kAAIXAAgJxBmSDwDuAQAXAAgJxBmSDwDuAQAAAA==.Grody:BAAALgAECgEJAgAAAA==.Grumpias:BAAALgAECgcJCQABLgAFFAQJBQAQAN8OAA==.',
Gu='Guroo:BAABLgAECn80AAICAAkJ7xJlRQDRAQACAAkJ7xJlRQDRAQAAAA==.',
['Gá']='Gárp:BAABLgAECn8VAAMPAAkJhh6VDQASAgAPAAUJVCWVDQASAgAhAAkJuhI+JADSAQABLgAECgkJFQAPAIYeAA==.',
['Gø']='Gødoth:BAACLgAFFH8JAAMJAAQJwhmDPQCaAAAJAAMJCRiDPQCaAAAYAAEJqhTAfQBCAAAuAAQKfyQAAwkACAlhIPUWAC4CAAkACAlhIPUWAC4CABgABQkQIvM7AJIBAAAA.',
Ha='Hagarn:BAACLgAFFH8hAAIEAAUJThIjHADoAAAEAAUJThIjHADoAAAuAAQKfzkAAgQACQkZF5Y7ABUCAAQACQkZF5Y7ABUCAAAA.Haithem:BAAALgAECgEJAgAAAA==.Halimah:BAABLgAECn8dAAICAAgJpww9DgAZAQACAAgJpww9DgAZAQAAAA==.Halloffame:BAAALgAECgIJAQAAAA==.Hamsham:BAAALgAECgEJAQAAAA==.Handjabz:BAAALgAECgEJAQAAAA==.Harbek:BAAALgAECggJEwAAAA==.Harleymoo:BAAALgAFFAIJBAAAAA==.Harleypaw:BAAALgADCgQJBAAAAA==.Harleypuddin:BAAALgAECgkJBwAAAA==.Harleysmol:BAAALgAECgkJAgAAAA==.Harlydorable:BAABLgAECn8dAAIoAAUJWCBVKABvAQAoAAUJWCBVKABvAQAAAA==.Harryphotter:BAAALgAFFAEJAwAAAA==.Hazan:BAABLgAECn8XAAIpAAYJDhxeGACXAQApAAYJDhxeGACXAQABLgAFFAQJDQAVAPUdAA==.Hazystar:BAAALgAECgcJDQAAAA==.',
He='Healmemaybe:BAABLgAECn8cAAIEAAYJ1hSSxQABAQAEAAYJ1hSSxQABAQAAAA==.Hemogoblin:BAAALgAECgIJAgABLgAECgkJFwARACkdAA==.Hemour:BAABLgAECn8hAAIFAAkJbQxIXgCtAQAFAAkJbQxIXgCtAQAAAA==.Hexmachine:BAAALgAFFAIJAgAAAA==.Hexyou:BAAALgAECgIJAgAAAA==.',
Hi='Hirak:BAAALgADCgIJAgABLgAFFAkJNAALAOAXAA==.',
Ho='Hogarth:BAAALgADCgEJAQAAAA==.Holdmyshock:BAAALgADCgEJAQAAAA==.Holmstein:BAABLgAECn8oAAIBAAkJvRSyGwDqAQABAAkJvRSyGwDqAQAAAA==.Hotnsoursoup:BAAALgADCgcJCgAAAA==.',
Hu='Hunkules:BAAALgAECgYJCAAAAA==.Huntzcatzup:BAAALgADCgYJBgAAAA==.',
Hy='Hypertext:BAAALgAECgEJAQAAAA==.',
['Hë']='Hëllsoldier:BAAALgADCgMJAwAAAA==.',
Ia='Iamahriman:BAACLgAFFH8JAAIJAAMJAgX1PgCUAAAJAAMJAgX1PgCUAAAuAAQKfzEAAgkACQmADXEwAH0BAAkACQmADXEwAH0BAAAA.Iamthanatos:BAABLgAECn8gAAIEAAcJpwluwQAGAQAEAAcJpwluwQAGAQAAAA==.',
Id='Idblastdat:BAABLgAECn80AAIRAAkJXhx4JACLAgARAAkJXhx4JACLAgAAAA==.',
Ig='Ignite:BAACLgAFFH8JAAMiAAMJBhXFAQCHAAARAAIJHhljOQCfAAAiAAIJnBLFAQCHAAAuAAQKfx0AAxEACQmgIIMoAHgCABEACQnPHoMoAHgCACIAAQkOHnMSAFoAAAAA.',
Il='Iliana:BAAALgAECgIJAQAAAA==.Illestria:BAABLgAECn8/AAIEAAkJsBlHMwAzAgAEAAkJsBlHMwAzAgAAAA==.Illumiscotty:BAACLgAFFH8FAAMiAAQJDxpNAQC8AAAiAAIJPx5NAQC8AAARAAIJ4BVMPACRAAAuAAQKfzgABBEACQn0Jf0EAF0DABEACQn0Jf0EAF0DACIABQm0HhgJAAQBACUAAQnbEIUUADAAAAAA.Ilwey:BAAALgAECgcJEAAAAA==.',
Im='Immortamonk:BAABLgAECn8XAAIoAAYJPB9JJgDSAQAoAAYJPB9JJgDSAQAAAA==.Immórtál:BAAALgADCgUJBQABLgAECgYJFwAoADwfAA==.Imodium:BAAALgADCgIJAgAAAA==.',
In='Incognonetoo:BAAALgAECgkJBwABLgAECgkJBwAOAAAAAA==.Insania:BAABLgAECn9AAAMYAAkJNRvQJAAyAgAYAAgJuxrQJAAyAgAVAAMJcATNMwBhAAAAAA==.Invisagal:BAAALgAECgQJBgAAAA==.',
Io='Ionni:BAAALgADCgUJCAAAAA==.Iosefka:BAAALgAECgEJAQAAAA==.',
Ir='Ironhands:BAABLgAECn8fAAMEAAkJyxANBwCHAQAEAAkJzQ0NBwCHAQAMAAQJDxSoBQCyAAAAAA==.',
Iz='Izara:BAAALgAECgQJBwAAAA==.',
Ja='Jalcal:BAAALgAECgMJAwAAAA==.Jarlmaxim:BAAALgAECgYJDAABLgAECggJDQAOAAAAAA==.Jasindra:BAAALgAECgcJDwABLgAFFAMJBgAYACQQAA==.Jaspally:BAABLgAECn8VAAMNAAcJRxRYKQDCAQANAAcJRxRYKQDCAQAEAAUJ7AiEHACUAAABLgAFFAMJBgAYACQQAA==.',
Je='Jeannette:BAAALgAECgMJAwAAAA==.',
Ji='Jin:BAAALgADCgEJAQAAAA==.Jinerdys:BAAALgAECgEJAQAAAA==.',
Jo='Johnnycash:BAAALgAECgEJAQAAAA==.Jolinascrubs:BAABLgAECn9CAAIMAAkJ2xCSEwCSAQAMAAkJ2xCSEwCSAQABLgAFFAYJJAACACgOAA==.Jonjee:BAABLgAECn8YAAIEAAkJIR1QMQBdAgAEAAkJIR1QMQBdAgAAAA==.',
Ju='Juicez:BAAALgADCgQJBAAAAA==.Jurkee:BAABLgAECn80AAIEAAkJcSDaFQC/AgAEAAkJcSDaFQC/AgAAAA==.',
Ka='Kahekili:BAAALgAECgMJBQAAAA==.Kain:BAABLgAECn8fAAIRAAkJzRo1WgDPAQARAAkJzRo1WgDPAQAAAA==.Kalagren:BAABLgAECn8XAAICAAUJHQcu1QChAAACAAUJHQcu1QChAAAAAA==.Kaleielin:BAAALgAECgIJAgAAAA==.Karestoc:BAAALgAECgEJAQABLgAECgkJIgABAHUYAA==.Kathring:BAAALgADCgQJBAAAAA==.Katio:BAACLgAFFH8fAAIjAAUJCiGnBwBWAQAjAAUJCiGnBwBWAQAuAAQKfz8AAyMACQm2JNgGAMACACMACAlwJNgGAMACACQAAgkaFB4dAHIAAAAA.Kavaria:BAAALgAECgIJAgAAAA==.Kayanna:BAAALgAECgEJAQAAAA==.Kaydra:BAAALgADCgUJCAAAAA==.Kayhless:BAABLgAECn8gAAIhAAgJ4wmAQQA/AQAhAAgJ4wmAQQA/AQAAAA==.',
Ke='Keerah:BAABLgAECn8aAAMDAAkJuAPtngDlAAADAAkJuAPtngDlAAAeAAUJmQH6KgBXAAAAAA==.Kelirra:BAAALgADCgEJAgAAAA==.Kendoraa:BAAALgAECgIJAwAAAA==.Kessala:BAAALgAECgQJBgAAAA==.Kessandra:BAACLgAFFH8fAAIdAAgJ/hwyCwBmAgAdAAgJ/hwyCwBmAgAuAAQKfywAAh0ACQlbJVAEAHYDAB0ACQlbJVAEAHYDAAAA.Kexkan:BAABLgAECn8sAAIhAAkJaR1HDAClAgAhAAkJaR1HDAClAgAAAA==.Kezzia:BAAALgADCgMJAwAAAA==.',
Kh='Kharilan:BAAALgAECgYJDAAAAA==.Khitai:BAAALgADCgcJDgAAAA==.Khurri:BAABLgAECn8VAAIQAAkJtx47BgCaAgAQAAkJtx47BgCaAgAAAA==.',
Ki='Kiarah:BAABLgAECn8bAAINAAYJ0wr+TgD+AAANAAYJ0wr+TgD+AAAAAA==.Killerbuster:BAAALgAECgMJAwABLgAECgQJBQAOAAAAAA==.Killplz:BAAALgAECgUJBQAAAA==.Kirr:BAAALgAECgcJEAAAAA==.Kirwyn:BAAALgADCgcJBwAAAA==.Kisor:BAAALgAECgcJCQAAAA==.Kitchenstink:BAABLgAECn8YAAIpAAkJ4B4VBAC0AgApAAkJ4B4VBAC0AgAAAA==.',
Kl='Klys:BAABLgAECn8wAAIDAAkJ/xRvOwDZAQADAAkJ/xRvOwDZAQAAAA==.',
Ko='Kordh:BAABLgAECn86AAQVAAcJbg9CEQCjAQAVAAcJew5CEQCjAQAYAAcJUg5TYwAxAQAJAAcJyg7BSwAGAQAAAA==.Kordiza:BAABLgAECn8YAAQmAAYJ9we0PgC7AAAmAAYJ9we0PgC7AAAeAAUJmQOYJQBzAAADAAQJAQIHFAE1AAABLgAECgcJOgAVAG4PAA==.',
Kr='Kritanta:BAACLgAFFH8GAAIHAAMJrA2/KgCjAAAHAAMJrA2/KgCjAAAuAAQKfykAAgcACQnlDPEjADQBAAcACQnlDPEjADQBAAAA.Krrsantan:BAAALgADCgYJDQAAAA==.Krystallus:BAABLgAECn8hAAIWAAcJyRHlNwA1AQAWAAcJyRHlNwA1AQAAAA==.',
Ku='Kurnea:BAABLgAECn8aAAINAAkJsR2GGQA7AgANAAkJsR2GGQA7AgAAAA==.',
Ky='Kyandur:BAAALgADCgQJBAAAAA==.Kyipp:BAAALgADCgcJCAAAAA==.',
['Kó']='Kórrá:BAAALgADCgEJAQAAAA==.',
La='Lachlann:BAAALgAECgIJAgAAAA==.Laidy:BAAALgADCgYJBgAAAA==.Lakartó:BAACLgAFFH8VAAMaAAUJ9hhjLgAJAQAaAAQJnRVjLgAJAQAZAAEJ4wgSKgBJAAAuAAQKfyQABBoACQlPHYkVAC4CABoACQkTHIkVAC4CAB8ABglRE2wXAH8BABkAAQkcFC86ADoAAAAA.Larzuk:BAAALgADCgcJBwAAAA==.Lathril:BAAALgADCgYJBgAAAA==.',
Ld='Ldritch:BAACLgAFFH8aAAQKAAUJMCMdAwB6AQAKAAUJMCMdAwB6AQAkAAIJ+RWlAwC9AAAjAAEJACB7OgBWAAAuAAQKfywABAoACAkAJg8CALYCACMABwmqI2MLAN8CACQABwlWJUkCANcCAAoACAnJJQ8CALYCAAEuAAUUCAkeAAcANCEA.',
Le='Leanfro:BAAALgADCgEJAQAAAA==.Leifson:BAABLgAECn8WAAIHAAcJ2hXcIABMAQAHAAcJ2hXcIABMAQAAAA==.Leonedis:BAABLgAECn9BAAIhAAkJvhT8AwBmAQAhAAkJvhT8AwBmAQAAAA==.Leothor:BAAALgAECgQJBAAAAA==.Lernen:BAABLgAECn8bAAQRAAcJzAwWtQAaAQARAAcJzAwWtQAaAQAlAAIJZgTmEgA+AAAiAAEJdQH5IgARAAAAAA==.Lesein:BAAALgAECgQJCQAAAA==.Lethea:BAAALgAECgQJCAAAAA==.Levious:BAAALgAFFAEJAQAAAA==.Lexo:BAAALgADCgkJCgABLgAECgcJFwAYAE0NAA==.',
Li='Liain:BAAALgADCgQJBAABLgAECgIJAgAOAAAAAA==.Lianara:BAAALgAECgcJDQABLgAECggJGwAYAFkLAA==.Lirazel:BAAALgAECgMJAwAAAA==.Litenkuk:BAACLgAFFH8GAAIbAAMJzw6IFgDnAAAbAAMJzw6IFgDnAAAuAAQKfyEAAxsACAnYHyERALICABsACAnYHyERALICACAAAgkPD7RPAHEAAAAA.Lithiel:BAAALgADCgYJCgAAAA==.Liuna:BAAALgADCgEJAQABLgAFFAMJCQAJAJcfAA==.',
Lo='Lockabolt:BAAALgADCgEJAQABLgAECgkJFwATALEZAA==.Lohin:BAABLgAFFH8FAAIYAAMJmxtwQADjAAAYAAMJmxtwQADjAAABLgAFFAYJCgAZAMoLAA==.Lonelycougar:BAAALgADCgcJDwAAAA==.Lothstein:BAABLgAECn8aAAIYAAgJbxAHPgC2AQAYAAgJbxAHPgC2AQAAAA==.Lovely:BAAALgAFFAMJAwAAAA==.',
Lu='Luan:BAAALgAECgcJDwAAAA==.Ludo:BAAALgAECgEJAQAAAA==.Lukri:BAAALgAECggJEwAAAA==.Luminate:BAABLgAECn82AAIYAAkJqyFFCQAeAwAYAAkJqyFFCQAeAwAAAA==.Lunalah:BAAALgADCgcJBwAAAA==.Lunarray:BAAALgAECgEJAwAAAA==.Luxurious:BAABLgAECn9OAAIeAAkJ3wcYEwAgAQAeAAkJ3wcYEwAgAQAAAA==.',
Ly='Lyndea:BAAALgADCgYJBgAAAA==.',
['Lí']='Líllsnorre:BAAALgAECgMJBAAAAA==.',
Ma='Maaca:BAABLgAFFH8GAAIXAAMJkQpiFQBdAAAXAAMJkQpiFQBdAAAAAA==.Madkow:BAAALgAECgQJBAAAAA==.Magichronic:BAAALgAECgEJAQAAAA==.Magicmoose:BAAALgADCgEJAQAAAA==.Magicwillow:BAAALgAECgUJBgAAAA==.Magnomonk:BAAALgAECgYJDQAAAA==.Majesticelf:BAAALgADCgcJCQAAAA==.Majuhstee:BAAALgADCgcJCAABLgAFFAEJAQAOAAAAAA==.Malachor:BAABLgAECn8lAAMHAAkJOxa5FwCoAQAHAAkJOxa5FwCoAQAGAAEJfgVxQAAmAAAAAA==.Maligned:BAABLgAECn8uAAIHAAkJpB2YCgBnAgAHAAkJpB2YCgBnAgAAAA==.Malphias:BAAALgAECgYJCgAAAA==.Manon:BAAALgAECgYJBwAAAA==.Marsilea:BAAALgADCgcJCgABLgAECgIJAgAOAAAAAA==.Martichoux:BAABLgAECn8XAAIRAAkJKR2xPwB6AgARAAkJKR2xPwB6AgAAAA==.Marvyy:BAAALgAECgcJEAAAAA==.Mash:BAAALgAECgIJAgABLgAFFAQJBAAOAAAAAA==.Mastakronik:BAAALgAECgEJAQAAAA==.Mathas:BAACLgAFFH8HAAINAAQJgRWBCQAVAQANAAQJgRWBCQAVAQAuAAQKfykAAg0ACQnZISkRAIkCAA0ACQnZISkRAIkCAAAA.Mathilda:BAABLgAECn8YAAIEAAcJpAGWSAFkAAAEAAcJpAGWSAFkAAAAAA==.Maxpower:BAAALgAECgMJAwAAAA==.Mazes:BAACLgAFFH8IAAIjAAMJmCGuIQAYAQAjAAMJmCGuIQAYAQAuAAQKf0QAAyMACQnUIWUDABQDACMACQnUIWUDABQDACQAAQmoBOIhACgAAAAA.',
Mc='Mccholock:BAABLgAECn8tAAMhAAkJXBqyHQABAgAhAAkJXBqyHQABAgApAAIJfBR+VgB+AAAAAA==.Mcllovin:BAAALgAECgEJAQAAAA==.Mcmach:BAAALgAECgYJEwAAAA==.',
Me='Meddox:BAAALgADCgYJBgAAAA==.Mediocrepaly:BAAALgAECgcJEgAAAA==.Mehaoloka:BAAALgADCgkJDAAAAA==.Mekanthis:BAACLgAFFH8eAAMHAAgJNCGNBABYAgAHAAgJNCGNBABYAgAFAAEJcRsPZQBVAAAuAAQKfygAAgcACQmEJTsCAFEDAAcACQmEJTsCAFEDAAAA.Memelle:BAAALgAECgEJAwAAAA==.Menith:BAAALgAECgQJBwAAAA==.Menoah:BAABLgAECn8hAAIXAAkJshFWFgCgAQAXAAkJshFWFgCgAQAAAA==.Menopaws:BAAALgADCggJCAAAAA==.Menotthatorc:BAAALgAECgUJCAABLgAFFAUJCgAdAKwWAA==.Merdoc:BAAALgAECgYJDAAAAA==.Meredith:BAABLgAECn8WAAIBAAkJKxqHEABjAgABAAkJKxqHEABjAgAAAA==.Mesilana:BAAALgAECgYJBwAAAA==.Metalhoof:BAAALgAECgQJBwAAAA==.',
Mi='Michelangelo:BAAALgAECgEJAQAAAA==.Mikak:BAAALgAECgIJAQAAAA==.Milanova:BAAALgADCgYJDQABLgAECggJEwAOAAAAAA==.Mirenna:BAABLgAECn8iAAIBAAkJdRgiDwB2AgABAAkJdRgiDwB2AgAAAA==.Mirra:BAAALgAECgIJAgAAAA==.Misseymiss:BAAALgAECgUJCAAAAA==.Missnewbooty:BAAALgAECgIJAQABLgAECgkJLwAHAH4QAA==.',
Mo='Mogwhy:BAABLgAECn8tAAIkAAkJIxbvBAA3AgAkAAkJIxbvBAA3AgAAAA==.Molbeato:BAAALgAFFAEJAQAAAA==.Monichan:BAAALgAECgYJCgAAAA==.Monkeypocket:BAAALgADCgQJBAAAAA==.Monkfu:BAAALgAECgIJAgAAAA==.Moonstrikex:BAAALgADCgUJBQAAAA==.Mooseknuckle:BAABLgAECn8YAAIoAAkJDRflHQC2AQAoAAkJDRflHQC2AQAAAA==.Moralekillas:BAABLgAFFH8QAAMkAAUJJxQgBQAwAQAkAAQJwhIgBQAwAQAjAAMJsBFuMwCUAAAAAA==.Morecowbell:BAAALgAECgIJAgAAAA==.Morganna:BAAALgAECgEJAgAAAA==.Morior:BAABLgAECn8hAAIcAAkJhw1+DAB4AQAcAAkJhw1+DAB4AQAAAA==.Motorcade:BAABLgAECn9MAAIoAAkJSgPNBQChAAAoAAkJSgPNBQChAAAAAA==.Mouthhugs:BAAALgAECgEJAQAAAA==.',
Mu='Muchoblades:BAABLgAECn8UAAImAAgJpA1zJwA/AQAmAAgJpA1zJwA/AQAAAA==.Murazor:BAAALgADCgUJBAAAAA==.Murples:BAABLgAECn8UAAISAAkJbhtmHABjAgASAAkJbhtmHABjAgABLgAFFAIJBwAUAIYgAA==.',
My='Mypal:BAAALgAECgcJDQAAAA==.Myronastus:BAAALgADCgEJAQAAAA==.',
Na='Naimaa:BAAALgAECgEJAgAAAA==.Najira:BAAALgAECgUJBQAAAA==.Narinn:BAAALgADCggJCAAAAA==.',
Ne='Neather:BAABLgAECn8pAAIRAAkJGRd8OAA3AgARAAkJGRd8OAA3AgAAAA==.Neels:BAAALgADCgMJAwAAAA==.Neodke:BAAALgAECgEJAQAAAA==.Neodken:BAAALgADCgYJCgAAAA==.Neron:BAAALgAECgEJAQAAAA==.Nestlee:BAAALgADCgcJBwAAAA==.Nevvermore:BAAALgAECgUJDAAAAA==.Nexeon:BAAALgAECgYJCAABLgAECgkJHgATAIMUAA==.Nezkima:BAAALgAECgcJBwAAAA==.',
Nf='Nfg:BAAALgADCgYJEAAAAA==.',
Ni='Niare:BAAALgAECgQJBAAAAA==.Ninfami:BAAALgADCggJCAAAAA==.Ninfamy:BAAALgADCgQJBQAAAA==.Ninfinite:BAACLgAFFH8JAAIDAAMJqhhdXgDUAAADAAMJqhhdXgDUAAAuAAQKfycAAgMACAmGH8YiAEUCAAMACAmGH8YiAEUCAAAA.Nira:BAABLgAECn8dAAILAAkJRhxuCADuAgALAAkJRhxuCADuAgAAAA==.',
No='Noastea:BAAALgAECgEJAQAAAA==.Nockturne:BAAALgADCgMJAwAAAA==.Nonetoo:BAAALgAECgkJBwAAAA==.Norasmina:BAAALgAECgEJAQAAAA==.Norr:BAABLgAECn8wAAMEAAkJISE8GACyAgAEAAkJISE8GACyAgAMAAMJIRO3LQCzAAAAAA==.Northpaul:BAAALgADCgQJBAAAAA==.Notdeadyet:BAABLgAECn8qAAICAAkJXxaUQgDaAQACAAkJXxaUQgDaAQAAAA==.Notneels:BAAALgAECgQJBQAAAA==.',
Ny='Nyceria:BAAALgAECgUJCQAAAA==.Nychophysis:BAAALgAECgEJAQAAAA==.Nyseria:BAAALgADCgEJAQABLgAECgUJCQAOAAAAAA==.Nyxion:BAAALgAECgEJAQABLgAECggJDAAOAAAAAA==.',
['Nø']='Nøcke:BAAALgADCgkJCQAAAA==.',
Oa='Oakarm:BAAALgAECgkJAgAAAA==.Oasis:BAAALgAECgEJAwAAAA==.',
Ob='Obpwnkenobi:BAAALgAECgQJEgAAAA==.',
Od='Odielleb:BAAALgAECgUJBQAAAA==.Odyssius:BAABLgAECn8VAAIdAAcJJQ2JiwAjAQAdAAcJJQ2JiwAjAQAAAA==.',
Og='Ogden:BAAALgAECgIJAgABLgAECgkJKwAYANsGAA==.',
Ol='Oldandblind:BAAALgAECgYJCwAAAA==.',
On='Ontherun:BAAALgADCgQJBQAAAA==.',
Op='Oprawinfury:BAABLgAECn8bAAIYAAgJWQtqEgCIAAAYAAgJWQtqEgCIAAAAAA==.',
Or='Oralia:BAAALgAECgYJBgAAAA==.Ordun:BAAALgAECgMJAwAAAA==.Orphani:BAAALgADCgIJAgAAAA==.',
Os='Oscarguydude:BAABLgAECn8eAAMCAAkJ0hpUYABHAQACAAcJ4RlUYABHAQAbAAUJNRjISgAnAQAAAA==.',
Ou='Ourus:BAABLgAECn88AAMPAAkJkSQ/AgAnAwAPAAkJkSQ/AgAnAwAhAAgJJg91MwDdAQAAAA==.',
Ov='Oversoul:BAAALgAECgEJAwAAAA==.',
Ow='Owlpha:BAAALgAECgYJCwAAAA==.',
Ox='Oxlob:BAABLgAECn8VAAIEAAgJUxF5cQCZAQAEAAgJUxF5cQCZAQAAAA==.',
Pa='Pallaminnow:BAAALgAECgIJAgAAAA==.Pallychef:BAAALgAECgEJAQABLgAECgkJMwAEAAEXAA==.Panax:BAAALgADCgcJBwAAAA==.Pansolo:BAAALgADCgUJBQAAAA==.Parabellum:BAAALgADCgYJBgAAAA==.Parkér:BAAALgAECgMJBQAAAA==.Pawtyr:BAAALgAECgEJAQABLgAECgkJJgAOAAAAAQ==.',
Pe='Peachieriest:BAAALgAECgMJAQAAAA==.Pele:BAABLgAECn8hAAISAAgJ3xPeOQCuAQASAAgJ3xPeOQCuAQAAAA==.Pellito:BAAALgADCgkJDAAAAA==.Perpetrator:BAABLgAECn9OAAIHAAkJOQh8BQDQAAAHAAkJOQh8BQDQAAAAAA==.',
Ph='Pheonix:BAAALgADCgYJBgAAAA==.Phyre:BAAALgADCggJDQAAAA==.',
Pi='Pikahboo:BAAALgADCgYJBgAAAA==.Piki:BAAALgAECgQJCwAAAA==.',
Po='Poepwn:BAABLgAECn85AAIUAAgJKBcQKwDVAQAUAAgJKBcQKwDVAQAAAA==.',
Pr='Prescient:BAAALgAECgkJCQAAAA==.Priestbot:BAAALgADCgcJCwAAAA==.Prokerz:BAAALgADCgkJCQAAAA==.Promo:BAAALgADCgIJAgAAAA==.Prydae:BAAALgAECgIJAgAAAA==.',
Pu='Puffypanda:BAAALgAECggJCgAAAA==.Putnamehere:BAAALgAECgEJAQAAAA==.',
Py='Pynelope:BAAALgADCgMJAwAAAA==.',
['Pá']='Párker:BAAALgAECgMJAwAAAA==.',
['Pû']='Pûrplehaze:BAAALgAFFAIJAgAAAA==.',
Qu='Quelude:BAABLgAECn8UAAIaAAkJJQrCOABKAQAaAAkJJQrCOABKAQAAAA==.Quill:BAABLgAECn8VAAMSAAkJxRXwKQAKAgASAAkJxRXwKQAKAgAXAAMJwRMSIgCNAAAAAA==.',
Ra='Raeris:BAEALgAECgcJAQABLgAECgkJAQAOAAAAAA==.Raicleach:BAAALgAECgkJCAAAAA==.Rainbow:BAAALgADCgcJDAAAAA==.Raktan:BAAALgAECgIJAgAAAA==.Ralz:BAAALgAECgEJAQAAAA==.Rancidgreen:BAAALgAECgMJBAAAAA==.Rannick:BAABLgAECn8fAAIVAAgJrxNMDwC8AQAVAAgJrxNMDwC8AQAAAA==.Ranua:BAACLgAFFH8GAAIYAAMJJBAYWgCZAAAYAAMJJBAYWgCZAAAuAAQKf0UABBgACQkYJAUEAHsDABgACQkYJAUEAHsDAAkABwlOD1BGABoBABUAAQmJCbs/ADEAAAAA.Ratio:BAABLgAECn8jAAIDAAkJXCDcDwDEAgADAAkJXCDcDwDEAgAAAA==.Ravenhunt:BAAALgAECgcJEQAAAA==.Ravenreaper:BAAALgADCgMJBAAAAA==.Rawmanu:BAAALgADCgkJEAAAAA==.Razlee:BAAALgAECgEJAQAAAA==.',
Re='Reania:BAAALgADCgUJCAAAAA==.Rectified:BAAALgAFFAMJBAAAAA==.Redbreastman:BAABLgAECn8dAAQZAAgJ3Bc+DgDqAQAZAAcJshc+DgDqAQAfAAUJWwzpGACQAAAaAAQJEAdJVQBvAAAAAA==.Redwings:BAAALgADCgEJAQAAAA==.Reiner:BAAALgAECggJDwAAAA==.Rekka:BAAALgAFFAIJBAAAAA==.Reoshe:BAAALgAECgcJCQAAAA==.',
Ri='Ripdvanwinkl:BAABLgAECn8rAAMDAAkJ/xEcVgCEAQADAAkJ+hEcVgCEAQAeAAQJyQ30IwB/AAAAAA==.Riven:BAAALgADCgcJBwAAAA==.',
Ro='Roachpocket:BAAALgAECgYJCQAAAA==.Ronyn:BAABLgAECn8fAAMYAAkJhhqaHwBTAgAYAAgJVxqaHwBTAgAJAAIJ4xIXgQBuAAAAAA==.Rozefire:BAAALgAECgUJBQABLgAECgkJFgABACsaAA==.',
Ru='Rude:BAAALgADCgEJAQAAAA==.Rudolf:BAAALgAECgQJBQAAAA==.Ruxlness:BAAALgADCgMJAwAAAA==.',
Rw='Rwarar:BAAALgADCgUJCAAAAA==.Rwqr:BAAALgADCgYJBwAAAA==.',
['Rä']='Räiden:BAABLgAECn8XAAIRAAYJuhKJrQAlAQARAAYJuhKJrQAlAQAAAA==.',
['Rö']='Rötthgard:BAAALgADCgkJCgAAAA==.',
Sa='Salacake:BAAALgAECgEJAwAAAA==.Salacakei:BAABLgAECn8vAAMjAAkJgxszDgBFAgAjAAkJgxszDgBFAgAkAAQJBwv7EwC/AAAAAA==.Salin:BAAALgAECgcJEwAAAA==.Salithril:BAAALgADCgYJCgAAAA==.Samlocke:BAAALgADCgYJBgABLgADCggJCwAOAAAAAA==.Santarock:BAAALgADCgEJAQAAAA==.Sanzo:BAAALgADCgMJAwABLgAECgcJEAAOAAAAAA==.Saradda:BAAALgAECgEJAwAAAA==.Sarthiy:BAABLgAECn8fAAMMAAkJdh1pBwBpAgAMAAcJKiNpBwBpAgAEAAYJqRTvjwBSAQABLgAFFAgJHQAMAIQZAA==.Sarthy:BAACLgAFFH8dAAIMAAgJhBkNAQAbAgAMAAgJhBkNAQAbAgAuAAQKfzUAAwwACQk5JGcAAJcDAAwACQk5JGcAAJcDAAQAAQlmDrSFATkAAAAA.Sassaphras:BAABLgAECn8dAAIBAAcJmB/kEQBSAgABAAcJmB/kEQBSAgAAAA==.Satheron:BAAALgAECgYJDwAAAA==.Satyric:BAAALgAECggJEgAAAA==.Saxifon:BAAALgADCgQJBAAAAA==.',
Sc='Scarletpaw:BAAALgAECggJEAAAAA==.Schnuggie:BAAALgAECgMJAwAAAA==.Scoobie:BAAALgAECgMJBQABLgAECggJKwACALofAA==.Scoobydo:BAAALgAECgQJBwABLgAECggJKwACALofAA==.Scratches:BAAALgAECgEJAgAAAA==.Screwwithme:BAAALgADCgYJBgAAAA==.Scrubs:BAACLgAFFH8kAAICAAYJKA6GJgBsAQACAAYJKA6GJgBsAQAuAAQKf0EAAgIACQngH00YAJUCAAIACQngH00YAJUCAAAA.',
Se='Seriadrina:BAAALgADCgIJAgAAAA==.Sevrum:BAAALgADCgYJDAAAAA==.',
Sh='Shaadow:BAAALgAECgEJAQAAAA==.Shadynastie:BAAALgAECgEJAQAAAA==.Shallabal:BAAALgAECgkJAgAAAA==.Shamyaltak:BAAALgAECgkJDgAAAA==.Shandralore:BAABLgAECn8iAAIbAAkJ0hn6BQA7AgAbAAkJ0hn6BQA7AgAAAA==.Shanleigh:BAAALgAECgEJAgAAAA==.Shauranna:BAAALgAECgMJAwAAAA==.Shiel:BAABLgAECn8tAAIQAAkJxhmkCgAVAgAQAAkJxhmkCgAVAgAAAA==.Shockdoctor:BAABLgAECn8mAAMYAAkJQyLSEgC2AgAYAAgJsiHSEgC2AgAJAAIJdRK/fQB3AAAAAA==.Shockzillah:BAAALgADCgkJCQAAAA==.Shogunasasin:BAABLgAECn8bAAMUAAgJBQ23KQBnAQAUAAgJBQ23KQBnAQATAAMJuxqVTQDbAAAAAA==.Shortrange:BAABLgAECn8YAAIbAAcJwyG5BwAHAgAbAAcJwyG5BwAHAgAAAA==.Shuzui:BAAALgADCgQJBAAAAA==.',
Si='Sicarion:BAABLgAECn8qAAIPAAcJ1wpUMAC+AAAPAAcJ1wpUMAC+AAAAAA==.Silentwalkr:BAAALgAECgIJAgAAAA==.Sivus:BAAALgADCgMJAwAAAA==.',
Sl='Sleples:BAABLgAECn8rAAMCAAgJuh/VIABjAgACAAgJuh/VIABjAgAgAAYJVRVsLQA6AQAAAA==.Sleyalias:BAABLgAFFH8FAAImAAMJ9QP9HwCfAAAmAAMJ9QP9HwCfAAAAAA==.Slufgor:BAAALgAECggJEwAAAA==.',
Sm='Smolder:BAAALgADCgkJFAAAAA==.',
Sn='Snoo:BAABLgAECn8jAAQnAAgJfB+YCgC2AQAdAAcJlRqBRwDDAQAnAAcJkx6YCgC2AQAcAAEJnxLEawA8AAAAAA==.Snoogon:BAAALgAECgUJBgABLgAECgkJIwAnAHwfAA==.Snorrehunter:BAAALgAECgQJBgAAAA==.Snowcaine:BAAALgAECgEJAwAAAA==.',
So='Solarlite:BAABLgAECn8XAAISAAYJLRNHTgBWAQASAAYJLRNHTgBWAQAAAA==.Solek:BAAALgADCgIJAgAAAA==.Solorion:BAAALgAECgYJCQAAAA==.Sorovar:BAABLgAECn8VAAILAAkJXSAFCAC/AgALAAkJXSAFCAC/AgAAAA==.',
Sp='Spamm:BAAALgAECgYJCQAAAA==.Spony:BAABLgAECn8zAAIkAAkJlhYsBwDsAQAkAAkJlhYsBwDsAQAAAA==.',
St='Starbrow:BAAALgAECgQJCwABLgAECgkJHwAFAHgfAA==.Stein:BAAALgADCgYJBgAAAA==.Steinn:BAAALgADCgEJAQAAAA==.Stevewinwood:BAAALgAECgYJEQAAAA==.Stormlight:BAABLgAECn8WAAISAAkJTQu6RwBwAQASAAkJTQu6RwBwAQAAAA==.Stárrk:BAAALgAECgEJAQAAAA==.',
Su='Sulevin:BAAALgAECgQJBAABLgAECgcJDQAOAAAAAA==.Summernight:BAAALgAECgEJAgAAAA==.Sushistryke:BAABLgAECn8iAAICAAkJAxWhVQCjAQACAAkJAxWhVQCjAQAAAA==.',
Sv='Svend:BAAALgADCgEJAQAAAA==.',
Sy='Syland:BAABLgAECn8qAAICAAkJ2RicNwAAAgACAAkJ2RicNwAAAgAAAA==.Sylanis:BAAALgAECgEJAQAAAA==.Sylissa:BAAALgADCgUJCAAAAA==.Sylvanäs:BAABLgAECn8bAAICAAcJehdNWgCWAQACAAcJehdNWgCWAQAAAA==.Sylvenna:BAABLgAECn8UAAMEAAcJDwtHugAQAQAEAAcJDwtHugAQAQANAAQJQQcydgCiAAAAAA==.Sypress:BAAALgADCgcJDgAAAA==.Syrelastus:BAAALgAECgEJAQAAAA==.Sysna:BAABLgAECn85AAIIAAkJ0CROAgBIAwAIAAkJ0CROAgBIAwAAAA==.',
Ta='Tachyon:BAAALgAECgEJAQAAAA==.Taiga:BAAALgAECgEJAQABLgAFFAUJCgAdAKwWAA==.Talley:BAACLgAFFH8GAAIYAAMJFAgNXwCNAAAYAAMJFAgNXwCNAAAuAAQKfygAAhgACQn4FIQ2ANYBABgACQn4FIQ2ANYBAAAA.Targis:BAAALgAECgYJEwAAAA==.Tauran:BAABLgAECn8XAAMYAAcJTQ2KVgBcAQAYAAcJTQ2KVgBcAQAJAAcJTw6XWADaAAAAAA==.Tazanaz:BAAALgAECgQJCAABLgAFFAMJBgAYACQQAA==.',
Te='Templeton:BAAALgAECgYJDQABLgAECgkJKwAYANsGAA==.Tendai:BAAALgADCgkJGAAAAA==.Tenloth:BAABLgAECn8kAAIRAAgJYRA0uwARAQARAAgJYRA0uwARAQAAAA==.Teozr:BAAALgADCgMJAwAAAA==.Teufelshund:BAAALgADCgcJBwAAAA==.',
Th='Thaeldrin:BAAALgADCgEJAQAAAA==.Thaleas:BAABLgAECn8iAAIMAAgJlRYSFgB0AQAMAAgJlRYSFgB0AQAAAA==.Theemedic:BAAALgADCgYJBQAAAA==.Thegreatkhal:BAAALgADCggJCAABLgAECgkJGQARABYYAA==.Thomasza:BAAALgAECgEJAQAAAA==.Thomii:BAAALgAECgEJAQAAAA==.Thorizine:BAAALgADCgMJAwAAAA==.Thorlas:BAABLgAECn88AAMYAAkJxSEdDAD5AgAYAAkJxSEdDAD5AgAJAAYJuRunPQA+AQAAAA==.Thorsham:BAAALgAECgYJBgAAAA==.',
Ti='Timadin:BAAALgADCgEJAQAAAA==.Timmúk:BAAALgAECgQJBAAAAA==.',
To='Tolkorthuul:BAAALgAECgIJAQABLgAECggJEwAOAAAAAA==.Tomma:BAABLgAECn8WAAIHAAkJ9CCABgDOAgAHAAkJ9CCABgDOAgAAAA==.Totem:BAAALgADCggJCAAAAA==.Totembi:BAACLgAFFH8lAAIYAAQJaCCcIgBlAQAYAAQJaCCcIgBlAQAuAAQKf0sAAhgACQmqHwkPANsCABgACQmqHwkPANsCAAAA.Totemzfury:BAAALgAECgEJAwAAAA==.',
Tr='Trailerpark:BAAALgAECgYJEgAAAA==.Tratre:BAACLgAFFH8PAAMaAAMJORVWFgDDAAAaAAMJORVWFgDDAAAfAAEJ2gX5DwA8AAAuAAQKf1UABBoACQl0GxYQAGgCABoACQl0GxYQAGgCABkABwnsHXEAAFgCAB8ABglLFVYCAJ4AAAAA.Treynof:BAABLgAECn8eAAIWAAkJmAxBLAB2AQAWAAkJmAxBLAB2AQAAAA==.Truewill:BAAALgADCgEJAQAAAA==.Trupeti:BAABLgAECn8vAAImAAkJ8wqNKAA4AQAmAAkJ8wqNKAA4AQAAAA==.',
Tu='Tulsiice:BAABLgAECn8ZAAIRAAkJFhgGPQAmAgARAAkJFhgGPQAmAgAAAA==.',
Tw='Twoglaivez:BAAALgAECgcJEgABLgAFFAkJKwAhAPEfAA==.',
Ty='Tytaniormu:BAAALgAECgkJEgAAAA==.',
['Tê']='Tês:BAAALgADCgEJAQAAAA==.',
Ug='Ugless:BAAALgADCgYJBgABLgADCgcJCAAOAAAAAA==.Uglify:BAAALgADCgcJCAAAAA==.',
Ul='Ulanmonk:BAAALgADCgMJAwAAAA==.Ulanybelle:BAAALgAECgEJAQAAAA==.Ulridan:BAAALgAECgEJAQABLgAFFAMJCQAJAJcfAA==.',
Un='Unc:BAAALgAFFAEJAgAAAA==.Undeathtwoy:BAACLgAFFH8MAAMFAAMJ2hwsOgC+AAAFAAMJ2hwsOgC+AAAHAAEJTg+XQQAsAAAuAAQKfyAAAwUABwkJHmloAL0BAAUABwmjGmloAL0BAAcABQkmFJ00AMYAAAAA.Undos:BAAALgAECgEJAgAAAA==.',
Va='Vaelraen:BAABLgAECn8kAAIEAAkJHBnvNwAiAgAEAAkJHBnvNwAiAgAAAA==.Valcher:BAABLgAECn8vAAMSAAkJqQ/oAgC9AQASAAkJqQ/oAgC9AQAWAAYJvgPqXACiAAAAAA==.Valendera:BAABLgAECn8VAAIdAAkJEQsLYACpAQAdAAkJEQsLYACpAQAAAA==.Valerius:BAAALgAECgEJAQAAAA==.Valhri:BAAALgAECgYJCgAAAA==.Valifadin:BAABLgAECn8iAAIgAAkJxxwXBwCtAgAgAAkJxxwXBwCtAgAAAA==.Valith:BAAALgAECgQJCQAAAA==.Valkenstein:BAAALgAECgIJAgABLgAFFAYJGgAEAIwZAA==.Valmoria:BAAALgADCgkJFwAAAA==.Valndrevy:BAAALgADCgUJDAAAAA==.Vansan:BAAALgAECgYJDAABLgAFFAMJBgAYACQQAA==.Varch:BAABLgAECn8bAAISAAkJJSF4BQBhAwASAAkJJSF4BQBhAwAAAA==.',
Ve='Vellas:BAAALgAECgEJAQAAAA==.Venngennce:BAABLgAECn8hAAMGAAkJFB4ABgBMAgAGAAkJFB4ABgBMAgAFAAMJ4AoF/ACDAAAAAA==.Vera:BAAALgAECgEJAQAAAA==.',
Vi='Viktir:BAAALgAECgQJBAABLgAECggJIQASAN8TAA==.Vintage:BAACLgAFFH8LAAIKAAMJjQ4VAQDsAAAKAAMJjQ4VAQDsAAAuAAQKfyIAAgoACQnpGfYAAAMDAAoACQnpGfYAAAMDAAAA.Visage:BAAALgADCgYJBgAAAA==.',
Vo='Voided:BAABLgAECn8UAAIFAAgJmyADLABQAgAFAAgJmyADLABQAgAAAA==.Volkareth:BAABLgAECn8VAAIfAAkJyhPRDQD9AQAfAAkJyhPRDQD9AQAAAA==.Vorkath:BAABLgAECn83AAQfAAkJNCMmAQD/AgAfAAkJNCMmAQD/AgAZAAgJrRxDCQBVAgAaAAMJqSDrQgAeAQAAAA==.Vormette:BAAALgADCgkJEwAAAA==.',
Vt='Vtae:BAABLgAECn8aAAICAAkJKAyBVACmAQACAAkJKAyBVACmAQAAAA==.',
Wa='Waka:BAAALgADCgkJCQABLgAECggJFQAEAFMRAA==.Wars:BAAALgADCgIJAgAAAA==.Waryndor:BAAALgADCgYJBgAAAA==.',
We='Werehamster:BAABLgAECn9gAAMSAAkJAhyMAQBGAgASAAkJAhyMAQBGAgAQAAEJehJxUAA4AAAAAA==.',
Wi='Wilderbeast:BAABLgAECn8fAAISAAkJdAV0YgAOAQASAAkJdAV0YgAOAQAAAA==.Wildlife:BAAALgADCgEJAQAAAA==.',
Wo='Woodrow:BAAALgADCgcJDgABLgAECgkJKwAYANsGAA==.Woxkal:BAABLgAECn87AAMHAAkJHQqTAwAwAQAHAAkJHQqTAwAwAQAFAAUJxgbwGwCAAAAAAA==.',
Wu='Wubblebubble:BAABLgAECn8vAAMHAAkJfhDQHQBpAQAHAAkJWw7QHQBpAQAFAAUJFxFvxwD0AAAAAA==.',
Xa='Xaelin:BAABLgAECn8sAAIBAAkJBBSoBQAJAQABAAkJBBSoBQAJAQAAAA==.',
Xe='Xernocke:BAABLgAFFH8FAAIWAAIJcRRZFACIAAAWAAIJcRRZFACIAAAAAA==.',
Ya='Yamoro:BAAALgAECgEJAQAAAA==.',
Ye='Yeimx:BAAALgAFFAMJAwAAAA==.',
Yi='Yisús:BAAALgAECgUJDQAAAA==.',
Yl='Ylvis:BAABLgAECn8tAAICAAkJSBVcNwAAAgACAAkJSBVcNwAAAgAAAA==.',
Yo='Yoshymi:BAAALgAECgkJJgAAAQ==.',
Yu='Yuná:BAAALgADCgMJAwAAAA==.',
Yv='Yvetal:BAAALgAECggJDAABLgAFFAUJCgAdAKwWAA==.',
Za='Zacco:BAABLgAECn8xAAIEAAgJtw6LggBqAQAEAAgJtw6LggBqAQAAAA==.Zalaric:BAAALgAFFAIJAgABLgAFFAYJCgAZAMoLAA==.Zaleth:BAACLgAFFH8KAAIZAAYJygs4GgDzAAAZAAYJygs4GgDzAAAuAAQKfykAAhkABwkYIakIALACABkABwkYIakIALACAAAA.Zamazenta:BAAALgADCgcJCwAAAA==.Zaranne:BAABLgAECn8lAAIFAAkJXgwdYQCmAQAFAAkJXgwdYQCmAQAAAA==.Zargar:BAAALgADCggJCQAAAA==.Zarion:BAAALgAECgYJCAABLgAFFAYJCgAZAMoLAA==.Zarra:BAAALgAECgYJDAAAAA==.Zathuera:BAAALgADCgQJBAAAAA==.Zatre:BAAALgAECgUJCQAAAA==.',
Ze='Zeirl:BAAALgADCgMJAQAAAA==.Zeroz:BAAALgAFFAEJAQAAAA==.',
Zh='Zhath:BAAALgAECgIJBAAAAA==.',
Zi='Zilik:BAABLgAECn8hAAINAAcJiSMZDgCyAgANAAcJiSMZDgCyAgABLgAFFAYJCgAZAMoLAA==.',
Zo='Zocorro:BAABLgAECn8VAAIIAAcJqhOFLwBhAQAIAAcJqhOFLwBhAQAAAA==.Zodiack:BAAALgAECgcJCgAAAA==.Zombe:BAABLgAECn8VAAIFAAgJCAmzegCPAQAFAAgJCAmzegCPAQAAAA==.',
Zu='Zuelmst:BAAALgAECgQJBgAAAA==.Zuutaa:BAAALgAECgMJAwAAAA==.',
Zy='Zym:BAAALgAECgEJAQABLgAFFAYJGgAEAIwZAA==.Zypherdius:BAAALgAECgYJDgAAAA==.',
['Ân']='Ângel:BAAALgAFFAEJAQABLgAFFAQJCAAcANgGAA==.',
['Ðe']='Ðecision:BAACLgAFFH8ZAAIEAAUJpSRvGwCbAQAEAAUJpSRvGwCbAQAuAAQKfyoAAgQACQkNJesHAC0DAAQACQkNJesHAC0DAAAA.',
['Øn']='Ønslaught:BAAALgADCgUJBQABLgAECggJFQAEAFMRAA==.',
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
