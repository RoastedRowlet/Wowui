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

local lookup = {'Mage-Frost','Paladin-Retribution','DeathKnight-Unholy','Druid-Restoration','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Preservation','Druid-Feral','Hunter-Survival','Priest-Shadow','DemonHunter-Devourer','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Paladin-Protection','Warlock-Affliction','Warlock-Demonology','Warrior-Protection','DemonHunter-Vengeance','Paladin-Holy','DeathKnight-Blood','Monk-Brewmaster','Druid-Balance','Monk-Windwalker','Mage-Arcane','Warlock-Destruction','Priest-Discipline','Priest-Holy','Shaman-Enhancement','Warrior-Fury','Druid-Guardian','Rogue-Outlaw','DemonHunter-Havoc','Monk-Mistweaver','Warrior-Arms','Mage-Fire',}
local provider = {region='US',realm='Firetree',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abacabb:BAAALgAECgUJBwAAAA==.',
Ac='Acanthiex:BAAALgADCgkJCQAAAA==.',
Ad='Adnarimn:BAAALgAECgEJAQAAAA==.Adondias:BAABLgAECn8zAAIBAAkJlCOlBgAlAwABAAkJlCOlBgAlAwAAAA==.',
Ae='Aelanthus:BAAALgADCgEJAQAAAA==.Aelinn:BAAALgADCgEJAQAAAA==.',
Ag='Agrevail:BAABLgAECn8UAAICAAYJWiC/SwCaAQACAAYJWiC/SwCaAQAAAA==.',
Ai='Aidendk:BAABLgAECn8cAAIDAAkJIR/RJACqAgADAAkJIR/RJACqAgAAAA==.Aidenw:BAAALgAECgUJBQAAAA==.',
Ak='Akrib:BAAALgADCgUJBQAAAA==.Akryllic:BAABLgAECn8vAAIEAAgJUR/aCwDDAgAEAAgJUR/aCwDDAgAAAA==.',
Al='Aldari:BAACLgAFFH8SAAIBAAYJERt4EQDJAQABAAYJERt4EQDJAQAuAAQKfyEAAgEACQndJO4HAIoDAAEACQndJO4HAIoDAAAA.Allen:BAAALgADCgcJBwAAAA==.Allydk:BAABLgAECn81AAMDAAkJ2CNBBwAJAwADAAkJ2CNBBwAJAwAFAAQJhxziEgDJAAAAAA==.Altrag:BAABLgAECn87AAMGAAkJryKqBgDyAgAGAAkJryKqBgDyAgAHAAEJmAHvmQAaAAAAAA==.Aluc:BAABLgAECn8rAAIIAAkJjQ7dDgCTAQAIAAkJjQ7dDgCTAQAAAA==.Alyrssa:BAAALgAECgYJBgAAAA==.',
An='Andilar:BAABLgAECn8ZAAICAAgJ/hg9RgARAgACAAgJ/hg9RgARAgAAAA==.Andrepov:BAAALgAECgEJBgAAAA==.Anehii:BAABLgAECn8uAAIJAAkJFgvzDQB2AQAJAAkJFgvzDQB2AQAAAA==.Aniia:BAAALgAECgYJEwAAAA==.Animaldude:BAACLgAFFH8HAAIKAAIJzxOwGQCpAAAKAAIJzxOwGQCpAAAuAAQKfzoABAoACQnmH2gGAIMCAAoACQnmH2gGAIMCAAYAAwlsHPxxAP4AAAcAAQneBHCQACoAAAAA.Anjera:BAABLgAECn8YAAILAAgJVhR/HACMAQALAAgJVhR/HACMAQAAAA==.Anotherdrood:BAAALgAECgcJBwAAAA==.Anslayer:BAAALgAECgEJAQAAAA==.Antor:BAAALgAECgYJCgABLgAECgkJNQAEADUmAA==.Anwala:BAAALgAECgEJAQAAAA==.Anémie:BAAALgADCgkJDwAAAA==.',
Ap='Apexis:BAABLgAECn8eAAIMAAYJWRTPZgAGAQAMAAYJWRTPZgAGAQAAAA==.Apolion:BAAALgAECgMJBAAAAA==.',
Ar='Arche:BAAALgADCgEJAQAAAA==.Arctodus:BAAALgAECgYJCgAAAA==.Arghuul:BAABLgAECn8pAAMNAAkJEh11BwAZAwANAAkJEh11BwAZAwAOAAEJ4RunGgBTAAAAAA==.Arks:BAABLgAECn8eAAIEAAgJPxveFQBRAgAEAAgJPxveFQBRAgAAAA==.Arksmash:BAAALgADCgcJBwAAAA==.',
As='Asperges:BAABLgAECn8XAAMPAAgJZBWaMwC2AQAPAAYJLxqaMwC2AQAQAAcJvhBdOABwAQAAAA==.Astropâ:BAAALgAECgEJAQAAAA==.',
Ax='Axsisdknight:BAAALgAECgEJAQAAAA==.',
Ay='Ayrmag:BAAALgAECgYJBgAAAA==.',
Az='Azasei:BAAALgADCgMJBAAAAA==.Azathoth:BAAALgADCgUJBwABLgAECgMJAwARAAAAAA==.',
['Aë']='Aëlana:BAABLgAECn8pAAIBAAkJuhpsLwAZAgABAAkJuhpsLwAZAgAAAA==.',
Ba='Babybowser:BAAALgADCgYJBgAAAA==.Baconn:BAACLgAFFH8SAAICAAUJNh9MFABrAQACAAUJNh9MFABrAQAuAAQKfx4AAgIABwnuJCIfALECAAIABwnuJCIfALECAAAA.Badbunny:BAAALgAECgUJEgAAAA==.Bailey:BAAALgADCgYJCQAAAA==.Baileyc:BAAALgAECgQJBAAAAA==.Balancer:BAAALgAECgcJDgAAAA==.Balkhan:BAAALgADCgMJAwAAAA==.Balun:BAAALgAECgEJAwAAAA==.Banza:BAAALgAECgIJAgAAAA==.Barsh:BAABLgAECn8ZAAIMAAYJOBrUTADBAQAMAAYJOBrUTADBAQABLgAFFAMJBgABADkZAA==.Bashful:BAAALgAECgEJAQAAAA==.Battlebidet:BAAALgAECgEJAgAAAA==.',
Be='Beauregarde:BAAALgADCggJBgAAAA==.Beef:BAACLgAFFH8OAAISAAUJuBy3CABjAQASAAUJuBy3CABjAQAuAAQKfxoAAxIACAkHJvYFACQDABIACAl4I/YFACQDABMABAlBJRgUAKUBAAAA.Beefdido:BAABLgAECn8kAAIOAAkJxhOCBAAAAgAOAAkJxhOCBAAAAgAAAA==.Beefstew:BAAALgAECgMJAwAAAA==.Befouled:BAAALgAECgcJEQAAAA==.Belinos:BAAALgADCgEJAQAAAA==.Belithe:BAABLgAECn8fAAIUAAYJ8gW3KQB6AAAUAAYJ8gW3KQB6AAAAAA==.Benson:BAAALgADCgIJAgAAAA==.Berrymanalow:BAACLgAFFH8NAAIBAAQJXwjYSgAZAQABAAQJXwjYSgAZAQAuAAQKfykAAgEACAlcFxVCANMBAAEACAlcFxVCANMBAAAA.',
Bi='Bigpapapumpz:BAAALgAECgYJBwAAAA==.Bijtoo:BAABLgAECn8xAAMVAAkJjxvIAgA2AgAVAAkJjxvIAgA2AgAWAAUJXw2plQDRAAAAAA==.Bikkels:BAAALgADCgYJDQABLgAECgUJBQARAAAAAA==.Bingsoo:BAABLgAECn8rAAIBAAkJMhh1KwApAgABAAkJMhh1KwApAgAAAA==.Bist:BAAALgAECgUJBwABLgAECgcJHwACAI0lAA==.Bistopher:BAABLgAECn8fAAICAAcJjSUFFADzAgACAAcJjSUFFADzAgAAAA==.Bisty:BAAALgADCgYJCgABLgAECgcJHwACAI0lAA==.',
Bj='Bjorney:BAABLgAECn8lAAILAAgJ7hZ1FQDPAQALAAgJ7hZ1FQDPAQAAAA==.',
Bl='Blankspace:BAAALgAECgcJDwAAAA==.Blaserr:BAABLgAECn8WAAIXAAgJwBbOFQCxAQAXAAgJwBbOFQCxAQAAAA==.Blessurface:BAAALgAECgMJAwAAAA==.Blindfire:BAABLgAECn8oAAIBAAkJ+R9lHAAFAwABAAkJ+R9lHAAFAwAAAA==.Blindspirit:BAAALgAECgYJDQAAAA==.Blindvngence:BAABLgAECn8lAAMYAAkJDxWfCADuAQAYAAgJ8BafCADuAQAMAAYJeQp4cwDnAAAAAA==.Blizzerker:BAAALgAECgEJAQAAAA==.Bloodrayne:BAAALgAECgIJAgAAAA==.Bludoosh:BAAALgAECgYJDQAAAA==.Blumken:BAAALgADCgEJAQAAAA==.',
Bo='Bombpops:BAAALgADCgEJAQABLgAECgkJLwAZAK4eAA==.Bonkdeath:BAABLgAECn8fAAMDAAgJrQogeAApAQADAAcJqwogeAApAQAaAAEJuQoASAAlAAAAAA==.Boomskii:BAAALgADCgIJAgAAAA==.Boomymonk:BAABLgAECn8aAAIbAAcJsR8xFABuAgAbAAcJsR8xFABuAgAAAA==.Boss:BAABLgAFFH8LAAIDAAUJwh7hCgDnAQADAAUJwh7hCgDnAQABLgAFFAcJGAAcAP0aAA==.Bourius:BAAALgAECgYJCwABLgAFFAQJCQACABoSAA==.Bowzette:BAAALgAECgQJBAAAAA==.',
Br='Br:BAABLgAECn8hAAIEAAkJ0SEOCgDcAgAEAAkJ0SEOCgDcAgAAAA==.Brauxx:BAAALgAECgEJAQAAAA==.Breadermonk:BAABLgAECn8eAAMbAAkJHiSsAQAtAwAbAAkJHiSsAQAtAwAdAAQJRR3iLQADAQAAAA==.Brezanyou:BAABLgAECn8mAAMEAAYJoApZXgDWAAAEAAYJoApZXgDWAAAJAAEJHQRfOgAiAAABLgAECgcJEwARAAAAAA==.Broblowa:BAAALgADCgEJAQABLgAECggJJAASAJYbAA==.Broly:BAAALgADCgcJDAABLgAECgMJAwARAAAAAA==.Brotherblud:BAAALgADCgkJCgAAAA==.Brøx:BAABLgAECn8yAAIDAAkJLCGKCwDZAgADAAkJLCGKCwDZAgAAAA==.',
Bu='Bubbelhearth:BAAALgAECgYJDAAAAA==.Budyzer:BAAALgAECgMJAwAAAA==.Builtdif:BAAALgADCgYJBgABLgAECggJLAACADYkAA==.Bumbaclottx:BAAALgAECgMJBAAAAA==.Bunnyboy:BAAALgAECgYJEAAAAA==.Burlen:BAABLgAECn8aAAMBAAgJuRvNRwBgAgABAAgJuRvNRwBgAgAeAAQJxBpoDQDyAAAAAA==.Bustalic:BAAALgAECgYJBgABLgAFFAYJEwAMAOkZAA==.Bustarime:BAAALgADCgkJLgAAAA==.Buyagram:BAAALgADCgIJAQAAAA==.',
Bw='Bwonsamdeez:BAAALgADCgYJBgAAAA==.',
['Bî']='Bîrth:BAACLgAFFH8HAAIBAAIJ3w5OcwCiAAABAAIJ3w5OcwCiAAAuAAQKfy4AAgEACQkuIWILAO4CAAEACQkuIWILAO4CAAAA.',
Ca='Caeleste:BAAALgAECgcJDAAAAA==.Calic:BAABLgAECn82AAMWAAkJkB75DQCqAgAWAAkJ/x35DQCqAgAfAAgJ0RxoBgBpAgAAAA==.Calryuu:BAABLgAECn8hAAIbAAkJsByLCgBRAgAbAAkJsByLCgBRAgAAAA==.Caltrask:BAAALgAECgIJAgAAAA==.Cambiön:BAACLgAFFH8HAAIBAAMJNw0eXQDpAAABAAMJNw0eXQDpAAAuAAQKfy4AAgEACAkvHaQmAD8CAAEACAkvHaQmAD8CAAAA.Cameltoetem:BAAALgAECgQJBAAAAA==.Canape:BAABLgAECn8ZAAIZAAYJHRuhKgBrAQAZAAYJHRuhKgBrAQAAAA==.Capnmurlock:BAAALgADCgEJAQAAAA==.Captnmurzzp:BAAALgADCgkJDgAAAA==.Carpetcrumbs:BAAALgAECgEJAQAAAA==.Castasaurus:BAAALgAECgQJBAAAAA==.Catharsis:BAACLgAFFH8VAAMgAAgJ7h5pAwB4AgAgAAgJrh5pAwB4AgAhAAEJHCUoEQBiAAAuAAQKfykABCAACQn5JSEAAOkDACAACQn5JSEAAOkDACEABwlYJQQKAKwCAAsAAQmRGkdYAEoAAAAA.',
Ce='Ceer:BAAALgADCggJDQAAAA==.Cenno:BAABLgAECn82AAIDAAkJiheLKQATAgADAAkJiheLKQATAgAAAA==.Cerioth:BAAALgAECgQJBAAAAA==.',
Ch='Chaadd:BAAALgADCgEJAQAAAA==.Chantyu:BAAALgADCgUJCAABLgAECgcJEwARAAAAAA==.Charlixcx:BAAALgADCgEJAQAAAA==.Chickenman:BAAALgAECgcJDgAAAA==.Chickienuggs:BAAALgADCgcJCgAAAA==.Chiflado:BAAALgAECgcJCwAAAA==.Chillinda:BAAALgAECgIJBQAAAA==.Chillpoppin:BAABLgAECn8fAAMiAAkJxCLQAQDYAgAiAAkJxCLQAQDYAgAQAAIJ9BbZcgB3AAAAAA==.Chinpokomon:BAAALgAECgkJQwAAAQ==.Chompsy:BAABLgAECn8dAAIBAAgJrxm8QQBzAgABAAgJrxm8QQBzAgABLgAFFAUJDQACALMUAA==.Chubbychi:BAAALgAECgEJAgABLgAECgcJEwARAAAAAA==.',
Ci='Ciei:BAAALgAECgMJBAAAAA==.Cilya:BAAALgAECgYJCAAAAA==.Citrusghoul:BAAALgAECgYJDQAAAA==.Citruslite:BAAALgAECgEJAQAAAA==.',
Cl='Clockworkx:BAAALgAECgEJAQAAAA==.',
Co='Cole:BAABLgAECn8tAAMjAAgJfiFLCwBsAgAjAAgJLSFLCwBsAgAXAAgJdRheDADZAQAAAA==.Conceptheals:BAABLgAECn8YAAQkAAYJERBKHQDfAAAkAAYJERBKHQDfAAAEAAUJgAmYaQCzAAAJAAEJMhKRMgA3AAAAAA==.Confessia:BAAALgAECgYJCgAAAA==.Constantine:BAAALgAECgMJBAAAAA==.Costcobeef:BAAALgAECgEJAQABLgAECgQJBgARAAAAAA==.Couchlocked:BAAALgADCgEJAQAAAA==.',
Cr='Crackle:BAAALgAECgUJCwAAAA==.Criticalmiss:BAAALgAECgQJBwABLgAFFAUJGwADAJsdAA==.Critsae:BAACLgAFFH8UAAIDAAYJpBwrEgCtAQADAAYJpBwrEgCtAQAuAAQKfx8AAgMACAk2IFwWAPYCAAMACAk2IFwWAPYCAAAA.Critydarkirn:BAACLgAFFH8FAAIZAAMJQh63GgABAQAZAAMJQh63GgABAQAuAAQKfyoABBkACQkaHuQcAC8CABkACQkaHuQcAC8CAAIABQn5EfZ9ACcBABQABQn7FYwYAAIBAAAA.Critymonk:BAAALgAFFAEJAQAAAA==.Crypticdh:BAABLgAECn8TAAMMAAYJZBaWXAAgAQAMAAYJZBaWXAAgAQAYAAEJAABFLgAAAAAAAA==.Cryptø:BAAALgAECgYJBwAAAA==.',
Cv='Cvrcvss:BAABLgAECn8bAAQWAAkJEBZaYQCmAQAWAAgJ5hZaYQCmAQAfAAUJhg4ZKQAeAQAVAAEJAABsLgBBAAAAAA==.',
Cy='Cybele:BAABLgAECn8uAAIMAAkJGCBtCgC/AgAMAAkJGCBtCgC/AgAAAA==.Cypriss:BAAALgAECgIJBAAAAA==.',
['Cë']='Cëlestial:BAAALgAECgYJBwAAAA==.',
Da='Dabadjuju:BAAALgAECgYJEwAAAA==.Dagoonfather:BAABLgAECn8bAAMOAAgJqBeqBAD5AQAOAAgJqBeqBAD5AQAlAAQJtAjDDABVAAAAAA==.Dale:BAAALgADCgMJAwAAAA==.Dandorllan:BAACLgAFFH8OAAIZAAMJjR/YGwD3AAAZAAMJjR/YGwD3AAAuAAQKfysAAxkACQkHIz8BAHgDABkACQkHIz8BAHgDAAIACQkyJfMCAEgDAAAA.Dandowaz:BAABLgAFFH8MAAIPAAMJLxZlLgDKAAAPAAMJLxZlLgDKAAABLgAFFAMJDgAZAI0fAA==.Dandyrandy:BAABLgAECn8vAAMCAAkJXRfGHgBLAgACAAkJXRfGHgBLAgAZAAgJJRGtLgDJAQAAAA==.Dani:BAAALgADCgUJCQAAAA==.Dareick:BAAALgAECgQJDAAAAA==.Darthashmire:BAAALgAECgQJBQAAAA==.Darthavenger:BAAALgAECggJDwAAAA==.Dayday:BAABLgAECn8bAAIcAAgJ1BBlKgCtAQAcAAgJ1BBlKgCtAQAAAA==.Dazzazn:BAABLgAECn8cAAIjAAcJpAG+YABvAAAjAAcJpAG+YABvAAAAAA==.',
De='Decious:BAABLgAECn8oAAICAAkJlBl3IABBAgACAAkJlBl3IABBAgAAAA==.Deepfist:BAABLgAECn81AAIbAAkJsyHbAgD9AgAbAAkJsyHbAgD9AgAAAA==.Deepfried:BAAALgAECgUJCwAAAA==.Defjam:BAABLgAECn8qAAIBAAkJoh0oFQCjAgABAAkJoh0oFQCjAgAAAA==.Delath:BAAALgAECgIJAgAAAA==.Deleerious:BAEALgAECgQJBAABLgAFFAUJEgANAMwlAA==.Delicia:BAABLgAECn8cAAMgAAkJpQ8+FADjAQAgAAkJUw0+FADjAQAhAAYJQA9FPgBBAQAAAA==.Delicias:BAAALgAECgUJBQABLgAECgkJHAAgAKUPAA==.Dellbelphine:BAABLgAECn85AAICAAkJ3iHACADwAgACAAkJ3iHACADwAgAAAA==.Dellock:BAAALgAECgUJBQAAAA==.Deminis:BAAALgADCgYJBgAAAA==.Demonbud:BAAALgAECgYJCgABLgAECgkJIAATAPUfAA==.Demoncarlos:BAACLgAFFH8PAAIMAAQJJxvEHABVAQAMAAQJJxvEHABVAQAuAAQKfyQAAgwACQnTHQgeAJ4CAAwACQnTHQgeAJ4CAAAA.Demonicscale:BAACLgAFFH8NAAIWAAQJcgVERgD2AAAWAAQJcgVERgD2AAAuAAQKfzAAAxYACQlEF0RPANoBABYACQlEF0RPANoBABUAAQlIBc81AC4AAAAA.Demonskii:BAACLgAFFH8GAAImAAMJMhJ3DQDpAAAmAAMJMhJ3DQDpAAAuAAQKfzUAAyYACAltIpoIANkCACYACAltIpoIANkCAAwAAgljDDO5AFgAAAAA.Demton:BAABLgAECn8uAAImAAkJhBv5BgB1AgAmAAkJhBv5BgB1AgAAAA==.Denken:BAABLgAFFH8WAAIQAAgJ2BPDAgAsAgAQAAgJ2BPDAgAsAgAAAA==.Deuslucis:BAAALgADCgEJAQAAAA==.Devage:BAAALgADCgUJBQAAAA==.Dezlock:BAAALgAECgYJBgAAAA==.Dezmage:BAAALgADCgYJBgAAAA==.Dezpriest:BAAALgAECgEJAgAAAA==.',
Di='Diagram:BAAALgAECgYJDgAAAA==.Diatonic:BAAALgADCgQJBAABLgAFFAQJDQAMAK8YAA==.Dildrathion:BAAALgAECgYJBgAAAA==.Direkau:BAABLgAECn81AAIXAAkJpCW0AABWAwAXAAkJpCW0AABWAwAAAA==.Dishonesty:BAAALgAECggJCAABLgAFFAIJBwAKAM8TAA==.Divinity:BAAALgAECgYJBgAAAA==.Diwata:BAACLgAFFH8bAAIgAAcJfhWQBABQAgAgAAcJfhWQBABQAgAuAAQKfzIAAyAACQnmHdYEAP0CACAACQnmHdYEAP0CACEABgnNDgU+AEIBAAAA.',
Do='Dogler:BAACLgAFFH8LAAMEAAMJIiJEGgArAQAEAAMJIiJEGgArAQAcAAEJigPPNAA5AAAuAAQKfycAAwQACQnuIvQEADoDAAQACQnuIvQEADoDABwABgnXGUEhAGIBAAAA.Dojaz:BAABLgAECn8tAAMMAAkJgw6FOQCUAQAMAAkJgw6FOQCUAQAmAAIJqAmzXwBjAAAAAA==.Doki:BAAALgADCgQJBAAAAA==.Domeydome:BAAALgAECgEJAQABLgAECggJGAABADkaAA==.Donthitgary:BAAALgAECgIJAgAAAA==.Dooley:BAABLgAECn8VAAInAAkJBhgJHgDGAQAnAAkJBhgJHgDGAQAAAA==.Doomgrapple:BAAALgAECgUJBQAAAA==.Doriahn:BAAALgAECgYJDQAAAA==.',
Dr='Draconica:BAABLgAECn8gAAITAAkJ9R8qAwDxAgATAAkJ9R8qAwDxAgAAAA==.Dracussy:BAABLgAECn8qAAMSAAkJuRvsCgBnAgASAAkJuRvsCgBnAgATAAIJkA7nNABtAAAAAA==.Dragar:BAABLgAECn8jAAIjAAkJFxckFgDxAQAjAAkJFxckFgDxAQAAAA==.Dragonler:BAAALgAECgUJEAABLgAFFAMJCwAEACIiAA==.Dragoon:BAAALgAECgYJBgAAAA==.Draktha:BAAALgAECgYJCQABLgAECgcJFwATAFwjAA==.Dreamchaser:BAAALgAECgQJBAAAAA==.Dreddful:BAAALgAECgEJBgAAAA==.Drkelso:BAABLgAECn8xAAIBAAkJ/A1HSQC8AQABAAkJ/A1HSQC8AQAAAA==.Dropswitch:BAAALgADCgEJAQAAAA==.Drunkcig:BAAALgAECgMJAwAAAA==.',
Du='Duchalu:BAABLgAECn8uAAIjAAkJUROJGQDTAQAjAAkJUROJGQDTAQAAAA==.Durtbag:BAAALgADCgQJBwAAAA==.',
Dw='Dwarrfie:BAAALgAECgUJBgAAAA==.',
Dy='Dynabear:BAAALgADCgQJCQAAAA==.',
['Dè']='Dèz:BAABLgAECn8eAAMMAAgJtxoAOQARAgAMAAgJtxoAOQARAgAYAAMJmg/lHgCQAAAAAA==.',
['Dú']='Dúncan:BAAALgAECgYJBgAAAA==.',
Ei='Eione:BAABLgAECn8yAAIcAAgJABlpFADaAQAcAAgJABlpFADaAQAAAA==.',
El='Elaswyn:BAAALgAECgQJDAAAAA==.Elegon:BAAALgADCgYJBgAAAA==.Elemantary:BAAALgAECgcJCAAAAA==.Elfieras:BAAALgAECgIJAgAAAA==.Elfies:BAAALgADCgYJBwAAAA==.Elinez:BAAALgAECgEJAQAAAA==.Ellcrys:BAABLgAECn8mAAIfAAgJhxAWCgBRAQAfAAgJhxAWCgBRAQAAAA==.Elvinshiznic:BAABLgAECn8YAAICAAgJ9Q90VwB7AQACAAgJ9Q90VwB7AQAAAA==.Elyzah:BAACLgAFFH8GAAIWAAMJtgi/WADLAAAWAAMJtgi/WADLAAAuAAQKfxwAAxYACAkxGkQuAOEBABYACAkxGkQuAOEBAB8AAQleCP51AC8AAAAA.',
Em='Emagine:BAABLgAECn80AAMPAAkJdCPaAgBWAwAPAAkJdCPaAgBWAwAQAAUJbg1tSAC6AAAAAA==.Embra:BAAALgAECgMJAwAAAA==.Emeraldbeast:BAACLgAFFH8TAAIEAAUJfxPsEQBvAQAEAAUJfxPsEQBvAQAuAAQKfycAAwQACAn/HmYaAGcCAAQACAn/HmYaAGcCABwAAgldEpJRAG0AAAAA.',
En='Enni:BAACLgAFFH8MAAIMAAMJBR8jMAAVAQAMAAMJBR8jMAAVAQAuAAQKfycAAgwACQm8IwgQAP4CAAwACQm8IwgQAP4CAAAA.',
Er='Erengarde:BAABLgAECn8eAAIZAAgJBBsVFwBZAgAZAAgJBBsVFwBZAgAAAA==.Eri:BAAALgAECgQJCgAAAA==.Erissra:BAABLgAECn8ZAAMVAAkJAgxYBwDfAQAVAAgJ4wxYBwDfAQAWAAYJygUCtADxAAAAAA==.Eroeda:BAABLgAECn8hAAImAAgJtA/uGABSAQAmAAgJtA/uGABSAQAAAA==.',
Es='Escanør:BAAALgAECgQJBQABLgAECgcJDgARAAAAAA==.',
Ev='Evvy:BAAALgADCgcJCQAAAA==.',
Ex='Exil:BAAALgADCgcJCgAAAA==.Exo:BAABLgAECn81AAIEAAkJeCUbAQC2AwAEAAkJeCUbAQC2AwAAAA==.Exosham:BAAALgADCgMJAwABLgAECgkJNQAEAHglAA==.',
Ey='Eynya:BAAALgADCgcJBwABLgAECgQJCAARAAAAAA==.',
Ez='Ezfrost:BAAALgAFFAEJAgAAAA==.Ezsmash:BAACLgAFFH8JAAIjAAMJ7R5QGwAEAQAjAAMJ7R5QGwAEAQAuAAQKfxoAAiMABwnLHQIiAEQCACMABwnLHQIiAEQCAAAA.',
['Eñ']='Eñkei:BAAALgAECgEJAQAAAA==.',
Fa='Fabulous:BAAALgADCgkJCQAAAA==.Faeline:BAAALgAECgMJBgAAAA==.Falkichu:BAAALgAECgEJAQAAAA==.Familiarface:BAAALgAECgYJDQAAAA==.Fastfeet:BAABLgAFFH8RAAIEAAUJFBdSDwCKAQAEAAUJFBdSDwCKAQAAAA==.',
Fe='Felam:BAAALgADCgcJBwAAAA==.Ferachio:BAAALgAECgQJBQAAAA==.',
Ff='Ffreshcope:BAABLgAFFH8FAAIDAAIJyxVxhACjAAADAAIJyxVxhACjAAABLgAFFAYJEAAVAOAfAA==.',
Fh='Fhud:BAAALgAECgEJAQAAAA==.',
Fi='Fierysquish:BAAALgADCgUJBgAAAA==.Fightinmoose:BAAALgAECgYJDgAAAA==.Finzak:BAAALgAECgQJBQAAAA==.Fireblitzer:BAAALgAECgMJBAAAAA==.Fistferge:BAABLgAECn8WAAMbAAgJZBuoDQAfAgAbAAgJZBuoDQAfAgAnAAUJMBgnKgBOAQABLgAECgcJGgAUACcgAA==.',
Fn='Fnaskmar:BAABLgAECn8gAAIGAAkJciDpCADTAgAGAAkJciDpCADTAgAAAA==.',
Fo='Fogpaw:BAAALgADCgkJGAAAAA==.Foosaa:BAAALgAECggJEAAAAA==.Forbearance:BAABLgAECn81AAIUAAkJ1iPmAAAoAwAUAAkJ1iPmAAAoAwAAAA==.',
Fr='Franco:BAABLgAECn8iAAIGAAkJUxLLIQAOAgAGAAkJUxLLIQAOAgAAAA==.Freshfresh:BAAALgAECgUJBgABLgAFFAYJEAAVAOAfAA==.Freshlock:BAACLgAFFH8QAAQVAAYJ4B+1AwDtAAAWAAMJ/R3vPAASAQAVAAMJ+Ca1AwDtAAAfAAIJURUWEwBZAAAuAAQKfx4ABB8ACQk9IkQMAP4BAB8ABQlcJUQMAP4BABYABgkzH3JOAN0BABUABwl3JC8GALIBAAAA.Frickvicious:BAAALgADCgIJAgAAAA==.Friend:BAAALgAECgEJAgAAAA==.Fright:BAACLgAFFH8GAAICAAMJUAzARQDaAAACAAMJUAzARQDaAAAuAAQKfx0AAgIACQmoGdY9AMQBAAIACQmoGdY9AMQBAAAA.Friska:BAAALgAECgUJCAAAAA==.Frizthle:BAAALgADCgIJAgABLgAECgkJEAARAAAAAA==.Frostbolt:BAAALgAECgEJAQAAAA==.Frostcool:BAABLgAECn8YAAIBAAgJwwzDZAB0AQABAAgJwwzDZAB0AQAAAA==.Frostyh:BAAALgAECgYJCQAAAA==.Frostyp:BAACLgAFFH8PAAILAAQJTwpxEQArAQALAAQJTwpxEQArAQAuAAQKfyAAAgsACQmeGS0OAKACAAsACQmeGS0OAKACAAAA.',
Fu='Funks:BAAALgAECgYJBgABLgAECgkJHwAiAMQiAA==.Furion:BAABLgAECn8UAAIjAAYJjRT1TAByAQAjAAYJjRT1TAByAQAAAA==.Furiousbruja:BAAALgAECgcJEwAAAA==.Furiousnun:BAAALgAECgEJAQAAAA==.Furtivis:BAAALgAECgMJAwAAAA==.',
Fy='Fyre:BAAALgAECgkJEAAAAA==.Fyrebird:BAAALgAECgUJBgABLgAECgkJEAARAAAAAA==.',
Ga='Galadhriel:BAABLgAECn81AAMEAAkJjxtyFgBMAgAEAAkJjxtyFgBMAgAcAAEJVgNIjQAhAAAAAA==.Galadima:BAACLgAFFH8OAAIZAAQJPxzOEQBNAQAZAAQJPxzOEQBNAQAuAAQKfzAAAhkACQn3H+kCAEMDABkACQn3H+kCAEMDAAAA.Galaxywing:BAAALgAECgYJDAAAAA==.Ganador:BAABLgAECn8tAAQWAAkJ6RqVJQAKAgAWAAcJExuVJQAKAgAfAAQJiRPfMAD2AAAVAAEJSxSbJAA5AAAAAA==.Gayguyender:BAAALgAECgUJDgAAAA==.Gazzerfroz:BAAALgAECgEJAQAAAA==.',
Gb='Gbones:BAAALgAECgEJAwABLgAECgQJCAARAAAAAA==.',
Ge='Geerah:BAAALgADCgYJBgAAAA==.Gennoro:BAAALgADCgcJBwABLgAECgkJHwAiAMQiAA==.',
Gi='Givesburger:BAAALgAECgYJBgAAAA==.',
Gl='Glizzies:BAABLgAECn8sAAICAAgJNiSoCwAxAwACAAgJNiSoCwAxAwAAAA==.Glocky:BAAALgADCgcJBwAAAA==.',
Gn='Gnomeofdeath:BAABLgAECn8fAAMDAAkJLSHgFgDyAgADAAkJLSHgFgDyAgAFAAEJHhIAAAAAAAAAAA==.',
Go='Gokusan:BAAALgAECgcJBwABLgAECgkJIwAWAKIhAA==.Gomgar:BAAALgADCgcJFwAAAA==.Gooned:BAABLgAECn8rAAMNAAgJLBd1EgC+AQANAAgJLBd1EgC+AQAOAAEJWAsaHgA9AAAAAA==.Goonforall:BAAALgADCgEJAQAAAA==.',
Gr='Grampus:BAAALgADCgIJAgABLgADCgYJBgARAAAAAA==.Grandmadeath:BAAALgADCgcJBwAAAA==.Grashoppa:BAABLgAECn8VAAIdAAYJxhV2JQA0AQAdAAYJxhV2JQA0AQAAAA==.Greentide:BAACLgAFFH8HAAIPAAIJDBqlOACeAAAPAAIJDBqlOACeAAAuAAQKfzQAAg8ACQn4IKQHAO0CAA8ACQn4IKQHAO0CAAAA.Grengar:BAAALgAECgYJDgAAAA==.Groovybonbon:BAAALgAECgEJAQAAAA==.Groovybun:BAAALgAECgYJBgAAAA==.Groovymochi:BAABLgAECn8qAAMnAAkJ7AwNIACaAQAnAAkJ7AwNIACaAQAdAAEJzgWXfQAoAAAAAA==.',
Gu='Guccimaybe:BAABLgAECn8gAAIiAAkJ4RDTDAD2AQAiAAkJ4RDTDAD2AQAAAA==.Guldaniel:BAAALgADCgEJAQAAAA==.Guldanramsey:BAABLgAECn8VAAMVAAcJ9BgWCQC2AQAVAAYJOR0WCQC2AQAWAAcJ3w+SfABiAQAAAA==.Gunjá:BAAALgADCgYJDgAAAA==.',
Gw='Gwynastrasza:BAAALgAECgQJCQAAAA==.Gwynleigh:BAAALgAECgQJBAAAAA==.Gwynneth:BAAALgAECgEJAQABLgAECgQJCQARAAAAAA==.',
Gx='Gxre:BAAALgAECgkJAgAAAA==.',
['Gò']='Gòku:BAABLgAECn8jAAMWAAkJoiHqCwC9AgAWAAgJoiHqCwC9AgAfAAIJvhF+TACIAAAAAA==.',
['Gö']='Göuf:BAAALgAECgcJBwAAAA==.',
['Gü']='Güy:BAABLgAECn8ZAAIDAAgJowtBXQBnAQADAAgJowtBXQBnAQAAAA==.',
Ha='Halea:BAABLgAECn8ZAAIMAAgJpRwyIwB/AgAMAAgJpRwyIwB/AgAAAA==.Haleluya:BAAALgAECgYJDQABLgAECggJGQAMAKUcAA==.Halepurr:BAAALgADCgIJAgABLgAECggJGQAMAKUcAA==.Halogenrofl:BAABLgAECn8bAAImAAgJhBiHDgDZAQAmAAgJhBiHDgDZAQAAAA==.Hammahtime:BAAALgADCgcJBwAAAA==.Hammerferge:BAABLgAECn8aAAIUAAcJJyCiCQA3AgAUAAcJJyCiCQA3AgAAAA==.Handsofelune:BAAALgAECgQJCAABLgAFFAQJDQAWAHIFAA==.Hannibol:BAAALgADCgYJCAAAAA==.Happa:BAAALgADCgkJEgABLgAFFAQJCgAiAPYbAA==.Harrowhark:BAABLgAECn8VAAIWAAUJbgy9lgDPAAAWAAUJbgy9lgDPAAAAAA==.Hawktwua:BAAALgAFFAEJAQAAAA==.Hawtshot:BAAALgAECgQJBgAAAA==.Hazelena:BAAALgAECgMJAwAAAA==.',
Hb='Hbz:BAABLgAECn83AAIXAAkJzh+ZAwC8AgAXAAkJzh+ZAwC8AgAAAA==.',
He='Healingbrew:BAACLgAFFH8LAAIbAAQJPhNtGAAcAQAbAAQJPhNtGAAcAQAuAAQKfyMAAxsACAk8HOAWAFECABsACAk8HOAWAFECAB0ABQmDDo45AMsAAAAA.Healzplz:BAAALgADCgcJBwAAAA==.Herekittycat:BAAALgAECgEJAQAAAA==.Heretoohelp:BAAALgAECgYJEAAAAA==.',
Hi='Hildar:BAABLgAECn8aAAIZAAcJRRVvJgCJAQAZAAcJRRVvJgCJAQAAAA==.Hillcoast:BAAALgADCgUJBQAAAA==.',
Ho='Holeymoley:BAAALgAECgEJAgAAAA==.Holibeef:BAAALgAECgcJEwAAAA==.Holybits:BAABLgAECn8ZAAIZAAgJjxFmKAB7AQAZAAgJjxFmKAB7AQAAAA==.Holyholly:BAAALgAECgQJBQABLgAECgkJIAATAPUfAA==.Holylinoleum:BAAALgADCgQJBAABLgADCggJBgARAAAAAA==.Holysquish:BAACLgAFFH8ZAAICAAYJ7BGOCgCiAQACAAYJ7BGOCgCiAQAuAAQKfyUAAgIACQm7HjIeALYCAAIACQm7HjIeALYCAAAA.Holyz:BAABLgAECn8gAAILAAgJ6ByfFgAyAgALAAgJ6ByfFgAyAgAAAA==.Homoglobin:BAACLgAFFH8KAAIaAAQJIQygFADlAAAaAAQJIQygFADlAAAuAAQKfxkAAhoACAn/GdURAJkBABoACAn/GdURAJkBAAAA.Honeydip:BAABLgAECn81AAIGAAkJChp9GQBAAgAGAAkJChp9GQBAAgAAAA==.Honésty:BAABLgAECn8rAAIhAAcJohuwGgAHAgAhAAcJohuwGgAHAgAAAA==.Hoontertile:BAAALgADCgcJBwAAAA==.Horsegirl:BAAALgAECgUJBwAAAA==.Hotfistbaby:BAAALgAECgcJCgAAAA==.Hotspankyboi:BAABLgAECn8UAAIUAAgJRSbyAABjAwAUAAgJRSbyAABjAwAAAA==.',
Hr='Hruun:BAAALgADCgcJBwAAAA==.',
Hu='Huntskii:BAAALgAECgQJBgAAAA==.Hussle:BAAALgADCggJDgAAAA==.',
Hw='Hwaryeong:BAAALgADCgEJAQAAAA==.',
Ia='Iamluck:BAAALgAFFAIJAgAAAA==.',
Ic='Iceicebabye:BAAALgAECgQJCQAAAA==.Iceleaf:BAAALgADCgYJBQAAAA==.Iciest:BAAALgAECgMJAgABLgAECggJLAACADYkAA==.',
Ig='Iger:BAAALgADCgcJDwAAAA==.',
Ih='Iha:BAAALgAECgEJAgAAAA==.Ihealdrunk:BAAALgAECgEJAQABLgAECggJMAAXAFwZAA==.',
Ij='Ijudgepeople:BAAALgADCggJCAABLgAECgQJBgARAAAAAA==.',
Ik='Ikkaroas:BAAALgAECgUJBQAAAA==.Ikkis:BAAALgAECgcJEQAAAA==.Ikmoti:BAAALgAECgEJAgAAAA==.',
Il='Ileinaa:BAABLgAECn9CAAIhAAkJARhFDwAqAgAhAAkJARhFDwAqAgAAAA==.Iliketrains:BAABLgAECn8zAAIQAAkJtx/CBgCyAgAQAAkJtx/CBgCyAgAAAA==.Illuminatì:BAAALgAECgcJEAAAAA==.Ilovegrizzly:BAAALgAECgIJBAABLgAECgcJCAARAAAAAA==.',
Im='Immortalhulk:BAAALgADCgIJAgAAAA==.',
In='Indicud:BAAALgAECgUJCwAAAA==.Inoxiakek:BAAALgAECgQJCQAAAA==.Intensedh:BAAALgAECgYJEwABLgAECggJFgAPAE4bAA==.Intensevok:BAAALgADCgcJBwABLgAECggJFgAPAE4bAA==.Intensifiedx:BAABLgAECn8WAAIPAAgJThsOHgArAgAPAAgJThsOHgArAgAAAA==.',
Ir='Ironwil:BAAALgAECgUJCQAAAA==.',
Is='Iscreamalot:BAABLgAECn8fAAIjAAgJAhkEGQCDAgAjAAgJAhkEGQCDAgAAAA==.Isele:BAAALgAECgQJBAABLgAECgYJCgARAAAAAA==.',
It='Itybity:BAAALgAECgYJCwAAAA==.',
Iy='Iyatsuki:BAABLgAFFH8GAAMcAAMJ5AHIFwB6AAAcAAIJswHIFwB6AAAEAAMJUwEsRABqAAAAAA==.',
Ja='Jawbone:BAAALgADCgEJAQAAAA==.Jawndis:BAAALgAECgUJBQAAAA==.Jayfizzle:BAAALgAECgYJBwAAAA==.Jaymazing:BAACLgAFFH8FAAIMAAQJfxK6KAArAQAMAAQJfxK6KAArAQAuAAQKfxwAAgwACQldIqgRAHQCAAwACQldIqgRAHQCAAEuAAQKBgkHABEAAAAA.',
Ji='Jimmyboy:BAAALgADCgUJBQAAAA==.',
Jo='Joenormousgg:BAAALgADCgUJBQAAAA==.Johnathan:BAAALgADCgEJAQAAAA==.Johnconner:BAABLgAECn8WAAIGAAYJvQmmcAACAQAGAAYJvQmmcAACAQAAAA==.Joj:BAAALgAECgcJBwAAAA==.Jonald:BAAALgAECgQJCwABLgAECgkJJwAbANoXAA==.Jongwoo:BAAALgADCgYJCAAAAA==.Jonthecron:BAABLgAECn8nAAMbAAkJ2hdADwAKAgAbAAkJ2hdADwAKAgAdAAMJpAqhYwBGAAAAAA==.Joojekabab:BAAALgADCgEJAQAAAA==.Jorkinit:BAAALgAECggJEwAAAA==.Jormot:BAAALgAECgEJAQABLgAECgkJEAARAAAAAA==.Jorok:BAABLgAECn8VAAIQAAkJhBXcHAAqAgAQAAkJhBXcHAAqAgAAAA==.',
Ju='Jubilee:BAABLgAECn8hAAIWAAkJFRneIwCEAgAWAAkJFRneIwCEAgAAAA==.Jumannji:BAABLgAECn8lAAIQAAkJwh41CACVAgAQAAkJwh41CACVAgAAAA==.Jumpingbench:BAABLgAECn8aAAIEAAYJlQyZYwDFAAAEAAYJlQyZYwDFAAAAAA==.Jurik:BAAALgADCgUJDgAAAA==.Justadragon:BAAALgADCgQJBgAAAA==.',
Ka='Kabluey:BAAALgADCgEJAQAAAA==.Kalarm:BAAALgADCgYJBgAAAA==.Kallidan:BAABLgAECn8lAAIMAAkJoRV6KQDbAQAMAAkJoRV6KQDbAQAAAA==.Kallight:BAABLgAECn8cAAIZAAkJ1hx4BQD7AgAZAAkJ1hx4BQD7AgAAAA==.Karks:BAACLgAFFH8PAAMjAAUJ1BiyIADjAAAjAAQJahayIADjAAAoAAEJEiDeCABjAAAuAAQKfx8AAyMACQmEH3UUAKoCACMACQkCG3UUAKoCACgAAwkRGacfAPEAAAAA.Karsaørlong:BAAALgAECgUJCQAAAA==.Kassabekkaia:BAAALgADCggJDgABLgAECggJHwACAMkMAA==.Katrois:BAAALgAECgYJBgAAAA==.Kayem:BAAALgAECgQJBAAAAA==.Kazroth:BAAALgADCgcJDQAAAA==.',
Kb='Kbe:BAAALgADCgQJBAAAAA==.',
Ke='Kelewan:BAABLgAECn83AAMDAAkJKRrIGwBdAgADAAkJhRnIGwBdAgAaAAcJZBaqFgCrAQAAAA==.Kellabrimbor:BAAALgADCgUJBQAAAA==.Kellelor:BAAALgAECgEJAwAAAA==.Kerrigan:BAAALgAECgEJAQABLgAECgYJCAARAAAAAA==.',
Ki='Killkillkill:BAAALgAECgYJBgAAAA==.Kindassuddy:BAACLgAFFH8GAAMBAAMJORnkUAAEAQABAAMJORnkUAAEAQApAAEJyAQ5AwBEAAAuAAQKfzQAAykACQnBIe8AAH4CAAEACAkBIp0qAMgCACkACQn2Gu8AAH4CAAAA.Kindled:BAABLgAECn8VAAIBAAgJnRazawD+AQABAAgJnRazawD+AQAAAA==.Kinvardar:BAAALgAECgcJEwAAAA==.Kirbbslav:BAAALgAECgIJBAABLgAFFAcJGgAZAPUZAA==.Kirbislav:BAAALgAFFAEJAQABLgAFFAcJGgAZAPUZAA==.Kirbslav:BAACLgAFFH8aAAIZAAcJ9RkbBQAHAgAZAAcJ9RkbBQAHAgAuAAQKfzEAAhkACQm5I6QEACMDABkACQm5I6QEACMDAAAA.Kirbyslav:BAABLgAFFH8LAAIEAAUJBBjZDACmAQAEAAUJBBjZDACmAQABLgAFFAcJGgAZAPUZAA==.Kirkland:BAAALgAECgIJAgAAAA==.Kirklandbeef:BAAALgAECgQJBgAAAA==.Kits:BAAALgAECgEJAQABLgAECggJGgACAOcPAA==.',
Kn='Kniavez:BAABLgAECn8kAAMoAAkJzBJ/CwDcAQAoAAkJzBJ/CwDcAQAjAAIJRgbBaQBUAAAAAA==.',
Ko='Koranova:BAABLgAECn8ZAAILAAgJXho6EQD9AQALAAgJXho6EQD9AQAAAA==.Korro:BAABLgAECn8qAAIKAAkJUx37BgB5AgAKAAkJUx37BgB5AgAAAA==.Kostin:BAABLgAECn8fAAIjAAgJ/BdrHgBcAgAjAAgJ/BdrHgBcAgAAAA==.',
Kr='Krak:BAABLgAECn8aAAIaAAgJ9BtkDwC+AQAaAAgJ9BtkDwC+AQAAAA==.Krasta:BAAALgAECgMJBgAAAA==.Kratosdh:BAAALgADCgMJBAAAAA==.Krolow:BAACLgAFFH8hAAMjAAYJXBvWBACcAQAjAAYJxRrWBACcAQAXAAQJehlzCQA7AQAuAAQKfyQAAyMACAnqG6gjADgCACMABwlOH6gjADgCABcACAnsF9UPAJwBAAAA.Kruugh:BAABLgAECn8bAAIQAAgJlxP3KgBDAQAQAAgJlxP3KgBDAQAAAA==.',
Ku='Kuler:BAACLgAFFH8HAAIjAAMJBxxKHAD9AAAjAAMJBxxKHAD9AAAuAAQKfy0AAiMACQk6Id4GALMCACMACQk6Id4GALMCAAAA.Kungfushrub:BAABLgAECn8fAAIUAAgJzBFwEwA7AQAUAAgJzBFwEwA7AQAAAA==.Kurolizian:BAAALgAECgYJCwAAAA==.Kurplow:BAAALgAECgEJAgAAAA==.Kuulandor:BAABLgAECn8lAAIaAAkJNyGUAwAfAwAaAAkJNyGUAwAfAwAAAA==.',
['Kè']='Kèèn:BAACLgAFFH8LAAICAAMJHB6NDwAsAQACAAMJHB6NDwAsAQAuAAQKfxQAAgIABgliI3JcAM0BAAIABgliI3JcAM0BAAAA.',
['Ké']='Két:BAABLgAECn8ZAAIEAAgJ0xoWJwAaAgAEAAgJ0xoWJwAaAgABLgAFFAMJBQACAJYNAA==.',
['Kê']='Kêt:BAABLgAFFH8FAAICAAMJlg24QADqAAACAAMJlg24QADqAAAAAA==.',
['Kí']='Kítkat:BAABLgAECn8aAAICAAgJ5w8PWAB6AQACAAgJ5w8PWAB6AQAAAA==.',
['Kÿ']='Kÿra:BAAALgAECgEJAQAAAA==.',
Le='Leesin:BAAALgAECgEJAgAAAA==.Levelground:BAAALgAFFAIJBAABLgAFFAcJGwAcAGkUAA==.Lewd:BAAALgAECgMJBAABLgAECggJGQAMAKUcAA==.Leylines:BAAALgADCgcJBwAAAA==.',
Li='Liakä:BAAALgADCgYJCgAAAA==.Lightblind:BAAALgADCgMJAwAAAA==.Lightrampant:BAAALgADCgMJAQAAAA==.Lilmonkey:BAAALgADCgQJBgAAAA==.Limegreen:BAAALgADCgEJAQAAAA==.Liquidsevenz:BAABLgAECn8gAAIiAAcJuxPpDgBPAQAiAAcJuxPpDgBPAQAAAA==.Litlit:BAAALgAECgYJDgAAAA==.',
Lo='Lodoss:BAACLgAFFH8KAAIPAAQJrxzKEABrAQAPAAQJrxzKEABrAQAuAAQKfywAAg8ACAmtHUURAHMCAA8ACAmtHUURAHMCAAAA.Lollipops:BAAALgAECgEJAQABLgAECgkJLwAZAK4eAA==.Lonah:BAABLgAECn8bAAIGAAgJVyUNCADeAgAGAAgJVyUNCADeAgABLgAECgcJKQAjACMmAA==.Lorienb:BAABLgAECn8uAAMLAAkJVxhuDwAUAgALAAkJVxhuDwAUAgAgAAIJbRCOSQByAAAAAA==.Lotheran:BAAALgADCgEJAQAAAA==.Lothé:BAAALgAECgQJBAAAAA==.Lotlizar:BAAALgAECgEJAQABLgAECggJHwADAK0KAA==.Lowkydead:BAAALgADCgQJBQAAAA==.',
Lu='Lubelesso:BAAALgADCgkJFgAAAA==.Luckehlock:BAACLgAFFH8LAAIVAAUJlyENAAAIAgAVAAUJlyENAAAIAgAuAAQKfyAAAxUACQlwJAsAAN4DABUACQlwJAsAAN4DABYAAQlvALs0ARIAAAEuAAUUCAkLABIAvRgA.Luckehtwo:BAABLgAFFH8LAAISAAgJvRi+AgBsAgASAAgJvRi+AgBsAgAAAA==.Luxcn:BAABLgAECn8lAAMGAAgJrhhNJAABAgAGAAgJrhhNJAABAgAHAAEJkgToMwAlAAAAAA==.',
Ma='Macgibbins:BAABLgAECn8ZAAIKAAgJ+xQpCgA7AgAKAAgJ+xQpCgA7AgAAAA==.Madepure:BAAALgAECgMJAwABLgAECggJLAACADYkAA==.Magus:BAABLgAECn8XAAMBAAcJpSOgUQBCAgABAAcJpSOgUQBCAgApAAIJ4xITDABuAAABLgAFFAcJGAAcAP0aAA==.Mahole:BAAALgAECgMJAwAAAA==.Mahyora:BAAALgAECgEJBQAAAA==.Marsoti:BAAALgAECgcJCgAAAA==.Mats:BAAALgADCgYJBgAAAA==.Mattyphunt:BAAALgAECgEJAQAAAA==.Mavus:BAABLgAECn8VAAIBAAgJAxxQZgALAgABAAgJAxxQZgALAgAAAA==.',
Mc='Mccream:BAAALgAECgMJAwAAAA==.',
Me='Melylen:BAAALgAECgQJCAAAAA==.Mezugyouzug:BAAALgADCgQJBAAAAA==.',
Mi='Milkbolt:BAABLgAECn8aAAIWAAkJMRKSOgCwAQAWAAkJMRKSOgCwAQAAAA==.Milkcream:BAAALgAECgYJBgAAAA==.Minigolf:BAABLgAECn8jAAQMAAgJ5BmKNQClAQAMAAgJKxmKNQClAQAmAAUJWRnKMABLAQAYAAEJAAA/LgAAAAAAAA==.Minigun:BAABLgAECn8fAAIKAAgJXyAPCQBVAgAKAAgJXyAPCQBVAgAAAA==.Minioozy:BAAALgAECgEJAQAAAA==.Minityr:BAAALgAECgYJBgAAAA==.Minivan:BAAALgADCgQJBAABLgAECggJIwAMAOQZAA==.Misawa:BAABLgAECn8VAAIMAAgJJQcEZwAFAQAMAAgJJQcEZwAFAQAAAA==.Mizuboxx:BAABLgAECn8uAAIZAAkJFiHzAgBCAwAZAAkJFiHzAgBCAwAAAA==.',
Mo='Molyver:BAABLgAECn8tAAMdAAkJGBlaJgClAQAdAAcJzhVaJgClAQAnAAUJYA5sOgDtAAAAAA==.Momak:BAAALgAECgQJBAABLgAECgYJCQARAAAAAA==.Mommey:BAAALgAECgYJCAAAAA==.Monteloco:BAAALgAECgQJBAAAAA==.Moonfrost:BAAALgADCgYJBwAAAA==.Moonkitty:BAAALgADCgEJAQAAAA==.Moonmane:BAABLgAECn8lAAMcAAgJdB9oCQB0AgAcAAgJdB9oCQB0AgAkAAYJIhiWEgBTAQAAAA==.Moonmellow:BAAALgAECgcJCQAAAA==.Moosin:BAAALgAECgEJAgAAAA==.Mozgus:BAABLgAECn8tAAIhAAgJiSOPBwCxAgAhAAgJiSOPBwCxAgAAAA==.',
Mu='Munder:BAAALgAECgYJEAAAAA==.Murdurio:BAAALgAECgQJCwAAAA==.Musculate:BAAALgAECgkJEgAAAA==.',
Mx='Mxdi:BAABLgAECn8kAAQEAAkJfCJvAwBeAwAEAAkJfCJvAwBeAwAcAAIJGRDyeQA+AAAJAAEJzQ3rNgArAAAAAA==.',
My='Myranda:BAAALgADCgMJAwAAAA==.',
Na='Nazdarok:BAAALgAECgMJBAAAAA==.Nazenoth:BAAALgADCggJFwAAAA==.Nazgûl:BAABLgAECn8aAAIYAAcJ3x5zCADzAQAYAAcJ3x5zCADzAQAAAA==.',
Ne='Necrofearlia:BAABLgAECn8cAAQWAAgJihdzRgCJAQAWAAgJ0xBzRgCJAQAVAAYJQxp+DwA3AQAfAAMJqAoXTQCGAAAAAA==.Nensha:BAABLgAECn8YAAIdAAYJXhELLAANAQAdAAYJXhELLAANAQAAAA==.Nethys:BAABLgAECn8tAAMLAAkJvh3VBwCPAgALAAkJvh3VBwCPAgAgAAEJnAUAXQAoAAAAAA==.',
Ni='Nick:BAACLgAFFH8YAAIcAAcJ/RrJAQAwAgAcAAcJ/RrJAQAwAgAuAAQKfy0ABBwACQkeJFoCAJwDABwACQkeJFoCAJwDACQABgmmIFcIACgCAAQAAQnBCPLHADoAAAAA.Nightxangel:BAAALgADCgcJBwAAAA==.',
No='Noctrimm:BAAALgADCgEJAQAAAA==.Nolyt:BAABLgAECn8qAAIDAAkJ8Ak8UgCFAQADAAkJ8Ak8UgCFAQAAAA==.Nonna:BAABLgAECn8dAAIoAAgJkB1rBQCFAgAoAAgJkB1rBQCFAgAAAA==.Noolore:BAACLgAFFH8bAAMDAAUJmx25FQBNAQADAAQJmx25FQBNAQAaAAEJAAAoOQAAAAAuAAQKfy4AAgMACQkBIkkMANICAAMACQkBIkkMANICAAAA.Norandil:BAAALgAECgQJBQAAAA==.Notendela:BAAALgAECgEJAQABLgAECgYJCgARAAAAAA==.',
Nu='Nuiria:BAAALgADCgUJBQAAAA==.Nurfgun:BAABLgAECn8hAAMGAAkJryJVCQDOAgAGAAkJ1iFVCQDOAgAHAAYJ/yJIHgA0AgAAAA==.Nurfroll:BAAALgAECggJEQABLgAECgkJIQAGAK8iAA==.Nurfstrasza:BAAALgADCgYJBgABLgAECgkJIQAGAK8iAA==.',
Nw='Nwahher:BAAALgAECgMJAwAAAA==.',
Of='Offleash:BAAALgAECgcJDQAAAA==.',
Om='Ominous:BAAALgADCgYJBgAAAA==.',
On='Onefelswoop:BAAALgAECgEJAQABLgAECggJHwAUAMwRAA==.Onlock:BAAALgADCgYJBgAAAA==.Onlyfrost:BAAALgADCgcJCQAAAA==.Onlyslams:BAABLgAECn8iAAMbAAgJqhwrFwBNAgAbAAgJqhwrFwBNAgAnAAQJMAeoUwB9AAAAAA==.',
Op='Opheliana:BAAALgADCgEJAQAAAA==.',
Or='Orcsmash:BAAALgAECgUJEQAAAA==.',
Ow='Owlwithahat:BAAALgADCgcJDQAAAA==.',
Ox='Oxen:BAACLgAFFH8LAAMDAAQJrQ09ZADsAAADAAMJuQ89ZADsAAAFAAIJYgrfDACQAAAuAAQKfzEABAMACQmOITwZAGwCABoACQnVHtgJAH4CAAMACQmwHTwZAGwCAAUABwkTFp8JAGoBAAAA.',
Pa='Padraig:BAAALgADCgcJBwAAAA==.Passoot:BAAALgAECgEJBwAAAA==.',
Pe='Pega:BAAALgADCgQJBAABLgAFFAQJCgAiAPYbAA==.Pegah:BAAALgAECgMJAwAAAA==.Pege:BAACLgAFFH8KAAIiAAQJ9hsfAwBUAQAiAAQJ9hsfAwBUAQAuAAQKfyUAAiIACAlXIj0DAAADACIACAlXIj0DAAADAAAA.Penniee:BAAALgAECgMJBAAAAA==.Penniwing:BAACLgAFFH8HAAMSAAQJuBQ2KQDbAAASAAMJ4g82KQDbAAAIAAIJXwZ/HAByAAAuAAQKfycABBIACQlmHA8cAOgBABIABwmHGg8cAOgBAAgACQllCyEeAJEBABMAAQnSEqhAAC8AAAAA.Percival:BAECLgAFFH8aAAIKAAgJdho1AACXAgAKAAgJdho1AACXAgAuAAQKfyYABAoACQlcI0EAAMUDAAoACQlcI0EAAMUDAAcABQnNHP9MAB0BAAYAAwmVI/CdAJQAAAAA.',
Ph='Phaedra:BAAALgAECgkJQwAAAQ==.Phanuel:BAABLgAECn8VAAIBAAYJTg3+zABQAQABAAYJTg3+zABQAQABLgAFFAMJCwACABweAA==.Phealvoker:BAAALgADCgIJAgABLgAECgkJLAAQAJ0cAA==.',
Pi='Piffboy:BAABLgAECn8nAAMCAAkJihOLUADwAQACAAgJMhSLUADwAQAZAAQJcwoZSADFAAAAAA==.Pillargodx:BAAALgAECgEJAQAAAA==.Pissvibe:BAAALgAECgcJBwAAAA==.Pithius:BAAALgAECgIJAgAAAA==.Pixr:BAAALgAECgcJAQAAAA==.',
Po='Powrwordaddy:BAAALgADCgkJEwABLgAECggJHwAUAMwRAA==.',
Pr='Priestler:BAABLgAECn8fAAQgAAgJ4x5vCQCkAgAgAAgJ4x5vCQCkAgALAAcJgxrIHAD1AQAhAAQJFAU9VgA3AAABLgAFFAMJCwAEACIiAA==.Primeape:BAABLgAECn8hAAMaAAgJvg5pGwAoAQAaAAgJ1A1pGwAoAQADAAIJ7xNfBgFqAAAAAA==.Prodigal:BAAALgADCgUJBQAAAA==.',
Pu='Pullbarg:BAAALgAECgcJEAAAAA==.Pumpies:BAABLgAECn8WAAIIAAUJlxOSGAAAAQAIAAUJlxOSGAAAAQAAAA==.Punchdrunk:BAAALgADCgYJDQAAAA==.Purrdruid:BAAALgADCgUJBQAAAA==.',
Py='Pyru:BAAALgAECgIJAgAAAA==.',
['Pà']='Pàngde:BAAALgAECgIJAgAAAA==.',
['Pï']='Pïng:BAABLgAECn8mAAIGAAgJZxFjPgCSAQAGAAgJZxFjPgCSAQAAAA==.',
Qu='Quickkwinter:BAAALgAECgIJAwABLgAECgcJCAARAAAAAA==.Quickly:BAAALgAECgYJCQAAAA==.Quickwinnter:BAAALgAECgcJCAAAAA==.Quickwinterd:BAAALgAECgEJAQABLgAECgcJCAARAAAAAA==.Quickwinterw:BAAALgAECgEJAgABLgAECgcJCAARAAAAAA==.',
Ra='Raantoks:BAAALgAECgQJBgAAAA==.Rachet:BAABLgAECn8YAAIWAAYJegd6jgDfAAAWAAYJegd6jgDfAAAAAA==.Raelilblack:BAAALgAECgYJBwAAAA==.Raideñ:BAAALgAECgIJAwAAAA==.Rakhár:BAABLgAECn8YAAIkAAgJySDlAwCOAgAkAAgJySDlAwCOAgAAAA==.Raner:BAAALgADCgMJAwABLgAFFAQJCAAdANkQAA==.Rashala:BAAALgAECgQJDwAAAA==.Raucahann:BAAALgAECgEJAgAAAA==.Rayado:BAAALgAECgYJEgAAAA==.Razarke:BAABLgAECn8XAAITAAcJXCMTBQCxAgATAAcJXCMTBQCxAgAAAA==.',
Re='Reggienoble:BAACLgAFFH8MAAIKAAQJyha5CgBMAQAKAAQJyha5CgBMAQAuAAQKfx8AAgoACAkWJIECABoDAAoACAkWJIECABoDAAAA.Rekerî:BAAALgAECgkJDwAAAA==.Reverendmini:BAAALgAECgMJAwAAAA==.Reynaria:BAACLgAFFH8NAAInAAQJuCM+DACYAQAnAAQJuCM+DACYAQAuAAQKfykAAycACAlLIDIJAMACACcACAlLIDIJAMACAB0ABAlcFF5JAO4AAAAA.Reyyne:BAACLgAFFH8PAAIZAAQJkx9PDwBpAQAZAAQJkx9PDwBpAQAuAAQKfycAAhkACAmtIg4JAN8CABkACAmtIg4JAN8CAAAA.',
Ri='Richmage:BAAALgAECgMJBAABLgAFFAUJEAAHAE4dAA==.Rimetail:BAAALgAECgcJEwAAAA==.Rinzee:BAAALgAECgQJBgAAAA==.Rinzlrr:BAAALgAECgUJDAABLgAFFAQJCAAdANkQAA==.Rioroute:BAAALgADCgkJEQAAAA==.Rivett:BAAALgADCgUJBQAAAA==.',
Ro='Roamer:BAAALgAECgkJCQAAAA==.Roelson:BAAALgADCgEJAQAAAA==.Roflock:BAAALgADCgEJAQAAAA==.Rohrn:BAABLgAECn8oAAICAAgJbxSOUACNAQACAAgJbxSOUACNAQAAAA==.Rol:BAACLgAFFH8RAAIgAAUJKBAkEQBxAQAgAAUJKBAkEQBxAQAuAAQKfxkABCEACQkVHVsKAKcCACEACAn8HVsKAKcCACAABQmiFQ8wAB8BAAsABAlhGFhBAO4AAAAA.Rolius:BAAALgADCgQJBAAAAA==.Rosalinalove:BAAALgADCgEJAQAAAA==.Rosenylund:BAAALgAECgYJEgAAAA==.Rotfist:BAAALgADCgUJBQABLgAECggJHwADAK0KAA==.',
Ru='Ruggishbone:BAAALgAECgYJDAAAAA==.',
Ry='Rydia:BAAALgADCgQJBAAAAA==.',
Sa='Safa:BAAALgAECgYJCgABLgAECggJGgABALkbAA==.Saintjudas:BAAALgAECgYJBwAAAA==.Saintsnetie:BAAALgAECgQJCAAAAA==.',
Sc='Scottyknows:BAAALgAECggJCAAAAA==.Scottymaybe:BAAALgAECggJEgAAAA==.Scredwin:BAABLgAECn8qAAMfAAkJ2Rx4AQCOAgAfAAkJ2Rx4AQCOAgAWAAEJOQOfKQEoAAABLgAECgkJOwALAPIVAA==.',
Se='Seancody:BAAALgADCgUJBQAAAA==.Senorbobo:BAACLgAFFH8IAAIXAAMJHRcMEADlAAAXAAMJHRcMEADlAAAuAAQKfyoAAhcACAmjHssIAJICABcACAmjHssIAJICAAAA.Serenian:BAAALgAECgYJEQAAAA==.Serni:BAAALgAECgYJCgAAAA==.',
Sh='Shadora:BAAALgAECgYJDwAAAA==.Shadowsbane:BAAALgADCgUJBQAAAA==.Shadowslite:BAAALgAECgEJAQAAAA==.Shadowwolf:BAABLgAECn8hAAIEAAgJrBD3RAAyAQAEAAgJrBD3RAAyAQAAAA==.Sham:BAACLgAFFH8KAAIWAAQJbBR4LwAwAQAWAAQJbBR4LwAwAQAuAAQKfykAAxYACAn5IOcXAFwCABYACAn5IOcXAFwCAB8AAgnkD2tYAGUAAAAA.Shamios:BAABLgAECn8YAAIEAAgJ5CCAEQCqAgAEAAgJ5CCAEQCqAgAAAA==.Shammknight:BAAALgADCgkJDQAAAA==.Shanksinatrá:BAACLgAFFH8eAAMNAAcJzR0MAwDqAQANAAYJKCEMAwDqAQAOAAMJmxAmBQDzAAAuAAQKfygAAw0ACQljJncBAK4DAA0ACQlSJncBAK4DAA4ABAlOGnkPABkBAAAA.Shaquira:BAABLgAECn8dAAIGAAgJWg0DRQB6AQAGAAgJWg0DRQB6AQAAAA==.Shatt:BAAALgAECgYJCAAAAA==.Shaxxi:BAABLgAECn8aAAIEAAkJnxGrJwDMAQAEAAkJnxGrJwDMAQAAAA==.Shedari:BAAALgAECgYJBgAAAA==.Shenra:BAAALgAECgQJBAAAAA==.Shephrah:BAABLgAECn8mAAMnAAkJAQz+KQBPAQAnAAkJAQz+KQBPAQAbAAMJSAVtVwBsAAAAAA==.Shiftalic:BAAALgAFFAMJBAABLgAFFAYJEwAMAOkZAA==.Shifter:BAAALgAECgYJEAAAAA==.Shiftyjd:BAAALgADCgUJBQABLgAECgYJCgARAAAAAA==.Shoshanna:BAAALgAECgIJAgAAAA==.Shourix:BAABLgAECn8pAAIjAAcJIybYCACQAgAjAAcJIybYCACQAgAAAA==.Shploople:BAAALgAECgYJEQAAAA==.Shuckle:BAAALgAECgQJBAABLgAFFAcJGAAcAP0aAA==.Shuppet:BAAALgADCgUJDAAAAA==.',
Si='Sifuicyhot:BAABLgAECn8WAAIBAAgJFRCAWACSAQABAAgJFRCAWACSAQAAAA==.Sihnn:BAAALgAECgYJCAAAAA==.Simzerker:BAACLgAFFH8XAAIjAAcJbBySAABGAgAjAAcJbBySAABGAgAuAAQKfx4AAiMACAllJlQHADMDACMACAllJlQHADMDAAAA.',
Sk='Skwinkles:BAAALgADCgEJAQAAAA==.',
Sl='Slambulance:BAAALgADCgIJAgAAAA==.Sleepington:BAAALgAECgMJAwAAAA==.Slickrick:BAAALgAECgMJBAAAAA==.Slikshotgrey:BAAALgADCgUJBQAAAA==.Slyvex:BAAALgADCgYJCgAAAA==.',
Sm='Smûsh:BAAALgADCgIJAgAAAA==.',
Sn='Snackum:BAAALgADCgYJBgAAAA==.Snarfca:BAAALgAECgQJBAAAAA==.Sneakthief:BAAALgADCgYJBwAAAA==.Sniiffle:BAABLgAECn8tAAMEAAkJoxjCFwBBAgAEAAkJoxjCFwBBAgAcAAYJBgv8NADpAAAAAA==.Snowmage:BAACLgAFFH8IAAIeAAQJ+Q6VAAA1AQAeAAQJ+Q6VAAA1AQAuAAQKfzYAAx4ACQleIHwAAOcCAB4ACQleIHwAAOcCACkAAQm6B88QADAAAAAA.',
So='Soarscha:BAAALgAECgEJAQAAAA==.Softly:BAACLgAFFH8TAAInAAYJhhfWAQASAgAnAAYJhhfWAQASAgAuAAQKfzsAAicACQmgJjwAAOcDACcACQmgJjwAAOcDAAAA.Sokan:BAAALgADCgUJBwAAAA==.Somecutty:BAAALgADCgEJAQAAAA==.',
Sp='Spellbeard:BAAALgAECgMJAwAAAA==.Spellcrackle:BAAALgADCgkJEQABLgAECgcJEwARAAAAAA==.Sploosh:BAAALgAECgQJBAAAAA==.Spùd:BAAALgAECgEJAQAAAA==.',
Sq='Squa:BAACLgAFFH8LAAMNAAMJTyXaFQARAQANAAMJTyXaFQARAQAOAAIJ7QkGBAC1AAAuAAQKfyMAAw0ACAmnIqQKAOgCAA0ACAmnIqQKAOgCAA4ABAlyHHgMAFwBAAAA.Squiggly:BAAALgAECgEJAQAAAA==.Squishdemon:BAAALgADCgEJAQAAAA==.Squî:BAAALgAFFAEJAQABLgAFFAMJCwANAE8lAA==.',
Ss='Ssudds:BAAALgAECgYJDQABLgAFFAMJBgABADkZAA==.Ssuddychan:BAAALgAECggJEgABLgAFFAMJBgABADkZAA==.',
St='Stalagstrype:BAABLgAECn8jAAICAAgJQR/zIQA5AgACAAgJQR/zIQA5AgABLgAFFAIJBwAKAM8TAA==.Stankfu:BAAALgADCgQJBAAAAA==.Starkisses:BAABLgAECn80AAIGAAkJ0iNRBAAZAwAGAAkJ0iNRBAAZAwAAAA==.Steeb:BAAALgAECgYJCAAAAA==.Stenkeydk:BAABLgAECn8sAAMDAAkJKxS5NwDaAQADAAkJKxS5NwDaAQAFAAEJEgK8JgAdAAAAAA==.Steve:BAAALgAECgQJBAABLgAECgIJAgARAAAAAA==.Stonepaw:BAAALgADCgQJBAAAAA==.Stopthecapp:BAACLgAFFH8FAAICAAMJ/hlTOAD+AAACAAMJ/hlTOAD+AAAuAAQKfzUAAgIACQnYJdMBAGMDAAIACQnYJdMBAGMDAAEuAAQKBwkpACMAIyYA.Storebrand:BAAALgADCgcJCAABLgAECgQJBgARAAAAAA==.Storebrandps:BAAALgADCgcJDAABLgAECgQJBgARAAAAAA==.Storms:BAAALgAECgEJAQAAAA==.Stratego:BAAALgADCgUJDgAAAA==.Styrthe:BAACLgAFFH8eAAQnAAgJBBblDACNAQAnAAUJlxPlDACNAQAbAAUJpBwwBQCCAQAdAAEJIQQ0KwA6AAAuAAQKfycAAxsACQmDGfERAIUCABsACQmDGfERAIUCACcABwnGETQuAEcBAAAA.',
Su='Subotae:BAAALgADCgMJAwAAAA==.Surfacing:BAAALgAECgcJDQAAAA==.Surventval:BAAALgAFFAQJBAABLgAFFAQJCAAdANkQAA==.',
Sw='Swindler:BAACLgAFFH8GAAIDAAMJghrfVgABAQADAAMJghrfVgABAQAuAAQKfxwAAwMACAnQH/8jAC4CAAMACAnQH/8jAC4CABoABgknFQUdAGMBAAAA.Swollstone:BAABLgAECn8bAAIWAAgJ+A3STwBtAQAWAAgJ+A3STwBtAQAAAA==.',
Sy='Symphony:BAACLgAFFH8NAAIMAAQJrxjYHwBJAQAMAAQJrxjYHwBJAQAuAAQKfy8AAgwACAmVIfgTAGICAAwACAmVIfgTAGICAAAA.Syzegy:BAAALgAECgEJAwAAAA==.',
Ta='Taeka:BAAALgAECgYJEgAAAA==.Talkimas:BAABLgAECn8vAAQKAAkJnBu6BwBpAgAKAAkJDhq6BwBpAgAHAAgJNBqrGwBLAgAGAAEJAAAtwQBDAAAAAA==.Talvisota:BAABLgAECn80AAIDAAkJmiMeBgAbAwADAAkJmiMeBgAbAwAAAA==.Tankthor:BAABLgAECn81AAMjAAkJyBU9EgAYAgAjAAkJyBU9EgAYAgAXAAcJcgnmIgAnAQAAAA==.Tarirn:BAACLgAFFH8JAAIDAAIJRh05PQCkAAADAAIJRh05PQCkAAAuAAQKfxQAAgMACAl+G39SAPoBAAMACAl+G39SAPoBAAAA.Tazgrim:BAABLgAECn8UAAMfAAgJzxOPBwCKAQAfAAgJzxOPBwCKAQAWAAEJJRDiGAE2AAAAAA==.',
Te='Teflondon:BAAALgADCgQJBwAAAA==.Teknar:BAAALgAECgMJAwAAAA==.Tekos:BAAALgAECgQJBwABLgAFFAUJDQAmACcWAA==.Tekoslul:BAACLgAFFH8NAAImAAUJJxYoAgCiAQAmAAUJJxYoAgCiAQAuAAQKfx0AAyYACQkBJDMCAHQDACYACQkBJDMCAHQDAAwABwkWGEF3AN4AAAAA.Tekosp:BAAALgAECgMJBAABLgAFFAUJDQAmACcWAA==.Tekosxd:BAAALgAECgEJAwABLgAFFAUJDQAmACcWAA==.Telawolf:BAAALgADCggJCAAAAA==.Teldrussy:BAAALgAECggJCQABLgAECggJMgAhAC4fAA==.Telorian:BAABLgAECn8YAAIMAAgJzh7yJAB1AgAMAAgJzh7yJAB1AgAAAA==.Tendeda:BAAALgAECgYJCgAAAA==.Terrasite:BAAALgAECgQJBAAAAA==.',
Th='Thalunar:BAACLgAFFH8GAAIGAAMJxRwpKgAUAQAGAAMJxRwpKgAUAQAuAAQKfyEAAgYACQn5H5sPAIwCAAYACQn5H5sPAIwCAAAA.Thatonedruid:BAAALgAECgUJCgABLgAFFAMJCAAXAB0XAA==.Thejw:BAABLgAECn8aAAIGAAgJTRplJQD7AQAGAAgJTRplJQD7AQAAAA==.Thoebranne:BAAALgADCgIJAgAAAA==.Thrallzballz:BAAALgADCgYJCQAAAA==.Thrdeyethump:BAAALgAECgYJCQAAAA==.Thundrcheeks:BAAALgAECgEJAQABLgAFFAcJGAADAHgcAA==.Thörck:BAABLgAECn8VAAMTAAgJ8gVeCwAcAQATAAgJ5QVeCwAcAQASAAgJiwPUQADRAAAAAA==.',
Ti='Tidens:BAAALgAECgQJBAAAAA==.Tigersu:BAAALgAFFAEJAQAAAA==.Tinklewinkle:BAABLgAECn8uAAIeAAkJ0yFDAAAgAwAeAAkJ0yFDAAAgAwAAAA==.Titanrb:BAAALgADCgcJCwAAAA==.Titantaunt:BAAALgADCgYJBgAAAA==.',
Tj='Tjaili:BAAALgAECgcJDwAAAA==.',
To='Tocks:BAAALgAECgQJBQAAAA==.Toco:BAAALgAECgQJBAABLgAECgYJHgAQAEIiAA==.Toge:BAABLgAECn8VAAMBAAgJjSEzOQCRAgABAAgJjSEzOQCRAgAeAAEJ9AzwHgAzAAABLgAFFAgJFgAQANgTAA==.Tokapolo:BAABLgAECn8eAAIQAAYJQiKwHgAaAgAQAAYJQiKwHgAaAgAAAA==.Toluene:BAAALgAECgIJAwAAAA==.Topshelfelf:BAABLgAECn8vAAMgAAkJ/BSeFgDJAQAgAAkJWROeFgDJAQAhAAQJfQVmTgBUAAAAAA==.Torver:BAAALgAECgkJEwAAAA==.Totemsquish:BAAALgADCgEJAQAAAA==.',
Tr='Treemother:BAABLgAECn8uAAIEAAcJLhrBJgDSAQAEAAcJLhrBJgDSAQAAAA==.Treewa:BAABLgAFFH8FAAQkAAMJuhQYCgDJAAAkAAMJuhQYCgDJAAAJAAEJmgf0DQBRAAAcAAEJYQOIMwA+AAAAAA==.Treezon:BAAALgADCgMJAwAAAA==.Tresdin:BAACLgAFFH8JAAICAAQJGhLMIgA/AQACAAQJGhLMIgA/AQAuAAQKfyEAAgIACQnfIK0IAPECAAIACQnfIK0IAPECAAAA.',
Ts='Tsohg:BAAALgADCgYJCAAAAA==.',
Tu='Tuhalla:BAABLgAECn8dAAICAAkJxQovaABTAQACAAkJxQovaABTAQAAAA==.Tumlock:BAABLgAECn8sAAMfAAgJUgxNFADIAAAWAAgJbguWWgBQAQAfAAYJ/glNFADIAAAAAA==.Turbulence:BAAALgAECgQJBAAAAA==.',
Tw='Twl:BAAALgAECgQJCQAAAA==.',
['Tï']='Tïgra:BAABLgAECn83AAIMAAkJVSIoBgD5AgAMAAkJVSIoBgD5AgAAAA==.',
Ua='Uandikillhim:BAACLgAFFH8FAAIgAAMJ8RxRGwD+AAAgAAMJ8RxRGwD+AAAuAAQKfykAAiAACAmdHysIAL0CACAACAmdHysIAL0CAAAA.',
Ul='Uldren:BAAALgAECgIJAgABLgAECgkJKQANABIdAA==.',
Un='Uncompetent:BAAALgADCgEJAQAAAA==.Undeadbones:BAAALgAECgQJCAAAAA==.Unfading:BAABLgAECn83AAICAAkJsB7EEACmAgACAAkJsB7EEACmAgAAAA==.Unholyknight:BAAALgAECgcJDQAAAA==.Uninfluenced:BAAALgAECgQJBQAAAA==.Unoo:BAAALgAECgUJCAAAAA==.',
Ur='Uranus:BAABLgAECn8dAAIGAAcJnRzbNQCzAQAGAAcJnRzbNQCzAQAAAA==.Urban:BAAALgADCgEJAQAAAA==.Urtark:BAACLgAFFH8HAAIjAAIJWR/zJwCoAAAjAAIJWR/zJwCoAAAuAAQKfy8AAiMACQn9II0GALoCACMACQn9II0GALoCAAAA.',
Va='Vadym:BAAALgAECgYJEAAAAA==.Vaelia:BAAALgAECggJDwAAAA==.Vainquish:BAAALgAECgYJDQAAAA==.Valeriann:BAAALgADCgMJAwAAAA==.Valorias:BAACLgAFFH8GAAIgAAMJOwZNIQDEAAAgAAMJOwZNIQDEAAAuAAQKfyQAAiAACAlrHOcMAGoCACAACAlrHOcMAGoCAAAA.Vankwish:BAABLgAECn8hAAMeAAcJwBbaBwB/AQAeAAYJFxTaBwB/AQABAAcJqhUeZwBuAQAAAA==.Vanquith:BAAALgAECgEJAQAAAA==.Varalic:BAABLgAFFH8FAAINAAMJBBdjGAD4AAANAAMJBBdjGAD4AAABLgAFFAYJEwAMAOkZAA==.Varandra:BAAALgADCgMJAwABLgAECgMJBAARAAAAAA==.Vareesa:BAAALgAECgMJAwAAAA==.Vashet:BAAALgAECgEJAQAAAA==.Vaulken:BAAALgAECgcJDQAAAA==.Vañquish:BAAALgADCgEJAQAAAA==.',
Ve='Veggyfruit:BAABLgAECn8XAAICAAYJqhepaQCsAQACAAYJqhepaQCsAQAAAA==.Ventrois:BAACLgAFFH8IAAIdAAQJ2RCCDQAYAQAdAAQJ2RCCDQAYAQAuAAQKfygAAh0ACAlnIK8MAC0CAB0ACAlnIK8MAC0CAAAA.Verdarts:BAAALgADCgcJBwAAAA==.Veregas:BAABLgAECn8aAAIZAAkJ6hmlFwD+AQAZAAkJ6hmlFwD+AQAAAA==.Vermilion:BAAALgADCgYJCwAAAA==.Vesseven:BAACLgAFFH8KAAIjAAMJ+xbuHwDnAAAjAAMJ+xbuHwDnAAAuAAQKfyYAAiMACAm7JbQDAPoCACMACAm7JbQDAPoCAAAA.',
Vi='Viikatemies:BAAALgAECgMJBAAAAA==.Vilienar:BAAALgAECgMJAwABLgAECgMJBAARAAAAAA==.Vimao:BAAALgAECgMJAwAAAA==.Vizzy:BAAALgADCgcJBwAAAA==.',
Vo='Voidalic:BAACLgAFFH8TAAIMAAYJ6RmXBgC6AQAMAAYJ6RmXBgC6AQAuAAQKfycAAgwACAlmJTYUAN8CAAwACAlmJTYUAN8CAAAA.Voidrend:BAACLgAFFH8VAAMMAAgJtBBMBQAiAgAMAAcJtBBMBQAiAgAYAAIJ4AMZDAAnAAAuAAQKfzAAAgwACQmZIRcJAD8DAAwACQmZIRcJAD8DAAAA.Voimasta:BAAALgADCgIJAgAAAA==.',
Vu='Vuloolu:BAABLgAECn8fAAIEAAgJWBL/KQC+AQAEAAgJWBL/KQC+AQAAAA==.Vulpiena:BAAALgADCgcJBwAAAA==.Vulvaenjoyer:BAAALgAECgcJBwAAAA==.',
Vy='Vynese:BAAALgAECgEJAgAAAA==.',
['Vî']='Vî:BAABLgAECn8cAAIZAAcJHyJ7EQA/AgAZAAcJHyJ7EQA/AgAAAA==.Vîews:BAAALgAECggJEwAAAA==.',
['Vø']='Vøgue:BAABLgAECn81AAIOAAkJTxXMAwAeAgAOAAkJTxXMAwAeAgAAAA==.',
Wa='Warbidet:BAAALgAECgEJAwAAAA==.Warket:BAAALgAECgIJAgAAAA==.Warlockwally:BAAALgAECgYJEgAAAA==.Warloko:BAABLgAECn8aAAIVAAgJIh2tAwAPAgAVAAgJIh2tAwAPAgAAAA==.Warmason:BAABLgAECn8wAAIXAAgJ7BVDEACUAQAXAAgJ7BVDEACUAQAAAA==.Warpheal:BAAALgAECgUJBQABLgAECgkJLAAQAJ0cAA==.Warrida:BAAALgADCgEJAQAAAA==.Washed:BAABLgAECn8iAAMWAAgJtxS4UwBiAQAWAAcJohW4UwBiAQAfAAQJsA1HRQCgAAAAAA==.',
We='Wealthy:BAABLgAECn81AAMgAAkJTR9OAwAyAwAgAAkJTR9OAwAyAwAhAAYJOBcGLwCHAQAAAA==.Wearkit:BAAALgADCgQJBAAAAA==.Weßall:BAAALgADCgcJBwAAAA==.',
Wh='Whiskeydix:BAAALgADCgYJBgAAAA==.Whyisitdark:BAAALgADCgUJBQAAAA==.',
Wi='Wiiska:BAAALgAECgYJBgAAAA==.Wildassassjd:BAAALgADCgUJBQABLgAECgYJCgARAAAAAA==.',
Wo='Wonderful:BAAALgADCgMJAwAAAA==.',
Wr='Wrakk:BAABLgAECn8hAAINAAgJfBPpHQAPAgANAAgJfBPpHQAPAgAAAA==.Wrred:BAABLgAECn8RAAIMAAYJYxvPPwB8AQAMAAYJYxvPPwB8AQAAAA==.',
Xo='Xombi:BAAALgADCgQJBAABLgAECgYJCAARAAAAAA==.',
Xt='Xtik:BAAALgADCgcJBwAAAA==.',
Yb='Ybeavg:BAAALgADCggJCAAAAA==.',
Yd='Ydduss:BAAALgAECgcJDgABLgAFFAMJBgABADkZAA==.',
Ye='Yeahbuddy:BAAALgADCgQJBAAAAA==.',
Yu='Yumbus:BAAALgAECggJEAAAAA==.Yunai:BAAALgAECgEJAQAAAA==.',
Ze='Zemi:BAABLgAECn81AAIiAAkJQhdqBgAUAgAiAAkJQhdqBgAUAgAAAA==.Zeneragor:BAAALgAECgQJBAAAAA==.Zenethrius:BAAALgADCgMJAwAAAA==.Zevalia:BAABLgAECn8pAAMnAAgJxRj6JwB1AQAnAAYJHxj6JwB1AQAbAAgJfRCNHgB0AQAAAA==.Zevarya:BAAALgADCgEJAQABLgAECggJKQAnAMUYAA==.Zevelyon:BAAALgADCgEJAQABLgAECggJKQAnAMUYAA==.',
Zo='Zophia:BAAALgAECgEJAQAAAA==.Zorak:BAAALgAECgIJAgABLgAFFAQJDwAZAJMfAA==.',
Zt='Ztoned:BAAALgADCgUJBgAAAA==.',
Zu='Zubby:BAABLgAECn8cAAIWAAcJryAONwC9AQAWAAcJryAONwC9AQAAAA==.Zuddy:BAAALgADCgUJBQAAAA==.Zugrotic:BAAALgAECgYJCQAAAA==.Zugtrek:BAAALgADCgEJAQAAAA==.Zulakunda:BAAALgAECgYJEwAAAA==.Zummey:BAAALgADCgcJBAAAAA==.',
Zy='Zylox:BAABLgAECn8bAAILAAgJqxBlIABuAQALAAgJqxBlIABuAQAAAA==.',
['Zë']='Zëüs:BAABLgAECn8nAAIUAAcJGBabDQCSAQAUAAcJGBabDQCSAQAAAA==.',
['ßl']='ßlaððe:BAAALgADCgMJAwAAAA==.',
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
