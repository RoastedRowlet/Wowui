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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Evoker-Devastation','Monk-Brewmaster','Rogue-Subtlety','Warrior-Arms','Mage-Arcane','Rogue-Outlaw','Rogue-Assassination','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-06-20',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR+gkQDoAAABAAMJqR+gkQDoAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBUIDgDZAAACAAMJwBUIDgDZAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB23TADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn8+AAIFAAkJ+CJYAQArAwAFAAkJ+CJYAQArAwAAAA==.Aeón:BAAALgAECgkJDwAAAA==.',
Ag='Aggèn:BAABLgAECn8qAAMGAAkJJR2VGwCeAgAGAAkJJR2VGwCeAgAHAAMJSAoNQwBVAAAAAA==.',
Aj='Aja:BAAALgAECgIJAgAAAA==.',
Ak='Akashá:BAAALgAECgEJAgAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJciY0AQCLAwABAAkJciY0AQCLAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwo4IADyAAAIAAQJGwo4IADyAAAJAAIJbQTcMABVAAAuAAQKfy0AAwgACAnbGEUdANsBAAgACAnbGEUdANsBAAkABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgMJBQAAAA==.Alandarus:BAAALgAECgEJAgAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8nAAIGAAgJ4Bu7MQA5AgAGAAgJ4Bu7MQA5AgAAAA==.Allenwalker:BAAALgAECgUJCAAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJIAAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8aAAIDAAkJGBMeJQAjAgADAAkJGBMeJQAjAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAFFAQJCAAMAMgeAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMNAAgJygtvQgApAQANAAgJygtvQgApAQALAAQJEgLzswBiAAAAAA==.',
Ao='Aoi:BAABLgAECn8yAAMOAAgJxBIxIgCeAQAOAAgJxBIxIgCeAQAPAAgJ5gtsSABKAQAAAA==.',
Ar='Arrisia:BAABLgAECn8yAAMMAAgJKRJ/TgC3AQAMAAgJKRJ/TgC3AQAQAAIJJwShOAA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8UAAIRAAQJiSGGAQANAQARAAQJiSGGAQANAQAuAAQKfzIAAhEACQnSI30BAHIDABEACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8gAAISAAQJWiAuCwBtAQASAAQJWiAuCwBtAQAuAAQKfzEAAhIACQnKI3AEAOcCABIACQnKI3AEAOcCAAEuAAUUBAkUABEAiSEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECggJDgABLgAECgkJHwAEAAESAA==.Autumni:BAABLgAECn8fAAIMAAcJsRhqXgCLAQAMAAcJsRhqXgCLAQAAAA==.Auvry:BAABLgAECn8aAAMTAAcJVhkdEAA5AgATAAcJVhkdEAA5AgAUAAIJqAlWmQAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJKwAVAEkIAA==.',
Ay='Aymus:BAABLgAECn8XAAQWAAYJ6gISAgA9AAAXAAYJbgKY6gBmAAAWAAIJyAMSAgA9AAAYAAMJzAFaggAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8mAAMGAAkJDwhajABYAQAGAAkJDwhajABYAQAHAAUJzATLOwBtAAAAAA==.Bakala:BAABLgAECn83AAMZAAgJEBUKLwCTAQAZAAgJTBMKLwCTAQARAAgJYw1AHgBCAQAAAA==.Bangbang:BAABLgAECn8qAAIMAAkJqBV7TAC8AQAMAAkJqBV7TAC8AQAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIKAAkJhw+HKQDBAQAKAAkJhw+HKQDBAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAaAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIQAAMJHwsPIACrAAAQAAMJHwsPIACrAAAuAAQKfx4AAhAACQnSE3kqANgBABAACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIXAAkJDg/2SQCoAQAXAAkJDg/2SQCoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wrcFwBKAQAFAAgJ5wrcFwBKAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn84AAIJAAkJ+RgAAQBlAQAJAAkJ+RgAAQBlAQAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAACLgAFFH8FAAIRAAIJ8xOOAwB9AAARAAIJ8xOOAwB9AAAuAAQKfzsAAxEACQlGHCkJAGQCABEACQlGHCkJAGQCABkAAwmkBkqQAFEAAAAA.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8iAAIbAAkJ2gvQDgCIAQAbAAkJ2gvQDgCIAQAAAA==.Borkuz:BAAALgAECgEJAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brettdadad:BAAALgAECgIJAwAAAA==.Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgMJBAAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMMAAkJ0h3XIABjAgAMAAkJ0h3XIABjAgAQAAYJyROxFwD1AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMJAAkJlhQFIQC6AQAJAAcJ+hYFIQC6AQAIAAcJ9RDfMQBUAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBbgDwC4AQACAAYJVxjgDwC4AQADAAgJdgk6YwALAQAEAAYJSgzkSQDkAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8pAAIFAAkJIyCuAwDEAgAFAAkJIyCuAwDEAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxSfDwCJAAAHAAMJ7QqfDwCJAAAGAAIJ9xNCmgCFAAAuAAQKfygABAYACQmiIEcbAKACAAYACAmyIkcbAKACAAcABAnRE2g3AIIAAAoAAwnuBPl2AGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAABLgAFFH8FAAIBAAMJnwiWuQC1AAABAAMJnwiWuQC1AAAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAdKOgAfAQAIAAcJdAdKOgAfAQAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9CAAMCAAgJWiP5AwDJAgACAAgJQyP5AwDJAgAcAAgJSxw4CwAvAgABLgAECgkJPgAFAPgiAA==.Crunky:BAABLgAECn8wAAIPAAgJ9hW1IgAJAgAPAAgJ9hW1IgAJAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIVAAkJNh5sMgCpAgAVAAkJNh5sMgCpAgAAAA==.',
Da='Daddywoof:BAAALgADCgYJBgAAAA==.Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAABLgAECn8dAAIXAAkJuCC6EgCtAgAXAAkJuCC6EgCtAgAAAA==.Dameond:BAAALgAECgUJCwAAAA==.David:BAAALgADCgQJBAAAAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAaAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8HAAMLAAMJfSC0NQALAQALAAMJfSC0NQALAQAFAAMJbwNIEgCjAAAuAAQKfx4AAwsABwltIc8XAIsCAAsABwltIc8XAIsCAAUAAwl4EMIsAJMAAAAA.Demonicteli:BAABLgAECn8WAAIYAAkJlxmZEABdAgAYAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDQAAAA==.Dermot:BAABLgAECn8wAAQdAAgJLiN0AwC6AgAdAAcJZCJ0AwC6AgAeAAYJ+iBqeQBGAQAfAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBFfLgBoAQAEAAgJLBFfLgBoAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8YAAIGAAgJexPmYwCoAQAGAAgJexPmYwCoAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Dl='Dlekri:BAAALgAECggJCAABLgAECgkJLAAbAGQcAA==.',
Do='Dolemen:BAABLgAECn8+AAIGAAgJUQ0GgwBpAQAGAAgJUQ0GgwBpAQAAAA==.Domaon:BAABLgAECn8wAAIYAAkJ+SFiBAADAwAYAAkJ+SFiBAADAwAAAA==.Domshammy:BAAALgAECggJDQABLgAECgkJMAAYAPkhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAMAOEXAA==.Doubt:BAABLgAECn8bAAIIAAgJWApFNgA9AQAIAAgJWApFNgA9AQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgkJEAAAAA==.Dunigan:BAABLgAECn80AAMGAAgJThHofgBxAQAGAAgJTRDofgBxAQAHAAYJDg+1JgDgAAAAAA==.Dunigen:BAAALgAECgcJCgAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8+AAISAAkJcxjrDABWAgASAAkJcxjrDABWAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ev='Evangelista:BAAALgAECgEJAQAAAA==.',
Ey='Eyeet:BAAALgAECgkJCQAAAA==.',
Fa='Facade:BAABLgAECn8kAAIgAAkJBROtAACKAQAgAAkJBROtAACKAQAAAA==.Facepalm:BAABLgAECn8fAAIZAAkJdxMwHwD1AQAZAAkJdxMwHwD1AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAaAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8dAAMDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQACAAQJyRO2LACzAAABLgAFFAIJBQATAAoHAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8eAAIbAAkJnAvOFQArAQAbAAkJnAvOFQArAQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCQAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxnPLAAFAgALAAcJcxnPLAAFAgANAAEJgRw0kQBQAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9JAAILAAkJdxvpFgCSAgALAAkJdxvpFgCSAgAAAA==.Foxmccloud:BAABLgAECn8uAAMLAAgJVRtaGwBwAgALAAgJVRtaGwBwAgANAAQJlQTFlwBHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIVAAkJMB96GADGAgAVAAkJMB96GADGAgAAAA==.',
Fu='Fuil:BAAALgAECgYJDQAAAA==.Furgaler:BAAALgAECgUJCQABLgAECgkJHQAXALggAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garidrael:BAAALgAECgEJAQAAAA==.Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn88AAIZAAgJaSBXDQCYAgAZAAgJaSBXDQCYAgAAAA==.Genmaitcha:BAAALgADCgEJAQAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8lAAMTAAkJtxdVBwCDAgATAAkJtxdVBwCDAgAhAAEJCQFdLQAKAAAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Grawn:BAAALgADCgMJAwAAAA==.Greycie:BAAALgADCgkJEwABLgAECggJEgAaAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn81AAIcAAgJGhkhDwDzAQAcAAgJGhkhDwDzAQAAAA==.Grimfu:BAAALgAECgYJCAABLgAECgkJGwAGAEoeAA==.',
Gy='Gyre:BAABLgAECn8dAAIMAAcJ6hBibABoAQAMAAcJ6hBibABoAQAAAA==.',
Ha='Haezi:BAAALgAECggJDQABLgAECgkJHwAiAEQUAA==.Happyendings:BAAALgAFFAIJBAAAAA==.',
He='Helbafx:BAAALgAECgcJEAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8cAAIRAAgJ2RKiGgBkAQARAAgJ2RKiGgBkAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgIJAgAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAABLgAECn8UAAIjAAYJEA2NMAAdAQAjAAYJEA2NMAAdAQAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMNAAkJggrAOgBLAQANAAkJggrAOgBLAQALAAIJZwiVxwBGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwuhOQDHAAADAAQJTwuhOQDHAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAABLgAECn8xAAILAAkJ3x22CAAmAwALAAkJ3x22CAAmAwAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g4UJACSAQAOAAkJ4g4UJACSAQAAAA==.Jaycie:BAAALgAECggJEgAAAA==.',
Je='Jessuss:BAABLgAECn8kAAIGAAgJjROEcACNAQAGAAgJjROEcACNAQAAAA==.',
Jh='Jha:BAAALgAECgEJAQAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQOeTwCDAAADAAMJqQOeTwCDAAAuAAQKfyoAAgMACQnTEIw1AMQBAAMACQnTEIw1AMQBAAAA.Kalebeesd:BAABLgAECn8uAAIXAAgJXBygIgBGAgAXAAgJXBygIgBGAgAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAaAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRTmNwC4AQADAAgJPRTmNwC4AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAINAAQJbCKGFAB7AQANAAQJbCKGFAB7AQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kebob:BAABLgAECn8VAAIHAAkJ3g8fGABdAQAHAAkJ3g8fGABdAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAIRAAgJ5BwkDgAJAgARAAgJ5BwkDgAJAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIVAAUJJgURMwDRAAAVAAUJJgURMwDRAAAuAAQKfyMAAhUACAmWF0BKAFgCABUACAmWF0BKAFgCAAEuAAUUBgkUAAEAxhMA.Kittylover:BAAALgAECgUJBQAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMReIIgDgAAAIAAMJMReIIgDgAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8hAAMZAAgJPh0GFQBHAgAZAAgJsRwGFQBHAgAkAAEJLhjEAwBKAAAAAA==.Korllan:BAAALgAECgQJBwAAAA==.Kossnen:BAABLgAECn8VAAIeAAkJTh3VHgBsAgAeAAkJTh3VHgBsAgAAAA==.',
Kr='Krelivus:BAAALgAECgYJCwAAAA==.',
Ku='Kuda:BAABLgAECn8sAAIVAAkJDxQmQwASAgAVAAkJDxQmQwASAgAAAA==.',
Kw='Kwanu:BAABLgAECn8dAAIPAAgJFw1GRABbAQAPAAgJFw1GRABbAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECgkJDwAaAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwABLgAECgYJDwAaAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBCxkQBPAQAGAAYJgBCxkQBPAQAAAA==.Laylani:BAABLgAECn8iAAIHAAkJ+RGADwDLAQAHAAkJ+RGADwDLAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIXAAkJ8Rc7LgBEAgAXAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgUJCAAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIlAAkJ4RYjAgBMAgAlAAkJ4RYjAgBMAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgkJHwAEAAESAA==.Lotuss:BAABLgAECn8aAAMPAAYJPxiRNwCVAQAPAAYJPxiRNwCVAQAOAAEJNgPXwAAXAAABLgAFFAIJBwANAPoJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8nAAIgAAkJBhKwFQC+AQAgAAkJBhKwFQC+AQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Madness:BAAALgAECgMJAwAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgrbMwBJAQAEAAkJCgrbMwBJAQAAAA==.Massack:BAABLgAECn8jAAIiAAkJ9xegEAA3AgAiAAkJ9xegEAA3AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgADCgYJCAAaAAAAAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECggJCgABLgAECgkJGgADABgTAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIOAAkJYhiaEwAfAgAOAAkJYhiaEwAfAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCAAaAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8mAAIKAAgJ/SM2BgAqAwAKAAgJ/SM2BgAqAwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8NAAMjAAQJiRwhFQBiAQAjAAQJIRshFQBiAQAmAAMJoRfsCADsAAAuAAQKfyMABCYACQntHe4GANkBACYABglmGu4GANkBACcABQnNHSgJALABACMABgkgFfYmAF8BAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAVAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAeAG8TAA==.Nytemayer:BAACLgAFFH8HAAIeAAMJbxNPeQDQAAAeAAMJbxNPeQDQAAAuAAQKfysABB4ACQmIIGEaAIYCAB4ACQl+H2EaAIYCAB0AAwmYH4szAOkAAB8AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn81AAICAAgJlhXrDgDGAQACAAgJlhXrDgDGAQAAAA==.Obonhigh:BAAALgAECgUJBQAAAA==.Oboñ:BAABLgAECn8lAAMfAAgJzw8RDQCLAQAfAAgJzw8RDQCLAQAeAAEJYwPyYgEeAAAAAA==.Obsfuyung:BAABLgAECn8yAAIOAAgJlhTmIACmAQAOAAgJlhTmIACmAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Oo='Oopsiez:BAAALgAECgQJBAAAAA==.',
Or='Orcc:BAAALgAECgEJAQAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAaAAAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxbUPAAOAgABAAkJiBPUPAAOAgAgAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8tAAQKAAkJdxtFFwBQAgAKAAgJrBtFFwBQAgAGAAIJ9wirWgFXAAAHAAEJAADOYgAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8oAAMdAAkJChVkBgD7AQAdAAkJChVkBgD7AQAeAAEJNgFtaQENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.Psyrine:BAAALgAECgQJBwAAAA==.',
Py='Pyrokast:BAAALgAECgUJBQAAAA==.Pyrokos:BAACLgAFFH8GAAIVAAMJUBmQfwDYAAAVAAMJUBmQfwDYAAAuAAQKfyEAAhUACAnsIDliABUCABUACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMkAAkJkiFvBgBlAgAkAAkJkiFvBgBlAgAZAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8XAAIKAAUJWhv0FgBvAQAKAAUJWhv0FgBvAQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIZAAgJ7BApQQBAAQAZAAgJ7BApQQBAAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIVAAQJ4xlwVwAuAQAVAAQJ4xlwVwAuAQAuAAQKfygAAhUACQlDJRUKACkDABUACQlDJRUKACkDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgADCgYJCgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8WAAIGAAYJtBFuJgBwAQAGAAYJtBFuJgBwAQAuAAQKfy4AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR6wXAD3AAAGAAMJVR6wXAD3AAAuAAQKfywAAgYACQkGIpsOABkDAAYACQkGIpsOABkDAAAA.',
Sa='Sabaak:BAABLgAECn8sAAIGAAgJZCEvGwChAgAGAAgJZCEvGwChAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn83AAIeAAkJ9RBTRADOAQAeAAkJ9RBTRADOAQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xMLpAAxAQAGAAYJ5xMLpAAxAQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBBKbgDpAAADAAYJmBBKbgDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJDwAAAA==.Sanorasong:BAEBLgAECn8gAAMKAAkJ7Bd4FwBOAgAKAAkJ7Bd4FwBOAgAGAAUJPhQDxwD/AAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8XAAMMAAkJbxoHHgBxAgAMAAkJbxoHHgBxAgAQAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn81AAIdAAgJ9xZjBwDfAQAdAAgJ9xZjBwDfAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgcJEAAAAA==.Sections:BAAALgADCgkJHAAAAA==.Semilla:BAAALgADCgEJAQAAAA==.Severussnape:BAABLgAECn8jAAMeAAkJqQnfYgB5AQAeAAkJnAnfYgB5AQAdAAEJ6gpUQwAnAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx4PPwDoAAALAAMJKx4PPwDoAAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgrRRAAgAQANAAgJLgrRRAAgAQAFAAMJ2wO3NQBZAAAAAA==.Shinron:BAAALgAECgEJAQAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEAAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8aAAInAAkJTBWtBQAaAgAnAAkJTBWtBQAaAgAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgUJCgABLgAECgkJHQAXALggAA==.Skarletbolt:BAAALgAECgUJBQAAAA==.Skarletflame:BAABLgAECn8aAAIYAAkJnRhADQBRAgAYAAkJnRhADQBRAgAAAA==.',
Sl='Slather:BAABLgAECn8aAAITAAgJcBAKGADVAQATAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIVAAgJtBBRdgCNAQAVAAgJtBBRdgCNAQAAAA==.Slayerdude:BAAALgAECgEJAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAABLgAECn8WAAIWAAcJAQXJGwC9AAAWAAcJAQXJGwC9AAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJIAAKAOwXAA==.Sorne:BAEBLgAFFH8GAAILAAUJbRMnLgApAQALAAUJbRMnLgApAQABLgAFFAMJDwALAGwlAA==.',
Sp='Spaghett:BAABLgAECn8fAAMiAAkJRBRHJwB2AQAiAAkJphFHJwB2AQAOAAYJJhOjRADtAAAAAA==.Springtotem:BAABLgAECn8fAAIEAAkJARKHJACnAQAEAAkJARKHJACnAQAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8mAAILAAkJPx7zCQAWAwALAAkJPx7zCQAWAwAAAA==.Storaxota:BAAALgAFFAcJBAAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAIJBwANAPoJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AvcQACOAQADAAkJ6AvcQACOAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIYAAgJshSxIQBrAQAYAAgJshSxIQBrAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIZAAkJzR+QCwCvAgAZAAkJzR+QCwCvAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8YAAIoAAQJKBOnJgAVAQAoAAQJKBOnJgAVAQAuAAQKfy8ABCgACAliG1MTAEYCACgACAliG1MTAEYCAAkAAQkFFq57ADoAAAgAAQkZDACOACwAAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwi4dwDPAAADAAcJTwi4dwDPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Terrenn:BAAALgADCggJCAAAAA==.Tessla:BAACLgAFFH8HAAINAAIJ+gnjRwBuAAANAAIJ+gnjRwBuAAAuAAQKf0wAAw0ACQmvHJYNAI8CAA0ACQmvHJYNAI8CAAsAAgm+CHbKAEMAAAAA.Tetragram:BAAALgAECgQJBAABLgAECgkJPgAFAPgiAA==.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIMAAkJRgr6VQCiAQAMAAkJRgr6VQCiAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAABLgAECn8bAAIGAAcJSh43MgBZAgAGAAcJSh43MgBZAgAAAA==.Thundertoes:BAABLgAECn8jAAMLAAkJexylDgDeAgALAAkJexylDgDeAgAFAAYJChJzHwD+AAAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAABLgAECgkJAQAaAAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8qAAMLAAcJ2RQGPwCyAQALAAcJ2RQGPwCyAQANAAcJChAYQQAwAQAAAA==.Torgoth:BAABLgAECn8oAAIFAAkJpRTkCQAeAgAFAAkJpRTkCQAeAgAAAA==.Toshido:BAABLgAECn8VAAIMAAYJWhD5oAAAAQAMAAYJWhD5oAAAAQAAAA==.',
Tr='Traetor:BAABLgAECn8kAAIEAAkJDib3AAB7AwAEAAkJDib3AAB7AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8YAAIGAAYJ3AeY5wDUAAAGAAYJ3AeY5wDUAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgAECgEJAQAAAA==.',
Ul='Ultane:BAABLgAECn8kAAILAAgJNQ4HRwCSAQALAAgJNQ4HRwCSAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8ZAAIMAAgJYQxVaQBwAQAMAAgJYQxVaQBwAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJFwAXANAcAA==.Valiantaint:BAACLgAFFH8XAAIXAAQJ0ByHNQBPAQAXAAQJ0ByHNQBPAQAuAAQKfzAAAhcACQk/HtgVAJUCABcACQk/HtgVAJUCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJFwAXANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJFwAXANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh/yFADFAgAGAAkJYh/yFADFAgAAAA==.Vendeldh:BAABLgAECn8sAAIXAAkJuCPUEgDpAgAXAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8lAAIMAAkJUhFWOgD1AQAMAAkJUhFWOgD1AQAAAA==.',
Vi='Virajr:BAABLgAECn8oAAMjAAgJ0RX+FQDvAQAjAAgJ0RX+FQDvAQAmAAEJvAT/KQAgAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIZAAkJ8wf/QABBAQAZAAkJ8wf/QABBAQAAAA==.Vissiction:BAABLgAECn8ZAAIXAAkJvxZgLQASAgAXAAkJvxZgLQASAgAAAA==.Vistine:BAACLgAFFH8FAAIHAAIJAQTVFQBMAAAHAAIJAQTVFQBMAAAuAAQKf0kAAgcACQkyEdkAAB0BAAcACQkyEdkAAB0BAAEuAAUUAgkHAA0A+gkA.Vitez:BAABLgAECn8WAAMdAAkJrAZ+HQC8AAAdAAgJFAd+HQC8AAAeAAIJRAPiGgFNAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIVAAcJUgyGqQAsAQAVAAcJUgyGqQAsAQAAAA==.Wendy:BAABLgAECn8pAAILAAgJ1RiLNwDSAQALAAgJ1RiLNwDSAQABLgAECgkJGgADABgTAA==.',
Wi='Win:BAACLgAFFH8FAAIEAAQJ9QbFLQDRAAAEAAQJ9QbFLQDRAAAuAAQKfyYAAwMABwnjGlolACICAAMABwnjGlolACICAAQABglzHQoBAEgBAAAA.Winkster:BAACLgAFFH8MAAIGAAUJWRykOQA5AQAGAAUJWRykOQA5AQAuAAQKfzAAAgYACQn4JH8KABMDAAYACQn4JH8KABMDAAAA.',
Xa='Xanadu:BAACLgAFFH8FAAIoAAIJIg+NPQCDAAAoAAIJIg+NPQCDAAAuAAQKfzgAAigACQlMHsEGABIDACgACQlMHsEGABIDAAAA.Xarinia:BAABLgAECn8rAAMUAAkJDRIEHgDnAQAUAAkJDRIEHgDnAQATAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8lAAIcAAkJthzrBwByAgAcAAkJthzrBwByAgABLgAFFAYJFQAjACgXAA==.',
Xd='Xdynasty:BAACLgAFFH8VAAIjAAYJKBeOEACQAQAjAAYJKBeOEACQAQAuAAQKfycAAyMACQkCJCwMANUCACMACQn/IywMANUCACcABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn86AAQeAAkJmhmXJgBDAgAeAAkJLxiXJgBDAgAdAAUJGBR5JQAxAQAfAAIJVgtDMAA9AAABLgAFFAQJBQAEAPUGAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAACLgAFFH8HAAILAAMJAhFnBwCNAAALAAMJAhFnBwCNAAAuAAQKfykAAwsACQnOEDI8AL4BAAsACQnOEDI8AL4BAA0ABAnJCCGEAGgAAAAA.Zabenir:BAABLgAECn8iAAIIAAkJ7hwwCwCdAgAIAAkJ7hwwCwCdAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
Zo='Zonni:BAAALgADCgYJBgAAAA==.Zorusii:BAAALgAECgMJAwABLgAECgkJHQAXALggAA==.',
['Ðe']='Ðexter:BAABLgAECn8ZAAIGAAYJJQn24QDbAAAGAAYJJQn24QDbAAAAAA==.',
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
