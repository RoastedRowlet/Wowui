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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','Unknown-Unknown','Shaman-Restoration','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Priest-Discipline','DemonHunter-Devourer','Paladin-Retribution','Hunter-BeastMastery','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Fire','DeathKnight-Frost','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Monk-Brewmaster','Paladin-Protection','Mage-Arcane','Mage-Frost','Druid-Feral','DeathKnight-Blood','Druid-Guardian','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement','Paladin-Holy','Priest-Shadow','Evoker-Preservation','Rogue-Outlaw',}
local provider = {region='US',realm='Hellscream',name='US',type='weekly',zone=46,date='2026-05-16',data={Aa='Aarix:BAABLgAECn8nAAMBAAkJSw/KEADjAQABAAkJSw/KEADjAQACAAEJCgDFnAACAAAAAA==.',
Ac='Achmed:BAAALgAECgEJAQAAAA==.',
Ad='Adaptabull:BAABLgAECn8bAAMDAAgJSxmeIQDwAQADAAgJSxmeIQDwAQAEAAIJIxW4rgBoAAAAAA==.Adari:BAAALgADCgMJAwAAAA==.Adune:BAAALgADCgQJBAAAAA==.',
Ae='Aedarria:BAAALgAECgEJAQAAAA==.Aelinessa:BAAALgAECggJDwAAAA==.Aelthalyste:BAAALgAECgYJAwAAAA==.Aeo:BAABLgAECn8iAAMFAAgJKB4uCgCUAgAFAAgJKB4uCgCUAgAGAAQJCASxSgCJAAABLgAECgkJKgAEABQgAA==.Aerodox:BAAALgAECgIJAgAAAA==.',
Ai='Aiel:BAAALgAECgcJEQABLgAECggJFQAHAKkUAA==.',
Al='Albedò:BAAALgAECgIJAwAAAA==.Aldrîch:BAAALgADCgMJAwAAAA==.Allyra:BAAALgADCgIJAgABLgAECgIJBQAIAAAAAA==.Allzaz:BAABLgAECn8VAAIJAAcJBBqMHwD7AQAJAAcJBBqMHwD7AQABLgAECgkJJQAKACUWAA==.Allzera:BAABLgAECn8lAAQKAAkJJRbADgBEAQALAAkJHhWmSwB5AQAKAAcJCBPADgBEAQAMAAUJqxCOFwCvAAAAAA==.Alric:BAAALgAECgYJDAAAAA==.',
Am='Amalei:BAAALgADCgYJCQAAAA==.Amberness:BAAALgAECgIJAgABLgAFFAMJBwAJACseAA==.Ammaria:BAAALgADCgUJBQAAAA==.Amorose:BAAALgAECgcJCgAAAA==.',
An='Anadrol:BAAALgADCgcJBwAAAA==.Anastassia:BAAALgAECgMJAgABLgAECgkJNAANAP0UAA==.Anduwyn:BAAALgADCgIJAgAAAA==.Anezra:BAAALgAECgEJAQAAAA==.Angelmack:BAAALgAECggJBwAAAA==.Anibella:BAABLgAECn8mAAIOAAgJ0h0mJwDnAQAOAAgJ0h0mJwDnAQAAAA==.Antons:BAAALgADCgkJEAAAAA==.Anuke:BAAALgAECgYJCgAAAA==.',
Ap='Aphlykted:BAAALgADCgYJBwAAAA==.',
Ar='Arbinu:BAAALgADCgMJAwAAAA==.Arflane:BAAALgADCgEJAQAAAA==.Argenta:BAAALgADCgEJAQAAAA==.Arkhlight:BAABLgAECn8XAAIPAAgJ+xyjMwDqAQAPAAgJ+xyjMwDqAQAAAA==.Arkhmonk:BAAALgAFFAEJAQAAAA==.Arkil:BAAALgAECgQJBAAAAA==.Arkillos:BAAALgAECgEJAwAAAA==.Armerous:BAAALgADCgMJAwAAAA==.Arnlok:BAAALgADCgMJAwAAAA==.Arrowhoof:BAACLgAFFH8LAAIQAAMJMwbSPQDNAAAQAAMJMwbSPQDNAAAuAAQKfxoAAhAACAmgGaoxAMMBABAACAmgGaoxAMMBAAAA.Arthurian:BAAALgADCgUJEQAAAA==.',
As='Ashmorph:BAAALgADCgYJCAAAAA==.Ashpriest:BAABLgAECn8qAAMNAAgJbRupFQDTAQANAAcJwRWpFQDTAQARAAgJKRnRFwDFAQAAAA==.Ashýra:BAABLgAECn8vAAIRAAkJMBYPCwBqAgARAAkJMBYPCwBqAgAAAA==.Askellus:BAAALgADCgYJBgAAAA==.Asphyxxed:BAAALgAECgEJAQAAAA==.Asterisk:BAABLgAECn85AAIQAAkJdR2TFABkAgAQAAkJdR2TFABkAgAAAA==.Asya:BAAALgAECgYJBQAAAA==.Asymmetric:BAAALgAECgkJDwAAAA==.',
At='Ataxica:BAAALgAECgEJAQAAAA==.Atlas:BAAALgAECgMJAwAAAA==.Attanu:BAAALgADCgIJAgAAAA==.Attilathepun:BAAALgADCgcJBwAAAA==.',
Au='Augrizia:BAAALgADCgMJBQAAAA==.Auriêl:BAAALgAECgQJBgAAAA==.',
Az='Azastra:BAABLgAECn8lAAMSAAgJ+A5ABwCFAQASAAgJ+A5ABwCFAQATAAYJbgdRQQDPAAAAAA==.Azer:BAAALgADCgYJBgAAAA==.Azorian:BAAALgAECgkJCwAAAA==.',
['Añ']='Aña:BAABLgAECn8cAAQUAAgJpyLfBQDqAQAUAAcJjSLfBQDqAQAOAAQJpA6IpwB4AAAVAAQJSRqROwBiAAAAAA==.Añarchist:BAAALgAECgEJAQABLgAECgkJHAAUAKciAA==.',
Ba='Babyymonster:BAAALgAFFAEJAgAAAA==.Badboii:BAAALgADCgMJAwAAAA==.Baelzharon:BAABLgAECn8hAAIWAAgJMRe7AgC2AQAWAAgJMRe7AgC2AQAAAA==.Baerenger:BAABLgAECn8bAAIPAAgJoCJ3DgC5AgAPAAgJoCJ3DgC5AgAAAA==.Baern:BAAALgAECgYJDwABLgAECggJGwAPAKAiAA==.Bagelpanda:BAAALgADCgMJAwAAAA==.Balròg:BAAALgADCgEJAQAAAA==.Barrlidan:BAAALgAECgEJAQABLgAFFAQJDAAHALgeAA==.Barrthas:BAABLgAFFH8MAAIHAAQJuB6uIwBtAQAHAAQJuB6uIwBtAQAAAA==.Basalt:BAABLgAECn8qAAIQAAgJBh0pJAACAgAQAAgJBh0pJAACAgAAAA==.Bastenwode:BAAALgAECgUJDAAAAA==.',
Bb='Bbye:BAAALgAECgEJAQAAAA==.',
Be='Bearlychaos:BAAALgADCgEJAQAAAA==.Bearmyload:BAAALgADCgUJBQABLgAECgkJGwAXAIwgAA==.Beastwrld:BAAALgADCgcJGgAAAA==.Becký:BAABLgAECn8dAAIQAAgJyR4IIAAXAgAQAAgJyR4IIAAXAgAAAA==.Beeflomein:BAAALgADCgEJAQAAAA==.Beroan:BAAALgADCgYJBgAAAA==.',
Bi='Bigcøøkie:BAAALgAECgQJBAAAAA==.Bighealin:BAAALgAECgcJCwAAAA==.Bigjim:BAABLgAECn8WAAMLAAkJKh74MwA8AgALAAkJKh74MwA8AgAMAAEJNQRXbQA6AAAAAA==.Biglul:BAAALgAFFAIJAgABLgAFFAQJEwAYAP4jAA==.Bigolcrities:BAAALgAECgYJCAAAAA==.Bivivi:BAAALgAECgYJEgAAAA==.',
Bj='Bjorn:BAAALgADCgQJBAAAAA==.',
Bl='Blackmagma:BAAALgAECgQJBwABLgAECggJIQAZAAIaAA==.Blackpiink:BAAALgAFFAEJAQAAAA==.Blackppink:BAACLgAFFH8RAAIJAAQJpB6aEQBlAQAJAAQJpB6aEQBlAQAuAAQKfygAAgkACQlEHIcLAMYCAAkACQlEHIcLAMYCAAAA.Blackppinkk:BAAALgAFFAIJAgAAAA==.Bladefi:BAABLgAECn8lAAMVAAgJESY6AgAGAwAVAAgJESY6AgAGAwAOAAgJ8R1pPgD7AQAAAA==.Blamo:BAABLgAECn8qAAIEAAgJUBbdIQDzAQAEAAgJUBbdIQDzAQAAAA==.Blesedtogoon:BAAALgAECgMJBQAAAA==.Bloodbunny:BAAALgAECgYJDAAAAA==.Bluddbeard:BAAALgAECgkJCwAAAA==.',
Bm='Bmoneycuh:BAACLgAFFH8KAAILAAMJ2xZUSgDqAAALAAMJ2xZUSgDqAAAuAAQKfyAAAgsACAnvHRseADICAAsACAnvHRseADICAAAA.',
Bo='Boozerbear:BAAALgAECgkJAwAAAA==.Bornite:BAAALgAECgEJAQAAAA==.Bosstradamus:BAAALgAECgkJEAABLgAFFAIJAgAIAAAAAA==.Bottombenoit:BAAALgADCgYJCgAAAA==.',
Br='Brewmanfu:BAABLgAECn82AAMFAAkJqB7XCACuAgAFAAkJqB7XCACuAgAGAAUJdQkVXQCcAAAAAA==.Brewmaster:BAAALgAECgEJAQAAAA==.Brickaton:BAABLgAECn8gAAIQAAgJkhT+MQDCAQAQAAgJkhT+MQDCAQAAAA==.Brickdrag:BAAALgADCgYJBgABLgAECggJIAAQAJIUAA==.Brickpanda:BAAALgAECgMJAwAAAA==.Brionaimina:BAAALgADCgQJBAAAAA==.Brocknor:BAABLgAECn8qAAIaAAgJ8hxMCAAaAgAaAAgJ8hxMCAAaAgAAAA==.Brook:BAAALgADCgcJBwAAAA==.Brucebanners:BAAALgAECgEJAgABLgAFFAQJCwAOANQOAA==.Bruiseli:BAABLgAECn8fAAMbAAgJCwQONADyAAAbAAgJCwQONADyAAAGAAMJTALNbwBTAAAAAA==.Brujilda:BAAALgAECgYJDwABLgAECgcJFwAcAMsMAA==.Brèdren:BAACLgAFFH8LAAIFAAQJ3xaMEwAzAQAFAAQJ3xaMEwAzAQAuAAQKf1sAAgUACQmgI48BAJQDAAUACQmgI48BAJQDAAAA.Brüh:BAAALgAECggJDAAAAA==.',
Bu='Bucklebury:BAAALgADCgEJAQAAAA==.Bullogna:BAAALgAECgIJAgAAAA==.Burbon:BAAALgADCgYJCAABLgAECggJLAAGAHIkAA==.Burstinatrix:BAAALgADCgEJAQAAAA==.Burtina:BAAALgAECgMJBAAAAA==.Butterdtoast:BAEBLgAECn8aAAIGAAgJvhL2GwB+AQAGAAgJvhL2GwB+AQAAAA==.Buzzrlok:BAAALgAECgQJCQAAAA==.',
['Bë']='Bëâst:BAAALgAECgIJAgAAAA==.',
Ca='Caboose:BAABLgAECn8nAAQdAAgJxR6WAgBqAgAdAAcJxR6WAgBqAgAeAAMJaAp6GgHKAAAWAAMJgBFQCQC+AAAAAA==.Cadius:BAAALgADCgMJAwAAAA==.Caimera:BAAALgAECgEJAQAAAA==.Caledor:BAAALgAECgMJBAAAAA==.Calindrel:BAABLgAECn8hAAIYAAgJHgU8PAADAQAYAAgJHgU8PAADAQAAAA==.Calita:BAAALgADCgYJBgAAAA==.Caraway:BAAALgAECgcJCwAAAA==.Carcus:BAAALgADCggJCAAAAA==.Carysa:BAAALgADCgcJFAAAAA==.',
Ce='Celebrindal:BAAALgADCgkJHQAAAA==.Celson:BAAALgAECgEJAQAAAA==.Celticlore:BAAALgAECgQJBgAAAA==.Cerrvantes:BAAALgADCgMJAwAAAA==.Cesarius:BAAALgAECgYJEwAAAA==.',
Ch='Chalida:BAAALgADCgkJCQAAAA==.Chappellroan:BAAALgAECgQJBAAAAA==.Charlemange:BAAALgADCgMJAwAAAA==.Charvein:BAAALgAECgQJBAAAAA==.Chernaboz:BAABLgAECn8bAAIMAAgJnRbBBQC5AQAMAAgJnRbBBQC5AQAAAA==.Chevelot:BAAALgAECgMJAwAAAA==.Chibbo:BAABLgAECn8fAAIfAAkJIghODgBwAQAfAAkJIghODgBwAQAAAA==.Chiblet:BAAALgAECgIJAgAAAA==.Chiggbithia:BAAALgAFFAEJAQAAAA==.Chillblain:BAAALgADCgEJAQAAAA==.Chioma:BAAALgADCgYJBgABLgAECggJLQAcAKcgAA==.Chippendale:BAAALgADCgkJGwAAAA==.Choda:BAAALgADCgUJBQAAAA==.Chondre:BAABLgAECn8fAAILAAgJfh/QGABVAgALAAgJfh/QGABVAgAAAA==.Chrigs:BAAALgAECgYJBwAAAA==.Chrispbacon:BAAALgADCgYJBgAAAA==.',
Ci='Citrogen:BAAALgAECgYJCwAAAA==.',
Cl='Clickityclak:BAAALgADCgIJAgAAAA==.',
Co='Colin:BAAALgADCgMJAgABLgAECgkJDgAIAAAAAA==.Combustdeez:BAAALgADCgUJBQABLgAFFAgJEgALAFUgAA==.Conrad:BAAALgADCgUJBQAAAA==.Copperheadj:BAAALgAECgMJAwABLgAECgcJFAAHAKYJAA==.Copperknight:BAABLgAECn8UAAIHAAcJpglYqQDQAAAHAAcJpglYqQDQAAAAAA==.Corenthos:BAABLgAECn8zAAMHAAgJnSJjGABxAgAHAAgJNyJjGABxAgAgAAgJKx1XCQAvAgAAAA==.Cornelia:BAAALgAECgQJBAABLgAECgkJNAANAP0UAA==.Cortanna:BAAALgADCgYJDgAAAA==.',
Cr='Cranker:BAAALgAECgMJCwAAAA==.Crashedot:BAAALgAECgQJCwAAAA==.Crazymoron:BAAALgADCggJCAAAAA==.Creselia:BAABLgAECn8YAAIeAAYJGAovogD9AAAeAAYJGAovogD9AAAAAA==.Criminel:BAAALgADCgEJAQAAAA==.Cropduzzter:BAAALgADCgQJBAAAAA==.Crovax:BAAALgAECgEJAQAAAA==.Crum:BAABLgAECn8bAAMDAAgJlgh4MQD7AAADAAgJfwh4MQD7AAAhAAMJ+AS5OwBAAAAAAA==.Crumdumpster:BAAALgAECgIJAgABLgAECggJGwADAJYIAA==.Cryptnotic:BAAALgADCgIJAgAAAA==.',
Cu='Cuddlerz:BAAALgAECgIJAgAAAA==.Cutthrøat:BAAALgAECgYJCwAAAA==.',
Cy='Cypherrellik:BAAALgAECgcJEAABLgAECggJGgAVADIRAA==.',
['Câ']='Câp:BAAALgAECgcJCQAAAA==.',
Da='Dablackmasta:BAABLgAECn8XAAIYAAgJbg7KPACxAQAYAAgJbg7KPACxAQAAAA==.Daftfunk:BAAALgAECgUJBQAAAA==.Dagthunderer:BAAALgAECgYJCwAAAA==.Daidonks:BAAALgAECgMJBAAAAA==.Dakkenrahl:BAAALgAECgYJDgAAAA==.Dalistra:BAAALgAECgIJBQAAAA==.Dalweaver:BAAALgAECgEJAwABLgAECgIJBQAIAAAAAA==.Dalzz:BAAALgADCgYJBgABLgAECgIJBQAIAAAAAA==.Damage:BAAALgADCgEJAQAAAA==.Dantar:BAAALgADCgQJBAAAAA==.Dantes:BAAALgADCgkJFAAAAA==.Dar:BAAALgAECgYJCwAAAA==.Darkaires:BAAALgAECgkJBgAAAA==.Darkflame:BAABLgAECn8fAAIQAAgJxhmUKADsAQAQAAgJxhmUKADsAQAAAA==.Darksidedbro:BAAALgADCgkJEQAAAA==.Darthvaeder:BAAALgAECgUJDAAAAA==.Davee:BAAALgADCgcJBwAAAA==.',
Dc='Dcpt:BAAALgADCggJFQAAAA==.',
De='Deadgeinside:BAAALgAECgcJCwAAAA==.Deadgnome:BAAALgAECgIJAgABLgAECggJHwAbALgQAA==.Deathrose:BAAALgADCgkJCgAAAA==.Deathstomper:BAAALgAECgQJBgAAAA==.Delnarian:BAABLgAECn8sAAIPAAkJbhxQGgBlAgAPAAkJbhxQGgBlAgAAAA==.Demondono:BAABLgAECn8nAAIVAAgJbBTaEQCoAQAVAAgJbBTaEQCoAQAAAA==.Demonsnake:BAAALgAECgEJAQAAAA==.Desmorphia:BAAALgAECgEJAwAAAA==.Destruir:BAAALgADCgkJCgAAAA==.Desy:BAAALgADCgQJBAABLgAECggJFwALAIIiAA==.Dethomonic:BAAALgADCgkJCQAAAA==.Devomo:BAABLgAECn8xAAIOAAcJ2yPCFgBNAgAOAAcJ2yPCFgBNAgAAAA==.Devoutsquirl:BAAALgADCgYJBgABLgAECggJFgAiAAUgAA==.Deyedora:BAAALgAECggJDwAAAA==.Deyjavaknadi:BAAALgADCgMJAwAAAA==.',
Di='Diegodruida:BAAALgADCgUJBQAAAA==.Dilligafnope:BAAALgADCgkJJAAAAA==.Dinkster:BAABLgAECn8iAAMDAAgJNgvkKQAoAQADAAgJNgvkKQAoAQAEAAMJ0gSPsABkAAAAAA==.Dinohunter:BAABLgAECn8bAAIQAAgJHCKUEgBzAgAQAAgJHCKUEgBzAgAAAA==.Dinokat:BAAALgADCgUJBgABLgAECgkJEAAIAAAAAA==.Dirtslinger:BAAALgAECgUJDAAAAA==.Disabler:BAACLgAFFH8SAAMLAAgJVSCBAADGAgALAAgJVSCBAADGAgAMAAEJBxWKFQBUAAAuAAQKfy0AAwsACQlGJu4AAHkDAAsACQlGJu4AAHkDAAwAAQnvIdtZAGEAAAAA.Discotits:BAAALgAECgEJAQAAAA==.',
Do='Dobyclease:BAAALgAECgMJAwAAAA==.Dojob:BAAALgAECgMJAwAAAA==.Dokesa:BAABLgAECn8YAAMHAAcJ7R7nQwAqAgAHAAcJ7R7nQwAqAgAgAAEJlwzoRwApAAAAAA==.Dolfratt:BAAALgAECgkJEgABLgAECgkJNgAFAKgeAA==.Dooknukem:BAAALgADCgYJBgAAAA==.Doomguard:BAAALgAECgMJAwAAAA==.Dorimane:BAAALgAECggJHQAAAQ==.Dorimonk:BAAALgAECgQJBAABLgAECggJHQAIAAAAAQ==.Dorlock:BAABLgAECn8hAAIKAAgJRggWDQAbAQAKAAgJRggWDQAbAQAAAA==.Dortivi:BAAALgAECgUJBQAAAA==.Dotdôtdot:BAAALgADCgIJAgAAAA==.Dotrastraez:BAAALgADCgIJAgAAAA==.Dotvader:BAAALgAECgcJDQAAAA==.',
Dr='Dragonrend:BAAALgAECgcJCgAAAA==.Draklee:BAAALgAECgEJAgAAAA==.Draxestraza:BAAALgADCgcJFwAAAA==.Draykey:BAAALgAECgQJBQABLgAECggJMwAEANQdAA==.Draykeyy:BAABLgAECn8zAAIEAAgJ1B35EgBwAgAEAAgJ1B35EgBwAgAAAA==.Dred:BAAALgAECgEJAQAAAA==.Dreddk:BAAALgAFFAEJAQAAAA==.Dredwarrior:BAABLgAECn8aAAMaAAkJsBEmIgDyAAAYAAYJ+xALXgA3AQAaAAYJog4mIgDyAAAAAA==.Drenlei:BAAALgAECggJDgAAAA==.Drood:BAAALgAECgEJAQAAAA==.Drotara:BAABLgAECn8kAAMQAAgJzR78EgBwAgAQAAgJzR78EgBwAgABAAMJ3xNiLgDZAAAAAA==.Drprodigy:BAABLgAECn8iAAIOAAkJThVePAADAgAOAAkJThVePAADAgAAAA==.Drunkbaby:BAACLgAFFH8HAAIPAAMJux1DLQAhAQAPAAMJux1DLQAhAQAuAAQKfxQAAg8ACQnxIKoRAAQDAA8ACQnxIKoRAAQDAAAA.',
Dy='Dynasty:BAAALgAECgQJCgAAAA==.Dyrcyn:BAAALgAECgEJAQAAAA==.',
['Dà']='Dàddy:BAAALgAECgQJBwAAAA==.Dànger:BAABLgAECn8WAAIBAAkJURlmCABdAgABAAkJURlmCABdAgAAAA==.',
Ed='Edrius:BAAALgAECgUJBQAAAA==.Edroh:BAABLgAECn8jAAIeAAgJgQnKcgBVAQAeAAgJgQnKcgBVAQAAAA==.',
Eh='Ehsera:BAAALgADCgUJBgAAAA==.',
Ei='Eidur:BAABLgAECn8YAAMjAAkJBRlaCQCsAQAjAAkJtBhaCQCsAQAkAAUJ7BZfPAA4AQAAAA==.',
El='Elando:BAAALgAECgQJBAAAAA==.Elegies:BAACLgAFFH8KAAIOAAUJVgu/NAAGAQAOAAUJVgu/NAAGAQAuAAQKf0MAAg4ACQkzIGQPAIgCAA4ACQkzIGQPAIgCAAAA.Elemefayoh:BAAALgAECgcJCwAAAA==.Elfater:BAAALgAECgMJAwAAAA==.Eliarace:BAAALgADCgMJAwAAAA==.Eljeffesan:BAAALgADCgcJFwAAAA==.Ellwynd:BAAALgADCgUJBQABLgAECgcJFAAlAA4hAA==.Elspeth:BAAALgADCgYJBgABLgAECggJJAAQAM0eAA==.Elythria:BAAALgAECgQJBwAAAA==.',
Em='Emagonadye:BAACLgAFFH8TAAIbAAUJfyAtCgCAAQAbAAUJfyAtCgCAAQAuAAQKfxsAAxsACAm2JFIEAEcDABsACAm2JFIEAEcDAAYAAgkLH8FBAKsAAAAA.Emerey:BAAALgADCgkJCgAAAA==.Emlee:BAAALgADCgIJAgAAAA==.Emporersmaug:BAAALgADCgEJAQAAAA==.',
En='Endgamer:BAAALgAECgYJBgAAAA==.Endugu:BAABLgAECn8fAAIeAAgJhBDoVQCZAQAeAAgJhBDoVQCZAQAAAA==.Enflamee:BAABLgAECn8lAAQeAAkJZSG1CQD/AgAeAAkJZSG1CQD/AgAWAAEJKRfnCwBBAAAdAAEJUwzOHQA2AAAAAA==.Enforcer:BAABLgAECn8iAAMLAAgJvxvpPACoAQALAAcJVxvpPACoAQAMAAMJBRXcOgDJAAAAAA==.Engath:BAAALgAECgYJDAABLgAECgkJJQAeAGUhAA==.',
Er='Erosonia:BAAALgAECgQJDQAAAA==.Erso:BAAALgADCgYJCAAAAA==.',
Es='Espresso:BAAALgAECgcJEAAAAA==.',
Et='Eternalpaín:BAACLgAFFH8GAAIPAAIJUxRlVAClAAAPAAIJUxRlVAClAAAuAAQKfyoAAg8ACAn9HWghADwCAA8ACAn9HWghADwCAAAA.',
Ev='Evanee:BAABLgAECn8VAAIJAAgJdRhsLACsAQAJAAgJdRhsLACsAQAAAA==.Evanrude:BAAALgAECgUJBwAAAA==.',
Ez='Ezykeul:BAAALgAECgYJDgAAAA==.',
Fa='Fal:BAABLgAECn8WAAMQAAkJOBGCTwB6AQAQAAgJVhGCTwB6AQACAAUJVQgLWwDXAAAAAA==.Falcyon:BAAALgADCgMJAwAAAA==.Fallenson:BAAALgAECgEJBAAAAA==.',
Fe='Felbrooks:BAAALgADCgkJFQAAAA==.Felmommy:BAAALgADCgcJAQAAAA==.Felsông:BAAALgADCgcJBwAAAA==.Fendretta:BAABLgAECn8hAAIQAAgJrRYoNAC6AQAQAAgJrRYoNAC6AQAAAA==.',
Fi='Firefawkes:BAAALgAECgYJCAAAAA==.Fistbump:BAAALgADCgYJDAAAAA==.Fivepiece:BAAALgADCgcJBwAAAA==.Fixzie:BAABLgAECn8aAAIYAAgJbg4OJwByAQAYAAgJbg4OJwByAQAAAA==.',
Fl='Flah:BAAALgAFFAEJAQAAAA==.Flip:BAAALgAECgcJBwAAAA==.Flizrak:BAABLgAECn8aAAIYAAgJkiNfDQBRAgAYAAgJkiNfDQBRAgABLgAFFAcJIAAeALIeAA==.',
Fo='Footsteps:BAAALgAECgYJBgAAAA==.Forestflex:BAAALgAECgYJBgAAAA==.Foxstrazagos:BAAALgADCgkJCwAAAA==.',
Fr='Freakopath:BAAALgAECgQJCQAAAA==.Friggnar:BAAALgADCgYJBwAAAA==.Frostsalad:BAAALgADCgQJBAAAAA==.Frostynugz:BAAALgADCgYJCQAAAA==.',
Fu='Fulta:BAABLgAECn8tAAICAAgJER2eBAAjAgACAAgJER2eBAAjAgAAAA==.',
Fy='Fyra:BAAALgAECgIJAgABLgAFFAQJDgAPAE4KAA==.',
['Fí']='Fírnen:BAAALgAECgQJBwAAAA==.',
Ga='Gailz:BAAALgADCgQJBAAAAA==.Galadoril:BAAALgADCgIJAgAAAA==.Gammb:BAAALgAECgEJAQAAAA==.Garadin:BAABLgAECn8nAAIDAAgJPRWlGACuAQADAAgJPRWlGACuAQAAAA==.Garcona:BAABLgAFFH8GAAIHAAIJ6xq3eAC1AAAHAAIJ6xq3eAC1AAAAAA==.Garnok:BAAALgAECgEJAQAAAA==.Garqman:BAAALgADCgUJBQAAAA==.Garwa:BAAALgAECgUJEwAAAA==.',
Ge='Geniver:BAAALgAECgYJDwAAAA==.Gerken:BAAALgAECgIJAgAAAA==.Gerkenator:BAAALgAECgcJCwAAAA==.Gerla:BAABLgAECn8iAAMPAAgJ6BFcagBOAQAPAAcJBhRcagBOAQAcAAgJEQeRGgDtAAAAAA==.',
Gh='Ghettoshout:BAAALgAECgMJBAAAAA==.',
Gi='Gialania:BAABLgAECn8jAAMDAAgJpQprKQAqAQADAAgJpQprKQAqAQAEAAMJjAB44wAiAAAAAA==.Gilgameshh:BAAALgADCgkJEQAAAA==.Girthbrook:BAAALgADCgcJCAAAAA==.Girthbrooks:BAAALgADCgQJBAAAAA==.Girthtrude:BAABLgAECn8oAAIOAAkJxQ2LPQCFAQAOAAkJxQ2LPQCFAQAAAA==.',
Gl='Glaivertoss:BAAALgAECggJCgAAAA==.Glorythighs:BAAALgADCgEJAQAAAA==.Glycerol:BAAALgADCgUJBQAAAA==.',
Go='Goblincox:BAABLgAECn8aAAIeAAcJ1BM/aABsAQAeAAcJ1BM/aABsAQAAAA==.Gomory:BAAALgAECgYJDwAAAA==.Gondark:BAAALgAECgQJBwAAAA==.Goobly:BAABLgAECn8nAAIkAAcJmx02EwC2AQAkAAcJmx02EwC2AQAAAA==.Gooseblade:BAAALgADCgUJBQAAAA==.Goregrimm:BAAALgAECgUJCQAAAA==.Gorgoz:BAAALgADCgEJAQAAAA==.Gorgrim:BAAALgADCgMJAwAAAA==.',
Gr='Gregòr:BAAALgAECgkJBQAAAA==.Gretchen:BAABLgAECn87AAMHAAgJORrnMAD0AQAHAAgJORrnMAD0AQAgAAUJtgqwNgCMAAAAAA==.Greywing:BAAALgAECggJEwAAAA==.Greywolf:BAABLgAECn8hAAIJAAkJXBmuFwBYAgAJAAkJXBmuFwBYAgAAAA==.Grezin:BAAALgAECgEJAQABLgAECgQJCQAIAAAAAA==.Grimlight:BAABLgAFFH8LAAIPAAQJ4SDjEgBxAQAPAAQJ4SDjEgBxAQABLgAFFAgJFgAHAP8XAA==.Grimshaw:BAAALgAECgYJBgAAAA==.Grimtorr:BAAALgADCgMJAwAAAA==.Ground:BAAALgAECgYJCQAAAA==.Grymlee:BAAALgAECgYJEQAAAA==.Grëgor:BAAALgAECgQJBAAAAA==.',
Gu='Guinènvere:BAAALgAECgYJEAAAAA==.',
['Gä']='Gärry:BAAALgAECgEJAQAAAA==.',
['Gö']='Gökù:BAAALgAECgEJAQAAAA==.',
Ha='Haedes:BAAALgAECgQJBAABLgAECgYJFAAFAFURAA==.Haktori:BAAALgAECgcJEwAAAA==.Hammerknee:BAABLgAECn8ZAAMmAAgJtxhVKgDfAQAmAAgJtxhVKgDfAQAPAAMJcwoJ8ABrAAAAAA==.Hariku:BAAALgAECgQJCgAAAA==.Harleii:BAAALgAECgcJDgAAAA==.Harlequins:BAAALgAECgEJBAAAAA==.Harmonix:BAAALgAECgkJBgAAAA==.Harrow:BAABLgAECn8VAAIHAAgJhhhqNADmAQAHAAgJhhhqNADmAQAAAA==.Hastler:BAAALgADCgkJCQAAAA==.Hatthorned:BAAALgADCgEJAQAAAA==.Hawt:BAAALgAECgEJBQAAAA==.Haxx:BAAALgAECgEJAQAAAA==.',
He='Hearge:BAABLgAECn8dAAMmAAkJzhtVDQCuAgAmAAkJzhtVDQCuAgAPAAYJVQgRuwAQAQAAAA==.Heckatae:BAABLgAECn8aAAIeAAYJuArwnAAGAQAeAAYJuArwnAAGAQAAAA==.Hellborne:BAAALgADCgIJAgAAAA==.Hellhawk:BAABLgAECn8hAAImAAgJQxVZGgDmAQAmAAgJQxVZGgDmAQAAAA==.Helwe:BAAALgAECgMJBQAAAA==.Heptandew:BAAALgAECgcJDgAAAA==.Hetepiir:BAAALgAECgQJBAABLgAFFAQJDgAPAE4KAA==.Hexmon:BAAALgAECgEJAwABLgAECgYJDgAIAAAAAA==.',
Hi='Hikkio:BAAALgADCgMJAwAAAA==.',
Ho='Holycheeks:BAAALgADCgYJBgAAAA==.Holychib:BAAALgAECgYJCAAAAA==.Holypho:BAAALgADCgYJDAAAAA==.Holysheet:BAAALgAECgYJCAAAAA==.Holystan:BAABLgAECn8UAAIPAAYJ/QxXnQDvAAAPAAYJ/QxXnQDvAAAAAA==.Hondoe:BAAALgAECgQJBQAAAA==.Honorable:BAAALgADCgEJAQABLgAECgkJNgAFAKgeAA==.Hoshino:BAAALgAECgYJCQABLgAECgYJDgAIAAAAAA==.Hoshiyoru:BAAALgADCggJFAAAAA==.Houki:BAABLgAECn8mAAIPAAgJNAmGcgA9AQAPAAgJNAmGcgA9AQAAAA==.',
Hp='Hpylorii:BAAALgAECgYJEgAAAA==.',
Ht='Htownhunter:BAAALgAECgQJCAAAAA==.Htownprot:BAABLgAFFH8JAAIPAAQJZiG4DgCHAQAPAAQJZiG4DgCHAQAAAA==.',
Hu='Hungovertank:BAACLgAFFH8XAAIbAAYJJiIBBQDCAQAbAAYJJiIBBQDCAQAuAAQKfzEAAhsACAmUJQ8EAEwDABsACAmUJQ8EAEwDAAAA.Hungzilla:BAABLgAECn8iAAMTAAkJyByPCACPAgATAAkJyByPCACPAgASAAMJvw+/LgCiAAAAAA==.Huntered:BAAALgADCgMJAgAAAA==.Huntfromhell:BAABLgAECn8hAAMUAAgJJCPiAQC3AgAUAAgJJCPiAQC3AgAVAAYJUxyqFACFAQAAAA==.Hurkano:BAAALgADCgUJCQAAAA==.',
Ig='Ignisfatuus:BAAALgAECgcJEAAAAA==.',
Ik='Ikurei:BAAALgADCggJCAAAAA==.',
Il='Ilarion:BAAALgAECgQJBAAAAA==.Illio:BAAALgAECgUJCAAAAA==.Illyasviel:BAAALgAECgMJBQAAAA==.',
Im='Imarea:BAABLgAECn8hAAIeAAgJTAbuggA1AQAeAAgJTAbuggA1AQAAAA==.Impirious:BAABLgAECn8nAAMgAAkJTg1WFQBpAQAgAAkJTg1WFQBpAQAHAAQJpQaA6ACvAAAAAA==.Imppimp:BAAALgAECgYJCgAAAA==.Imtryntotank:BAABLgAECn8kAAImAAgJPQtiMgA6AQAmAAgJPQtiMgA6AQAAAA==.Imyx:BAABLgAECn8lAAIHAAgJjhjCPADIAQAHAAgJjhjCPADIAQAAAA==.',
In='Infamuspikel:BAABLgAECn8UAAMHAAkJGhhbZQDEAQAHAAkJsRNbZQDEAQAgAAMJPBxdIwDiAAAAAA==.Infel:BAAALgAECgkJDQAAAA==.Inkkish:BAAALgAECgYJEgAAAA==.Innovates:BAAALgAECgQJDAAAAA==.Innowar:BAAALgADCgYJBgAAAA==.Interstellar:BAAALgAECgYJBgAAAA==.Intervene:BAAALgADCgMJAwABLgAFFAIJBgAPAFMUAA==.Invictus:BAABLgAECn8lAAIeAAgJeQ5OYQB8AQAeAAgJeQ5OYQB8AQAAAA==.',
Io='Iota:BAAALgAECgYJEwAAAA==.',
Ir='Irminarae:BAABLgAECn8qAAMLAAgJFxaiNADHAQALAAgJFxaiNADHAQAMAAEJPgNBegAoAAAAAA==.',
Is='Isa:BAAALgADCgEJAQAAAA==.Isaßeau:BAAALgAECggJEAAAAA==.',
Ja='Jandoar:BAABLgAECn8lAAIeAAgJ4wZ2ggA2AQAeAAgJ4wZ2ggA2AQAAAA==.Jarlen:BAAALgADCgcJDAAAAA==.Jasmil:BAAALgADCgUJCAAAAA==.Jaylah:BAAALgADCgUJBgAAAA==.',
Je='Jeohr:BAAALgAECgEJAQAAAA==.Jezala:BAAALgADCgkJKwAAAQ==.',
Ji='Jiq:BAAALgADCgUJBwAAAA==.',
Jo='Johli:BAAALgADCgkJCQAAAA==.',
['Jö']='Jördyn:BAAALgADCgcJCgAAAA==.',
Ka='Kabilos:BAAALgAECgcJEAAAAA==.Kaboòm:BAACLgAFFH8FAAIeAAMJwgd/YgDYAAAeAAMJwgd/YgDYAAAuAAQKfyEAAh4ACAlxEKt9ANYBAB4ACAlxEKt9ANYBAAAA.Kaedian:BAAALgADCgQJBAABLgAECggJLAAGAHIkAA==.Kaelthazad:BAAALgADCgEJAQAAAA==.Kagamai:BAAALgADCgUJBQAAAA==.Kagaramar:BAAALgAECgEJAQAAAA==.Kalesmora:BAABLgAECn8nAAIaAAgJBhwnCAAdAgAaAAgJBhwnCAAdAgAAAA==.Kaluu:BAAALgAECgEJAQABLgAECgIJBAAIAAAAAA==.Kamikaze:BAABLgAECn8oAAIVAAgJXBC0FQB2AQAVAAgJXBC0FQB2AQAAAA==.Kaorî:BAAALgADCgEJAQAAAA==.Karlov:BAABLgAECn8SAAInAAcJBhPUJQCpAQAnAAcJBhPUJQCpAQAAAA==.Karthis:BAAALgAECgEJAQAAAA==.Kassima:BAAALgADCgEJAQAAAA==.Katebush:BAAALgAECgIJAgAAAA==.Kaydahlia:BAAALgAECgUJBgAAAA==.',
Ke='Keelmyeve:BAAALgAECgQJCQAAAA==.Keheo:BAAALgAECgEJAQAAAA==.Kelastalan:BAAALgADCgIJAgAAAA==.Kelithiena:BAAALgADCgYJDgAAAA==.Keynn:BAAALgADCgIJAgABLgAECggJLAAGAHIkAA==.',
Kh='Khaziel:BAAALgAECgUJBQAAAA==.Kheims:BAAALgAECgQJCAAAAA==.Khri:BAAALgAECgIJAgAAAA==.Khuzdul:BAAALgAECgEJAQAAAA==.',
Ki='Kidcat:BAAALgAECgMJBQAAAA==.Kiddemon:BAAALgADCgcJCAAAAA==.Killduran:BAAALgAFFAIJAwAAAA==.Kimiyo:BAAALgADCgcJCAAAAA==.Kimpossumble:BAAALgAECgMJAwAAAA==.Kinetic:BAAALgADCgkJEAAAAA==.Kirasha:BAAALgADCgIJAgAAAA==.Kitom:BAAALgAFFAEJAQAAAA==.Kiwia:BAAALgAECgEJAQABLgAECggJJQALAJ8jAA==.',
Kl='Kleopatra:BAABLgAECn8oAAMGAAcJcQmANQDcAAAGAAcJfAaANQDcAAAbAAQJJAtkWABpAAAAAA==.Klunt:BAAALgADCgcJCAABLgAECggJFwASAHwcAA==.',
Kn='Knitehunt:BAAALgAECgUJBQAAAA==.Knives:BAAALgAECgQJCwAAAA==.',
Ko='Kochiyo:BAAALgADCgcJHQAAAA==.Korgal:BAAALgAECgIJAgAAAA==.Kortar:BAAALgAECgQJBAAAAA==.Kotros:BAAALgAECggJDwAAAA==.',
Kr='Kracked:BAAALgAECgMJBAABLgAECgYJEwAIAAAAAA==.Kreigan:BAAALgADCgkJCQAAAA==.Krelid:BAAALgADCgkJEAABLgAECggJIQAFAAkgAA==.Krellyroll:BAABLgAECn8hAAMFAAgJCSAVCAC9AgAFAAgJCSAVCAC9AgAGAAIJZRMrZAB9AAAAAA==.Krelthyr:BAAALgADCgkJDwABLgAECggJIQAFAAkgAA==.Krumm:BAABLgAECn8yAAIiAAgJ7Av0GAAkAQAiAAgJ7Av0GAAkAQAAAA==.Krumpas:BAAALgADCgcJDgAAAA==.Kryvea:BAAALgADCggJCAAAAA==.',
Ku='Kuhne:BAAALgAECgMJBgAAAA==.Kurno:BAAALgAECgEJAQAAAA==.Kuromie:BAAALgADCgIJAgABLgAFFAEJAQAIAAAAAA==.',
Ky='Kyboom:BAAALgADCgYJBgAAAA==.',
['Kà']='Kàlluu:BAAALgAECgIJBAAAAA==.',
['Kñ']='Kñightboat:BAABLgAECn8aAAIUAAgJXBF9CgBjAQAUAAgJXBF9CgBjAQAAAA==.',
La='Ladeiene:BAAALgAECgIJAgAAAA==.Laelwyn:BAAALgAECgYJDQAAAA==.Laelynd:BAAALgAECgEJAQAAAA==.Lardna:BAAALgAECgEJAQAAAA==.',
Le='Leathermommy:BAAALgAECgcJEwAAAA==.Leges:BAABLgAECn8lAAMLAAgJnyNVDQCvAgALAAgJnyNVDQCvAgAMAAEJAAAgPQAAAAAAAA==.Lehong:BAABLgAECn8rAAMbAAgJkx2uCgBPAgAbAAgJkx2uCgBPAgAGAAEJWgffgwAsAAAAAA==.Lejion:BAAALgAFFAIJAwAAAA==.Lethariel:BAAALgAECgYJCQAAAA==.Lethas:BAABLgAECn8iAAIHAAgJFB+hGwBeAgAHAAgJFB+hGwBeAgAAAA==.',
Li='Liandrys:BAAALgAECgUJCgAAAA==.Lightrising:BAAALgAECgIJBAAAAA==.Lilfreya:BAAALgADCgQJBAAAAA==.Lilmonstrman:BAABLgAECn8sAAMeAAgJgBS6TwCqAQAeAAgJgBS6TwCqAQAdAAYJzhHSCABjAQAAAA==.Limbbiscuit:BAAALgAECgQJBAAAAA==.Linger:BAABLgAECn8XAAIHAAgJ5BgibgCtAQAHAAgJ5BgibgCtAQAAAA==.Linnet:BAAALgAECgEJAQAAAA==.Litany:BAABLgAECn8oAAImAAgJvxA2JQCRAQAmAAgJvxA2JQCRAQAAAA==.Liya:BAABLgAECn8lAAMKAAgJAxO7CgCQAQAKAAcJpxW7CgCQAQALAAcJ0wnWcgAYAQAAAA==.',
Lo='Lokith:BAAALgAECgEJAQAAAA==.Lorilai:BAAALgAECgUJCQAAAA==.Loroke:BAAALgADCgkJCwAAAA==.Lots:BAAALgAECgQJBQAAAA==.Loxx:BAAALgAECgEJAgAAAA==.',
Lu='Lucith:BAAALgADCgcJCQAAAA==.Lul:BAACLgAFFH8TAAIYAAQJ/iNDBAClAQAYAAQJ/iNDBAClAQAuAAQKfywAAxgABwkNJWoQAM4CABgABwkFJWoQAM4CABoABgltHb0KAPgBAAAA.Lumpthumb:BAAALgADCgMJAwAAAA==.Lunaaru:BAAALgAECgMJAwABLgAECgkJKgAEABQgAA==.Lunamay:BAABLgAECn8qAAMEAAkJFCBzDwC9AgAEAAkJFCBzDwC9AgADAAQJSw4ESgCNAAAAAA==.',
['Lð']='Lðvergirl:BAABLgAECn8WAAMDAAcJyg6GMQD7AAADAAcJ6AmGMQD7AAAhAAQJmRCXIQC+AAAAAA==.',
['Lò']='Lòck:BAAALgAECgEJAQAAAA==.',
['Ló']='Lóki:BAAALgADCgEJAQAAAA==.',
Ma='Machotaco:BAAALgADCgMJAwAAAA==.Maddieketh:BAAALgADCgMJAwAAAA==.Maeghor:BAACLgAFFH8GAAIeAAQJJwNEUAAGAQAeAAQJJwNEUAAGAQAuAAQKfx4AAh4ABwlZF4aFAMYBAB4ABwlZF4aFAMYBAAAA.Maelleam:BAAALgAECgQJBAAAAA==.Maelman:BAAALgADCgcJBwAAAA==.Maelsham:BAAALgADCgcJBwAAAA==.Magicash:BAABLgAECn8UAAIeAAYJkhp5agBnAQAeAAYJkhp5agBnAQAAAA==.Magistella:BAAALgAECgYJBgAAAA==.Magmadh:BAAALgAECgIJBgAAAA==.Malignantt:BAABLgAECn8jAAIgAAgJdxBXGQA8AQAgAAgJdxBXGQA8AQAAAA==.Manastress:BAAALgAECgQJBQAAAA==.Mapletoast:BAAALgADCgQJBAAAAA==.Mareanette:BAAALgAECgcJCAABLgAECggJHwAbALgQAA==.Maskerade:BAAALgADCgUJBQAAAA==.Maurphious:BAAALgAECgQJBwAAAA==.Mavraela:BAAALgADCgYJEQAAAA==.',
Me='Meenhoe:BAAALgADCgUJBQAAAA==.Melee:BAAALgADCgcJBwAAAA==.Meleena:BAAALgADCgEJAQAAAA==.Melinola:BAAALgAECgMJCgAAAA==.Mellecarde:BAAALgAECgYJBwAAAA==.Melodrama:BAAALgAECgcJCwAAAA==.Messadin:BAABLgAECn8ZAAIcAAcJ7RbUFQB0AQAcAAcJ7RbUFQB0AQAAAA==.Metalguard:BAAALgADCgUJBQAAAA==.Methodical:BAAALgADCgIJAgAAAA==.Metri:BAAALgAECgUJDgAAAA==.',
Mi='Michelleyeoh:BAAALgADCgUJBQABLgAECggJGAALAE8aAA==.Michelney:BAAALgAECgUJBQAAAA==.Mikearoni:BAABLgAECn8vAAMTAAgJlhTqIACAAQATAAgJlhTqIACAAQAoAAEJeQH8TQAkAAAAAA==.Mirgaree:BAABLgAECn8hAAIHAAgJOhAfVQB9AQAHAAgJOhAfVQB9AQAAAA==.Mistweaving:BAACLgAFFH8YAAIFAAYJSyWuAgBxAgAFAAYJSyWuAgBxAgAuAAQKfyMAAwUACAlMI04GAPoCAAUACAlMI04GAPoCAAYABAnNFRdMAOIAAAAA.',
Mo='Moistweaver:BAABLgAECn8eAAIFAAkJmxpfFgAQAgAFAAkJmxpfFgAQAgAAAA==.Mommystrasza:BAAALgAECgQJDQAAAA==.Monkfall:BAAALgADCgMJAwABLgAFFAMJBgAHADMEAA==.Monkoreo:BAAALgADCgQJBAAAAA==.Monkwrld:BAABLgAECn8dAAIGAAgJZB18EAB5AgAGAAgJZB18EAB5AgAAAA==.Monty:BAAALgAECgYJDQAAAA==.Moosemode:BAAALgADCgcJBwAAAA==.Mordet:BAAALgAECgQJBAABLgAECggJHQAIAAAAAQ==.Moridane:BAAALgAECgQJBwABLgAECggJHQAIAAAAAQ==.Mormael:BAAALgAECgEJAQAAAA==.',
Mu='Muffinz:BAABLgAECn8fAAIbAAgJuBAiJwA4AQAbAAgJuBAiJwA4AQAAAA==.Multiabuse:BAAALgAECgUJBQAAAA==.',
My='Myau:BAABLgAECn8nAAInAAgJPRjQFADWAQAnAAgJPRjQFADWAQAAAA==.Myera:BAAALgADCgUJBQAAAA==.Mynia:BAABLgAECn8xAAIBAAgJxhLLEwDAAQABAAgJxhLLEwDAAQAAAA==.Mythrius:BAAALgAECgUJCwAAAA==.',
['Mø']='Mørdu:BAAALgAECgYJDgAAAA==.',
Na='Nada:BAAALgAECgUJCgAAAA==.Nano:BAABLgAECn8pAAILAAgJ9RhnKgDyAQALAAgJ9RhnKgDyAQAAAA==.Nardor:BAAALgAECgYJDgAAAA==.Naturelle:BAABLgAECn8WAAMEAAYJPQWLcwCXAAAEAAYJPQWLcwCXAAADAAIJFwFJigAlAAAAAA==.Nautilius:BAAALgADCggJDwAAAA==.Navaani:BAABLgAECn8tAAIcAAgJpyAdBAB4AgAcAAgJpyAdBAB4AgAAAA==.Nazdreg:BAACLgAFFH8KAAILAAQJIwzOPAASAQALAAQJIwzOPAASAQAuAAQKfycAAwsABwn2HZQzAD4CAAsABwn2HZQzAD4CAAwAAQkAAISBAAYAAAAA.Nazgull:BAAALgAECgIJAgAAAA==.',
Ne='Neisa:BAAALgADCgMJAwAAAA==.Nelrae:BAAALgAECgMJAwAAAA==.Nemesicc:BAAALgAECgUJDQAAAA==.Neotoldir:BAABLgAECn8uAAMXAAgJ3h91BAARAgAXAAgJxxt1BAARAgAgAAcJOyBCCwAGAgAAAA==.Nerfdisc:BAAALgAECgcJDAAAAA==.Nerfdruids:BAAALgADCgUJBQAAAA==.Nerozond:BAAALgAECgEJAgAAAA==.Netalli:BAABLgAECn8UAAIeAAgJmyB6JwDUAgAeAAgJmyB6JwDUAgABLgAFFAQJDAAHALgeAA==.Nevershocked:BAABLgAECn8fAAITAAkJqRhjDABPAgATAAkJqRhjDABPAgAAAA==.Nezziee:BAABLgAECn8WAAIYAAcJzg++LQBLAQAYAAcJzg++LQBLAQAAAA==.',
Ni='Nibroc:BAAALgAECgYJCgAAAA==.Nidhoggy:BAABLgAECn8VAAMJAAYJZBvnMwC0AQAJAAYJZBvnMwC0AQAZAAIJ0QUagQBDAAAAAA==.Nife:BAAALgAECgEJAQAAAA==.',
No='Nordie:BAAALgAECgcJEwAAAA==.Noriss:BAAALgAECgEJAgABLgAECggJHQAIAAAAAQ==.Northik:BAABLgAECn8sAAMHAAgJ1yBeHwDFAgAHAAgJ1yBeHwDFAgAgAAYJ8w15IwDhAAAAAA==.Notintheface:BAAALgAECgYJEAAAAA==.',
Nu='Numlock:BAAALgAECgcJEAAAAA==.',
Ny='Nydav:BAABLgAECn8sAAIGAAgJciTOBADOAgAGAAgJciTOBADOAgAAAA==.Nyphithys:BAAALgAECgUJBQAAAA==.Nystallina:BAAALgADCgMJAwAAAA==.',
['Ní']='Níítefall:BAABLgAECn8iAAMUAAkJYx91AwCbAgAUAAgJaR91AwCbAgAOAAYJGhIfXwAaAQABLgAECgkJJQAeAGUhAA==.',
Oa='Oakbreaker:BAAALgAECgQJBwABLgAFFAMJCQAkAJEeAA==.',
Ob='Obalma:BAAALgAECgYJEQAAAA==.',
Od='Odrade:BAAALgADCgIJAgAAAA==.Odwalla:BAACLgAFFH8RAAMQAAUJHh/iCQATAQAQAAUJHh/iCQATAQABAAIJoBfeGACvAAAuAAQKfyMABBAACAlQIwsKAPgCABAACAlQIwsKAPgCAAEABgmtHy8VAHUBAAIAAwkMFFVkAK8AAAAA.',
Oh='Ohgodno:BAABLgAECn8aAAIHAAgJJgUoggAVAQAHAAgJJgUoggAVAQAAAA==.',
Ok='Oktal:BAAALgAECgYJBgAAAA==.',
Ol='Olmec:BAABLgAECn8sAAIZAAgJGhPuIACHAQAZAAgJGhPuIACHAQAAAA==.Olmek:BAAALgAECgYJCAAAAA==.',
On='Onlydesert:BAAALgAECgYJEQAAAA==.',
Oo='Oorudun:BAAALgADCgYJBgAAAA==.',
Op='Ophiel:BAAALgAECgYJEAAAAA==.Optiks:BAABLgAECn8aAAIeAAgJrBgNPQDkAQAeAAgJrBgNPQDkAQAAAA==.',
Or='Orblio:BAAALgADCgQJBAAAAA==.Orcofhell:BAAALgAECgMJBAAAAA==.Orcthas:BAAALgAECgYJDAAAAA==.Orksauce:BAACLgAFFH8JAAIkAAMJkR45FQAYAQAkAAMJkR45FQAYAQAuAAQKfzIAAyQACQmDJJwBACEDACQACQmDJJwBACEDACMAAQnZFg0cAEgAAAAA.Orleron:BAAALgAECgEJAQAAAA==.Oroth:BAAALgAECgYJDwAAAA==.',
Os='Osares:BAAALgAECggJEgAAAA==.Oshizitskoro:BAAALgAECgIJAgAAAA==.',
Ot='Otsu:BAAALgADCgMJAwABLgAECgYJDgAIAAAAAA==.',
Ou='Outofwater:BAAALgADCgYJBgAAAA==.Outtyfox:BAAALgADCgIJAgAAAA==.',
Ow='Owlkin:BAAALgAECgUJBQABLgAECgkJNgAFAKgeAA==.',
['Oß']='Oß:BAABLgAECn8VAAIPAAgJIRLXQwCyAQAPAAgJIRLXQwCyAQAAAA==.',
Pa='Pagophobia:BAAALgADCgEJAQAAAA==.Pakku:BAABLgAECn8iAAIeAAgJvRvAKwAoAgAeAAgJvRvAKwAoAgAAAA==.Palilicious:BAAALgAECgYJCgAAAA==.Pallytree:BAAALgAECggJEgAAAA==.Pantheeon:BAAALgADCggJCwAAAA==.Paradom:BAAALgADCgIJAgAAAA==.Parzival:BAABLgAECn8cAAIeAAcJMQvngwA0AQAeAAcJMQvngwA0AQAAAA==.Patchface:BAAALgADCgcJBwAAAA==.',
Pd='Pdp:BAABLgAECn8VAAIDAAcJiCO6FgBXAgADAAcJiCO6FgBXAgAAAA==.',
Pe='Perkbane:BAABLgAECn8WAAQKAAgJBxxdEAAoAQAKAAUJJB9dEAAoAQALAAcJuxOxmwAiAQAMAAIJnQ/XTgCBAAAAAA==.Perkdragon:BAAALgAECgYJBQABLgAECggJFgAKAAccAA==.Perkyl:BAABLgAECn8YAAIDAAYJiQsrNwDdAAADAAYJiQsrNwDdAAAAAA==.Petrol:BAAALgAECgYJBwAAAA==.',
Ph='Phage:BAAALgAECgEJAgABLgAECggJFwASAHwcAA==.Pheel:BAAALgAECgUJBQAAAA==.Phillactery:BAAALgAECgMJAwAAAA==.Phlykz:BAAALgAECgQJBwAAAA==.Phosho:BAAALgADCgYJBgAAAA==.',
Pi='Pidra:BAAALgADCgcJBwAAAA==.Piezo:BAAALgADCgMJAwAAAA==.Pig:BAAALgAECgQJBAAAAA==.Pikevarr:BAAALgAECgcJEAAAAA==.',
Pk='Pkrage:BAABLgAECn8sAAMiAAkJ4xnqCwBOAgAiAAkJ4xnqCwBOAgAYAAEJTABCtwAIAAAAAA==.',
Pl='Plagueborne:BAABLgAECn8VAAMXAAgJawijDAArAQAXAAgJawijDAArAQAHAAYJ7gHE6ACuAAAAAA==.Plazzy:BAABLgAECn8uAAQkAAkJjhySDwCsAgAkAAkJjhySDwCsAgAjAAYJaRfwCQBVAQApAAEJHw+ZFwA7AAAAAA==.Plopp:BAEALgAECgcJEwAAAA==.',
Po='Pollywog:BAAALgADCgYJBgABLgAFFAYJGAAFAEslAA==.Polyethylene:BAABLgAECn8fAAIJAAgJrwb7SgAfAQAJAAgJrwb7SgAfAQAAAA==.Popprocks:BAAALgADCgEJAQAAAA==.Poxx:BAAALgAECgIJAwAAAA==.',
Pr='Praxis:BAAALgADCgcJAQABLgAECgcJCgAIAAAAAA==.Pretzel:BAAALgAECgEJBQABLgAECggJHQAIAAAAAQ==.Proxymate:BAAALgADCgMJAwAAAA==.',
Pu='Puhtty:BAAALgAECgMJAwAAAA==.Punkfangs:BAAALgADCggJFQAAAA==.',
['Pë']='Pëaches:BAAALgADCgcJBwABLgAFFAYJEwAOAGYKAA==.',
['Pï']='Pï:BAAALgAECgQJBgAAAA==.',
Qk='Qkoira:BAAALgADCgYJBgABLgADCgcJCgAIAAAAAA==.',
Qu='Quanlain:BAABLgAECn8dAAMQAAgJmxy1JAD/AQAQAAgJmxy1JAD/AQACAAMJmBWQZgClAAAAAA==.Quasár:BAABLgAECn8XAAIDAAcJbRHnIwBPAQADAAcJbRHnIwBPAQAAAA==.Quilara:BAAALgADCgkJHQAAAA==.Quillathe:BAABLgAECn8mAAMNAAgJCBQFEgD+AQANAAgJCBQFEgD+AQAnAAYJAwzHMQABAQAAAA==.',
Ra='Radíant:BAAALgADCgUJBQABLgABCgYJBgAIAAAAAA==.Ragemaster:BAAALgAECgQJCQAAAA==.Ramiusraven:BAAALgADCgIJAgAAAA==.Rancore:BAABLgAECn8rAAMYAAgJQxkSGQDXAQAYAAgJQxkSGQDXAQAaAAMJcgqjKwCXAAAAAA==.Rashdar:BAACLgAFFH8OAAIPAAQJTgrwKwAmAQAPAAQJTgrwKwAmAQAuAAQKfx8AAg8ACAmZGRc5ANUBAA8ACAmZGRc5ANUBAAAA.Rattpack:BAABLgAECn8eAAMOAAgJaRZpOgCQAQAOAAcJWhdpOgCQAQAVAAYJdxL3OAAfAQAAAA==.Raves:BAABLgAECn8jAAIeAAcJ8h8aMgAOAgAeAAcJ8h8aMgAOAgAAAA==.',
Re='Regilz:BAABLgAECn8UAAMHAAcJmROWZwBNAQAHAAcJ1xCWZwBNAQAgAAMJ+g2jMQCEAAAAAA==.Reiayanomi:BAAALgAECgYJBgAAAA==.Repent:BAAALgAECgkJBwAAAA==.Reselience:BAAALgAECgQJBAABLgAFFAUJBQALAM8DAA==.Rewara:BAAALgADCgcJBwAAAA==.',
Rh='Rhadamenth:BAAALgADCgMJAwAAAA==.Rhinity:BAAALgADCgQJBAABLgAECgYJEwAIAAAAAA==.Rhyolite:BAAALgAECgEJAQAAAA==.',
Ri='Riaeviana:BAABLgAECn8VAAIOAAcJvhpBTQDAAQAOAAcJvhpBTQDAAQAAAA==.Ribeyye:BAAALgAECggJCwAAAA==.Rigormistis:BAAALgADCgEJAQAAAA==.Rilde:BAAALgADCgcJBwAAAA==.Rinjielune:BAAALgADCgYJDwAAAA==.Risch:BAAALgAECgMJAwAAAA==.Rius:BAAALgAECgIJAgAAAA==.',
Ro='Roberts:BAAALgADCgkJEAAAAA==.Robroy:BAAALgAECgkJAQAAAA==.Robroÿ:BAAALgAECgkJEwAAAA==.Robrõy:BAAALgAECgkJCgABLgAECgkJFgABAFEZAA==.Roku:BAABLgAECn8SAAIZAAcJvB16GwCwAQAZAAcJvB16GwCwAQABLgAFFAcJIgALAOEfAA==.Romex:BAAALgADCgEJAQAAAA==.Rondo:BAAALgADCgUJBQAAAA==.Roseclaw:BAEALgAECgYJDAABLgAECgYJEQAIAAAAAA==.Roseclawed:BAEALgAECgYJEQAAAA==.Roxcee:BAAALgAECgYJBgABLgAECggJGQAmALcYAA==.Roxso:BAACLgAFFH8gAAIeAAcJsh4RBQBTAgAeAAcJsh4RBQBTAgAuAAQKfyoAAh4ACQl0JqACANQDAB4ACQl0JqACANQDAAAA.',
Ru='Runnigan:BAAALgADCgQJBAAAAA==.Ruìñ:BAAALgAECgkJAQAAAA==.',
Rx='Rxse:BAAALgAECgYJEAAAAA==.',
Ry='Rylun:BAAALgADCgYJCQAAAA==.',
['Rà']='Rànik:BAAALgADCgIJAgAAAA==.',
['Rë']='Rëdmagma:BAABLgAECn8hAAIZAAgJAhp1FADzAQAZAAgJAhp1FADzAQAAAA==.',
['Rö']='Röbin:BAAALgAECgEJAQAAAA==.',
Sa='Saasaki:BAAALgAECgYJDgAAAA==.Sabrinacarp:BAABLgAECn8nAAImAAkJQRo1EgA2AgAmAAkJQRo1EgA2AgAAAA==.Sabryelle:BAAALgADCgEJAgAAAA==.Sacrelicious:BAABLgAECn8jAAIPAAgJbg8iXgBrAQAPAAgJbg8iXgBrAQAAAA==.Sagewynn:BAAALgAECgcJEAAAAA==.Salfroc:BAABLgAECn8yAAMKAAgJBhxvBADvAQAKAAgJBhxvBADvAQAMAAIJ5QpuLgA0AAAAAA==.Saltychief:BAAALgADCgUJBwAAAA==.Saplo:BAABLgAECn8pAAIQAAgJsQsySABwAQAQAAgJsQsySABwAQAAAA==.Sapphiraflux:BAAALgADCgIJAgAAAA==.Sarif:BAAALgADCgcJDAAAAA==.Sarvashi:BAAALgAECgMJBAAAAA==.Sasara:BAAALgAECgMJBgAAAA==.Sathas:BAAALgADCgQJBAAAAA==.Saxel:BAAALgAECggJEAAAAA==.',
Sc='Scrabble:BAAALgAECgQJBwAAAA==.',
Se='Segio:BAAALgAECgkJEwAAAA==.Selcia:BAABLgAECn8UAAIeAAcJaBhcYgB5AQAeAAcJaBhcYgB5AQAAAA==.Serenati:BAABLgAECn8cAAIPAAgJ8RnQKAAWAgAPAAgJ8RnQKAAWAgAAAA==.Sermour:BAAALgAECgEJAQAAAA==.',
Sh='Shadephoenix:BAABLgAECn8oAAIXAAgJIAYFDwADAQAXAAgJIAYFDwADAQAAAA==.Shados:BAABLgAECn8VAAMGAAkJmR5RFADGAQAbAAcJKRw+GwAqAgAGAAkJJB5RFADGAQAAAA==.Shadowen:BAAALgAECgcJDAAAAA==.Shambülance:BAAALgADCgEJAQAAAA==.Sharavia:BAABLgAECn8oAAIVAAgJ+w3+FwBbAQAVAAgJ+w3+FwBbAQAAAA==.Shari:BAABLgAECn8bAAIMAAgJOBERCQBnAQAMAAgJOBERCQBnAQAAAA==.Shatoo:BAAALgAECgYJDwAAAA==.Shaunchaos:BAAALgADCgMJAwAAAA==.Shaunchi:BAAALgADCgQJBAAAAA==.Shaunrawr:BAABLgAECn8iAAMQAAgJPhlRNwCsAQAQAAgJPhlRNwCsAQACAAIJ5wX2ewBUAAAAAA==.Shield:BAAALgAECgUJBQAAAA==.Shiftedtea:BAAALgAECgEJAQAAAA==.Shizaxe:BAAALgAECgYJCQAAAA==.Shizish:BAABLgAECn8WAAQGAAgJthp0FQC5AQAGAAYJ9hl0FQC5AQAFAAYJARZTMwAmAQAbAAUJ0AhUXADSAAAAAA==.Shocktuah:BAABLgAECn8rAAIZAAgJLCIhDABYAgAZAAgJLCIhDABYAgAAAA==.Shonúff:BAABLgAECn8yAAMGAAgJaxyDDAAvAgAGAAgJaxyDDAAvAgAFAAcJ4xKpJgBnAQAAAA==.Shotaro:BAABLgAECn8dAAMmAAcJcR5FEQBCAgAmAAcJcR5FEQBCAgAcAAQJnRhVHQAfAQAAAA==.Shox:BAAALgAECgEJAQAAAA==.',
Si='Sillybear:BAAALgAECgQJBQAAAA==.Silvermain:BAAALgADCgQJBAAAAA==.Sinful:BAABLgAECn8nAAMQAAgJMhOILgD3AQAQAAgJMhOILgD3AQACAAMJ6AA/fwBJAAAAAA==.Singarti:BAAALgAECggJDgAAAA==.Sizzlesnout:BAAALgAECgMJAwAAAA==.',
Sk='Skalagrim:BAAALgADCgMJAwAAAA==.Skedu:BAAALgADCgEJAQAAAA==.Skeptyk:BAABLgAECn8aAAIRAAgJPR1ACgB4AgARAAgJPR1ACgB4AgAAAA==.Skolivermist:BAEALgAECgcJCgABLgAFFAQJDgAnAHsJAA==.Skolivia:BAECLgAFFH8OAAMnAAQJewm8EQAoAQAnAAQJewm8EQAoAQANAAMJmwGZIwCnAAAuAAQKfxYAAycACAn6GGUZABYCACcACAn6GGUZABYCAA0AAglfEJtJAHEAAAAA.Skroggo:BAAALgAECgQJBgAAAA==.Skådoosh:BAABLgAECn80AAMGAAgJ5xEVHAB9AQAGAAgJ5xEVHAB9AQAbAAcJ+wdmNgDoAAABLgAECggJFQAPACESAA==.',
Sl='Slightdawn:BAAALgADCgkJCQAAAA==.Sloppymop:BAAALgADCgUJCAAAAA==.Sloppysteaks:BAAALgADCgUJBQAAAA==.',
Sm='Smallben:BAAALgADCgIJAgAAAA==.Smiley:BAAALgAECgYJDgAAAA==.Smite:BAAALgADCgIJAgAAAA==.Smitti:BAAALgAECgMJAwAAAA==.Smug:BAABLgAECn8pAAIOAAkJ6CSAAwArAwAOAAkJ6CSAAwArAwAAAA==.',
Sn='Snapcrklepop:BAAALgADCgUJBQAAAA==.Sniffledoo:BAABLgAECn8aAAIiAAgJzRLIEQB8AQAiAAgJzRLIEQB8AQAAAA==.Snuwuf:BAAALgADCgEJAQAAAA==.Snóóf:BAAALgAECgYJDgAAAA==.',
So='Solomeani:BAAALgAECgMJBAAAAA==.Sonicnoah:BAAALgAECgQJBAAAAA==.Soonmia:BAAALgADCgcJBwAAAA==.Sourfangs:BAACLgAFFH8LAAIYAAQJRSBRDQBPAQAYAAQJRSBRDQBPAQAuAAQKfxcAAhgACAkmJZsFAE0DABgACAkmJZsFAE0DAAAA.Soxx:BAAALgAECgEJAQAAAA==.',
Sp='Sparklymayhm:BAAALgADCgkJGgAAAA==.Spearz:BAAALgADCgQJBAAAAA==.Speedmonster:BAAALgADCggJCAAAAA==.Spicymilk:BAABLgAECn8jAAIdAAkJwiH0AQCTAgAdAAkJwiH0AQCTAgAAAA==.Spicypeño:BAABLgAECn8jAAMSAAgJdh5BDAAXAgASAAYJPiFBDAAXAgATAAcJ/hsEGADHAQABLgAFFAgJHAATAMcTAA==.Spinach:BAABLgAECn8YAAMmAAcJWxITNwAgAQAmAAYJ0BITNwAgAQAPAAEJigO2WAEXAAAAAA==.Spire:BAABLgAECn8mAAQeAAgJNgZdkQAbAQAeAAgJNgZdkQAbAQAdAAIJ8wGADgBCAAAWAAEJPwFBEgAVAAAAAA==.Splithoofe:BAAALgAECgUJBQABLgAFFAMJCwAQADMGAA==.Sprawl:BAABLgAECn9GAAIpAAkJpRllAgBcAgApAAkJpRllAgBcAgAAAA==.',
Sq='Squrrlydan:BAABLgAECn8WAAMiAAgJBSA9DADbAQAiAAcJAB89DADbAQAYAAYJXhvQSACBAQAAAA==.',
St='Staggerleaf:BAAALgAECgYJBwABLgAECgYJDgAIAAAAAA==.Stains:BAAALgADCgYJBgABLgAECggJFwASAHwcAA==.Staint:BAABLgAECn8XAAMSAAgJfBxBDQAFAgASAAcJ8h1BDQAFAgATAAEJvhNvaQA9AAAAAA==.Starnights:BAABLgAECn8UAAIXAAgJCAuXDAArAQAXAAgJCAuXDAArAQAAAA==.Statman:BAABLgAECn8qAAIiAAgJow/ZFABVAQAiAAgJow/ZFABVAQAAAA==.Steelbubble:BAAALgAECgYJDwAAAA==.Stengah:BAABLgAECn8uAAIoAAgJ4iSDAQBKAwAoAAgJ4iSDAQBKAwAAAA==.Steris:BAAALgADCgYJBgABLgADCgEJAQAIAAAAAA==.Strela:BAAALgAFFAEJAQAAAQ==.Stressummon:BAAALgADCgMJAgAAAA==.Strykie:BAAALgADCgQJBAAAAA==.',
Su='Sulina:BAAALgAECgYJEwAAAA==.Suzaki:BAAALgADCgkJCQAAAA==.',
Sv='Svetlian:BAAALgAECgUJCQABLgAFFAEJAQAIAAAAAA==.',
Sw='Swtblsphmy:BAABLgAECn8uAAMJAAgJMRaGJQDVAQAJAAgJMRaGJQDVAQAZAAIJZgR6gwAkAAAAAA==.',
Sy='Symphony:BAAALgADCgEJAQAAAA==.Syradora:BAABLgAECn8XAAMRAAcJQhN7HgCHAQARAAcJQhN7HgCHAQAnAAEJiAJNbgAdAAAAAA==.Syynner:BAAALgAECgcJBwAAAA==.',
['Sä']='Säber:BAAALgAECgQJBAAAAA==.',
['Sè']='Sèd:BAAALgAECgkJEwAAAA==.Sèitheach:BAAALgAECgMJAwAAAA==.',
Ta='Taelak:BAAALgAECgcJEAAAAA==.Tahrin:BAABLgAECn8hAAIQAAgJAx1VFgCFAgAQAAgJAx1VFgCFAgAAAA==.Talamon:BAABLgAECn8qAAIbAAgJRheREwDWAQAbAAgJRheREwDWAQAAAA==.Talmøre:BAAALgADCgMJAwAAAA==.Talyyon:BAABLgAECn8WAAILAAYJ+wFWwQB5AAALAAYJ+wFWwQB5AAAAAA==.Tandinise:BAABLgAFFH8HAAInAAMJlQXLGQDLAAAnAAMJlQXLGQDLAAAAAA==.Tandruid:BAAALgAECgMJBgABLgAFFAUJBQALAM8DAA==.Tankmeta:BAAALgADCgMJAwAAAA==.Tanmonk:BAAALgAECgQJBAABLgAFFAUJBQALAM8DAA==.Taproot:BAAALgAECgkJCQAAAA==.Tas:BAAALgADCgUJCgAAAA==.Tashi:BAABLgAECn8iAAICAAkJNRIDCAC1AQACAAkJNRIDCAC1AQAAAA==.Tasina:BAAALgAECgEJAQABLgAECgUJCAAIAAAAAA==.Tastictank:BAAALgAECgQJBgAAAA==.Taurenamos:BAABLgAECn82AAQEAAgJWBYXHgANAgAEAAgJWBYXHgANAgADAAgJEhnEEgDsAQAhAAYJ5AbFKwB7AAAAAA==.Taynam:BAAALgAFFAEJAQABLgAECgkJGwAXAIwgAA==.',
Te='Tebas:BAAALgAECgQJBQAAAA==.Teival:BAABLgAECn8fAAIQAAgJHRvbHQBTAgAQAAgJHRvbHQBTAgAAAA==.Tempëst:BAAALgADCgIJAgAAAA==.Tenchu:BAABLgAECn8PAAMVAAUJRBw8NAA5AQAVAAUJRBw8NAA5AQAOAAUJlA6gigC1AAAAAA==.Tenfour:BAAALgADCgYJBgAAAA==.Tenseven:BAABLgAECn8XAAIEAAgJ0QqiSQAgAQAEAAgJ0QqiSQAgAQAAAA==.Teredorn:BAAALgADCgkJDQABLgAECgkJHQAmAM4bAA==.Terrorbláde:BAAALgADCgcJBwAAAA==.Terrørßlade:BAAALgADCgYJBgABLgAECgcJGwABAFYgAA==.',
Th='Thalinin:BAAALgADCgYJCAAAAA==.Thalion:BAAALgAECggJCQAAAA==.Thark:BAAALgAECgUJBgABLgAECggJJQAVABEmAA==.Theharmacist:BAAALgAECgQJBAAAAA==.Therris:BAABLgAECn8pAAIQAAgJMBBXPgCSAQAQAAgJMBBXPgCSAQAAAA==.Thideaes:BAAALgADCgYJEAAAAA==.Thidias:BAAALgAECgIJAgAAAA==.Thorimane:BAAALgAECgQJBAABLgAECggJHQAIAAAAAA==.Thrizzowd:BAAALgADCgkJDQAAAA==.Throwd:BAABLgAECn8yAAIkAAgJxBejEQDJAQAkAAgJxBejEQDJAQAAAA==.Thwark:BAAALgADCgQJBAABLgAECggJJQAVABEmAA==.',
Ti='Tinytony:BAABLgAECn8qAAMcAAkJrhMyDgCIAQAcAAgJbRUyDgCIAQAPAAcJRArmkQADAQAAAA==.',
To='Toranis:BAAALgAECgMJBAAAAA==.Torrellan:BAAALgADCgMJAwAAAA==.Torrents:BAABLgAECn8zAAQJAAgJySMJBQAdAwAJAAgJySMJBQAdAwAZAAUJaRIQUwCUAAAlAAIJAQc0JwBnAAAAAA==.Totemik:BAAALgAECgEJAQAAAA==.Touchofchaos:BAAALgAECgEJAQAAAA==.Toxíc:BAAALgADCgcJEgAAAA==.',
Tr='Traffyfu:BAAALgAECgMJAwAAAA==.Trailerpark:BAAALgAECgkJAgAAAA==.Traver:BAAALgAECgQJBAAAAA==.Trinytee:BAAALgAECgMJBgAAAA==.Trogdor:BAAALgADCgQJBAAAAA==.',
Tu='Turbocarried:BAAALgAECgcJDAAAAA==.Ture:BAAALgADCgkJGQAAAA==.Turnandburn:BAAALgAECgIJBQAAAA==.',
Tw='Twistedsugar:BAAALgAECgMJAwAAAA==.Twìztid:BAABLgAECn8dAAIOAAgJrCOiEgBtAgAOAAgJrCOiEgBtAgAAAA==.',
Ty='Tyriäel:BAABLgAECn8xAAIgAAkJtCAABAC/AgAgAAkJtCAABAC/AgAAAA==.Tyrrible:BAAALgADCggJDwAAAA==.',
['Tà']='Tàyla:BAAALgADCgYJBgABLgAECgMJBgAIAAAAAA==.',
['Tð']='Tðxîc:BAAALgAECgEJAgAAAA==.',
Ul='Ulther:BAAALgAECgcJEAAAAA==.Ultìmecia:BAAALgAECgYJAQAAAA==.',
Un='Unbinddeath:BAAALgADCgQJBwAAAA==.Unfriendly:BAAALgADCgEJAQAAAA==.',
Up='Upside:BAAALgAECgYJDgAAAA==.',
Ur='Uruz:BAABLgAECn8dAAIYAAkJ+x5UGQCBAgAYAAkJ+x5UGQCBAgAAAA==.',
Ut='Uthêr:BAAALgADCgMJAwAAAA==.',
Va='Vacare:BAAALgAECgcJEAAAAA==.Valdyria:BAAALgADCgQJCAAAAA==.Valefar:BAAALgAECgYJDgAAAA==.Valkoienne:BAAALgAECgEJAQAAAA==.Valyniss:BAAALgAECgEJAgAAAA==.Vamp:BAAALgADCgUJBQAAAA==.Vanart:BAAALgAECgkJBQAAAA==.Vandemar:BAAALgAECgMJAwAAAA==.Vanderpump:BAAALgADCgYJBgABLgAECgkJNAANAP0UAA==.Vanreu:BAAALgAECgYJBwAAAA==.Varnashar:BAAALgAECgYJBwAAAA==.Vavictus:BAAALgAECgcJEAAAAA==.',
Ve='Vedronorael:BAAALgADCgkJFgAAAA==.Vekkar:BAAALgAECgEJAQAAAA==.Velanthia:BAAALgAECgEJAQAAAA==.Vengrath:BAABLgAECn8aAAIeAAgJPiJpIQBaAgAeAAgJPiJpIQBaAgAAAA==.Venomgodd:BAAALgADCgEJAQAAAA==.Verderben:BAAALgAECgYJCgAAAA==.',
Vi='Vibestotem:BAAALgAECgEJAQAAAA==.Vilenia:BAAALgAECgcJEwAAAA==.Vilkasdk:BAAALgAECgYJCQAAAA==.Vinchenzo:BAAALgAECgIJAgAAAA==.Vinhelsin:BAAALgAECgQJBAAAAA==.Violetangel:BAAALgAECgYJBQAAAA==.Vionir:BAABLgAECn8kAAIBAAgJoyP+BQCpAgABAAgJoyP+BQCpAgAAAA==.Vitality:BAAALgAECgIJAgAAAA==.',
Vo='Voidrush:BAAALgAECgcJEAAAAA==.Voirdire:BAABLgAECn8bAAIPAAgJfAjidgA0AQAPAAgJfAjidgA0AQAAAA==.Voron:BAAALgAECggJEAAAAA==.',
Vu='Vulpa:BAABLgAECn8uAAMMAAgJIBLXCABsAQAMAAgJIBLXCABsAQALAAIJFAKJDwE/AAAAAA==.',
Vy='Vynessa:BAAALgAECgEJAQAAAA==.Vyshareth:BAAALgADCgcJBwAAAA==.',
Wa='Wanren:BAAALgAECgQJBAAAAA==.Wargodd:BAAALgADCgMJAwAAAA==.Waterwhip:BAABLgAFFH8FAAIJAAIJSwpCHACFAAAJAAIJSwpCHACFAAAAAA==.',
We='Westfall:BAACLgAFFH8GAAMHAAMJMwQIcwDGAAAHAAMJ/gIIcwDGAAAgAAEJlAazKQAuAAAuAAQKfx4AAyAACQkXGxwNAD4CACAACQkIGxwNAD4CAAcABwnvDCZ0ADIBAAAA.',
Wh='Whirl:BAABLgAECn8VAAIHAAgJqRSmRwCkAQAHAAgJqRSmRwCkAQAAAA==.Whirlock:BAAALgADCgYJBgAAAA==.Whirlwind:BAABLgAECn8hAAIYAAcJCBtFKgAQAgAYAAcJCBtFKgAQAgABLgAECggJFQAHAKkUAA==.Whydoiexist:BAABLgAECn8VAAIbAAYJHCAHHQAbAgAbAAYJHCAHHQAbAgABLgAECgkJJwAoAFsiAA==.',
Wi='Willrun:BAABLgAECn8WAAMDAAYJqQZ4QQCwAAADAAYJqQZ4QQCwAAAfAAEJYgQXNwAqAAAAAA==.Windwatcher:BAABLgAECn8kAAIZAAcJngu6NgADAQAZAAcJngu6NgADAQAAAA==.Witheredyam:BAAALgAECgEJAQAAAA==.Withirony:BAAALgAECgYJBwAAAA==.',
Wo='Wompeal:BAABLgAECn8pAAIRAAgJzh+zCADAAgARAAgJzh+zCADAAgAAAA==.Wonkwonk:BAABLgAECn8aAAIeAAgJ9gS6mwAIAQAeAAgJ9gS6mwAIAQAAAA==.Worth:BAABLgAECn8qAAIPAAgJ+CPWDQC/AgAPAAgJ+CPWDQC/AgAAAA==.',
Wr='Wrathofdirt:BAAALgADCgUJBQAAAA==.Wravin:BAABLgAECn8vAAIQAAkJ1w6/MgDkAQAQAAkJ1w6/MgDkAQABLgAECgkJLwARADAWAA==.Wrukolas:BAABLgAECn8eAAILAAcJSwziZwAwAQALAAcJSwziZwAwAQAAAA==.',
Wu='Wulf:BAAALgAECgMJBAAAAA==.Wumdaorm:BAAALgADCgEJAQAAAA==.',
Wy='Wyhm:BAAALgADCgUJBwAAAA==.Wystan:BAABLgAECn8rAAIJAAgJ2Bo3FgBEAgAJAAgJ2Bo3FgBEAgAAAA==.',
['Wé']='Wés:BAABLgAECn8jAAIbAAgJFhqmEAD5AQAbAAgJFhqmEAD5AQAAAA==.',
['Wí']='Wíckedwítch:BAAALgAECgcJDgAAAA==.',
Xa='Xalatoes:BAAALgADCgEJAwAAAA==.Xanthe:BAABLgAECn8gAAMmAAgJUAcqNgAlAQAmAAgJUAcqNgAlAQAPAAEJIwQeWAEnAAAAAA==.Xayden:BAAALgADCgMJAwAAAA==.',
Xe='Xeal:BAAALgAECgYJEQAAAA==.Xelkath:BAAALgAECgcJEwAAAA==.Xenomorphic:BAACLgAFFH8SAAIFAAUJFR0fCwCrAQAFAAUJFR0fCwCrAQAuAAQKfywAAgUACQnMIpQCAGEDAAUACQnMIpQCAGEDAAAA.Xentow:BAABLgAECn8pAAIQAAgJEwqiTQBfAQAQAAgJEwqiTQBfAQAAAA==.',
Xu='Xuanfeng:BAAALgAFFAQJBAAAAA==.',
Xy='Xythros:BAAALgADCggJCAAAAA==.',
Ya='Yacob:BAAALgADCgEJAgABLgAECggJJAARAM0dAA==.Yamling:BAAALgAECgQJBQAAAA==.Yarel:BAACLgAFFH8JAAIFAAUJxwdYBgBjAQAFAAUJxwdYBgBjAQAuAAQKfyoAAwUACQmbHt4NAHgCAAUACQmbHt4NAHgCAAYACQleGYcYAJwBAAEuAAUUAgkCAAgAAAAA.Yayaka:BAAALgAFFAEJAwAAAA==.',
Yi='Yizdano:BAACLgAFFH8KAAIkAAMJiyJ+FQAVAQAkAAMJiyJ+FQAVAQAuAAQKfywAAyQACAl5IRQJAEkCACQACAl5IRQJAEkCACMAAQlrFG8dAEAAAAAA.',
Yo='Yoloscrap:BAAALgADCgYJBQAAAA==.',
Yu='Yukiina:BAAALgAECgMJAwAAAA==.',
['Yù']='Yùm:BAAALgAECgcJDAABLgAECgkJJwAeAJccAA==.',
Za='Zaccheus:BAABLgAECn8UAAMFAAYJVRE4LwAsAQAFAAYJVRE4LwAsAQAGAAYJUAaISgDpAAAAAA==.Zalruin:BAAALgADCgkJCgAAAA==.Zambora:BAAALgAECggJDgAAAA==.Zarb:BAAALgADCggJCAAAAA==.',
Ze='Zeebra:BAABLgAECn8bAAMdAAYJaQ9/BgASAQAdAAYJag1/BgASAQAeAAYJZQu9lwAQAQAAAA==.Zeenii:BAAALgADCgMJAwAAAA==.Zeesaw:BAABLgAECn8eAAMaAAgJihzOFgBJAQAYAAcJgxzgJgBzAQAaAAcJohLOFgBJAQAAAA==.Zeretrix:BAABLgAECn8vAAIeAAkJ0hwaGwB+AgAeAAkJ0hwaGwB+AgAAAA==.Zeroperfect:BAAALgADCgUJBQAAAA==.',
Zi='Zikà:BAAALgADCgMJAwAAAA==.Zinni:BAAALgADCgIJAgAAAA==.Ziros:BAAALgAECgYJBQAAAA==.',
Zl='Zlutar:BAAALgAECgMJBQAAAA==.',
Zo='Zonotix:BAAALgAECgMJAwAAAA==.',
Zq='Zq:BAAALgADCgEJAQAAAA==.',
Zy='Zynos:BAABLgAECn8kAAIOAAgJgg3BagD8AAAOAAgJgg3BagD8AAAAAA==.',
['Âl']='Âllatår:BAAALgADCgUJBQABLgAECgYJBgAIAAAAAA==.',
['Ãl']='Ãlexstrasza:BAAALgADCgUJAwAAAA==.',
['Ça']='Çalindrel:BAAALgADCgkJCQAAAA==.',
['Ñu']='Ñuk:BAAALgAECgYJDQAAAA==.',
['Úà']='Úà:BAAALgADCgcJCgAAAA==.',
['Üb']='Überhealz:BAAALgAECgQJBwABLgAECgYJFAAFAFURAA==.',
['ßö']='ßöw:BAABLgAECn8gAAMQAAgJFxKkPQCUAQAQAAgJFxKkPQCUAQACAAYJdgh2WQDfAAAAAA==.',
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
