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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Devourer','DemonHunter-Vengeance','Paladin-Protection','DemonHunter-Havoc','Paladin-Retribution','Paladin-Holy','Druid-Balance','Unknown-Unknown','Druid-Feral','DeathKnight-Frost','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Monk-Brewmaster','Shaman-Elemental','Warlock-Demonology','Warrior-Fury','Warrior-Protection','Shaman-Enhancement','Monk-Mistweaver','Shaman-Restoration','Priest-Discipline','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Arms','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Warlock-Affliction','Druid-Guardian','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-06-13',data={Aa='Aaronius:BAABLgAECn8oAAIBAAgJLQXIPAD7AAABAAgJLQXIPAD7AAAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8rAAMCAAkJyR0IJgCBAgACAAkJwB0IJgCBAgADAAUJNReKCwAeAQAAAA==.',
Ac='Acceptance:BAAALgAECgMJBAAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8uAAIEAAkJFyLHEADHAgAEAAkJFyLHEADHAgAAAA==.Adora:BAABLgAECn8jAAIEAAkJaBztEwCvAgAEAAkJaBztEwCvAgAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aelise:BAAALgADCgQJBAABLgAECgkJMAAFAFEfAA==.',
Ag='Agaliarept:BAACLgAFFH8KAAIGAAQJAgrkUgDvAAAGAAQJAgrkUgDvAAAuAAQKfxYAAwcACAkYCygaAMgAAAYABwnpBuCLAAsBAAcABwkPCygaAMgAAAAA.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAABLgAECn8WAAIIAAUJyhWKKADPAAAIAAUJyhWKKADPAAAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn88AAMJAAkJXRT2FADkAQAJAAkJXRT2FADkAQAGAAgJ8AcgcwA4AQAAAA==.',
Ak='Akumajoe:BAAALgADCgcJBwAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAABLgAECn8VAAMKAAgJ3xXNeQB4AQAKAAgJ3xXNeQB4AQALAAIJ4BF5dgBeAAAAAA==.Aluni:BAAALgAECgUJBQAAAA==.',
Am='Amethÿst:BAAALgAFFAIJAgAAAA==.Amoral:BAAALgAECgMJAwAAAA==.',
An='Angelneko:BAABLgAECn8zAAIMAAkJaQ0KKACMAQAMAAkJaQ0KKACMAQAAAA==.Anitabj:BAAALgAECgMJAwAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwANAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIMAAYJWAM9VgDLAAAMAAYJWAM9VgDLAAAAAA==.Arcon:BAAALgAECgEJAQAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8RAAMOAAYJvxdiAQBxAQAOAAUJmxtiAQBxAQAMAAEJTgg6RwBNAAAuAAQKfywAAg4ACQnzIJkDANQCAA4ACQnzIJkDANQCAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJFAAKAO4aAA==.Auley:BAAALgADCgQJBAAAAA==.Aumers:BAAALgAECgEJAQAAAA==.Auroraa:BAABLgAECn8tAAIMAAgJoAjkPQATAQAMAAgJoAjkPQATAQAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgANAAAAAA==.',
Av='Avalectra:BAAALgAECgUJCAAAAA==.',
Ay='Aylana:BAAALgAECgYJBgAAAA==.',
Az='Azanost:BAAALgADCgQJBAABLgAECgkJJAAPAOAVAA==.Azmodeaz:BAABLgAECn89AAIDAAkJxhtpAQCRAgADAAkJxhtpAQCRAgAAAA==.',
Ba='Bajapanti:BAABLgAECn86AAIQAAkJvxu/AwCGAgAQAAkJvxu/AwCGAgAAAA==.Ballyhøø:BAABLgAECn8aAAIMAAkJRhQoMABZAQAMAAkJRhQoMABZAQAAAA==.Banchory:BAAALgADCgQJBQAAAA==.Bandaron:BAAALgAECgQJCgAAAA==.Baxstab:BAABLgAECn82AAIRAAkJ5xu2DABXAgARAAkJ5xu2DABXAgAAAA==.',
Bc='Bcam:BAAALgADCgYJBgAAAA==.',
Be='Beahon:BAAALgAECgQJDQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgMJAwAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJCgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackjak:BAAALgAECgEJAQAAAA==.Blackpatch:BAABLgAECn84AAMSAAkJZCKnBAALAwASAAkJZCKnBAALAwATAAgJ4gdfOAAYAQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgUJCgAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Bloomhammer:BAABLgAFFH8JAAIUAAQJOhYYHgAlAQAUAAQJOhYYHgAlAQAAAA==.Blooming:BAAALgAECgcJDQABLgAECggJHAAVAA4aAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJDBYUZQBZAQAGAAgJDBYUZQBZAQAAAA==.Bloomslinger:BAAALgADCgQJBAAAAA==.',
Bo='Bonerflex:BAACLgAFFH8JAAIWAAQJ+wq+KQAIAQAWAAQJ+wq+KQAIAQAuAAQKfygAAxYACQlKGm8NAJUCABYACQlKGm8NAJUCABcABAlACj5CAGMAAAAA.Booneboy:BAABLgAECn8cAAMKAAgJTyGaJABwAgAKAAgJTyGaJABwAgAIAAQJVhBvKwC9AAAAAA==.Boptyboopity:BAAALgAECgQJBgAAAA==.Botemedel:BAABLgAECn8lAAMIAAkJXxV/GQBLAQAIAAkJ7BJ/GQBLAQAKAAcJ3A24ogAxAQABLgAFFAUJGgAYAPsXAA==.',
Br='Brennor:BAABLgAECn8zAAIKAAkJ5w6mZgCfAQAKAAkJ5w6mZgCfAQAAAA==.Brewslunt:BAACLgAFFH8QAAIZAAYJQRbYHAB7AQAZAAYJQRbYHAB7AQAuAAQKfywAAxkACAmfIQ4TAH8CABkACAmfIQ4TAH8CABIAAwnEC+tmAIQAAAEuAAUUBwkfABoAvR4A.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Bubblydin:BAAALgAECgYJBgABLgAFFAMJCAAbAP0GAA==.Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAABLgAECn8rAAIaAAkJ1xNSJAAwAgAaAAkJ1xNSJAAwAgAAAA==.Cairyan:BAABLgAECn80AAIHAAkJJx3EAwCVAgAHAAkJJx3EAwCVAgAAAA==.Caiya:BAAALgADCgcJBwABLgAECgkJOAARAOMkAA==.Capn:BAAALgADCgcJCQAAAA==.Carvil:BAABLgAECn8zAAMcAAkJGxaOBgDzAQAcAAkJGxaOBgDzAQAVAAMJjwcI7QCDAAAAAA==.Castalia:BAAALgAECgYJEAAAAA==.Catboy:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8XAAICAAYJKBfnMwCcAQACAAYJKBfnMwCcAQAuAAQKfysAAgIACQkXJCocAAYDAAIACQkXJCocAAYDAAAA.Celendil:BAAALgAECgEJAQABLgAFFAYJFwACACgXAA==.Celithe:BAABLgAECn8dAAIKAAgJpxSaXQC0AQAKAAgJpxSaXQC0AQAAAA==.Cendrian:BAABLgAECn8WAAIMAAcJYQu2QgD9AAAMAAcJYQu2QgD9AAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8tAAICAAkJfhxjLQBhAgACAAkJfhxjLQBhAgAAAA==.Charmshield:BAAALgAECgMJAwAAAA==.Cheezle:BAAALgAECgkJCAAAAA==.Chiafix:BAABLgAECn8cAAITAAgJDwzNMQA3AQATAAgJDwzNMQA3AQABLgAECgkJMgAaANYhAA==.Chipp:BAABLgAECn8UAAITAAcJ/CbRBwC1AgATAAcJ/CbRBwC1AgAAAA==.Chleo:BAAALgAECgMJBwAAAA==.Choco:BAACLgAFFH8kAAIdAAgJox2GAgDRAgAdAAgJox2GAgDRAgAuAAQKfykAAx0ACQnvI+QFAOgCAB0ACQnvI+QFAOgCAB4AAQkVG+0gAEkAAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAgJJAAdAKMdAA==.Chudster:BAABLgAECn8gAAMeAAkJ/RUpCACuAQAeAAkJ/RUpCACuAQAfAAUJDQjwXgC5AAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Cl='Clerick:BAAALgAECgIJAgAAAA==.',
Co='Coggler:BAABLgAECn8kAAMXAAgJFiAECAB5AgAXAAgJFiAECAB5AgAgAAEJixF6dgAwAAAAAA==.Conqueror:BAAALgAECgYJEAABLgAFFAMJCQAFAE8RAA==.',
Cr='Crawdaddy:BAABLgAECn8WAAIEAAcJJhIybwBdAQAEAAcJJhIybwBdAQAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgcJDwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECggJHAAKAFcMAA==.Curmudge:BAABLgAECn9OAAIFAAkJrBf8HABbAgAFAAkJrBf8HABbAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgANAAAAAA==.Cybele:BAABLgAECn8XAAIBAAcJKgvHNwAZAQABAAcJKgvHNwAZAQAAAA==.',
Da='Dakunaito:BAABLgAECn8fAAIhAAkJTCTzEwDOAgAhAAkJTCTzEwDOAgAAAA==.Danay:BAAALgAECgEJAQAAAA==.Danksquaddon:BAAALgADCgQJBAAAAA==.Darachane:BAABLgAECn8zAAMiAAcJ6A8VNABGAQAiAAcJ6A8VNABGAQABAAEJxwLgeAAfAAAAAA==.Darovan:BAAALgADCgMJAwABLgAECgkJQAAjAOkjAA==.Dauglow:BAAALgAECgYJCQAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJDQAAAA==.Deathstars:BAAALgADCggJDwAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAFFAEJAgAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEwAAAA==.Deltia:BAABLgAECn8rAAIUAAkJshhwFgAwAgAUAAkJshhwFgAwAgAAAA==.Deluzion:BAAALgAECgUJBQABLgAFFAQJEAAEAKURAA==.Demonagent:BAAALgAECgcJEgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8VAAMfAAYJ+hadHgBjAQAfAAYJ+hadHgBjAQAeAAIJfQ4ZCQBYAAAuAAQKfzAAAx4ACQkOH9YJAEICAB4ACQlbHNYJAEICAB8ACAlrG8obAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8cAAIVAAgJDhr3OQDxAQAVAAgJDhr3OQDxAQAAAA==.',
Di='Dimebagg:BAAALgAECgYJCgAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8sAAMBAAgJdx2vEgBFAgABAAgJdx2vEgBFAgAbAAMJDgnvRACRAAAAAA==.Dokspades:BAABLgAECn8UAAIaAAkJ/g8zMgDmAQAaAAkJ/g8zMgDmAQAAAA==.Dornoch:BAABLgAECn8hAAMLAAcJFiKrDgCoAgALAAcJFiKrDgCoAgAKAAEJ8AE1XAEjAAAAAA==.Dotzilla:BAABLgAECn8UAAQVAAUJ7iU+gwAyAQAVAAMJtSQ+gwAyAQAkAAIJ9iUpHADYAAAcAAIJbSTeLABiAAAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJCQAAAA==.Dreadnight:BAAALgAECgIJAgAAAA==.Dremire:BAABLgAECn8tAAIKAAkJ2g1IbACTAQAKAAkJ2g1IbACTAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgcJEgANAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAABLgAFFH8HAAIGAAIJ+h09cAChAAAGAAIJ+h09cAChAAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8PAAIhAAMJwRkdkQDlAAAhAAMJwRkdkQDlAAAuAAQKfzQAAiEACQknIYoWAL0CACEACQknIYoWAL0CAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAgAAAA==.',
Ei='Einherja:BAAALgAECgQJBgAAAA==.Eisenhorn:BAAALgAECgUJBgAAAA==.',
El='Elessaria:BAABLgAECn8cAAIFAAgJCgaXagDyAAAFAAgJCgaXagDyAAAAAA==.Elfatheàrt:BAABLgAECn8WAAIKAAUJ8A+u4wDWAAAKAAUJ8A+u4wDWAAAAAA==.Elidrus:BAAALgADCgcJBwABLgAECgkJCQANAAAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emelgee:BAABLgAECn8UAAIlAAYJMw3GNQDKAAAlAAYJMw3GNQDKAAABLgAFFAMJCAAbAP0GAA==.Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgkJIwAEAGgcAA==.',
Es='Esika:BAAALgAFFAIJAwAAAA==.Estherras:BAABLgAECn8wAAIEAAkJXBqgIwBRAgAEAAkJXBqgIwBRAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fa='Fato:BAAALgAECgUJBgAAAA==.',
Fe='Feardotrun:BAABLgAECn8kAAMVAAkJhQ3VVACdAQAVAAkJ2QzVVACdAQAcAAMJWQwJJgB/AAAAAA==.Felicious:BAAALgAECgUJEQAAAA==.Felora:BAAALgAECgEJAQABLgAECgQJBgANAAAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgAECgMJAgAAAA==.Finahlia:BAABLgAECn8gAAIFAAkJ7CHFBQBZAwAFAAkJ7CHFBQBZAwAAAA==.Finally:BAABLgAECn8jAAIUAAcJvQgkUgDrAAAUAAcJvQgkUgDrAAAAAA==.Firebat:BAAALgADCgcJBwABLgAECggJHAAKAE8hAA==.Firemage:BAABLgAECn81AAIVAAkJLiN1BwAcAwAVAAkJLiN1BwAcAwAAAA==.Fizzanelf:BAABLgAECn8jAAIFAAcJOCNXEQDDAgAFAAcJOCNXEQDDAgAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAACLgAFFH8MAAIKAAUJpQRWXwDqAAAKAAUJpQRWXwDqAAAuAAQKfzIAAgoACQkKGgBRAO4BAAoACQkKGgBRAO4BAAAA.Friendo:BAABLgAECn85AAMOAAkJARniBwBRAgAOAAkJARniBwBRAgAMAAQJcwYdZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAFFAEJAwAAAA==.Frynied:BAAALgAECgUJCAABLgAECgkJIgABAKwaAA==.',
Fu='Furnost:BAABLgAECn8kAAIPAAkJ4BUXCQD0AQAPAAkJ4BUXCQD0AQAAAA==.Futnuraz:BAABLgAECn8fAAIgAAcJNAdOOQDbAAAgAAcJNAdOOQDbAAAAAA==.',
Fy='Fyrakkobama:BAAALgAECgkJBQABLgAECgkJGQAmAP0iAA==.Fyriat:BAABLgAECn81AAICAAkJ0wnUdACNAQACAAkJ0wnUdACNAQAAAA==.',
Ga='Gazardiel:BAAALgAECgIJAgAAAA==.',
Ge='Getafix:BAAALgAECgcJCwABLgAECgkJMgAaANYhAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgUJCgAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8yAAISAAgJsxwOEABIAgASAAgJsxwOEABIAgAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goldstorm:BAAALgADCgYJBgAAAA==.Goliath:BAAALgAECgUJCgABLgAECgkJGwAKAMcbAA==.Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8lAAIcAAkJIh1OAgCYAgAcAAkJIh1OAgCYAgAAAA==.Greybark:BAAALgADCgcJEQAAAA==.Griffindor:BAABLgAECn8zAAIKAAkJYBgHMgA1AgAKAAkJYBgHMgA1AgAAAA==.Grimfelborn:BAACLgAFFH8gAAMkAAYJgBLCCADpAAAVAAUJVg7QOABgAQAkAAQJ4BHCCADpAAAuAAQKfzIAAxUACQn1HLsxAEUCABUACQlMG7sxAEUCACQAAwlQIdQgALUAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAABLgAECn8mAAIaAAgJpxvXGQB4AgAaAAgJpxvXGQB4AgAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgAECgEJAgAAAA==.',
Ha='Hanicus:BAAALgAECgkJCQAAAA==.Hanoverfiste:BAABLgAECn8cAAIKAAgJVwwwkQBNAQAKAAgJVwwwkQBNAQAAAA==.Hapsburg:BAABLgAECn8rAAIZAAkJdxImJAD6AQAZAAkJdxImJAD6AQAAAA==.Havince:BAABLgAECn82AAIjAAkJ+CDgBgCuAgAjAAkJ+CDgBgCuAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn84AAIKAAkJsB9QFgC7AgAKAAkJsB9QFgC7AgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Ig='Ignisdaemoni:BAAALgAECgMJBAABLgAECgkJIAAFAOwhAA==.',
Il='Illidai:BAAALgAECgYJEgAAAA==.Ilyndra:BAABLgAECn8zAAMgAAkJ3iFKBwCBAgAXAAkJeR2QBwCGAgAgAAgJsyFKBwCBAgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn81AAIWAAkJuxabGgAXAgAWAAkJuxabGgAXAgAAAA==.',
It='Ithea:BAABLgAECn8xAAICAAkJCCFFEwDkAgACAAkJCCFFEwDkAgAAAA==.',
Ja='Jackyll:BAAALgAECgIJBQAAAA==.Jaeson:BAEBLgAECn8iAAIVAAkJjhapMAAUAgAVAAkJjhapMAAUAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAgJHwALAGscAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgkJGQAmAP0iAA==.Jeefrenzy:BAABLgAECn8ZAAMmAAkJ/SLqBADaAgAmAAkJ/SLqBADaAgAEAAIJkiEU+wBeAAAAAA==.Jeefwrld:BAAALgAECgQJBAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgcJEQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8lAAQBAAkJeBlQHwDEAQABAAgJsRJQHwDEAQAbAAYJ8RSgIwB2AQAiAAUJDRSMPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAABLgAECn8cAAInAAgJsg/8CQCYAQAnAAgJsg/8CQCYAQAAAA==.',
Jw='Jwise:BAAALgAECgkJBgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kamus:BAAALgAECgMJAwAAAA==.Kanabat:BAAALgAECgcJDgAAAA==.Karaden:BAAALgAECgUJBQAAAA==.Karawyn:BAABLgAECn8kAAIEAAgJ5Q5BPQC5AQAEAAgJ5Q5BPQC5AQABLgAECgcJCQANAAAAAA==.Karelix:BAAALgAECgIJAwAAAA==.Katrishy:BAACLgAFFH8gAAMiAAYJrxjqDACMAQAiAAYJrxjqDACMAQABAAEJcQH4NAA6AAAuAAQKfy8AAyIACQk+IIcWADMCACIACQk+IIcWADMCAAEAAQlwBUSIACcAAAAA.Kaylierocks:BAAALgAECgEJAQAAAA==.Kayyfrost:BAAALgADCgIJAgAAAA==.Kazeral:BAAALgADCggJEQAAAA==.',
Ke='Keedrid:BAABLgAECn8WAAIhAAkJbh3+MwAsAgAhAAkJbh3+MwAsAgAAAA==.Keindis:BAAALgAECgcJDwABLgAECgcJMwAiAOgPAA==.Kelaeno:BAAALgADCgkJCQABLgAECggJHQAGAAwHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJDAfrkgD2AAAGAAgJDAfrkgD2AAAAAA==.Kelox:BAAALgAECgEJAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8yAAIaAAkJ1iGqBgBDAwAaAAkJ1iGqBgBDAwAAAA==.Kruàlty:BAACLgAFFH8GAAIOAAUJ5RJGCAAgAQAOAAUJ5RJGCAAgAQAuAAQKfyQAAg4ACAmCHYsHAFwCAA4ACAmCHYsHAFwCAAAA.',
Kt='Kthnx:BAAALgADCgEJAQABLgAECgMJAwANAAAAAA==.',
Ku='Kungpow:BAAALgAECgMJAwAAAA==.',
Le='Legreebash:BAAALgAECgEJAQABLgAECgcJFwADAFIKAA==.Legreecast:BAABLgAECn8XAAIDAAcJUgptCAASAQADAAcJUgptCAASAQAAAA==.Levlia:BAAALgADCgYJBgAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgcJCwAAAA==.Litheliice:BAABLgAECn8yAAQBAAkJGQ/qJwCCAQABAAkJGQ/qJwCCAQAiAAIJ2wcpfgA8AAAbAAEJrgEaiAAbAAAAAA==.',
Lo='Loamuhwea:BAAALgAECgEJAQAAAA==.Lodur:BAABLgAECn8uAAIaAAkJlRtQGgB0AgAaAAkJlRtQGgB0AgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn80AAIlAAkJJhP1FQCeAQAlAAkJJhP1FQCeAQAAAA==.Losat:BAABLgAECn86AAIXAAkJzg0KGAB8AQAXAAkJzg0KGAB8AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8bAAIKAAkJxxsJKABhAgAKAAkJxxsJKABhAgAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJCwANAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAABLgAFFH8GAAIbAAMJQwuwNACyAAAbAAMJQwuwNACyAAAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgkJMQAZAGAWAA==.Mackkie:BAABLgAECn8xAAMZAAkJYBYkHwAbAgAZAAgJgRckHwAbAgASAAcJvg3qNAAsAQAAAA==.Madonkadonk:BAABLgAECn82AAMeAAkJwhA2BwDKAQAeAAkJwhA2BwDKAQAfAAMJlAWXiABGAAAAAA==.Maedai:BAABLgAECn81AAIZAAkJyhbAGABNAgAZAAkJyhbAGABNAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAACLgAFFH8IAAILAAQJbBa7IQALAQALAAQJbBa7IQALAQAuAAQKfzsAAwsACQk3Hs8TAG4CAAsACQk3Hs8TAG4CAAoABQm7EA8IAaoAAAAA.Magús:BAAALgAECgEJAgAAAA==.Maldive:BAABLgAECn8uAAIVAAkJZRH8QwDOAQAVAAkJZRH8QwDOAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Maliificent:BAAALgAECgEJAQAAAA==.Mallicia:BAACLgAFFH8SAAIBAAQJkSGqDgBeAQABAAQJkSGqDgBeAQAuAAQKfzcAAwEACQm4I5cDACADAAEACQm4I5cDACADABsACAmiFyYVAC8CAAAA.Mallika:BAABLgAECn8mAAMaAAgJvxfbJwAcAgAaAAgJvxfbJwAcAgAUAAEJ3wm1pgAsAAABLgAFFAQJEgABAJEhAA==.Mallistraza:BAAALgAECgIJAwABLgAFFAQJEgABAJEhAA==.Mallwizard:BAACLgAFFH8JAAIVAAMJjAYShQC2AAAVAAMJjAYShQC2AAAuAAQKfy0AAhUACQnEFZQ4ACkCABUACQnEFZQ4ACkCAAAA.Mandor:BAAALgADCgYJBgAAAA==.Mangopewpew:BAAALgAECgUJDwAAAA==.Marks:BAAALgAECgEJAQAAAA==.Martris:BAAALgAECgIJAgAAAA==.Massoflice:BAACLgAFFH8MAAIhAAQJSgkEfAAKAQAhAAQJSgkEfAAKAQAuAAQKfyoAAiEACQn2Fyk3ACACACEACQn2Fyk3ACACAAAA.Maxblaide:BAAALgAECgUJEQAAAA==.Maxilla:BAAALgADCgcJDQABLgAFFAQJCQAWAPsKAA==.',
Me='Menguli:BAAALgAECgIJAgAAAA==.Meridians:BAABLgAECn8bAAIZAAYJxxZ4OwB7AQAZAAYJxxZ4OwB7AQAAAA==.',
Mh='Mhataharii:BAAALgAECgEJAQAAAA==.',
Mi='Mindhorn:BAACLgAFFH8MAAMUAAMJkxrELQDWAAAUAAMJkxrELQDWAAAaAAIJrRmeVwCZAAAuAAQKfycAAxQACAk0IR8QAHACABQACAk0IR8QAHACABoABAnTFYd8AKEAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8yAAIIAAkJAhm1CgAbAgAIAAkJAhm1CgAbAgAAAA==.Moctar:BAAALgADCgQJBAAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8XAAIKAAgJJyAcMwBWAgAKAAgJJyAcMwBWAgAAAA==.Muradox:BAAALgAECgEJAQABLgAECgkJIgAfAHYUAA==.Musashi:BAAALgAFFAMJBAAAAA==.Mustardhunt:BAAALgADCgcJDAAAAA==.',
My='Myriad:BAABLgAECn8vAAIXAAkJmh8qBgCpAgAXAAkJmh8qBgCpAgAAAA==.',
Na='Nakze:BAABLgAECn82AAIRAAkJAg9LGADVAQARAAkJAg9LGADVAQAAAA==.Namanari:BAAALgAECgEJAQAAAA==.Nancydru:BAAALgAECgQJBAAAAA==.Nardwuar:BAAALgAECgYJDAABLgAFFAEJAwANAAAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8xAAIEAAkJURwdGgCEAgAEAAkJURwdGgCEAgAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.Neptune:BAAALgAFFAIJAgAAAA==.',
Nh='Nhilas:BAAALgAECgQJDAAAAA==.',
Ni='Nightstryke:BAAALgAECgEJAQAAAA==.Nishal:BAAALgADCgkJEgAAAA==.',
No='Nork:BAAALgAECgIJAgAAAA==.',
Ny='Nyxaries:BAABLgAECn8eAAIjAAgJqhhuEwDZAQAjAAgJqhhuEwDZAQAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
On='Onenytestand:BAAALgAECgkJCAAAAA==.',
Or='Ordis:BAAALgADCgQJBAAAAA==.Orrana:BAAALgAECgEJAQAAAA==.',
Pa='Pablo:BAAALgAECgcJDgAAAA==.Pannacea:BAAALgAECgYJDQABLgAECgkJMgAaANYhAA==.Panzerblitz:BAABLgAECn8cAAIlAAgJhQk7NQDNAAAlAAgJhQk7NQDNAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIcAAcJNQoFIABSAQAcAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCggJDAAAAA==.',
Pe='Pedrote:BAAALgADCgcJCgAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Peppert:BAAALgAECggJCAAAAA==.Pestcontrol:BAAALgAECgYJCwAAAA==.',
Ph='Phane:BAAALgAECgUJCQAAAA==.Phson:BAAALgADCgkJDgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJOCApKgANAgAEAAYJOCApKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pincher:BAAALgADCgQJBAAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAwAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAABLgAECn8hAAIgAAcJUwnvMQD7AAAgAAcJUwnvMQD7AAAAAA==.Pretzelz:BAAALgAECgMJAwAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puertoricanj:BAAALgAECgMJAgAAAA==.Puffer:BAABLgAECn84AAICAAkJdhBSWQDOAQACAAkJdhBSWQDOAQAAAA==.',
Ra='Rabone:BAAALgAECgUJBQAAAA==.Raelaris:BAAALgAFFAIJAwABLgAFFAUJEwACANgjAA==.Raevyn:BAAALgAECgUJBQAAAA==.Raito:BAABLgAECn8gAAIKAAgJcgu/mgA9AQAKAAgJcgu/mgA9AQAAAA==.Rakshasa:BAACLgAFFH8NAAIVAAQJeh1FNwBlAQAVAAQJeh1FNwBlAQAuAAQKfykAAxUACQnJIjUMAOsCABUACQnJIjUMAOsCACQAAQkAALIhAGsAAAAA.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgUJCAABLgAECgkJIwAEAGgcAA==.Rasetsungo:BAABLgAECn8fAAIBAAkJnxweDACiAgABAAkJnxweDACiAgAAAA==.Raura:BAABLgAECn8hAAIjAAcJuRIyIABOAQAjAAcJuRIyIABOAQAAAA==.Rayala:BAAALgAECgkJCQAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAABLgAECn8oAAIKAAkJlxCrUQDRAQAKAAkJlxCrUQDRAQAAAA==.Remi:BAABLgAECn8iAAMBAAgJrBqkEQBQAgABAAgJrBqkEQBQAgAiAAEJ3RMSfgA8AAAAAA==.Reveillark:BAABLgAECn8UAAIdAAYJYheiEgCbAQAdAAYJYheiEgCbAQAAAA==.Revelaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.',
Ro='Rolan:BAACLgAFFH8IAAIhAAQJDyVHLACsAQAhAAQJDyVHLACsAQAuAAQKfx4AAiEACQnYJGoWAL4CACEACQnYJGoWAL4CAAAA.Roogyrunes:BAAALgAECgcJCQABLgAECgkJIwAKAIUjAA==.Rosalian:BAABLgAECn81AAIFAAkJJhxzEADLAgAFAAkJJhxzEADLAgAAAA==.Rotiko:BAABLgAECn8iAAIaAAkJoQtIRgCQAQAaAAkJoQtIRgCQAQAAAA==.Roweene:BAABLgAECn8yAAIoAAkJPAjjCwBWAQAoAAkJPAjjCwBWAQAAAA==.',
Ry='Ryez:BAAALgAECgEJAQAAAA==.Ryusei:BAAALgAECgQJBAAAAA==.',
['Rá']='Rágnar:BAABLgAECn8XAAQKAAkJ/Q7VYQCqAQAKAAkJJg7VYQCqAQAIAAcJkgchKwC/AAALAAMJSQZEcgBqAAAAAA==.',
Sa='Saintseven:BAAALgAECgUJEgAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgAECgUJBgAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8nAAMSAAgJdh8VEgAuAgASAAgJdh8VEgAuAgATAAEJEws+hQA8AAABLgAECgkJDgANAAAAAA==.Serenatee:BAABLgAECn8xAAIiAAkJnhBlIADBAQAiAAkJnhBlIADBAQAAAA==.',
Sh='Shadowkrak:BAAALgAECgEJAgAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCgkJGAAAAA==.Shappens:BAAALgADCgcJEwABLgAECggJHAAKAFcMAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgYJEQAAAA==.Shoottokill:BAAALgAECgMJAwAAAA==.Shouhuzhee:BAACLgAFFH8HAAIGAAMJcA0sZwC4AAAGAAMJcA0sZwC4AAAuAAQKfx0AAgYACQlzEgs9ANABAAYACQlzEgs9ANABAAAA.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgcJGQAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgQJBAAAAA==.Simbà:BAAALgAECgYJDwAAAA==.',
Sk='Skaelig:BAAALgADCgIJBAAAAA==.Skugen:BAAALgADCgcJDQAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8YAAMGAAcJGSHEIQCGAgAGAAcJGSHEIQCGAgAJAAEJ9hZVawA7AAABLgAECgkJGQAmAP0iAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAACLgAFFH8KAAIRAAMJ7BcjIwACAQARAAMJ7BcjIwACAQAuAAQKfxQAAxEABglfHqEfAJUBABEABQlfHqEfAJUBACcAAwlRGk0kAEEAAAAA.',
So='Soferfax:BAAALgADCgYJDQAAAA==.Sokroar:BAABLgAFFH8FAAIhAAIJaQwK3wCFAAAhAAIJaQwK3wCFAAABLgAFFAQJBQACAHYJAA==.Sonknight:BAABLgAECn8pAAMLAAYJswfbUwDmAAALAAYJswfbUwDmAAAKAAUJ8QLnMwF0AAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIUAAgJZB0wGQAWAgAUAAgJZB0wGQAWAgAAAA==.Spiky:BAAALgAECgIJAgAAAA==.Spitefulcrow:BAABLgAECn8/AAImAAkJzQqUHgCnAQAmAAkJzQqUHgCnAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgQJCAAAAA==.Sto:BAABLgAECn8UAAIKAAgJ7hrwNQAnAgAKAAgJ7hrwNQAnAgAAAA==.Stratof:BAAALgADCgIJAgAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Subjugaiden:BAAALgAECgEJAQABLgAECgkJPAAJAF0UAA==.Sukerpunch:BAAALgADCgEJAQAAAA==.Supad:BAAALgADCgYJBwAAAA==.Superjpriest:BAAALgAFFAEJAQABLgAFFAMJAwANAAAAAA==.Suria:BAABLgAECn8wAAIFAAkJUR8DCQAnAwAFAAkJUR8DCQAnAwAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgIJAgAAAA==.Syphax:BAAALgAECgMJAwAAAA==.',
Ta='Tackle:BAAALgAECgIJAgAAAA==.Tahrovin:BAAALgAECgIJAgAAAA==.Talaera:BAAALgAECgUJCwAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgAECgEJAQAAAA==.Taternutzz:BAAALgAECgEJAQAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAABLgAECn8sAAMbAAkJUx5JCwC4AgAbAAgJLx5JCwC4AgABAAIJwxLqVgB5AAAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8+AAMLAAkJzwWdPABRAQALAAkJzwWdPABRAQAKAAgJ3gn2zAD0AAAAAA==.',
Te='Ted:BAAALgADCgUJBQAAAA==.Teenyshieva:BAAALgADCgEJAQAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgAECgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn82AAIYAAkJPiGsAwDBAgAYAAkJPiGsAwDBAgAAAA==.',
Ti='Tigerstarr:BAACLgAFFH8MAAIhAAMJ1BDrnADWAAAhAAMJ1BDrnADWAAAuAAQKfx4AAyEACQm7E7c6ABMCACEACQm7E7c6ABMCAA8AAQlRBioZACoAAAAA.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8bAAMBAAYJTA7xPQD1AAABAAYJTA7xPQD1AAAiAAQJTwPTZgB8AAAAAA==.Tizuki:BAAALgAECgIJAwAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgkJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8wAAIcAAgJCxzXBAAnAgAcAAgJCxzXBAAnAgAAAA==.Treenn:BAABLgAECn8ZAAMaAAYJ7hR3TQB3AQAaAAYJ7hR3TQB3AQAUAAMJ/wQ/gwBlAAAAAA==.Triplock:BAAALgAECgYJBgAAAA==.Trolcain:BAABLgAECn8uAAIhAAkJLiRxCAAtAwAhAAkJLiRxCAAtAwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgkJLgAhAC4kAA==.',
Ty='Tyrix:BAABLgAECn8jAAIKAAkJhSOZCgAQAwAKAAkJhSOZCgAQAwAAAA==.Tyránt:BAACLgAFFH8QAAIEAAQJpRHpRQAbAQAEAAQJpRHpRQAbAQAuAAQKfzEAAwQACQlNI10MAO0CAAQACQlNI10MAO0CABAAAQkAAN6bABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAITAAYJ2BmCQABCAQATAAYJ2BmCQABCAQAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXwYQAWAgACAAUJoyXwYQAWAgAAAA==.Valadir:BAAALgAECgQJCwAAAA==.Valerossi:BAABLgAECn84AAImAAkJlx/OBADdAgAmAAkJlx/OBADdAgAAAA==.Valha:BAABLgAECn8mAAIJAAkJeRItFwDIAQAJAAkJeRItFwDIAQAAAA==.Valira:BAAALgADCggJCQABLgAECgkJIwAEAGgcAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgAECgIJAgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAQJEgABAJEhAA==.Varteras:BAABLgAECn8yAAMkAAkJsxsqBgAbAgAkAAgJghsqBgAbAgAVAAgJnxLyVQCaAQAAAA==.',
Ve='Veleiri:BAABLgAECn8vAAICAAkJSBFJTwDrAQACAAkJSBFJTwDrAQAAAA==.Velenal:BAAALgAECgQJDAAAAA==.Vellron:BAABLgAECn8uAAIEAAkJhw4ZRQDOAQAEAAkJhw4ZRQDOAQAAAA==.',
Vo='Voidgawd:BAAALgADCgcJCQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAACLgAFFH8UAAMGAAUJbRgXUwDvAAAGAAQJlRsXUwDvAAAJAAIJHA3WIACJAAAuAAQKfxYAAwkABgm1IxEYAL8BAAkABgkKIxEYAL8BAAYABAkfH25pAE4BAAAA.Wardkbriggle:BAACLgAFFH8OAAIjAAYJkx4oDACwAQAjAAYJkx4oDACwAQAuAAQKfyEAAiMACQmoI5kDAAMDACMACQmoI5kDAAMDAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8YAAITAAYJxRzxCgDXAQATAAYJxRzxCgDXAQAuAAQKfyAAAhMACQkeIBwLAIACABMACQkeIBwLAIACAAAA.',
Wi='Wifi:BAAALgAECgIJBwAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMjAAYJeAWFNwCGAAAjAAQJGQaFNwCGAAAPAAUJ9AEBEwBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn86AAICAAkJ1RItTQDxAQACAAkJ1RItTQDxAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn84AAQRAAkJ4yT+AQBEAwARAAkJsyT+AQBEAwAnAAcJASMUBAB1AgAoAAYJth3MCQCJAQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJCwABLgAECgkJOAARAOMkAA==.',
Xh='Xhared:BAABLgAECn9AAAIjAAkJ6SN7AgAmAwAjAAkJ6SN7AgAmAwAAAA==.',
Ya='Yahtzee:BAAALgAECgMJBgAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8fAAIGAAgJBwNYugCyAAAGAAgJBwNYugCyAAAAAA==.',
Ye='Yesenia:BAAALgADCgkJCQAAAA==.',
Yk='Ykszord:BAAALgAECgEJAQAAAA==.',
Ze='Zephy:BAAALgAECgYJCgAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Åe']='Åeon:BAABLgAECn8aAAIEAAcJGRAqdABTAQAEAAcJGRAqdABTAQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRg0AgARAQApAAQJuRg0AgARAQAuAAQKfzQAAykACQlVIMEAAP8CACkACQlVIMEAAP8CAAIABAmyF6r5AAcBAAAA.',
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
