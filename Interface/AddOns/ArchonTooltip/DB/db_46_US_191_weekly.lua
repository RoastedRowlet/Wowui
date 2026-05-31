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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Guardian','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+tdQDzAAABAAMJqR+tdQDzAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBWBCgDiAAACAAMJwBWBCgDiAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGByLGADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn8vAAIFAAkJTyK5AgDYAgAFAAkJTyK5AgDYAgABLgAECggJOQACAFojAA==.Aeón:BAAALgAECgcJDAAAAA==.',
Ag='Aggen:BAABLgAECn8hAAMGAAkJYxlNJwBNAgAGAAkJYxlNJwBNAgAHAAEJAACBWAAAAAAAAA==.',
Aj='Aja:BAAALgADCgEJAQAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJciacAACSAwABAAkJciacAACSAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwopGgADAQAIAAQJGwopGgADAQAJAAIJbQSfKQBYAAAuAAQKfykAAwgACAnLGIoaANUBAAgACAnLGIoaANUBAAkABwlpEUErAJsBAAAA.Alandarus:BAAALgAECgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8fAAIGAAYJkBwMYACXAQAGAAYJkBwMYACXAQAAAA==.Allenwalker:BAAALgAECgUJCAAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJGwAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8aAAIDAAkJGBPDIQAnAgADAAkJGBPDIQAnAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJCAABLgAECgkJHwAMAEMZAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8mAAMNAAgJlwteOgAwAQANAAgJlwteOgAwAQALAAQJEgJnoABkAAAAAA==.',
Ao='Aoi:BAABLgAECn8rAAMOAAgJyxEDIACYAQAOAAgJyxEDIACYAQAPAAgJnwqTQgAuAQAAAA==.',
Ar='Arrisia:BAABLgAECn8qAAMQAAgJQRHISgCpAQAQAAgJQRHISgCpAQARAAIJJwTwMgA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8MAAISAAMJXx+NFADiAAASAAMJXx+NFADiAAAuAAQKfzIAAhIACQnSI30BAHIDABIACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8XAAITAAQJIyAVCQBvAQATAAQJIyAVCQBvAQAuAAQKfzAAAhMACQlzI9QEANECABMACQlzI9QEANECAAEuAAUUAwkMABIAXx8A.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECggJHAAEAHgSAA==.Autumni:BAABLgAECn8eAAIQAAcJUhj0UQCUAQAQAAcJUhj0UQCUAQAAAA==.Auvry:BAABLgAECn8aAAMUAAcJVhkdEAA5AgAUAAcJVhkdEAA5AgAVAAIJqAnLiAAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJKwAWAEkIAA==.',
Ay='Aymus:BAABLgAECn8VAAMXAAYJtQKF2QBcAAAXAAYJbgKF2QBcAAAYAAMJzAENcAAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8cAAIGAAkJ/Qc8gABTAQAGAAkJ/Qc8gABTAQAAAA==.Bakala:BAABLgAECn8sAAMSAAgJbRJ+GwBDAQASAAgJ6Qx+GwBDAQAZAAYJWRSmQwAfAQAAAA==.Bangbang:BAABLgAECn8qAAIQAAkJqBUGQQDHAQAQAAkJqBUGQQDHAQAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8hAAIKAAgJhxAILQCVAQAKAAgJhxAILQCVAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAaAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIRAAMJHwtmGQC2AAARAAMJHwtmGQC2AAAuAAQKfx4AAhEACQnSE3kqANgBABEACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIXAAkJDg8dQgCqAQAXAAkJDg8dQgCqAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wpfFABSAQAFAAgJ5wpfFABSAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8gAAIJAAgJFhXZGADuAQAJAAgJFhXZGADuAQAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAABLgAECn8xAAISAAkJnBolCwAmAgASAAkJnBolCwAmAgAAAA==.Bordok:BAABLgAECn8YAAIbAAkJOAf+EQAnAQAbAAkJOAf+EQAnAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgEJAQAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMQAAkJ0h08GwBtAgAQAAkJ0h08GwBtAgARAAYJyRPkFAD+AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8jAAMJAAgJtxVzHQDBAQAJAAcJ+hZzHQDBAQAIAAYJIBK9NgAYAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBaLDQC6AQACAAYJVxiLDQC6AQADAAgJdgnyXAANAQAEAAYJSgx2QgDmAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8oAAIFAAgJLSDOBQBrAgAFAAgJLSDOBQBrAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxSWDACUAAAHAAMJ7QqWDACUAAAGAAIJ9xMXfwCIAAAuAAQKfygABAYACQmiIA4WAKgCAAYACAmyIg4WAKgCAAcABAnRE64xAIQAAAoAAwnuBJFuAGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgQJCAAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAdKOgAfAQAIAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn85AAMCAAgJWiMhAwDPAgACAAgJQyMhAwDPAgAcAAgJSxxhCQA0AgAAAA==.Crunky:BAABLgAECn8rAAIPAAgJvBJjJwC/AQAPAAgJvBJjJwC/AQAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBQAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIWAAkJNh5sMgCpAgAWAAkJNh5sMgCpAgAAAA==.',
Da='Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAABLgAECn8dAAIXAAkJuCBEEACuAgAXAAkJuCBEEACuAgAAAA==.Dameond:BAAALgAECgUJCAAAAA==.David:BAAALgADCgQJBAABLgAECgcJAQAaAAAAAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAaAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAABLgAECn8eAAMLAAcJbSEwFACQAgALAAcJbSEwFACQAgAFAAMJeBCvJQCaAAAAAA==.Demonicteli:BAABLgAECn8WAAIYAAkJlxmZEABdAgAYAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDQAAAA==.Dermot:BAABLgAECn8tAAQdAAgJLiN0AwC6AgAdAAcJZCJ0AwC6AgAMAAUJ+iCXcQBMAQAeAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBGHKQBrAQAEAAgJLBGHKQBrAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8YAAIGAAgJexNSVwCtAQAGAAgJexNSVwCtAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn8vAAIGAAcJlQjvtAD7AAAGAAcJlQjvtAD7AAAAAA==.Domaon:BAABLgAECn8uAAIYAAkJrCGvAwAAAwAYAAkJrCGvAwAAAwAAAA==.Domshammy:BAAALgAECgcJCQABLgAECgkJLgAYAKwhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJPQAQAOEXAA==.Doubt:BAABLgAECn8UAAIIAAgJnQehOAAPAQAIAAgJnQehOAAPAQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgcJCQAAAA==.Dunigan:BAABLgAECn80AAMGAAgJThH4cgBuAQAGAAgJTRD4cgBuAQAHAAYJDg/XIgDiAAAAAA==.Dunigen:BAAALgAECgcJCgAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8+AAITAAkJcxjlCgBlAgATAAkJcxjlCgBlAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgcJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgADCgkJEAAAAA==.',
Fa='Facade:BAAALgAECgYJCwAAAA==.Facepalm:BAABLgAECn8dAAIZAAgJghMGJQC5AQAZAAgJghMGJQC5AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAaAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8ZAAIDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQAAAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8cAAIbAAgJwgvXEgAeAQAbAAgJwgvXEgAeAQAAAA==.',
Fi='Fierytotes:BAAALgADCgYJEgAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxk5JwAJAgALAAcJcxk5JwAJAgANAAEJgRzFgABSAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9CAAILAAkJ0RcFHgBDAgALAAkJ0RcFHgBDAgAAAA==.Foxmccloud:BAABLgAECn8pAAMLAAgJmhpgGQBmAgALAAgJmhpgGQBmAgANAAQJlQRghABLAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8hAAIWAAgJhx6tKQBdAgAWAAgJhx6tKQBdAgAAAA==.',
Fu='Fuil:BAAALgAECgEJAQAAAA==.Furgaler:BAAALgAECgUJBQABLgAECgkJHQAXALggAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn8xAAIZAAcJ6xw+GgAIAgAZAAcJ6xw+GgAIAgAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8bAAIUAAkJCRboCABLAgAUAAkJCRboCABLAgAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwABLgAECggJCAAaAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn8rAAIcAAgJHBgeDgDfAQAcAAgJHBgeDgDfAQAAAA==.',
Gy='Gyre:BAABLgAECn8WAAIQAAYJtRBhegAxAQAQAAYJtRBhegAxAQAAAA==.',
Ha='Haezi:BAAALgAECgYJBgAAAA==.Happyendings:BAAALgAECgcJDQAAAA==.',
He='Helbafx:BAAALgAECgYJDAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8XAAISAAYJyxbbIQAIAQASAAYJyxbbIQAIAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAAALgAECgIJBAAAAA==.',
If='Ifearnobeer:BAABLgAECn8uAAMNAAkJEwrANgBCAQANAAkJEwrANgBCAQALAAIJZwiSsQBIAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJDgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwstLgDrAAADAAQJTwstLgDrAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jaiantobea:BAABLgAECn8nAAILAAkJcxl0EAC1AgALAAkJcxl0EAC1AgAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g4hHwCfAQAOAAkJ4g4hHwCfAQAAAA==.Jaycie:BAAALgAECggJCAAAAA==.',
Je='Jessuss:BAABLgAECn8bAAIGAAcJmw4mlwArAQAGAAcJmw4mlwArAQAAAA==.',
Jh='Jha:BAAALgADCgYJBgAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQMHQwCXAAADAAMJqQMHQwCXAAAuAAQKfyoAAgMACQnTEJQxAMYBAAMACQnTEJQxAMYBAAAA.Kalebeesd:BAABLgAECn8iAAIXAAgJ5BjyLAD+AQAXAAgJ5BjyLAD+AQAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAaAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRTVMwC6AQADAAgJPRTVMwC6AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8JAAINAAQJIyHsDgB/AQANAAQJIyHsDgB/AQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kebob:BAABLgAECn8VAAIHAAkJ3g8jFQBkAQAHAAkJ3g8jFQBkAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAISAAgJ5BzqCwAYAgASAAgJ5BzqCwAYAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIWAAUJJgURMwDRAAAWAAUJJgURMwDRAAAuAAQKfyMAAhYACAmWF0BKAFgCABYACAmWF0BKAFgCAAAA.Kittylover:BAAALgADCgcJCgAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMRcvHADuAAAIAAMJMRcvHADuAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8eAAIZAAcJXhz5HADyAQAZAAcJXhz5HADyAQAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgcJEAAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAABLgAECn8iAAIWAAkJERG/TwDVAQAWAAkJERG/TwDVAQAAAA==.',
Kw='Kwanu:BAABLgAECn8XAAIPAAgJFw2YOQBZAQAPAAgJFw2YOQBZAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgcJDAAaAAAAAA==.',
La='Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwAAAA==.Lasloo:BAABLgAECn8bAAIGAAYJ7Q4WjwA4AQAGAAYJ7Q4WjwA4AQAAAA==.Laylani:BAABLgAECn8bAAIHAAkJpg/VEACeAQAHAAkJpg/VEACeAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIXAAkJ8Rc7LgBEAgAXAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8bAAIfAAkJnxUrAgAyAgAfAAkJnxUrAgAyAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECggJHAAEAHgSAA==.Lotuss:BAAALgAECgYJDgABLgAECgkJOAANAH8cAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8dAAIgAAkJuBBeFwCQAQAgAAkJuBBeFwCQAQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8aAAIEAAgJVgrCMgA1AQAEAAgJVgrCMgA1AQAAAA==.Massack:BAABLgAECn8hAAIhAAgJshUqGQDLAQAhAAgJshUqGQDLAQAAAA==.Mastik:BAAALgAECgEJAQAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAKAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8hAAIOAAgJJBjpGADTAQAOAAgJJBjpGADTAQAAAA==.',
My='Myroslava:BAAALgADCgkJEwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCAAaAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8UAAIKAAcJsx9OFwA3AgAKAAcJsx9OFwA3AgAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8IAAIiAAQJIRt1DgB0AQAiAAQJIRt1DgB0AQAuAAQKfyIABCMACQntHVUGANkBACMABglmGlUGANkBACQABQnNHUUIALEBACIABgkgFYkiAGYBAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAWAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAMAG8TAA==.Nytemayer:BAACLgAFFH8HAAIMAAMJbxNYZgDeAAAMAAMJbxNYZgDeAAAuAAQKfysABAwACQmIIO4WAI8CAAwACQl+H+4WAI8CAB0AAwmYH4szAOkAAB4AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn8rAAICAAgJ8RKxDwCYAQACAAgJ8RKxDwCYAQAAAA==.Oboñ:BAABLgAECn8gAAMeAAgJzw/XCgCPAQAeAAgJzw/XCgCPAQAMAAEJYwNARwEfAAAAAA==.Obsfuyung:BAABLgAECn8qAAIOAAgJlhNSIQCOAQAOAAgJlhNSIQCOAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Or='Orcc:BAAALgADCgkJFAAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAaAAAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxaONQAVAgABAAkJiBOONQAVAgAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8hAAQKAAgJFxs4FgBCAgAKAAgJFxs4FgBCAgAGAAEJ2wEopAEUAAAHAAEJAACpWAAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8dAAMdAAkJqhGSBwC8AQAdAAkJqhGSBwC8AQAMAAEJNgHfTAENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.',
Py='Pyrokos:BAACLgAFFH8FAAIWAAMJUBnDbADoAAAWAAMJUBnDbADoAAAuAAQKfyEAAhYACAnsIDliABUCABYACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMlAAkJkiFvCgApAgAlAAkJkiFvCgApAgAZAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8QAAIKAAUJuhn7EQCEAQAKAAUJuhn7EQCEAQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIZAAgJ7BCbOQBKAQAZAAgJ7BCbOQBKAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIWAAQJ4xk/QwBGAQAWAAQJ4xk/QwBGAQAuAAQKfygAAhYACQlDJecHACsDABYACQlDJecHACsDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8UAAIGAAUJOBMKLwA2AQAGAAUJOBMKLwA2AQAuAAQKfy0AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR4eSAACAQAGAAMJVR4eSAACAQAuAAQKfywAAgYACQkGIuIPANECAAYACQkGIuIPANECAAAA.',
Sa='Sabaak:BAABLgAECn8jAAIGAAgJDB5cIQBqAgAGAAgJDB5cIQBqAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn8nAAIMAAgJFw5PXQB8AQAMAAgJFw5PXQB8AQAAAA==.Saintsnyder:BAABLgAECn8cAAIGAAYJ5xPAjwA3AQAGAAYJ5xPAjwA3AQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBB5ZwDsAAADAAYJmBB5ZwDsAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJBgABLgAECgYJBwAaAAAAAA==.Sanorasong:BAEBLgAECn8bAAMKAAkJ7BeEFABUAgAKAAkJ7BeEFABUAgAGAAUJQQ1H2ADJAAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgcJCwAAAA==.Sarylin:BAABLgAECn8UAAMQAAgJyRskIwBAAgAQAAgJyRskIwBAAgARAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn8rAAIdAAgJ9hS1BwC5AQAdAAgJ9hS1BwC5AQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgcJEAAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAABLgAECn8hAAMMAAgJDQpjbQBVAQAMAAgJ/gljbQBVAQAdAAEJ6grxOwAqAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx4BMwD1AAALAAMJKx4BMwD1AAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgrgOwApAQANAAgJLgrgOwApAQAFAAMJ2wMvLQBaAAAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEAAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8aAAIkAAkJTBUTBQAdAgAkAAkJTBUTBQAdAgAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgIJAwABLgAECgkJHQAXALggAA==.Skarletflame:BAABLgAECn8VAAIYAAkJGBYlEAAFAgAYAAkJGBYlEAAFAgAAAA==.',
Sl='Slather:BAABLgAECn8aAAIUAAgJcBAKGADVAQAUAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIWAAgJtBCCaACSAQAWAAgJtBCCaACSAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAAALgAECgYJCwAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJGwAKAOwXAA==.Sorne:BAABLgAFFH8GAAILAAUJbROOIgA6AQALAAUJbROOIgA6AQABLgAFFAMJDAALAH8kAA==.',
Sp='Spaghett:BAABLgAECn8fAAMhAAkJRBTQIwB7AQAhAAkJphHQIwB7AQAOAAYJJhNXPQDxAAAAAA==.Springtotem:BAABLgAECn8cAAIEAAgJeBJQKQBsAQAEAAgJeBJQKQBsAQAAAA==.',
St='Stachel:BAAALgAECgQJBQAAAA==.Stanger:BAABLgAECn8bAAILAAgJ5xfeGwBSAgALAAgJ5xfeGwBSAgAAAA==.Storaxota:BAAALgAFFAcJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAECgkJOAANAH8cAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AspPACRAQADAAkJ6AspPACRAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIYAAgJshTEHABzAQAYAAgJshTEHABzAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIZAAkJzR9gCQC5AgAZAAkJzR9gCQC5AgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8SAAImAAQJ9xJbHgAlAQAmAAQJ9xJbHgAlAQAuAAQKfyoAAyYACAnuGWgVAPwBACYACAnuGWgVAPwBAAkAAQkFFq57ADoAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwjcbwDTAAADAAcJTwjcbwDTAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAABLgAECn84AAMNAAkJfxw9DACMAgANAAkJfxw9DACMAgALAAIJvgitswBEAAAAAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8hAAIQAAgJjQqZXwBvAQAQAAgJjQqZXwBvAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAABLgAECn8YAAIGAAcJPx03MgBZAgAGAAcJPx03MgBZAgAAAA==.Thundertoes:BAABLgAECn8hAAMLAAgJMR2uEgCfAgALAAgJMR2uEgCfAgAFAAYJChK6GgAEAQAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgIJBQABLgAECgYJDgAaAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8hAAMLAAcJ2RQ4OACzAQALAAcJ2RQ4OACzAQANAAYJWw6ASAD2AAAAAA==.Torgoth:BAABLgAECn8dAAIFAAkJ2hHPCwDZAQAFAAkJ2hHPCwDZAQAAAA==.Toshido:BAABLgAECn8VAAIQAAYJWhBcjQAKAQAQAAYJWhBcjQAKAQAAAA==.',
Tr='Traetor:BAABLgAECn8hAAIEAAgJ5yV2BAAKAwAEAAgJ5yV2BAAKAwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8WAAIGAAYJ1wdL0wDQAAAGAAYJ1wdL0wDQAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAABLgAECn8cAAILAAcJlww4UgBLAQALAAcJlww4UgBLAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAAALgAECggJEAAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJEQAXANQUAA==.Valiantaint:BAACLgAFFH8RAAIXAAQJ1BTvNgAkAQAXAAQJ1BTvNgAkAQAuAAQKfyoAAhcACQkHHocaAGECABcACQkHHocaAGECAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJEQAXANQUAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJEQAXANQUAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8bAAIGAAgJMiDyHQB6AgAGAAgJMiDyHQB6AgAAAA==.Vendeldh:BAABLgAECn8sAAIXAAkJuCPUEgDpAgAXAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8bAAIQAAkJ5wxIQwDAAQAQAAkJ5wxIQwDAAQAAAA==.',
Vi='Virajr:BAABLgAECn8eAAMiAAgJ5g+RGgCqAQAiAAgJ5g+RGgCqAQAjAAEJvAQfJAAhAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIZAAkJ8wdYOQBLAQAZAAkJ8wdYOQBLAQAAAA==.Vissiction:BAABLgAECn8XAAIXAAgJ4xMfRQCgAQAXAAgJ4xMfRQCgAQAAAA==.Vistine:BAABLgAECn8wAAIHAAkJBws/GgAtAQAHAAkJBws/GgAtAQAAAA==.Vitez:BAABLgAECn8WAAMdAAkJrAZ+GQDEAAAdAAgJFAd+GQDEAAAMAAIJRAMcBgFOAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8gAAIWAAYJBw7QswD/AAAWAAYJBw7QswD/AAAAAA==.Wendy:BAABLgAECn8iAAILAAgJuhjiMADWAQALAAgJuhjiMADWAQABLgAECgkJGgADABgTAA==.',
Wi='Win:BAAALgAECgcJEQABLgAECgkJNgAMANEYAA==.Winkster:BAACLgAFFH8MAAIGAAUJWRx8JgBNAQAGAAUJWRx8JgBNAQAuAAQKfzAAAgYACQn4JMkHABoDAAYACQn4JMkHABoDAAAA.',
Xa='Xanadu:BAABLgAECn8xAAImAAkJFx77BQALAwAmAAkJFx77BQALAwAAAA==.Xarinia:BAABLgAECn8jAAMVAAkJDRInGgDrAQAVAAkJDRInGgDrAQAUAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8gAAIcAAkJ1xpeBwBjAgAcAAkJ1xpeBwBjAgABLgAFFAUJEwAiAO4YAA==.',
Xd='Xdynasty:BAACLgAFFH8TAAIiAAUJ7hhuFgBAAQAiAAUJ7hhuFgBAAQAuAAQKfycAAyIACQkCJCwMANUCACIACQn/IywMANUCACQABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn82AAQMAAkJ0RjUSQCxAQAMAAkJJRXUSQCxAQAdAAUJGBR5JQAxAQAeAAIJVgtDMAA9AAAAAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8oAAMLAAkJzhBfNQDAAQALAAkJzhBfNQDAAQANAAQJqgYudgBoAAAAAA==.Zabenir:BAABLgAECn8YAAIIAAkJsBoDEQAzAgAIAAkJsBoDEQAzAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
['Ðe']='Ðexter:BAAALgAECgYJEwAAAA==.',
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
