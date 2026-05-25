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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Holy','Monk-Mistweaver','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Druid-Guardian','Paladin-Holy','Mage-Frost','Warrior-Protection','Evoker-Preservation','Druid-Feral','Paladin-Retribution','DemonHunter-Devourer','Monk-Brewmaster','Priest-Discipline','DemonHunter-Havoc','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','DeathKnight-Blood','Rogue-Assassination','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIDAAYJ3xXfKwBGAQADAAYJ3xXfKwBGAQAAAA==.',
Al='Alex:BAABLgAFFH8FAAIEAAQJ5RNpHAASAQAEAAQJ5RNpHAASAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAAALgAECgcJEwAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn89AAIFAAkJgB2GGwB/AgAFAAkJgB2GGwB/AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIGAAMJBxlDKwDpAAAGAAMJBxlDKwDpAAAuAAQKfyMAAwYACQn9IScJAP4CAAYACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAGAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAIIAAYJVhu7MQC9AQAIAAYJVhu7MQC9AQAAAA==.Amorsith:BAAALgAECgcJEAAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8JAAMJAAMJQxlUMQCaAAAJAAIJORZUMQCaAAAKAAEJVh+WKQBRAAAuAAQKfyEAAwoACQnQIswHAFECAAoABwk2IcwHAFECAAkABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgUJDAAAAA==.Angrycrack:BAABLgAECn8VAAICAAgJaBiKFwC3AQACAAgJaBiKFwC3AQAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxpfJgBrAQAHAAYJzxpfJgBrAQAAAA==.Anjunabeets:BAABLgAFFH8bAAQLAAgJlBp/BwDAAQALAAYJDR5/BwDAAQAMAAYJYQ+fCQCAAQANAAEJlggXKQBIAAAAAA==.Anthran:BAABLgAECn8mAAMOAAkJqw8jHwBYAQAOAAYJzQ4jHwBYAQAPAAcJJQzrcABCAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.',
Ar='Archos:BAAALgAECgEJAwAAAA==.Arcscythe:BAABLgAECn8gAAIQAAkJ4BYQAgAfAgAQAAkJ4BYQAgAfAgAAAA==.Arctron:BAAALgAECgYJBwABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgEJAwAAAA==.Artoo:BAAALgAECgcJCwAAAA==.',
As='Asleep:BAAALgADCgIJAgABLgAECgkJMgAJAAEXAA==.Astralpanda:BAABLgAECn8ZAAIRAAgJKAoxPAAUAQARAAgJKAoxPAAUAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8gAAISAAYJng05MwAxAQASAAYJng05MwAxAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQATADEYAA==.Baer:BAABLgAECn8eAAIUAAgJ9gdcKwC9AAAUAAgJ9gdcKwC9AAAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn8tAAIVAAkJPg+/IgDIAQAVAAkJPg+/IgDIAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8bAAIPAAcJNgqWgAAjAQAPAAcJNgqWgAAjAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAWAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8YAAIXAAcJSBsPEwCTAQAXAAcJSBsPEwCTAQAAAA==.Bauchelaine:BAABLgAECn8aAAIPAAYJaQ/qiAATAQAPAAYJaQ/qiAATAQAAAA==.Bavunga:BAABLgAECn8mAAIYAAgJoSFqAwDzAgAYAAgJoSFqAwDzAgAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAECgQJBAAAAA==.Beoron:BAACLgAFFH8HAAIZAAMJoxxtBwANAQAZAAMJoxxtBwANAQAuAAQKfy0AAhkACQlbJZkAAGMDABkACQlbJZkAAGMDAAEuAAUUBAkHABIAgREA.Bettyßastion:BAABLgAECn8kAAIaAAgJQh2bQQDjAQAaAAgJQh2bQQDjAQAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJBQABAAAAAA==.Bioenergy:BAAALgAECgkJBQAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJBQABAAAAAA==.Bisoncrusher:BAAALgAECgYJDwAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAAALgAECgUJBwABLgAFFAMJDgAIAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMNAAgJQSVlAgAeAwANAAgJQSVlAgAeAwAMAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAABLgAECn8VAAIRAAgJtBJbIwCeAQARAAgJtBJbIwCeAQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAAALgAECggJEwAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMLAAcJZxPBYABXAQALAAcJZxPBYABXAQANAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgEJAQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQAAAA==.Calißoy:BAABLgAECn8kAAIIAAkJgg9cNgCmAQAIAAkJgg9cNgCmAQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJAgABAAAAAA==.Cannyon:BAAALgAECgMJAwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgADCgcJBwABLgAECgkJRAACAE4lAA==.Ceruledge:BAAALgAECgYJEQABLgAFFAMJBgATADwWAA==.',
Ch='Chaboomy:BAECLgAFFH8WAAIHAAYJqRIPDgBzAQAHAAYJqRIPDgBzAQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chingy:BAAALgAECgEJAQABLgAFFAUJEgAbAF8aAA==.Chips:BAABLgAECn8yAAIJAAkJARcMFQAjAgAJAAkJARcMFQAjAgAAAA==.Chopper:BAACLgAFFH8KAAIZAAQJUhq4AwBcAQAZAAQJUhq4AwBcAQAuAAQKfyYAAhkACQn9IWYDAAEDABkACQn9IWYDAAEDAAAA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8MAAIcAAQJZhCmHwARAQAcAAQJZhCmHwARAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMDAAcJfBWpJgC4AQADAAcJ5hSpJgC4AQAdAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn89AAIZAAkJbiZMAACBAwAZAAkJbiZMAACBAwAAAA==.Conkerin:BAAALgAFFAIJBAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJBAAAAA==.Crusible:BAAALgAECgUJDQAAAA==.',
Cu='Curzz:BAAALgAECggJCAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCQAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJAwABLgAECgkJHAAeAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJBwABLgAFFAEJAQABAAAAAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIGAAgJVgqCTgBqAQAGAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgUJDwABLgAECgYJBgABAAAAAA==.Darla:BAAALgADCgIJAwAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAAALgAFFAIJBAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQOAAkJwhhuGwByAQAPAAgJAhJoTQCcAQAOAAcJZBZuGwByAQAfAAIJ0Rh5HwB7AAAAAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAUJFgACAAIiAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8uAAIFAAkJShqeIwBUAgAFAAkJShqeIwBUAgAAAA==.Deepman:BAAALgAECgcJCgABLgAECgkJIQALAEMZAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8/AAMgAAkJdyQNAQA0AwAgAAkJdyQNAQA0AwAVAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAALAHcDAA==.Disastrous:BAACLgAFFH8QAAILAAUJfhT5LQAmAQALAAUJfhT5LQAmAQAuAAQKfzMAAgsACQlCIMYRAKoCAAsACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJOAAeAKMiAA==.',
Do='Doomangel:BAABLgAECn8UAAIFAAYJuhHQlgAUAQAFAAYJuhHQlgAUAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAAALgAECgYJDAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJDgAIAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAWALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJSAAaANseAA==.Dragonslock:BAABLgAECn8VAAQPAAcJKQ5mjwAGAQAPAAYJcA5mjwAGAQAOAAIJxAzQNQAwAAAfAAEJiwMuNQAeAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAISAAcJDBGQJQCQAQASAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJCQAAAA==.Drumboppie:BAABLgAECn8oAAMGAAkJtxFVPQB7AQAGAAcJRBFVPQB7AQAHAAgJ9QaRSgCwAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAECgkJIQALAEMZAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8WAAICAAUJAiJzCgCLAQACAAUJAiJzCgCLAQAuAAQKfzEAAgIACQkmJT0CACADAAIACQkmJT0CACADAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAUJFgACAAIiAA==.',
['Dø']='Døc:BAABLgAECn9JAAQIAAkJ9xkuDwCwAgAIAAkJ9xkuDwCwAgARAAkJchHDHADOAQAhAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIgAAMJWQ7qCAC4AAAgAAMJWQ7qCAC4AAAuAAQKfyAAAyAACAl0G/8QALcBACAABwlyGP8QALcBABoABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8TAAMPAAYJ3xHPIQB4AQAPAAYJ3xHPIQB4AQAOAAEJagETGwBAAAAuAAQKfykAAw8ACAl7HHQ1ADYCAA8ACAl7HHQ1ADYCAA4AAQkAAMRfAE8AAAAA.',
El='Eldoryn:BAABLgAECn8fAAIbAAkJMhnjKgBVAgAbAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9MAAIiAAkJUh2LBwB8AgAiAAkJUh2LBwB8AgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8LAAQfAAMJbwk/CgCEAAAPAAMJwQYMagDBAAAOAAIJ6Af0DwCHAAAfAAIJmgc/CgCEAAAuAAQKfy4ABA8ACQn5Goc4AN8BAA8ACAloGIc4AN8BAA4ACAmiFL0fAFQBAB8AAglRGtEYALQAAAEuAAUUBAkKABkAUhoA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAQJDwAjANsiAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJBgAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.',
Fi='Finntastic:BAAALgADCgYJCAABLgAFFAIJBgAiAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJBgAiAMoaAA==.Fisterdobble:BAABLgAECn8+AAIWAAkJ2xZHPwADAgAWAAkJ2xZHPwADAgAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Fleurdelys:BAAALgADCgkJMwAAAA==.',
Fo='Forestpump:BAAALgAECggJCAABLgAECggJGgAEAA0jAA==.Forgeddemon:BAABLgAECn8XAAMcAAgJJgmlRQArAQAcAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgADCgcJBwABLgAECgkJJQAEABsXAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIgAAkJ0h6VBgBRAgAgAAkJ0h6VBgBRAgAAAA==.Frostina:BAABLgAECn8cAAIWAAgJ8xNGXACtAQAWAAgJ8xNGXACtAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Furionik:BAABLgAECn8YAAMXAAcJFBQ2GACUAQAXAAcJFBQ2GACUAQAJAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIgAAYJ1hctFQBPAQAgAAYJ1hctFQBPAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.',
Gl='Glimmawitz:BAAALgADCgcJCgAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAAALgAECgYJDwAAAA==.Goodboy:BAABLgAFFH8IAAILAAQJdwO+SwDKAAALAAQJdwO+SwDKAAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8jAAIGAAcJVhJ6PgB2AQAGAAcJVhJ6PgB2AQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8PAAIjAAQJ2yJ8AQCnAQAjAAQJ2yJ8AQCnAQAuAAQKfxoAAiMACAlcJBUCAOgCACMACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8ZAAIIAAYJ/xSCQQB1AQAIAAYJ/xSCQQB1AQAAAA==.',
Gu='Gulaj:BAABLgAECn8UAAILAAgJZRjISQCMAQALAAgJZRjISQCMAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQfAAkJRRNwBgDgAQAPAAgJ1RFYRQD7AQAfAAkJNxJwBgDgAQAOAAQJ2wfgNQAwAAAAAA==.',
He='Healgimp:BAABLgAECn8iAAIDAAkJixUvGQDaAQADAAkJixUvGQDaAQAAAA==.Healslux:BAABLgAECn8eAAIVAAkJvx/RCQDKAgAVAAkJvx/RCQDKAgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAEALgAECgEJAgABLgAFFAcJDQAdADANAA==.Hortzel:BAABLgAECn8UAAIPAAYJOA6ViwANAQAPAAYJOA6ViwANAQAAAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAABLgAECn8UAAIaAAcJ2RcuUgC0AQAaAAcJ2RcuUgC0AQAAAA==.Huntus:BAABLgAECn84AAMLAAkJsCOpBgALAwALAAkJsCOpBgALAwAMAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIaAAgJHxYXVACvAQAaAAgJHxYXVACvAQAAAA==.',
Ic='Icy:BAAALgAECgUJBgAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgASAAcJjxKLIgCqAQAAAA==.Impostor:BAABLgAECn8yAAITAAkJdiAfBQDqAgATAAkJdiAfBQDqAgAAAA==.',
In='Indabow:BAABLgAECn8gAAILAAkJbRopKAAXAgALAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAcAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIeAAgJihRTGQD7AQAeAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8bAAMeAAgJFhpXEQBUAgAeAAgJFhpXEQBUAgAbAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8FAAIbAAIJCx6/VQC2AAAbAAIJCx6/VQC2AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8aAAIkAAkJFBruCgBwAgAkAAkJFBruCgBwAgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8OAAMCAAUJVxvrEQBOAQACAAUJVxvrEQBOAQAjAAEJBwdfDgBMAAAuAAQKfxsAAwIACAmEHPohAOkBAAIABwkRHfohAOkBACMABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8YAAIcAAYJlg5IEwBRAQAcAAYJlg5IEwBRAQAuAAQKfyQAAhwACAnxElshAPcBABwACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgUJBQABLgAECgYJBgABAAAAAA==.Juul:BAABLgAECn8YAAISAAkJ2RWoEgArAgASAAkJ2RWoEgArAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAIJAgABAAAAAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAIJAgABAAAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Ke='Kelemvor:BAABLgAECn8wAAIbAAkJdB3zFQDTAgAbAAkJdB3zFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8SAAIiAAUJDBj2EgATAQAiAAUJDBj2EgATAQAuAAQKfxUAAiIACAnWGQAPABwCACIACAnWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAECgYJCAABAAAAAA==.Kidslaps:BAABLgAECn8eAAIcAAgJTAzpKQBHAQAcAAgJTAzpKQBHAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.Korìe:BAAALgAECgkJCAABLgAFFAIJAgABAAAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAABLgAECn8lAAQEAAkJGxeiIACuAQAEAAkJGxeiIACuAQAcAAEJSgzTeAA+AAAkAAEJPQ/IfQA1AAAAAA==.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8hAAILAAkJQxmcIQA1AgALAAkJQxmcIQA1AgAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8jAAQPAAgJFwfIgQAgAQAPAAcJhgbIgQAgAQAOAAUJxAR8JQBmAAAfAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAIPAAkJiBrgFwB8AgAPAAkJiBrgFwB8AgAAAA==.',
Lh='Lhux:BAABLgAECn8tAAILAAgJ3iG9DADZAgALAAgJ3iG9DADZAgAAAA==.Lhuxi:BAACLgAFFH8JAAISAAQJzhGFIQAWAQASAAQJzhGFIQAWAQAuAAQKfx4AAhIACQnTG8QKAI8CABIACQnTG8QKAI8CAAEuAAQKCAktAAsA3iEA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAAALgAFFAEJAgAAAA==.Lightisright:BAAALgAECgIJAgAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8WAAIaAAgJGA42aQB9AQAaAAgJGA42aQB9AQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8SAAIHAAUJ9BTbFwAqAQAHAAUJ9BTbFwAqAQAuAAQKfysAAgcACAlcIHwMAGkCAAcACAlcIHwMAGkCAAAA.Lorgar:BAAALgAECgQJBAAAAA==.',
Lu='Luca:BAABLgAECn8iAAIGAAkJdA0XPQB8AQAGAAkJdA0XPQB8AQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgADCgYJBgAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSQAIAPcZAA==.Lyxxie:BAABLgAECn89AAMFAAkJihrQNwBXAgAFAAkJihrQNwBXAgAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIWAAkJsBzNIACAAgAWAAkJsBzNIACAAgAAAA==.Mageus:BAAALgAECgEJAQAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECgYJFAAgANYXAA==.Marici:BAAALgADCgMJAwAAAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8aAAIJAAcJUAz0OAA9AQAJAAcJUAz0OAA9AQABLgAFFAMJDgAIAMMYAA==.Metsutan:BAABLgAECn9EAAICAAkJTiV+AgAWAwACAAkJTiV+AgAWAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAABLgAECn8qAAMTAAkJvRK/GwDBAQATAAgJFxS/GwDBAQADAAYJoQoYYACyAAAAAA==.Moistfellow:BAABLgAECn8VAAIWAAYJHxYLvABqAQAWAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIfAAgJNCJ9AgCWAgAfAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCQAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAWALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Moskeebee:BAABLgAECn8UAAILAAcJyiUSEgCnAgALAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAAALgAECgcJEgAAAA==.',
['Må']='Måtthew:BAAALgADCgEJAQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8jAAIPAAcJgwqRfAAqAQAPAAcJgwqRfAAqAQAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.Nazuresh:BAAALgAECgUJBgABLgAECgcJKQADAJAUAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMPAAgJVBvYRAC1AQAPAAgJVBvYRAC1AQAOAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn83AAMOAAgJpRy3AwAqAgAOAAgJpRy3AwAqAgAPAAIJ4w2r5gBmAAAAAA==.Nemriel:BAAALgAECgYJDwAAAA==.Newthilena:BAAALgAECgEJAQAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMbAAkJjxb5OADBAQAbAAkJzxD5OADBAQAeAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Norsem:BAAALgAECggJDQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPAAJAKAlAA==.',
['Nä']='Nämeless:BAAALgAFFAEJAQAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIdAAMJTBz2HwAHAQAdAAMJTBz2HwAHAQAuAAQKfywAAh0ACAlGIPsMAHMCAB0ACAlGIPsMAHMCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
On='Oneth:BAABLgAECn8UAAIfAAYJ3xCYEQATAQAfAAYJ3xCYEQATAQAAAA==.Onfleek:BAABLgAECn8yAAMDAAgJXiMbBQAOAwADAAgJXiMbBQAOAwATAAYJJA1BNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8OAAIIAAMJwxhXMADrAAAIAAMJwxhXMADrAAAuAAQKf0EAAggACQkdHQQTAIgCAAgACQkdHQQTAIgCAAAA.',
Or='Orakrak:BAABLgAECn8fAAIJAAgJtAsfNgBJAQAJAAgJtAsfNgBJAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgADCgYJCQAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNAAdAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNAAdAB4lAA==.Parseval:BAABLgAECn80AAQdAAkJHiWAAQClAwAdAAkJHiWAAQClAwATAAgJ0RuEEQAlAgADAAQJPxsuQwAsAQAAAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPAAJAKAlAA==.Paws:BAABLgAECn88AAIJAAkJoCUUAgBAAwAJAAkJoCUUAgBAAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIVAAgJORjnMwBaAQAVAAgJORjnMwBaAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIhAAYJqg1nGAD9AAAhAAYJqg1nGAD9AAAAAA==.',
Pi='Pipsqueak:BAAALgADCgMJAwAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAECgYJDwAAAA==.Porkins:BAABLgAECn88AAMiAAkJGSCoBwB5AgAiAAgJmx+oBwB5AgAmAAkJqh09BQAmAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgADCgQJBAAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgADCgkJCQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBQAbAAseAA==.',
Ps='Psyndar:BAAALgADCgMJAwABLgAFFAQJDgAIANsRAA==.Psyndra:BAAALgAECgMJAwABLgAFFAQJDgAIANsRAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8KAAIWAAMJHBFFZgDpAAAWAAMJHBFFZgDpAAAuAAQKfy8AAhYACQkwHi4WALkCABYACQkwHi4WALkCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAIJAgABAAAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8GAAIPAAQJDQ3/UQD4AAAPAAQJDQ3/UQD4AAAuAAQKfyAAAg8ACAnXIYQRAKkCAA8ACAnXIYQRAKkCAAAA.Rakomar:BAAALgADCgIJAgAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMbAAgJjRJ2VABmAQAbAAgJ7xF2VABmAQAeAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8pAAMDAAcJkBTCIgCKAQADAAcJkBTCIgCKAQATAAUJhgUtUgCTAAAAAA==.',
Re='Replicate:BAABLgAECn8dAAIJAAgJRCL6CACzAgAJAAgJRCL6CACzAgAAAA==.Resisted:BAAALgAECgEJAQABLgAFFAYJEwASAPYcAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJLwALAM0YAA==.',
Ry='Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8SAAIVAAUJuB+RCgDGAQAVAAUJuB+RCgDGAQAuAAQKfzEAAhUACQmNJd0AAJIDABUACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgADCgYJBgAAAA==.Ryri:BAABLgAECn8cAAIgAAcJXxX/EACHAQAgAAcJXxX/EACHAQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMdAAkJlgqwIgB+AQAdAAkJlgqwIgB+AQATAAIJGQssXQBjAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMcAAkJbQmhJQBiAQAcAAkJbQmhJQBiAQAEAAcJ0gzILgBDAQAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECgcJEAAAAA==.Santoku:BAABLgAECn8QAAIbAAYJsxc4XgBKAQAbAAYJsxc4XgBKAQAAAA==.Sarah:BAACLgAFFH8KAAIdAAQJkBWnGQA8AQAdAAQJkBWnGQA8AQAuAAQKfzMAAh0ACQmxH+YDAEADAB0ACQmxH+YDAEADAAAA.Sassyface:BAABLgAECn9EAAIOAAkJ7Q7nCACOAQAOAAkJ7Q7nCACOAQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgEJAQAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAGAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAAALgAECgQJBAAAAA==.Shaduw:BAACLgAFFH8YAAIXAAYJnR66BQCgAQAXAAYJnR66BQCgAQAuAAQKfyQAAxcACAnOIbMDABkDABcACAnOIbMDABkDAAkACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBCaIwBJAQACAAcJkBCaIwBJAQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJBwABLgAECgkJJgAOAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAITAAMJPBavGgDtAAATAAMJPBavGgDtAAAuAAQKfzYAAhMACQlGIfwFAC4DABMACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIWAAMJCBvFXQD9AAAWAAMJCBvFXQD9AAAuAAQKfycAAhYACQlNIykVACkDABYACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMVAAgJniPOEACMAgAVAAgJniPOEACMAgAaAAQJrRh0AwGDAAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMEAAgJDSPpCQC0AgAEAAcJnyLpCQC0AgAkAAYJJBXjKgA4AQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spazcaster:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQjAAgJEBdEBwDDAQAjAAgJyhVEBwDDAQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCggJBwAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgQJCgAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAIJAgABAAAAAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAAALgAECgkJDwAAAA==.Stelthme:BAABLgAECn8UAAQjAAYJBw1MEQDuAAAjAAUJqA5MEQDuAAAnAAMJQwjKFQB+AAACAAEJGAiiXgA5AAABLgAFFAMJDQACAF4lAA==.Stormburst:BAAALgADCgIJAgABLgAFFAQJDwAjANsiAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIWAAcJQyFKOgCNAgAWAAcJQyFKOgCNAgABLgAECggJFAANAEElAA==.',
Su='Susaki:BAAALgADCgEJAQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAANAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8oAAIXAAkJox4rBADIAgAXAAkJox4rBADIAgAAAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8HAAISAAQJgRFQIgATAQASAAQJgRFQIgATAQAuAAQKfyIAAxIACQl5IGQFAPMCABIACQl5IGQFAPMCACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgADCgMJAwAAAA==.',
Th='Theory:BAABLgAECn80AAMFAAkJhhefTAC6AQAFAAgJbRafTAC6AQAiAAIJ+hipNQCSAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgQJBAAAAA==.',
Tj='Tj:BAAALgAECgcJBgAAAA==.',
To='Tomjim:BAACLgAFFH8TAAMSAAYJ9hySGgA5AQASAAUJRh2SGgA5AQAYAAMJZQXtEwCLAAAuAAQKfyYABBIACAlAIwsLAMUCABIACAlAIwsLAMUCABgABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn8uAAINAAkJwxuXDQAyAgANAAkJwxuXDQAyAgAAAA==.Treevive:BAACLgAFFH8JAAIGAAUJtRCaFgBsAQAGAAUJtRCaFgBsAQAuAAQKfxkAAgYACAmaIEEcAFoCAAYACAmaIEEcAFoCAAAA.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn8uAAIaAAkJJxOnOAD/AQAaAAkJJxOnOAD/AQAAAA==.',
Ts='Tsinga:BAABLgAECn8aAAIZAAYJHw/rGQAEAQAZAAYJHw/rGQAEAQAAAA==.',
Tu='Turl:BAAALgAECgUJCgABLgAECgYJIQAVAHMfAA==.Turlo:BAABLgAECn8hAAIVAAYJcx83LADWAQAVAAYJcx83LADWAQAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAQJDAAnAHUJAA==.Twostep:BAACLgAFFH8MAAInAAQJdQkSBQAaAQAnAAQJdQkSBQAaAQAuAAQKfyoAAicACQnzGRUDACwCACcACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8RAAIaAAYJ8SBTCgDDAQAaAAYJ8SBTCgDDAQAuAAQKfyIAAhoABwmkJTsYANgCABoABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8KAAIEAAMJaRHFJwC3AAAEAAMJaRHFJwC3AAAuAAQKfy4AAgQACQmTHYQQAGkCAAQACQmTHYQQAGkCAAAA.',
Ur='Ursos:BAABLgAECn8aAAIUAAcJthbyEwB7AQAUAAcJthbyEwB7AQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8WAAMSAAkJERjuFwD3AQASAAkJERjuFwD3AQAYAAEJ1gFSTAApAAAAAA==.Vallatris:BAAALgAECgUJDgAAAA==.Valsande:BAAALgADCgkJHwAAAA==.Vargr:BAAALgADCgEJAQAAAA==.',
Ve='Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn8oAAIWAAcJYBG1cwB1AQAWAAcJYBG1cwB1AQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgADCgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgADCgIJBAAAAA==.Viracocha:BAAALgAFFAIJAwAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgYJBgABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAECgEJAQAAAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8aAAIbAAYJPRhjXQBMAQAbAAYJPRhjXQBMAQAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.',
Wi='Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIdAAcJMhJAJgBuAQAdAAcJMhJAJgBuAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCAAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAAALgAECgYJCwABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8oAAINAAkJVRxpCwBSAgANAAkJVRxpCwBSAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQfAAYJvyB9DABwAQAPAAUJcx6VXACzAQAfAAQJByJ9DABwAQAOAAEJAABYYABOAAABLgAFFAEJAQABAAAAAA==.Zandramadas:BAABLgAECn8/AAQGAAkJMRpoLAD9AQAGAAgJqRloLAD9AQAHAAkJIx2bFgDwAQAUAAcJXxLoGABIAQAAAA==.Zaraline:BAABLgAECn8vAAILAAkJzRjDJwAWAgALAAkJzRjDJwAWAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCAAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIFAAgJrBsNMwAPAgAFAAgJrBsNMwAPAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.',
Zh='Zhuu:BAAALgADCgQJBAAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIFAAYJbBZdhgAyAQAFAAYJbBZdhgAyAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIWAAkJUR5HFwCzAgAWAAkJUR5HFwCzAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECggJGwATAFgYAA==.',
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
