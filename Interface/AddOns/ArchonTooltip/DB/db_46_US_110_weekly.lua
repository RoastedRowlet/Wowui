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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Preservation','Paladin-Retribution','DemonHunter-Devourer','Warlock-Affliction','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIDAAYJ3xW+MAA8AQADAAYJ3xW+MAA8AQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIEAAQJIRWgJQATAQAEAAQJIRWgJQATAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAABLgAECn8XAAQFAAkJHwbvOwCiAAAGAAYJEwfFUQC4AAAFAAkJywLvOwCiAAAHAAQJBgbIMACKAAAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9EAAIIAAkJgB17IAB/AgAIAAkJgB17IAB/AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIJAAMJBxnnMwDaAAAJAAMJBxnnMwDaAAAuAAQKfyMAAwkACQn9IScJAP4CAAkACQn9IScJAP4CAAYAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAJAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAIKAAYJVhsCOgC5AQAKAAYJVhsCOgC5AQAAAA==.Amorsith:BAAALgAECggJEQAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8NAAMLAAMJ9h4XOQCsAAALAAIJxh4XOQCsAAAMAAEJVh/TNgBRAAAuAAQKfyUAAwwACQnQIn8FAKYCAAwACAm+IH8FAKYCAAsABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgYJDQAAAA==.Angrycrack:BAABLgAECn8YAAICAAgJsBmAGQC/AQACAAgJsBmAGQC/AQAAAA==.Animuggus:BAEBLgAECn8UAAIGAAYJzxrLKwBpAQAGAAYJzxrLKwBpAQAAAA==.Anjunabeets:BAABLgAFFH8lAAQNAAgJSBtwDgDHAQANAAYJih5wDgDHAQAOAAYJYQ+fCQCAAQAPAAIJ9w+yJgCNAAAAAA==.Anthran:BAABLgAECn8mAAMQAAkJqw8jHwBYAQAQAAYJzQ4jHwBYAQARAAcJJQzafQA4AQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgYJBwABLgAECgkJNAALAAEXAA==.Archos:BAAALgAECgEJBAAAAA==.Arcscythe:BAABLgAECn8kAAISAAkJ4BavAgAIAgASAAkJ4BavAgAIAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgQJBgAAAA==.Artoo:BAAALgAECggJDAAAAA==.',
As='Asleep:BAAALgAECgQJBQABLgAECgkJNAALAAEXAA==.Assaulter:BAAALgAECgYJCQABLgAFFAEJAQABAAAAAA==.Astralpanda:BAABLgAECn8ZAAITAAgJKAoCRgALAQATAAgJKAoCRgALAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8wAAIUAAkJFw+rIwC2AQAUAAkJFw+rIwC2AQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAVADEYAA==.Baer:BAABLgAECn8eAAIFAAgJ9geKNgC4AAAFAAgJ9geKNgC4AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn82AAIWAAkJWA+NJwDEAQAWAAkJWA+NJwDEAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8gAAIRAAcJAQt9iAAkAQARAAcJAQt9iAAkAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAXAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8aAAIYAAgJdhsFEADcAQAYAAgJdhsFEADcAQAAAA==.Bauchelaine:BAABLgAECn8fAAIRAAgJIw9ZYQB5AQARAAgJIw9ZYQB5AQAAAA==.Bavunga:BAABLgAECn8pAAIZAAkJhCCJAgA6AwAZAAkJhCCJAgA6AwAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAFFAEJAQAAAA==.Beoron:BAACLgAFFH8HAAIHAAMJoxzkCgDyAAAHAAMJoxzkCgDyAAAuAAQKfy0AAgcACQlbJeoAAFUDAAcACQlbJeoAAFUDAAEuAAUUBAkHABQAgREA.Bettyßastion:BAABLgAECn8yAAIaAAkJrx+UGACmAgAaAAkJrx+UGACmAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJDAABAAAAAA==.Bioenergy:BAAALgAECgkJDAAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJDAABAAAAAA==.Biolysis:BAAALgAECgMJAwABLgAECgkJDAABAAAAAA==.Bisoncrusher:BAAALgAECggJDwAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAABLgAECn8YAAIVAAgJhAcWPAAZAQAVAAgJhAcWPAAZAQABLgAFFAMJGQAKAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMPAAgJQSVlAgAeAwAPAAgJQSVlAgAeAwAOAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAABLgAECn8WAAITAAgJ+xL2KACZAQATAAgJ+xL2KACZAQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECggJEwAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIGAAgJehYaKQC2AQAGAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMNAAcJZxN8bwBVAQANAAcJZxN8bwBVAQAPAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgQJBQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQABLgAECgkJKQAKAFsRAA==.Calißoy:BAABLgAECn8pAAIKAAkJWxFvOADAAQAKAAkJWxFvOADAAQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJBAABAAAAAA==.Cannyon:BAAALgAECgQJBwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJRAACAE4lAA==.Ceruledge:BAABLgAECn8YAAIbAAgJSBQJRwCmAQAbAAgJSBQJRwCmAQABLgAFFAMJBgAVADwWAA==.',
Ch='Chaboomy:BAECLgAFFH8XAAIGAAcJSxGCDQClAQAGAAcJSxGCDQClAQAuAAQKfx0AAgYACAkFIOcPAKQCAAYACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn80AAILAAkJARfTGQAYAgALAAkJARfTGQAYAgAAAA==.Chopper:BAACLgAFFH8RAAIHAAQJ7BpYBQBOAQAHAAQJ7BpYBQBOAQAuAAQKfyYAAgcACQn9IWYDAAEDAAcACQn9IWYDAAEDAAEuAAUUBQkRABwAvw4A.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAIdAAQJsxFEJQAKAQAdAAQJsxFEJQAKAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMDAAcJfBWpJgC4AQADAAcJ5hSpJgC4AQAeAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn89AAIHAAkJbiaBAABzAwAHAAkJbiaBAABzAwAAAA==.Colmoore:BAAALgAFFAEJAgABLgAFFAQJDQARAL0YAA==.Conkerin:BAABLgAFFH8HAAINAAMJqhfgUQDvAAANAAMJqhfgUQDvAAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJDQAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAfAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCAABLgAFFAIJBAABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIJAAgJVgqCTgBqAQAJAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgcJDwAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8GAAIKAAIJ0CJTRQDCAAAKAAIJ0CJTRQDCAAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQQAAkJwhhuGwByAQARAAgJAhLSWACOAQAQAAcJZBZuGwByAQAcAAIJ0Rj7JgByAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAUJFgAgAJsjAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAYJHQACAM8cAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIIAAkJCxs5JQBnAgAIAAkJCxs5JQBnAgAAAA==.Deepman:BAAALgAFFAEJAQAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8/AAMhAAkJdyR0AQAtAwAhAAkJdyR0AQAtAwAWAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAANAHcDAA==.Disastrous:BAACLgAFFH8SAAINAAYJoxQKGwCCAQANAAYJoxQKGwCCAQAuAAQKfzMAAg0ACQlCIMYRAKoCAA0ACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJOAAfAKMiAA==.',
Do='Doomangel:BAABLgAECn8UAAIIAAYJuhEMqgAUAQAIAAYJuhEMqgAUAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAABLgAECn8VAAILAAYJGQZiXgDPAAALAAYJGQZiXgDPAAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJGQAKAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAXALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJTAAaAFofAA==.Dragonslock:BAABLgAECn8VAAQRAAcJKQ6ingD8AAARAAYJcA6ingD8AAAQAAIJxAwmPAAwAAAcAAEJiwOjQAAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIUAAcJDBGQJQCQAQAUAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMJAAkJtxHOQgB8AQAJAAcJRBHOQgB8AQAGAAgJ9QaxVACuAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAFFAEJAQABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8dAAICAAYJzxwkCgDOAQACAAYJzxwkCgDOAQAuAAQKfzEAAgIACQkmJToDAA8DAAIACQkmJToDAA8DAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAYJHQACAM8cAA==.',
['Dø']='Døc:BAABLgAECn9JAAQKAAkJ9xkJEwCpAgAKAAkJ9xkJEwCpAgATAAkJchFqIgDEAQAiAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIhAAMJWQ6QCwCwAAAhAAMJWQ6QCwCwAAAuAAQKfyAAAyEACAl0G/8QALcBACEABwlyGP8QALcBABoABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8UAAMRAAcJOA9+IQCjAQARAAcJOA9+IQCjAQAQAAEJagETGwBAAAAuAAQKfykAAxEACAl7HHQ1ADYCABEACAl7HHQ1ADYCABAAAQkAAMRfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8fAAIbAAkJMhnjKgBVAgAbAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9SAAIjAAkJUh2rCQBvAgAjAAkJUh2rCQBvAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erindralla:BAAALgAECgQJBQAAAA==.Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8RAAQcAAUJvw6qDwB+AAARAAUJvw6eUgAVAQAQAAIJ6AeoFACDAAAcAAIJmgeqDwB+AAAuAAQKfy4ABBEACQn5GpFAANUBABEACAloGJFAANUBABAACAmiFL0fAFQBABwAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAUJFgAgAJsjAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJCAABLgAECgcJDwABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finnland:BAAALgAECgEJAQABLgAFFAIJCQAjAMoaAA==.Finntastic:BAAALgADCgYJCAABLgAFFAIJCQAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCQAjAMoaAA==.Fisterdobble:BAABLgAECn9BAAIXAAkJ2xaQSQD4AQAXAAkJ2xaQSQD4AQAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAAALgAECggJEgABLgAECggJGgAEAA0jAA==.Forgeddemon:BAABLgAECn8XAAMdAAgJJgmlRQArAQAdAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAQJCwAEAJMUAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIhAAkJ0h6MBgB/AgAhAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIXAAgJGRTOZgCpAQAXAAgJGRTOZgCpAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMYAAcJFBQ2GACUAQAYAAcJFBQ2GACUAQALAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIhAAYJ1hd/GABLAQAhAAYJ1hd/GABLAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJCAAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8WAAIaAAgJIxtoQgD1AQAaAAgJIxtoQgD1AQAAAA==.Goodboy:BAABLgAFFH8IAAINAAQJdwNCYgDGAAANAAQJdwNCYgDGAAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8qAAIJAAcJBxMYQQCEAQAJAAcJBxMYQQCEAQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8WAAIgAAUJmyPlAQCeAQAgAAUJmyPlAQCeAQAuAAQKfxoAAiAACAlcJBUCAOgCACAACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8bAAIKAAYJ/xSqSwBzAQAKAAYJ/xSqSwBzAQAAAA==.',
Gu='Gulaj:BAABLgAECn8UAAINAAgJZRjISQCMAQANAAgJZRjISQCMAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQcAAkJRROfCADMAQARAAgJ1RFYRQD7AQAcAAkJNxKfCADMAQAQAAQJ2wdjPAAwAAAAAA==.',
He='Healgimp:BAABLgAECn8iAAIDAAkJixVFHgDEAQADAAkJixVFHgDEAQAAAA==.Healslux:BAABLgAECn8eAAIWAAkJvx9PDADAAgAWAAkJvx9PDADAAgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAAALgAECgEJAgABLgAFFAcJFAAeAOEQAA==.Hortzel:BAABLgAECn8UAAIRAAYJOA5omgAEAQARAAYJOA5omgAEAQAAAA==.Hotrollz:BAAALgAECgQJBwABLgAECgkJGQAJAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAABLgAECn8ZAAIaAAcJiBv4RgDmAQAaAAcJiBv4RgDmAQAAAA==.Huntus:BAABLgAECn84AAMNAAkJsCNqCgD5AgANAAkJsCNqCgD5AgAOAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIaAAgJHxZqYgChAQAaAAgJHxZqYgChAQAAAA==.',
Ic='Icy:BAAALgAECgYJBwAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAUAAcJjxKLIgCqAQAAAA==.Impostor:BAACLgAFFH8FAAIVAAMJ3whNJAC+AAAVAAMJ3whNJAC+AAAuAAQKfzIAAhUACQl2INAGAN8CABUACQl2INAGAN8CAAAA.',
In='Indabow:BAABLgAECn8gAAINAAkJbRopKAAXAgANAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAdAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8dAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAbAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIbAAIJvCHNXwC+AAAbAAIJvCHNXwC+AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8rAAIkAAkJSBzVCQCcAgAkAAkJSBzVCQCcAgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8WAAMCAAUJsh0AEwBgAQACAAUJsh0AEwBgAQAgAAEJBwdhEQBFAAAuAAQKfxsAAwIACAmEHPohAOkBAAIABwkRHfohAOkBACAABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8ZAAIdAAcJAQ4NEgB9AQAdAAcJAQ4NEgB9AQAuAAQKfyQAAh0ACAnxElshAPcBAB0ACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJDQABLgAECgcJDwABAAAAAA==.Juul:BAABLgAECn8YAAIUAAkJ2RV9FQAmAgAUAAkJ2RV9FQAmAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAQJCwAVAFcJAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAQJCwAVAFcJAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgAECgYJCAABLgAECgYJEQABAAAAAA==.Karram:BAAALgADCgYJBgAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Kc='Kcup:BAAALgADCgIJAgAAAA==.',
Ke='Kelemvor:BAABLgAECn83AAIbAAkJlx3zFQDTAgAbAAkJlx3zFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8XAAIjAAUJVxlTFwAZAQAjAAUJVxlTFwAZAQAuAAQKfxUAAiMACAnWGQAPABwCACMACAnWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Kidslaps:BAABLgAECn8eAAIdAAgJTAyZLgBCAQAdAAgJTAyZLgBCAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8LAAIEAAQJkxQ8JgAPAQAEAAQJkxQ8JgAPAQAuAAQKfycABAQACQn+F6IgAK4BAAQACQn+F6IgAK4BAB0AAQlKDACEAD0AACQAAQk9D+mRADMAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8jAAINAAkJFhoYJQBCAgANAAkJFhoYJQBCAgABLgAFFAEJAQABAAAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8kAAQRAAgJagf0iAAjAQARAAcJagf0iAAjAQAQAAUJxATOKgBjAAAcAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAIRAAkJiBqrHAByAgARAAkJiBqrHAByAgAAAA==.',
Lh='Lhux:BAABLgAECn8uAAINAAgJ/iO9DADZAgANAAgJ/iO9DADZAgAAAA==.Lhuxi:BAACLgAFFH8RAAIUAAQJVhjUIQA4AQAUAAQJVhjUIQA4AQAuAAQKfykAAhQACQleHS0KAK4CABQACQleHS0KAK4CAAEuAAQKCAkuAA0A/iMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAABLgAECn8UAAIaAAkJwRrtIQB1AgAaAAkJwRrtIQB1AgAAAA==.Lightisright:BAAALgAECgYJCwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIaAAgJaBBhbQCIAQAaAAgJaBBhbQCIAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8UAAIGAAUJ9BQsIAAKAQAGAAUJ9BQsIAAKAQAuAAQKfy0AAgYACQk0IPcHAMsCAAYACQk0IPcHAMsCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIJAAkJdA0pRAB2AQAJAAkJdA0pRAB2AQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAgAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSQAKAPcZAA==.Lyxxie:BAABLgAECn9EAAMIAAkJihrQNwBXAgAIAAkJihrQNwBXAgAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIXAAkJsByjJwB2AgAXAAkJsByjJwB2AgAAAA==.Mageus:BAAALgAECgEJAQAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECggJFAAhANYXAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8fAAILAAkJ8g0sKQCtAQALAAkJ8g0sKQCtAQABLgAFFAMJGQAKAMMYAA==.Metsutan:BAABLgAECn9EAAICAAkJTiWAAwAFAwACAAkJTiWAAwAFAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAABLgAECn8wAAMVAAkJ+xMyHgDLAQAVAAgJghUyHgDLAQADAAYJoQoYYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAIXAAYJHxYLvABqAQAXAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIcAAgJNCJ9AgCWAgAcAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCQAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAXALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAQJCwAVAFcJAA==.Moskeebee:BAABLgAECn8UAAINAAcJyiUSEgCnAgANAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8WAAMKAAkJAAIreQDiAAAKAAkJAAIreQDiAAATAAQJewHGiQBOAAAAAA==.',
['Må']='Måtthew:BAAALgADCgYJBQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAIRAAcJoQrRhwAlAQARAAcJoQrRhwAlAQAAAA==.Møsh:BAAALgAECgkJCwAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.Nazuresh:BAAALgAECgUJCgABLgAECggJMAADAFYTAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMRAAgJVBv0QwAAAgARAAgJVBv0QwAAAgAQAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn9HAAMRAAkJcBwqEwCuAgARAAkJeRsqEwCuAgAQAAgJpRzIBAAhAgAAAA==.Nemriel:BAAALgAECgcJDwAAAA==.Newthilena:BAAALgAECgQJBwAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMbAAkJjxYzQgC1AQAbAAkJzxAzQgC1AQAfAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECggJDQAAAA==.Nossem:BAAALgAECgEJAQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPAALAKAlAA==.Nymera:BAAALgADCgEJAQABLgAECgcJIAAFAHwYAA==.',
['Nä']='Nämeless:BAAALgAFFAIJAwAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIeAAMJTBz2JgD4AAAeAAMJTBz2JgD4AAAuAAQKfywAAh4ACAlGIJUPAGoCAB4ACAlGIJUPAGoCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ol='Olgaa:BAAALgAECgEJAQAAAA==.',
On='Oneth:BAABLgAECn8UAAIcAAYJ3xCzFQAJAQAcAAYJ3xCzFQAJAQAAAA==.Onfleek:BAABLgAECn8yAAMDAAgJXCOZBgD+AgADAAgJXCOZBgD+AgAVAAYJJA1BNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8ZAAIKAAMJwxh0QADQAAAKAAMJwxh0QADQAAAuAAQKf0MAAgoACQkdHT4TAKcCAAoACQkdHT4TAKcCAAAA.',
Or='Orakrak:BAABLgAECn8lAAILAAkJHhECIwDUAQALAAkJHhECIwDUAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgAECgEJAQAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNQAeAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNQAeAB4lAA==.Parseval:BAABLgAECn81AAQeAAkJHiUMAgCbAwAeAAkJHiUMAgCbAwAVAAgJ0Rv8FAAdAgADAAQJPxsuQwAsAQAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPAALAKAlAA==.Paws:BAABLgAECn88AAILAAkJoCU6AwAzAwALAAkJoCU6AwAzAwAAAA==.',
Pd='Pdbm:BAAALgAECgEJAQAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIWAAgJORjcOQBXAQAWAAgJORjcOQBXAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIiAAYJqg2wHQD8AAAiAAYJqg2wHQD8AAAAAA==.',
Pi='Pipsqueak:BAAALgAFFAEJAQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAEJAgAAAA==.Porkins:BAABLgAECn88AAMjAAkJGSDCCQBtAgAjAAgJmx/CCQBtAgAmAAkJqh3dBgAgAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgAECgYJCQAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAECgYJBgAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAbALwhAA==.',
Ps='Psyndar:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Psyndra:BAAALgAECgYJCQABLgAFFAEJAQABAAAAAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8LAAIXAAMJ0BMsdwDiAAAXAAMJ0BMsdwDiAAAuAAQKfzIAAhcACQkTH0MVANMCABcACQkTH0MVANMCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAQJCwAVAFcJAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8NAAIRAAQJvRiOOABQAQARAAQJvRiOOABQAQAuAAQKfzIAAhEACAnDJOQKAPMCABEACAnDJOQKAPMCAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMbAAgJjRLfXwBeAQAbAAgJ7xHfXwBeAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8wAAMDAAgJVhNFIQCrAQADAAgJVhNFIQCrAQAVAAUJ2gWJXQCSAAAAAA==.',
Re='Replicate:BAACLgAFFH8FAAILAAMJrBvPKAD+AAALAAMJrBvPKAD+AAAuAAQKfyIAAgsACQm9IUgFAAQDAAsACQm9IUgFAAQDAAAA.Resisted:BAAALgAECgEJAQABLgAFFAcJFAAUAC4aAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJPAANAI0cAA==.',
Ry='Ryanqt:BAAALgAECgcJBwAAAA==.Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8UAAIWAAYJkyAjCAAeAgAWAAYJkyAjCAAeAgAuAAQKfzEAAhYACQmNJd0AAJIDABYACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJDwAAAA==.Ryri:BAABLgAECn8fAAIhAAcJXxUPFAB/AQAhAAcJXxUPFAB/AQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMeAAkJlgqwIgB+AQAeAAkJlgqwIgB+AQAVAAIJGQsQawBgAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMdAAkJbQnmKQBeAQAdAAkJbQnmKQBeAQAEAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJBQAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECggJEQAAAA==.Santoku:BAABLgAECn8QAAIbAAYJsxdYaABIAQAbAAYJsxdYaABIAQAAAA==.Sarah:BAACLgAFFH8OAAIeAAQJZhZyIAAqAQAeAAQJZhZyIAAqAQAuAAQKfzMAAh4ACQmxHwMFADQDAB4ACQmxHwMFADQDAAAA.Sassyface:BAABLgAECn9KAAIQAAkJ7Q7wCgCCAQAQAAkJ7Q7wCgCCAQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Sc='Scarletdawns:BAAALgADCgEJAQAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAJAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAAALgAECgYJEQAAAA==.Shaduw:BAACLgAFFH8ZAAIYAAcJwx9fBQDfAQAYAAcJwx9fBQDfAQAuAAQKfyQAAxgACAnOIbMDABkDABgACAnOIbMDABkDAAsACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBBhKQA8AQACAAcJkBBhKQA8AQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJCQABLgAECgkJJgAQAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIVAAMJPBZ3IQDRAAAVAAMJPBZ3IQDRAAAuAAQKfzYAAhUACQlGIfwFAC4DABUACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIXAAMJCBsvdADoAAAXAAMJCBsvdADoAAAuAAQKfycAAhcACQlNIykVACkDABcACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMWAAgJniPOEACMAgAWAAgJniPOEACMAgAaAAQJrRgzJAF8AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMEAAgJDSPpCQC0AgAEAAcJnyLpCQC0AgAkAAYJJBWfMQAyAQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQgAAgJEBezCACzAQAgAAgJyhWzCACzAQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgUJCwAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAQJCwAVAFcJAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIaAAkJjwTxygDtAAAaAAkJjwTxygDtAAAAAA==.Stelthme:BAABLgAECn8aAAQgAAYJIxhTCwByAQAgAAYJIxhTCwByAQAnAAMJQwgtGQB9AAACAAEJGAiiXgA5AAABLgAFFAMJDQACAF4lAA==.Stormburst:BAAALgADCgIJAgABLgAFFAUJFgAgAJsjAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIXAAcJQyFKOgCNAgAXAAcJQyFKOgCNAgABLgAECggJFAAPAEElAA==.',
Su='Susaki:BAAALgAECgQJBQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAAPAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8pAAIYAAkJcx/KBADJAgAYAAkJcx/KBADJAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8HAAIUAAQJgRG2LQD/AAAUAAQJgRG2LQD/AAAuAAQKfyIAAxQACQl5IGkGAO4CABQACQl5IGkGAO4CACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgAECgMJAwAAAA==.',
Th='Theory:BAABLgAECn9FAAMIAAkJ4Rl6KwBKAgAIAAkJ1Rd6KwBKAgAjAAIJ+hgnPQCQAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBgAAAA==.',
To='Tomjim:BAACLgAFFH8UAAMUAAcJLhqqGQB1AQAUAAYJ4BmqGQB1AQAZAAMJZQXtEwCLAAAuAAQKfyYABBQACAlAIwsLAMUCABQACAlAIwsLAMUCABkABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn83AAIPAAkJ2RtCDgBCAgAPAAkJ2RtCDgBCAgAAAA==.Treevive:BAACLgAFFH8MAAIJAAYJzxJLEwC9AQAJAAYJzxJLEwC9AQAuAAQKfxkAAgkACAmaIEEcAFoCAAkACAmaIEEcAFoCAAAA.Trencough:BAAALgAECgYJCQAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn9AAAIaAAkJlRu5HQCJAgAaAAkJlRu5HQCJAgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIHAAYJaRP8GQArAQAHAAYJaRP8GQArAQAAAA==.',
Tu='Turl:BAAALgAECgYJEgABLgAECgcJIQAWAHMfAA==.Turlo:BAABLgAECn8hAAIWAAYJcx83LADWAQAWAAYJcx83LADWAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAUJEgAnAC8QAA==.Twostep:BAACLgAFFH8SAAInAAUJLxDhBQAmAQAnAAUJLxDhBQAmAQAuAAQKfyoAAicACQnzGRUDACwCACcACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8SAAIaAAcJ8h90CwD2AQAaAAcJ8h90CwD2AQAuAAQKfyIAAhoABwmkJTsYANgCABoABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8LAAIEAAMJDBRzNAC2AAAEAAMJDBRzNAC2AAAuAAQKfy4AAgQACQmTHcITAGwCAAQACQmTHcITAGwCAAAA.',
Ur='Ursos:BAABLgAECn8gAAIFAAcJfBhxFQCWAQAFAAcJfBhxFQCWAQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8XAAMUAAkJERhCGwDzAQAUAAkJERhCGwDzAQAZAAEJ1gFSTAApAAAAAA==.Valiantinter:BAAALgAECgEJAQAAAA==.Vallatris:BAAALgAECgcJDgAAAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8wAAIXAAgJMhUWUADlAQAXAAgJMhUWUADlAQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgADCgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgADCgIJBAABLgAECgcJIAAFAHwYAA==.Viracocha:BAABLgAFFH8JAAMKAAQJ/RrwPQDYAAAKAAMJtxjwPQDYAAAiAAEJCBqWFQBLAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgcJDwABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAFFAIJAgAAAA==.',
Vu='Vulcin:BAAALgAECgEJAQABLgAFFAMJCwAXANATAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIbAAYJdRpmVgB4AQAbAAYJdRpmVgB4AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.Whitegirls:BAAALgAECgIJAgAAAA==.',
Wi='Winderkin:BAAALgADCgMJAwAAAA==.Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIeAAcJMhIBLABpAQAeAAcJMhIBLABpAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8WAAIKAAcJmRtKHgBPAgAKAAcJmRtKHgBPAgABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8oAAIPAAkJVRyJBgCaAgAPAAkJVRyJBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQcAAYJvyB9DABwAQARAAUJcx6VXACzAQAcAAQJByJ9DABwAQAQAAEJAABYYABOAAABLgAFFAIJBAABAAAAAA==.Zandramadas:BAABLgAECn9GAAQGAAkJFiA3FAAlAgAGAAkJFiA3FAAlAgAJAAgJqRloLAD9AQAFAAcJXxLIHwA8AQAAAA==.Zaraline:BAABLgAECn88AAINAAkJjRxkFgCVAgANAAkJjRxkFgCVAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIIAAgJrBsGPAAJAgAIAAgJrBsGPAAJAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAAALgAECgQJBwAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIIAAYJbBZilwAxAQAIAAYJbBZilwAxAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIXAAkJUR74HACoAgAXAAkJUR74HACoAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECggJGwAVAFgYAA==.',
['Øv']='Øval:BAAALgAECgEJAQAAAA==.',
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
