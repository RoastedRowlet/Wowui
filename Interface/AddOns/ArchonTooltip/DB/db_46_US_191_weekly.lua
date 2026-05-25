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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Paladin-Protection','Druid-Guardian','Mage-Frost','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-05-23',data={Ab='Abyssara:BAAALgAECgYJEQAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR8SZgD/AAABAAMJqR8SZgD/AAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUtCAD8AAACAAMJwBUtCAD8AAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB5i7ADMAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn8tAAIFAAkJTyJBAgDeAgAFAAkJTyJBAgDeAgAAAA==.Aeón:BAAALgAECgcJDAAAAA==.',
Ag='Aggen:BAABLgAECn8dAAIGAAkJ4hcpLwAiAgAGAAkJ4hcpLwAiAgAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.',
Al='Al:BAACLgAFFH8JAAMHAAMJfQvCHADaAAAHAAMJfQvCHADaAAAIAAIJbQRNJQBkAAAuAAQKfykAAwcACAnLGBAYAOIBAAcACAnLGBAYAOIBAAgABwlpEUErAJsBAAAA.Alandarus:BAAALgAECgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8fAAIGAAYJkByHWQChAQAGAAYJkByHWQChAQAAAA==.Allenwalker:BAAALgAECgUJCAAAAA==.Alucarde:BAEALgADCgYJBgABLgAECggJFQAJAGMZAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8aAAIDAAkJGBNUHwAoAgADAAkJGBNUHwAoAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwAKACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJCAABLgAECgkJHwALAEMZAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8gAAMMAAgJbwqsNwApAQAMAAgJbwqsNwApAQAKAAQJEgJOlABkAAAAAA==.',
Ao='Aoi:BAABLgAECn8jAAMNAAgJYxGBLAAwAQANAAYJ9ROBLAAwAQAOAAgJnwrIOgAuAQAAAA==.',
Ar='Arrisia:BAABLgAECn8iAAMPAAgJnBBcSgCWAQAPAAgJnBBcSgCWAQAQAAIJJwSHLwA/AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8MAAIRAAMJXx+qEQDzAAARAAMJXx+qEQDzAAAuAAQKfzIAAhEACQnSI30BAHIDABEACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8TAAISAAQJih67CABmAQASAAQJih67CABmAQAuAAQKfzAAAhIACQlzIwoEANgCABIACQlzIwoEANgCAAEuAAUUAwkMABEAXx8A.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECggJGgAEAPARAA==.Autumni:BAABLgAECn8eAAIPAAcJUhjTSgCUAQAPAAcJUhjTSgCUAQAAAA==.Auvry:BAABLgAECn8aAAMTAAcJVhkdEAA5AgATAAcJVhkdEAA5AgAUAAIJqAkAgAAsAAAAAA==.',
Ay='Aymus:BAABLgAECn8VAAMVAAYJtQL1xwBnAAAVAAYJbgL1xwBnAAAWAAMJzAGRZQAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8aAAIGAAgJhAZkmQAhAQAGAAgJhAZkmQAhAQAAAA==.Bakala:BAABLgAECn8kAAMRAAgJiRFyHAApAQARAAgJCwpyHAApAQAXAAYJWRSXPgAiAQAAAA==.Bangbang:BAABLgAECn8qAAIPAAkJqBUQOwDIAQAPAAkJqBUQOwDIAQAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8bAAIJAAgJhxD4KQCYAQAJAAgJhxD4KQCYAQAAAA==.Belenos:BAAALgADCggJFwABLgADCggJFwAYAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIQAAMJHwuXFQDIAAAQAAMJHwuXFQDIAAAuAAQKfx4AAhAACQnSE3kqANgBABAACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8aAAIVAAgJ/gsiXQBNAQAVAAgJ/gsiXQBNAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wopEgBSAQAFAAgJ5wopEgBSAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8fAAIIAAgJFhWUFgD1AQAIAAgJFhWUFgD1AQAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAABLgAECn8rAAIRAAkJJxr1CgAbAgARAAkJJxr1CgAbAgAAAA==.Bordok:BAABLgAECn8WAAIZAAgJNgcqEwACAQAZAAgJNgcqEwACAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brows:BAAALgADCgkJCQAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMPAAkJ0h2OFgB3AgAPAAkJ0h2OFgB3AgAQAAYJyRNiEwACAQAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8dAAIIAAcJ+hYkGwDIAQAIAAcJ+hYkGwDIAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBYZDADCAQACAAYJVxgZDADCAQADAAgJdglAWAAPAQAEAAYJSgykPQDnAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8mAAIFAAgJLSANBQBtAgAFAAgJLSANBQBtAgAAAA==.Celiñ:BAACLgAFFH8HAAMaAAMJZxTeCgCWAAAaAAMJ7QreCgCWAAAGAAIJ9xPfcQCQAAAuAAQKfycABAYACQmiIEETALQCAAYACAmyIkETALQCABoABAnRE9stAIYAAAkAAwnuBAVpAGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAaAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgQJBwAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIHAAcJdAdKOgAfAQAHAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgQJBQAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn8sAAMbAAgJKB6OCQAWAgAbAAgJmBqOCQAWAgACAAYJpiJvCQD8AQABLgAECgkJLQAFAE8iAA==.Crunky:BAABLgAECn8jAAIOAAgJVA8BLwBvAQAOAAgJVA8BLwBvAQAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBQAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIcAAkJNh5sMgCpAgAcAAkJNh5sMgCpAgAAAA==.',
Da='Dadmike:BAAALgAECgEJAQAAAA==.Dahealzrhere:BAAALgAECgYJCgAAAA==.Dalel:BAABLgAECn8bAAIVAAgJWCCLHABMAgAVAAgJWCCLHABMAgAAAA==.Dameond:BAAALgAECgQJBQAAAA==.David:BAAALgADCgQJBAABLgAECgkJLAASAJkgAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAYAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAABLgAECn8eAAMKAAcJbSHOEQCUAgAKAAcJbSHOEQCUAgAFAAMJeBCZIQCaAAAAAA==.Demonicteli:BAABLgAECn8WAAIWAAkJlxmZEABdAgAWAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECgYJBgAAAA==.Dermot:BAABLgAECn8tAAQdAAgJLiN0AwC6AgAdAAcJZCJ0AwC6AgALAAUJ+iDKagBQAQAeAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJDwAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBFAJgBsAQAEAAgJLBFAJgBsAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8VAAIGAAgJaRKaUgCzAQAGAAgJaRKaUgCzAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn8nAAIGAAYJOAkMuwDsAAAGAAYJOAkMuwDsAAAAAA==.Domaon:BAABLgAECn8nAAIWAAkJ0CDEBADPAgAWAAkJ0CDEBADPAgAAAA==.Domshammy:BAAALgAECgIJAgABLgAECgkJJwAWANAgAA==.Doombunny:BAAALgAECgUJCQABLgAECggJNAAPAHAZAA==.Doubt:BAABLgAECn8UAAIHAAgJnQeyMwAiAQAHAAgJnQeyMwAiAQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJDAAAAA==.',
Du='Dullgrim:BAAALgADCgcJBwAAAA==.Dunigan:BAABLgAECn80AAMGAAgJThHlYQCNAQAGAAgJTRDlYQCNAQAaAAYJDg8cIADjAAAAAA==.Dunigen:BAAALgAECgEJAQAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn81AAISAAkJOxaVCwBOAgASAAkJOxaVCwBOAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgcJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgQJBQAAAA==.Facepalm:BAABLgAECn8XAAIXAAgJJRGaJgCfAQAXAAgJJRGaJgCfAQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAYAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8ZAAIDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8cAAIZAAgJwguLDwAxAQAZAAgJwguLDwAxAQAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8hAAIKAAcJcxl6IwAMAgAKAAcJcxl6IwAMAgAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn87AAIKAAkJOxa5HgArAgAKAAkJOxa5HgArAgAAAA==.Foxmccloud:BAABLgAECn8jAAMKAAgJmhqZFgBoAgAKAAgJmhqZFgBoAgAMAAIJowkgiwAtAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8bAAIcAAgJRR7UJgBjAgAcAAgJRR7UJgBjAgAAAA==.',
Fu='Fuil:BAAALgADCgYJBgAAAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn8pAAIXAAcJlBuMGwDtAQAXAAcJlBuMGwDtAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8ZAAITAAgJkRaMCgASAgATAAgJkRaMCgASAgAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn8jAAIbAAgJUxeFDQDPAQAbAAgJUxeFDQDPAQAAAA==.',
Gy='Gyre:BAABLgAECn8VAAIPAAYJZxDxcwAqAQAPAAYJZxDxcwAqAQAAAA==.',
Ha='Haezi:BAAALgADCgYJBgAAAA==.Happyendings:BAAALgAECgcJDQAAAA==.',
He='Helbafx:BAAALgAECgQJCwAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8XAAIRAAYJyxYRHwAQAQARAAYJyxYRHwAQAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.',
If='Ifearnobeer:BAABLgAECn8oAAIMAAkJEwrcMgBCAQAMAAkJEwrcMgBCAQAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAaAN4PAA==.',
In='Inters:BAAALgAECgUJCgAAAA==.',
Ir='Ironspark:BAAALgAECgcJDgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwvyKAD2AAADAAQJTwvyKAD2AAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJCQAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAABLgAECn8bAAIKAAgJsBTnJQD9AQAKAAgJsBTnJQD9AQAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAINAAkJ4g4LHAClAQANAAkJ4g4LHAClAQAAAA==.',
Je='Jessuss:BAABLgAECn8VAAIGAAcJZAy1kQAuAQAGAAcJZAy1kQAuAQAAAA==.',
Jh='Jha:BAAALgADCgYJBgAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJFwAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQMfPAChAAADAAMJqQMfPAChAAAuAAQKfyoAAgMACQnTEJ0uAMcBAAMACQnTEJ0uAMcBAAAA.Kalebeesd:BAABLgAECn8XAAIVAAcJ0RRtUAByAQAVAAcJ0RRtUAByAQAAAA==.Karthdh:BAAALgADCgMJAwABLgADCggJCAAYAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRTlMAC6AQADAAgJPRTlMAC6AQAAAA==.Kawk:BAABLgAECn8uAAIaAAkJWx+LBAC7AgAaAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8FAAIMAAQJjRX7FgArAQAMAAQJjRX7FgArAQAuAAQKfyUAAgwACAn5I/4OALcCAAwACAn5I/4OALcCAAAA.',
Ke='Kebob:BAABLgAECn8VAAIaAAkJ3g9lEwBnAQAaAAkJ3g9lEwBnAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAIRAAgJ5ByICgAkAgARAAgJ5ByICgAkAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8HAAIcAAQJigURMwDRAAAcAAQJigURMwDRAAAuAAQKfyMAAhwACAmWF0BKAFgCABwACAmWF0BKAFgCAAEuAAUUBQkOAAEAOBEA.Kittylover:BAAALgADCgcJCgAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIHAAMJMRcwGQD6AAAHAAMJMRcwGQD6AAAuAAQKfx4AAgcACQmqHowNAKoCAAcACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8XAAIXAAYJFh0tJgCiAQAXAAYJFh0tJgCiAQAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgcJDwAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAABLgAECn8gAAIcAAgJuxHUZACYAQAcAAgJuxHUZACYAQAAAA==.',
Kw='Kwanu:BAAALgAECgYJDwAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgcJDAAYAAAAAA==.',
La='Lantern:BAAALgADCgUJBQAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAABLgAECn8WAAIGAAUJZQ1vpgAMAQAGAAUJZQ1vpgAMAQAAAA==.Laylani:BAAALgAECgYJEAAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIVAAkJ8Rc7LgBEAgAVAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8VAAIfAAkJow1OCQBVAQAfAAkJow1OCQBVAQAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECggJGgAEAPARAA==.Lotuss:BAAALgAECgYJDAABLgAECgkJLgAMALMbAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8bAAIgAAgJnREsGgBbAQAgAAgJnREsGgBbAQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgADCgcJBwAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8UAAIEAAgJGAi3MgAfAQAEAAgJGAi3MgAfAQAAAA==.Massack:BAABLgAECn8bAAIhAAgJEBE9IQB/AQAhAAgJEBE9IQB/AQAAAA==.Mastik:BAAALgAECgEJAQAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAJAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJBwAAAA==.',
Mu='Muldoinit:BAABLgAECn8bAAINAAgJHhX1GwClAQANAAgJHhX1GwClAQAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJCwABLgAECgUJCAAYAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8UAAIJAAcJsx85FQA8AgAJAAcJsx85FQA8AgAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAABLgAECn8iAAQiAAkJ7R3KBQDaAQAiAAYJZhrKBQDaAQAjAAUJzR2jBwC1AQAkAAYJIBVSHwBvAQAAAA==.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAcAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwALAG8TAA==.Nytemayer:BAACLgAFFH8HAAILAAMJbxNfWgDjAAALAAMJbxNfWgDjAAAuAAQKfysABAsACQmIIFAUAJUCAAsACQl+H1AUAJUCAB0AAwmYH4szAOkAAB4AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn8jAAICAAgJnRD7DwCAAQACAAgJnRD7DwCAAQAAAA==.Oboñ:BAABLgAECn8aAAMeAAgJTg5hCgCEAQAeAAgJTg5hCgCEAQALAAEJYwOvNQEfAAAAAA==.Obsfuyung:BAABLgAECn8jAAINAAgJAhE6JQBeAQANAAgJAhE6JQBeAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Or='Orcc:BAAALgADCgkJDAAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8eAAMBAAgJzxa+XwCGAQABAAgJJRG+XwCGAQAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8hAAQJAAgJFxsRFABIAgAJAAgJFxsRFABIAgAGAAEJ2wH2hgEVAAAaAAEJAAD5UQAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8aAAMdAAgJABEnCgB0AQAdAAgJABEnCgB0AQALAAEJNgHEOgENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.',
Py='Pyrokos:BAACLgAFFH8FAAIcAAMJUBlbYQDzAAAcAAMJUBlbYQDzAAAuAAQKfyEAAhwACAnsIDliABUCABwACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMlAAkJkiEuCQAzAgAlAAkJkiEuCQAzAgAXAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8PAAIJAAQJMh/AFQBEAQAJAAQJMh/AFQBEAQAuAAQKfx8AAgkACQn8HdMMALMCAAkACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIXAAgJ7BBNNQBNAQAXAAgJ7BBNNQBNAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIcAAQJ4xnJNQBXAQAcAAQJ4xnJNQBXAQAuAAQKfyYAAhwACAkiJT4UAMYCABwACAkiJT4UAMYCAAAA.Roshak:BAAALgADCgMJAwAAAA==.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8QAAIGAAQJjBFrMgAqAQAGAAQJjBFrMgAqAQAuAAQKfy0AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR48PQAOAQAGAAMJVR48PQAOAQAuAAQKfywAAgYACQkGImANAOACAAYACQkGImANAOACAAAA.',
Sa='Sabaak:BAABLgAECn8bAAIGAAYJKyLxPgDrAQAGAAYJKyLxPgDrAQAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn8fAAILAAgJuQkzaABWAQALAAgJuQkzaABWAQAAAA==.Saintsnyder:BAABLgAECn8cAAIGAAYJ5xMShgBCAQAGAAYJ5xMShgBCAQAAAA==.Saithis:BAAALgAECgYJEwAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJBgABLgAECgYJBwAYAAAAAA==.Sanorasong:BAEBLgAECn8VAAMJAAgJYxkTGAAgAgAJAAgJYxkTGAAgAgAGAAQJbwxj9gCXAAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgYJBwAAAA==.Sarylin:BAABLgAECn8UAAMPAAgJyRt1HgBGAgAPAAgJyRt1HgBGAgAQAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn8jAAIdAAgJpBQVBwC3AQAdAAgJpBQVBwC3AQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgcJCwAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAABLgAECn8bAAILAAgJ3gmiZgBaAQALAAgJ3gmiZgBaAQAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAIKAAMJKx7iKwD7AAAKAAMJKx7iKwD7AAAuAAQKfxsAAgoACQnPHikGAA8DAAoACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8UAAMMAAcJlwm4QQD8AAAMAAcJlwm4QQD8AAAFAAMJ2wMBKABaAAAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgAECgMJAwAAAA==.',
Si='Sighah:BAAALgAECgkJEAAAAA==.Sinensis:BAABLgAECn8aAAIjAAkJTBVlBAAmAgAjAAkJTBVlBAAmAgAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgEJAQABLgAECggJGwAVAFggAA==.Skarletflame:BAAALgAECggJEwAAAA==.',
Sl='Slather:BAABLgAECn8aAAITAAgJcBAKGADVAQATAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIcAAgJtBC1YQCfAQAcAAgJtBC1YQCfAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAAALgAECgUJBQAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECggJFQAJAGMZAA==.Sorne:BAAALgAFFAQJBAAAAA==.',
Sp='Spaghett:BAABLgAECn8fAAMhAAkJRBQzIQB/AQAhAAkJphEzIQB/AQANAAYJJhNSOAD0AAAAAA==.Springtotem:BAABLgAECn8aAAIEAAgJ8BHaJgBnAQAEAAgJ8BHaJgBnAQAAAA==.',
St='Stachel:BAAALgAECgQJBQAAAA==.Stanger:BAAALgAECggJEgAAAA==.Storaxota:BAAALgAFFAUJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAECgkJLgAMALMbAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AuFOACSAQADAAkJ6AuFOACSAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIWAAgJshTQGQB4AQAWAAgJshTQGQB4AQAAAA==.',
Ta='Tael:BAABLgAECn8sAAIXAAkJYR8xCQCvAgAXAAkJYR8xCQCvAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8OAAImAAQJCg2/HAAjAQAmAAQJCg2/HAAjAQAuAAQKfyoAAyYACAnuGWgVAPwBACYACAnuGWgVAPwBAAgAAQkFFq57ADoAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwjoagDTAAADAAcJTwjoagDTAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAABLgAECn8uAAMMAAkJsxuKDQBsAgAMAAkJsxuKDQBsAgAKAAIJvgjApQBEAAAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8bAAIPAAgJ+wm0XgBcAQAPAAgJ+wm0XgBcAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAABLgAECn8YAAIGAAcJPx03MgBZAgAGAAcJPx03MgBZAgAAAA==.Thundertoes:BAABLgAECn8bAAMKAAgJxxoHFgBtAgAKAAgJxxoHFgBtAgAFAAYJChLiFwAEAQAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgIJBAABLgAECgYJDgAYAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8cAAMKAAcJ2RQ+MwC2AQAKAAcJ2RQ+MwC2AQAMAAUJqQjWWwCgAAAAAA==.Torgoth:BAABLgAECn8aAAIFAAgJvRGnDgCMAQAFAAgJvRGnDgCMAQAAAA==.Toshido:BAABLgAECn8UAAIPAAYJWhCQggAJAQAPAAYJWhCQggAJAQAAAA==.',
Tr='Traetor:BAABLgAECn8bAAIEAAgJzCX0AwAIAwAEAAgJzCX0AwAIAwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8VAAIGAAYJvgcywADkAAAGAAYJvgcywADkAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAABLgAECn8VAAIKAAYJwQkvZgDwAAAKAAYJwQkvZgDwAAAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAAALgAECgcJDgAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiGeLQAoAgAGAAkJXiGeLQAoAgAJAAkJgg2xPQCCAQABLgAFFAMJDQAVAIUUAA==.Valiantaint:BAACLgAFFH8NAAIVAAMJhRQPRADuAAAVAAMJhRQPRADuAAAuAAQKfyoAAhUACQkHHqoXAGsCABUACQkHHqoXAGsCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAMJDQAVAIUUAA==.Valyulon:BAAALgADCgMJAwABLgAFFAMJDQAVAIUUAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8VAAIGAAgJDSBHGwCDAgAGAAgJDSBHGwCDAgAAAA==.Vendeldh:BAABLgAECn8sAAIVAAkJuCPUEgDpAgAVAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8YAAIPAAgJoA31UQB/AQAPAAgJoA31UQB/AQAAAA==.',
Vi='Virajr:BAABLgAECn8YAAMkAAgJFw6xGgCZAQAkAAgJFw6xGgCZAQAiAAEJvATxIAAhAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIXAAkJ8wd/NABRAQAXAAkJ8wd/NABRAQAAAA==.Vissiction:BAABLgAECn8XAAIVAAgJ4xN7PwCpAQAVAAgJ4xN7PwCpAQAAAA==.Vistine:BAABLgAECn8vAAIaAAkJqAmkGwAMAQAaAAkJqAmkGwAMAQAAAA==.Vitez:BAABLgAECn8WAAMdAAkJrAZ5FwDGAAAdAAgJFAd5FwDGAAALAAIJRAMh+ABPAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8gAAIcAAYJBw6RpQAXAQAcAAYJBw6RpQAXAQAAAA==.Wendy:BAABLgAECn8iAAIKAAgJuhh2LADYAQAKAAgJuhh2LADYAQABLgAECgkJGgADABgTAA==.',
Wi='Win:BAAALgAECgYJDQABLgAECgkJNgALANEYAA==.Winkster:BAACLgAFFH8MAAIGAAUJWRwzHQBeAQAGAAUJWRwzHQBeAQAuAAQKfzAAAgYACQn4JDoGACgDAAYACQn4JDoGACgDAAAA.',
Xa='Xanadu:BAABLgAECn8vAAImAAkJFx4sBQAWAwAmAAkJFx4sBQAWAwAAAA==.Xarinia:BAABLgAECn8cAAMUAAgJKg4BLABoAQAUAAgJKg4BLABoAQATAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8aAAIbAAgJVBlLDADjAQAbAAgJVBlLDADjAQAAAA==.',
Xd='Xdynasty:BAACLgAFFH8RAAIkAAQJ7hiIEgBLAQAkAAQJ7hiIEgBLAQAuAAQKfycAAyQACQkCJCwMANUCACQACQn/IywMANUCACMABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn82AAQLAAkJ0RgHRAC4AQALAAkJJRUHRAC4AQAdAAUJGBR5JQAxAQAeAAIJVgtDMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8fAAMKAAkJ0w+ENgCmAQAKAAkJ0w+ENgCmAQAMAAEJggF4oAARAAAAAA==.Zabenir:BAABLgAECn8WAAIHAAgJHhmXGQDUAQAHAAgJHhmXGQDUAQAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJBwAAAA==.',
['Ðe']='Ðexter:BAAALgAECgYJEgAAAA==.',
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
