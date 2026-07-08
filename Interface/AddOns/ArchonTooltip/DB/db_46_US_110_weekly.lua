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

local lookup = {'Unknown-Unknown','Rogue-Subtlety','Priest-Discipline','Priest-Holy','Monk-Mistweaver','Druid-Guardian','Druid-Balance','Druid-Feral','DeathKnight-Unholy','Druid-Restoration','Shaman-Restoration','Warrior-Fury','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Mage-Fire','Shaman-Elemental','Evoker-Augmentation','Priest-Shadow','Paladin-Holy','Mage-Frost','Warrior-Protection','Warlock-Affliction','Evoker-Preservation','Paladin-Retribution','DemonHunter-Devourer','Monk-Brewmaster','DemonHunter-Havoc','Rogue-Assassination','Paladin-Protection','Shaman-Enhancement','DeathKnight-Blood','Monk-Windwalker','Evoker-Devastation','DeathKnight-Frost','DemonHunter-Vengeance','Rogue-Outlaw',}
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-07-05',data={Ab='Abracadabra:BAAALgAECgYJDQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJDQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adrasteia:BAAALgAECgMJAwABLgAECgkJKAADAIEZAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.Agunagun:BAAALgAECgEJAQAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIEAAYJ3xU9MwA7AQAEAAYJ3xU9MwA7AQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIFAAQJIRWcLAAOAQAFAAQJIRWcLAAOAQAAAA==.Alexiel:BAAALgAECgIJAgAAAA==.Alfuric:BAABLgAECn8XAAQGAAkJHwZgQQChAAAHAAYJEwdcVgC3AAAGAAkJywJgQQChAAAIAAQJBgZENQCIAAAAAA==.Aliviana:BAAALgAECgEJAQABLgAECgkJKAADAIEZAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9EAAIJAAkJgB23IgB8AgAJAAkJgB23IgB8AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIKAAMJBxk/NgDTAAAKAAMJBxk/NgDTAAAuAAQKfyMAAwoACQn9IScJAP4CAAoACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAKAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAILAAYJVht/PQC4AQALAAYJVht/PQC4AQAAAA==.Amorsith:BAAALgAECgkJEgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8NAAMMAAMJ9h4xPwCqAAAMAAIJxh4xPwCqAAANAAEJVh9hPgBQAAAuAAQKfyUAAw0ACQnQIhIGAKICAA0ACAm+IBIGAKICAAwABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgYJDQAAAA==.Angrycrack:BAABLgAECn8aAAICAAkJ6xhUEwAJAgACAAkJ6xhUEwAJAgAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxpGLgBpAQAHAAYJzxpGLgBpAQAAAA==.Anjunabeets:BAABLgAFFH80AAQOAAkJTB6PFQC4AQAOAAcJ5h6PFQC4AQAPAAYJHhOfCQCAAQAQAAUJfRacDwBIAQAAAA==.Anthran:BAABLgAECn8mAAMRAAkJqw8jHwBYAQARAAYJzQ4jHwBYAQASAAcJJQwThQAvAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgYJCwABLgAECgkJOAAMAGsXAA==.Archos:BAAALgAECgEJBgAAAA==.Arcon:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Arcscythe:BAABLgAECn8lAAITAAkJ4BYLAwAEAgATAAkJ4BYLAwAEAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgQJBgAAAA==.Artoo:BAABLgAECn8WAAICAAkJSBwzCgCBAgACAAkJSBwzCgCBAgAAAA==.',
As='Asleep:BAAALgAECgYJCwABLgAECgkJOAAMAGsXAA==.Assaulter:BAAALgAECgYJEAABLgAECgkJKgAOAEEaAA==.Astralpanda:BAABLgAECn8ZAAIUAAgJKAq9SgAKAQAUAAgJKAq9SgAKAQAAAA==.Asunä:BAAALgADCgQJBAAAAA==.',
At='Athair:BAAALgAECgMJAwAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn9BAAIVAAkJjhR0AQDYAQAVAAkJjhR0AQDYAQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAWADEYAA==.Baer:BAABLgAECn8eAAIGAAgJ9geaOwC3AAAGAAgJ9geaOwC3AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn83AAIXAAkJWA9TKQDCAQAXAAkJWA9TKQDCAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8lAAISAAcJAQurkAAZAQASAAcJAQurkAAZAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAYAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8aAAIZAAgJdhtNEQDWAQAZAAgJdhtNEQDWAQAAAA==.Bauchelaine:BAABLgAECn8iAAMSAAgJRBD/YQB7AQASAAgJRBD/YQB7AQAaAAEJEAZLRAAoAAAAAA==.Bavunga:BAABLgAECn8pAAIbAAkJhCCtAgA3AwAbAAkJhCCtAgA3AwAAAA==.Bawitaba:BAAALgAECggJCAAAAA==.Bayle:BAAALgAECgUJCQAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Bearme:BAAALgADCgQJBAAAAA==.Beastadi:BAAALgAFFAMJBAAAAA==.Beelieve:BAAALgADCgYJBgAAAA==.Beoron:BAACLgAFFH8IAAIIAAMJyB+iDADsAAAIAAMJyB+iDADsAAAuAAQKfy0AAggACQlbJQgBAFADAAgACQlbJQgBAFADAAEuAAUUBAkKABUAkBEA.Bettyßastion:BAABLgAECn8yAAIcAAkJrx84GwChAgAcAAkJrx84GwChAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJDAABAAAAAA==.Bioenergy:BAAALgAECgkJDAAAAA==.Biogen:BAAALgAECgMJBAABLgAECgkJDAABAAAAAA==.Biolysis:BAAALgAECgMJAwABLgAECgkJDAABAAAAAA==.Bisoncrusher:BAAALgAECggJEQAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Blockhead:BAAALgADCgIJBAABLgAECgkJOAAMAGsXAA==.Bloodstone:BAAALgAECgYJCgAAAA==.Blowtortch:BAAALgAECgYJBgAAAA==.',
Bo='Boagrius:BAABLgAECn8YAAIWAAgJhAc/QQALAQAWAAgJhAc/QQALAQABLgAFFAMJGgALAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMQAAgJQSVlAgAeAwAQAAgJQSVlAgAeAwAPAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAACLgAFFH8HAAIUAAIJfQxQGgB6AAAUAAIJfQxQGgB6AAAuAAQKfxYAAhQACAn7En8rAJgBABQACAn7En8rAJgBAAAA.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAABLgAECn8ZAAQZAAkJ6hr1HgA7AQAMAAgJZBZOTgBuAQAZAAQJgRn1HgA7AQANAAMJ+xAfUACSAAAAAA==.Bruus:BAAALgAFFAEJAgAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMOAAcJZxOSeABOAQAOAAcJZxOSeABOAQAQAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgUJCQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
['Bé']='Béllas:BAAALgAFFAEJAQAAAA==.',
Ca='Caliboy:BAAALgAECgEJAQABLgAECgkJKgALAFsRAA==.Calihots:BAAALgADCgEJAQABLgAECgkJKgALAFsRAA==.Calißoy:BAABLgAECn8qAAILAAkJWxEQPAC+AQALAAkJWxEQPAC+AQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJBAABAAAAAA==.Cannyon:BAAALgAECgQJBwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgAECgQJBAABLgAECgkJRgACAE4lAA==.Cerberus:BAAALgAFFAIJAwAAAA==.Ceruledge:BAABLgAECn8fAAIdAAgJyxSjRwCvAQAdAAgJyxSjRwCvAQABLgAFFAMJBgAWADwWAA==.',
Ch='Chabar:BAEALgAFFAEJAQABLgAFFAgJGAAHALsSAA==.Chaboomy:BAECLgAFFH8YAAIHAAgJuxJSCgD1AQAHAAgJuxJSCgD1AQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn84AAIMAAkJaxflGQAfAgAMAAkJaxflGQAfAgAAAA==.Chopper:BAACLgAFFH8SAAIIAAUJ7BpgBgBHAQAIAAUJ7BpgBgBHAQAuAAQKfyYAAggACQn9IWYDAAEDAAgACQn9IWYDAAEDAAEuAAUUBgkYABoArxQA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAIeAAQJsxGxKAAGAQAeAAQJsxGxKAAGAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMEAAcJfBWpJgC4AQAEAAcJ5hSpJgC4AQADAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn9AAAIIAAkJbiaaAABuAwAIAAkJbiaaAABuAwAAAA==.Colmoore:BAAALgAFFAEJAgABLgAFFAUJFgASAJUeAA==.Conkerin:BAABLgAFFH8HAAIOAAMJqhegXQDpAAAOAAMJqhegXQDpAAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJCgAAAA==.Crusible:BAAALgAECgUJDQAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cucumbered:BAAALgADCgUJBQABLgAFFAIJBAABAAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAfAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCQABLgAFFAIJBwALACcjAA==.Dapper:BAAALgADCgIJAgAAAA==.Darii:BAAALgAECgEJAQAAAA==.Darkis:BAABLgAECn8WAAIKAAgJVgqCTgBqAQAKAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgcJEQAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8HAAILAAIJ0CJJTQC+AAALAAIJ0CJJTQC+AAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQRAAkJwhhuGwByAQASAAgJAhKEXwCBAQARAAcJZBZuGwByAQAaAAIJ0RhfKgBxAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAUJHAAgAJsjAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAYJIAACAM8cAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIJAAkJCxuoKABeAgAJAAkJCxuoKABeAgAAAA==.Deepman:BAAALgAFFAEJAQABLgAECgkJKgAOAEEaAA==.Delessia:BAAALgADCgIJAgAAAA==.Denar:BAAALgAECgEJAQAAAA==.Deo:BAABLgAECn9BAAMhAAkJdyTBAQApAwAhAAkJdyTBAQApAwAXAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCQAOAD4FAA==.Disastrous:BAACLgAFFH8YAAIOAAcJZRJ8DwBcAQAOAAcJZRJ8DwBcAQAuAAQKfzMAAg4ACQlCIMYRAKoCAA4ACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAFFAUJBQAfAGQOAA==.',
Do='Doe:BAAALgAECgQJBAAAAA==.Doomangel:BAABLgAECn8UAAIJAAYJuhGStAAOAQAJAAYJuhGStAAOAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAABLgAECn8cAAIMAAcJqQhrCgC/AAAMAAcJqQhrCgC/AAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJGgALAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAYALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJNQARAMQeAA==.Dragonslock:BAABLgAECn8VAAQSAAcJKQ4opgD1AAASAAYJcA4opgD1AAARAAIJxAznPwAvAAAaAAEJiwNiRgAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIVAAcJDBGQJQCQAQAVAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMKAAkJtxGqRAB+AQAKAAcJRBGqRAB+AQAHAAgJ9QYzWQCuAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAECgkJKgAOAEEaAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8gAAICAAYJzxwfDQDBAQACAAYJzxwfDQDBAQAuAAQKfzEAAgIACQkmJbUDAAoDAAIACQkmJbUDAAoDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAYJIAACAM8cAA==.',
['Dø']='Døc:BAABLgAECn9LAAQLAAkJ9xmIFACnAgALAAkJ9xmIFACnAgAUAAkJXxKHJADDAQAiAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIhAAMJWQ5JDQClAAAhAAMJWQ5JDQClAAAuAAQKfyAAAyEACAl0G/8QALcBACEABwlyGP8QALcBABwABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8XAAMSAAgJ9w20GwDqAQASAAgJ9w20GwDqAQARAAEJagETGwBAAAAuAAQKfykAAxIACAl7HHQ1ADYCABIACAl7HHQ1ADYCABEAAQkAAMRfAE8AAAAA.',
El='Elanna:BAAALgAECgEJAQABLgAECgkJGQAZAOoaAA==.Eldoryn:BAABLgAECn8fAAIdAAkJMhnjKgBVAgAdAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9VAAIjAAkJUh2mCgBmAgAjAAkJUh2mCgBmAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erindralla:BAAALgAECgQJBQAAAA==.Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8YAAQaAAYJrxRVCwDHAAASAAYJrxIGNQBzAQAaAAMJAApVCwDHAAARAAIJ6Af7FgB8AAAuAAQKfy4ABBIACQn5GhdEAM8BABIACAloGBdEAM8BABEACAmiFL0fAFQBABoAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAUJHAAgAJsjAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJDQABLgAECgcJEQABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Felshadra:BAABLgAFFH8FAAISAAUJQwd1ZwD2AAASAAUJQwd1ZwD2AAAAAA==.',
Fi='Finnland:BAAALgAECgEJAQABLgAFFAIJCQAjAMoaAA==.Finntastic:BAAALgADCgYJCAABLgAFFAIJCQAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCQAjAMoaAA==.Fisterdobble:BAABLgAECn9DAAIYAAkJMRcRTwDuAQAYAAkJMRcRTwDuAQAAAA==.Fisticuffs:BAAALgADCgMJAwAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Flawlesshope:BAAALgAECgQJBAAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAABLgAECn8ZAAMLAAkJOR2sGACEAgALAAgJhBysGACEAgAiAAkJ9RkdBgB6AgABLgAECggJGgAFAA0jAA==.Forgeddemon:BAABLgAECn8XAAMeAAgJJgmlRQArAQAeAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgUJCAAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAUJFAAFADgbAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIhAAkJ0h6MBgB/AgAhAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIYAAgJGRS0bACiAQAYAAgJGRS0bACiAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Funeral:BAAALgAECgYJDAABLgAECgkJKgAOAEEaAA==.Furionik:BAABLgAECn8YAAMZAAcJFBQ2GACUAQAZAAcJFBQ2GACUAQAMAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIhAAYJ1hfeGQBKAQAhAAYJ1hfeGQBKAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Genesìs:BAAALgAECgEJAQABLgAECgkJIQAWADEYAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJEAAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8WAAIcAAgJIxvqRgDyAQAcAAgJIxvqRgDyAQAAAA==.Gonga:BAAALgAECgEJAQAAAA==.Goodboy:BAABLgAFFH8JAAIOAAQJPgWdcAC/AAAOAAQJPgWdcAC/AAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn87AAIKAAgJVhRAPACjAQAKAAgJVhRAPACjAQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8cAAIgAAUJmyNKAgCWAQAgAAUJmyNKAgCWAQAuAAQKfxoAAiAACAlcJBUCAOgCACAACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8bAAILAAYJ/xTmTwByAQALAAYJ/xTmTwByAQAAAA==.',
Gu='Gulaj:BAABLgAECn8bAAIOAAkJzhuDWwCTAQAOAAkJzhuDWwCTAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.Guttsholycow:BAAALgAECgcJBwAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQaAAkJRROlCQDIAQASAAgJ1RFYRQD7AQAaAAkJNxKlCQDIAQARAAQJ2wfSPwAvAAAAAA==.',
He='Healgimp:BAACLgAFFH8OAAIEAAMJ3hhzCwCrAAAEAAMJ3hhzCwCrAAAuAAQKfyIAAgQACQmLFUggAMABAAQACQmLFUggAMABAAAA.Healslux:BAABLgAECn8eAAIXAAkJvx9ODQC9AgAXAAkJvx9ODQC9AgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hortzel:BAABLgAECn8UAAISAAYJOA5ZoQD9AAASAAYJOA5ZoQD9AAAAAA==.Hotrollz:BAAALgAECgQJBwABLgAECgkJGQAKAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAACLgAFFH8FAAIcAAEJmRGhTABKAAAcAAEJmRGhTABKAAAuAAQKfyAAAhwACQknHnkJAFIBABwACQknHnkJAFIBAAAA.Huntus:BAABLgAECn84AAMOAAkJsCM/DADxAgAOAAkJsCM/DADxAgAPAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIcAAgJHxbpaQCbAQAcAAgJHxbpaQCbAQAAAA==.',
Ic='Icy:BAAALgAECggJCQAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAVAAcJjxKLIgCqAQAAAA==.Impostor:BAACLgAFFH8FAAIWAAMJ3wg4KAC8AAAWAAMJ3wg4KAC8AAAuAAQKfzIAAhYACQl2IIEHANgCABYACQl2IIEHANgCAAAA.',
In='Indabow:BAABLgAECn8gAAIOAAkJbRopKAAXAgAOAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAeAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8fAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAdAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIdAAIJvCHaaQC4AAAdAAIJvCHaaQC4AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8xAAIkAAkJEx4HCQC1AgAkAAkJEx4HCQC1AgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8XAAMCAAYJ9BrHFgBXAQACAAUJsh3HFgBXAQAgAAIJggvLAwBcAAAuAAQKfx0AAwIACQkjHugRABgCAAIACQlCHegRABgCACAABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8cAAIeAAgJexAqCgDuAQAeAAgJexAqCgDuAQAuAAQKfyQAAh4ACAnxElshAPcBAB4ACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJDQABLgAECgcJEQABAAAAAA==.Juul:BAABLgAECn8YAAIVAAkJ2RWAFgAkAgAVAAkJ2RWAFgAkAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAQJBQAOAJ0KAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAQJBQAOAJ0KAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgAECgYJCAABLgAECgcJHAANAP4gAA==.Karram:BAAALgADCgYJBgAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Kc='Kcup:BAAALgADCgIJAgAAAA==.',
Ke='Kelemvor:BAABLgAECn8+AAIdAAkJlx3zFQDTAgAdAAkJlx3zFQDTAgAAAA==.Keranos:BAAALgADCgMJAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8YAAIjAAYJAhUNGwAOAQAjAAYJAhUNGwAOAQAuAAQKfxcAAiMACQlWGQAPABwCACMACQlWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Kidslaps:BAABLgAECn8eAAIeAAgJTAxTMABCAQAeAAgJTAxTMABCAQAAAA==.Killeos:BAAALgAECgEJAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8UAAIFAAUJOBuZDQBEAQAFAAUJOBuZDQBEAQAuAAQKfycABAUACQn+F6IgAK4BAAUACQn+F6IgAK4BAB4AAQlKDJiIAD0AACQAAQk9D92bADMAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8qAAIOAAkJQRp/KAA9AgAOAAkJQRp/KAA9AgAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Leethalrot:BAAALgAECgEJAQABLgAECgQJBQABAAAAAA==.Legosi:BAABLgAECn8kAAQSAAgJagf3jwAbAQASAAcJagf3jwAbAQARAAUJxAQwLgBhAAAaAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAISAAkJiBqKHgBtAgASAAkJiBqKHgBtAgAAAA==.',
Lh='Lhux:BAABLgAECn8wAAIOAAgJ/iO9DADZAgAOAAgJ/iO9DADZAgAAAA==.Lhuxi:BAACLgAFFH8dAAIVAAUJxxpZDAA1AQAVAAUJxxpZDAA1AQAuAAQKfzIAAhUACQnwHdAJALsCABUACQnwHdAJALsCAAEuAAQKCAkwAA4A/iMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAACLgAFFH8GAAIcAAMJYBorYADvAAAcAAMJYBorYADvAAAuAAQKfxYAAhwACQlZG+8kAHECABwACQlZG+8kAHECAAAA.Lightisright:BAAALgAECgYJCwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIcAAgJaBBvdACFAQAcAAgJaBBvdACFAQAAAA==.Liriel:BAAALgAECgEJAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8ZAAIHAAYJAxetFgBlAQAHAAYJAxetFgBlAQAuAAQKfy0AAgcACQk0IJ8IAMoCAAcACQk0IJ8IAMoCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIKAAkJdA0LRwB0AQAKAAkJdA0LRwB0AQAAAA==.Luceean:BAAALgAECgEJAQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAgAAAA==.Lurthshots:BAAALgAFFAEJAQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSwALAPcZAA==.Lyxxie:BAABLgAECn9LAAMJAAkJQBurRQDxAQAJAAkJQBurRQDxAQAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIYAAkJsBxrKgBwAgAYAAkJsBxrKgBwAgAAAA==.Mageus:BAAALgAFFAIJAwAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manchop:BAAALgAECgEJAQAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECggJFAAhANYXAA==.Marici:BAAALgADCgMJAwAAAA==.Mattxtz:BAAALgADCgMJAwABLgAECgkJMQAYALAcAA==.Maximosharp:BAAALgADCgUJBQABLgAECgkJOAAMAGsXAA==.',
Me='Mechanizedtv:BAABLgAECn8UAAMnAAkJPROoAAAGAgAnAAkJPROoAAAGAgAdAAMJ9AYoGQBoAAABLgAFFAQJFAAGAO4jAA==.Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8fAAIMAAkJ8g0YLACkAQAMAAkJ8g0YLACkAQABLgAFFAMJGgALAMMYAA==.Metsutan:BAABLgAECn9GAAICAAkJTiULBAD/AgACAAkJTiULBAD/AgAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAACLgAFFH8FAAIWAAIJSQyJMACEAAAWAAIJSQyJMACEAAAuAAQKfzcAAxYACQnJFQweANUBABYACAn6FgweANUBAAQABgmwDBhgALIAAAAA.Moistfellow:BAABLgAECn8VAAIYAAYJHxYLvABqAQAYAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIaAAgJNCJ9AgCWAgAaAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAYALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moogoboom:BAAALgADCgEJAQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAQJBQAOAJ0KAA==.Moskeebee:BAABLgAECn8UAAIOAAcJyiUSEgCnAgAOAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8XAAMLAAkJmwKmewDtAAALAAkJmwKmewDtAAAUAAQJewH6kgBOAAAAAA==.',
['Mä']='Mätthew:BAAALgAECgEJAQAAAA==.',
['Må']='Måtthew:BAAALgAECgEJAwAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAISAAcJoQoCjgAeAQASAAcJoQoCjgAeAQAAAA==.Møsh:BAAALgAECgkJDgABLgAFFAQJBQAOAJ0KAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMSAAgJVBv0QwAAAgASAAgJVBv0QwAAAgARAAEJjAnIdQAvAAAAAA==.Nekromant:BAACLgAFFH8MAAMSAAMJlQ1WJQDBAAASAAMJlQ1WJQDBAAARAAEJ8gWQDQA6AAAuAAQKf1IAAxIACQl2HXQCAB8CABIACQmYHHQCAB8CABEACAmlHFcFAB0CAAAA.Nemriel:BAAALgAECgcJDwAAAA==.Newthilena:BAAALgAFFAQJBAAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMdAAkJjxasRQC2AQAdAAkJzxCsRQC2AQAfAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Normandy:BAAALgADCgEJAQABLgAFFAMJGgALAMMYAA==.Norsem:BAAALgAECgkJDgAAAA==.Nossem:BAAALgAECgEJAQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPwAMAKAlAA==.Nymera:BAAALgAECgQJBQABLgAECgcJIAAGAHwYAA==.Nyxanee:BAAALgAECgcJDQABLgAFFAQJBQAOAJ0KAA==.',
['Nä']='Nämeless:BAAALgAFFAIJBAAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIDAAMJTBzuKwDyAAADAAMJTBzuKwDyAAAuAAQKfywAAgMACAlGIKQQAGgCAAMACAlGIKQQAGgCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ok='Oktar:BAAALgADCgIJAgAAAA==.',
Ol='Olgaa:BAAALgAFFAEJAQABLgAFFAcJEgAKAGwaAA==.',
On='Oneth:BAABLgAECn8UAAIaAAYJ3xC3FwAHAQAaAAYJ3xC3FwAHAQAAAA==.Onfleek:BAABLgAECn80AAQEAAgJXCNRBwD6AgAEAAgJXCNRBwD6AgAWAAYJvBFBNgA7AQADAAEJWB2lEABXAAAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQABLgAECgEJAQABAAAAAA==.Opshammi:BAACLgAFFH8aAAILAAMJwxhiSQDJAAALAAMJwxhiSQDJAAAuAAQKf0MAAgsACQkdHa4UAKYCAAsACQkdHa4UAKYCAAAA.',
Or='Orakrak:BAABLgAECn8nAAIMAAkJHhFkJQDMAQAMAAkJHhFkJQDMAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgAECgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNQADAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNQADAB4lAA==.Parseval:BAABLgAECn81AAQDAAkJHiVPAgCWAwADAAkJHiVPAgCWAwAWAAgJ0RssFgAaAgAEAAQJPxsuQwAsAQAAAA==.Parshock:BAAALgAFFAEJAQABLgAECgkJNQADAB4lAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPwAMAKAlAA==.Paws:BAABLgAECn8/AAIMAAkJoCXFAwArAwAMAAkJoCXFAwArAwAAAA==.Pawsitivity:BAAALgAECgMJAwABLgAECgkJPwAMAKAlAA==.',
Pd='Pdbm:BAAALgAECgEJBAAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIXAAgJORg9PABXAQAXAAgJORg9PABXAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIiAAYJqg1dIAD1AAAiAAYJqg1dIAD1AAAAAA==.',
Pi='Pipsqueak:BAAALgAFFAEJAQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAIJBAAAAA==.Porkins:BAABLgAECn9CAAMjAAkJfyCkCgBmAgAjAAgJmx+kCgBmAgAmAAkJEB6xBwAaAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgAECgYJCQAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAFFAIJAwAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAdALwhAA==.',
Ps='Psyn:BAAALgAECgQJBAABLgAFFAQJHgALACMgAA==.Psyndar:BAAALgAECgEJAQABLgAFFAQJHgALACMgAA==.Psyndra:BAAALgAECgYJDAABLgAFFAQJHgALACMgAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8QAAIYAAMJnRT1OQCcAAAYAAMJnRT1OQCcAAAuAAQKfzMAAhgACQm5IJgVANcCABgACQm5IJgVANcCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAQJBQAOAJ0KAA==.',
Qt='Qtip:BAAALgAECgMJAwAAAA==.Qtwithabooty:BAAALgAECgEJAQAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8WAAISAAUJlR6ZOgBhAQASAAUJlR6ZOgBhAQAuAAQKfzIAAhIACAnDJBsMAO0CABIACAnDJBsMAO0CAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMdAAgJjRI/ZABfAQAdAAgJ7xE/ZABfAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razle:BAAALgADCgQJBAAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8yAAMEAAkJsRViIQC3AQAEAAkJsRViIQC3AQAWAAUJ2gUbZQCHAAAAAA==.',
Re='Replicate:BAACLgAFFH8GAAIMAAMJYx3yKwAEAQAMAAMJYx3yKwAEAQAuAAQKfyMAAgwACQnrIdQFAAMDAAwACQnrIdQFAAMDAAAA.Resisted:BAAALgAECgEJAQABLgAFFAgJFQAVAFMYAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rochara:BAAALgAECgIJAwABLgAECgkJKgALAFsRAA==.Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJPAAOAI0cAA==.',
Ru='Runeswipe:BAAALgAECgEJAgABLgAFFAMJBQAhABAQAA==.',
Ry='Ryanmonk:BAAALgAFFAEJAQAAAA==.Ryanqt:BAAALgAFFAEJAQAAAA==.Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8XAAIXAAgJgRxDBgBpAgAXAAgJgRxDBgBpAgAuAAQKfzEAAhcACQmNJd0AAJIDABcACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAFFAEJAQAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJEAAAAA==.Ryri:BAABLgAECn8fAAIhAAcJXxVAFQB+AQAhAAcJXxVAFQB+AQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMDAAkJlgqwIgB+AQADAAkJlgqwIgB+AQAWAAIJGQvNdABXAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMeAAkJbQm+KwBbAQAeAAkJbQm+KwBbAQAFAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJCAAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECggJEQAAAA==.Santoku:BAABLgAECn8QAAIdAAYJsxdVbQBJAQAdAAYJsxdVbQBJAQAAAA==.Sarah:BAACLgAFFH8TAAIDAAUJsBcLHQB0AQADAAUJsBcLHQB0AQAuAAQKfzMAAgMACQmxH4cFADADAAMACQmxH4cFADADAAAA.Sass:BAAALgAECgQJBQAAAA==.Sassyface:BAABLgAECn9MAAIRAAkJERH8CwB/AQARAAkJERH8CwB/AQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Sc='Scarletdawns:BAAALgADCgEJAQAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAKAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAABLgAECn8cAAMNAAcJ/iCbCgBAAgANAAcJ/iCbCgBAAgAMAAEJcRuZkABRAAAAAA==.Shaduw:BAACLgAFFH8bAAIZAAgJGx5mBAAmAgAZAAgJGx5mBAAmAgAuAAQKfyQAAxkACAnOIbMDABkDABkACAnOIbMDABkDAAwACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBCcKwA8AQACAAcJkBCcKwA8AQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJEAABLgAECgkJJgARAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIWAAMJPBYGJQDPAAAWAAMJPBYGJQDPAAAuAAQKfzYAAhYACQlGIfwFAC4DABYACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIYAAMJCBtGfgDaAAAYAAMJCBtGfgDaAAAuAAQKfycAAhgACQlNIykVACkDABgACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMXAAgJniPOEACMAgAXAAgJniPOEACMAgAcAAQJrRj5MgF8AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Slaughter:BAAALgADCgMJAwAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMFAAgJDSPpCQC0AgAFAAcJnyLpCQC0AgAkAAYJJBWCNAAxAQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQgAAgJEBchCQCxAQAgAAgJyhUhCQCxAQACAAQJ9RiNPwAhAQAoAAEJMAiuDgAyAAAAAA==.Sporki:BAAALgAECgEJAQAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgUJCwAAAA==.',
St='Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIcAAkJjwQs1wDpAAAcAAkJjwQs1wDpAAAAAA==.Stelthme:BAABLgAECn8aAAQgAAYJIxjmCwBwAQAgAAYJIxjmCwBwAQAoAAMJQwi4GgB7AAACAAEJFwiiXgA5AAABLgAFFAUJEAACANolAA==.Stormburst:BAAALgADCgIJAgABLgAFFAUJHAAgAJsjAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIYAAcJQyFKOgCNAgAYAAcJQyFKOgCNAgABLgAECggJFAAQAEElAA==.',
Su='Susaki:BAAALgAECgQJBQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAAQAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8wAAIZAAkJJSFOAwACAwAZAAkJJSFOAwACAwAAAA==.Takeshì:BAAALgAECgcJBwABLgAECgkJMgAEALEVAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8KAAIVAAQJkBHOMwDzAAAVAAQJkBHOMwDzAAAuAAQKfyIAAxUACQl5IMYGAOwCABUACQl5IMYGAOwCACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAABLgAFFH8GAAIhAAIJjxYABQCTAAAhAAIJjxYABQCTAAAAAA==.',
Th='Theory:BAABLgAECn9ZAAMJAAkJ1xrwAwDuAQAJAAkJJxrwAwDuAQAjAAIJ+hhwQACNAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBwAAAA==.',
To='Tomjim:BAACLgAFFH8VAAMVAAgJUxhsFgC5AQAVAAcJwxdsFgC5AQAbAAMJZQXtEwCLAAAuAAQKfyYABBUACAlAIwsLAMUCABUACAlAIwsLAMUCABsABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn85AAIQAAkJQBxNDwA5AgAQAAkJQBxNDwA5AgAAAA==.Treevive:BAACLgAFFH8SAAIKAAcJbBocBAD9AQAKAAcJbBocBAD9AQAuAAQKfx0AAgoACQmQIUEcAFoCAAoACQmQIUEcAFoCAAAA.Trencough:BAABLgAECn8YAAIJAAcJMg3RGQCQAAAJAAcJMg3RGQCQAAAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trost:BAAALgADCgEJAQAAAA==.Trystan:BAABLgAECn9MAAIcAAkJEB4LFgC+AgAcAAkJEB4LFgC+AgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIIAAYJaRMaHAArAQAIAAYJaRMaHAArAQAAAA==.',
Tu='Tugbote:BAAALgAECgUJBQAAAA==.Turl:BAABLgAECn8VAAIYAAYJEhLipQAxAQAYAAYJEhLipQAxAQABLgAECggJJgAXAEggAA==.Turlo:BAABLgAECn8mAAIXAAcJSCDOHwAFAgAXAAcJSCDOHwAFAgAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAYJGQAoAJwQAA==.Twostep:BAACLgAFFH8ZAAIoAAYJnBAyAwB3AQAoAAYJnBAyAwB3AQAuAAQKfyoAAigACQnzGRUDACwCACgACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8VAAIcAAgJWR/FCABLAgAcAAgJWR/FCABLAgAuAAQKfyIAAhwABwmkJTsYANgCABwABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgAECgIJAgAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8SAAIFAAMJgRdfHgCPAAAFAAMJgRdfHgCPAAAuAAQKfzUAAwUACQmVH+IDAMEBAAUACQmVH+IDAMEBACQAAQnFBFAZACEAAAAA.',
Ur='Ursos:BAABLgAECn8gAAIGAAcJfBh2FwCWAQAGAAcJfBh2FwCWAQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8XAAMVAAkJERh7HADyAQAVAAkJERh7HADyAQAbAAEJ1gFSTAApAAAAAA==.Valiantinter:BAAALgAECgEJAQAAAA==.Vallatris:BAAALgAECgcJDgAAAA==.Valomyr:BAAALgAECgMJAwABLgAECgcJHAANAP4gAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn9GAAIYAAgJuxcfCAB0AQAYAAgJuxcfCAB0AQAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgAECgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgAECgYJBwABLgAECgcJIAAGAHwYAA==.Viracocha:BAABLgAFFH8JAAMLAAQJ/RrwRADVAAALAAMJtxjwRADVAAAiAAEJCBp0GQBJAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgcJEQABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAABLgAFFH8FAAISAAIJHgUjtwBoAAASAAIJHgUjtwBoAAAAAA==.',
Vu='Vulcin:BAABLgAECn8UAAIXAAcJZBiqAQAAAgAXAAcJZBiqAQAAAgABLgAFFAMJEAAYAJ0UAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIdAAYJdRpqWgB4AQAdAAYJdRpqWgB4AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.Whitegirls:BAAALgAECgYJBwAAAA==.',
Wi='Winder:BAAALgAECgYJDgAAAA==.Windercase:BAAALgAECgEJAQAAAA==.Windercurse:BAAALgAECgEJAwAAAA==.Winderk:BAAALgAECgMJBQAAAA==.Winderkin:BAAALgAECgEJAwAAAA==.Winderv:BAAALgAECgEJAgAAAA==.Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIDAAcJMhJkLwBiAQADAAcJMhJkLwBiAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8hAAILAAcJCB1DBQCMAQALAAcJCB1DBQCMAQABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8rAAIQAAkJLx2JBgCaAgAQAAkJLx2JBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.Yoshimitsu:BAAALgAECgEJAwAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQaAAYJvyB9DABwAQASAAUJcx6VXACzAQAaAAQJByJ9DABwAQARAAEJAABYYABOAAABLgAFFAIJBwALACcjAA==.Zandramadas:BAABLgAECn9NAAQHAAkJFiCOFQAjAgAHAAkJFiCOFQAjAgAKAAgJqRloLAD9AQAGAAcJ2BNkHgBaAQAAAA==.Zaraline:BAABLgAECn88AAIOAAkJjRwNGQCPAgAOAAkJjRwNGQCPAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJDwAAAA==.Zect:BAAALgAECgYJBgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIJAAgJrBvqPwADAgAJAAgJrBvqPwADAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAABLgAECn8dAAIYAAcJHRaKBgCbAQAYAAcJHRaKBgCbAQAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIJAAYJbBaQnwAtAQAJAAYJbBaQnwAtAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAABLgAECn8UAAILAAgJaA8PZgApAQALAAgJaA8PZgApAQAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIYAAkJUR5bHwCiAgAYAAkJUR5bHwCiAgAAAA==.',
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
