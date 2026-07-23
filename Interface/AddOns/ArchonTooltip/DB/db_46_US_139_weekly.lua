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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Evoker-Augmentation','Shaman-Restoration','DeathKnight-Blood','Warlock-Demonology','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Druid-Guardian','Druid-Feral','Shaman-Enhancement','Druid-Balance','Shaman-Elemental','Monk-Brewmaster','Warlock-Affliction','Rogue-Subtlety','DemonHunter-Vengeance','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Warrior-Arms','Warrior-Protection','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-07-19',data={Ab='Abeblinken:BAAALgAECgIJAgAAAA==.Ablucia:BAAALgADCgUJCQAAAA==.Abomb:BAAALgAECgEJAwAAAA==.Abotharn:BAAALgADCgUJBQAAAA==.Absolution:BAAALgAECgQJBAAAAA==.',
Ac='Acanaline:BAAALgAECgEJAgAAAA==.Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgUJCAAAAA==.Aeoliana:BAABLgAECn8cAAIBAAgJKA/ZBQBSAQABAAgJKA/ZBQBSAQAAAA==.',
Aj='Ajier:BAACLgAFFH8TAAIBAAYJgxZEDgBpAQABAAYJgxZEDgBpAQAuAAQKfy0AAgEACQkpFqMWACcCAAEACQkpFqMWACcCAAAA.',
Al='Aleraz:BAACLgAFFH8gAAMBAAYJ3xlIDQB2AQABAAUJkRpIDQB2AQACAAUJ1hTNCwAPAQAuAAQKf0IABAIACQmWIIkGAOkCAAIACQmWIIkGAOkCAAEABwnbIOEVAC0CAAMAAwkmBxZjAHAAAAAA.Allcapwne:BAAALgAECgcJDQAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdfIwCYAQAEAAcJ0BdfIwCYAQAAAA==.Alucart:BAAALgAECgEJAQAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECgkJIQAFAPMdAA==.Amonkle:BAAALgAFFAEJAQAAAA==.',
An='Anchoredowl:BAAALgAECgEJAgAAAA==.Anewrbyss:BAAALgAECgUJEwAAAA==.Angela:BAABLgAECn9QAAQDAAkJCSDGBgASAwADAAkJUx/GBgASAwABAAYJsBshAwDkAQACAAEJoww3iwAvAAAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJBAAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAACLgAFFH8QAAIGAAUJhhdsBABAAQAGAAUJhhdsBABAAQAuAAQKfzAAAgYACQmGIloBACEDAAYACQmGIloBACEDAAAA.Apocalýpsè:BAAALgAECgIJAgAAAA==.Applebottomj:BAAALgAECgMJAwAAAA==.Applebottum:BAAALgAECgkJEAAAAA==.Appärition:BAABLgAECn8zAAIHAAgJqCCbAgCKAgAHAAgJqCCbAgCKAgAAAA==.',
Ar='Arleance:BAAALgAECgUJCAAAAA==.Arondael:BAABLgAECn8iAAIGAAkJ8xjhBwDVAQAGAAkJ8xjhBwDVAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Ashelaandrii:BAAALgAFFAEJAgAAAA==.Astroglyde:BAAALgAECgcJCQAAAA==.Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn9BAAIIAAkJURufLQBjAgAIAAkJURufLQBjAgAAAA==.Avendeloria:BAABLgAECn8dAAIBAAkJiRTEHgDPAQABAAkJiRTEHgDPAQAAAA==.Averyn:BAAALgADCgEJAQAAAA==.',
Az='Azrahn:BAAALgADCgQJBQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECggJCQAJAAAAAA==.',
Ba='Babybear:BAAALgAECgIJAgAAAA==.Backmoist:BAAALgAECgQJBwAAAA==.Badru:BAAALgAECgMJAwAAAA==.Bagmaster:BAACLgAFFH8cAAIBAAUJNSGzCADEAQABAAUJNSGzCADEAQAuAAQKfzgAAgEACQkAJpkCAD4DAAEACQkAJpkCAD4DAAAA.Bahm:BAAALgADCgYJEwAAAA==.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Barthallomew:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Bartholomoo:BAABLgAECn9BAAIKAAkJvyIQEADsAgAKAAkJvyIQEADsAgAAAA==.Bayonetta:BAAALgAECgcJDQAAAA==.',
Be='Beeftornado:BAAALgAECgYJBwAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAwAAAA==.',
Bi='Bichstewy:BAAALgAECgEJAQAAAA==.Bigbusta:BAAALgADCgMJAwAAAA==.Bigdoofus:BAAALgAECgIJAgAAAA==.Bigmanblasto:BAAALgADCgMJBAAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAABLgAECn8UAAMLAAgJfQq7BQB7AAAMAAYJxgXkxwC4AAALAAcJxgq7BQB7AAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blackdracula:BAAALgAECgUJBgAAAA==.Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAABLgAECn8ZAAIMAAYJcwwdqADyAAAMAAYJcwwdqADyAAAAAA==.Blazeknight:BAACLgAFFH8KAAINAAMJIw/yEQB+AAANAAMJIw/yEQB+AAAuAAQKfy4AAw0ACQn9GV0WANYBAA0ACQn9GV0WANYBAA4AAQkAAGc8AAAAAAAA.Blazemaker:BAACLgAFFH8NAAIIAAQJVAXwPgCyAAAIAAQJVAXwPgCyAAAuAAQKfxoAAggABgk8EMTAAAgBAAgABgk8EMTAAAgBAAAA.Blazemaster:BAAALgAECgQJCQAAAA==.Blinduru:BAACLgAFFH8VAAIOAAQJNyLLKACHAQAOAAQJNyLLKACHAQAuAAQKfzkAAg4ACQltJcoCAFsDAA4ACQltJcoCAFsDAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAAOANkOAA==.Bloodsylf:BAAALgAECgkJBAABLgAECgcJFgAPAM4TAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgMJAwAAAA==.Bobcobb:BAAALgAECgQJBAAAAA==.Bonez:BAAALgAECgMJAwAAAA==.Boocakey:BAAALgADCgkJDwAAAA==.Book:BAABLgAECn8UAAIDAAkJHBV7EQBdAgADAAkJHBV7EQBdAgAAAA==.Bookie:BAAALgAECgcJCAAAAA==.Books:BAAALgAECgcJBwAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJCAAAAA==.',
Bp='Bpain:BAAALgAECgMJAwABLgAECgkJOQAQAFQcAA==.Bpaìn:BAABLgAECn85AAIQAAkJVByLAQAfAgAQAAkJVByLAQAfAgAAAA==.',
Br='Braski:BAAALgAECgEJAQAAAA==.Breandán:BAAALgADCgEJAQABLgAFFAgJIgARAOUcAA==.Brewlïth:BAAALgAECgIJAgABLgAFFAYJEQASAMceAA==.Brewmaester:BAAALgAECgEJAgAAAA==.Brewmooster:BAAALgADCgYJBgABLgAECgkJNQATALMZAA==.Brink:BAABLgAECn8bAAIIAAkJFxEEWwDNAQAIAAkJFxEEWwDNAQAAAA==.Broadside:BAAALgAECgQJBQAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Brolic:BAAALgAECgQJBgAAAA==.Brolymorph:BAAALgAECgcJCgAAAA==.Bromaster:BAAALgAECgQJBQAAAA==.Brones:BAAALgAFFAcJAQAAAA==.Brossiere:BAABLgAECn8hAAQUAAgJERuSNQB6AQAUAAUJZRqSNQB6AQAVAAYJoxdQjABYAQAWAAUJVRenIwD4AAAAAA==.Brotemic:BAABLgAFFH8GAAIRAAIJjhvUJgCgAAARAAIJjhvUJgCgAAAAAA==.Brovine:BAAALgAECgEJAQAAAA==.Bru:BAACLgAFFH8SAAIBAAYJEBcxDQB3AQABAAYJEBcxDQB3AQAuAAQKfyoAAgEACQl1HOwMAIYCAAEACQl1HOwMAIYCAAAA.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bt='Bt:BAAALgAECgcJDwAAAA==.',
Bu='Bubblegal:BAAALgAECgQJCQAAAA==.Bullsmcgee:BAABLgAECn88AAMKAAkJlyVqAwBpAwAKAAkJlyVqAwBpAwASAAEJAAAXQwA9AAAAAA==.Burningtree:BAABLgAECn8kAAIIAAkJiRD9ZgCvAQAIAAkJiRD9ZgCvAQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buthunter:BAAALgAECgEJAQAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bâ']='Bâdmammajama:BAAALgAECgEJAQAAAA==.',
['Bæ']='Bæyoncé:BAAALgAECgMJAwAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8aAAIFAAkJ3BNxOAC1AQAFAAkJ3BNxOAC1AQAAAA==.Captcorndog:BAACLgAFFH8GAAMQAAMJ2wq3SQClAAAQAAMJ2wq3SQClAAAXAAEJ2QLqGAAlAAAuAAQKfygABBAACAlAFcAjAL4BABAACAlAFcAjAL4BABcABQnzA3k4AKcAABgAAQkAALRAAC8AAAAA.Carlundalen:BAAALgADCgEJAQAAAA==.Caskket:BAABLgAECn8fAAISAAkJ2R2cAQBYAgASAAkJ2R2cAQBYAgAAAA==.Castreytid:BAAALgAECgcJDQABLgAFFAQJBQAZAHoHAA==.Catdog:BAABLgAECn8mAAIaAAYJFRiyIwAzAQAaAAYJFRiyIwAzAQAAAA==.Catechism:BAABLgAECn8yAAMUAAkJ2h/6BgAcAwAUAAkJ2h/6BgAcAwAVAAYJnwjc3wDeAAAAAA==.',
Ce='Cellistle:BAAALgAECgkJEgAAAA==.Cemeo:BAABLgAECn8UAAIXAAcJiBcTFgDsAQAXAAcJiBcTFgDsAQAAAA==.Cerberusalfa:BAACLgAFFH8ZAAINAAYJTCVYBQC6AQANAAYJTCVYBQC6AQAuAAQKfzgAAg0ACQkTJkQBAGsDAA0ACQkTJkQBAGsDAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAFFAQJBQAZAHoHAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAACLgAFFH8RAAIIAAQJ5hQNJQApAQAIAAQJ5hQNJQApAQAuAAQKfyoAAggACAmsHVkrAGwCAAgACAmsHVkrAGwCAAAA.Chinchilla:BAAALgAECgEJAQAAAA==.Chiphoof:BAABLgAECn8tAAMbAAkJvRntCAA6AgAbAAkJvRntCAA6AgAaAAEJuQylHwAoAAAAAA==.Chocofox:BAABLgAECn8iAAMRAAkJmSFuBQBcAwARAAkJmSFuBQBcAwAcAAEJ0AOFRwAhAAAAAA==.Chokemagic:BAABLgAFFH8GAAITAAIJbA6BnwCLAAATAAIJbA6BnwCLAAAAAA==.Chopndot:BAAALgAECgQJCAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAABLgAECn8cAAIOAAYJchfxbABKAQAOAAYJchfxbABKAQAAAA==.',
Cl='Clankss:BAABLgAECn8cAAIOAAkJ7wfgDwDnAAAOAAkJ7wfgDwDnAAAAAA==.Claraabun:BAAALgAECgUJBQABLgAFFAYJFgAUAMYTAA==.Clarabuns:BAACLgAFFH8WAAIUAAYJxhNKEQCsAQAUAAYJxhNKEQCsAQAuAAQKfx8AAxQACQnGF2YlAPsBABQACQnGF2YlAPsBABUABQl1F/l+AHEBAAAA.Clarasbuns:BAAALgAECgMJAwABLgAFFAYJFgAUAMYTAA==.Clawdragoon:BAECLgAFFH8gAAQdAAYJnA+3JgD5AAAdAAYJnA+3JgD5AAAFAAQJhAFISwCPAAAaAAEJUgdBMQAgAAAuAAQKfzAAAx0ACAnVGW0UAG8CAB0ACAnVGW0UAG8CAAUABQlACN+bAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Coldorc:BAAALgADCgEJAQAAAA==.Colforbin:BAAALgADCgUJBQAAAA==.Colosie:BAAALgAECgYJEwABLgAFFAEJAQAJAAAAAA==.Comegetpsalm:BAABLgAECn89AAIUAAkJJRrpEQCEAgAUAAkJJRrpEQCEAgAAAA==.Cornbreadmat:BAAALgADCgcJDQAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8iAAIRAAgJ5RymBgBcAgARAAgJ5RymBgBcAgAuAAQKfzsAAxEACQk5HE0cAGoCABEACQk5HE0cAGoCAB4AAwlXE3BjALUAAAAA.Creatlachlol:BAAALgAECgkJCQABLgAFFAgJIgARAOUcAA==.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgAECgEJAQAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMeAAkJggwPNABrAQAeAAkJggwPNABrAQARAAUJrREiXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cyraxx:BAAALgADCgMJAwAAAA==.Cyrusdragon:BAAALgAECgYJBgAAAA==.Cyrussham:BAAALgAECgEJAQAAAA==.Cytherea:BAACLgAFFH8JAAIVAAMJ+gOOSwBrAAAVAAMJ+gOOSwBrAAAuAAQKfy0AAhUACAkiENiDAGgBABUACAkiENiDAGgBAAAA.',
Da='Daddybod:BAABLgAECn8gAAIfAAkJjRJzHgCyAQAfAAkJjRJzHgCyAQAAAA==.Dainnan:BAAALgADCgEJAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Danicarkel:BAABLgAECn8XAAIgAAkJLRsLAQD0AQAgAAkJLRsLAQD0AQAAAA==.Darkcallum:BAAALgAECgUJDgAAAA==.Darktaynt:BAAALgAECgMJBgAAAA==.Darthfox:BAAALgAECgMJBQAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathsyn:BAABLgAFFH8JAAIKAAQJzRk+VwBEAQAKAAQJzRk+VwBEAQAAAA==.Deathtracker:BAABLgAECn8gAAIMAAgJ7g90YgCBAQAMAAgJ7g90YgCBAQAAAA==.Deathwarden:BAAALgAECggJEwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJDgABLgAFFAEJAQAJAAAAAA==.Delimeatear:BAAALgAECgIJAgABLgAECgkJHQACABkcAA==.Demiloss:BAAALgAFFAEJAQABLgAFFAQJDgAVAHwcAA==.Demise:BAACLgAFFH8QAAIIAAgJ1BsYBgCcAgAIAAgJ1BsYBgCcAgAuAAQKfzIAAggACAnmHpQJAJgBAAgACAnmHpQJAJgBAAAA.Demolish:BAAALgAECgEJAQAAAA==.Demonclem:BAAALgAFFAIJAgAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAACLgAFFH8FAAINAAMJPQpBHQC4AAANAAMJPQpBHQC4AAAuAAQKfzsAAw0ACQnkGZQNAEwCAA0ACQnkGZQNAEwCAA4ABgmnC5WIABQBAAAA.Destructin:BAAALgAECgEJAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAFFAMJAwABLgAFFAUJEwADAOgQAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinoknight:BAAALgAECgcJBwAAAA==.Dinopriest:BAABLgAECn8XAAICAAcJLRcFJgCcAQACAAcJLRcFJgCcAQAAAA==.Dista:BAAALgAECgUJCwAAAA==.Distia:BAAALgAECgcJCgAAAA==.Divinedragon:BAABLgAECn8uAAMCAAkJGhihEgA+AgACAAkJGhihEgA+AgADAAcJ5QvnLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgAECgYJCwAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Draggo:BAAALgAECgEJAwAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn9NAAIVAAkJ4CEADQD9AgAVAAkJ4CEADQD9AgAAAA==.Dreya:BAABLgAECn8aAAIcAAkJDR3ZCQAfAgAcAAkJDR3ZCQAfAgAAAA==.Dreyas:BAAALgADCgYJBgAAAA==.Drinkcoolaid:BAACLgAFFH8LAAIRAAQJnBPfFwD2AAARAAQJnBPfFwD2AAAuAAQKfx8AAhEACQmfFrMgAEsCABEACQmfFrMgAEsCAAAA.Drinkoolaide:BAAALgAECggJCAABLgAFFAQJCwARAJwTAA==.Dritzle:BAABLgAECn8aAAMhAAgJBhXKIQDrAQAhAAgJBhXKIQDrAQAGAAQJHgi5EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dude:BAABLgAECn8aAAMiAAkJCApXAwD6AAAiAAYJ7g1XAwD6AAAOAAkJ1gInIQBkAAAAAA==.Durrt:BAAALgADCgcJCAABLgAECgcJLAAFAGsiAA==.Dutchman:BAACLgAFFH8WAAIMAAcJEyLrCwANAgAMAAcJEyLrCwANAgAuAAQKfxwAAgwACAkNIWYIAAsDAAwACAkNIWYIAAsDAAAA.',
['Dë']='Dëçäÿ:BAAALgAECgMJBAABLgAECgcJIQAFAMobAA==.',
Eh='Ehhmuh:BAAALgAECgYJCgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRvDgBvAgAEAAYJRSRvDgBvAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn82AAMIAAkJYh6lGgC6AgAIAAkJYh6lGgC6AgAjAAEJ7hOWHAA6AAAAAA==.Elethil:BAAALgADCgEJAgAAAA==.Elfstomper:BAAALgADCggJCwAAAA==.Elitepaladin:BAABLgAECn8nAAIUAAkJGBbfIQAPAgAUAAkJGBbfIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elrai:BAAALgAECgIJAwAAAA==.Elyseia:BAABLgAECn8gAAIMAAkJgwbtiQArAQAMAAkJgwbtiQArAQAAAA==.',
Em='Emeritus:BAAALgAECgkJBwAAAA==.Empkin:BAAALgAECgcJEwAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgAECggJCwABLgAFFAQJFgAkAO8TAA==.',
Ep='Epicsause:BAABLgAFFH8JAAIaAAMJ9g6uDwCcAAAaAAMJ9g6uDwCcAAAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAECLgAFFH8OAAISAAYJ2xLMGQAYAQASAAYJ2xLMGQAYAQAuAAQKfy4ABBIACQlOGj0KAHYCABIACQlOGj0KAHYCACUABgnBEHUcAOoAAAoAAQkAAMiuAQAAAAAA.Españaluna:BAEALgAECgcJBgABLgAFFAYJDgASANsSAA==.Españamor:BAEALgAECgkJCAABLgAFFAYJDgASANsSAA==.Essdeath:BAAALgAECgEJAQABLgAECgkJIAAfAI0SAA==.',
Ex='Excrucio:BAAALgADCgYJBgAAAA==.',
Ez='Ezpain:BAAALgAECgQJBQAAAA==.',
Fa='Fantastick:BAAALgAECgEJAQAAAA==.Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgQJCAABLgAFFAQJDQAVAIQaAA==.Fatalmann:BAACLgAFFH8MAAMXAAUJYwjLHgC4AAAXAAQJvQLLHgC4AAAYAAMJPwVhCwBpAAAuAAQKfxYAAxgACQnMD5kVAJUBABgABwmoD5kVAJUBABcABgk2DyQcAB0BAAAA.Fatalminn:BAAALgAECgYJDgAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgAFFAEJAQABLgAFFAgJIgARAOUcAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flinwazzart:BAAALgAECgUJBQAAAA==.Flutterby:BAAALgAECgIJAwABLgAECgkJQQACABoKAA==.Flèxion:BAACLgAFFH8OAAIKAAUJ2R9dSgBeAQAKAAUJ2R9dSgBeAQAuAAQKfygAAgoACAkBJc8gAIUCAAoACAkBJc8gAIUCAAAA.',
Fo='Foskin:BAAALgAECgMJBAABLgAFFAQJBQAZAHoHAA==.',
Fr='Frak:BAAALgAECgYJBgAAAA==.Frankymermai:BAAALgADCgYJBgAAAA==.Frassk:BAABLgAECn9FAAMHAAkJiBs6BgABAgAHAAcJrh06BgABAgATAAQJ0hIV0QCyAAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Frigid:BAAALgAECgkJBwAAAA==.Frik:BAAALgAECgEJAQAAAA==.Froggystyle:BAAALgAECgYJDgABLgAECggJDgAJAAAAAA==.Frostydru:BAABLgAECn8wAAIbAAgJfiH5BwBTAgAbAAgJfiH5BwBTAgAAAA==.Frozat:BAACLgAFFH8bAAIXAAgJGxhfBACZAgAXAAgJGxhfBACZAgAuAAQKfygAAxcACAkRI2oEAOYCABcACAkRI2oEAOYCABAAAQmAEZ5eAEAAAAAA.Fruk:BAAALgAECgUJBQAAAA==.Frösting:BAAALgADCgcJDgABLgAECgkJTgAOAIkfAA==.',
Fu='Fullblooded:BAAALgAECgEJAQAAAA==.Fundeedo:BAAALgAFFAIJAwAAAA==.Furballieo:BAAALgADCgIJAgAAAA==.Furfoxxsakes:BAAALgAECgQJBAAAAA==.',
Ga='Galadriels:BAAALgAECgQJBAAAAA==.Galianem:BAAALgADCgMJAwAAAA==.Galled:BAAALgAECgEJAQAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJCAAAAA==.Garbarn:BAABLgAECn8WAAIVAAkJ0w9yfgBxAQAVAAkJ0w9yfgBxAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminiholy:BAAALgADCgcJBwABLgAFFAQJFgAkAO8TAA==.Geminirunes:BAAALgADCgYJBgABLgAFFAQJFgAkAO8TAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJBgAAAA==.',
Gi='Gia:BAABLgAECn89AAIEAAgJFR4aBQDUAQAEAAgJFR4aBQDUAQAAAA==.',
Gl='Glitches:BAAALgADCgMJAwAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAABLgAECn8tAAIZAAkJlQjJOwBXAQAZAAkJlQjJOwBXAQAAAA==.Goodlocktime:BAAALgADCgIJAgABLgAECgYJCAAJAAAAAA==.Goodtimesm:BAAALgAECgYJCAAAAA==.Goodtymes:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Gorearrow:BAACLgAFFH8RAAIMAAYJHRmXNwA+AQAMAAYJHRmXNwA+AQAuAAQKfzAAAwwACQlXItgLAOMCAAwACQlXItgLAOMCAAsAAglWB2N6AFkAAAAA.Goretaint:BAAALgAECgYJDwAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gorribal:BAAALgADCgcJCQAAAA==.Gothladriel:BAAALgAECgYJDAAAAA==.Gotpwnedd:BAAALgAECgEJAQAAAA==.Gottamoo:BAACLgAFFH8GAAIaAAMJmhOWFAB1AAAaAAMJmhOWFAB1AAAuAAQKfxkAAxoACQknDMApAA4BABoACQknDMApAA4BAB0AAQk9AVaQABoAAAAA.',
Gr='Greenstank:BAAALgAECggJDgAAAA==.Greygg:BAAALgAECgEJAQAAAA==.Grrumpybear:BAABLgAECn9GAAIaAAkJLBxTBwCBAgAaAAkJLBxTBwCBAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.Grís:BAAALgAECgMJAwAAAA==.',
Gu='Gumbuz:BAAALgAECgQJBgAAAA==.Gunafistya:BAABLgAFFH8NAAIEAAMJYhboOQC+AAAEAAMJYhboOQC+AAAAAA==.Gunnaroptiks:BAAALgAECgUJBQABLgAFFAUJGQAfAIsXAA==.Guzzler:BAAALgAECgkJDgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAgAAAA==.Hajin:BAAALgAECgYJDwAAAA==.Hankjr:BAAALgAECgEJAwAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Harrier:BAAALgADCgEJAQABLgAECgkJLQAbAL0ZAA==.Havòk:BAAALgAECggJBwABLgAFFAEJAQAJAAAAAA==.Hawthorn:BAAALgAECgMJCAAAAA==.Hazyblades:BAAALgAECgMJAwAAAA==.',
He='Hektar:BAAALgADCgYJBgAAAA==.Helacookie:BAABLgAECn8ZAAIVAAkJMBNSVADNAQAVAAkJMBNSVADNAQAAAA==.Henso:BAAALgAFFAEJAQABLgAFFAQJFgAkAO8TAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJEAAAAA==.',
Hi='Hiawatha:BAAALgADCgEJAQABLgAECgcJBwAJAAAAAA==.Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgAECgEJAQABLgAECgkJFwAKADQcAA==.Hitstabkill:BAAALgAECgEJAQAAAA==.Hiver:BAAALgAECgQJBgAAAA==.',
Ho='Hoegar:BAAALgAFFAIJAgABLgAFFAMJCgALALkeAA==.Holes:BAAALgAECgEJAwAAAA==.Holier:BAACLgAFFH8PAAIVAAQJYQ5nJgDdAAAVAAQJYQ5nJgDdAAAuAAQKfzkAAhUACQn+FXRGAPMBABUACQn+FXRGAPMBAAAA.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgkJEQABLgAFFAgJLAATALYcAA==.Hoochurcooch:BAAALgAECgEJAQAAAA==.Hoppers:BAAALgAECgIJAgABLgAECgcJDwAJAAAAAA==.Hopperstotem:BAAALgAECgcJDwAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgcJDwAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAgJKAAdAEQVAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.Hush:BAABLgAECn8tAAMZAAkJWx3rEQBlAgAZAAkJWx3rEQBlAgAmAAEJPQmlggAnAAABLgAECgkJLQAZAFsdAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.Icys:BAAALgAECgEJAgAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
If='Ifirt:BAAALgAECgkJEgAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCgAAAA==.Invisabull:BAAALgAECgQJBgAAAA==.Invysion:BAACLgAFFH8WAAIDAAYJYgj1DQBBAQADAAYJYgj1DQBBAQAuAAQKfy4AAgMACQkXEf8dAN4BAAMACQkXEf8dAN4BAAAA.',
Ir='Ironballz:BAAALgAECgMJAwAAAA==.Irri:BAAALgADCgUJBQAAAA==.',
Is='Ishara:BAAALgAECggJCAABLgAECgkJNgAIAGIeAA==.',
Ja='Jacuzzi:BAAALgAECggJEAAAAA==.Jaidess:BAAALgAECgEJAQAAAA==.',
Je='Jeangen:BAAALgAECgUJBAAAAA==.Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8NAAIMAAQJnhuwQgAoAQAMAAQJnhuwQgAoAQAuAAQKfycAAgwACAlAJVMEAEoDAAwACAlAJVMEAEoDAAAA.Jellybea:BAACLgAFFH8SAAIBAAYJUBwoDACIAQABAAYJUBwoDACIAQAuAAQKfywAAwEACQltITEEABIDAAEACQltITEEABIDAAIAAgkJDA1xAGAAAAAA.Jemmoro:BAAALgADCgEJAQAAAA==.Jesstter:BAAALgAECgUJBQAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgcJDQABLgAECgkJLQAZAFsdAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEQAAAA==.Jump:BAAALgAECgcJEwAAAA==.Junglebrew:BAAALgAECgEJAwAAAA==.Jurisdiction:BAABLgAECn8uAAIVAAkJWRLESQDpAQAVAAkJWRLESQDpAQAAAA==.',
Jz='Jz:BAAALgAECgMJBAAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8sAAIFAAcJayJLEwCbAgAFAAcJayJLEwCbAgAAAA==.Kabea:BAAALgAECgEJAgAAAA==.Kadath:BAAALgAECgIJAgAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahanie:BAAALgADCgcJBwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJDwAJAAAAAA==.Kakutogi:BAAALgADCgEJAQAAAA==.Kalycia:BAAALgAECgEJAgAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Kanalz:BAAALgAECgQJBAAAAA==.Karael:BAAALgAECgUJEQABLgAFFAMJBwARAKkWAA==.Karma:BAABLgAECn8bAAIhAAcJggPBQADCAAAhAAcJggPBQADCAAAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keei:BAAALgADCgQJBQAAAA==.Keho:BAABLgAECn9BAAMfAAkJ0QtGAwBGAQAfAAkJ0QtGAwBGAQAkAAIJkg6maABqAAAAAA==.Keihoe:BAAALgAECgMJAwABLgAECgkJQQAfANELAA==.Kenalia:BAABLgAECn8qAAIEAAkJlRbSGgBCAgAEAAkJlRbSGgBCAgAAAA==.Kengo:BAAALgAECgEJAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAFFAIJAwABLgAFFAUJEwACABESAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.Khromn:BAAALgAECgkJAgABLgAFFAIJAgAJAAAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIVAAgJNiBdIgCgAgAVAAgJNiBdIgCgAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Kilgreed:BAAALgAECggJCgAAAA==.Killaban:BAACLgAFFH8KAAIZAAQJ9BcEHwA1AQAZAAQJ9BcEHwA1AQAuAAQKfzIAAxkACQklINwXAC8CABkACQngH9wXAC8CACYAAwkZGVMrAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAACLgAFFH8NAAIVAAQJhBoYFwAmAQAVAAQJhBoYFwAmAQAuAAQKfzcAAxUACQnxJL4EAFMDABUACQnxJL4EAFMDABQABAn0CmVjAKgAAAAA.Kissmydots:BAABLgAECn9EAAITAAkJKR5+FwCXAgATAAkJKR5+FwCXAgAAAA==.Kitja:BAABLgAECn9tAAQDAAkJ7SJuAACNAwADAAkJ7SJuAACNAwABAAgJaBw3EQBZAgACAAEJNBBcHwAyAAAAAA==.Kitla:BAAALgADCgUJBQABLgAECgkJbQADAO0iAA==.',
Kl='Klipsch:BAAALgAECgEJAQAAAA==.Klukai:BAAALgADCgcJCwABLgAECgkJIQAFAPMdAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAgJKAAdAEQVAA==.Kohman:BAABLgAECn8bAAITAAYJ3RXOfABiAQATAAYJ3RXOfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kp='Kpop:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8mAAINAAkJByNbAAAhAwANAAkJByNbAAAhAwAuAAQKfysAAw0ACQnQJDcEADcDAA0ACQnQJDcEADcDAA4AAQkAAOpIAQAAAAAA.Kronas:BAABLgAECn8VAAIMAAgJ3RWyYgCAAQAMAAgJ3RWyYgCAAQAAAA==.Kronophyne:BAACLgAFFH8OAAIIAAUJZhHsKQAPAQAIAAUJZhHsKQAPAQAuAAQKfzkAAggACQnZHiA0AEgCAAgACQnZHiA0AEgCAAAA.Kronopop:BAAALgAECgcJDQAAAA==.Kronotality:BAACLgAFFH8OAAMSAAMJnRtgFQCVAAAKAAMJXQuirADHAAASAAMJnRtgFQCVAAAuAAQKf0oAAhIACQkZJWMCACoDABIACQkZJWMCACoDAAAA.Kronotek:BAAALgAECgcJDQAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.Kronotide:BAAALgAFFAIJAgAAAA==.',
Ku='Kungfoosauce:BAAALgAFFAEJAQAAAA==.Kungfukittn:BAAALgAECgUJCgAAAA==.Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJEgAAAA==.Kynbrochel:BAAALgAECgYJEgAAAA==.',
La='Laars:BAAALgAECgUJDAABLgAECggJJQATADsNAA==.Laimaster:BAAALgAECgEJAwAAAA==.Laizie:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn9JAAIcAAkJiBsZBgB6AgAcAAkJiBsZBgB6AgAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lanney:BAAALgAECgYJBgAAAA==.Lapsu:BAABLgAECn8fAAIkAAkJjRQBHQDGAQAkAAkJjRQBHQDGAQAAAA==.Lascivia:BAACLgAFFH8UAAMZAAYJrxveFABlAQAZAAYJrxveFABlAQAnAAQJQBLIFwDcAAAuAAQKfyYAAxkACQkAH1AmACcCABkACQmIHFAmACcCACcACAnlEJ4eAD8BAAAA.Lawhanx:BAAALgADCgEJAQABLgAFFAQJDgAVAHwcAA==.Laylahh:BAAALgAECgQJBQAAAA==.Lazy:BAABLgAECn8WAAMTAAYJyRcpiQBHAQATAAUJyRcpiQBHAQAHAAIJxQGEYQBLAAAAAA==.',
Le='Leademon:BAABLgAECn9BAAMOAAkJ6SBAEQC4AgAOAAkJ6SBAEQC4AgANAAIJTRrWWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECgkJQQAOAOkgAA==.Leadmln:BAAALgADCgcJBwABLgAECgkJQQAOAOkgAA==.Leftlane:BAABLgAECn8uAAMRAAkJsiE7BgBMAwARAAkJsiE7BgBMAwAeAAEJgA2LqgAsAAAAAA==.Legato:BAAALgAECgkJCgABLgAFFAgJIAARANgeAA==.Lehsham:BAAALgAECgkJAgAAAA==.Lekiri:BAAALgAECgYJCgAAAA==.Lep:BAAALgAFFAQJBAABLgAFFAgJGwAXABsYAA==.Lethalkrits:BAAALgAECgkJAgAAAA==.Leva:BAABLgAECn8hAAIFAAkJ8x3JGAB/AgAFAAkJ8x3JGAB/AgAAAA==.',
Li='Liberté:BAAALgAECgYJEQAAAA==.Liciano:BAABLgAECn8aAAMoAAkJdRygAgCRAgAoAAkJSRugAgCRAgAhAAcJPBxrGwC8AQABLgAFFAMJBwARAKkWAA==.Licious:BAAALgAECgEJAQABLgAECgcJBwAJAAAAAA==.Lie:BAACLgAFFH8HAAIhAAIJTgvYNACOAAAhAAIJTgvYNACOAAAuAAQKfzsAAiEACQkNGUQNAFICACEACQkNGUQNAFICAAAA.Lief:BAAALgAECgEJAQAAAA==.Lightsdown:BAAALgAECgYJBgAAAA==.Lilbeebs:BAAALgAECgkJEQAAAA==.Lileth:BAAALgAECgkJBAAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAABLgAECn8cAAIHAAkJEgxNDgBXAQAHAAkJEgxNDgBXAQAAAA==.Lilïth:BAACLgAFFH8RAAISAAYJxx7GEQBtAQASAAYJxx7GEQBtAQAuAAQKfyAAAhIABwmDJPIGAMICABIABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJBAABLgAFFAYJIAABAN8ZAA==.Lisalisa:BAABLgAECn89AAIRAAkJwxfGIQBEAgARAAkJwxfGIQBEAgAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lotioned:BAAALgADCgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lukethywalkr:BAAALgADCgYJBgAAAA==.Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Luminari:BAAALgADCgEJAQABLgAECgkJNgAIAGIeAA==.Lunaa:BAAALgAECgkJDAAAAA==.Lurassa:BAAALgAECgYJDAABLgAECggJDwAJAAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAFFAMJBQAVAIwGAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAABLgAECn8mAAIYAAYJBRI3DwAXAQAYAAYJBRI3DwAXAQAAAA==.Maellus:BAAALgAECgEJAQAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magickdragon:BAAALgAECgYJBwABLgAECgkJLgACABoYAA==.Magicmoo:BAAALgAECgEJAQABLgAFFAQJDQAVAIQaAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAACLgAFFH8FAAIdAAMJqQRnOgCPAAAdAAMJqQRnOgCPAAAuAAQKf0QAAh0ACQmIEZEfAMsBAB0ACQmIEZEfAMsBAAAA.Manaproblems:BAAALgADCgMJBAAAAA==.Mandemic:BAAALgAECgYJCQABLgAFFAYJGAAZAE0WAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECggJDwAAAA==.Marisatomei:BAAALgAECgYJCQAAAA==.Markamanimal:BAACLgAFFH8PAAIbAAQJjBpbBgBIAQAbAAQJjBpbBgBIAQAuAAQKfyUAAhsACAnfIYYDAPwCABsACAnfIYYDAPwCAAAA.Marnix:BAABLgAECn8bAAIeAAgJmRIwLwCEAQAeAAgJmRIwLwCEAQAAAA==.Marshail:BAAALgAECgEJAQAAAA==.',
Md='Mdbeef:BAAALgAECgUJBQAAAA==.',
Me='Medikus:BAABLgAECn8qAAMRAAgJWh43BgDAAQARAAgJWh43BgDAAQAeAAMJGQ4oegCAAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Megajoo:BAACLgAFFH8KAAMdAAIJuQzZPwB1AAAdAAIJuQzZPwB1AAAFAAIJZgQ1aQBJAAAuAAQKfxUAAx0ACAnYFRIeANgBAB0ACAnYFRIeANgBAAUABgnlBwh7AMYAAAAA.Menil:BAABLgAECn8XAAMEAAgJwBtXFgAQAgAEAAcJJhpXFgAQAgAkAAQJchYeUQDDAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.Meyounow:BAAALgAECgEJBQAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAECLgAFFH8GAAMpAAQJqhGfBACdAAApAAIJzBmfBACdAAAIAAIJiAllpQCGAAAuAAQKfzoAAykACQmDJK0AAP0CACkACQlAIq0AAP0CAAgACAlkIFdWANoBAAAA.Mips:BAAALgAFFAMJBAABLgAFFAgJEAAIANQbAA==.Missluana:BAAALgADCgIJAgAAAA==.Mitzii:BAAALgADCgMJAwABLgAFFAIJAgAJAAAAAA==.',
Mk='Mk:BAEALgADCgcJBwABLgAECgkJTQAkAIoiAA==.',
Mo='Mob:BAAALgADCgcJBwAAAA==.Mockra:BAABLgAECn8+AAMIAAkJViIgFADhAgAIAAkJViIgFADhAgAjAAIJuBiqGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAABLgAECn8tAAIVAAkJ7h9GAgDnAgAVAAkJ7h9GAgDnAgAAAA==.Moolou:BAACLgAFFH8UAAIWAAYJ0BfrBAA+AQAWAAYJ0BfrBAA+AQAuAAQKfyMAAhYACQm1H1AGAIICABYACQm1H1AGAIICAAAA.Moonraka:BAAALgADCgUJBQAAAA==.Moosé:BAAALgAECgEJAQABLgAFFAkJNgAVABccAA==.Mootilater:BAAALgADCgQJAQAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECgkJPAAKAJclAA==.Morechie:BAABLgAECn8nAAIgAAkJARjTBwDwAQAgAAkJARjTBwDwAQAAAA==.Morecowbell:BAAALgAECgEJAQAAAA==.Morgatho:BAAALgADCgEJAwAAAA==.Morsz:BAAALgAECgEJAQABLgAECgYJCAAJAAAAAA==.Mortiferon:BAABLgAECn83AAIKAAkJCh8TFgDDAgAKAAkJCh8TFgDDAgAAAA==.',
Mu='Muhgunguh:BAAALgAECgEJAQAAAA==.Munnky:BAABLgAECn9JAAIEAAgJFyXiAAA/AwAEAAgJFyXiAAA/AwAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgAECgEJAQAAAA==.Mytu:BAAALgADCgUJBgAAAA==.',
['Má']='Mánflu:BAACLgAFFH8YAAMZAAYJTRYpGABTAQAZAAUJERspGABTAQAmAAEJOgOIIQAtAAAuAAQKfysAAyYACQniHhIDAOICACYACQniHhIDAOICABkABwlJGlI0ANkBAAAA.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgQJCwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgAECgUJCgABLgAFFAYJFwARAKMXAA==.Narn:BAABLgAECn9DAAQQAAkJOBybFAA3AgAYAAcJrRjRCQBCAgAQAAkJ5RibFAA3AgAXAAIJLQiEQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrophyllis:BAAALgAECgMJAwAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nei:BAAALgAECgEJAQABLgAECgkJIAAfAI0SAA==.Nerrisa:BAABLgAECn8iAAICAAkJERQtIgC2AQACAAkJERQtIgC2AQAAAA==.Nertmage:BAAALgADCgUJBQABLgAECgkJQwAXADEZAA==.Nertt:BAAALgADCgYJBgABLgAECgkJQwAXADEZAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECggJEgAAAA==.Nimrods:BAAALgAECgQJBAAAAA==.',
No='Noblewarrior:BAACLgAFFH8iAAIZAAgJOhtDAwBVAgAZAAgJOhtDAwBVAgAuAAQKfysAAhkACAmuJHYNAJcCABkACAmuJHYNAJcCAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nohkari:BAAALgADCgkJHQABLgAECgkJKgATAPAXAA==.Nooj:BAACLgAFFH9FAAMGAAkJBSImAADoAgAGAAkJBSImAADoAgAhAAYJiRRDFABqAQAuAAQKfx4AAwYACQl7ITsAAMMDAAYACQl7ITsAAMMDACEABgmFEpA6AEQBAAAA.Notakoala:BAACLgAFFH8oAAIdAAgJRBUGDQDMAQAdAAgJRBUGDQDMAQAuAAQKfycAAx0ACAlHJFQNAMUCAB0ACAlHJFQNAMUCABoAAQk3EjJzADQAAAAA.Nothnx:BAAALgAFFAEJAwAAAA==.Notoriouspat:BAABLgAECn8jAAIMAAgJFA/+YACFAQAMAAgJFA/+YACFAQAAAA==.Notsamadeath:BAABLgAFFH8LAAQlAAUJWRFdDwAeAQAlAAQJWRFdDwAeAQAKAAIJ3wi26wB+AAASAAEJAAB0TwAAAAAAAA==.Notsifra:BAAALgAFFAIJAgABLgAFFAQJDAAEAJglAA==.Novia:BAAALgAECgYJBwAAAA==.Noyber:BAAALgAFFAMJAwAAAA==.Noydin:BAAALgAFFAIJAwAAAA==.Noythrax:BAABLgAFFH8FAAIOAAMJTQKoPQBiAAAOAAMJTQKoPQBiAAAAAA==.',
['Ní']='Nínebreaker:BAAALgAECgkJEQAAAA==.',
['Nü']='Nüll:BAABLgAECn8UAAIOAAgJ2AsBdwAzAQAOAAgJ2AsBdwAzAQAAAA==.',
Ob='Obern:BAABLgAECn8WAAIPAAkJZhsgFgDxAQAPAAkJZhsgFgDxAQAAAA==.Obiron:BAAALgAECgEJAQAAAA==.Oblïna:BAABLgAECn88AAIEAAkJrQ3ACAB4AQAEAAkJrQ3ACAB4AQAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJCAAAAA==.Oftheages:BAAALgAFFAEJAQABLgAFFAgJGwAXABsYAA==.',
Ol='Olayro:BAAALgADCgQJBAAAAA==.',
Om='Omnicarkel:BAAALgAECgUJBQAAAA==.',
On='Onetozerosix:BAABLgAECn8jAAIKAAkJHhyQPQAMAgAKAAkJHhyQPQAMAgAAAA==.Onos:BAAALgAECgEJAQAAAA==.Onsen:BAAALgAECgQJBgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgAECgEJAgAAAA==.Operation:BAAALgAECgQJCAAAAA==.Oprahwndfury:BAAALgADCgIJAgAAAA==.',
Or='Oresties:BAAALgAECgYJCQAAAA==.Orestisies:BAAALgAECgcJCQAAAA==.Orghrax:BAAALgADCgEJAQAAAA==.Orisys:BAAALgAECgIJAwAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Padfoote:BAAALgAECgEJAQAAAA==.Pahaa:BAAALgAECgUJBQAAAA==.Painkiller:BAABLgAECn8UAAIMAAcJZxWLCgCWAQAMAAcJZxWLCgCWAQAAAA==.Pairadeez:BAAALgAECgYJDwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAABLgAFFH8HAAIkAAMJagqMEACUAAAkAAMJagqMEACUAAAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8yAAIMAAkJlg43RwDMAQAMAAkJlg43RwDMAQAAAA==.Parakka:BAABLgAECn82AAIRAAkJGhZ8IQBGAgARAAkJGhZ8IQBGAgAAAA==.Patak:BAAALgAECgMJAwAAAA==.Pavle:BAAALgAECgMJAwAAAA==.Pawp:BAAALgAECgYJCgABLgAFFAQJBgABAHoHAA==.',
Pe='Pearagon:BAABLgAECn8VAAICAAgJwBEJJwCVAQACAAgJwBEJJwCVAQABLgAFFAYJFwARAKMXAA==.Pepsidew:BAAALgADCgcJDAAAAA==.Pepsisprite:BAABLgAECn86AAIBAAkJdhqqDACcAgABAAkJdhqqDACcAgAAAA==.Pesky:BAABLgAECn8jAAIdAAYJJBazNQBAAQAdAAYJJBazNQBAAQABLgAFFAQJEQAIAOYUAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAABLgAFFH8IAAIaAAMJ1RVkHwCgAAAaAAMJ1RVkHwCgAAABLgAFFAYJEQASAMceAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwKIQDvAgAIAAkJQRwKIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn9DAAIKAAkJHiMYCgAeAwAKAAkJHiMYCgAeAwAAAA==.Pissflizzle:BAABLgAECn8dAAITAAgJ9w0kagBoAQATAAgJ9w0kagBoAQAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8pAAIIAAgJuAwChgBrAQAIAAgJuAwChgBrAQAAAA==.Portwings:BAAALgADCgYJBgAAAA==.',
Pr='Praye:BAAALgAFFAMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.Professahoak:BAAALgAECgUJBQABLgAECgkJPgAIAFYiAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgYJCAABLgAECggJIQABABkfAA==.Psyrax:BAAALgAECgIJAgAAAA==.',
Pu='Pushemover:BAAALgAECgMJBgAAAA==.',
Qu='Quelyndlina:BAAALgAECgEJAQAAAA==.Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8ZAAMUAAYJKxjcNgBzAQAUAAYJKxjcNgBzAQAVAAEJlQY0sgEpAAAAAA==.Ragerade:BAAALgAECggJDwAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJDQAAAA==.Raphåel:BAAALgAFFAEJAQAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAABLgAFFH8FAAMHAAQJWAGhFwByAAAHAAQJoAChFwByAAAgAAEJDAN8FgA6AAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgcJEgAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECggJDQABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn85AAIIAAgJOyQVHACzAgAIAAgJOyQVHACzAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAFFAMJAwAAAA==.Rickheaddk:BAAALgADCgEJAgAAAA==.Riivan:BAABLgAECn83AAITAAkJJBeIAwAcAgATAAkJJBeIAwAcAgAAAA==.Rini:BAAALgAECgkJEQABLgABCgYJCwAJAAAAAA==.Rivian:BAAALgADCgIJAgABLgAECgEJAgAJAAAAAA==.',
Ro='Robot:BAABLgAECn8oAAIEAAgJUBGqPQB5AQAEAAgJUBGqPQB5AQAAAA==.Roguè:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.Rokmog:BAAALgAECggJEQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Romanoff:BAAALgAECgEJAQABLgAECgkJIAAfAI0SAA==.Roxanol:BAAALgADCgEJAQABLgAECgkJPQAUACUaAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
Rx='Rxqüeen:BAAALgAECgEJAQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAgAAAA==.Sackoss:BAAALgAECgQJBQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJHwABLgAFFAMJCwAkAE4WAA==.Sainsei:BAABLgAECn8kAAMfAAcJFQalCACIAAAkAAUJBAcdZQCNAAAfAAcJnwWlCACIAAAAAA==.Saith:BAAALgAECgEJBgAAAA==.Samasear:BAABLgAECn8UAAIZAAgJ0w8wMgDjAQAZAAgJ0w8wMgDjAQABLgAFFAgJIQAlANMeAA==.Sandwitch:BAABLgAECn9DAAMTAAkJLRjBLwAZAgATAAkJLRjBLwAZAgAHAAIJmxB0UwB0AAAAAA==.Sanoa:BAACLgAFFH8JAAIcAAQJywTzDQDfAAAcAAQJywTzDQDfAAAuAAQKfxkAAxwACQmDEmADAEIBABwACAmNEWADAEIBAB4ABQnXDKwQAJIAAAAA.Sargatana:BAABLgAECn9IAAQfAAkJ7iB/BAD9AgAfAAkJ7iB/BAD9AgAkAAUJHBoCBQA0AQAEAAEJsQtEMgAkAAAAAA==.Sars:BAABLgAECn84AAMEAAkJpSQ6BQBXAwAEAAkJpSQ6BQBXAwAkAAMJGhO3XwCbAAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8nAAMOAAgJOR7tJAA6AgAOAAgJOR7tJAA6AgANAAQJ+BG9SwDAAAABLgAFFAQJDgAVAHwcAA==.Scarne:BAAALgAECgIJAgAAAA==.Schrodinger:BAABLgAECn8gAAIWAAgJuAp9IAAQAQAWAAgJuAp9IAAQAQAAAA==.Scravenhoof:BAAALgAECgcJDAAAAA==.',
Se='Seira:BAAALgAECgEJAwABLgAECgkJUAADAAkgAA==.Selunee:BAAALgADCgEJAQAAAA==.Semiu:BAAALgAECgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgAECgkJAQAAAA==.Severum:BAABLgAECn8+AAInAAkJYh0YBwCVAgAnAAkJYh0YBwCVAgAAAA==.Seyrah:BAAALgAECgkJAgAAAA==.',
Sh='Shabang:BAAALgAFFAEJAQAAAA==.Shadowtiger:BAABLgAECn8wAAIMAAkJag3tTgC1AQAMAAkJag3tTgC1AQAAAA==.Shadrad:BAACLgAFFH8NAAIVAAYJ6B9NIQCCAQAVAAYJ6B9NIQCCAQAuAAQKfxsAAhUACQnFJd0IACMDABUACQnFJd0IACMDAAAA.Shamanor:BAAALgAECgcJCAAAAA==.Shammoo:BAAALgAECgIJBAABLgAFFAkJNgAVABccAA==.Shantz:BAABLgAECn8sAAISAAgJVxRfHAB3AQASAAgJVxRfHAB3AQAAAA==.Shiban:BAABLgAECn8YAAIPAAkJIxCjEwAJAgAPAAkJIxCjEwAJAgAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIeAAkJ4xedIwDJAQAeAAkJ4xedIwDJAQAAAA==.Shokalypse:BAAALgADCgEJAQAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silverfox:BAAALgADCgMJAQABLgAECgkJPgAIAFYiAA==.Silx:BAABLgAECn8VAAMDAAcJMBE8IQCJAQADAAcJMBE8IQCJAQACAAEJoBZEXQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinsangel:BAAALgAECgYJBgAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.Sithiry:BAAALgAECgEJAQAAAA==.',
Sk='Skik:BAAALgAECgcJBwAAAA==.Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgYJBgABLgAFFAgJGAAZAPYTAA==.Slaté:BAAALgAECgEJAgABLgAECgMJBQAJAAAAAA==.Slowrot:BAAALgAECgQJBQABLgAFFAQJDQAVAIQaAA==.Slushpuppy:BAAALgAFFAEJAQAAAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smokkie:BAABLgAFFH8OAAIVAAQJfByrEgBGAQAVAAQJfByrEgBGAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAABLgAECn8bAAMkAAkJGiG9BgDeAgAkAAkJGiG9BgDeAgAEAAEJtws1xgAlAAAAAA==.',
So='Solas:BAAALgADCgYJBgAAAA==.Somaliabiggs:BAAALgAECgYJCgAAAA==.Sonar:BAAALgADCgYJBgABLgAECgkJPAAKAJclAA==.Sonuvabitxh:BAAALgADCgQJBAAAAA==.Sorraba:BAABLgAFFH8KAAIIAAQJUgKVjgC7AAAIAAQJUgKVjgC7AAABLgAFFAUJEwADAOgQAA==.Sorrabo:BAACLgAFFH8TAAMDAAUJ6BDTJQAdAQADAAUJ6BDTJQAdAQACAAEJrhmQHABQAAAuAAQKfyIABAMACQn3Gd4LALECAAMACQn3Gd4LALECAAEAAwm7A8JlAEsAAAIAAQkpA2yYACEAAAAA.Sorraug:BAAALgAFFAMJAwABLgAFFAUJEwADAOgQAA==.Soryan:BAACLgAFFH8IAAIVAAQJWALmegDAAAAVAAQJWALmegDAAAAuAAQKfxoAAhUACAk4B9OVAFEBABUACAk4B9OVAFEBAAAA.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8VAAITAAUJ8B2/OwBdAQATAAUJ8B2/OwBdAQAuAAQKfx4ABBMABwnhIyYXAMkCABMABwnhIyYXAMkCACAAAQkAAPIfAHIAAAcAAQm1GkhiAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8lAAMVAAkJTRgKRgD0AQAVAAkJTRgKRgD0AQAUAAUJowh+YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAABLgAECn8VAAIEAAcJVhxiHwAfAgAEAAcJVhxiHwAfAgABLgAECggJSQAEABclAA==.Sparkyy:BAAALgAECgMJAwAAAA==.',
Sq='Squeaks:BAAALgAECgkJAQAAAA==.Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stash:BAAALgAFFAEJAgAAAA==.Stinkycurse:BAAALgAECgUJBQABLgAECgYJHQAfAMwYAA==.Stinkydeathy:BAAALgAECgMJBAABLgAECgYJHQAfAMwYAA==.Stinkyfree:BAABLgAECn8dAAMfAAYJzBjSLgCcAQAfAAYJzBjSLgCcAQAkAAEJQRPuGAA9AAAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJHQAfAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCgKADQAgAIAAgJ6SCgKADQAgAAAA==.Stormknight:BAAALgAFFAMJAwAAAA==.Stormpoo:BAAALgAECgEJAQAAAA==.Straka:BAABLgAECn8fAAIFAAkJERIZPgCrAQAFAAkJERIZPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Sultanae:BAAALgAECgQJBAAAAA==.Sunbearr:BAAALgAECgEJAgAAAA==.Suneater:BAAALgAECgEJAgAAAA==.Sunmane:BAAALgAECgEJAwABLgAECgkJLQAbAL0ZAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdk:BAABLgAFFH8IAAIlAAQJkhb8CwA7AQAlAAQJkhb8CwA7AQABLgAFFAgJFQAVAOIaAA==.Superdruid:BAAALgADCgUJBQABLgAFFAgJFQAVAOIaAA==.Supermonks:BAAALgAECggJDAABLgAFFAgJFQAVAOIaAA==.Superpi:BAABLgAECn8aAAIDAAcJFx5uEwBFAgADAAcJFx5uEwBFAgABLgAFFAgJFQAVAOIaAA==.Superret:BAACLgAFFH8VAAIVAAgJ4hrtEADnAQAVAAgJ4hrtEADnAQAuAAQKfycAAxUACQkGI/gOABYDABUACQkGI/gOABYDABQAAQn7FAWIADsAAAAA.Superskeet:BAACLgAFFH8HAAIUAAMJtAsSNgCWAAAUAAMJtAsSNgCWAAAuAAQKfyUAAhQACAl3F54iAPABABQACAl3F54iAPABAAAA.Superwar:BAAALgAECgkJCQABLgAFFAgJFQAVAOIaAA==.',
Sv='Svetllama:BAAALgAECgYJCgAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMLAAYJlBZYOwBzAQALAAYJjhRYOwBzAQAMAAUJAg0MxQC9AAAAAA==.',
Sy='Sylphièl:BAACLgAFFH8VAAMGAAUJDgdfBgALAQAGAAUJDgdfBgALAQAoAAEJqQKSEwAsAAAuAAQKfygAAwYACAkwDoQLAHgBACgACAmbCq8EALkBAAYACAlDDYQLAHgBAAAA.Syncere:BAAALgAFFAIJAgAAAA==.Synhunt:BAAALgAFFAEJAgAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8aAAMVAAYJJxnaMABQAQAVAAUJWB/aMABQAQAUAAEJZAAAAAAAAAAuAAQKfyIAAhUACQmjHqoPABEDABUACQmjHqoPABEDAAAA.Tano:BAAALgAECgUJCQABLgAECgkJPgAIAFYiAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgYJCAAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Tazath:BAAALgAECgEJAwAAAA==.Taírn:BAABLgAECn8ZAAQQAAYJlQ19CADQAAAQAAYJeA19CADQAAAYAAYJpAaCGQCIAAAXAAEJpwRvQwAgAAAAAA==.',
Te='Tehpredator:BAAALgAFFAMJAwABLgAFFAUJEwADAOgQAA==.Teilin:BAACLgAFFH8gAAIRAAgJ2B4uAwCrAgARAAgJ2B4uAwCrAgAuAAQKfyIAAhEACQmQI7MEACcDABEACQmQI7MEACcDAAAA.Tenderloin:BAABLgAECn8YAAINAAkJcQraBgAbAQANAAkJcQraBgAbAQAAAA==.Teralynn:BAAALgAECgEJAgAAAA==.Terryisgreat:BAAALgAECgIJAwABLgAECggJGgAUAHgXAA==.',
Th='Thalendor:BAAALgAECgIJAgAAAA==.Theaterthug:BAAALgAECgIJAgAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgIJAwABLgAECgcJFgAPAM4TAA==.Thewhole:BAAALgAFFAQJAQAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICPAIgAyAgAFAAYJICPAIgAyAgABLgAFFAEJAQAJAAAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAACLgAFFH8KAAIOAAMJARlyXQDXAAAOAAMJARlyXQDXAAAuAAQKfzwAAw4ACQkFJfQDAEcDAA4ACQkFJfQDAEcDAA0ABwlYHRAUADICAAAA.Thundurus:BAACLgAFFH8QAAIeAAYJpxBBJwD5AAAeAAYJpxBBJwD5AAAuAAQKfyUAAh4ACAm9Fmc3AFsBAB4ACAm9Fmc3AFsBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAITAAgJCBZ5OQAmAgATAAgJCBZ5OQAmAgAAAA==.Timmertot:BAAALgADCgEJAQAAAA==.Tindrill:BAABLgAECn84AAMmAAkJhyXYAABzAwAmAAkJfSXYAABzAwAnAAYJfyOuAQAJAgAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tofu:BAAALgAECgMJBAAAAA==.Tomraedisk:BAACLgAFFH8FAAIZAAQJegfjKwAEAQAZAAQJegfjKwAEAQAuAAQKfxkAAhkACQmJG8MWADgCABkACQmJG8MWADgCAAAA.Totemagoat:BAACLgAFFH8nAAMRAAgJPBb1CACpAQARAAgJPBb1CACpAQAeAAUJ+hCKJwD3AAAuAAQKfzQAAx4ACQkJHdUYABwCAB4ACAnQG9UYABwCABEACQmqFNgsANcBAAAA.Totemlyfine:BAABLgAECn82AAMRAAkJUCEpEADQAgARAAkJUCEpEADQAgAeAAQJMBUkYQDCAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJEgAAAA==.Treechains:BAABLgAECn8WAAMRAAYJ8hcGUAByAQARAAYJ8hcGUAByAQAeAAEJZQPtkQAlAAAAAA==.Treefist:BAAALgAFFAIJBAAAAA==.Treelight:BAAALgAECgcJCAAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAgAAAA==.Triplex:BAAALgAECgQJBAAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Ts='Tsumuji:BAAALgAECgEJAQAAAA==.',
Tu='Tulainth:BAAALgAECgQJBQAAAA==.Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAACLgAFFH8MAAIFAAMJJgVvTgCGAAAFAAMJJgVvTgCGAAAuAAQKfxUAAgUABwmGEOVdADgBAAUABwmGEOVdADgBAAAA.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Tygra:BAAALgAECgcJDgAAAA==.Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgMJBAAAAA==.',
['Tø']='Tøga:BAAALgADCgMJAQAAAA==.Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1qEABUAgAEAAkJjh1qEABUAgAAAA==.',
Un='Undeadmonks:BAACLgAFFH8QAAIfAAMJ/BcWDwDKAAAfAAMJ/BcWDwDKAAAuAAQKf0kAAx8ACQliHqgHALsCAB8ACQliHqgHALsCACQAAwl2CsRlAHYAAAAA.',
Uv='Uvaweez:BAAALgAECgMJAwAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgYJCwAAAA==.Valeshot:BAACLgAFFH8FAAIMAAMJwAHzfQCcAAAMAAMJwAHzfQCcAAAuAAQKfycAAgwACQnUCm4/ALEBAAwACQnUCm4/ALEBAAAA.Valkillrie:BAAALgADCgcJBwAAAA==.Valkyrié:BAAALgAECgIJBAAAAA==.Vall:BAAALgAECggJDAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAoRsAAhAQAIAAcJmAoRsAAhAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.Vashi:BAABLgAECn86AAIVAAkJQxb6UgDQAQAVAAkJQxb6UgDQAQAAAA==.',
Ve='Vedbow:BAACLgAFFH8UAAQPAAQJmiNdDQBaAQAPAAQJ0iFdDQBaAQAMAAMJMBUeZgDZAAALAAEJgA+6JwBNAAAuAAQKfxwABAwACQnIIh4UAJUCAAwACAm5IR4UAJUCAAsABAnyHyc8AG4BAA8AAwldIPo1AAUBAAAA.Vedronas:BAABLgAECn8XAAIVAAcJaiOcHgC0AgAVAAcJaiOcHgC0AgAAAA==.Velara:BAAALgADCgUJBQAAAA==.Velillys:BAAALgAECgEJAQAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Veos:BAAALgAECgEJAQAAAA==.Verdict:BAABLgAECn8aAAIRAAkJeRIEPQC6AQARAAkJeRIEPQC6AQAAAA==.Veritae:BAAALgAECgcJCQAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+BdlJQCkAQADAAgJ+BdlJQCkAQACAAIJgwYoWQBWAAAAAA==.Vernaar:BAAALgAECgMJAwABLgAECggJGAADAPgXAA==.Vernah:BAABLgAECn8VAAIUAAgJ1Rk4GABGAgAUAAgJ1Rk4GABGAgABLgAECggJGAADAPgXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwgewDbAQAIAAYJpRwgewDbAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgAECgYJBgAAAA==.',
Wa='Waambler:BAAALgAECgIJAgAAAA==.Waamchifu:BAABLgAECn85AAIfAAkJhyN4AgA2AwAfAAkJhyN4AgA2AwAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAACLgAFFH8OAAIMAAQJ1w9MHwAYAQAMAAQJ1w9MHwAYAQAuAAQKfxcAAgwACQlvFz0pADkCAAwACQlvFz0pADkCAAAA.Warsheep:BAAALgADCgQJAQAAAA==.',
We='Wednesdayy:BAAALgAECgEJAgAAAA==.Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgAECgEJAQABLgAFFAQJDQAVAIQaAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whoforted:BAAALgAFFAIJAwAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8tAAIVAAkJHR9rFQDCAgAVAAkJHR9rFQDCAgABLgAFFAQJBQAZAHoHAA==.Wisperia:BAAALgADCgYJBgAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.Wulrat:BAAALgAECgEJAQABLgAECgkJNQATALMZAA==.',
Xe='Xelí:BAAALgAECgEJAgAAAA==.Xercuul:BAAALgAECgcJEgAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Xp='Xplosiv:BAABLgAECn8WAAIMAAgJLCKgCAC9AQAMAAgJLCKgCAC9AQABLgAFFAgJIgARAOUcAA==.',
Xy='Xylophonejoe:BAAALgAECgYJDgAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.Yourdad:BAAALgAECgYJEAABLgAFFAEJAQAJAAAAAA==.',
Yu='Yudah:BAACLgAFFH8JAAQPAAMJuRQPIgDJAAAPAAMJDQ4PIgDJAAAMAAIJzxwWgACYAAALAAEJ3AAaPQAnAAAuAAQKfy0ABA8ACAmgHT8YAN8BAA8ACAkZGT8YAN8BAAsABglUFtYTACQBAAwABwlgD1KWABMBAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgAECgEJAQAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAACLgAFFH8LAAIkAAMJThaKCgDhAAAkAAMJThaKCgDhAAAuAAQKf04AAyQACQnDIrsDACQDACQACQnDIrsDACQDAAQAAQlJFdZkAD4AAAAA.Zara:BAAALgAECgEJAwAAAA==.Zarinaria:BAABLgAECn8cAAIOAAYJ2Q7qfQAvAQAOAAYJ2Q7qfQAvAQAAAA==.',
Ze='Zetsumei:BAAALgADCgMJAwAAAA==.',
Zh='Zhael:BAABLgAECn8hAAIOAAkJCRo0JwAvAgAOAAkJCRo0JwAvAgAAAA==.',
Zi='Zitizen:BAAALgADCgYJBwAAAA==.',
Zo='Zodstrike:BAABLgAECn82AAMNAAkJrAtwCgDAAAAOAAkJbwUjiwAKAQANAAYJHg5wCgDAAAAAAA==.Zomara:BAAALgAECgMJCgAAAA==.Zooboo:BAABLgAECn8XAAIZAAkJURcjJgDHAQAZAAkJURcjJgDHAQAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJCwABLgAFFAEJAQAJAAAAAA==.',
['Ät']='Ätticus:BAAALgAECgYJBwABLgAFFAEJAQAJAAAAAA==.',
['Äú']='Äúra:BAAALgAECggJCQAAAA==.',
['Åi']='Åir:BAAALgADCgIJAgAAAA==.',
['Ðô']='Ðôôm:BAAALgAECgEJAQAAAA==.',
['Öv']='Överpöwered:BAAALgADCgIJAgABLgAFFAEJAQAJAAAAAA==.',
['Öð']='Öðïn:BAAALgADCgQJBAAAAA==.',
['ßl']='ßlisster:BAAALgADCgYJBgAAAA==.',
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
