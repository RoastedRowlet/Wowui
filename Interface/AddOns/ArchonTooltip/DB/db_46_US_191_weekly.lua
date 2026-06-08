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
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-06-06',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR92ggDwAAABAAMJqR92ggDwAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUpDADeAAACAAMJwBUpDADeAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB2jMADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn82AAIFAAkJaiKeAQAUAwAFAAkJaiKeAQAUAwAAAA==.Aeón:BAAALgAECggJDgAAAA==.',
Ag='Aggen:BAABLgAECn8jAAMGAAkJWxrcJABnAgAGAAkJWxrcJABnAgAHAAEJAABKXQAAAAAAAA==.',
Aj='Aja:BAAALgADCgEJAQAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJcibiAACQAwABAAkJcibiAACQAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwoZHQD0AAAIAAQJGwoZHQD0AAAJAAIJbQQKLABYAAAuAAQKfyoAAwgACAnLGHgcANoBAAgACAnLGHgcANoBAAkABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgEJAQAAAA==.Alandarus:BAAALgAECgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8iAAIGAAgJ3xpENAAlAgAGAAgJ3xpENAAlAgAAAA==.Allenwalker:BAAALgAECgUJCAAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJHwAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8aAAIDAAkJGBNFIwAmAgADAAkJGBNFIwAmAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAECgkJHwAMAEMZAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMNAAgJygt5PgAqAQANAAgJygt5PgAqAQALAAQJEgLcqABkAAAAAA==.',
Ao='Aoi:BAABLgAECn8tAAMOAAgJyxFMIgCRAQAOAAgJyxFMIgCRAQAPAAgJ5gupQgBIAQAAAA==.',
Ar='Arrisia:BAABLgAECn8vAAMQAAgJpBE2SwC0AQAQAAgJpBE2SwC0AQARAAIJJwS+NQA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8QAAISAAQJiSGWCQB8AQASAAQJiSGWCQB8AQAuAAQKfzIAAhIACQnSI30BAHIDABIACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8YAAITAAQJWiCrCQBsAQATAAQJWiCrCQBsAQAuAAQKfzEAAhMACQnKI/wDAO8CABMACQnKI/wDAO8CAAEuAAUUBAkQABIAiSEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgkJHwAEAAESAA==.Autumni:BAABLgAECn8fAAIQAAcJsRjuVgCSAQAQAAcJsRjuVgCSAQAAAA==.Auvry:BAABLgAECn8aAAMUAAcJVhkdEAA5AgAUAAcJVhkdEAA5AgAVAAIJqAkFkQAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJKwAWAEkIAA==.',
Ay='Aymus:BAABLgAECn8VAAMXAAYJtQJV3gBmAAAXAAYJbgJV3gBmAAAYAAMJzAHpdwAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8gAAIGAAkJDwjDgwBcAQAGAAkJDwjDgwBcAQAAAA==.Bakala:BAABLgAECn8xAAMSAAgJbRJ0HABGAQASAAgJYw10HABGAQAZAAYJWRSKRwAeAQAAAA==.Bangbang:BAABLgAECn8qAAIQAAkJqBUfRgDDAQAQAAkJqBUfRgDDAQAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIKAAkJhw+AJwDEAQAKAAkJhw+AJwDEAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAaAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIRAAMJHwv0GwC2AAARAAMJHwv0GwC2AAAuAAQKfx4AAhEACQnSE3kqANgBABEACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIXAAkJDg9ARgCoAQAXAAkJDg9ARgCoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wrVFQBSAQAFAAgJ5wrVFQBSAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8nAAIJAAgJThfOFAAiAgAJAAgJThfOFAAiAgAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAABLgAECn87AAMSAAkJRhxLCABrAgASAAkJRhxLCABrAgAZAAMJpAakiABSAAAAAA==.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8cAAIbAAkJUQrGDgB4AQAbAAkJUQrGDgB4AQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgIJAwAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMQAAkJ0h3OHQBoAgAQAAkJ0h3OHQBoAgARAAYJyRNKFgD4AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMJAAkJlhQZHwC8AQAJAAcJ+hYZHwC8AQAIAAcJ9RAYLgBhAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBajDgC5AQACAAYJVxijDgC5AQADAAgJdgkjYAALAQAEAAYJSgwnRgDlAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8oAAIFAAgJLSBQBgBoAgAFAAgJLSBQBgBoAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxQPDgCOAAAHAAMJ7QoPDgCOAAAGAAIJ9xNRjACFAAAuAAQKfygABAYACQmiIJYYAKYCAAYACAmyIpYYAKYCAAcABAnRE2w0AIMAAAoAAwnuBJRyAGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAECgQJCAAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAfpTwDGAAAIAAcJdAfpTwDGAAAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9AAAMCAAgJWiOaAwDMAgACAAgJQyOaAwDMAgAcAAgJSxwvCgAxAgABLgAECgkJNgAFAGoiAA==.Crunky:BAABLgAECn8wAAIPAAgJ9hXVHwAIAgAPAAgJ9hXVHwAIAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIWAAkJNh5sMgCpAgAWAAkJNh5sMgCpAgAAAA==.',
Da='Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAABLgAECn8dAAIXAAkJuCCEEQCtAgAXAAkJuCCEEQCtAgAAAA==.Dameond:BAAALgAECgUJCAAAAA==.David:BAAALgADCgQJBAABLgAECgcJAQAaAAAAAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAaAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8GAAMLAAMJfSCmLgAQAQALAAMJfSCmLgAQAQAFAAMJbwNQDwCtAAAuAAQKfx4AAwsABwltIRAWAI0CAAsABwltIRAWAI0CAAUAAwl4EKcoAJoAAAAA.Demonicteli:BAABLgAECn8WAAIYAAkJlxmZEABdAgAYAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDQAAAA==.Dermot:BAABLgAECn8tAAQdAAgJLiN0AwC6AgAdAAcJZCJ0AwC6AgAMAAUJ+iBydQBKAQAeAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBHWKwBpAQAEAAgJLBHWKwBpAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8YAAIGAAgJexNwXQCsAQAGAAgJexNwXQCsAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn82AAIGAAcJjA1enQAwAQAGAAcJjA1enQAwAQAAAA==.Domaon:BAABLgAECn8vAAIYAAkJrCFVBAD6AgAYAAkJrCFVBAD6AgAAAA==.Domshammy:BAAALgAECggJDQABLgAECgkJLwAYAKwhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAQAOEXAA==.Doubt:BAABLgAECn8ZAAIIAAgJiwnzMgBGAQAIAAgJiwnzMgBGAQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgcJDwAAAA==.Dunigan:BAABLgAECn80AAMGAAgJThGAdwB0AQAGAAgJTRCAdwB0AQAHAAYJDg/GJADhAAAAAA==.Dunigen:BAAALgAECgcJCgAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8+AAITAAkJcxjCCwBhAgATAAkJcxjCCwBhAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgAECgkJCQAAAA==.',
Fa='Facade:BAAALgAECgcJEgAAAA==.Facepalm:BAABLgAECn8fAAIZAAkJdxMiHQD/AQAZAAkJdxMiHQD/AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAaAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8ZAAIDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQABLgAECggJHgAUAHcQAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8cAAIbAAgJwgtUEwA1AQAbAAgJwgtUEwA1AQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCAAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxkGKgAGAgALAAcJcxkGKgAGAgANAAEJgRz5hwBRAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9CAAILAAkJ0Rc4IABBAgALAAkJ0Rc4IABBAgAAAA==.Foxmccloud:BAABLgAECn8pAAMLAAgJmhqOGwBiAgALAAgJmhqOGwBiAgANAAQJlQRLjgBHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIWAAkJMB9pFgDMAgAWAAkJMB9pFgDMAgAAAA==.',
Fu='Fuil:BAAALgAECgQJBgAAAA==.Furgaler:BAAALgAECgUJCQABLgAECgkJHQAXALggAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn84AAIZAAcJBCG4FABEAgAZAAcJBCG4FABEAgAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8fAAIUAAkJtxf/BgCFAgAUAAkJtxf/BgCFAgAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwABLgAECggJDQAaAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn8wAAIcAAgJIRgvDwDgAQAcAAgJIRgvDwDgAQAAAA==.',
Gy='Gyre:BAABLgAECn8dAAIQAAcJ6hCSZABuAQAQAAcJ6hCSZABuAQAAAA==.',
Ha='Haezi:BAAALgAECgcJDAAAAA==.Happyendings:BAAALgAECgcJDQAAAA==.',
He='Helbafx:BAAALgAECgYJDAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8XAAISAAYJyxYGJAADAQASAAYJyxYGJAADAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgIJAgAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAAALgAECgYJCgAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMNAAkJggopNwBMAQANAAkJggopNwBMAQALAAIJZwgHvABGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwsLMwDdAAADAAQJTwsLMwDdAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAABLgAECn8rAAILAAkJhxtADADtAgALAAkJhxtADADtAgAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g5/IQCXAQAOAAkJ4g5/IQCXAQAAAA==.Jaycie:BAAALgAECggJDQAAAA==.',
Je='Jessuss:BAABLgAECn8iAAIGAAgJPhKbaACTAQAGAAgJPhKbaACTAQAAAA==.',
Jh='Jha:BAAALgADCgYJBgAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQNgSACQAAADAAMJqQNgSACQAAAuAAQKfyoAAgMACQnTEG4zAMYBAAMACQnTEG4zAMYBAAAA.Kalebeesd:BAABLgAECn8kAAIXAAgJ5Bj6LgD/AQAXAAgJ5Bj6LgD/AQAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAaAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRS+NQC5AQADAAgJPRS+NQC5AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAINAAQJbCJ9EACJAQANAAQJbCJ9EACJAQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kebob:BAABLgAECn8VAAIHAAkJ3g+yFgBgAQAHAAkJ3g+yFgBgAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAISAAgJ5BwFDQAPAgASAAgJ5BwFDQAPAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIWAAUJJgURMwDRAAAWAAUJJgURMwDRAAAuAAQKfyMAAhYACAmWF0BKAFgCABYACAmWF0BKAFgCAAAA.Kittylover:BAAALgADCgcJCgAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMRcQHwDjAAAIAAMJMRcQHwDjAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8eAAIZAAcJXhw0HwDvAQAZAAcJXhw0HwDvAQAAAA==.Korllan:BAAALgAECgEJAQAAAA==.Kossnen:BAAALgAECgcJEgAAAA==.',
Kr='Krelivus:BAAALgAECgUJBgAAAA==.',
Ku='Kuda:BAABLgAECn8mAAIWAAkJuRPBPwAXAgAWAAkJuRPBPwAXAgAAAA==.',
Kw='Kwanu:BAABLgAECn8XAAIPAAgJFw3MPgBZAQAPAAgJFw3MPgBZAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECggJDgAaAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwABLgAECgYJCQAaAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBCpiABTAQAGAAYJgBCpiABTAQAAAA==.Laylani:BAABLgAECn8bAAIHAAkJpg8WEgCZAQAHAAkJpg8WEgCZAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIXAAkJ8Rc7LgBEAgAXAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgMJBgAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIfAAkJ4RYBAgBRAgAfAAkJ4RYBAgBRAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgkJHwAEAAESAA==.Lotuss:BAAALgAECgYJDgABLgAFFAIJBQANAPoJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8hAAIgAAkJKxHFFQCyAQAgAAkJKxHFFQCyAQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgrOMABMAQAEAAkJCgrOMABMAQAAAA==.Massack:BAABLgAECn8jAAIhAAkJ9xeODwA6AgAhAAkJ9xeODwA6AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAKAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECgEJAQABLgAECgkJGgADABgTAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIOAAkJYhhmEgAhAgAOAAkJYhhmEgAhAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCAAaAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8fAAIKAAgJlSGUCQDnAgAKAAgJlSGUCQDnAgAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8LAAMiAAQJiRyWEQBrAQAiAAQJIRuWEQBrAQAjAAMJoRf5BwDuAAAuAAQKfyMABCMACQntHasGANgBACMABglmGqsGANgBACQABQnNHcQIALABACIABgkgFXokAGIBAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAWAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAMAG8TAA==.Nytemayer:BAACLgAFFH8HAAIMAAMJbxN/bwDUAAAMAAMJbxN/bwDUAAAuAAQKfysABAwACQmIIJEYAIsCAAwACQl+H5EYAIsCAB0AAwmYH4szAOkAAB4AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn8wAAICAAgJSBQrDwCyAQACAAgJSBQrDwCyAQAAAA==.Obonhigh:BAAALgADCgEJAQAAAA==.Oboñ:BAABLgAECn8lAAMeAAgJzw/0CwCMAQAeAAgJzw/0CwCMAQAMAAEJYwP/UwEeAAAAAA==.Obsfuyung:BAABLgAECn8rAAIOAAgJkRTVIQCVAQAOAAgJkRTVIQCVAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Or='Orcc:BAAALgADCgkJFgAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAaAAAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxYHOQAUAgABAAkJiBMHOQAUAgAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8pAAQKAAgJrBvPFQBTAgAKAAgJrBvPFQBTAgAGAAEJ2wHhuQEUAAAHAAEJAAByXQAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8hAAMdAAkJ5xNyBgDsAQAdAAkJ5xNyBgDsAQAMAAEJNgGoWQENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.',
Py='Pyrokos:BAACLgAFFH8FAAIWAAMJUBnDdQDlAAAWAAMJUBnDdQDlAAAuAAQKfyEAAhYACAnsIDliABUCABYACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMlAAkJkiFvBgBlAgAlAAkJkiFvBgBlAgAZAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8UAAIKAAUJuhm5FAB3AQAKAAUJuhm5FAB3AQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIZAAgJ7BCwPABKAQAZAAgJ7BCwPABKAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIWAAQJ4xnkTQA+AQAWAAQJ4xnkTQA+AQAuAAQKfygAAhYACQlDJfIIAC8DABYACQlDJfIIAC8DAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8UAAIGAAUJOBN1OAArAQAGAAUJOBN1OAArAQAuAAQKfy4AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR6iUQD6AAAGAAMJVR6iUQD6AAAuAAQKfywAAgYACQkGItsRANACAAYACQkGItsRANACAAAA.',
Sa='Sabaak:BAABLgAECn8nAAIGAAgJDB5cJABpAgAGAAgJDB5cJABpAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn8tAAIMAAkJVg46SgC3AQAMAAkJVg46SgC3AQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xMpmgA1AQAGAAYJ5xMpmgA1AQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBAjawDpAAADAAYJmBAjawDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJCQAAAA==.Sanorasong:BAEBLgAECn8fAAMKAAkJ7BcZFgBQAgAKAAkJ7BcZFgBQAgAGAAUJPhQmvQAAAQAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8UAAMQAAgJyRuMJgA6AgAQAAgJyRuMJgA6AgARAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn8wAAIdAAgJZxXFBwDHAQAdAAgJZxXFBwDHAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgcJEAAAAA==.Sections:BAAALgADCgkJHAAAAA==.Severussnape:BAABLgAECn8jAAMMAAkJqQluXACFAQAMAAkJnAluXACFAQAdAAEJ6gpDPwApAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx7LNwDsAAALAAMJKx7LNwDsAAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgp+QAAiAQANAAgJLgp+QAAiAQAFAAMJ2wMwMQBaAAAAAA==.Shinron:BAAALgADCgYJDwAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEAAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8aAAIkAAkJTBVsBQAaAgAkAAkJTBVsBQAaAgAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgIJBAABLgAECgkJHQAXALggAA==.Skarletflame:BAABLgAECn8ZAAIYAAkJnRgKDABWAgAYAAkJnRgKDABWAgAAAA==.',
Sl='Slather:BAABLgAECn8aAAIUAAgJcBAKGADVAQAUAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIWAAgJtBAbbwCWAQAWAAgJtBAbbwCWAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAAALgAECgYJEAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJHwAKAOwXAA==.Sorne:BAABLgAFFH8GAAILAAUJbRO/JwAuAQALAAUJbRO/JwAuAQABLgAFFAMJDwALAGwlAA==.',
Sp='Spaghett:BAABLgAECn8fAAMhAAkJRBRsJQB5AQAhAAkJphFsJQB5AQAOAAYJJhMFQQDtAAAAAA==.Springtotem:BAABLgAECn8fAAIEAAkJARL6IQCsAQAEAAkJARL6IQCsAQAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8cAAILAAkJ9hfhFACYAgALAAkJ9hfhFACYAgAAAA==.Storaxota:BAAALgAFFAcJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAIJBQANAPoJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AtdPgCQAQADAAkJ6AtdPgCQAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIYAAgJshQsHwBuAQAYAAgJshQsHwBuAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIZAAkJzR96CgC1AgAZAAkJzR96CgC1AgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8WAAImAAQJKBMeIgAaAQAmAAQJKBMeIgAaAQAuAAQKfyoAAyYACAnuGWgVAPwBACYACAnuGWgVAPwBAAkAAQkFFq57ADoAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwgrdADPAAADAAcJTwgrdADPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAACLgAFFH8FAAINAAIJ+gl5QAB4AAANAAIJ+gl5QAB4AAAuAAQKf0YAAw0ACQmZHOoMAI0CAA0ACQmZHOoMAI0CAAsAAgm+CGC9AEQAAAAA.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIQAAkJRgoITwCpAQAQAAkJRgoITwCpAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAABLgAECn8YAAIGAAcJPx03MgBZAgAGAAcJPx03MgBZAgAAAA==.Thundertoes:BAABLgAECn8jAAMLAAkJexxfDQDgAgALAAkJexxfDQDgAgAFAAYJChLlHAAEAQAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAABLgAECgYJDgAaAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8oAAMLAAcJ2RSZOwCyAQALAAcJ2RSZOwCyAQANAAYJwA5zSwD3AAAAAA==.Torgoth:BAABLgAECn8hAAIFAAkJSxR0CQAZAgAFAAkJSxR0CQAZAgAAAA==.Toshido:BAABLgAECn8VAAIQAAYJWhBUlgAFAQAQAAYJWhBUlgAFAQAAAA==.',
Tr='Traetor:BAABLgAECn8jAAIEAAkJDibfAAB+AwAEAAkJDibfAAB+AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8WAAIGAAYJ1wdR2wDXAAAGAAYJ1wdR2wDXAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgQJBAAAAA==.',
Ul='Ultane:BAABLgAECn8cAAILAAcJlwzzVgBKAQALAAcJlwzzVgBKAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8UAAIQAAgJRQsabwBWAQAQAAgJRQsabwBWAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJFQAXANAcAA==.Valiantaint:BAACLgAFFH8VAAIXAAQJ0BykLQBXAQAXAAQJ0BykLQBXAQAuAAQKfyoAAhcACQkHHo8cAF8CABcACQkHHo8cAF8CAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJFQAXANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJFQAXANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh/DEgDKAgAGAAkJYh/DEgDKAgAAAA==.Vendeldh:BAABLgAECn8sAAIXAAkJuCPUEgDpAgAXAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8fAAIQAAkJRxCiOgDpAQAQAAkJRxCiOgDpAQAAAA==.',
Vi='Virajr:BAABLgAECn8jAAMiAAgJdxJeGQDAAQAiAAgJdxJeGQDAAQAjAAEJvASmJgAhAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIZAAkJ8wdwPABLAQAZAAkJ8wdwPABLAQAAAA==.Vissiction:BAABLgAECn8ZAAIXAAkJvxZgKwAPAgAXAAkJvxZgKwAPAgAAAA==.Vistine:BAABLgAECn8+AAIHAAkJBwvpGwAqAQAHAAkJBwvpGwAqAQAAAA==.Vitez:BAABLgAECn8WAAMdAAkJrAYuGwDCAAAdAAgJFAcuGwDCAAAMAAIJRAO6DwFOAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIWAAcJUQyHoAA1AQAWAAcJUQyHoAA1AQAAAA==.Wendy:BAABLgAECn8pAAILAAgJ1Rj5MwDUAQALAAgJ1Rj5MwDUAQABLgAECgkJGgADABgTAA==.',
Wi='Win:BAABLgAECn8cAAMDAAcJ4xrbIwAiAgADAAcJ4xrbIwAiAgAEAAQJIhNmVACvAAAAAA==.Winkster:BAACLgAFFH8MAAIGAAUJWRzJLwBAAQAGAAUJWRzJLwBAAQAuAAQKfzAAAgYACQn4JBUJABgDAAYACQn4JBUJABgDAAAA.',
Xa='Xanadu:BAABLgAECn84AAImAAkJTB4lBgAWAwAmAAkJTB4lBgAWAwAAAA==.Xarinia:BAABLgAECn8qAAMVAAkJDRLoGwDvAQAVAAkJDRLoGwDvAQAUAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8kAAIcAAkJhxtKBwBzAgAcAAkJhxtKBwBzAgABLgAFFAYJFQAiACgXAA==.',
Xd='Xdynasty:BAACLgAFFH8VAAIiAAYJKBedDQCXAQAiAAYJKBedDQCXAQAuAAQKfycAAyIACQkCJCwMANUCACIACQn/IywMANUCACQABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn82AAQMAAkJ0Ri9TACvAQAMAAkJJRW9TACvAQAdAAUJGBR5JQAxAQAeAAIJVgtDMAA9AAABLgAECgcJHAADAOMaAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAABLgAECn8oAAMLAAkJzhDfOAC+AQALAAkJzhDfOAC+AQANAAQJqgZnfABoAAAAAA==.Zabenir:BAABLgAECn8cAAIIAAkJURxKCwCVAgAIAAkJURxKCwCVAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
['Ðe']='Ðexter:BAABLgAECn8YAAIGAAYJ8wX96QDFAAAGAAYJ8wX96QDFAAAAAA==.',
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
