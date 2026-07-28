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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Druid-Restoration','Monk-Brewmaster','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-07-28',data={Ab='Abracadabra:BAAALgAECgYJDQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJDQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adrasteia:BAAALgAECgMJAwABLgAECgkJKAADAIEZAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.Agunagun:BAAALgAECgEJAQAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIEAAYJ3xU9MwA7AQAEAAYJ3xU9MwA7AQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIFAAQJIRWcLAAOAQAFAAQJIRWcLAAOAQAAAA==.Alexiel:BAAALgAECgIJAgAAAA==.Alfuric:BAABLgAECn8XAAQGAAkJHwZgQQChAAAHAAYJEwdcVgC3AAAGAAkJywJgQQChAAAIAAQJBgZENQCIAAAAAA==.Aliviana:BAAALgAECgEJAQABLgAECgkJKAADAIEZAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9EAAIJAAkJgB23IgB8AgAJAAkJgB23IgB8AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIKAAMJBxk/NgDTAAAKAAMJBxk/NgDTAAAuAAQKfyMAAwoACQn9IScJAP4CAAoACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAKAAcZAA==.',
Am='Amatraek:BAAALgAFFAIJAgABLgAFFAgJHAALAHsQAA==.Amatsano:BAEBLgAECn8UAAIMAAYJVht/PQC4AQAMAAYJVht/PQC4AQAAAA==.Amorsith:BAAALgAECgkJEgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8NAAMNAAMJ9h4xPwCqAAANAAIJxh4xPwCqAAAOAAEJVh9hPgBQAAAuAAQKfyUAAw4ACQnQIhIGAKICAA4ACAm+IBIGAKICAA0ABQkVI+c3AMgBAAAA.',
An='Anahita:BAAALgADCgYJBgAAAA==.Anderson:BAAALgADCgIJAgAAAA==.Aneyna:BAAALgAECgYJDQAAAA==.Angrycrack:BAABLgAECn8aAAICAAkJ6xhUEwAJAgACAAkJ6xhUEwAJAgAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxpGLgBpAQAHAAYJzxpGLgBpAQAAAA==.Anjunabeets:BAABLgAFFH9FAAQPAAkJLyKBBAB7AgAPAAcJBSSBBAB7AgAQAAcJLxGfCQCAAQARAAUJfRacDwBIAQAAAA==.Anthran:BAABLgAECn8mAAMSAAkJqw8jHwBYAQASAAYJzQ4jHwBYAQATAAcJJQwThQAvAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgYJCwABLgAECgkJOwANAGsXAA==.Archos:BAAALgAECgEJBgAAAA==.Arcon:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Arcscythe:BAABLgAECn8lAAIUAAkJ4BYLAwAEAgAUAAkJ4BYLAwAEAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgQJBgAAAA==.Artoo:BAABLgAECn8fAAICAAkJOx45AgDnAQACAAkJOx45AgDnAQAAAA==.',
As='Ashesonly:BAAALgAECgcJCwAAAA==.Asleep:BAAALgAECgYJCwABLgAECgkJOwANAGsXAA==.Assaulter:BAAALgAECgYJEAABLgAECgkJKgAPAEEaAA==.Astralpanda:BAABLgAECn8ZAAIVAAgJKAq9SgAKAQAVAAgJKAq9SgAKAQAAAA==.Asunä:BAAALgADCgQJBAAAAA==.',
At='Athair:BAAALgAECgMJAwAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn9MAAIWAAkJoBUpAgDhAQAWAAkJoBUpAgDhAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAXADEYAA==.Baer:BAABLgAECn8eAAIGAAgJ9geaOwC3AAAGAAgJ9geaOwC3AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn9AAAIYAAkJhBGxBAChAQAYAAkJhBGxBAChAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8lAAITAAcJAQurkAAZAQATAAcJAQurkAAZAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAZAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8aAAIaAAgJdhtNEQDWAQAaAAgJdhtNEQDWAQAAAA==.Bauchelaine:BAABLgAECn8jAAMTAAgJRhD/YQB7AQATAAgJRhD/YQB7AQAbAAEJEAZLRAAoAAAAAA==.Bavunga:BAABLgAECn8pAAIcAAkJhCCtAgA3AwAcAAkJhCCtAgA3AwAAAA==.Bawitaba:BAAALgAECggJDgAAAA==.Bayle:BAAALgAECgUJCQAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Bearme:BAAALgADCgcJCgAAAA==.Beastadi:BAAALgAFFAMJBAAAAA==.Beelieve:BAAALgADCgYJBgAAAA==.Beoron:BAACLgAFFH8OAAIIAAYJ3xxrAQC0AQAIAAYJ3xxrAQC0AQAuAAQKfy8AAggACQnaJQgBAFADAAgACQnaJQgBAFADAAAA.Bettyßastion:BAABLgAECn8yAAIdAAkJrx84GwChAgAdAAkJrx84GwChAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJDAABAAAAAA==.Bioenergy:BAAALgAECgkJDAAAAA==.Biogen:BAAALgAECgMJBAABLgAECgkJDAABAAAAAA==.Biolysis:BAAALgAECggJCwABLgAECgkJDAABAAAAAA==.Bisoncrusher:BAAALgAECggJEQAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Blockhead:BAAALgADCgIJBAABLgAECgkJOwANAGsXAA==.Bloodstone:BAAALgAECgYJCgAAAA==.Blowtortch:BAAALgAECgcJEwAAAA==.',
Bo='Boagrius:BAABLgAECn8YAAIXAAgJhAc/QQALAQAXAAgJhAc/QQALAQABLgAFFAMJGgAMAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMRAAgJQSVlAgAeAwARAAgJQSVlAgAeAwAQAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Boulder:BAAALgAECgEJAQAAAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAACLgAFFH8HAAIVAAIJfQyHJgBsAAAVAAIJfQyHJgBsAAAuAAQKfxcAAhUACAkSFX8rAJgBABUACAkSFX8rAJgBAAAA.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAABLgAECn8ZAAQaAAkJ6hr1HgA7AQANAAgJZBZOTgBuAQAaAAQJgRn1HgA7AQAOAAMJ+xAfUACSAAAAAA==.Bruus:BAAALgAFFAEJAwAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bubblêwrap:BAAALgAECgMJAwAAAA==.Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMPAAcJZxOSeABOAQAPAAcJZxOSeABOAQARAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgUJCQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
['Bé']='Béllas:BAAALgAFFAEJAQAAAA==.',
Ca='Caliboy:BAAALgAECgEJAQABLgAECgkJKgAMAFsRAA==.Calihots:BAAALgADCgEJAQABLgAECgkJKgAMAFsRAA==.Calira:BAAALgADCgUJBQAAAA==.Calißoy:BAABLgAECn8qAAIMAAkJWxEQPAC+AQAMAAkJWxEQPAC+AQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJBAABAAAAAA==.Cankles:BAAALgADCgMJAwAAAA==.Cannyon:BAAALgAECgQJBwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgAECgQJBAABLgAECgkJRgACAE4lAA==.Cerberus:BAAALgAFFAIJAwAAAA==.Ceruledge:BAABLgAECn8fAAIeAAgJyxSjRwCvAQAeAAgJyxSjRwCvAQABLgAFFAMJBgAXADwWAA==.',
Ch='Chabar:BAEALgAFFAIJAgABLgAFFAkJGQAHAIQRAA==.Chaboomy:BAECLgAFFH8ZAAIHAAkJhBFSCgD1AQAHAAkJhBFSCgD1AQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chidori:BAAALgAECgYJBgAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn87AAINAAkJaxflGQAfAgANAAkJaxflGQAfAgAAAA==.Chopper:BAACLgAFFH8SAAIIAAUJ7BpgBgBHAQAIAAUJ7BpgBgBHAQAuAAQKfyYAAggACQn9IWYDAAEDAAgACQn9IWYDAAEDAAEuAAUUBgkeABsA2BcA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAILAAQJsxGxKAAGAQALAAQJsxGxKAAGAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMEAAcJfBWpJgC4AQAEAAcJ5hSpJgC4AQADAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn9AAAIIAAkJbiaaAABuAwAIAAkJbiaaAABuAwAAAA==.Colmoore:BAAALgAFFAEJAgABLgAFFAYJFwATAGsZAA==.Conkerin:BAABLgAFFH8HAAIPAAMJqhegXQDpAAAPAAMJqhegXQDpAAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJCgAAAA==.Crusible:BAAALgAECgUJEgAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cucumbered:BAAALgADCgUJBQABLgAFFAIJBAABAAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAfAIUQAA==.Cystic:BAAALgADCgcJBwAAAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCQABLgAFFAIJBwAMACcjAA==.Dapper:BAAALgADCgIJAgAAAA==.Darii:BAAALgAECgEJAQAAAA==.Darkis:BAABLgAECn8WAAIKAAgJVgqCTgBqAQAKAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgcJEQAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8HAAIMAAIJ0CJJTQC+AAAMAAIJ0CJJTQC+AAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQSAAkJwhhuGwByAQATAAgJAhKEXwCBAQASAAcJZBZuGwByAQAbAAIJ0RhfKgBxAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAUJHAAgAJsjAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAYJIAACAM8cAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIJAAkJCxuoKABeAgAJAAkJCxuoKABeAgAAAA==.Deepman:BAAALgAFFAEJAQABLgAECgkJKgAPAEEaAA==.Delessia:BAAALgAECgMJBAAAAA==.Demondoom:BAAALgAECgkJCQAAAA==.Denar:BAAALgAECgEJAQAAAA==.Deo:BAABLgAECn9BAAMhAAkJdyTBAQApAwAhAAkJdyTBAQApAwAYAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCQAPAD4FAA==.Disastrous:BAACLgAFFH8jAAIPAAgJmBSnCAAPAgAPAAgJmBSnCAAPAgAuAAQKfzUAAg8ACQlkIsYRAKoCAA8ACQlkIsYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAFFAUJCgAfAFYTAA==.',
Do='Doe:BAAALgAECgQJBAAAAA==.Doomangel:BAABLgAECn8UAAIJAAYJuhGStAAOAQAJAAYJuhGStAAOAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAABLgAECn8oAAINAAcJ6xBHCAA4AQANAAcJ6xBHCAA4AQAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJGgAMAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAZALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Dracthyr:BAAALgAECgUJBQABLgAECgkJDAABAAAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJNQASAMQeAA==.Dragonslock:BAABLgAECn8VAAQTAAcJKQ4opgD1AAATAAYJcA4opgD1AAASAAIJxAznPwAvAAAbAAEJiwNiRgAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIWAAcJDBGQJQCQAQAWAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMKAAkJtxGqRAB+AQAKAAcJRBGqRAB+AQAHAAgJ9QYzWQCuAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAECgkJKgAPAEEaAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8gAAICAAYJzxwfDQDBAQACAAYJzxwfDQDBAQAuAAQKfzEAAgIACQkmJbUDAAoDAAIACQkmJbUDAAoDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAYJIAACAM8cAA==.',
['Dø']='Døc:BAABLgAECn9LAAQMAAkJ9xmIFACnAgAMAAkJ9xmIFACnAgAVAAkJXxKHJADDAQAiAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIhAAMJWQ5JDQClAAAhAAMJWQ5JDQClAAAuAAQKfyAAAyEACAl0G/8QALcBACEABwlyGP8QALcBAB0ABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8YAAMTAAkJqQy0GwDqAQATAAkJqQy0GwDqAQASAAEJagETGwBAAAAuAAQKfykAAxMACAl7HHQ1ADYCABMACAl7HHQ1ADYCABIAAQkAAMRfAE8AAAAA.',
El='Elanna:BAAALgAECgEJAQABLgAECgkJGQAaAOoaAA==.Eldoryn:BAABLgAECn8fAAIeAAkJMhnjKgBVAgAeAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9VAAIjAAkJUh2mCgBmAgAjAAkJUh2mCgBmAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erindralla:BAAALgAECgQJBQAAAA==.Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8eAAQbAAYJ2BdVCwDHAAATAAYJBhQGNQBzAQAbAAMJCQtVCwDHAAASAAMJSxT7FgB8AAAuAAQKfy4ABBMACQn5GhdEAM8BABMACAloGBdEAM8BABIACAmiFL0fAFQBABsAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAUJHAAgAJsjAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgcJDQABLgAECgcJEQABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Felshadra:BAABLgAFFH8GAAITAAYJTgd1ZwD2AAATAAYJTgd1ZwD2AAAAAA==.',
Fi='Finnland:BAAALgAECgEJAQABLgAFFAIJCQAjAMoaAA==.Finntastic:BAAALgADCgYJCAABLgAFFAIJCQAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCQAjAMoaAA==.Fisterdobble:BAABLgAECn9DAAIZAAkJMRcRTwDuAQAZAAkJMRcRTwDuAQAAAA==.Fisticuffs:BAAALgADCgMJAwAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Flawlesshope:BAAALgAECgQJBAAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAABLgAECn8ZAAMMAAkJOR2sGACEAgAMAAgJhBysGACEAgAiAAkJ9RkdBgB6AgABLgAECggJGgAFAA0jAA==.Forgeddemon:BAABLgAECn8XAAMLAAgJJgmlRQArAQALAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgUJCAAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAUJFAAFADgbAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIhAAkJ0h6MBgB/AgAhAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIZAAgJGRS0bACiAQAZAAgJGRS0bACiAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Funeral:BAAALgAECgcJEgABLgAECgkJKgAPAEEaAA==.Furionik:BAABLgAECn8YAAMaAAcJFBQ2GACUAQAaAAcJFBQ2GACUAQANAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIhAAYJ1hfeGQBKAQAhAAYJ1hfeGQBKAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Genesìs:BAAALgAECgEJAQABLgAECgkJIQAXADEYAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJEAAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8WAAIdAAgJIxvqRgDyAQAdAAgJIxvqRgDyAQAAAA==.Gonga:BAAALgAECgEJAQAAAA==.Goodboy:BAABLgAFFH8JAAIPAAQJPgWdcAC/AAAPAAQJPgWdcAC/AAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn9AAAIKAAkJJRS9CAAdAQAKAAkJJRS9CAAdAQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8cAAIgAAUJmyNKAgCWAQAgAAUJmyNKAgCWAQAuAAQKfxoAAiAACAlcJBUCAOgCACAACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8bAAIMAAYJ/xTmTwByAQAMAAYJ/xTmTwByAQAAAA==.',
Gu='Gulaj:BAABLgAECn8cAAIPAAkJzhuDWwCTAQAPAAkJzhuDWwCTAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.Guttsholycow:BAAALgAECgcJBwAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQbAAkJRROlCQDIAQATAAgJ1RFYRQD7AQAbAAkJNxKlCQDIAQASAAQJ2wfSPwAvAAAAAA==.',
He='Healgimp:BAACLgAFFH8UAAIEAAQJSRhjCQAZAQAEAAQJSRhjCQAZAQAuAAQKfyIAAgQACQmLFUggAMABAAQACQmLFUggAMABAAAA.Healslux:BAABLgAECn8eAAIYAAkJvx9ODQC9AgAYAAkJvx9ODQC9AgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.Hiruken:BAAALgADCgkJFAAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hortzel:BAABLgAECn8UAAITAAYJOA5ZoQD9AAATAAYJOA5ZoQD9AAAAAA==.Hotrollz:BAAALgAECgQJBwABLgAECgkJGQAKAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAACLgAFFH8FAAIdAAEJmRFsaABFAAAdAAEJmRFsaABFAAAuAAQKfyUAAh0ACQlOIB8EAHgCAB0ACQlOIB8EAHgCAAAA.Huntus:BAABLgAECn84AAMPAAkJsCM/DADxAgAPAAkJsCM/DADxAgAQAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIdAAgJHxbpaQCbAQAdAAgJHxbpaQCbAQAAAA==.',
Ic='Icy:BAAALgAECggJCQAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAWAAcJjxKLIgCqAQAAAA==.Impostor:BAACLgAFFH8FAAIXAAMJ3wg4KAC8AAAXAAMJ3wg4KAC8AAAuAAQKfzIAAhcACQl2IIEHANgCABcACQl2IIEHANgCAAAA.',
In='Indabow:BAABLgAECn8gAAIPAAkJbRopKAAXAgAPAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQALAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8fAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAeAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIeAAIJvCHaaQC4AAAeAAIJvCHaaQC4AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8xAAIkAAkJEx4HCQC1AgAkAAkJEx4HCQC1AgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8XAAMCAAYJ9BrHFgBXAQACAAUJsh3HFgBXAQAgAAIJgguMBQBXAAAuAAQKfx0AAwIACQkjHugRABgCAAIACQlCHegRABgCACAABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8cAAILAAgJexAqCgDuAQALAAgJexAqCgDuAQAuAAQKfyQAAgsACAnxElshAPcBAAsACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJDQABLgAECgcJEQABAAAAAA==.Juul:BAABLgAECn8YAAIWAAkJ2RWAFgAkAgAWAAkJ2RWAFgAkAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAQJBQAPAJ0KAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAQJBQAPAJ0KAA==.',
['Jö']='Jöze:BAAALgAECgYJBgAAAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgAECgYJCAABLgAECggJHgAOAE4dAA==.Karram:BAAALgAECgEJAQAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Kc='Kcup:BAAALgADCgIJAgAAAA==.',
Ke='Kelemvor:BAABLgAECn8+AAIeAAkJlx3zFQDTAgAeAAkJlx3zFQDTAgAAAA==.Keranos:BAAALgADCgcJCQAAAA==.Keyzo:BAAALgAECgEJAQAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8YAAIjAAYJAhUNGwAOAQAjAAYJAhUNGwAOAQAuAAQKfxcAAiMACQlWGQAPABwCACMACQlWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAFFAEJAQABLgAFFAMJCgAJABcaAA==.Kidslaps:BAABLgAECn8eAAILAAgJTAxTMABCAQALAAgJTAxTMABCAQAAAA==.Killeos:BAAALgAECgEJAQAAAA==.Kimmy:BAAALgAECgEJAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Koosh:BAAALgAECgMJAwABLgAECggJJgAYAEggAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8UAAIFAAUJOBt+FAAzAQAFAAUJOBt+FAAzAQAuAAQKfycABAUACQn+F6IgAK4BAAUACQn+F6IgAK4BAAsAAQlKDJiIAD0AACQAAQk9D92bADMAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8qAAIPAAkJQRp/KAA9AgAPAAkJQRp/KAA9AgAAAA==.Leadresa:BAAALgAECgMJAwABLgAFFAIJDAAdAOgKAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Leethalrot:BAAALgAECgEJAgABLgAECgQJBQABAAAAAA==.Legosi:BAABLgAECn8kAAQTAAgJagf3jwAbAQATAAcJagf3jwAbAQASAAUJxAQwLgBhAAAbAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAITAAkJiBqKHgBtAgATAAkJiBqKHgBtAgAAAA==.',
Lh='Lhux:BAABLgAECn8+AAIPAAkJDyPCAgDDAgAPAAkJDyPCAgDDAgAAAA==.Lhuxi:BAACLgAFFH8gAAIWAAYJvBjyDgBaAQAWAAYJvBjyDgBaAQAuAAQKfzgAAhYACQmRHo8BADcCABYACQmRHo8BADcCAAEuAAQKCQk+AA8ADyMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAACLgAFFH8GAAIdAAMJYBorYADvAAAdAAMJYBorYADvAAAuAAQKfxYAAh0ACQlZG+8kAHECAB0ACQlZG+8kAHECAAAA.Lightisright:BAAALgAECgYJCwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIdAAgJaBBvdACFAQAdAAgJaBBvdACFAQAAAA==.Liriel:BAAALgAECgEJAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8aAAIHAAcJexitFgBlAQAHAAcJexitFgBlAQAuAAQKfy0AAgcACQk0IJ8IAMoCAAcACQk0IJ8IAMoCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIKAAkJdA0LRwB0AQAKAAkJdA0LRwB0AQAAAA==.Luceean:BAAALgAFFAEJAQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAgAAAA==.Lurthshots:BAAALgAFFAEJAQAAAA==.Luxmunkii:BAAALgAECgkJEgAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSwAMAPcZAA==.Lyxxie:BAABLgAECn9LAAMJAAkJQBurRQDxAQAJAAkJQBurRQDxAQAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIZAAkJsBxrKgBwAgAZAAkJsBxrKgBwAgAAAA==.Mageus:BAAALgAFFAIJAwAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manchop:BAAALgAECgEJAQAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECggJFAAhANYXAA==.Marici:BAAALgADCgMJAwAAAA==.Matsumushi:BAAALgAFFAMJBAABLgAFFAMJBgAXAM8PAA==.Mattxtz:BAAALgADCgMJAwABLgAECgkJMQAZALAcAA==.Maximosharp:BAAALgAECgYJBgABLgAECgkJOwANAGsXAA==.',
Me='Mechanizedtv:BAABLgAECn8cAAMnAAkJLBnXAABhAgAnAAkJLBnXAABhAgAeAAMJ9AbrJgBdAAABLgAFFAQJFwAGAFQkAA==.Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8fAAINAAkJ8g0YLACkAQANAAkJ8g0YLACkAQABLgAFFAMJGgAMAMMYAA==.Metsutan:BAABLgAECn9GAAICAAkJTiULBAD/AgACAAkJTiULBAD/AgAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAACLgAFFH8GAAIXAAMJzw+JMACEAAAXAAMJzw+JMACEAAAuAAQKfzcAAxcACQnJFQweANUBABcACAn6FgweANUBAAQABgmwDBhgALIAAAAA.Moistfellow:BAABLgAECn8VAAIZAAYJHxYLvABqAQAZAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIbAAgJNCJ9AgCWAgAbAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAZALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moogoboom:BAAALgADCgEJAQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAQJBQAPAJ0KAA==.Moskeebee:BAABLgAECn8UAAIPAAcJyiUSEgCnAgAPAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8XAAMMAAkJmwKmewDtAAAMAAkJmwKmewDtAAAVAAQJewH6kgBOAAAAAA==.',
['Mä']='Mätthew:BAAALgAECgEJAwAAAA==.',
['Må']='Måtthew:BAAALgAECgEJAwAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAITAAcJoQoCjgAeAQATAAcJoQoCjgAeAQAAAA==.Møsh:BAAALgAECgkJDgABLgAFFAQJBQAPAJ0KAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMTAAgJVBv0QwAAAgATAAgJVBv0QwAAAgASAAEJjAnIdQAvAAAAAA==.Nekromant:BAACLgAFFH8MAAMTAAMJlQ0WNQCzAAATAAMJlQ0WNQCzAAASAAEJ8gXsEgA5AAAuAAQKf08AAxMACQl2HdAUAKgCABMACQmYHNAUAKgCABIACAmlHFcFAB0CAAAA.Nemriel:BAAALgAECggJDwAAAA==.Newthilena:BAAALgAFFAQJBAAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMeAAkJjxasRQC2AQAeAAkJzxCsRQC2AQAfAAYJfRhPIQCyAQAAAA==.Nighthoe:BAAALgAECgkJBAAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Normandy:BAAALgADCgEJAQABLgAFFAMJGgAMAMMYAA==.Norsem:BAAALgAECgkJDgAAAA==.Nossem:BAAALgAECgEJAgAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPwANAKAlAA==.Nymera:BAAALgAECgQJBQABLgAFFAMJBQAGACwOAA==.Nyxanee:BAABLgAFFH8JAAICAAQJYwnIDwAFAQACAAQJYwnIDwAFAQABLgAFFAQJBQAPAJ0KAA==.',
['Nä']='Nämeless:BAAALgAFFAIJBAAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIDAAMJTBzuKwDyAAADAAMJTBzuKwDyAAAuAAQKfywAAgMACAlGIKQQAGgCAAMACAlGIKQQAGgCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ok='Oktar:BAAALgADCgIJAgAAAA==.',
Ol='Oleksandra:BAAALgAECgMJAwAAAA==.Olgaa:BAAALgAFFAIJAwABLgAFFAcJEwAKANIbAA==.',
On='Oneth:BAABLgAECn8UAAIbAAYJ3xC3FwAHAQAbAAYJ3xC3FwAHAQAAAA==.Onfleek:BAABLgAECn80AAQEAAgJXCNRBwD6AgAEAAgJXCNRBwD6AgAXAAYJvBFBNgA7AQADAAEJWB3DGQBYAAAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Opshammi:BAACLgAFFH8aAAIMAAMJwxhiSQDJAAAMAAMJwxhiSQDJAAAuAAQKf0MAAgwACQkdHa4UAKYCAAwACQkdHa4UAKYCAAAA.',
Or='Orakrak:BAABLgAECn8nAAINAAkJHhFkJQDMAQANAAkJHhFkJQDMAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.Oroku:BAAALgAECgMJAwAAAA==.',
Oz='Ozzmodius:BAAALgAECgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNQADAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNQADAB4lAA==.Parseval:BAABLgAECn81AAQDAAkJHiVPAgCWAwADAAkJHiVPAgCWAwAXAAgJ0RssFgAaAgAEAAQJPxsuQwAsAQAAAA==.Parshock:BAAALgAFFAEJAQABLgAECgkJNQADAB4lAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPwANAKAlAA==.Paws:BAABLgAECn8/AAINAAkJoCXFAwArAwANAAkJoCXFAwArAwAAAA==.Pawsitivity:BAAALgAECgMJAwABLgAECgkJPwANAKAlAA==.',
Pd='Pdbm:BAAALgAECgEJBAAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIYAAgJORg9PABXAQAYAAgJORg9PABXAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIiAAYJqg1dIAD1AAAiAAYJqg1dIAD1AAAAAA==.',
Pi='Pipsqueak:BAAALgAFFAEJAQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAIJBAAAAA==.Porkins:BAABLgAECn9CAAMjAAkJfyCkCgBmAgAjAAgJmx+kCgBmAgAmAAkJEB6xBwAaAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgAECgYJCQAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAFFAIJAwAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAeALwhAA==.',
Ps='Psyn:BAAALgAECgQJBAABLgAFFAQJHgAMACMgAA==.Psyndar:BAAALgAECgEJAQABLgAFFAQJHgAMACMgAA==.Psyndra:BAAALgAECgYJDAABLgAFFAQJHgAMACMgAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8QAAIZAAMJnRTAgADVAAAZAAMJnRTAgADVAAAuAAQKfzMAAhkACQm5IJgVANcCABkACQm5IJgVANcCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAQJBQAPAJ0KAA==.',
['Pü']='Pück:BAAALgADCgUJBQAAAA==.',
Qt='Qtip:BAAALgAECgMJAwAAAA==.Qtwithabooty:BAAALgAFFAEJAQAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8XAAITAAYJaxmcHAAwAQATAAYJaxmcHAAwAQAuAAQKfzIAAhMACAnDJBsMAO0CABMACAnDJBsMAO0CAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMeAAgJjRI/ZABfAQAeAAgJ7xE/ZABfAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razle:BAAALgADCgQJBAAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn82AAMEAAkJThdiIQC3AQAEAAkJThdiIQC3AQAXAAUJ2gUbZQCHAAAAAA==.',
Re='Replicate:BAACLgAFFH8IAAINAAMJYx3yKwAEAQANAAMJYx3yKwAEAQAuAAQKfyMAAg0ACQnrIdQFAAMDAA0ACQnrIdQFAAMDAAAA.Resisted:BAAALgAECgEJAQABLgAFFAgJFQAWAFMYAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rochara:BAAALgAECgIJAwABLgAECgkJKgAMAFsRAA==.Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJRwAPAKAcAA==.',
Ru='Runeswipe:BAAALgAECgEJAgABLgAFFAMJBQAhABAQAA==.',
Ry='Ryanmonk:BAAALgAFFAEJAQAAAA==.Ryanqt:BAAALgAFFAMJAwAAAA==.Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8XAAIYAAgJgRxDBgBpAgAYAAgJgRxDBgBpAgAuAAQKfzEAAhgACQmNJd0AAJIDABgACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAFFAEJAgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJEAAAAA==.Ryri:BAABLgAECn8fAAIhAAcJXxVAFQB+AQAhAAcJXxVAFQB+AQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMDAAkJlgqwIgB+AQADAAkJlgqwIgB+AQAXAAIJGQvNdABXAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMLAAkJbQm+KwBbAQALAAkJbQm+KwBbAQAFAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJCAAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECggJEQAAAA==.Santoku:BAABLgAECn8QAAIeAAYJsxdVbQBJAQAeAAYJsxdVbQBJAQAAAA==.Sarah:BAACLgAFFH8TAAIDAAUJsBcLHQB0AQADAAUJsBcLHQB0AQAuAAQKfzMAAgMACQmxH4cFADADAAMACQmxH4cFADADAAAA.Sass:BAAALgAECgQJBQAAAA==.Sassyface:BAABLgAECn9MAAISAAkJERH8CwB/AQASAAkJERH8CwB/AQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Sc='Scarletdawns:BAAALgADCgEJAQAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAKAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAABLgAECn8eAAMOAAgJTh3aAQDIAQAOAAgJTh3aAQDIAQANAAEJcRuZkABRAAAAAA==.Shaduw:BAACLgAFFH8cAAIaAAkJ6hxmBAAmAgAaAAkJ6hxmBAAmAgAuAAQKfyQAAxoACAnOIbMDABkDABoACAnOIbMDABkDAA0ACAkBDj8yAOMBAAAA.Shambooly:BAAALgADCgQJBAAAAA==.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBCcKwA8AQACAAcJkBCcKwA8AQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJEAABLgAECgkJJgASAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIXAAMJPBYGJQDPAAAXAAMJPBYGJQDPAAAuAAQKfzYAAhcACQlGIfwFAC4DABcACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIZAAMJCBtGfgDaAAAZAAMJCBtGfgDaAAAuAAQKfycAAhkACQlNIykVACkDABkACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMYAAgJniPOEACMAgAYAAgJniPOEACMAgAdAAQJrRj5MgF8AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Slaughter:BAAALgADCggJCQAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMFAAgJDSPpCQC0AgAFAAcJnyLpCQC0AgAkAAYJJBWCNAAxAQAAAA==.Sniperdoom:BAAALgAECgUJBQAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgIJAgAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQgAAgJEBchCQCxAQAgAAgJyhUhCQCxAQACAAQJ9RiNPwAhAQAoAAEJMAiuDgAyAAAAAA==.Sporki:BAAALgAECgEJAQAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgUJCwAAAA==.',
St='Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIdAAkJjwQs1wDpAAAdAAkJjwQs1wDpAAAAAA==.Stellar:BAAALgAECgIJAgABLgAFFAUJFQACANolAA==.Stelthme:BAABLgAECn8dAAQgAAcJFBrmCwBwAQAgAAcJFBrmCwBwAQAoAAMJQwi4GgB7AAACAAEJGAiiXgA5AAABLgAFFAUJFQACANolAA==.Stormburst:BAAALgADCgIJAgABLgAFFAUJHAAgAJsjAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIZAAcJQyFKOgCNAgAZAAcJQyFKOgCNAgABLgAECggJFAARAEElAA==.',
Su='Susaki:BAAALgAECgQJBQAAAA==.',
Sw='Swan:BAAALgAECgcJCgABLgAFFAQJEAARAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8wAAIaAAkJJSFOAwACAwAaAAkJJSFOAwACAwAAAA==.Takeshì:BAAALgAECgcJBwABLgAECgkJNgAEAE4XAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8KAAIWAAQJkBHOMwDzAAAWAAQJkBHOMwDzAAAuAAQKfyIAAxYACQl5IMYGAOwCABYACQl5IMYGAOwCACUAAgnTAX9EACQAAAEuAAUUBgkOAAgA3xwA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tendroni:BAAALgAFFAIJAwAAAA==.Tenten:BAABLgAFFH8IAAIhAAIJjxZXCACHAAAhAAIJjxZXCACHAAAAAA==.',
Th='Theory:BAABLgAECn9ZAAMJAAkJ1xqbBgDhAQAJAAkJJxqbBgDhAQAjAAIJ+hhwQACNAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCggJCAAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBwAAAA==.',
To='Tomjim:BAACLgAFFH8VAAMWAAgJUxhsFgC5AQAWAAcJwxdsFgC5AQAcAAMJZQXtEwCLAAAuAAQKfyYABBYACAlAIwsLAMUCABYACAlAIwsLAMUCABwABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn85AAIRAAkJQBxNDwA5AgARAAkJQBxNDwA5AgAAAA==.Treevive:BAACLgAFFH8TAAIKAAcJ0hsfBgALAgAKAAcJ0hsfBgALAgAuAAQKfx4AAgoACQlFIkEcAFoCAAoACQlFIkEcAFoCAAAA.Trencough:BAABLgAECn8YAAIJAAcJMg1YJgCOAAAJAAcJMg1YJgCOAAAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trost:BAAALgADCgEJAQAAAA==.Trystan:BAABLgAECn9MAAIdAAkJEB4LFgC+AgAdAAkJEB4LFgC+AgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIIAAYJaRMaHAArAQAIAAYJaRMaHAArAQAAAA==.',
Tu='Tugbote:BAAALgAECgUJBQAAAA==.Turl:BAABLgAECn8VAAIZAAYJEhLipQAxAQAZAAYJEhLipQAxAQABLgAECggJJgAYAEggAA==.Turlo:BAABLgAECn8mAAIYAAcJSCDOHwAFAgAYAAcJSCDOHwAFAgAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twobrews:BAABLgAFFH8FAAILAAUJ1Q/jDAD4AAALAAUJ1Q/jDAD4AAABLgAFFAYJGgAoAJwQAA==.Twoglaives:BAAALgAECggJDgABLgAFFAYJGgAoAJwQAA==.Twostep:BAACLgAFFH8aAAIoAAYJnBAyAwB3AQAoAAYJnBAyAwB3AQAuAAQKfyoAAigACQnzGRUDACwCACgACQnzGRUDACwCAAAA.',
['Tì']='Tìnktìnk:BAAALgADCgcJBwABLgAECgkJNgAEAE4XAA==.',
['Tø']='Tøm:BAACLgAFFH8WAAIdAAkJWR7FCABLAgAdAAkJWR7FCABLAgAuAAQKfyIAAh0ABwmkJTsYANgCAB0ABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgAECgIJAgAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgAFFAEJAQAAAA==.Unshookable:BAACLgAFFH8TAAIFAAMJgRfYJwCJAAAFAAMJgRfYJwCJAAAuAAQKfzUAAwUACQmVH1UVAG8CAAUACQmVH1UVAG8CACQAAQnFBA0kAB0AAAAA.',
Ur='Ursos:BAACLgAFFH8FAAMGAAMJLA4EFgB0AAAGAAIJBRIEFgB0AAAIAAEJegb3FAAoAAAuAAQKfyAAAgYABwl8GHYXAJYBAAYABwl8GHYXAJYBAAAA.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8XAAMWAAkJERh7HADyAQAWAAkJERh7HADyAQAcAAEJ1gFSTAApAAAAAA==.Valiantinter:BAAALgAECgEJAQAAAA==.Vallatris:BAAALgAECgcJDgAAAA==.Valomyr:BAAALgAECgMJAwABLgAECggJHgAOAE4dAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn9GAAIZAAgJuxe8DQBsAQAZAAgJuxe8DQBsAQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgAECgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgAECgYJBwABLgAFFAMJBQAGACwOAA==.Viracocha:BAABLgAFFH8JAAMMAAQJ/RrwRADVAAAMAAMJtxjwRADVAAAiAAEJCBp0GQBJAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgcJEQABAAAAAA==.',
Vo='Voidh:BAABLgAFFH8GAAIeAAUJ+AgPMwCjAAAeAAUJ+AgPMwCjAAAAAA==.Voidlockus:BAABLgAFFH8FAAITAAIJHgUjtwBoAAATAAIJHgUjtwBoAAAAAA==.Voodomon:BAAALgADCgQJBAABLgAFFAMJDAATAJUNAA==.',
Vu='Vulcin:BAABLgAECn8UAAIYAAcJZBjFAgAJAgAYAAcJZBjFAgAJAgABLgAFFAMJEAAZAJ0UAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAFFAEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIeAAYJdRpqWgB4AQAeAAYJdRpqWgB4AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.Whitegirls:BAAALgAECgYJBwAAAA==.',
Wi='Winder:BAAALgAECgYJDgAAAA==.Windercase:BAAALgAECgEJAQAAAA==.Windercurse:BAAALgAECgEJAwAAAA==.Winderk:BAAALgAECgMJBQAAAA==.Winderkin:BAAALgAECgEJAwAAAA==.Winderv:BAAALgAECgEJAgAAAA==.Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIDAAcJMhJkLwBiAQADAAcJMhJkLwBiAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8hAAIMAAcJCB1xIABNAgAMAAcJCB1xIABNAgABLgAECgYJEwABAAAAAA==.Xingcai:BAAALgAECgEJAQAAAA==.',
Xy='Xyfin:BAABLgAECn8rAAIRAAkJLx2JBgCaAgARAAkJLx2JBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.Yoshimitsu:BAAALgAECgEJAwAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQbAAYJvyB9DABwAQATAAUJcx6VXACzAQAbAAQJByJ9DABwAQASAAEJAABYYABOAAABLgAFFAIJBwAMACcjAA==.Zandramadas:BAABLgAECn9NAAQHAAkJFiCOFQAjAgAHAAkJFiCOFQAjAgAKAAgJqRloLAD9AQAGAAcJ2BNkHgBaAQAAAA==.Zaraline:BAABLgAECn9HAAIPAAkJoBwNGQCPAgAPAAkJoBwNGQCPAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJDwAAAA==.Zect:BAAALgAECgYJBgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIJAAgJrBvqPwADAgAJAAgJrBvqPwADAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAABLgAECn8gAAIZAAcJ0xaUCgCeAQAZAAcJ0xaUCgCeAQAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIJAAYJbBaQnwAtAQAJAAYJbBaQnwAtAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAABLgAECn8VAAIMAAkJpw4PZgApAQAMAAkJpw4PZgApAQAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIZAAkJUR5bHwCiAgAZAAkJUR5bHwCiAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECggJGwAXAFgYAA==.',
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
