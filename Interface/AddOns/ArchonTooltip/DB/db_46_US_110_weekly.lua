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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Preservation','Paladin-Retribution','Warlock-Affliction','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','DemonHunter-Devourer','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIDAAYJ3xWkLgBBAQADAAYJ3xWkLgBBAQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIEAAQJIRUfIAAZAQAEAAQJIRUfIAAZAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAABLgAECn8XAAQFAAkJHwYJNgCnAAAGAAYJEwfoTQC4AAAFAAkJywIJNgCnAAAHAAQJBgYvLQCKAAAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9CAAIIAAkJgB0VHwB7AgAIAAkJgB0VHwB7AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIJAAMJBxmMMADfAAAJAAMJBxmMMADfAAAuAAQKfyMAAwkACQn9IScJAP4CAAkACQn9IScJAP4CAAYAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAJAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAIKAAYJVhuYNgC7AQAKAAYJVhuYNgC7AQAAAA==.Amorsith:BAAALgAECggJEQAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8MAAMLAAMJfR1CNQClAAALAAIJkBxCNQClAAAMAAEJVh/cMABRAAAuAAQKfyUAAwwACQnQIvcEAKkCAAwACAm+IPcEAKkCAAsABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgUJDAAAAA==.Angrycrack:BAABLgAECn8XAAICAAgJsBnMFwDEAQACAAgJsBnMFwDEAQAAAA==.Animuggus:BAEBLgAECn8UAAIGAAYJzxqkKQBqAQAGAAYJzxqkKQBqAQAAAA==.Anjunabeets:BAABLgAFFH8gAAQNAAgJSBunCQDPAQANAAYJih6nCQDPAQAOAAYJYQ+fCQCAAQAPAAIJ+w5XIwCaAAAAAA==.Anthran:BAABLgAECn8mAAMQAAkJqw8jHwBYAQAQAAYJzQ4jHwBYAQARAAcJJQxMeQA8AQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgEJAQABLgAECgkJMgALAAEXAA==.Archos:BAAALgAECgEJBAAAAA==.Arcscythe:BAABLgAECn8kAAISAAkJ4BZFAgAhAgASAAkJ4BZFAgAhAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgEJAwAAAA==.Artoo:BAAALgAECggJDAAAAA==.',
As='Asleep:BAAALgAECgMJAwABLgAECgkJMgALAAEXAA==.Assaulter:BAAALgAECgIJAQABLgAFFAEJAQABAAAAAA==.Astralpanda:BAABLgAECn8ZAAITAAgJKAo6QQATAQATAAgJKAo6QQATAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8nAAIUAAgJjQ77LQBlAQAUAAgJjQ77LQBlAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAVADEYAA==.Baer:BAABLgAECn8eAAIFAAgJ9gfvMQC6AAAFAAgJ9gfvMQC6AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn82AAIWAAkJWA+DJQDGAQAWAAkJWA+DJQDGAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8gAAIRAAcJAQt3ggAqAQARAAcJAQt3ggAqAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAXAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8ZAAIYAAcJARyoEwCbAQAYAAcJARyoEwCbAQAAAA==.Bauchelaine:BAABLgAECn8eAAIRAAgJIw/6WwB/AQARAAgJIw/6WwB/AQAAAA==.Bavunga:BAABLgAECn8pAAIZAAkJhCBmAgA6AwAZAAkJhCBmAgA6AwAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAFFAEJAQAAAA==.Beoron:BAACLgAFFH8HAAIHAAMJoxxpCQD3AAAHAAMJoxxpCQD3AAAuAAQKfy0AAgcACQlbJcUAAFgDAAcACQlbJcUAAFgDAAEuAAUUBAkHABQAgREA.Bettyßastion:BAABLgAECn8xAAIaAAkJwB81FgCoAgAaAAkJwB81FgCoAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJCwABAAAAAA==.Bioenergy:BAAALgAECgkJCwAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJCwABAAAAAA==.Bisoncrusher:BAAALgAECgcJDwAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAABLgAECn8WAAIVAAgJhAenQADoAAAVAAgJhAenQADoAAABLgAFFAMJFAAKAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMPAAgJQSVlAgAeAwAPAAgJQSVlAgAeAwAOAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAABLgAECn8VAAITAAgJtBLhJgCbAQATAAgJtBLhJgCbAQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECggJEwAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIGAAgJehYaKQC2AQAGAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMNAAcJZxNLaABaAQANAAcJZxNLaABaAQAPAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgQJBQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAABLgAECn8kAAIKAAkJgg9BOwClAQAKAAkJgg9BOwClAQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Cannyon:BAAALgAECgMJAwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJRAACAE4lAA==.Ceruledge:BAAALgAECgYJEQABLgAFFAMJBgAVADwWAA==.',
Ch='Chaboomy:BAECLgAFFH8WAAIGAAYJqRI8EwBUAQAGAAYJqRI8EwBUAQAuAAQKfx0AAgYACAkFIOcPAKQCAAYACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn8yAAILAAkJARf/FwAaAgALAAkJARf/FwAaAgAAAA==.Chopper:BAACLgAFFH8OAAIHAAQJjxp/BABQAQAHAAQJjxp/BABQAQAuAAQKfyYAAgcACQn9IWYDAAEDAAcACQn9IWYDAAEDAAEuAAUUBAkOABsASQoA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAIcAAQJsxHpIQAPAQAcAAQJsxHpIQAPAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMDAAcJfBWpJgC4AQADAAcJ5hSpJgC4AQAdAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn89AAIHAAkJbiZtAAB3AwAHAAkJbiZtAAB3AwAAAA==.Colmoore:BAAALgAFFAEJAQABLgAFFAQJCQARANoSAA==.Conkerin:BAAALgAFFAIJBAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJDQAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAeAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCAABLgAFFAIJAwABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIJAAgJVgqCTgBqAQAJAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgYJDwAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8GAAIKAAIJ0CJRQADIAAAKAAIJ0CJRQADIAAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQQAAkJwhhuGwByAQARAAgJAhJIVACTAQAQAAcJZBZuGwByAQAbAAIJ0RgwJAByAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAQJEgAfABojAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAUJGgACAAIiAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIIAAkJCxuEIgBpAgAIAAkJCxuEIgBpAgAAAA==.Deepman:BAAALgAFFAEJAQAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8/AAMgAAkJdyRJAQAxAwAgAAkJdyRJAQAxAwAWAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAANAHcDAA==.Disastrous:BAACLgAFFH8SAAINAAYJoxQKFQCFAQANAAYJoxQKFQCFAQAuAAQKfzMAAg0ACQlCIMYRAKoCAA0ACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJOAAeAKMiAA==.',
Do='Doomangel:BAABLgAECn8UAAIIAAYJuhHKoQAUAQAIAAYJuhHKoQAUAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAAALgAECgYJDAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJFAAKAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAXALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJTAAaAGMfAA==.Dragonslock:BAABLgAECn8VAAQRAAcJKQ5vmAACAQARAAYJcA5vmAACAQAQAAIJxAwmOQAwAAAbAAEJiwP0OwAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIUAAcJDBGQJQCQAQAUAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMJAAkJtxHCQAB8AQAJAAcJRBHCQAB8AQAGAAgJ9QZxUACvAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAFFAEJAQABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8aAAICAAUJAiLpDQB7AQACAAUJAiLpDQB7AQAuAAQKfzEAAgIACQkmJdUCABUDAAIACQkmJdUCABUDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAUJGgACAAIiAA==.',
['Dø']='Døc:BAABLgAECn9JAAQKAAkJ9xliEQCsAgAKAAkJ9xliEQCsAgATAAkJchHAHwDLAQAhAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIgAAMJWQ6CCgC1AAAgAAMJWQ6CCgC1AAAuAAQKfyAAAyAACAl0G/8QALcBACAABwlyGP8QALcBABoABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8TAAMRAAYJ3xEPKgBxAQARAAYJ3xEPKgBxAQAQAAEJagETGwBAAAAuAAQKfykAAxEACAl7HHQ1ADYCABEACAl7HHQ1ADYCABAAAQkAAMRfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8fAAIiAAkJMhnjKgBVAgAiAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9SAAIjAAkJUh3DCAB1AgAjAAkJUh3DCAB1AgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8OAAQbAAQJSQprDQCAAAARAAQJCAlxVAAJAQAQAAIJ6AdlEgCGAAAbAAIJmgdrDQCAAAAuAAQKfy4ABBEACQn5GrQ9ANgBABEACAloGLQ9ANgBABAACAmiFL0fAFQBABsAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAQJEgAfABojAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJCAABLgAECgYJDwABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAFFAIJCAAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCAAjAMoaAA==.Fisterdobble:BAABLgAECn9BAAIXAAkJ2xZKRwDuAQAXAAkJ2xZKRwDuAQAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAAALgAECggJDAABLgAECggJGgAEAA0jAA==.Forgeddemon:BAABLgAECn8XAAMcAAgJJgmlRQArAQAcAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAMJBwAEANgWAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIgAAkJ0h6MBgB/AgAgAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIXAAgJGRTrYQCiAQAXAAgJGRTrYQCiAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMYAAcJFBQ2GACUAQAYAAcJFBQ2GACUAQALAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIgAAYJ1hcHFwBNAQAgAAYJ1hcHFwBNAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJBAAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8VAAIaAAcJBxpQYQCUAQAaAAcJBxpQYQCUAQAAAA==.Goodboy:BAABLgAFFH8IAAINAAQJdwO5VwDJAAANAAQJdwO5VwDJAAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8jAAIJAAcJVhLqQQB3AQAJAAcJVhLqQQB3AQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8SAAIfAAQJGiOwAQCeAQAfAAQJGiOwAQCeAQAuAAQKfxoAAh8ACAlcJBUCAOgCAB8ACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8aAAIKAAYJ/xSARwB0AQAKAAYJ/xSARwB0AQAAAA==.',
Gu='Gulaj:BAABLgAECn8UAAINAAgJZRjISQCMAQANAAgJZRjISQCMAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQbAAkJRRO7BwDTAQARAAgJ1RFYRQD7AQAbAAkJNxK7BwDTAQAQAAQJ2wdiOQAwAAAAAA==.',
He='Healgimp:BAABLgAECn8iAAIDAAkJixUwHADNAQADAAkJixUwHADNAQAAAA==.Healslux:BAABLgAECn8eAAIWAAkJvx9YCwDDAgAWAAkJvx9YCwDDAgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAAALgAECgEJAgABLgAFFAcJDQAdADANAA==.Hortzel:BAABLgAECn8UAAIRAAYJOA4blAAKAQARAAYJOA4blAAKAQAAAA==.Hotrollz:BAAALgAECgEJBAABLgAECgkJGQAJAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAABLgAECn8VAAIaAAcJxRjPVACzAQAaAAcJxRjPVACzAQAAAA==.Huntus:BAABLgAECn84AAMNAAkJsCPLCAAAAwANAAkJsCPLCAAAAwAOAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIaAAgJHxYdXAChAQAaAAgJHxYdXAChAQAAAA==.',
Ic='Icy:BAAALgAECgUJBgAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAUAAcJjxKLIgCqAQAAAA==.Impostor:BAABLgAECn8yAAIVAAkJdiANBgDaAgAVAAkJdiANBgDaAgAAAA==.',
In='Indabow:BAABLgAECn8gAAINAAkJbRopKAAXAgANAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAcAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIeAAgJihRTGQD7AQAeAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8dAAMeAAgJFhpXEQBUAgAeAAgJFhpXEQBUAgAiAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIiAAIJvCGeWADEAAAiAAIJvCGeWADEAAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8jAAIkAAkJ0BojCwB9AgAkAAkJ0BojCwB9AgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8SAAMCAAUJVxtrFABKAQACAAUJVxtrFABKAQAfAAEJBwcLEABFAAAuAAQKfxsAAwIACAmEHPohAOkBAAIABwkRHfohAOkBAB8ABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8YAAIcAAYJlg4tFwBIAQAcAAYJlg4tFwBIAQAuAAQKfyQAAhwACAnxElshAPcBABwACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJCwABLgAECgYJDwABAAAAAA==.Juul:BAABLgAECn8YAAIUAAkJ2RVeFAAgAgAUAAkJ2RVeFAAgAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAQJBwAVAA4GAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAQJBwAVAA4GAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgADCggJCAABLgAECgYJCgABAAAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8wAAIiAAkJdB3zFQDTAgAiAAkJdB3zFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8WAAIjAAUJVxnfEwAhAQAjAAUJVxnfEwAhAQAuAAQKfxUAAiMACAnWGQAPABwCACMACAnWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Kidslaps:BAABLgAECn8eAAIcAAgJTAy5LABDAQAcAAgJTAy5LABDAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgAECgkJCwABLgAFFAQJBwAVAA4GAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8HAAIEAAMJ2BaUKgDMAAAEAAMJ2BaUKgDMAAAuAAQKfyYABAQACQkbF6IgAK4BAAQACQkbF6IgAK4BABwAAQlKDG9/AD0AACQAAQk9D/WIADUAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8hAAINAAkJQxnEJgAuAgANAAkJQxnEJgAuAgABLgAFFAEJAQABAAAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8kAAQRAAgJagcRgwApAQARAAcJagcRgwApAQAQAAUJxASJKABjAAAbAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAIRAAkJiBrNGgB2AgARAAkJiBrNGgB2AgAAAA==.',
Lh='Lhux:BAABLgAECn8uAAINAAgJ/iO9DADZAgANAAgJ/iO9DADZAgAAAA==.Lhuxi:BAACLgAFFH8NAAIUAAQJwBMEJgANAQAUAAQJwBMEJgANAQAuAAQKfyUAAhQACQleHX0JAKgCABQACQleHX0JAKgCAAEuAAQKCAkuAA0A/iMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAAALgAFFAIJAwAAAA==.Lightisright:BAAALgAECgYJBgAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIaAAgJaBAmZgCJAQAaAAgJaBAmZgCJAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8TAAIGAAUJ9BT2HAAMAQAGAAUJ9BT2HAAMAQAuAAQKfysAAgYACAlcINwNAGcCAAYACAlcINwNAGcCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIJAAkJdA0MQQB7AQAJAAkJdA0MQQB7AQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAQAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSQAKAPcZAA==.Lyxxie:BAABLgAECn89AAMIAAkJihrQNwBXAgAIAAkJihrQNwBXAgAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIXAAkJsBzyJAByAgAXAAkJsBzyJAByAgAAAA==.Mageus:BAAALgAECgEJAQAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECgcJFAAgANYXAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8bAAILAAgJCQvHOABOAQALAAgJCQvHOABOAQABLgAFFAMJFAAKAMMYAA==.Metsutan:BAABLgAECn9EAAICAAkJTiUYAwALAwACAAkJTiUYAwALAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAABLgAECn8sAAMVAAkJvRKHHgCyAQAVAAgJFxSHHgCyAQADAAYJoQoYYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAIXAAYJHxYLvABqAQAXAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIbAAgJNCJ9AgCWAgAbAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCQAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAXALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAQJBwAVAA4GAA==.Moskeebee:BAABLgAECn8UAAINAAcJyiUSEgCnAgANAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8VAAMKAAgJrgFHgAC9AAAKAAgJrgFHgAC9AAATAAQJewGUgQBQAAAAAA==.',
['Må']='Måtthew:BAAALgADCgYJBQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAIRAAcJoQpSgQAsAQARAAcJoQpSgQAsAQAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.Nazuresh:BAAALgAECgUJBgABLgAECggJLQADAFYTAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMRAAgJVBv0QwAAAgARAAgJVBv0QwAAAgAQAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn9GAAMRAAkJZxy/EQCxAgARAAkJcBu/EQCxAgAQAAgJpRxXBAAkAgAAAA==.Nemriel:BAAALgAECgcJDwAAAA==.Newthilena:BAAALgAECgQJBQAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMiAAkJjxaePgC2AQAiAAkJzxCePgC2AQAeAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECggJDQAAAA==.Nossem:BAAALgAECgEJAQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPAALAKAlAA==.Nymera:BAAALgADCgEJAQABLgAECgcJIAAFAHwYAA==.',
['Nä']='Nämeless:BAAALgAFFAEJAQAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIdAAMJTBxUIwD/AAAdAAMJTBxUIwD/AAAuAAQKfywAAh0ACAlGIL8OAGMCAB0ACAlGIL8OAGMCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ol='Olgaa:BAAALgAECgEJAQAAAA==.',
On='Oneth:BAABLgAECn8UAAIbAAYJ3xDlEwAMAQAbAAYJ3xDlEwAMAQAAAA==.Onfleek:BAABLgAECn8yAAMDAAgJXCP/BQAFAwADAAgJXCP/BQAFAwAVAAYJJA1BNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8UAAIKAAMJwximOQDgAAAKAAMJwximOQDgAAAuAAQKf0MAAgoACQkdHaARAKkCAAoACQkdHaARAKkCAAAA.',
Or='Orakrak:BAABLgAECn8iAAILAAkJLhAeJAC/AQALAAkJLhAeJAC/AQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgcJCwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNAAdAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNAAdAB4lAA==.Parseval:BAABLgAECn80AAQdAAkJHiXLAQCZAwAdAAkJHiXLAQCZAwAVAAgJ0Rt9EwAYAgADAAQJPxsuQwAsAQAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPAALAKAlAA==.Paws:BAABLgAECn88AAILAAkJoCW5AgA3AwALAAkJoCW5AgA3AwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIWAAgJORiDNwBYAQAWAAgJORiDNwBYAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIhAAYJqg13GwD8AAAhAAYJqg13GwD8AAAAAA==.',
Pi='Pipsqueak:BAAALgAECgQJBAAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAEJAgAAAA==.Porkins:BAABLgAECn88AAMjAAkJGSDfCAByAgAjAAgJmx/fCAByAgAmAAkJqh0gBgAdAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAECgYJBgAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAiALwhAA==.',
Ps='Psyndar:BAAALgAECgEJAQABLgAFFAQJEQAKAGkZAA==.Psyndra:BAAALgAECgYJCQABLgAFFAQJEQAKAGkZAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8LAAIXAAMJ0BMYbgDlAAAXAAMJ0BMYbgDlAAAuAAQKfzEAAhcACQkRH9AUAMcCABcACQkRH9AUAMcCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAQJBwAVAA4GAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8JAAIRAAQJ2hITUQARAQARAAQJ2hITUQARAQAuAAQKfyoAAhEACAmDIpkQALsCABEACAmDIpkQALsCAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMiAAgJjRJUXABaAQAiAAgJ7xFUXABaAQAeAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8tAAMDAAgJVhPHHgC3AQADAAgJVhPHHgC3AQAVAAUJ2gXKWwB4AAAAAA==.',
Re='Replicate:BAABLgAECn8iAAILAAkJvSGSBAAKAwALAAkJvSGSBAAKAwAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAYJEwAUAPYcAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJPAANAI0cAA==.',
Ry='Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8TAAIWAAYJkyAxBgArAgAWAAYJkyAxBgArAgAuAAQKfzEAAhYACQmNJd0AAJIDABYACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJCAAAAA==.Ryri:BAABLgAECn8fAAIgAAcJXxWcEgCEAQAgAAcJXxWcEgCEAQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMdAAkJlgqwIgB+AQAdAAkJlgqwIgB+AQAVAAIJGQuoawBIAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMcAAkJbQk8KABeAQAcAAkJbQk8KABeAQAEAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJBQAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgcJEAAAAA==.Santoku:BAABLgAECn8QAAIiAAYJsxc1ZABFAQAiAAYJsxc1ZABFAQAAAA==.Sarah:BAACLgAFFH8OAAIdAAQJZhasHAA3AQAdAAQJZhasHAA3AQAuAAQKfzMAAh0ACQmxH3kEADQDAB0ACQmxH3kEADQDAAAA.Sassyface:BAABLgAECn9KAAIQAAkJ7Q4bCgCFAQAQAAkJ7Q4bCgCFAQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAJAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAAALgAECgYJCgAAAA==.Shaduw:BAACLgAFFH8YAAIYAAYJnR4OCACIAQAYAAYJnR4OCACIAQAuAAQKfyQAAxgACAnOIbMDABkDABgACAnOIbMDABkDAAsACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBAGJwBCAQACAAcJkBAGJwBCAQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJBwABLgAECgkJJgAQAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIVAAMJPBaGHgDaAAAVAAMJPBaGHgDaAAAuAAQKfzYAAhUACQlGIfwFAC4DABUACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIXAAMJCBsTagDuAAAXAAMJCBsTagDuAAAuAAQKfycAAhcACQlNIykVACkDABcACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMWAAgJniPOEACMAgAWAAgJniPOEACMAgAaAAQJrRgTFAF9AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMEAAgJDSPpCQC0AgAEAAcJnyLpCQC0AgAkAAYJJBW8LgA2AQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQfAAgJEBcPCAC6AQAfAAgJyhUPCAC6AQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJCgAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAQJBwAVAA4GAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIaAAkJjwQ9wwDmAAAaAAkJjwQ9wwDmAAAAAA==.Stelthme:BAABLgAECn8aAAQfAAYJIxijCgB4AQAfAAYJIxijCgB4AQAnAAMJQwjKFwB9AAACAAEJGAiiXgA5AAABLgAFFAMJDQACAF4lAA==.Stormburst:BAAALgADCgIJAgABLgAFFAQJEgAfABojAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIXAAcJQyFKOgCNAgAXAAcJQyFKOgCNAgABLgAECggJFAAPAEElAA==.',
Su='Susaki:BAAALgADCgEJAQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAAPAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8oAAIYAAkJox4CBQC7AgAYAAkJox4CBQC7AgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8HAAIUAAQJgREtKAAFAQAUAAQJgREtKAAFAQAuAAQKfyIAAxQACQl5IPoFAOYCABQACQl5IPoFAOYCACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgAECgMJAwAAAA==.',
Th='Theory:BAABLgAECn89AAMIAAkJhhicLwAtAgAIAAkJcxacLwAtAgAjAAIJ+hgZOgCRAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBgAAAA==.',
To='Tomjim:BAACLgAFFH8TAAMUAAYJ9hwJIAArAQAUAAUJRh0JIAArAQAZAAMJZQXtEwCLAAAuAAQKfyYABBQACAlAIwsLAMUCABQACAlAIwsLAMUCABkABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn8yAAIPAAkJwxsZDwAtAgAPAAkJwxsZDwAtAgAAAA==.Treevive:BAACLgAFFH8LAAIJAAUJiBMNGAB6AQAJAAUJiBMNGAB6AQAuAAQKfxkAAgkACAmaIEEcAFoCAAkACAmaIEEcAFoCAAAA.Trencough:BAAALgAECgYJCAAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn83AAIaAAkJbhZvMwAaAgAaAAkJbhZvMwAaAgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIHAAYJaRMRGAAsAQAHAAYJaRMRGAAsAQAAAA==.',
Tu='Turl:BAAALgAECgYJDgABLgAECgYJIQAWAHMfAA==.Turlo:BAABLgAECn8hAAIWAAYJcx83LADWAQAWAAYJcx83LADWAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAQJDwAnAC8QAA==.Twostep:BAACLgAFFH8PAAInAAQJLxAbBQAoAQAnAAQJLxAbBQAoAQAuAAQKfyoAAicACQnzGRUDACwCACcACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8RAAIaAAYJ8SA4EACpAQAaAAYJ8SA4EACpAQAuAAQKfyIAAhoABwmkJTsYANgCABoABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8LAAIEAAMJDBTcLQC4AAAEAAMJDBTcLQC4AAAuAAQKfy4AAgQACQmTHT4SAGsCAAQACQmTHT4SAGsCAAAA.',
Ur='Ursos:BAABLgAECn8gAAIFAAcJfBitEwCZAQAFAAcJfBitEwCZAQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8WAAMUAAkJERjbGQDtAQAUAAkJERjbGQDtAQAZAAEJ1gFSTAApAAAAAA==.Vallatris:BAAALgAECgYJDgAAAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8sAAIXAAcJWBJ9cQB9AQAXAAcJWBJ9cQB9AQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgADCgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgADCgIJBAABLgAECgcJIAAFAHwYAA==.Viracocha:BAABLgAFFH8JAAMKAAQJ/RrQOQDfAAAKAAMJtxjQOQDfAAAhAAEJCBorEgBRAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIiAAYJdRobUwB1AQAiAAYJdRobUwB1AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIdAAcJMhILKQBmAQAdAAcJMhILKQBmAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8VAAIKAAcJmRsQHABRAgAKAAcJmRsQHABRAgABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8oAAIPAAkJVRyJBgCaAgAPAAkJVRyJBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQbAAYJvyB9DABwAQARAAUJcx6VXACzAQAbAAQJByJ9DABwAQAQAAEJAABYYABOAAABLgAFFAIJAwABAAAAAA==.Zandramadas:BAABLgAECn8/AAQJAAkJMRpoLAD9AQAJAAgJqRloLAD9AQAGAAkJIx0EGQDsAQAFAAcJXxKPHABEAQAAAA==.Zaraline:BAABLgAECn88AAINAAkJjRz+EwCbAgANAAkJjRz+EwCbAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCQAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIIAAgJrBs2OAALAgAIAAgJrBs2OAALAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAAALgAECgQJBAAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIIAAYJbBYnkAAxAQAIAAYJbBYnkAAxAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIXAAkJUR5tGgCmAgAXAAkJUR5tGgCmAgAAAA==.',
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
