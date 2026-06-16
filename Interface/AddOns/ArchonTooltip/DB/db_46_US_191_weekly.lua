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

local lookup = {'DeathKnight-Unholy','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Retribution','Paladin-Protection','Priest-Shadow','Priest-Holy','Paladin-Holy','Shaman-Restoration','Hunter-BeastMastery','Shaman-Elemental','Monk-Windwalker','Monk-Mistweaver','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Guardian','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Blood','Evoker-Devastation','Mage-Arcane','Monk-Brewmaster','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warrior-Arms','DemonHunter-Vengeance','Priest-Discipline',}
local provider = {region='US',realm='Shandris',name='US',type='weekly',zone=46,date='2026-06-13',data={Ab='Abyssara:BAAALgAECgcJEgAAAA==.',
Ac='Acebets:BAAALgAECgEJAQAAAA==.Acedk:BAACLgAFFH8GAAIBAAMJqR99jADtAAABAAMJqR99jADtAAAuAAQKfxoAAgEACQlPIZoLAD4DAAEACQlPIZoLAD4DAAAA.',
Ad='Adorie:BAAALgAECgIJAwAAAA==.Adun:BAAALgADCgQJBAAAAA==.',
Ae='Aelphe:BAACLgAFFH8GAAICAAMJwBVxDQDZAAACAAMJwBVxDQDZAAAuAAQKfx8ABAIACQmwIe0AAHwDAAIACQmwIe0AAHwDAAMAAQlGB0vRADEAAAQAAQkuAiKOAB8AAAAA.Aelusius:BAABLgAECn8+AAIFAAkJ+CJNAQAtAwAFAAkJ+CJNAQAtAwABLgAECggJQgACAFojAA==.Aeón:BAAALgAECggJDgAAAA==.',
Ag='Aggèn:BAABLgAECn8oAAMGAAkJ2xwCGwCgAgAGAAkJ2xwCGwCgAgAHAAIJNQhBVAAlAAAAAA==.',
Aj='Aja:BAAALgADCgEJAQAAAA==.',
Ak='Akashá:BAAALgADCgUJBQAAAA==.Akriksdk:BAABLgAECn8WAAIBAAkJciYXAQCNAwABAAkJciYXAQCNAwAAAA==.',
Al='Al:BAACLgAFFH8NAAMIAAQJGwo4HwDyAAAIAAQJGwo4HwDyAAAJAAIJbQSwLwBVAAAuAAQKfy0AAwgACAnbGNscAN0BAAgACAnbGNscAN0BAAkABwlpEUErAJsBAAAA.Aladrios:BAAALgAECgIJAwAAAA==.Alandarus:BAAALgAECgEJAQAAAA==.Alexanderath:BAAALgAECgQJBwAAAA==.Alexânderson:BAAALgAECgUJDQAAAA==.Alkaline:BAAALgADCggJCAAAAA==.Alkatractite:BAABLgAECn8nAAIGAAgJ4BvQMAA7AgAGAAgJ4BvQMAA7AgAAAA==.Allenwalker:BAAALgAECgUJCAAAAA==.Alucarde:BAEALgADCgYJBgABLgAECgkJHwAKAOwXAA==.Alzul:BAAALgADCgUJBQAAAA==.',
Am='Amanita:BAABLgAECn8aAAIDAAkJGBONJAAkAgADAAkJGBONJAAkAgAAAA==.Amasham:BAAALgAECgYJBgAAAA==.Amberness:BAAALgAFFAEJAQABLgAFFAMJBwALACseAA==.Ambersoul:BAAALgAECgEJAQAAAA==.Amira:BAAALgAECgcJDQABLgAFFAQJBwAMAMgeAA==.',
An='Anixa:BAAALgADCgkJCQAAAA==.Anyi:BAABLgAECn8rAAMNAAgJygtIQQAqAQANAAgJygtIQQAqAQALAAQJEgK5sABiAAAAAA==.',
Ao='Aoi:BAABLgAECn8yAAMOAAgJxBKkIQCeAQAOAAgJxBKkIQCeAQAPAAgJ5gvBRgBJAQAAAA==.',
Ar='Arrisia:BAABLgAECn8yAAMMAAgJKRLOTAC3AQAMAAgJKRLOTAC3AQAQAAIJJwTONwA9AAAAAA==.Artemissy:BAAALgADCgQJBAAAAA==.Arthedain:BAACLgAFFH8QAAIRAAQJiSFVCwBvAQARAAQJiSFVCwBvAQAuAAQKfzIAAhEACQnSI30BAHIDABEACQnSI30BAHIDAAAA.Arthedaine:BAACLgAFFH8bAAISAAQJWiCGCgBvAQASAAQJWiCGCgBvAQAuAAQKfzEAAhIACQnKI04EAOoCABIACQnKI04EAOoCAAEuAAUUBAkQABEAiSEA.',
As='Asiea:BAAALgADCgQJBAAAAA==.',
Au='Augmentmyass:BAAALgAFFAEJAQAAAA==.Aushahin:BAAALgAECgYJBgABLgAECgkJHwAEAAESAA==.Autumni:BAABLgAECn8fAAIMAAcJsRhbXACMAQAMAAcJsRhbXACMAQAAAA==.Auvry:BAABLgAECn8aAAMTAAcJVhkdEAA5AgATAAcJVhkdEAA5AgAUAAIJqAnMlgAqAAAAAA==.',
Ax='Axel:BAAALgADCgUJBQABLgAECgkJKwAVAEkIAA==.',
Ay='Aymus:BAABLgAECn8VAAMWAAYJtQLD5gBmAAAWAAYJbgLD5gBmAAAXAAMJzAHpfgAbAAAAAA==.',
Az='Azliain:BAAALgAECgkJCAAAAA==.',
Ba='Bahamutfang:BAABLgAECn8lAAMGAAkJDwg9iQBbAQAGAAkJDwg9iQBbAQAHAAUJzAT8OgBtAAAAAA==.Bakala:BAABLgAECn82AAMYAAgJ5RT3LwCNAQAYAAgJOBL3LwCNAQARAAgJYw3IHQBDAQAAAA==.Bangbang:BAABLgAECn8qAAIMAAkJqBXiSgC8AQAMAAkJqBXiSgC8AQAAAA==.Bast:BAAALgADCgQJBAAAAA==.',
Be='Beeyou:BAAALgADCgEJAQAAAA==.Belegaer:BAABLgAECn8jAAIKAAkJhw/QKADDAQAKAAkJhw/QKADDAQAAAA==.Belenos:BAAALgADCggJHQABLgADCggJHQAZAAAAAA==.Bellamy:BAAALgAECgEJAQAAAA==.Beltway:BAAALgADCgcJCgAAAA==.Bendini:BAACLgAFFH8GAAIQAAMJHwuwHgCwAAAQAAMJHwuwHgCwAAAuAAQKfx4AAhAACQnSE3kqANgBABAACQnSE3kqANgBAAAA.Benmaverick:BAABLgAECn8dAAIWAAkJDg/fSACoAQAWAAkJDg/fSACoAQAAAA==.',
Bh='Bhe:BAABLgAECn8aAAIFAAgJ5wpNFwBMAQAFAAgJ5wpNFwBMAQAAAA==.',
Bi='Billymayzz:BAAALgADCgIJAgAAAA==.Bishop:BAABLgAECn8zAAIJAAgJvBd0FAAwAgAJAAgJvBd0FAAwAgAAAA==.',
Bl='Blackbird:BAAALgADCgYJCgAAAA==.',
Bo='Bobe:BAABLgAECn87AAMRAAkJRhzzCABlAgARAAkJRhzzCABlAgAYAAMJpAYYjgBSAAAAAA==.Bobedruid:BAAALgADCgQJAQAAAA==.Bordok:BAABLgAECn8hAAIaAAkJ2gtKDgCOAQAaAAkJ2gtKDgCOAQAAAA==.Borkuz:BAAALgAECgEJAQAAAA==.Bowfléx:BAAALgAECgEJAQAAAA==.',
Br='Brettdadad:BAAALgAECgIJAwAAAA==.Brighella:BAAALgADCgMJAwAAAA==.Bronxdr:BAAALgADCgQJBAAAAA==.Brows:BAAALgAECgIJAwAAAA==.Bruisewayne:BAAALgADCggJCAAAAA==.Brunco:BAABLgAECn8fAAMMAAkJ0h3xHwBkAgAMAAkJ0h3xHwBkAgAQAAYJyRNUFwD1AAAAAA==.Brxndxn:BAAALgADCgUJBQAAAA==.Brëw:BAAALgADCgUJBQAAAA==.Brütäl:BAAALgADCgIJAgAAAA==.',
Bu='Bubbleyo:BAAALgADCgcJCAAAAA==.Bustaheals:BAABLgAECn8lAAMJAAkJlhR5IAC6AQAJAAcJ+hZ5IAC6AQAIAAcJ9RBsMABaAQAAAA==.',
Bw='Bwasamdi:BAAALgAFFAEJAQAAAA==.',
Ca='Calypsa:BAAALgADCgMJBAAAAA==.Captplanet:BAABLgAECn8fAAQCAAkJVBaLDwC4AQACAAYJVxiLDwC4AQADAAgJdglOYgALAQAEAAYJSgzTSADkAAAAAA==.Cashartea:BAAALgAECgUJBQAAAA==.Cattleclysm:BAAALgADCgMJAwAAAA==.',
Ce='Ceindra:BAABLgAECn8pAAIFAAkJIyCXAwDFAgAFAAkJIyCXAwDFAgAAAA==.Celiñ:BAACLgAFFH8HAAMHAAMJZxQTDwCKAAAHAAMJ7QoTDwCKAAAGAAIJ9xN7lQCFAAAuAAQKfygABAYACQmiIJQaAKICAAYACAmyIpQaAKICAAcABAnRE5g2AIIAAAoAAwnuBLR1AGAAAAAA.Celîn:BAAALgAECgQJBAABLgAFFAMJBwAHAGcUAA==.Ceronia:BAAALgADCgEJAQAAAA==.',
Ch='Chainstormer:BAAALgAECgUJCQAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chibby:BAAALgAECgQJBAAAAA==.Chuladk:BAAALgAFFAIJAgAAAA==.',
Cl='Cleymour:BAAALgADCgcJDgAAAA==.Cløudstrife:BAAALgAECgEJAQAAAA==.',
Co='Colbalt:BAABLgAECn8UAAIIAAcJdAflUwDAAAAIAAcJdAflUwDAAAAAAA==.Cor:BAAALgAECgUJCAAAAA==.Corrosive:BAAALgAECgYJBQAAAA==.Cotilion:BAAALgADCgMJAwAAAA==.',
Cr='Creation:BAABLgAECn9CAAMCAAgJWiPoAwDJAgACAAgJQyPoAwDJAgAbAAgJSxz7CgAvAgAAAA==.Crunky:BAABLgAECn8wAAIPAAgJ9hXnIQAIAgAPAAgJ9hXnIQAIAgAAAA==.',
Cu='Cuddleybunni:BAAALgADCgMJAwAAAA==.Cuddlymethod:BAAALgAECgMJBgAAAA==.',
['Có']='Cól:BAABLgAECn8uAAIVAAkJNh5sMgCpAgAVAAkJNh5sMgCpAgAAAA==.',
Da='Daddywoof:BAAALgADCgMJAwAAAA==.Dadmike:BAAALgAECgEJAQAAAA==.Daedilus:BAAALgADCgMJAwAAAA==.Dahealzrhere:BAAALgAECgYJCwAAAA==.Dalel:BAABLgAECn8dAAIWAAkJuCBjEgCtAgAWAAkJuCBjEgCtAgAAAA==.Dameond:BAAALgAECgUJCwAAAA==.David:BAAALgADCgQJBAABLgAFFAQJBQASAHsZAA==.',
De='Deadisdead:BAAALgAECgYJDgAAAA==.Deadlyglow:BAAALgADCgcJDAABLgAECgYJCAAZAAAAAA==.Deathkratos:BAAALgADCgYJCQAAAA==.Demiurgos:BAACLgAFFH8HAAMLAAMJfSBzMwANAQALAAMJfSBzMwANAQAFAAMJbwNmEQCoAAAuAAQKfx4AAwsABwltIUYXAIsCAAsABwltIUYXAIsCAAUAAwl4EJorAJMAAAAA.Demonicteli:BAABLgAECn8WAAIXAAkJlxmZEABdAgAXAAkJlxmZEABdAgAAAA==.Demonopii:BAAALgAECgQJCAAAAA==.Denzle:BAAALgAECggJDQAAAA==.Dermot:BAABLgAECn8tAAQcAAgJLiN0AwC6AgAcAAcJZCJ0AwC6AgAdAAUJ+iBWeABIAQAeAAIJCyYHIQBuAAAAAA==.',
Dh='Dhiying:BAAALgAECggJEAAAAA==.',
Di='Dippindots:BAABLgAECn8fAAMEAAgJLBG/LQBoAQAEAAgJLBG/LQBoAQADAAEJZQGJ7AAVAAAAAA==.Divakon:BAAALgADCgkJCgAAAA==.Dixmen:BAABLgAECn8YAAIGAAgJexP4YQCqAQAGAAgJexP4YQCqAQAAAA==.',
Dk='Dkäri:BAAALgAECgYJDQAAAA==.',
Do='Dolemen:BAABLgAECn89AAIGAAgJUQ3qfwBsAQAGAAgJUQ3qfwBsAQAAAA==.Domaon:BAABLgAECn8vAAIXAAkJrCHEBAD3AgAXAAkJrCHEBAD3AgAAAA==.Domshammy:BAAALgAECggJDQABLgAECgkJLwAXAKwhAA==.Doombunny:BAAALgAECgUJCQABLgAECgkJQAAMAOEXAA==.Doubt:BAABLgAECn8bAAIIAAgJWArdNABCAQAIAAgJWArdNABCAQAAAA==.',
Dr='Dranthrax:BAAALgAECgUJEAAAAA==.',
Du='Dullgrim:BAAALgADCgkJEAAAAA==.Dunigan:BAABLgAECn80AAMGAAgJThFGfQBxAQAGAAgJTRBGfQBxAQAHAAYJDg8rJgDhAAAAAA==.Dunigen:BAAALgAECgcJCgAAAA==.Dunstan:BAAALgAECgYJDwAAAA==.Durmet:BAAALgAECgUJBQAAAA==.Dustos:BAAALgADCgIJAgAAAA==.',
Eb='Ebeast:BAABLgAECn8+AAISAAkJcxiNDABbAgASAAkJcxiNDABbAgAAAA==.Ebingus:BAAALgADCgYJBgAAAA==.',
Ei='Eifaun:BAEALgAECgUJCQAAAA==.',
El='Elexidor:BAAALgAECgkJDAAAAA==.Elorrna:BAAALgADCgYJBgAAAA==.',
Em='Emberjoy:BAAALgADCgUJBQAAAA==.',
Er='Erathen:BAAALgADCgUJBQAAAA==.',
Ey='Eyeet:BAAALgAECgkJCQAAAA==.',
Fa='Facade:BAABLgAECn8bAAIfAAkJIBIMGwCCAQAfAAkJIBIMGwCCAQAAAA==.Facepalm:BAABLgAECn8fAAIYAAkJdxPDHgD3AQAYAAkJdxPDHgD3AQAAAA==.Faked:BAAALgADCgEJAQABLgAECgYJDAAZAAAAAA==.Falion:BAAALgAECgYJBgAAAA==.Fallensaints:BAAALgAECgYJCwAAAA==.Falshalad:BAABLgAECn8dAAMDAAcJJhP3VQBRAQADAAcJJhP3VQBRAQACAAQJyRPJKwCyAAABLgAECggJHgATAHcQAA==.Falyy:BAAALgADCgQJBAAAAA==.',
Fe='Fentak:BAABLgAECn8cAAIaAAgJwgvAFAAyAQAaAAgJwgvAFAAyAQAAAA==.',
Fi='Fierytotes:BAAALgAECgUJCAAAAA==.Finka:BAAALgAECgMJAwAAAA==.',
Fl='Flamedaddy:BAABLgAECn8kAAMLAAcJcxn1KwAFAgALAAcJcxn1KwAFAgANAAEJgRxpjgBQAAAAAA==.',
Fo='Fog:BAAALgAECgEJAgAAAA==.Forgotmymeds:BAABLgAECn9IAAILAAkJbBq3GQB5AgALAAkJbBq3GQB5AgAAAA==.Foxmccloud:BAABLgAECn8uAAMLAAgJVRvFGgBxAgALAAgJVRvFGgBxAgANAAQJlQTllABHAAAAAA==.',
Fr='Fruitloop:BAABLgAECn8jAAIVAAkJMB/bFwDHAgAVAAkJMB/bFwDHAgAAAA==.',
Fu='Fuil:BAAALgAECgYJDAAAAA==.Furgaler:BAAALgAECgUJCQABLgAECgkJHQAWALggAA==.',
Fy='Fyznen:BAAALgAECgQJBAAAAA==.',
Ga='Garidrael:BAAALgAECgEJAQAAAA==.Garim:BAAALgADCgcJBwAAAA==.Gaviriard:BAAALgADCgMJAwAAAA==.',
Ge='Gebran:BAAALgAECgEJAQAAAA==.Gellywoo:BAABLgAECn88AAIYAAgJayCrDQCRAgAYAAgJayCrDQCRAgAAAA==.',
Gh='Ghostofonyx:BAAALgADCgcJFQAAAA==.',
Gi='Girlypop:BAAALgAECgQJBgAAAA==.',
Go='Golaoth:BAABLgAECn8kAAMTAAkJtxczBwCDAgATAAkJtxczBwCDAgAgAAEJCQGQLAAKAAAAAA==.Gooftoo:BAABLgAECn8UAAIDAAcJKB8QLwDwAQADAAcJKB8QLwDwAQAAAA==.',
Gr='Greycie:BAAALgADCgkJEwABLgAECggJEgAZAAAAAA==.Greyfax:BAAALgADCgcJDQAAAA==.Greymoon:BAABLgAECn81AAIbAAgJGhnIDgDzAQAbAAgJGhnIDgDzAQAAAA==.',
Gy='Gyre:BAABLgAECn8dAAIMAAcJ6hAcagBpAQAMAAcJ6hAcagBpAQAAAA==.',
Ha='Haezi:BAAALgAECgcJDAAAAA==.Happyendings:BAAALgAFFAIJAwAAAA==.',
He='Helbafx:BAAALgAECgcJEAAAAA==.',
Hi='Hiroshì:BAAALgAECgEJAQAAAA==.',
Ho='Homewrecker:BAABLgAECn8cAAIRAAgJ2RI1GgBlAQARAAgJ2RI1GgBlAQAAAA==.',
Hu='Hunnee:BAAALgADCgkJFAAAAA==.Huské:BAAALgAECgIJAgAAAA==.',
Ic='Icelace:BAAALgAECgEJAQAAAA==.Icemàn:BAAALgAECgYJDwAAAA==.',
If='Ifearnobeer:BAABLgAECn81AAMNAAkJggqMOQBMAQANAAkJggqMOQBMAQALAAIJZwj2wwBGAAAAAA==.',
Ii='Iifelike:BAAALgAECgUJBQABLgAECgkJFQAHAN4PAA==.',
In='Inters:BAAALgAECgUJDgAAAA==.',
Ir='Ironspark:BAAALgAECgcJEgAAAA==.',
Is='Isabel:BAACLgAFFH8QAAIDAAQJTwtAOADHAAADAAQJTwtAOADHAAAuAAQKfxUAAgMACAmEGC0kACoCAAMACAmEGC0kACoCAAAA.Isaetr:BAAALgAECggJDwAAAA==.',
Ja='Jackôdaniels:BAAALgADCgkJDgAAAA==.Jadus:BAAALgAECgMJAwAAAA==.Jaiantobea:BAABLgAECn8wAAILAAkJ3x11CAAmAwALAAkJ3x11CAAmAwAAAA==.Jake:BAAALgAECgIJAgAAAA==.Jakulista:BAAALgADCgcJFQAAAA==.Jashugan:BAAALgADCgQJBAAAAA==.Jawn:BAABLgAECn8iAAIOAAkJ4g6CIwCSAQAOAAkJ4g6CIwCSAQAAAA==.Jaycie:BAAALgAECggJEgAAAA==.',
Je='Jessuss:BAABLgAECn8iAAIGAAgJPhK7bQCQAQAGAAgJPhK7bQCQAQAAAA==.',
Jh='Jha:BAAALgADCgYJBgAAAA==.',
Ju='Jude:BAAALgAECgUJCgAAAA==.Juggernàut:BAAALgAECgYJEAAAAA==.Julïeth:BAAALgAECgEJAQAAAA==.Junipermoon:BAAALgADCggJHQAAAA==.',
Ka='Kajas:BAAALgAECgMJAwAAAA==.Kalahandra:BAACLgAFFH8FAAIDAAMJqQPYTQCDAAADAAMJqQPYTQCDAAAuAAQKfyoAAgMACQnTEPk0AMUBAAMACQnTEPk0AMUBAAAA.Kalebeesd:BAABLgAECn8uAAIWAAgJXBwXIgBGAgAWAAgJXBwXIgBGAgAAAA==.Karthdh:BAAALgADCgcJDgABLgADCggJCAAZAAAAAA==.Kasey:BAAALgAECgEJAQAAAA==.Katithianna:BAAALgADCgQJAwAAAA==.Katotan:BAABLgAECn8fAAIDAAgJPRQ8NwC4AQADAAgJPRQ8NwC4AQAAAA==.Kawk:BAABLgAECn8uAAIHAAkJWx+LBAC7AgAHAAkJWx+LBAC7AgAAAA==.Kazatreshan:BAAALgADCgcJDgAAAA==.Kazragor:BAACLgAFFH8NAAINAAQJbCIgEwB+AQANAAQJbCIgEwB+AQAuAAQKfyUAAg0ACAn5I/4OALcCAA0ACAn5I/4OALcCAAAA.',
Ke='Kebob:BAABLgAECn8VAAIHAAkJ3g/SFwBdAQAHAAkJ3g/SFwBdAQAAAA==.Kenziedadght:BAAALgAECgIJBQAAAA==.Keyboärd:BAABLgAECn8hAAIRAAgJ5BzTDQAKAgARAAgJ5BzTDQAKAgAAAA==.',
Ki='Kilo:BAAALgADCgEJAwAAAA==.Kippo:BAECLgAFFH8IAAIVAAUJJgURMwDRAAAVAAUJJgURMwDRAAAuAAQKfyMAAhUACAmWF0BKAFgCABUACAmWF0BKAFgCAAEuAAUUBgkTAAEAxhMA.Kittylover:BAAALgADCgcJEQAAAA==.',
Kl='Klazarth:BAACLgAFFH8HAAIIAAMJMRdzIQDhAAAIAAMJMRdzIQDhAAAuAAQKfx4AAggACQmqHowNAKoCAAgACQmqHowNAKoCAAAA.',
Ko='Kombat:BAABLgAECn8gAAIYAAgJshyvFABJAgAYAAgJshyvFABJAgAAAA==.Korllan:BAAALgAECgMJBAAAAA==.Kossnen:BAABLgAECn8UAAIdAAgJAh02MQASAgAdAAgJAh02MQASAgAAAA==.',
Kr='Krelivus:BAAALgAECgYJCwAAAA==.',
Ku='Kuda:BAABLgAECn8rAAIVAAkJuRMJQgATAgAVAAkJuRMJQgATAgAAAA==.',
Kw='Kwanu:BAABLgAECn8dAAIPAAgJFw25QgBaAQAPAAgJFw25QgBaAQAAAA==.',
['Kó']='Kóñä:BAAALgADCgkJDAABLgAECggJDgAZAAAAAA==.',
La='Lamue:BAAALgAECgIJAgAAAA==.Lantern:BAAALgADCgYJCwAAAA==.Larke:BAAALgAECgUJBwAAAA==.Lasa:BAAALgAECgYJBwABLgAECgYJDgAZAAAAAA==.Lasloo:BAABLgAECn8eAAIGAAYJgBAJjwBRAQAGAAYJgBAJjwBRAQAAAA==.Laylani:BAABLgAECn8cAAIHAAkJpg/3EgCWAQAHAAkJpg/3EgCWAQAAAA==.Layllis:BAAALgADCgQJBgAAAA==.',
Le='Legiondary:BAABLgAECn8cAAIWAAkJ8Rc7LgBEAgAWAAkJ8Rc7LgBEAgAAAA==.Lesabor:BAAALgADCgYJBgAAAA==.',
Li='Licknstick:BAAALgAECgUJCAAAAA==.Lir:BAAALgADCgIJAwAAAA==.Lisan:BAABLgAECn8hAAIhAAkJ4RYZAgBOAgAhAAkJ4RYZAgBOAgAAAA==.Lisanalgaib:BAAALgAECgEJAgAAAA==.Littledicey:BAAALgADCgcJCwAAAA==.',
Lo='Lothan:BAAALgADCgkJCQABLgAECgkJHwAEAAESAA==.Lotuss:BAABLgAECn8VAAMPAAYJYhctNgCUAQAPAAYJYhctNgCUAQAOAAEJNgMXvQAXAAABLgAFFAIJBwANAPoJAA==.',
Lu='Lucien:BAAALgAECgYJEQAAAA==.Luciä:BAABLgAECn8mAAIfAAkJBhJCFQDBAQAfAAkJBhJCFQDBAQAAAA==.Lucymoon:BAAALgAECgYJBQAAAA==.',
Ly='Lynex:BAAALgAECgQJBwAAAA==.',
Ma='Machoman:BAAALgAECgQJBAAAAA==.Madness:BAAALgAECgIJAgAAAA==.Magdeth:BAAALgADCgYJEAAAAA==.Magiann:BAAALgADCgEJAQAAAA==.Maiama:BAAALgAECgYJBwAAAA==.Marabelle:BAABLgAECn8cAAIEAAkJCgrcMgBLAQAEAAkJCgrcMgBLAQAAAA==.Massack:BAABLgAECn8jAAIiAAkJ9xdfEAA4AgAiAAkJ9xdfEAA4AgAAAA==.Mastik:BAAALgAECgEJAQAAAA==.Maximusblood:BAAALgADCgIJAgAAAA==.',
Mc='Mcknight:BAAALgAECgYJBgAAAA==.',
Me='Merex:BAAALgADCgEJAQAAAA==.Mero:BAAALgAECgYJBgAAAA==.Mew:BAAALgADCgEJAQABLgAECggJHwAKAJ0XAA==.',
Mi='Midgetmàniàc:BAAALgAECgMJBAAAAA==.Mikebeard:BAAALgAECgIJBQAAAA==.Mikereport:BAAALgAECgIJAgAAAA==.Misfire:BAAALgAECggJCQABLgAECgkJGgADABgTAA==.',
Mo='Moktar:BAAALgAECgYJBwAAAA==.Moobear:BAAALgADCgQJCwAAAA==.',
Mu='Muldoinit:BAABLgAECn8jAAIOAAkJYhhUEwAfAgAOAAkJYhhUEwAfAgAAAA==.',
My='Myroslava:BAAALgAECgMJAwAAAA==.Mystrall:BAAALgAECgYJBgAAAA==.',
['Më']='Mërikh:BAAALgADCggJEQABLgAECgUJCAAZAAAAAA==.',
Na='Nadorian:BAAALgAECgEJAQAAAA==.',
Ne='Neb:BAABLgAECn8mAAIKAAgJ/SMOBgArAwAKAAgJ/SMOBgArAwAAAA==.Nehemia:BAAALgAECgYJEQAAAA==.Nerilestis:BAAALgAECgEJAQAAAA==.Netherrogue:BAACLgAFFH8MAAMjAAQJiRzoEwBkAQAjAAQJIRvoEwBkAQAkAAMJoRetCADsAAAuAAQKfyMABCQACQntHdwGANoBACQABglmGtwGANoBACUABQnNHQcJALABACMABgkgFSgmAGEBAAAA.',
Ni='Nicage:BAAALgAECgQJBAABLgAFFAQJEAAVAOMZAA==.Nightdreams:BAAALgADCgcJCQAAAA==.',
Ny='Nytelytë:BAAALgAECgYJCQABLgAFFAMJBwAdAG8TAA==.Nytemayer:BAACLgAFFH8HAAIdAAMJbxOldgDQAAAdAAMJbxOldgDQAAAuAAQKfysABB0ACQmIINoZAIcCAB0ACQl+H9oZAIcCABwAAwmYH4szAOkAAB4AAQkAAC4pAE0AAAAA.',
Ob='Obmakare:BAABLgAECn81AAICAAgJlhWiDgDFAQACAAgJlhWiDgDFAQAAAA==.Obonhigh:BAAALgAECgUJBQAAAA==.Oboñ:BAABLgAECn8lAAMeAAgJzw+9DACLAQAeAAgJzw+9DACLAQAdAAEJYwNnXgEeAAAAAA==.Obsfuyung:BAABLgAECn8wAAIOAAgJkRRwIACnAQAOAAgJkRRwIACnAQAAAA==.',
On='Onkelos:BAAALgAECgEJAwAAAA==.',
Oo='Oopsiez:BAAALgAECgQJBAAAAA==.',
Or='Orcc:BAAALgADCgkJFwAAAA==.',
Pa='Paley:BAAALgAECgYJCgAAAA==.Palpatine:BAAALgAECgIJAgAAAA==.',
Pe='Peopleperson:BAAALgADCgQJAQAAAA==.Performance:BAAALgAECgcJEAAAAA==.Peterturbo:BAAALgAECgQJBAABLgADCgcJDQAZAAAAAA==.',
Pi='Pinji:BAAALgAECgIJAgAAAA==.Pinkky:BAAALgADCgkJCQAAAA==.Pinkypoo:BAABLgAECn8rAAMBAAkJmxawOwAPAgABAAkJiBOwOwAPAgAfAAYJvBixIwAjAQAAAA==.',
Pl='Plato:BAABLgAECn8tAAQKAAkJdxvqFgBRAgAKAAgJrBvqFgBRAgAGAAIJ9whFVQFXAAAHAAEJAAAwYQAAAAAAAA==.',
Po='Poiet:BAAALgAECgEJAgAAAA==.Poîsonivy:BAABLgAECn8mAAMcAAkJ2hQ7BgD7AQAcAAkJ2hQ7BgD7AQAdAAEJNgF/ZAENAAAAAA==.',
Ps='Psyche:BAAALgADCgkJDgAAAA==.Psyrine:BAAALgAECgQJBAAAAA==.',
Py='Pyrokast:BAAALgAECgUJBQAAAA==.Pyrokos:BAACLgAFFH8GAAIVAAMJUBmofADkAAAVAAMJUBmofADkAAAuAAQKfyEAAhUACAnsIDliABUCABUACAnsIDliABUCAAAA.Pyrö:BAAALgAECgkJCQAAAA==.',
Qu='Qu:BAABLgAECn84AAMmAAkJkiFvBgBlAgAmAAkJkiFvBgBlAgAYAAIJTQowlQBrAAAAAA==.Quellia:BAACLgAFFH8WAAIKAAUJWhsJFgBwAQAKAAUJWhsJFgBwAQAuAAQKfyIAAgoACQn8HdMMALMCAAoACQn8HdMMALMCAAAA.',
Ra='Rangel:BAABLgAECn8YAAIYAAgJ7BBuPwBGAQAYAAgJ7BBuPwBGAQAAAA==.Rattlesnake:BAAALgADCgYJBgAAAA==.Razziels:BAAALgAECgYJBwAAAA==.',
Re='Redacted:BAAALgADCgMJAwAAAA==.Renägäde:BAAALgAECgYJDwAAAA==.Rexulti:BAAALgAECgEJAQAAAA==.',
Ri='Ricodadawg:BAAALgADCgEJAQAAAA==.Rizen:BAAALgAECgQJBAAAAA==.',
Ro='Roija:BAACLgAFFH8QAAIVAAQJ4xlcVQA8AQAVAAQJ4xlcVQA8AQAuAAQKfygAAhUACQlDJbUJACsDABUACQlDJbUJACsDAAAA.Roshak:BAAALgADCgYJCQAAAA==.',
Ru='Runningbearr:BAAALgADCgYJBgAAAA==.Runningmage:BAAALgADCgcJDAAAAA==.Rurahk:BAACLgAFFH8WAAIGAAYJtBEbJABwAQAGAAYJtBEbJABwAQAuAAQKfy4AAgYACAkEIaIVAOgCAAYACAkEIaIVAOgCAAAA.',
['Rõ']='Rõbb:BAACLgAFFH8HAAIGAAMJVR4YWQD4AAAGAAMJVR4YWQD4AAAuAAQKfywAAgYACQkGIpsOABkDAAYACQkGIpsOABkDAAAA.',
Sa='Sabaak:BAABLgAECn8sAAIGAAgJZCGMGgCiAgAGAAgJZCGMGgCiAgAAAA==.Sacerdote:BAAALgADCgUJBQAAAA==.Saeriin:BAABLgAECn82AAIdAAkJrhC4RADLAQAdAAkJrhC4RADLAQAAAA==.Saintsnyder:BAABLgAECn8dAAIGAAYJ5xNcoAA0AQAGAAYJ5xNcoAA0AQAAAA==.Saithis:BAABLgAECn8UAAIDAAYJmBB3bQDpAAADAAYJmBB3bQDpAAAAAA==.Saltycrank:BAAALgADCgYJBgAAAA==.Sandew:BAAALgAECgYJDgAAAA==.Sanorasong:BAEBLgAECn8fAAMKAAkJ7BciFwBPAgAKAAkJ7BciFwBPAgAGAAUJPhTtxAD/AAAAAA==.Saphaa:BAAALgADCgEJAQAAAA==.Sardine:BAAALgAECgcJDAAAAA==.Sarylin:BAABLgAECn8XAAMMAAkJbxojHQByAgAMAAkJbxojHQByAgAQAAQJdQhqYwCzAAAAAA==.Satanshealer:BAAALgADCgYJCQAAAA==.Sathpriest:BAAALgAECgIJAgAAAA==.Satsuki:BAAALgAECgYJCgAAAA==.',
Sc='Schio:BAABLgAECn81AAIcAAgJ9xYvBwDfAQAcAAgJ9xYvBwDfAQAAAA==.',
Se='Sean:BAAALgADCgYJBgAAAA==.Seananagíns:BAAALgAECgcJEAAAAA==.Sections:BAAALgADCgkJHAAAAA==.Semilla:BAAALgADCgEJAQAAAA==.Severussnape:BAABLgAECn8jAAMdAAkJqQn4YAB9AQAdAAkJnAn4YAB9AQAcAAEJ6goRQgAnAAAAAA==.',
Sh='Shambs:BAACLgAFFH8HAAILAAMJKx7RPADpAAALAAMJKx7RPADpAAAuAAQKfxsAAgsACQnPHikGAA8DAAsACQnPHikGAA8DAAAA.Shamrorag:BAABLgAECn8bAAMNAAgJLgplQwAiAQANAAgJLgplQwAiAQAFAAMJ2wM5NABZAAAAAA==.Shinron:BAAALgAECgEJAQAAAA==.Shökan:BAAALgAECgQJBwAAAA==.',
Si='Sighah:BAAALgAECgkJEAAAAA==.Simlockdr:BAAALgADCgYJBgAAAA==.Sinensis:BAABLgAECn8aAAIlAAkJTBWdBQAaAgAlAAkJTBWdBQAaAgAAAA==.Singood:BAAALgAECgcJBwAAAA==.Sinnecro:BAABLgAECn8aAAIBAAkJ4h5nIADAAgABAAkJ4h5nIADAAgAAAA==.Sinshift:BAAALgADCgUJBQAAAA==.Sinstab:BAAALgAECggJCAAAAA==.',
Sk='Skadoosh:BAAALgAECgUJCQABLgAECgkJHQAWALggAA==.Skarletbolt:BAAALgAECgUJBQAAAA==.Skarletflame:BAABLgAECn8ZAAIXAAkJnRjnDABUAgAXAAkJnRjnDABUAgAAAA==.',
Sl='Slather:BAABLgAECn8aAAITAAgJcBAKGADVAQATAAgJcBAKGADVAQAAAA==.Slaycie:BAABLgAECn8jAAIVAAgJtBBzdACNAQAVAAgJtBBzdACNAQAAAA==.Slayerdude:BAAALgAECgEJAQAAAA==.Slofinger:BAAALgADCgYJCgAAAA==.',
Sn='Sneeb:BAAALgAECgEJAQAAAA==.Snugglebus:BAABLgAECn8WAAInAAcJAQVPGwC9AAAnAAcJAQVPGwC9AAAAAA==.',
So='Songli:BAEALgADCgEJAQABLgAECgkJHwAKAOwXAA==.Sorne:BAABLgAFFH8GAAILAAUJbRMaLAAqAQALAAUJbRMaLAAqAQABLgAFFAMJDwALAGwlAA==.',
Sp='Spaghett:BAABLgAECn8fAAMiAAkJRBTTJgB2AQAiAAkJphHTJgB2AQAOAAYJJhOUQwDtAAAAAA==.Springtotem:BAABLgAECn8fAAIEAAkJARKVIwCqAQAEAAkJARKVIwCqAQAAAA==.',
St='Stachel:BAAALgAECgUJBwAAAA==.Stanger:BAABLgAECn8mAAILAAkJPx6dCQAWAwALAAkJPx6dCQAWAwAAAA==.Storaxota:BAAALgAFFAcJAgAAAA==.Stormdk:BAAALgADCgcJCQAAAA==.',
Su='Superneo:BAAALgAECgYJBgABLgAFFAMJCgAEAOciAA==.Suvion:BAAALgAECgcJEwABLgAFFAIJBwANAPoJAA==.',
Sy='Sylinial:BAAALgAECgEJAQAAAA==.Sylvanis:BAAALgAECgUJBwAAAA==.Syrden:BAABLgAECn8WAAIDAAkJ6AsbQACPAQADAAkJ6AsbQACPAQAAAA==.',
Sz='Szadèk:BAAALgAECgYJBwAAAA==.',
['Sÿ']='Sÿphallus:BAABLgAECn8SAAIXAAgJshTMIABtAQAXAAgJshTMIABtAQAAAA==.',
Ta='Tael:BAABLgAECn8tAAIYAAkJzR9SCwCxAgAYAAkJzR9SCwCxAgAAAA==.Tagreth:BAAALgADCgQJBAAAAA==.Tangylizard:BAACLgAFFH8XAAIoAAQJKBNTJQAWAQAoAAQJKBNTJQAWAQAuAAQKfy8ABCgACAliG+YSAEgCACgACAliG+YSAEgCAAkAAQkFFq57ADoAAAgAAQkZDAOKAC4AAAAA.Tattoospyder:BAABLgAECn8aAAIDAAcJTwjRdgDPAAADAAcJTwjRdgDPAAAAAA==.Tatyanafour:BAAALgADCgIJAQAAAA==.Tatyanathirt:BAAALgADCgYJBgAAAA==.',
Te='Tessla:BAACLgAFFH8HAAINAAIJ+gmDRQBuAAANAAIJ+gmDRQBuAAAuAAQKf0cAAw0ACQmZHMENAIsCAA0ACQmZHMENAIsCAAsAAgm+CM3GAEMAAAAA.',
Th='Thafrggnpope:BAAALgADCgEJAQAAAA==.Thelarï:BAABLgAECn8jAAIMAAkJRgo6VACiAQAMAAkJRgo6VACiAQAAAA==.Thellany:BAAALgAECgEJAQAAAA==.Theshiznitz:BAAALgAECgMJAwAAAA==.Thors:BAABLgAECn8bAAIGAAcJSh43MgBZAgAGAAcJSh43MgBZAgAAAA==.Thundertoes:BAABLgAECn8jAAMLAAkJexw/DgDfAgALAAkJexw/DgDfAgAFAAYJChK0HgD/AAAAAA==.Thÿsucc:BAAALgADCgcJBwAAAA==.',
Ti='Tia:BAAALgAECgEJAQAAAA==.Timmy:BAAALgAECgMJCAAAAA==.',
To='Tommychong:BAAALgAECgIJAgAAAA==.Tonik:BAABLgAECn8qAAMLAAcJ2RQJPgCyAQALAAcJ2RQJPgCyAQANAAcJChDuPwAwAQAAAA==.Torgoth:BAABLgAECn8mAAIFAAkJpRSiCQAfAgAFAAkJpRSiCQAfAgAAAA==.Toshido:BAABLgAECn8VAAIMAAYJWhDznQAAAQAMAAYJWhDznQAAAQAAAA==.',
Tr='Traetor:BAABLgAECn8kAAIEAAkJDibvAAB8AwAEAAkJDibvAAB8AwAAAA==.Trakker:BAAALgADCgQJBAAAAA==.Trevize:BAABLgAECn8WAAIGAAYJ1wcv4wDXAAAGAAYJ1wcv4wDXAAAAAA==.',
Tt='Ttelloc:BAAALgADCgIJAgAAAA==.',
Tu='Tusiny:BAAALgAECgEJAQAAAA==.',
Ub='Ubully:BAAALgADCgYJCQAAAA==.',
Ul='Ultane:BAABLgAECn8jAAILAAgJfw3bRQCSAQALAAgJfw3bRQCSAQAAAA==.',
Un='Unreal:BAAALgADCgQJBAAAAA==.',
Va='Vaera:BAAALgAECgEJAQAAAA==.Valastae:BAABLgAECn8ZAAIMAAgJYQxGZwBwAQAMAAgJYQxGZwBwAQAAAA==.Valiantaine:BAABLgAECn8wAAMGAAkJXiFzKgB6AgAGAAkJXiFzKgB6AgAKAAkJgg2xPQCCAQABLgAFFAQJFgAWANAcAA==.Valiantaint:BAACLgAFFH8WAAIWAAQJ0Bz8MgBQAQAWAAQJ0Bz8MgBQAQAuAAQKfzAAAhYACQk/HoAVAJUCABYACQk/HoAVAJUCAAAA.Valiantrain:BAAALgAECgEJAgABLgAFFAQJFgAWANAcAA==.Valyulon:BAAALgADCgMJAwABLgAFFAQJFgAWANAcAA==.Vanjin:BAAALgADCgUJBQAAAA==.',
Ve='Vecna:BAAALgAECgYJCAAAAA==.Velherun:BAABLgAECn8dAAIGAAkJYh9kFADGAgAGAAkJYh9kFADGAgAAAA==.Vendeldh:BAABLgAECn8sAAIWAAkJuCPUEgDpAgAWAAkJuCPUEgDpAgAAAA==.Veni:BAAALgAECgYJBgAAAA==.Vexxaa:BAABLgAECn8kAAIMAAkJUhH/OAD2AQAMAAkJUhH/OAD2AQAAAA==.',
Vi='Virajr:BAABLgAECn8oAAMjAAgJ0RWeFQDvAQAjAAgJ0RWeFQDvAQAkAAEJvATKKAAhAAAAAA==.Vishus:BAAALgADCgUJBQAAAA==.Visiôn:BAABLgAECn8bAAIYAAkJ8wdePwBGAQAYAAkJ8wdePwBGAQAAAA==.Vissiction:BAABLgAECn8ZAAIWAAkJvxbqLAARAgAWAAkJvxbqLAARAgAAAA==.Vistine:BAACLgAFFH8FAAIHAAIJAQT4FABNAAAHAAIJAQT4FABNAAAuAAQKf0UAAgcACQlIDscWAGgBAAcACQlIDscWAGgBAAAA.Vitez:BAABLgAECn8WAAMcAAkJrAbSHAC9AAAcAAgJFAfSHAC9AAAdAAIJRAPCFwFNAAAAAA==.',
Vo='Voidscar:BAAALgADCgcJBwAAAA==.',
Wa='Warhurts:BAAALgAECgMJAwAAAA==.Waterbloom:BAAALgADCgMJAwAAAA==.',
We='Weave:BAABLgAECn8iAAIVAAcJUgyLpwAsAQAVAAcJUgyLpwAsAQAAAA==.Wendy:BAABLgAECn8pAAILAAgJ1RicNgDSAQALAAgJ1RicNgDSAQABLgAECgkJGgADABgTAA==.',
Wi='Win:BAABLgAECn8hAAMDAAcJ4xrqJAAiAgADAAcJ4xrqJAAiAgAEAAYJfxnUKgB6AQAAAA==.Winkster:BAACLgAFFH8MAAIGAAUJWRy9NgA6AQAGAAUJWRy9NgA6AQAuAAQKfzAAAgYACQn4JB4KABUDAAYACQn4JB4KABUDAAAA.',
Xa='Xanadu:BAACLgAFFH8FAAIoAAIJIg+YOwCEAAAoAAIJIg+YOwCEAAAuAAQKfzgAAigACQlMHo4GABQDACgACQlMHo4GABQDAAAA.Xarinia:BAABLgAECn8rAAMUAAkJDRJhHQDqAQAUAAkJDRJhHQDqAQATAAUJ4weUMQDjAAAAAA==.',
Xb='Xbear:BAABLgAECn8kAAIbAAkJhxvCBwByAgAbAAkJhxvCBwByAgABLgAFFAYJFQAjACgXAA==.',
Xd='Xdynasty:BAACLgAFFH8VAAIjAAYJKBeZDwCSAQAjAAYJKBeZDwCSAQAuAAQKfycAAyMACQkCJCwMANUCACMACQn/IywMANUCACUABgnDG+UNADwBAAAA.',
Xo='Xo:BAABLgAECn86AAQdAAkJmhn/JQBEAgAdAAkJLxj/JQBEAgAcAAUJGBR5JQAxAQAeAAIJVgtDMAA9AAABLgAECgcJIQADAOMaAA==.',
Xy='Xyfarion:BAAALgADCgYJBgAAAA==.Xyril:BAAALgAECgEJAQAAAA==.',
Ya='Yaasnah:BAAALgADCggJCAAAAA==.',
Za='Zabazz:BAACLgAFFH8FAAILAAMJdgjbYACAAAALAAMJdgjbYACAAAAuAAQKfygAAwsACQnOEDI7AL4BAAsACQnOEDI7AL4BAA0ABAmqBvKBAGgAAAAA.Zabenir:BAABLgAECn8hAAIIAAkJ7hz9CgCfAgAIAAkJ7hz9CgCfAgAAAA==.Zané:BAAALgAECgEJAgAAAA==.Zapan:BAAALgADCgUJBQAAAA==.',
Ze='Zeverai:BAAALgADCgkJCgAAAA==.',
Zi='Ziria:BAAALgADCgQJCwAAAA==.',
['Ðe']='Ðexter:BAABLgAECn8YAAIGAAYJ8wUs8gDFAAAGAAYJ8wUs8gDFAAAAAA==.',
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
