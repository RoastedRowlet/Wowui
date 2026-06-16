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
local provider = {region='US',realm='Gorefiend',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abracadabra:BAAALgAECgYJCQAAAA==.Abracanoobra:BAAALgAECgYJBwABLgAECgYJCQABAAAAAA==.',
Ac='Acry:BAABLgAECn8hAAICAAkJsQ1GIgDnAQACAAkJsQ1GIgDnAQAAAA==.',
Ad='Adewe:BAAALgADCgcJEAAAAA==.Adrasteia:BAAALgAECgMJAwABLgAECgkJJQADAIEZAA==.Adry:BAAALgAECgYJDAAAAA==.',
Ae='Aelxdoox:BAAALgAECgMJBQAAAA==.',
Ag='Agartha:BAAALgADCgQJBAAAAA==.',
Ai='Ailiia:BAAALgADCgcJBwAAAA==.Airwickdin:BAAALgAECgEJAQAAAA==.',
Ak='Akagane:BAAALgADCgkJHwAAAA==.Akalla:BAABLgAECn8UAAIEAAYJ3xVpMgA7AQAEAAYJ3xVpMgA7AQAAAA==.',
Al='Alex:BAABLgAFFH8GAAIFAAQJIRVTKgAOAQAFAAQJIRVTKgAOAQAAAA==.Alexiel:BAAALgADCgUJBQAAAA==.Alfuric:BAABLgAECn8XAAQGAAkJHwarPwChAAAHAAYJEwfhVAC3AAAGAAkJywKrPwChAAAIAAQJBgbmMwCIAAAAAA==.Alliautopsy:BAAALgAECgUJCgAAAA==.Althraniir:BAAALgAECgYJEwAAAA==.Altrois:BAABLgAECn9EAAIJAAkJgB05IgB8AgAJAAkJgB05IgB8AgAAAA==.Altruis:BAAALgADCgYJCgAAAA==.Alyshira:BAACLgAFFH8GAAIKAAMJBxnHNADUAAAKAAMJBxnHNADUAAAuAAQKfyMAAwoACQn9IScJAP4CAAoACQn9IScJAP4CAAcAAQnBF3l4AEMAAAAA.Alystrasza:BAAALgAECgcJEwABLgAFFAMJBgAKAAcZAA==.',
Am='Amatsano:BAABLgAECn8UAAILAAYJVht6PAC4AQALAAYJVht6PAC4AQAAAA==.Amorsith:BAAALgAECgkJEgAAAA==.Amurai:BAAALgAECgEJAQAAAA==.Amyst:BAACLgAFFH8NAAMMAAMJ9h5EPQCqAAAMAAIJxh5EPQCqAAANAAEJVh/7OwBQAAAuAAQKfyUAAw0ACQnQIuoFAKMCAA0ACAm+IOoFAKMCAAwABQkVI+c3AMgBAAAA.',
An='Aneyna:BAAALgAECgYJDQAAAA==.Angrycrack:BAABLgAECn8YAAICAAgJsBnKGgC9AQACAAgJsBnKGgC9AQAAAA==.Animuggus:BAEBLgAECn8UAAIHAAYJzxqrLQBoAQAHAAYJzxqrLQBoAQAAAA==.Anjunabeets:BAABLgAFFH8qAAQOAAgJSBszEwC7AQAOAAYJih4zEwC7AQAPAAYJYQ+fCQCAAQAQAAUJfRYBDwBIAQAAAA==.Anthran:BAABLgAECn8mAAMRAAkJqw8jHwBYAQARAAYJzQ4jHwBYAQASAAcJJQyGggAzAQAAAA==.',
Ap='Apexlegend:BAAALgAECgUJBQAAAA==.Applebottom:BAAALgAECgQJBAAAAA==.',
Ar='Archdruid:BAAALgAECgYJBwABLgAECgkJNQAMAGsXAA==.Archos:BAAALgAECgEJBgAAAA==.Arcon:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Arcscythe:BAABLgAECn8kAAITAAkJ4Bb0AgAFAgATAAkJ4Bb0AgAFAgAAAA==.Arctron:BAAALgAECgkJEAABLgAECgkJIQACALENAA==.Arinok:BAAALgAECgQJBgAAAA==.Artoo:BAAALgAECgkJEQAAAA==.',
As='Asleep:BAAALgAECgQJBgABLgAECgkJNQAMAGsXAA==.Assaulter:BAAALgAECgYJDQABLgAFFAEJAQABAAAAAA==.Astralpanda:BAABLgAECn8ZAAIUAAgJKAosSQALAQAUAAgJKAosSQALAQAAAA==.',
Az='Azrayel:BAAALgAECgEJAQAAAA==.Azvar:BAABLgAECn8zAAIVAAkJNw+JJAC3AQAVAAkJNw+JJAC3AQAAAA==.',
Ba='Baconn:BAAALgAECgkJBwAAAA==.Badpwny:BAAALgADCgMJAwABLgAECgkJIQAWADEYAA==.Baer:BAABLgAECn8eAAIGAAgJ9gcTOgC3AAAGAAgJ9gcTOgC3AAAAAA==.Bafunga:BAAALgAECgIJAgAAAA==.Bakon:BAAALgAECggJAwAAAA==.Balgith:BAABLgAECn82AAIXAAkJWA/TKADDAQAXAAkJWA/TKADDAQAAAA==.Balrus:BAAALgADCgEJAQAAAA==.Baossulympis:BAABLgAECn8gAAISAAcJAQssjgAeAQASAAcJAQssjgAeAQAAAA==.Barron:BAAALgAECgYJDgABLgAFFAMJBgAYAAgbAA==.Bastid:BAAALgADCgkJFQAAAA==.Battleburger:BAABLgAECn8aAAIZAAgJdhv5EADYAQAZAAgJdhv5EADYAQAAAA==.Bauchelaine:BAABLgAECn8hAAMSAAgJRBAJYAB/AQASAAgJRBAJYAB/AQAaAAEJEAaeQgAoAAAAAA==.Bavunga:BAABLgAECn8pAAIbAAkJhCCjAgA3AwAbAAkJhCCjAgA3AwAAAA==.Bayle:BAAALgADCgcJCAAAAA==.',
Bc='Bchan:BAAALgAECgQJCQAAAA==.',
Be='Beanfrog:BAAALgAECgEJAwAAAA==.Beastadi:BAAALgAFFAEJAQAAAA==.Beelieve:BAAALgADCgMJAwAAAA==.Beoron:BAACLgAFFH8HAAIIAAMJoxwiDADtAAAIAAMJoxwiDADtAAAuAAQKfy0AAggACQlbJf4AAFADAAgACQlbJf4AAFADAAEuAAUUBAkKABUAkBEA.Bettyßastion:BAABLgAECn8yAAIcAAkJrx+PGgCiAgAcAAkJrx+PGgCiAgAAAA==.',
Bi='Big:BAAALgAECgQJBAAAAA==.Bigcat:BAAALgAECgYJCwAAAA==.Bigdawg:BAAALgAECgUJCQAAAA==.Bio:BAAALgAECgkJAQABLgAECgkJDAABAAAAAA==.Bioenergy:BAAALgAECgkJDAAAAA==.Biogen:BAAALgAECgEJAQABLgAECgkJDAABAAAAAA==.Biolysis:BAAALgAECgMJAwABLgAECgkJDAABAAAAAA==.Bisoncrusher:BAAALgAECggJEAAAAA==.',
Bl='Blastrakhan:BAAALgADCgYJDQAAAA==.Blockhead:BAAALgADCgIJAgABLgAECgkJNQAMAGsXAA==.Bloodstone:BAAALgAECgYJCgAAAA==.',
Bo='Boagrius:BAABLgAECn8YAAIWAAgJhAezPwAPAQAWAAgJhAezPwAPAQABLgAFFAMJGQALAMMYAA==.Boneash:BAAALgADCgIJAgAAAA==.Borabora:BAABLgAECn8UAAMQAAgJQSVlAgAeAwAQAAgJQSVlAgAeAwAPAAEJ+w8zigAxAAAAAA==.Boss:BAAALgAECgEJAQABLgAECgkJIQACALENAA==.Bouldernar:BAAALgADCgYJBgAAAA==.',
Br='Brageus:BAABLgAECn8WAAIUAAgJ+xLMKgCYAQAUAAgJ+xLMKgCYAQAAAA==.Breadmaster:BAAALgADCgYJBgAAAA==.Brontag:BAABLgAECn8UAAMMAAkJaBVOTgBuAQAMAAgJZBZOTgBuAQANAAMJ+xDRTQCUAAAAAA==.Bruus:BAAALgAECgEJAQAAAA==.Bryant:BAAALgAECgcJDgAAAA==.',
Bu='Bud:BAABLgAECn8gAAIHAAgJehYaKQC2AQAHAAgJehYaKQC2AQAAAA==.Bugles:BAAALgAECgEJAwAAAA==.Bullessed:BAAALgAECgMJBAAAAA==.Busterbrown:BAABLgAECn8ZAAMOAAcJZxNZdgBOAQAOAAcJZxNZdgBOAQAQAAQJBwNMJACpAAAAAA==.Butho:BAAALgAECgQJBQAAAA==.',
By='Byrnholf:BAAALgADCgcJDgAAAA==.',
Ca='Caliboy:BAAALgADCgMJBQABLgAECgkJKQALAFsRAA==.Calißoy:BAABLgAECn8pAAILAAkJWxEUOwC+AQALAAkJWxEUOwC+AQAAAA==.Camabell:BAAALgADCgcJCgAAAA==.Canekii:BAAALgAECgUJBQABLgAFFAEJBAABAAAAAA==.Cannyon:BAAALgAECgQJBwAAAA==.Cartravistus:BAAALgADCgcJBwAAAA==.Cathore:BAAALgAECgEJAQAAAA==.Cathrîne:BAAALgADCgkJJgAAAA==.',
Ce='Celarae:BAAALgAECgQJBAABLgAECgkJRAACAE4lAA==.Ceruledge:BAABLgAECn8fAAIdAAgJyxSlRgCvAQAdAAgJyxSlRgCvAQABLgAFFAMJBgAWADwWAA==.',
Ch='Chaboomy:BAECLgAFFH8XAAIHAAcJSxHVDwCfAQAHAAcJSxHVDwCfAQAuAAQKfx0AAgcACAkFIOcPAKQCAAcACAkFIOcPAKQCAAAA.Changlaive:BAAALgADCgUJBQABLgAECgQJCQABAAAAAA==.Chaoscupcake:BAAALgADCgUJBQAAAA==.Chillshot:BAAALgAECgUJBgAAAA==.Chips:BAABLgAECn81AAIMAAkJaxdmGQAhAgAMAAkJaxdmGQAhAgAAAA==.Chopper:BAACLgAFFH8SAAIIAAUJ7BoYBgBIAQAIAAUJ7BoYBgBIAQAuAAQKfyYAAggACQn9IWYDAAEDAAgACQn9IWYDAAEDAAEuAAUUBgkWABoArxQA.Chrictt:BAAALgAECgEJAQAAAA==.Chromate:BAABLgAFFH8QAAIeAAQJsxG9JwAGAQAeAAQJsxG9JwAGAQAAAA==.',
Ci='Cindreqt:BAABLgAECn8UAAMEAAcJfBWpJgC4AQAEAAcJ5hSpJgC4AQADAAQJBAYNQQCpAAAAAA==.Cingz:BAAALgAECgMJBAAAAA==.',
Cl='Clicidios:BAAALgADCgYJBgAAAA==.',
Co='Cobblerjr:BAAALgAECgYJCwAAAA==.Coffeebean:BAAALgAECgQJBAAAAA==.Collie:BAEBLgAECn8+AAIIAAkJbiaTAABvAwAIAAkJbiaTAABvAwAAAA==.Colmoore:BAAALgAFFAEJAgABLgAFFAQJEQASAH0aAA==.Conkerin:BAABLgAFFH8HAAIOAAMJqhe6WQDpAAAOAAMJqhe6WQDpAAAAAA==.',
Cr='Croissant:BAAALgAECgQJBwAAAA==.Crusadus:BAAALgAECgkJCgAAAA==.Crusible:BAAALgAECgUJDQAAAA==.Crusty:BAAALgAECggJBQAAAA==.',
Cu='Cucumbered:BAAALgADCgUJBQABLgAFFAEJAgABAAAAAA==.Cutcha:BAAALgADCgEJAQAAAA==.',
Cy='Cycko:BAAALgAECgcJCwAAAA==.Cynis:BAAALgAECgIJAgAAAA==.Cypherrellik:BAAALgAECgMJBQABLgAECgkJHAAfAIUQAA==.',
Da='Dad:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daddy:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Dalidan:BAAALgAECgcJCQABLgAFFAIJBQALACcjAA==.Dapper:BAAALgADCgIJAgAAAA==.Darkis:BAABLgAECn8WAAIKAAgJVgqCTgBqAQAKAAgJVgqCTgBqAQAAAA==.Darkseph:BAAALgAECgcJDwAAAA==.Darla:BAAALgADCgIJAwAAAA==.Darthjarjar:BAAALgAECggJCAAAAA==.Daug:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.Daysham:BAABLgAFFH8GAAILAAIJ0CLFSgC/AAALAAIJ0CLFSgC/AAAAAA==.',
De='Deadcoffee:BAABLgAECn8bAAQRAAkJwhhuGwByAQASAAgJAhJxXQCGAQARAAcJZBZuGwByAQAaAAIJ0RhdKQBxAAAAAA==.Deadiron:BAAALgAECgYJBgABLgAFFAUJFgAgAJsjAA==.Deathshroud:BAAALgAFFAMJBAABLgAFFAYJIAACAM8cAA==.Deathsteak:BAAALgAECgYJBwAAAA==.Deebis:BAAALgADCgMJAwAAAA==.Deekaay:BAABLgAECn8xAAIJAAkJCxvoJwBgAgAJAAkJCxvoJwBgAgAAAA==.Deepman:BAAALgAFFAEJAQAAAA==.Delessia:BAAALgADCgIJAgAAAA==.Deo:BAABLgAECn8/AAMhAAkJdySrAQAqAwAhAAkJdySrAQAqAwAXAAgJkhy6FwBUAgAAAA==.',
Di='Diabo:BAAALgADCgcJBwAAAA==.Diddleficks:BAAALgAECgYJBgAAAA==.Diggersby:BAAALgAECgEJAQABLgAFFAQJCAAOAHcDAA==.Disastrous:BAACLgAFFH8SAAIOAAYJoxTtIAB4AQAOAAYJoxTtIAB4AQAuAAQKfzMAAg4ACQlCIMYRAKoCAA4ACQlCIMYRAKoCAAAA.Distractin:BAAALgAECgYJDgAAAA==.',
Dk='Dkfive:BAAALgADCgIJAgABLgAECgkJOAAfAKMiAA==.',
Do='Doe:BAAALgAECgQJBAAAAA==.Doomangel:BAABLgAECn8UAAIJAAYJuhEGsQAQAQAJAAYJuhEGsQAQAQAAAA==.Dorá:BAAALgAFFAEJAgAAAA==.Doson:BAABLgAECn8VAAIMAAYJGQYDYgDOAAAMAAYJGQYDYgDOAAAAAA==.Dotsyalater:BAAALgADCgMJAwABLgAFFAMJGQALAMMYAA==.Doubleedge:BAAALgADCgIJAgABLgAECgkJMQAYALAcAA==.',
Dr='Dracomoose:BAAALgADCgUJBQAAAA==.Drago:BAAALgAECgUJCwABLgAECgkJJQARAKcaAA==.Dragonslock:BAABLgAECn8VAAQSAAcJKQ5TowD5AAASAAYJcA5TowD5AAARAAIJxAyJPgAwAAAaAAEJiwOORAAcAAAAAA==.Drakelord:BAAALgAECggJEwAAAA==.Drakgor:BAAALgAECgYJBgAAAA==.Drakonic:BAABLgAECn8VAAIVAAcJDBGQJQCQAQAVAAcJDBGQJQCQAQAAAA==.Draygos:BAAALgAECgcJDQAAAA==.Drbigbolt:BAAALgADCgUJAgAAAA==.Druidtime:BAAALgAECgkJDwAAAA==.Drumboppie:BAABLgAECn8oAAMKAAkJtxErRAB9AQAKAAcJRBErRAB9AQAHAAgJ9Qa4VwCuAAAAAA==.Drunkenmasta:BAAALgAECgYJEQABLgAFFAEJAQABAAAAAA==.Druzzil:BAAALgAECgEJAQAAAA==.',
Du='Dummythicc:BAAALgAECgEJAQAAAA==.Duskblade:BAACLgAFFH8gAAICAAYJzxwPDADEAQACAAYJzxwPDADEAQAuAAQKfzEAAgIACQkmJZgDAAsDAAIACQkmJZgDAAsDAAAA.Duskshifter:BAAALgAECgUJBQABLgAFFAYJIAACAM8cAA==.',
['Dø']='Døc:BAABLgAECn9JAAQLAAkJ9xkWFACoAgALAAkJ9xkWFACoAgAUAAkJchH/IwDDAQAiAAcJEgwfFgBcAQAAAA==.',
Ed='Edalynn:BAAALgAECgMJBQAAAA==.Eddie:BAAALgAECgYJDgAAAA==.',
Eg='Eggland:BAACLgAFFH8FAAIhAAMJWQ7TDACnAAAhAAMJWQ7TDACnAAAuAAQKfyAAAyEACAl0G/8QALcBACEABwlyGP8QALcBABwABQneHgZwAJwBAAAA.',
Ei='Eielmolate:BAACLgAFFH8UAAMSAAcJOA+CJwCeAQASAAcJOA+CJwCeAQARAAEJagETGwBAAAAuAAQKfykAAxIACAl7HHQ1ADYCABIACAl7HHQ1ADYCABEAAQkAAMRfAE8AAAAA.',
El='Elanna:BAAALgAECgEJAQABLgAECgkJFAAMAGgVAA==.Eldoryn:BAABLgAECn8fAAIdAAkJMhnjKgBVAgAdAAkJMhnjKgBVAgAAAA==.Elene:BAAALgADCgIJAgAAAA==.Ellyana:BAAALgAECgEJAQAAAA==.Elthius:BAAALgADCgIJAgAAAA==.',
Em='Emeraldcream:BAAALgAECgIJAgAAAA==.Emmabear:BAAALgAECgYJEAAAAA==.',
En='Enimed:BAABLgAECn9SAAIjAAkJUh1sCgBpAgAjAAkJUh1sCgBpAgAAAA==.Ennio:BAAALgAECgYJBwAAAA==.Entropi:BAAALgADCgIJAgAAAA==.',
Er='Erindralla:BAAALgAECgQJBQAAAA==.Erzascarlet:BAAALgAECgUJCAAAAA==.',
Ev='Evil:BAACLgAFFH8WAAQaAAYJrxTUCgDIAAASAAYJrxJ/MgB0AQAaAAMJAArUCgDIAAARAAIJ6AcbFgCCAAAuAAQKfy4ABBIACQn5GoxDAM8BABIACAloGIxDAM8BABEACAmiFL0fAFQBABoAAglRGtEYALQAAAAA.',
Ex='Exile:BAAALgADCgkJDAAAAA==.',
Ey='Eyebite:BAAALgAFFAIJAwABLgAFFAUJFgAgAJsjAA==.',
Fa='Faelinius:BAAALgAECgUJDQAAAA==.Farfik:BAAALgAECgEJBAABLgAECgQJBwABAAAAAA==.Fatherseph:BAAALgAECgYJCAABLgAECgcJDwABAAAAAA==.',
Fe='Feleyeza:BAAALgADCgEJAQABLgAECgYJBwABAAAAAA==.Felshadra:BAAALgAFFAQJBAAAAA==.',
Fi='Finnland:BAAALgAECgEJAQABLgAFFAIJCQAjAMoaAA==.Finntastic:BAAALgADCgYJCAABLgAFFAIJCQAjAMoaAA==.Finnthehuman:BAAALgAECgYJCQAAAA==.Finntree:BAAALgAECgQJCAABLgAFFAIJCQAjAMoaAA==.Fisterdobble:BAABLgAECn9BAAIYAAkJ2xb6TQDuAQAYAAkJ2xb6TQDuAQAAAA==.',
Fl='Flawless:BAAALgAECgEJAQAAAA==.Flawlesshope:BAAALgADCgkJCQAAAA==.Fleurdelys:BAAALgAECgQJAwAAAA==.',
Fo='Forestpump:BAABLgAECn8ZAAMLAAkJOR0oGACFAgALAAgJhBwoGACFAgAiAAkJ9Rn1BQB7AgABLgAECggJGgAFAA0jAA==.Forgeddemon:BAABLgAECn8XAAMeAAgJJgmlRQArAQAeAAcJ6wmlRQArAQAkAAQJ1wUaYgCHAAAAAA==.Forkinaround:BAAALgAECggJCwAAAA==.Fortune:BAAALgADCgYJBgAAAA==.',
Fr='Fralix:BAAALgAECgMJAwAAAA==.Frankiè:BAAALgAECgEJAQAAAA==.Fray:BAAALgADCgIJAgAAAA==.Frostbanshee:BAAALgAECgQJBAABLgAFFAQJDwAFAJYaAA==.Frostborne:BAAALgAECgcJDgAAAA==.Frostheart:BAABLgAECn8lAAIhAAkJ0h6MBgB/AgAhAAkJ0h6MBgB/AgAAAA==.Frostina:BAABLgAECn8dAAIYAAgJGRQFawCiAQAYAAgJGRQFawCiAQAAAA==.Frostmorne:BAAALgADCgEJAQAAAA==.Frostqueenie:BAAALgADCgEJAQAAAA==.',
Fu='Fullsend:BAAALgADCgcJCAAAAA==.Funeral:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Furionik:BAABLgAECn8YAAMZAAcJFBQ2GACUAQAZAAcJFBQ2GACUAQAMAAEJuAsRpgA5AAAAAA==.',
Fw='Fweaky:BAAALgAECgEJAQAAAA==.',
['Fé']='Féannas:BAAALgAECgkJCAAAAA==.',
Ga='Galcian:BAAALgAECgYJEwAAAA==.Gamjee:BAABLgAECn8UAAIhAAYJ1heHGQBKAQAhAAYJ1heHGQBKAQAAAA==.',
Ge='Gellis:BAAALgADCgUJCAAAAA==.Gerkinmonk:BAAALgAECgQJBQAAAA==.',
Gh='Ghidorah:BAAALgADCgQJBAAAAA==.Ghostlyxd:BAAALgAECgUJBQAAAA==.',
Gl='Glimmawitz:BAAALgAECgQJCAAAAA==.Glo:BAAALgAECgUJCQABLgAECgYJBgABAAAAAA==.Glofu:BAAALgAECgYJBgAAAA==.Glyndin:BAAALgAECgUJBQAAAA==.',
Gn='Gnomeater:BAAALgADCgMJAwAAAA==.',
Go='Goldeen:BAABLgAECn8WAAIcAAgJIxveRQDyAQAcAAgJIxveRQDyAQAAAA==.Goodboy:BAABLgAFFH8IAAIOAAQJdwMNbAC/AAAOAAQJdwMNbAC/AAAAAA==.Goodolrúss:BAAALgADCgUJBQAAAA==.Goombas:BAAALgAECgYJBQAAAA==.',
Gr='Gr:BAAALgADCgYJBgAAAA==.Grackalackin:BAABLgAECn8xAAIKAAcJhRThOwCiAQAKAAcJhRThOwCiAQAAAA==.Grinnaux:BAAALgADCgMJAwAAAA==.Grounds:BAACLgAFFH8WAAIgAAUJmyM7AgCYAQAgAAUJmyM7AgCYAQAuAAQKfxoAAiAACAlcJBUCAOgCACAACAlcJBUCAOgCAAAA.Grìffith:BAAALgAECgUJCAAAAA==.Grøtesk:BAABLgAECn8bAAILAAYJ/xSjTgByAQALAAYJ/xSjTgByAQAAAA==.',
Gu='Gulaj:BAABLgAECn8WAAIOAAkJ8BfISQCMAQAOAAkJ8BfISQCMAQAAAA==.Gumby:BAAALgADCgIJAgAAAA==.Gunbrawl:BAAALgADCgEJAgAAAA==.',
['Gë']='Gënesis:BAAALgAECgQJBAAAAA==.',
Ha='Havixsucks:BAABLgAECn8yAAQaAAkJRRNLCQDKAQASAAgJ1RFYRQD7AQAaAAkJNxJLCQDKAQARAAQJ2wejPgAvAAAAAA==.',
He='Healgimp:BAACLgAFFH8HAAIEAAMJ3hjDGwDUAAAEAAMJ3hjDGwDUAAAuAAQKfyIAAgQACQmLFa8fAMEBAAQACQmLFa8fAMEBAAAA.Healslux:BAABLgAECn8eAAIXAAkJvx8QDQC+AgAXAAkJvx8QDQC+AgAAAA==.',
Hi='Hideyori:BAAALgAECgUJBgAAAA==.Highmane:BAAALgAECgYJBwAAAA==.',
Ho='Holyshot:BAAALgADCgUJCAAAAA==.Hope:BAAALgAECgEJAgABLgAFFAcJFQADAOEQAA==.Hortzel:BAABLgAECn8UAAISAAYJOA7nngABAQASAAYJOA7nngABAQAAAA==.Hotrollz:BAAALgAECgQJBwABLgAECgkJGQAKAE4WAA==.Howdoiheal:BAAALgAECgcJDQAAAA==.',
Hu='Humaa:BAABLgAECn8aAAIcAAcJlBzaRQDyAQAcAAcJlBzaRQDyAQAAAA==.Huntus:BAABLgAECn84AAMOAAkJsCO/CwDzAgAOAAkJsCO/CwDzAgAPAAEJlQfskQApAAAAAA==.',
Ia='Iamdownhere:BAABLgAECn8cAAIcAAgJHxYzZwCeAQAcAAgJHxYzZwCeAQAAAA==.',
Ic='Icy:BAAALgAECggJCQAAAA==.',
Il='Illadelf:BAAALgAECgEJAQABLgAECgUJBQABAAAAAA==.',
Im='Immersa:BAABLgAECn8WAAMlAAgJTBahDQAAAgAlAAgJdhWhDQAAAgAVAAcJjxKLIgCqAQAAAA==.Impostor:BAACLgAFFH8FAAIWAAMJ3wgLJwC8AAAWAAMJ3wgLJwC8AAAuAAQKfzIAAhYACQl2IFgHANsCABYACQl2IFgHANsCAAAA.',
In='Indabow:BAABLgAECn8gAAIOAAkJbRopKAAXAgAOAAkJbRopKAAXAgAAAA==.Indamurim:BAABLgAECn8WAAMkAAgJJxKrKQCPAQAkAAcJTxCrKQCPAQAeAAcJcwzZPgBKAQAAAA==.Inzili:BAAALgAECgkJDgAAAA==.',
Is='Isaarek:BAABLgAECn8UAAIfAAgJihRTGQD7AQAfAAgJihRTGQD7AQAAAA==.',
Ja='Jabrick:BAABLgAECn8eAAMfAAgJFhpXEQBUAgAfAAgJFhpXEQBUAgAdAAEJdgU96wAnAAAAAA==.Jakamu:BAAALgAECgUJDAAAAA==.Jamminmydh:BAABLgAFFH8GAAIdAAIJvCF2ZgC6AAAdAAIJvCF2ZgC6AAAAAA==.Janim:BAAALgAECgUJBQAAAA==.Jattin:BAAALgADCgYJBgAAAA==.Jawnski:BAAALgAECggJDgAAAA==.Jay:BAABLgAECn8tAAIkAAkJSBx1CgCaAgAkAAkJSBx1CgCaAgAAAA==.',
Ji='Jibjabjibjab:BAACLgAFFH8WAAMCAAUJsh2pFQBYAQACAAUJsh2pFQBYAQAgAAEJBwfnEQBFAAAuAAQKfx0AAwIACQkjHoARABkCAAIACQlCHYARABkCACAABAnmGMENAD8BAAAA.Jimm:BAACLgAFFH8ZAAIeAAcJAQ44FAB5AQAeAAcJAQ44FAB5AQAuAAQKfyQAAh4ACAnxElshAPcBAB4ACAnxElshAPcBAAAA.',
Ju='Judge:BAAALgAECgYJBgAAAA==.Juroda:BAAALgADCgkJDQABLgAECgcJDwABAAAAAA==.Juul:BAABLgAECn8YAAIVAAkJ2RVHFgAlAgAVAAkJ2RVHFgAlAgAAAA==.',
['Jì']='Jìm:BAAALgADCgIJAgABLgAFFAUJEAAWAFcJAA==.Jìmothy:BAAALgAFFAEJAQABLgAFFAUJEAAWAFcJAA==.',
Ka='Kailthosjr:BAAALgADCgEJAQAAAA==.Karnatos:BAAALgAECgYJCAABLgAECgcJFwANANAgAA==.Karram:BAAALgADCgYJBgAAAA==.Kazurtrin:BAAALgADCgMJAwAAAA==.',
Kc='Kcup:BAAALgADCgIJAgAAAA==.',
Ke='Kelemvor:BAABLgAECn8+AAIdAAkJlx3zFQDTAgAdAAkJlx3zFQDTAgAAAA==.',
Kf='Kfp:BAAALgAECgQJBQAAAA==.',
Kh='Khandak:BAACLgAFFH8XAAIjAAUJVxn9GQASAQAjAAUJVxn9GQASAQAuAAQKfxcAAiMACQlWGQAPABwCACMACQlWGQAPABwCAAAA.',
Ki='Kibin:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.Kidslaps:BAABLgAECn8eAAIeAAgJTAzJLwBCAQAeAAgJTAzJLwBCAQAAAA==.',
Kj='Kjsockeye:BAAALgADCgkJEgAAAA==.',
Kl='Kleenex:BAAALgAFFAEJAQAAAA==.',
Kn='Knigamortis:BAAALgADCgUJBQAAAA==.',
Ko='Kon:BAAALgAECgYJCgAAAA==.Kordmoridden:BAAALgADCgYJBgAAAA==.',
Kr='Krug:BAAALgAECgIJAgAAAA==.',
Ku='Kurisutina:BAACLgAFFH8PAAIFAAQJlhrnJAA4AQAFAAQJlhrnJAA4AQAuAAQKfycABAUACQn+F6IgAK4BAAUACQn+F6IgAK4BAB4AAQlKDCyHAD0AACQAAQk9D9uYADMAAAAA.',
La='Lafeum:BAAALgAECgQJBAABLgAECgUJBwABAAAAAA==.Lana:BAAALgAECgMJAwAAAA==.Laokenic:BAAALgAECgUJBwAAAA==.Lariat:BAAALgAFFAEJAQAAAA==.',
Le='Leadblaster:BAABLgAECn8lAAIOAAkJKBpzJwA+AgAOAAkJKBpzJwA+AgABLgAFFAEJAQABAAAAAA==.Leethalfu:BAAALgAECgQJBQAAAA==.Legosi:BAABLgAECn8kAAQSAAgJagcCjgAeAQASAAcJagcCjgAeAQARAAUJxAQHLQBiAAAaAAEJ8AknMQA8AAAAAA==.Lemegegen:BAABLgAECn8sAAISAAkJiBoFHgBvAgASAAkJiBoFHgBvAgAAAA==.',
Lh='Lhux:BAABLgAECn8uAAIOAAgJ/iO9DADZAgAOAAgJ/iO9DADZAgAAAA==.Lhuxi:BAACLgAFFH8WAAIVAAUJwRg5JQA2AQAVAAUJwRg5JQA2AQAuAAQKfysAAhUACQmUHUAKALICABUACQmUHUAKALICAAEuAAQKCAkuAA4A/iMA.',
Li='Lidean:BAAALgAECgIJAwAAAA==.Liedron:BAACLgAFFH8GAAIcAAMJYBpmXADwAAAcAAMJYBpmXADwAAAuAAQKfxQAAhwACQnBGkgkAHICABwACQnBGkgkAHICAAAA.Lightisright:BAAALgAECgYJCwAAAA==.Lilbokchoy:BAAALgADCgcJDQAAAA==.Lillith:BAAALgADCgYJBgAAAA==.Linkolas:BAAALgAECgcJEAAAAA==.Liny:BAABLgAECn8YAAIcAAgJaBDbcgCFAQAcAAgJaBDbcgCFAQAAAA==.',
Lo='Locrian:BAAALgADCgEJAQAAAA==.Lohotaf:BAAALgADCgcJDQAAAA==.Lorani:BAACLgAFFH8VAAIHAAYJABNOFwBYAQAHAAYJABNOFwBYAQAuAAQKfy0AAgcACQk0IHIIAMoCAAcACQk0IHIIAMoCAAAA.Lorgar:BAAALgAECgQJBQAAAA==.',
Lu='Luca:BAABLgAECn8iAAIKAAkJdA0gRgB1AQAKAAkJdA0gRgB1AQAAAA==.Luceean:BAAALgADCgcJDQAAAA==.Lucon:BAAALgAECgEJAgAAAA==.Lulu:BAAALgADCgEJAQAAAA==.Lurth:BAAALgAECgEJAgAAAA==.Lurthshots:BAAALgAECgEJBQAAAA==.Luxmunkii:BAAALgAECgUJCwAAAA==.',
Ly='Lykaboops:BAAALgADCgcJEAABLgAECgkJSQALAPcZAA==.Lyxxie:BAABLgAECn9LAAMJAAkJQBtXRADzAQAJAAkJQBtXRADzAQAmAAEJQAZiGQApAAAAAA==.',
Ma='Magentic:BAABLgAECn8xAAIYAAkJsBy8KQBxAgAYAAkJsBy8KQBxAgAAAA==.Mageus:BAAALgAFFAIJAwAAAA==.Maguar:BAAALgAECggJEgAAAA==.Manimadruid:BAAALgADCgMJAwAAAA==.Manimashaman:BAAALgADCgYJBgAAAA==.Marek:BAAALgAECgEJAQABLgAECggJFAAhANYXAA==.Marici:BAAALgADCgMJAwAAAA==.Mattxtz:BAAALgADCgMJAwABLgAECgkJMQAYALAcAA==.',
Me='Melith:BAAALgADCgkJEQAAAA==.Menthol:BAAALgADCgEJAQAAAA==.Menyin:BAABLgAECn8fAAIMAAkJ8g3gKgCpAQAMAAkJ8g3gKgCpAQABLgAFFAMJGQALAMMYAA==.Metsutan:BAABLgAECn9EAAICAAkJTiXuAwABAwACAAkJTiXuAwABAwAAAA==.',
Mi='Milkystream:BAAALgAECgEJAgAAAA==.Mind:BAAALgAECgMJAwAAAA==.Mixlife:BAAALgAECgEJAQAAAA==.',
Mo='Moggle:BAACLgAFFH8FAAIWAAIJSQwrLwCEAAAWAAIJSQwrLwCEAAAuAAQKfzQAAxYACQk/FVQdANoBABYACAlcFlQdANoBAAQABgmwDBhgALIAAAAA.Moistfellow:BAABLgAECn8VAAIYAAYJHxYLvABqAQAYAAYJHxYLvABqAQAAAA==.Mokey:BAABLgAECn8aAAIaAAgJNCJ9AgCWAgAaAAgJNCJ9AgCWAgAAAA==.Molathom:BAAALgAECgYJCgAAAA==.Monktastic:BAAALgADCgYJCgABLgAECgkJMQAYALAcAA==.Moog:BAAALgADCgkJCQAAAA==.Moohealer:BAAALgAECgYJDQAAAA==.Moppit:BAAALgAECgMJBAAAAA==.Morvster:BAAALgAECgYJCwAAAA==.Mosh:BAAALgAECgkJCAABLgAFFAUJEAAWAFcJAA==.Moskeebee:BAABLgAECn8UAAIOAAcJyiUSEgCnAgAOAAcJyiUSEgCnAgAAAA==.',
Mu='Muxx:BAAALgADCgEJAQAAAA==.',
['Mâ']='Mâtthêw:BAABLgAECn8XAAMLAAkJmwKieQDtAAALAAkJmwKieQDtAAAUAAQJewEPkABOAAAAAA==.',
['Må']='Måtthew:BAAALgADCgYJBQAAAA==.',
['Mø']='Møløtøv:BAABLgAECn8pAAISAAcJoQqTiwAiAQASAAcJoQqTiwAiAQAAAA==.Møsh:BAAALgAECgkJCwAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQAAAA==.',
Ne='Nekcrotic:BAABLgAECn8dAAMSAAgJVBv0QwAAAgASAAgJVBv0QwAAAgARAAEJjAnIdQAvAAAAAA==.Nekromant:BAABLgAECn9HAAMSAAkJcBxLFACqAgASAAkJeRtLFACqAgARAAgJpRwnBQAeAgAAAA==.Nemriel:BAAALgAECgcJDwAAAA==.Newthilena:BAAALgAECgQJBwAAAA==.',
Ni='Nictus:BAABLgAECn8bAAMdAAkJjxanRAC1AQAdAAkJzxCnRAC1AQAfAAYJfRhPIQCyAQAAAA==.Nirith:BAAALgAECgYJCwAAAA==.',
No='Noc:BAAALgADCgMJAwAAAA==.Nohric:BAAALgAECgUJBwAAAA==.Normandy:BAAALgADCgEJAQABLgAFFAMJGQALAMMYAA==.Norsem:BAAALgAECgkJDgAAAA==.Nossem:BAAALgAECgEJAQAAAA==.',
Nu='Numerion:BAAALgAECgMJAwAAAA==.Nutbutter:BAAALgADCgIJAgAAAA==.',
Ny='Nyagativity:BAAALgAECggJCAABLgAECgkJPQAMAKAlAA==.Nymera:BAAALgAECgMJAwABLgAECgcJIAAGAHwYAA==.',
['Nä']='Nämeless:BAAALgAFFAIJBAAAAA==.',
['Nî']='Nîghtraid:BAACLgAFFH8FAAIDAAMJTByGKgD0AAADAAMJTByGKgD0AAAuAAQKfywAAgMACAlGID0QAGoCAAMACAlGID0QAGoCAAAA.',
Oa='Oakenmoose:BAAALgADCgMJBQAAAA==.',
Od='Odinn:BAAALgAECgIJAgABLgAECgcJDQABAAAAAA==.',
Oh='Ohlorn:BAAALgAECgIJDAAAAA==.',
Ol='Olgaa:BAAALgAECgEJAQABLgAFFAYJDAAKAM8SAA==.',
On='Oneth:BAABLgAECn8UAAIaAAYJ3xAmFwAIAQAaAAYJ3xAmFwAIAQAAAA==.Onfleek:BAABLgAECn8yAAMEAAgJXCMlBwD7AgAEAAgJXCMlBwD7AgAWAAYJJA1BNgA7AQAAAA==.',
Op='Ophiline:BAAALgADCgUJBQAAAA==.Ophiri:BAAALgAECgQJBAAAAA==.Opladin:BAAALgAECgEJAQAAAA==.Opshammi:BAACLgAFFH8ZAAILAAMJwxj8RgDKAAALAAMJwxj8RgDKAAAuAAQKf0MAAgsACQkdHUIUAKYCAAsACQkdHUIUAKYCAAAA.',
Or='Orakrak:BAABLgAECn8nAAIMAAkJHhFjJADRAQAMAAkJHhFjJADRAQAAAA==.Oro:BAAALgADCgEJAQAAAA==.',
Oz='Ozzmodius:BAAALgAECgIJAwAAAA==.',
Pa='Pakapunch:BAAALgAECgQJBgAAAA==.Pallom:BAAALgAECgEJAgAAAA==.Parsera:BAAALgAECggJCAABLgAECgkJNQADAB4lAA==.Parseus:BAAALgAECgkJCQABLgAECgkJNQADAB4lAA==.Parseval:BAABLgAECn81AAQDAAkJHiU3AgCaAwADAAkJHiU3AgCaAwAWAAgJ0RvwFQAbAgAEAAQJPxsuQwAsAQAAAA==.Parshock:BAAALgAECgQJBAABLgAECgkJNQADAB4lAA==.Pawerful:BAAALgADCgYJBgABLgAECgkJPQAMAKAlAA==.Paws:BAABLgAECn89AAIMAAkJoCWfAwAuAwAMAAkJoCWfAwAuAwAAAA==.Pawsitivity:BAAALgAECgMJAwABLgAECgkJPQAMAKAlAA==.',
Pd='Pdbm:BAAALgAECgEJAgAAAA==.',
Pe='Perdi:BAAALgADCgQJBwAAAA==.Pettigrew:BAAALgAECgQJBAAAAA==.Peut:BAABLgAECn8WAAIXAAgJORigOwBXAQAXAAgJORigOwBXAQAAAA==.',
Ph='Physix:BAABLgAECn8UAAIiAAYJqg2ZHwD2AAAiAAYJqg2ZHwD2AAAAAA==.',
Pi='Pipsqueak:BAAALgAFFAEJAQAAAA==.',
Po='Poedime:BAAALgAECgQJBQAAAA==.Popped:BAAALgAFFAEJAgAAAA==.Porkins:BAABLgAECn9AAAMjAAkJGSBtCgBpAgAjAAgJmx9tCgBpAgAmAAkJqh2DBwAcAgAAAA==.Porkçhop:BAAALgAECgEJAgAAAA==.Potterpanda:BAAALgAECgYJCQAAAA==.Powerline:BAAALgAECgQJBQAAAA==.',
Pr='Priestus:BAAALgAFFAEJAQAAAA==.Promised:BAAALgAECgMJAwABLgAFFAIJBgAdALwhAA==.',
Ps='Psyn:BAAALgAECgQJBAABLgAFFAQJGAALAHAfAA==.Psyndar:BAAALgAECgEJAQABLgAFFAQJGAALAHAfAA==.Psyndra:BAAALgAECgYJCQABLgAFFAQJGAALAHAfAA==.',
Pt='Ptolemy:BAAALgAECgEJAQAAAA==.',
Py='Pyraxx:BAACLgAFFH8MAAIYAAMJ0BMFfgDiAAAYAAMJ0BMFfgDiAAAuAAQKfzMAAhgACQm5IBcVANgCABgACQm5IBcVANgCAAAA.',
['Pê']='Pênny:BAAALgADCgEJAQABLgAFFAUJEAAWAFcJAA==.',
Qt='Qtip:BAAALgAECgMJAwAAAA==.',
Qu='Quakezord:BAAALgADCgYJBgAAAA==.Quesofundido:BAAALgADCgEJAQAAAA==.Quillvo:BAAALgADCgkJDwAAAA==.',
Ra='Radovan:BAACLgAFFH8RAAISAAQJfRrVNwBjAQASAAQJfRrVNwBjAQAuAAQKfzIAAhIACAnDJL8LAO8CABIACAnDJL8LAO8CAAAA.Rakomar:BAAALgAECgQJBAAAAA==.Ramipril:BAAALgADCgMJAwAAAA==.Ranestari:BAAALgADCgcJBgAAAA==.Ranlor:BAAALgADCgYJBgAAAA==.Raphorath:BAABLgAECn8dAAMdAAgJjRLcYgBeAQAdAAgJ7xHcYgBeAQAfAAIJXAy3XgBmAAAAAA==.Rareware:BAAALgADCgEJAQAAAA==.Rax:BAAALgAECgEJAQAAAA==.Razputan:BAAALgAECgYJBgABLgAECgcJDQABAAAAAA==.Raìdèn:BAABLgAECn8xAAMEAAgJQxTVIAC3AQAEAAgJQxTVIAC3AQAWAAUJ2gUHYwCJAAAAAA==.',
Re='Replicate:BAACLgAFFH8GAAIMAAMJYx0uKgAGAQAMAAMJYx0uKgAGAQAuAAQKfyMAAgwACQnrIaQFAAUDAAwACQnrIaQFAAUDAAAA.Resisted:BAAALgAECgEJAQABLgAFFAcJFAAVAC4aAA==.Restocrayze:BAAALgAECgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgIJAwAAAA==.',
Ro='Rookeria:BAAALgADCgYJBgAAAA==.Ropesale:BAAALgADCgEJAQAAAA==.Rosaelyia:BAAALgAECgQJBAABLgAECgkJPAAOAI0cAA==.',
Ry='Ryanmonk:BAAALgAFFAEJAQAAAA==.Ryanqt:BAAALgAECgcJBwAAAA==.Ryanvoker:BAAALgAECgIJAgAAAA==.Ryanx:BAACLgAFFH8VAAIXAAcJAx7xBQBhAgAXAAcJAx7xBQBhAgAuAAQKfzEAAhcACQmNJd0AAJIDABcACQmNJd0AAJIDAAAA.Ryanxx:BAAALgAECgYJBgAAAA==.Ryanxz:BAAALgAECgYJCAAAAA==.Ryomou:BAAALgAECgYJEAAAAA==.Ryri:BAABLgAECn8fAAIhAAcJXxX1FAB+AQAhAAcJXxX1FAB+AQAAAA==.',
Sa='Saatana:BAABLgAECn8ZAAMDAAkJlgqwIgB+AQADAAkJlgqwIgB+AQAWAAIJGQvHcQBaAAAAAA==.Sadima:BAAALgAECgEJAQAAAA==.Sahaquiel:BAAALgAECgEJAQAAAA==.Salife:BAAALgAECggJCgAAAA==.Samavati:BAABLgAECn8uAAMeAAkJbQlAKwBbAQAeAAkJbQlAKwBbAQAFAAcJ0gzILgBDAQAAAA==.Sammi:BAAALgAECgUJBgAAAA==.Samrc:BAAALgAECgIJAgAAAA==.Sanddragon:BAAALgADCgcJDQAAAA==.Sands:BAAALgAECggJEQAAAA==.Santoku:BAABLgAECn8QAAIdAAYJsxfQawBIAQAdAAYJsxfQawBIAQAAAA==.Sarah:BAACLgAFFH8QAAIDAAUJiBYGHAB1AQADAAUJiBYGHAB1AQAuAAQKfzMAAgMACQmxH1oFADMDAAMACQmxH1oFADMDAAAA.Sassyface:BAABLgAECn9KAAIRAAkJ7Q63CwCAAQARAAkJ7Q63CwCAAQAAAA==.Sathend:BAAALgADCgUJBQAAAA==.Saveena:BAAALgAECgUJBgAAAA==.Saviq:BAAALgADCgEJAgAAAA==.',
Sc='Scarletdawns:BAAALgADCgEJAQAAAA==.',
Se='Seabolt:BAAALgAECgYJBgABLgAFFAMJBgAKAAcZAA==.Sebbyr:BAAALgADCgMJAwAAAA==.Sellit:BAAALgADCgEJAgAAAA==.',
Sh='Shadowdin:BAAALgAECgYJDwAAAA==.Shadowes:BAABLgAECn8XAAMNAAcJ0CBtCgBAAgANAAcJ0CBtCgBAAgAMAAEJcRuLjgBRAAAAAA==.Shaduw:BAACLgAFFH8ZAAIZAAcJwx+4BgDRAQAZAAcJwx+4BgDRAQAuAAQKfyQAAxkACAnOIbMDABkDABkACAnOIbMDABkDAAwACAkBDj8yAOMBAAAA.Shanalister:BAAALgADCgUJBQAAAA==.Shari:BAABLgAECn8WAAICAAcJkBD/KgA8AQACAAcJkBD/KgA8AQAAAA==.Shiklah:BAAALgAECgQJBAAAAA==.Shuyinn:BAAALgAECgcJEAABLgAECgkJJgARAKsPAA==.',
Si='Sibbrena:BAACLgAFFH8GAAIWAAMJPBb3IwDPAAAWAAMJPBb3IwDPAAAuAAQKfzYAAhYACQlGIfwFAC4DABYACQlGIfwFAC4DAAAA.Sivanna:BAAALgAECgQJAgABLgAECgkJCAABAAAAAA==.Sixpacksorc:BAACLgAFFH8GAAIYAAMJCBsRewDnAAAYAAMJCBsRewDnAAAuAAQKfycAAhgACQlNIykVACkDABgACQlNIykVACkDAAAA.',
Sk='Skn:BAABLgAECn8hAAMXAAgJniPOEACMAgAXAAgJniPOEACMAgAcAAQJrRhiLgF8AAAAAA==.',
Sl='Slam:BAAALgAECgIJAgAAAA==.Sleeping:BAAALgADCgEJAQAAAA==.Slizzard:BAAALgAECgYJDgAAAA==.',
Sm='Smutty:BAAALgAECggJEAAAAA==.',
Sn='Snackychan:BAABLgAECn8aAAMFAAgJDSPpCQC0AgAFAAcJnyLpCQC0AgAkAAYJJBWeMwAyAQAAAA==.Sniperdoom:BAAALgADCgYJBgAAAA==.',
So='Soggycheezit:BAAALgADCgcJBwAAAA==.Souleater:BAAALgAECgEJAQAAAA==.Sourdiesal:BAAALgAECgUJBQAAAA==.',
Sp='Spigvoker:BAAALgADCgEJAQAAAA==.Spleen:BAABLgAECn8eAAQgAAgJEBf/CACxAQAgAAgJyhX/CACxAQACAAQJ9RiNPwAhAQAnAAEJMAiuDgAyAAAAAA==.Spron:BAAALgADCggJCAAAAA==.Spywo:BAAALgAECgEJAQABLgAECgIJAgABAAAAAA==.',
Sq='Squirrelydan:BAAALgAECgUJCwAAAA==.',
St='Stabbý:BAAALgAECgYJBgABLgAFFAUJEAAWAFcJAA==.Stabinem:BAAALgADCgcJAQAAAA==.Stardria:BAAALgAECgEJAQAAAA==.Steakfries:BAABLgAECn8YAAIcAAkJjwQh0wDsAAAcAAkJjwQh0wDsAAAAAA==.Stelthme:BAABLgAECn8aAAQgAAYJIxjDCwBwAQAgAAYJIxjDCwBwAQAnAAMJQwgvGgB9AAACAAEJGAiiXgA5AAABLgAFFAQJDgACAEwlAA==.Stormburst:BAAALgADCgIJAgABLgAFFAUJFgAgAJsjAA==.Stormi:BAAALgADCgYJBgAAAA==.Strawberries:BAABLgAECn8cAAIYAAcJQyFKOgCNAgAYAAcJQyFKOgCNAgABLgAECggJFAAQAEElAA==.',
Su='Susaki:BAAALgAECgQJBQAAAA==.',
Sw='Swan:BAAALgAECgcJCQABLgAFFAQJEAAQAA4PAA==.Swoleyspirit:BAAALgAECgMJBQAAAA==.',
Ta='Takamura:BAABLgAECn8wAAIZAAkJJSE8AwADAwAZAAkJJSE8AwADAwAAAA==.Takeshì:BAAALgAECgcJBwABLgAECggJMQAEAEMUAA==.Tarle:BAAALgAECgcJCgAAAA==.Tazath:BAACLgAFFH8KAAIVAAQJkBHKMQD5AAAVAAQJkBHKMQD5AAAuAAQKfyIAAxUACQl5IKsGAO0CABUACQl5IKsGAO0CACUAAgnTAX9EACQAAAAA.',
Te='Techsorcist:BAAALgAECgQJBQAAAA==.Tenten:BAAALgAECgMJAwAAAA==.',
Th='Theory:BAABLgAECn9OAAMJAAkJ1xrkKABbAgAJAAkJJxrkKABbAgAjAAIJ+hh8PwCOAAAAAA==.Thessali:BAAALgAECgYJCwAAAA==.Thiccen:BAAALgADCgEJAQABLgADCgIJAgABAAAAAA==.Thoranji:BAAALgAECgUJCAAAAA==.',
Ti='Tipz:BAAALgAECgUJBwAAAA==.Tism:BAAALgADCgcJBwAAAA==.Titanpanda:BAAALgAECgkJDwAAAA==.',
Tj='Tj:BAAALgAECgcJBgAAAA==.',
To='Tomjim:BAACLgAFFH8UAAMVAAcJLhopHQBvAQAVAAYJ4BkpHQBvAQAbAAMJZQXtEwCLAAAuAAQKfyYABBUACAlAIwsLAMUCABUACAlAIwsLAMUCABsABwnmEBodAJwBACUABglrCzEiABkBAAAA.',
Tr='Trashii:BAABLgAECn85AAIQAAkJQBzYDgA+AgAQAAkJQBzYDgA+AgAAAA==.Treevive:BAACLgAFFH8MAAIKAAYJzxJnFgCmAQAKAAYJzxJnFgCmAQAuAAQKfxkAAgoACAmaIEEcAFoCAAoACAmaIEEcAFoCAAAA.Trencough:BAAALgAECgYJEgAAAA==.Trenx:BAAALgAECgUJCAAAAA==.Trystan:BAABLgAECn9JAAIcAAkJEB59FQDAAgAcAAkJEB59FQDAAgAAAA==.',
Ts='Tsinga:BAABLgAECn8gAAIIAAYJaRN7GwAqAQAIAAYJaRN7GwAqAQAAAA==.',
Tu='Tugbote:BAAALgAECgUJBQAAAA==.Turl:BAABLgAECn8VAAIYAAYJEhLVowAxAQAYAAYJEhLVowAxAQABLgAECggJJgAXAEggAA==.Turlo:BAABLgAECn8mAAIXAAcJSCBkHwAGAgAXAAcJSCBkHwAGAgAAAA==.',
Tw='Tweik:BAAALgADCgcJCAAAAA==.Twoglaives:BAAALgAECggJDgABLgAFFAYJFwAnANsPAA==.Twostep:BAACLgAFFH8XAAInAAYJ2w8qAwB1AQAnAAYJ2w8qAwB1AQAuAAQKfyoAAicACQnzGRUDACwCACcACQnzGRUDACwCAAAA.',
['Tø']='Tøm:BAACLgAFFH8SAAIcAAcJ8h++DgDtAQAcAAcJ8h++DgDtAQAuAAQKfyIAAhwABwmkJTsYANgCABwABwmkJTsYANgCAAAA.',
Ul='Ullirus:BAAALgADCgYJAwAAAA==.',
Un='Unbearable:BAAALgADCgYJBgAAAA==.Unbroken:BAAALgADCgEJAQAAAA==.Undergrowth:BAAALgAFFAEJAgAAAA==.Unholyblodd:BAAALgADCggJCAAAAA==.Unshookable:BAACLgAFFH8MAAIFAAMJDBRSOgCxAAAFAAMJDBRSOgCxAAAuAAQKfy8AAgUACQmTHdQUAG4CAAUACQmTHdQUAG4CAAAA.',
Ur='Ursos:BAABLgAECn8gAAIGAAcJfBjZFgCWAQAGAAcJfBjZFgCWAQAAAA==.',
Uz='Uzume:BAAALgADCgEJAQAAAA==.',
Va='Valefor:BAABLgAECn8XAAMVAAkJERg6HADyAQAVAAkJERg6HADyAQAbAAEJ1gFSTAApAAAAAA==.Valiantinter:BAAALgAECgEJAQAAAA==.Vallatris:BAAALgAECgcJDgAAAA==.Valomyr:BAAALgAECgMJAwABLgAECgcJFwANANAgAA==.Valsande:BAAALgAECgQJAwAAAA==.Vargr:BAAALgADCgIJAgAAAA==.',
Ve='Vedis:BAAALgAECgEJAQAAAA==.Velton:BAAALgADCgMJAwAAAA==.Vendnmachine:BAABLgAECn88AAIYAAgJuxd2QgASAgAYAAgJuxd2QgASAgAAAA==.Verilyx:BAAALgAECgIJAgAAAA==.Vermaelen:BAAALgAECgcJDAAAAA==.Vexmord:BAAALgADCgEJAQAAAA==.',
Vh='Vhyk:BAAALgADCgYJBgAAAA==.',
Vi='Vika:BAAALgAECgEJAQABLgAECgcJIAAGAHwYAA==.Viracocha:BAABLgAFFH8JAAMLAAQJ/Rq4QgDWAAALAAMJtxi4QgDWAAAiAAEJCBpTGABKAAAAAA==.Vitki:BAAALgADCgIJAgAAAA==.Viviera:BAAALgADCgcJBwABLgAECgcJDwABAAAAAA==.',
Vo='Voidh:BAAALgAFFAIJAgAAAA==.Voidlockus:BAAALgAFFAIJAwAAAA==.',
Vu='Vulcin:BAAALgAECgcJCQABLgAFFAMJDAAYANATAA==.',
Wa='Wargeezer:BAAALgAECgEJAgAAAA==.Wariuus:BAAALgAECgEJAQAAAA==.Watercupp:BAAALgAECgMJBAAAAA==.',
We='Wear:BAABLgAECn8eAAIdAAYJdRpDWQB4AQAdAAYJdRpDWQB4AQAAAA==.Wetwizard:BAAALgADCgcJBwAAAA==.',
Wh='Whimsy:BAAALgADCgcJDwABLgADCgkJDAABAAAAAA==.Whitegirls:BAAALgAECgIJAgAAAA==.',
Wi='Winder:BAAALgAECgQJBQAAAA==.Windercurse:BAAALgAECgEJAgAAAA==.Winderk:BAAALgAECgEJAQAAAA==.Winderkin:BAAALgAECgEJAgAAAA==.Winderv:BAAALgAECgEJAQAAAA==.Wisewithpet:BAAALgAECgYJCQAAAA==.Wisheni:BAABLgAECn8kAAIDAAcJMhIXLgBoAQADAAcJMhIXLgBoAQAAAA==.',
Wr='Wrathofdolph:BAAALgAECgUJCgAAAA==.Wrexx:BAAALgAFFAEJAQAAAA==.',
Xi='Xial:BAABLgAECn8WAAILAAcJmRvCHwBNAgALAAcJmRvCHwBNAgABLgAECgYJEwABAAAAAA==.',
Xy='Xyfin:BAABLgAECn8oAAIQAAkJVRyJBgCaAgAQAAkJVRyJBgCaAgAAAA==.',
Yo='Yoruichi:BAAALgADCgEJAQAAAA==.',
Yu='Yunalescah:BAAALgAECgMJAwAAAA==.Yuno:BAAALgAECgEJAQAAAA==.',
Za='Zaboo:BAABLgAECn8UAAQaAAYJvyB9DABwAQASAAUJcx6VXACzAQAaAAQJByJ9DABwAQARAAEJAABYYABOAAABLgAFFAIJBQALACcjAA==.Zandramadas:BAABLgAECn9NAAQHAAkJFiAvFQAkAgAHAAkJFiAvFQAkAgAKAAgJqRloLAD9AQAGAAcJ2BO4HQBaAQAAAA==.Zaraline:BAABLgAECn88AAIOAAkJjRwzGACRAgAOAAkJjRwzGACRAgAAAA==.Zarasha:BAAALgAECgQJBgAAAA==.',
Ze='Zeakz:BAAALgAECgYJCgAAAA==.Zemsta:BAAALgADCgEJAQAAAA==.Zeolock:BAAALgAECgMJAwAAAA==.Zephon:BAABLgAECn8oAAIJAAgJrBuzPgAFAgAJAAgJrBuzPgAFAgAAAA==.Zerksees:BAAALgADCgMJAwAAAA==.Zezima:BAAALgAECgQJBwAAAA==.',
Zh='Zhuu:BAAALgAECgYJBgAAAA==.',
Zi='Zinyak:BAABLgAECn8UAAIJAAYJbBa7nQAtAQAJAAYJbBa7nQAtAQAAAA==.Zithrax:BAAALgADCgYJBgAAAA==.',
Zo='Zohara:BAAALgAECgQJBAAAAA==.Zoomiez:BAAALgAECggJEwAAAA==.',
Zu='Zumwalmilui:BAAALgAECgEJAgAAAA==.',
Zy='Zyyn:BAABLgAECn8zAAIYAAkJUR6UHgCjAgAYAAkJUR6UHgCjAgAAAA==.',
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
