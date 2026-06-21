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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Paladin-Retribution','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adrasteia:BAAALgAECgMJAwABLgAECgkJJgADAIEZAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIEAAYJ3xU4MwA7AQAEAAYJ3xU4MwA7AQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIFAAQJIRWYLAAOAQAFAAQJIRWYLAAOAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAABLgAECn8XAAQGAAkJHwZfQQChAAAHAAYJEwdWVgC3AAAGAAkJywJfQQChAAAIAAQJBgZGNQCIAAAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9EAAIJAAkJgB22IgB8AgAJAAkJgB22IgB8AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIKAAMJBxlENgDTAAAKAAMJBxlENgDTAAAuAAQKfyMAAwoACQn9IScJAP4CAAoACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAKAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAILAAYJVht9PQC4AQALAAYJVht9PQC4AQAAAA==.Amorsith:BAAALgAECgkJEgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8NAAMMAAMJ9h42PwCqAAAMAAIJxh42PwCqAAANAAEJVh9kPgBQAAAuAAQKfyUAAw0ACQnQIhIGAKICAA0ACAm+IBIGAKICAAwABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgYJDQAAAA==.Angrycrack:BAABLgAECn8aAAICAAkJ6xhUEwAJAgACAAkJ6xhUEwAJAgAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxpBLgBpAQAHAAYJzxpBLgBpAQAAAA==.Anjunabeets:BAABLgAFFH8qAAQOAAgJSBuRFQC4AQAOAAYJih6RFQC4AQAPAAYJYQ+fCQCAAQAQAAUJfRacDwBIAQAAAA==.Anthran:BAABLgAECn8mAAMRAAkJqw8jHwBYAQARAAYJzQ4jHwBYAQASAAcJJQwPhQAvAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgYJCwABLgAECgkJNgAMAGsXAA==.Archos:BAAALgAECgEJBgAAAA==.Arcon:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Arcscythe:BAABLgAECn8kAAITAAkJ4BYLAwAEAgATAAkJ4BYLAwAEAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgQJBgAAAA==.Artoo:BAABLgAECn8UAAICAAkJsRkxCgCBAgACAAkJsRkxCgCBAgAAAA==.',
As='Asleep:BAAALgAECgYJCwABLgAECgkJNgAMAGsXAA==.Assaulter:BAAALgAECgYJEAABLgAFFAEJAQABAAAAAA==.Astralpanda:BAABLgAECn8ZAAIUAAgJKAq9SgAKAQAUAAgJKAq9SgAKAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn80AAIVAAkJmA9KJQC0AQAVAAkJmA9KJQC0AQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAWADEYAA==.Baer:BAABLgAECn8eAAIGAAgJ9gebOwC3AAAGAAgJ9gebOwC3AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn82AAIXAAkJWA9RKQDCAQAXAAkJWA9RKQDCAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8lAAISAAcJAQunkAAZAQASAAcJAQunkAAZAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAYAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8aAAIZAAgJdhtPEQDWAQAZAAgJdhtPEQDWAQAAAA==.Bauchelaine:BAABLgAECn8iAAMSAAgJRBAAYgB7AQASAAgJRBAAYgB7AQAaAAEJEAZNRAAoAAAAAA==.Bavunga:BAABLgAECn8pAAIbAAkJhCCtAgA3AwAbAAkJhCCtAgA3AwAAAA==.Bayle:BAAALgAECgUJCQAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Bearme:BAAALgADCgMJAwAAAA==.Beastadi:BAAALgAFFAMJAwAAAA==.Beelieve:BAAALgADCgYJBgAAAA==.Beoron:BAACLgAFFH8HAAIIAAMJoxygDADsAAAIAAMJoxygDADsAAAuAAQKfy0AAggACQlbJQgBAFADAAgACQlbJQgBAFADAAEuAAUUBAkKABUAkBEA.Bettyßastion:BAABLgAECn8yAAIcAAkJrx83GwChAgAcAAkJrx83GwChAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJDAABAAAAAA==.Bioenergy:BAAALgAECgkJDAAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJDAABAAAAAA==.Biolysis:BAAALgAECgMJAwABLgAECgkJDAABAAAAAA==.Bisoncrusher:BAAALgAECggJEQAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Blockhead:BAAALgADCgIJAgABLgAECgkJNgAMAGsXAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAABLgAECn8YAAIWAAgJhAc5QQALAQAWAAgJhAc5QQALAQABLgAFFAMJGQALAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMQAAgJQSVlAgAeAwAQAAgJQSVlAgAeAwAPAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAABLgAECn8WAAIUAAgJ+xJ9KwCYAQAUAAgJ+xJ9KwCYAQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAABLgAECn8YAAQZAAkJ6hr1HgA7AQAMAAgJZBZOTgBuAQAZAAQJgRn1HgA7AQANAAMJ+xAfUACSAAAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMOAAcJZxOUeABOAQAOAAcJZxOUeABOAQAQAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgUJCQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
['Bé']='Béllas:BAAALgAFFAEJAQAAAA==.',
Ca='Caliboy:BAAALgAECgEJAQABLgAECgkJKgALAFsRAA==.Calißoy:BAABLgAECn8qAAILAAkJWxEOPAC+AQALAAkJWxEOPAC+AQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJBAABAAAAAA==.Cannyon:BAAALgAECgQJBwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgAECgQJBAABLgAECgkJRAACAE4lAA==.Ceruledge:BAABLgAECn8fAAIdAAgJyxSjRwCvAQAdAAgJyxSjRwCvAQABLgAFFAMJBgAWADwWAA==.',
Ch='Chabar:BAEALgAFFAEJAQABLgAFFAgJGAAHALsSAA==.Chaboomy:BAECLgAFFH8YAAIHAAgJuxJgCgD1AQAHAAgJuxJgCgD1AQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn82AAIMAAkJaxflGQAfAgAMAAkJaxflGQAfAgAAAA==.Chopper:BAACLgAFFH8SAAIIAAUJ7BphBgBHAQAIAAUJ7BphBgBHAQAuAAQKfyYAAggACQn9IWYDAAEDAAgACQn9IWYDAAEDAAEuAAUUBgkYABoArxQA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAIeAAQJsxG3KAAGAQAeAAQJsxG3KAAGAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMEAAcJfBWpJgC4AQAEAAcJ5hSpJgC4AQADAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn8+AAIIAAkJbiaaAABuAwAIAAkJbiaaAABuAwAAAA==.Colmoore:BAAALgAFFAEJAgABLgAFFAUJEgASAH0aAA==.Conkerin:BAABLgAFFH8HAAIOAAMJqhehXQDpAAAOAAMJqhehXQDpAAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJCgAAAA==.Crusible:BAAALgAECgUJDQAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cucumbered:BAAALgADCgUJBQABLgAFFAEJAgABAAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAfAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCQABLgAFFAIJBgALACcjAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIKAAgJVgqCTgBqAQAKAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgcJEQAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8GAAILAAIJ0CJHTQC+AAALAAIJ0CJHTQC+AAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQRAAkJwhhuGwByAQASAAgJAhKFXwCBAQARAAcJZBZuGwByAQAaAAIJ0RhfKgBxAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAUJGAAgAJsjAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAYJIAACAM8cAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIJAAkJCxunKABeAgAJAAkJCxunKABeAgAAAA==.Deepman:BAAALgAFFAEJAQAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Denar:BAAALgAECgEJAQAAAA==.Deo:BAABLgAECn8/AAMhAAkJdyTBAQApAwAhAAkJdyTBAQApAwAXAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAAOAHcDAA==.Disastrous:BAACLgAFFH8SAAIOAAYJoxRLIwB4AQAOAAYJoxRLIwB4AQAuAAQKfzMAAg4ACQlCIMYRAKoCAA4ACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJOAAfAKMiAA==.',
Do='Doe:BAAALgAECgQJBAAAAA==.Doomangel:BAABLgAECn8UAAIJAAYJuhGMtAAOAQAJAAYJuhGMtAAOAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAABLgAECn8VAAIMAAYJGQbQYwDKAAAMAAYJGQbQYwDKAAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJGQALAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAYALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJLgARAK4eAA==.Dragonslock:BAABLgAECn8VAAQSAAcJKQ4npgD1AAASAAYJcA4npgD1AAARAAIJxAznPwAvAAAaAAEJiwNlRgAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIVAAcJDBGQJQCQAQAVAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMKAAkJtxGsRAB+AQAKAAcJRBGsRAB+AQAHAAgJ9QYuWQCuAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAFFAEJAQABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8gAAICAAYJzxwoDQDBAQACAAYJzxwoDQDBAQAuAAQKfzEAAgIACQkmJbUDAAoDAAIACQkmJbUDAAoDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAYJIAACAM8cAA==.',
['Dø']='Døc:BAABLgAECn9JAAQLAAkJ9xmJFACnAgALAAkJ9xmJFACnAgAUAAkJchGJJADDAQAiAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIhAAMJWQ5JDQClAAAhAAMJWQ5JDQClAAAuAAQKfyAAAyEACAl0G/8QALcBACEABwlyGP8QALcBABwABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8WAAMSAAgJ9w3TGwDqAQASAAgJ9w3TGwDqAQARAAEJagETGwBAAAAuAAQKfykAAxIACAl7HHQ1ADYCABIACAl7HHQ1ADYCABEAAQkAAMRfAE8AAAAA.',
El='Elanna:BAAALgAECgEJAQABLgAECgkJGAAZAOoaAA==.Eldoryn:BAABLgAECn8fAAIdAAkJMhnjKgBVAgAdAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9TAAIjAAkJUh2oCgBmAgAjAAkJUh2oCgBmAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erindralla:BAAALgAECgQJBQAAAA==.Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8YAAQaAAYJrxRVCwDHAAASAAYJrxIqNQBzAQAaAAMJAApVCwDHAAARAAIJ6AcCFwB8AAAuAAQKfy4ABBIACQn5GhVEAM8BABIACAloGBVEAM8BABEACAmiFL0fAFQBABoAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAUJGAAgAJsjAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJDQABLgAECgcJEQABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Felshadra:BAABLgAFFH8FAAISAAUJQweLZwD2AAASAAUJQweLZwD2AAAAAA==.',
Fi='Finnland:BAAALgAECgEJAQABLgAFFAIJCQAjAMoaAA==.Finntastic:BAAALgADCgYJCAABLgAFFAIJCQAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCQAjAMoaAA==.Fisterdobble:BAABLgAECn9BAAIYAAkJ2xYSTwDuAQAYAAkJ2xYSTwDuAQAAAA==.Fisticuffs:BAAALgADCgMJAwAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Flawlesshope:BAAALgADCgkJCQAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAABLgAECn8ZAAMLAAkJOR2rGACEAgALAAgJhByrGACEAgAiAAkJ9RkeBgB6AgABLgAECggJGgAFAA0jAA==.Forgeddemon:BAABLgAECn8XAAMeAAgJJgmlRQArAQAeAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAQJDwAFAJYaAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIhAAkJ0h6MBgB/AgAhAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIYAAgJGRS0bACiAQAYAAgJGRS0bACiAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Funeral:BAAALgAECgYJBgABLgAFFAEJAQABAAAAAA==.Furionik:BAABLgAECn8YAAMZAAcJFBQ2GACUAQAZAAcJFBQ2GACUAQAMAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIhAAYJ1hfeGQBKAQAhAAYJ1hfeGQBKAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJCQAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8WAAIcAAgJIxvsRgDxAQAcAAgJIxvsRgDxAQAAAA==.Gonga:BAAALgAECgEJAQAAAA==.Goodboy:BAABLgAFFH8IAAIOAAQJdwOhcAC/AAAOAAQJdwOhcAC/AAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn82AAIKAAgJ4BMGAgDTAAAKAAgJ4BMGAgDTAAAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8YAAIgAAUJmyNKAgCWAQAgAAUJmyNKAgCWAQAuAAQKfxoAAiAACAlcJBUCAOgCACAACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8bAAILAAYJ/xTgTwByAQALAAYJ/xTgTwByAQAAAA==.',
Gu='Gulaj:BAABLgAECn8aAAIOAAkJthuFWwCTAQAOAAkJthuFWwCTAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.Guttsholycow:BAAALgAECgcJBwAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQaAAkJRROkCQDIAQASAAgJ1RFYRQD7AQAaAAkJNxKkCQDIAQARAAQJ2wfRPwAvAAAAAA==.',
He='Healgimp:BAACLgAFFH8IAAIEAAMJ3hiWHADTAAAEAAMJ3hiWHADTAAAuAAQKfyIAAgQACQmLFUUgAMABAAQACQmLFUUgAMABAAAA.Healslux:BAABLgAECn8eAAIXAAkJvx9ODQC9AgAXAAkJvx9ODQC9AgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hortzel:BAABLgAECn8UAAISAAYJOA5YoQD9AAASAAYJOA5YoQD9AAAAAA==.Hotrollz:BAAALgAECgQJBwABLgAECgkJGQAKAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAABLgAECn8dAAIcAAgJqh5kAwAQAQAcAAgJqh5kAwAQAQAAAA==.Huntus:BAABLgAECn84AAMOAAkJsCNDDADxAgAOAAkJsCNDDADxAgAPAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIcAAgJHxbqaQCbAQAcAAgJHxbqaQCbAQAAAA==.',
Ic='Icy:BAAALgAECggJCQAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAVAAcJjxKLIgCqAQAAAA==.Impostor:BAACLgAFFH8FAAIWAAMJ3wg3KAC8AAAWAAMJ3wg3KAC8AAAuAAQKfzIAAhYACQl2IIEHANgCABYACQl2IIEHANgCAAAA.',
In='Indabow:BAABLgAECn8gAAIOAAkJbRopKAAXAgAOAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAeAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8fAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAdAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIdAAIJvCHpaQC4AAAdAAIJvCHpaQC4AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8uAAIkAAkJEx4HCQC1AgAkAAkJEx4HCQC1AgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8XAAMCAAYJ9BrPFgBXAQACAAUJsh3PFgBXAQAgAAIJggvuAABhAAAuAAQKfx0AAwIACQkjHuURABgCAAIACQlCHeURABgCACAABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8bAAIeAAgJexA6CgDuAQAeAAgJexA6CgDuAQAuAAQKfyQAAh4ACAnxElshAPcBAB4ACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJDQABLgAECgcJEQABAAAAAA==.Juul:BAABLgAECn8YAAIVAAkJ2RV/FgAkAgAVAAkJ2RV/FgAkAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAUJEQAWAFcJAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAUJEQAWAFcJAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgAECgYJCAABLgAECgcJFwANAM8gAA==.Karram:BAAALgADCgYJBgAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Kc='Kcup:BAAALgADCgIJAgAAAA==.',
Ke='Kelemvor:BAABLgAECn8+AAIdAAkJlx3zFQDTAgAdAAkJlx3zFQDTAgAAAA==.Keranos:BAAALgADCgMJAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8YAAIjAAYJAhUTGwAOAQAjAAYJAhUTGwAOAQAuAAQKfxcAAiMACQlWGQAPABwCACMACQlWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Kidslaps:BAABLgAECn8eAAIeAAgJTAxQMABCAQAeAAgJTAxQMABCAQAAAA==.Killeos:BAAALgAECgEJAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8PAAIFAAQJlhrjJgA3AQAFAAQJlhrjJgA3AQAuAAQKfycABAUACQn+F6IgAK4BAAUACQn+F6IgAK4BAB4AAQlKDJSIAD0AACQAAQk9D9+bADMAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8lAAIOAAkJKBqBKAA9AgAOAAkJKBqBKAA9AgABLgAFFAEJAQABAAAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8kAAQSAAgJagfyjwAbAQASAAcJagfyjwAbAQARAAUJxAQvLgBhAAAaAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAISAAkJiBqJHgBtAgASAAkJiBqJHgBtAgAAAA==.',
Lh='Lhux:BAABLgAECn8uAAIOAAgJ/iO9DADZAgAOAAgJ/iO9DADZAgAAAA==.Lhuxi:BAACLgAFFH8bAAIVAAUJwRj6AgAsAQAVAAUJwRj6AgAsAQAuAAQKfy0AAhUACQnwHdAJALsCABUACQnwHdAJALsCAAEuAAQKCAkuAA4A/iMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAACLgAFFH8GAAIcAAMJYBo5YADvAAAcAAMJYBo5YADvAAAuAAQKfxQAAhwACQnBGu8kAHECABwACQnBGu8kAHECAAAA.Lightisright:BAAALgAECgYJCwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIcAAgJaBBxdACFAQAcAAgJaBBxdACFAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8XAAIHAAYJABS1FgBlAQAHAAYJABS1FgBlAQAuAAQKfy0AAgcACQk0IJ8IAMoCAAcACQk0IJ8IAMoCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIKAAkJdA0ORwB0AQAKAAkJdA0ORwB0AQAAAA==.Luceean:BAAALgAECgEJAQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAgAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSQALAPcZAA==.Lyxxie:BAABLgAECn9LAAMJAAkJQBunRQDxAQAJAAkJQBunRQDxAQAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIYAAkJsBxuKgBwAgAYAAkJsBxuKgBwAgAAAA==.Mageus:BAAALgAFFAIJAwAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manchop:BAAALgAECgEJAQAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECggJFAAhANYXAA==.Marici:BAAALgADCgMJAwAAAA==.Mattxtz:BAAALgADCgMJAwABLgAECgkJMQAYALAcAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8fAAIMAAkJ8g0YLACkAQAMAAkJ8g0YLACkAQABLgAFFAMJGQALAMMYAA==.Metsutan:BAABLgAECn9EAAICAAkJTiUMBAD/AgACAAkJTiUMBAD/AgAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAACLgAFFH8FAAIWAAIJSQyHMACEAAAWAAIJSQyHMACEAAAuAAQKfzQAAxYACQk/FQweANUBABYACAlcFgweANUBAAQABgmwDBhgALIAAAAA.Moistfellow:BAABLgAECn8VAAIYAAYJHxYLvABqAQAYAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIaAAgJNCJ9AgCWAgAaAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAYALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAUJEQAWAFcJAA==.Moskeebee:BAABLgAECn8UAAIOAAcJyiUSEgCnAgAOAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8XAAMLAAkJmwKeewDtAAALAAkJmwKeewDtAAAUAAQJewH8kgBOAAAAAA==.',
['Mä']='Mätthew:BAAALgADCgQJBQAAAA==.',
['Må']='Måtthew:BAAALgAECgEJAQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAISAAcJoQr+jQAeAQASAAcJoQr+jQAeAQAAAA==.Møsh:BAAALgAECgkJCwABLgAFFAUJEQAWAFcJAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMSAAgJVBv0QwAAAgASAAgJVBv0QwAAAgARAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn9SAAMSAAkJPB2OAAAxAgASAAkJXRyOAAAxAgARAAgJpRxXBQAdAgAAAA==.Nemriel:BAAALgAECgcJDwAAAA==.Newthilena:BAAALgAFFAMJAwAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMdAAkJjxapRQC2AQAdAAkJzxCpRQC2AQAfAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Normandy:BAAALgADCgEJAQABLgAFFAMJGQALAMMYAA==.Norsem:BAAALgAECgkJDgAAAA==.Nossem:BAAALgAECgEJAQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPQAMAKAlAA==.Nymera:BAAALgAECgMJAwABLgAECgcJIAAGAHwYAA==.',
['Nä']='Nämeless:BAAALgAFFAIJBAAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIDAAMJTBzzKwDyAAADAAMJTBzzKwDyAAAuAAQKfywAAgMACAlGIKMQAGgCAAMACAlGIKMQAGgCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ol='Olgaa:BAAALgAECgEJAQABLgAFFAYJDAAKAM8SAA==.',
On='Oneth:BAABLgAECn8UAAIaAAYJ3xC5FwAHAQAaAAYJ3xC5FwAHAQAAAA==.Onfleek:BAABLgAECn8yAAMEAAgJXCNRBwD6AgAEAAgJXCNRBwD6AgAWAAYJJA1BNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8ZAAILAAMJwxhfSQDJAAALAAMJwxhfSQDJAAAuAAQKf0MAAgsACQkdHa8UAKYCAAsACQkdHa8UAKYCAAAA.',
Or='Orakrak:BAABLgAECn8nAAIMAAkJHhFlJQDMAQAMAAkJHhFlJQDMAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgAECgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNQADAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNQADAB4lAA==.Parseval:BAABLgAECn81AAQDAAkJHiVRAgCWAwADAAkJHiVRAgCWAwAWAAgJ0RssFgAZAgAEAAQJPxsuQwAsAQAAAA==.Parshock:BAAALgAECgYJCwABLgAECgkJNQADAB4lAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPQAMAKAlAA==.Paws:BAABLgAECn89AAIMAAkJoCXFAwArAwAMAAkJoCXFAwArAwAAAA==.Pawsitivity:BAAALgAECgMJAwABLgAECgkJPQAMAKAlAA==.',
Pd='Pdbm:BAAALgAECgEJAwAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIXAAgJORg7PABXAQAXAAgJORg7PABXAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIiAAYJqg1dIAD1AAAiAAYJqg1dIAD1AAAAAA==.',
Pi='Pipsqueak:BAAALgAFFAEJAQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAEJAgAAAA==.Porkins:BAABLgAECn9AAAMjAAkJGSClCgBmAgAjAAgJmx+lCgBmAgAmAAkJqh2xBwAaAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgAECgYJCQAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAFFAEJAQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAdALwhAA==.',
Ps='Psyn:BAAALgAECgQJBAABLgAFFAQJGwALACMgAA==.Psyndar:BAAALgAECgEJAQABLgAFFAQJGwALACMgAA==.Psyndra:BAAALgAECgYJCQABLgAFFAQJGwALACMgAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8MAAIYAAMJ0BPdgADVAAAYAAMJ0BPdgADVAAAuAAQKfzMAAhgACQm5IJwVANcCABgACQm5IJwVANcCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAUJEQAWAFcJAA==.',
Qt='Qtip:BAAALgAECgMJAwAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8SAAISAAUJfRq5OgBhAQASAAUJfRq5OgBhAQAuAAQKfzIAAhIACAnDJBsMAO0CABIACAnDJBsMAO0CAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMdAAgJjRI/ZABfAQAdAAgJ7xE/ZABfAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8yAAMEAAkJrhVgIQC3AQAEAAkJrhVgIQC3AQAWAAUJ2gUQZQCHAAAAAA==.',
Re='Replicate:BAACLgAFFH8GAAIMAAMJYx33KwAEAQAMAAMJYx33KwAEAQAuAAQKfyMAAgwACQnrIdIFAAMDAAwACQnrIdIFAAMDAAAA.Resisted:BAAALgAECgEJAQABLgAFFAgJFQAVAFMYAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJPAAOAI0cAA==.',
Ru='Runeswipe:BAAALgAECgEJAgABLgAECgYJGwAXAEEdAA==.',
Ry='Ryanmonk:BAAALgAFFAEJAQAAAA==.Ryanqt:BAAALgAECgcJBwAAAA==.Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8WAAIXAAcJAx5IBgBpAgAXAAcJAx5IBgBpAgAuAAQKfzEAAhcACQmNJd0AAJIDABcACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJEAAAAA==.Ryri:BAABLgAECn8fAAIhAAcJXxVAFQB+AQAhAAcJXxVAFQB+AQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMDAAkJlgqwIgB+AQADAAkJlgqwIgB+AQAWAAIJGQvEdABXAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMeAAkJbQm7KwBbAQAeAAkJbQm7KwBbAQAFAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJBgAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECggJEQAAAA==.Santoku:BAABLgAECn8QAAIdAAYJsxdWbQBJAQAdAAYJsxdWbQBJAQAAAA==.Sarah:BAACLgAFFH8RAAIDAAUJiBYeHQB0AQADAAUJiBYeHQB0AQAuAAQKfzMAAgMACQmxH4cFADADAAMACQmxH4cFADADAAAA.Sass:BAAALgAECgQJBAAAAA==.Sassyface:BAABLgAECn9KAAIRAAkJ7Q78CwB/AQARAAkJ7Q78CwB/AQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Sc='Scarletdawns:BAAALgADCgEJAQAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAKAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAABLgAECn8XAAMNAAcJzyCeCgBAAgANAAcJzyCeCgBAAgAMAAEJcRuSkABRAAAAAA==.Shaduw:BAACLgAFFH8bAAIZAAgJGx5oBAAmAgAZAAgJGx5oBAAmAgAuAAQKfyQAAxkACAnOIbMDABkDABkACAnOIbMDABkDAAwACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBCbKwA8AQACAAcJkBCbKwA8AQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJEAABLgAECgkJJgARAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIWAAMJPBYEJQDPAAAWAAMJPBYEJQDPAAAuAAQKfzYAAhYACQlGIfwFAC4DABYACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIYAAMJCBtmfgDaAAAYAAMJCBtmfgDaAAAuAAQKfycAAhgACQlNIykVACkDABgACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMXAAgJniPOEACMAgAXAAgJniPOEACMAgAcAAQJrRjxMgF8AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMFAAgJDSPpCQC0AgAFAAcJnyLpCQC0AgAkAAYJJBWBNAAxAQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQgAAgJEBcgCQCxAQAgAAgJyhUgCQCxAQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgUJCwAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAUJEQAWAFcJAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIcAAkJjwQq1wDpAAAcAAkJjwQq1wDpAAAAAA==.Stelthme:BAABLgAECn8aAAQgAAYJIxjnCwBwAQAgAAYJIxjnCwBwAQAnAAMJQwi5GgB7AAACAAEJGAiiXgA5AAABLgAFFAQJDgACAEwlAA==.Stormburst:BAAALgADCgIJAgABLgAFFAUJGAAgAJsjAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIYAAcJQyFKOgCNAgAYAAcJQyFKOgCNAgABLgAECggJFAAQAEElAA==.',
Su='Susaki:BAAALgAECgQJBQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAAQAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8wAAIZAAkJJSFOAwACAwAZAAkJJSFOAwACAwAAAA==.Takeshì:BAAALgAECgcJBwABLgAECgkJMgAEAK4VAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8KAAIVAAQJkBHOMwDzAAAVAAQJkBHOMwDzAAAuAAQKfyIAAxUACQl5IMcGAOwCABUACQl5IMcGAOwCACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgAFFAIJAgAAAA==.',
Th='Theory:BAABLgAECn9YAAMJAAkJ1xrjAAD2AQAJAAkJJxrjAAD2AQAjAAIJ+hhuQACNAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBwAAAA==.',
To='Tomjim:BAACLgAFFH8VAAMVAAgJUxiPFgC4AQAVAAcJwxePFgC4AQAbAAMJZQXtEwCLAAAuAAQKfyYABBUACAlAIwsLAMUCABUACAlAIwsLAMUCABsABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn85AAIQAAkJQBxPDwA5AgAQAAkJQBxPDwA5AgAAAA==.Treevive:BAACLgAFFH8MAAIKAAYJzxKQFwCjAQAKAAYJzxKQFwCjAQAuAAQKfxkAAgoACAmaIEEcAFoCAAoACAmaIEEcAFoCAAAA.Trencough:BAAALgAECgYJEgAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn9MAAIcAAkJEB4LFgC+AgAcAAkJEB4LFgC+AgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIIAAYJaRMYHAArAQAIAAYJaRMYHAArAQAAAA==.',
Tu='Tugbote:BAAALgAECgUJBQAAAA==.Turl:BAABLgAECn8VAAIYAAYJEhLfpQAxAQAYAAYJEhLfpQAxAQABLgAECggJJgAXAEggAA==.Turlo:BAABLgAECn8mAAIXAAcJSCDPHwAFAgAXAAcJSCDPHwAFAgAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAYJGQAnAJwQAA==.Twostep:BAACLgAFFH8ZAAInAAYJnBAyAwB3AQAnAAYJnBAyAwB3AQAuAAQKfyoAAicACQnzGRUDACwCACcACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8UAAIcAAgJZR7KCABLAgAcAAgJZR7KCABLAgAuAAQKfyIAAhwABwmkJTsYANgCABwABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8MAAIFAAMJDBTvPACxAAAFAAMJDBTvPACxAAAuAAQKfzQAAwUACQkNH1YVAG8CAAUACQkNH1YVAG8CACQAAQnFBMMHACIAAAAA.',
Ur='Ursos:BAABLgAECn8gAAIGAAcJfBh2FwCWAQAGAAcJfBh2FwCWAQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8XAAMVAAkJERh7HADyAQAVAAkJERh7HADyAQAbAAEJ1gFSTAApAAAAAA==.Valiantinter:BAAALgAECgEJAQAAAA==.Vallatris:BAAALgAECgcJDgAAAA==.Valomyr:BAAALgAECgMJAwABLgAECgcJFwANAM8gAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn9BAAIYAAgJuxc1AgBgAQAYAAgJuxc1AgBgAQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgAECgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgAECgEJAQABLgAECgcJIAAGAHwYAA==.Viracocha:BAABLgAFFH8JAAMLAAQJ/RrsRADVAAALAAMJtxjsRADVAAAiAAEJCBp2GQBJAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgcJEQABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAFFAIJAwAAAA==.',
Vu='Vulcin:BAAALgAECgcJDwABLgAFFAMJDAAYANATAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIdAAYJdRprWgB4AQAdAAYJdRprWgB4AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.Whitegirls:BAAALgAECgIJAgAAAA==.',
Wi='Winder:BAAALgAECgYJDgAAAA==.Windercase:BAAALgAECgEJAQAAAA==.Windercurse:BAAALgAECgEJAwAAAA==.Winderk:BAAALgAECgMJBQAAAA==.Winderkin:BAAALgAECgEJAwAAAA==.Winderv:BAAALgAECgEJAQAAAA==.Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIDAAcJMhJjLwBiAQADAAcJMhJjLwBiAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8ZAAILAAcJAR1wIABNAgALAAcJAR1wIABNAgABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8oAAIQAAkJVRyJBgCaAgAQAAkJVRyJBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.Yoshimitsu:BAAALgAECgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQaAAYJvyB9DABwAQASAAUJcx6VXACzAQAaAAQJByJ9DABwAQARAAEJAABYYABOAAABLgAFFAIJBgALACcjAA==.Zandramadas:BAABLgAECn9NAAQHAAkJFiCNFQAjAgAHAAkJFiCNFQAjAgAKAAgJqRloLAD9AQAGAAcJ2BNjHgBaAQAAAA==.Zaraline:BAABLgAECn88AAIOAAkJjRwOGQCPAgAOAAkJjRwOGQCPAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCwAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIJAAgJrBvnPwADAgAJAAgJrBvnPwADAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAAALgAECgYJDwAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIJAAYJbBaPnwAtAQAJAAYJbBaPnwAtAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIYAAkJUR5cHwCiAgAYAAkJUR5cHwCiAgAAAA==.',
['Ði']='Ðisperse:BAAALgAECgUJBQABLgAECggJGwAWAFgYAA==.',
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
