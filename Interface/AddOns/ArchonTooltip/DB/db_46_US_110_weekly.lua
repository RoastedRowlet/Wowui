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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Holy','Monk-Mistweaver','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Druid-Guardian','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Preservation','Druid-Feral','Paladin-Retribution','Warlock-Affliction','Monk-Brewmaster','Priest-Discipline','Paladin-Protection','DemonHunter-Havoc','Shaman-Enhancement','DemonHunter-Devourer','DeathKnight-Blood','Rogue-Assassination','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1OGQB1AQACAAkJsQ1OGQB1AQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIDAAYJ3xWqJQBPAQADAAYJ3xWqJQBPAQAAAA==.',
Al='Alex:BAABLgAFFH8FAAIEAAQJ5RNzFQAeAQAEAAQJ5RNzFQAeAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAAALgAECgYJCgAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn80AAIFAAgJKR2GLQACAgAFAAgJKR2GLQACAgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIGAAMJBxnLJADqAAAGAAMJBxnLJADqAAAuAAQKfyMAAwYACQn9IScJAP4CAAYACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAGAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAIIAAYJVht4KADDAQAIAAYJVht4KADDAQAAAA==.Amorsith:BAAALgAECgcJEAAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8HAAMJAAMJQxlfKQCfAAAJAAIJORZfKQCfAAAKAAEJVh/tHwBVAAAuAAQKfyAAAwoACAl0IqcKAOkBAAoABgmGIKcKAOkBAAkABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgQJCwAAAA==.Angrycrack:BAAALgAECggJEwAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxodHwB0AQAHAAYJzxodHwB0AQAAAA==.Anjunabeets:BAABLgAFFH8aAAQLAAcJ6ho9AwDcAQALAAYJCR49AwDcAQAMAAUJGw2fCQCAAQANAAEJlgi7IwBJAAAAAA==.Anthran:BAABLgAECn8mAAMOAAkJqg8jHwBYAQAOAAYJzQ4jHwBYAQAPAAcJJAziYgA7AQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.',
Ar='Archos:BAAALgAECgEJAwAAAA==.Arcscythe:BAABLgAECn8fAAIQAAgJkhdpAgDUAQAQAAgJkhdpAgDUAQAAAA==.Arctron:BAAALgAECgYJBwABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgEJAwAAAA==.Artoo:BAAALgAECgcJCwAAAA==.',
As='Astralpanda:BAABLgAECn8YAAIRAAgJKAqOMgAYAQARAAgJKAqOMgAYAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8gAAISAAYJng05MwAxAQASAAYJng05MwAxAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECggJIAATAEkZAA==.Baer:BAABLgAECn8dAAIUAAgJ9gcRIQDCAAAUAAgJ9gcRIQDCAAAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn8sAAIVAAkJPg+BHADSAQAVAAkJPg+BHADSAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8YAAIPAAYJ0AlqhgDvAAAPAAYJ0AlqhgDvAAAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAWAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8XAAIXAAYJ1xwOFQC8AQAXAAYJ1xwOFQC8AQAAAA==.Bauchelaine:BAABLgAECn8aAAIPAAYJaQ/4dAATAQAPAAYJaQ/4dAATAQAAAA==.Bavunga:BAABLgAECn8fAAIYAAgJoSG3AgD7AgAYAAgJoSG3AgD7AgAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAECgQJBAAAAA==.Beoron:BAACLgAFFH8HAAIZAAMJoxxqBQAeAQAZAAMJoxxqBQAeAQAuAAQKfy0AAhkACQlbJV0AAGsDABkACQlbJV0AAGsDAAAA.Bettyßastion:BAABLgAECn8kAAIaAAgJQh2nNQDiAQAaAAgJQh2nNQDiAQAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJAQABAAAAAA==.Bisoncrusher:BAAALgAECgYJDwAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAAALgAECgIJAgABLgAFFAMJCwAIADcXAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMNAAgJQSVlAgAeAwANAAgJQSVlAgAeAwAMAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAAALgAECgcJDQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECggJEgAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8YAAMLAAcJZhOQTwBZAQALAAcJZhOQTwBZAQANAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgEJAQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAABLgAECn8fAAIIAAgJhxBRNQB9AQAIAAgJhxBRNQB9AQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQAAAA==.Cannyon:BAAALgADCgUJBQAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJRAACAE4lAA==.Ceruledge:BAAALgAECgYJDwABLgAFFAMJBgATADwWAA==.',
Ch='Chaboomy:BAECLgAFFH8WAAIHAAYJqRJjCQB/AQAHAAYJqRJjCQB/AQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn8rAAIJAAkJwhY4EQAjAgAJAAkJwhY4EQAjAgAAAA==.Chopper:BAACLgAFFH8GAAIZAAMJhRYnBgAMAQAZAAMJhRYnBgAMAQAuAAQKfyYAAhkACQn9IWYDAAEDABkACQn9IWYDAAEDAAEuAAUUAwkLABsAbwkA.Chromate:BAABLgAFFH8JAAIcAAMJRBCrKADQAAAcAAMJRBCrKADQAAAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMDAAcJfBWpJgC4AQADAAcJ5hSpJgC4AQAdAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn89AAIZAAkJbiYnAACIAwAZAAkJbiYnAACIAwAAAA==.Conkerin:BAAALgAFFAIJAgAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJCAAAAA==.',
Cu='Curzz:BAAALgAECggJCAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgIJBAAAAA==.Cynis:BAAALgAECgIJAgAAAA==.',
Da='Dad:BAAALgAECgEJAQAAAA==.Daddy:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIGAAgJVgqCTgBqAQAGAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgUJDwABLgAECgYJBgABAAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAAALgAECgYJBwABLgAFFAEJAQABAAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQOAAkJwhhuGwByAQAPAAgJAhK+QgCUAQAOAAcJXhZuGwByAQAbAAIJ1RgVGACCAAAAAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAUJFQACAAIiAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8pAAIFAAkJMRipIQA7AgAFAAkJMRipIQA7AgAAAA==.Deepman:BAAALgAECgQJBAABLgAECggJHwALAPoaAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8/AAMeAAkJdyStAAA7AwAeAAkJdyStAAA7AwAVAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAALAHcDAA==.Disastrous:BAACLgAFFH8PAAILAAUJfhTEIAA2AQALAAUJfhTEIAA2AQAuAAQKfysAAgsACQk4IFIQAIcCAAsACQk4IFIQAIcCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJMgAfAJYhAA==.',
Do='Doomangel:BAABLgAECn8UAAIFAAYJuhFGfAAhAQAFAAYJuhFGfAAhAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAAALgAECgYJDAAAAA==.Doubleedge:BAAALgADCgIJAgABLgAECggJLwAWAGQbAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJPwAaAEkcAA==.Dragonslock:BAABLgAECn8VAAQPAAcJKQ6KegAHAQAPAAYJcA6KegAHAQAOAAIJxAxjMwAmAAAbAAEJiwO8KQAeAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAISAAcJDBGQJQCQAQASAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDAAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJCQAAAA==.Drumboppie:BAABLgAECn8iAAMGAAkJoxAyPwBNAQAGAAcJ4Q8yPwBNAQAHAAgJ9QZ6RACkAAAAAA==.Drunkenmasta:BAAALgAECgUJCwABLgAECggJHwALAPoaAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8VAAICAAUJAiJHBgCaAQACAAUJAiJHBgCaAQAuAAQKfzEAAgIACQkmJVYBADYDAAIACQkmJVYBADYDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAUJFQACAAIiAA==.',
['Dø']='Døc:BAABLgAECn9BAAQIAAkJ9hlHCwC5AgAIAAkJ9hlHCwC5AgAgAAcJEAwfFgBcAQARAAkJHwuzKwA+AQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIeAAMJWQ7oBgC9AAAeAAMJWQ7oBgC9AAAuAAQKfyAAAx4ACAl0G/8QALcBAB4ABwlyGP8QALcBABoABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8TAAMPAAYJ3xHRFwB9AQAPAAYJ3xHRFwB9AQAOAAEJagETGwBAAAAuAAQKfykAAw8ACAl7HHQ1ADYCAA8ACAl7HHQ1ADYCAA4AAQkAAMRfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8fAAIhAAkJMhnjKgBVAgAhAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9EAAIiAAkJPR3cBQCHAgAiAAkJPR3cBQCHAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8LAAQbAAMJbwn5BgCJAAAPAAMJwQaJWgDGAAAOAAIJ6Af9DACLAAAbAAIJmgf5BgCJAAAuAAQKfygABA4ACQnzGr0fAFQBAA8ACAliGFtUAMoBAA4ABwmiFL0fAFQBABsAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJCwAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAQJCwAjAEwhAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJAwABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJBgAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAECggJHQAiAAEXAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAECggJHQAiAAEXAA==.Fisterdobble:BAABLgAECn82AAIWAAkJsxUsPgDgAQAWAAkJsxUsPgDgAQAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Fleurdelys:BAAALgADCgkJMwAAAA==.',
Fo='Forestpump:BAAALgAECggJCAABLgAECggJEgABAAAAAA==.Forgeddemon:BAABLgAECn8XAAMcAAgJJgmlRQArAQAcAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgADCgcJBwABLgAECgkJIwAEAMUWAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIeAAkJ0h79BABdAgAeAAkJ0h79BABdAgAAAA==.Frostina:BAABLgAECn8bAAIWAAgJ8xNvTgCuAQAWAAgJ8xNvTgCuAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMXAAcJFBQ2GACUAQAXAAcJFBQ2GACUAQAJAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIeAAYJ1hdQEQBXAQAeAAYJ1hdQEQBXAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.',
Gl='Glimmawitz:BAAALgADCgQJBAAAAA==.Glo:BAAALgAECgUJCQAAAA==.Glofu:BAAALgAECgUJBQABLgAECgUJCQABAAAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAAALgAECgYJCQAAAA==.Goodboy:BAABLgAFFH8IAAILAAQJdwMxPADVAAALAAQJdwMxPADVAAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8cAAIGAAcJexGbOABrAQAGAAcJexGbOABrAQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8LAAIjAAQJTCFtAQCRAQAjAAQJTCFtAQCRAQAuAAQKfxoAAiMACAlcJBUCAOgCACMACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8WAAIIAAYJOhIfPwBPAQAIAAYJOhIfPwBPAQAAAA==.',
Gu='Gulaj:BAAALgAECggJEgAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQbAAkJRRNnBADwAQAPAAgJ1BFYRQD7AQAbAAkJNhJnBADwAQAOAAQJ2wfdLgAzAAAAAA==.',
He='Healgimp:BAABLgAECn8iAAIDAAkJihXYFADjAQADAAkJihXYFADjAQAAAA==.Healslux:BAABLgAECn8eAAIVAAkJvx/pBgDeAgAVAAkJvx/pBgDeAgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAEALgAECgEJAgABLgAFFAcJDQAdAC4NAA==.Hortzel:BAABLgAECn8UAAIPAAYJOA5NdwAOAQAPAAYJOA5NdwAOAQAAAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAAALgAECgcJCQAAAA==.Huntus:BAABLgAECn84AAMLAAkJsCOvAwAkAwALAAkJsCOvAwAkAwAMAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIaAAgJHhZiQQC6AQAaAAgJHhZiQQC6AQAAAA==.',
Ic='Icy:BAAALgAECgUJBgAAAA==.',
Il='Illadelf:BAAALgADCgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgASAAcJjxKLIgCqAQAAAA==.Impostor:BAABLgAECn8pAAITAAkJZx5OBgCuAgATAAkJZx5OBgCuAgAAAA==.',
In='Indabow:BAABLgAECn8gAAILAAkJbRopKAAXAgALAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAcAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8aAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAhAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAAALgAFFAIJAwAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAAALgAECgQJCwAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8KAAMCAAQJUhuFDgBNAQACAAQJUhuFDgBNAQAjAAEJBweTDABMAAAuAAQKfxsAAwIACAmEHN8YAHkBAAIABwkTHd8YAHkBACMABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8YAAIcAAYJlg6ZDgBYAQAcAAYJlg6ZDgBYAQAuAAQKfyQAAhwACAnxElshAPcBABwACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgUJBQABLgAECgYJBgABAAAAAA==.Juul:BAAALgAECgkJEwAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAEJAQABAAAAAA==.Jìmothy:BAAALgAFFAEJAQAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8tAAIhAAkJdB3zFQDTAgAhAAkJdB3zFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8OAAIiAAQJQxVIEAALAQAiAAQJQxVIEAALAQAuAAQKfxUAAiIACAnWGQAPABwCACIACAnWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Kidslaps:BAABLgAECn8dAAIcAAgJOwzpJQBAAQAcAAgJOwzpJQBAAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgADCgQJBAABLgAFFAEJAQABAAAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAABLgAECn8jAAMEAAkJxRaiIACuAQAEAAkJxRaiIACuAQAcAAEJSgxAbQA/AAAAAA==.',
La='Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8fAAILAAgJ+hojJAACAgALAAgJ+hojJAACAgAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8bAAQPAAgJXwahewAFAQAPAAcJzgWhewAFAQAbAAEJ8AknMQA8AAAOAAIJLwFybQA6AAAAAA==.Lemegegen:BAABLgAECn8kAAIPAAkJZxdiGwBEAgAPAAkJZxdiGwBEAgAAAA==.',
Lh='Lhux:BAABLgAECn8tAAILAAgJ3iG9DADZAgALAAgJ3iG9DADZAgAAAA==.Lhuxi:BAACLgAFFH8FAAISAAMJPAwYKwDSAAASAAMJPAwYKwDSAAAuAAQKfxYAAhIABgl2F/IpAEABABIABgl2F/IpAEABAAEuAAQKCAktAAsA3iEA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAAALgAECgQJBAAAAA==.Lightisright:BAAALgAECgIJAgAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAAALgAECgYJDQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8NAAIHAAQJHhKYFAAnAQAHAAQJHhKYFAAnAQAuAAQKfyoAAgcACAmTH4UKAGACAAcACAmTH4UKAGACAAAA.Lorgar:BAAALgAECgQJBAAAAA==.',
Lu='Luca:BAABLgAECn8ZAAIGAAgJrwiuTwAJAQAGAAgJrwiuTwAJAQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgADCgYJBgAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJQQAIAPYZAA==.Lyxxie:BAABLgAECn84AAMFAAkJiRrQNwBXAgAFAAkJiRrQNwBXAgAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8vAAIWAAgJZBteLgAdAgAWAAgJZBteLgAdAgAAAA==.Mageus:BAAALgAECgEJAQAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECgYJFAAeANYXAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAAALgAECgcJEAABLgAFFAMJCwAIADcXAA==.Metsutan:BAABLgAECn9EAAICAAkJTiVsAQAuAwACAAkJTiVsAQAuAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgADCgUJDAAAAA==.',
Mo='Moggle:BAABLgAECn8kAAMTAAkJwA++GQCkAQATAAgJrxC+GQCkAQADAAUJAQgYYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAIWAAYJHxYLvABqAQAWAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIbAAgJFyJ9AgCWAgAbAAgJFyJ9AgCWAgAAAA==.Molathom:BAAALgAECgIJAwAAAA==.Monktastic:BAAALgADCgYJCgABLgAECggJLwAWAGQbAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Moskeebee:BAABLgAECn8UAAILAAcJyiUSEgCnAgALAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAAALgAECgcJEQAAAA==.',
['Må']='Måtthew:BAAALgADCgEJAQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8jAAIPAAcJggrCbQAjAQAPAAcJggrCbQAjAQAAAA==.',
Na='Nazuresh:BAAALgAECgUJBgABLgAECgcJIgADAMsWAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMPAAgJUxsEOQC2AQAPAAgJUxsEOQC2AQAOAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn81AAIOAAgJpRzFAgA1AgAOAAgJpRzFAgA1AgAAAA==.Nemriel:BAAALgAECgYJDwAAAA==.Newthilena:BAAALgADCgEJAQAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMhAAkJjxaiMQC1AQAhAAkJzxCiMQC1AQAfAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECggJDQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPAAJAKAlAA==.',
['Nä']='Nämeless:BAAALgAECgQJBAAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIdAAMJTBwwGgAMAQAdAAMJTBwwGgAMAQAuAAQKfywAAh0ACAlHIC0KAHwCAB0ACAlHIC0KAHwCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDAABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
On='Oneth:BAABLgAECn8UAAIbAAYJ3xBgDQAWAQAbAAYJ3xBgDQAWAQAAAA==.Onfleek:BAABLgAECn8lAAMDAAgJ1iI0BAAIAwADAAgJ1iI0BAAIAwATAAYJ9QpBNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8LAAIIAAMJNxfJKQDgAAAIAAMJNxfJKQDgAAAuAAQKfzkAAggACAl9G5soAO4BAAgACAl9G5soAO4BAAAA.',
Or='Orakrak:BAABLgAECn8eAAIJAAcJhQxHNwAaAQAJAAcJhQxHNwAaAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgADCgIJAQABLgAECgkJNAAdAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNAAdAB4lAA==.Parseval:BAABLgAECn80AAQdAAkJHiUCAQCsAwAdAAkJHiUCAQCsAwATAAgJ0hs3DQAyAgADAAQJPxsuQwAsAQAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPAAJAKAlAA==.Paws:BAABLgAECn88AAIJAAkJoCUkAQBRAwAJAAkJoCUkAQBRAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8UAAIVAAgJ6xVOOQAUAQAVAAgJ6xVOOQAUAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIgAAYJqg2tEwABAQAgAAYJqg2tEwABAQAAAA==.',
Pi='Pipsqueak:BAAALgADCgMJAwAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAECgQJCgAAAA==.Porkins:BAABLgAECn80AAMmAAkJqh1zAwA+AgAmAAkJqh1zAwA+AgAiAAcJhhF4JADZAAAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgADCgkJCQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJAwABAAAAAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8FAAIWAAMJHBFsVgD3AAAWAAMJHBFsVgD3AAAuAAQKfywAAhYACQktHvIPAMgCABYACQktHvIPAMgCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAEJAQABAAAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAABLgAECn8cAAIPAAgJliBYEACUAgAPAAgJliBYEACUAgAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMhAAgJjRIxSgBYAQAhAAgJ7xExSgBYAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDAABAAAAAA==.Raìdèn:BAABLgAECn8iAAMDAAcJyxbPLgCIAQADAAYJtBbPLgCIAQATAAUJhgX3RgCUAAAAAA==.',
Re='Replicate:BAAALgAECgcJEwAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAYJEwASAPYcAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgADCgQJBAABLgAECgkJLQALALUYAA==.',
Ry='Ryanx:BAACLgAFFH8OAAIVAAUJuB9UBwDYAQAVAAUJuB9UBwDYAQAuAAQKfy4AAhUACQldJd0AAJIDABUACQldJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgQJBgAAAA==.Ryri:BAABLgAECn8VAAIeAAcJgxPgEQBPAQAeAAcJgxPgEQBPAQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMdAAkJlgqwIgB+AQAdAAkJlgqwIgB+AQATAAIJGQvcUABkAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8tAAMcAAkJbAmJIABkAQAcAAkJbAmJIABkAQAEAAcJ0gzILgBDAQAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgcJEAAAAA==.Santoku:BAABLgAECn8QAAIhAAYJsxeETQBNAQAhAAYJsxeETQBNAQAAAA==.Sarah:BAACLgAFFH8GAAIdAAMJeRczHADxAAAdAAMJeRczHADxAAAuAAQKfzMAAh0ACQmyH98CAEcDAB0ACQmyH98CAEcDAAAA.Sassyface:BAABLgAECn88AAIOAAkJ7Q5qBwCOAQAOAAkJ7Q5qBwCOAQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgEJAQAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAGAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shaduw:BAACLgAFFH8YAAIXAAYJnR5mAwC2AQAXAAYJnR5mAwC2AQAuAAQKfyQAAxcACAnOIbMDABkDABcACAnOIbMDABkDAAkACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJjhCDHgBDAQACAAcJjhCDHgBDAQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.',
Si='Sibbrena:BAACLgAFFH8GAAITAAMJPBb/FQD3AAATAAMJPBb/FQD3AAAuAAQKfzEAAhMACQlpIPwFAC4DABMACQlpIPwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIWAAMJCBuqTgALAQAWAAMJCBuqTgALAQAuAAQKfycAAhYACQlNIykVACkDABYACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMVAAgJniPOEACMAgAVAAgJniPOEACMAgAaAAQJrRjm4ACDAAAAAA==.',
Sl='Slam:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJDgAAAA==.',
Sn='Snackychan:BAAALgAECggJEgAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spleen:BAABLgAECn8dAAQjAAgJDxf0BQDFAQAjAAgJyhX0BQDFAQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCgYJBgAAAA==.Spywo:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJCgAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAEJAQABAAAAAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAAALgAECgkJDwAAAA==.Stelthme:BAABLgAECn8UAAQjAAYJBw0CDwDwAAAjAAUJqA4CDwDwAAAnAAMJQwi5EQCFAAACAAEJGAiiXgA5AAABLgAFFAMJCQACAJEeAA==.Stormburst:BAAALgADCgIJAgABLgAFFAQJCwAjAEwhAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIWAAcJQyFKOgCNAgAWAAcJQyFKOgCNAgABLgAECggJFAANAEElAA==.',
Su='Susaki:BAAALgADCgEJAQAAAA==.',
Sw='Swan:BAAALgAECgYJCQABLgAFFAMJCAAWAPkHAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8fAAIXAAgJEB+LBwBCAgAXAAgJEB+LBwBCAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAABLgAECn8aAAMSAAkJSBqTCwBcAgASAAkJSBqTCwBcAgAlAAIJ0wF/RAAkAAABLgAFFAMJBwAZAKMcAA==.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgADCgMJAwAAAA==.',
Th='Theory:BAABLgAECn8rAAMFAAgJHxdYSQCfAQAFAAgJdxVYSQCfAQAiAAEJTh7YOgBVAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgEJAQAAAA==.',
Tj='Tj:BAAALgAECgcJBgAAAA==.',
To='Tomjim:BAACLgAFFH8TAAMSAAYJ9hwiFABLAQASAAUJRh0iFABLAQAYAAMJZQXtEwCLAAAuAAQKfyYABBIACAlAIwsLAMUCABIACAlAIwsLAMUCABgABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn8mAAINAAkJwxvnCgAxAgANAAkJwxvnCgAxAgAAAA==.Treevive:BAACLgAFFH8IAAIGAAQJghJAGgArAQAGAAQJghJAGgArAQAuAAQKfxkAAgYACAmaIEEcAFoCAAYACAmaIEEcAFoCAAAA.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn8lAAIaAAkJng9ePADKAQAaAAkJng9ePADKAQAAAA==.',
Ts='Tsinga:BAABLgAECn8VAAIZAAYJ5gyRFgD7AAAZAAYJ5gyRFgD7AAAAAA==.',
Tu='Turl:BAAALgAECgQJCAABLgAECgYJGgAVAGUeAA==.Turlo:BAABLgAECn8aAAIVAAYJZR43LADWAQAVAAYJZR43LADWAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECgMJBgABLgAFFAQJDAAnAHUJAA==.Twostep:BAACLgAFFH8MAAInAAQJdQnFAwAmAQAnAAQJdQnFAwAmAQAuAAQKfyoAAicACQnxGRUDACwCACcACQnxGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8RAAIaAAYJ8SDGBQDaAQAaAAYJ8SDGBQDaAQAuAAQKfyIAAhoABwmkJTsYANgCABoABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unshookable:BAACLgAFFH8FAAIEAAMJ0wygIQCsAAAEAAMJ0wygIQCsAAAuAAQKfysAAgQACQlZHV4NAGACAAQACQlZHV4NAGACAAAA.',
Ur='Ursos:BAAALgAECgcJEwAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8WAAMSAAkJERhzEwD2AQASAAkJERhzEwD2AQAYAAEJ1gFSTAApAAAAAA==.Vallatris:BAAALgAECgUJDgAAAA==.Valsande:BAAALgADCgkJHQAAAA==.Vargr:BAAALgADCgEJAQAAAA==.',
Ve='Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8iAAIWAAcJdw88bgBfAQAWAAcJdw88bgBfAQAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgADCgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgADCgIJAwAAAA==.Viracocha:BAAALgAFFAEJAQAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgYJBgABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAAALgAECgYJEwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJCwABAAAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8fAAIdAAcJ0hFQIQBkAQAdAAcJ0hFQIQBkAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCAAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAAALgAECgYJCwABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8mAAINAAkJMRzpCABUAgANAAkJMRzpCABUAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQbAAYJvyB9DABwAQAPAAUJcx6VXACzAQAbAAQJByJ9DABwAQAOAAEJAABYYABOAAAAAA==.Zandramadas:BAABLgAECn84AAMGAAkJMRpoLAD9AQAGAAgJqRloLAD9AQAHAAkJIx09EgDzAQAAAA==.Zaraline:BAABLgAECn8tAAILAAkJtRiAHgAhAgALAAkJtRiAHgAhAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCAAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8hAAIFAAgJWhoUTACWAQAFAAgJWhoUTACWAQAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIFAAYJbBaUbQBAAQAFAAYJbBaUbQBAAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEgAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8sAAIWAAgJKB7IIwBOAgAWAAgJKB7IIwBOAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECggJGgATAJoXAA==.',
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
