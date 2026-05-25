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

local lookup = {'Warrior-Fury','Shaman-Restoration','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Warrior-Protection','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Paladin-Retribution','Druid-Balance','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Priest-Shadow','Monk-Brewmaster','Priest-Holy','Monk-Windwalker','Warlock-Destruction','Druid-Guardian','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Vengeance','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','DemonHunter-Devourer','Rogue-Assassination','Rogue-Outlaw','Hunter-Marksmanship','Shaman-Enhancement','Druid-Feral','Warrior-Arms','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-05-23',data={Ac='Acharon:BAABLgAECn81AAIBAAkJBRmpEgA7AgABAAkJBRmpEgA7AgAAAA==.',
Ad='Adrastus:BAAALgAECgYJDwAAAA==.',
Ae='Aeslin:BAABLgAECn8XAAICAAYJRSVPFQB0AgACAAYJRSVPFQB0AgAAAA==.',
Af='Af:BAAALgAECgUJBQABLgAFFAMJCAADAJcgAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAAALgAFFAMJBAAAAA==.Ainslie:BAAALgAECgYJCQAAAA==.',
Al='Alarashinu:BAABLgAECn8eAAIEAAcJ6wRvyADeAAAEAAcJ6wRvyADeAAAAAA==.Alataris:BAAALgADCgUJCgAAAA==.Alawae:BAABLgAECn8xAAIFAAkJjSHqAgD8AgAFAAkJjSHqAgD8AgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8WAAIGAAgJhxajEwDRAQAGAAgJhxajEwDRAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Angela:BAAALgADCgcJEAABLgAECgkJLQAHALsWAA==.Anosvoldgoad:BAAALgAECgIJAQAAAA==.',
Ap='Apaka:BAAALgADCgEJAQAAAA==.',
Ar='Araedia:BAAALgAECgYJDQABLgAECgkJJAAIADAUAA==.Arahant:BAACLgAFFH8TAAIJAAUJjxYeFQBdAQAJAAUJjxYeFQBdAQAuAAQKfzIAAgkACQkJHgENAIMCAAkACQkJHgENAIMCAAAA.Arazat:BAAALgADCgIJAgAAAA==.Aretas:BAABLgAECn80AAMKAAkJNyI2AwD1AgAKAAkJNyI2AwD1AgALAAEJthbLJQFBAAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.Arssi:BAAALgADCgIJAgAAAA==.',
As='Ashuffle:BAAALgAECgQJCwAAAA==.Asifa:BAABLgAECn8bAAIEAAYJ6BUahQBRAQAEAAYJ6BUahQBRAQAAAA==.Astinds:BAAALgADCgMJBQABLgAECgUJCAAMAAAAAA==.',
At='Atherion:BAABLgAECn8xAAIEAAgJ7BOtVgC8AQAEAAgJ7BOtVgC8AQAAAA==.Attackzilla:BAAALgAECgEJAQABLgAECggJGQAKAKwZAA==.',
Au='Aurakk:BAAALgADCgMJAwABLgAECggJJQANALEeAA==.Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJAwABLgAECgcJEQAMAAAAAA==.Avranarada:BAABLgAECn8kAAMIAAkJMBRuIAAgAgAIAAkJMBRuIAAgAgAOAAYJ4g2aOAD/AAAAAA==.',
Aw='Aw:BAAALgADCgUJBgABLgAFFAMJCAADAJcgAA==.',
Az='Azung:BAABLgAECn83AAINAAkJex/KFwCWAgANAAkJex/KFwCWAgAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8XAAIPAAUJqhmYCgANAQAPAAUJqhmYCgANAQAuAAQKfzQAAg8ACQnjI3YEAC0DAA8ACQnjI3YEAC0DAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMQAAkJEhEaCACzAQAQAAkJEhEaCACzAQARAAEJXwFrNAEUAAAAAA==.Baka:BAABLgAECn81AAMSAAgJVyXuAwBAAwASAAgJVyXuAwBAAwANAAYJNBChkQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8ZAAIGAAgJ5hmpDQDlAQAGAAgJ5hmpDQDlAQAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8RAAILAAQJ4BgQQwA/AQALAAQJ4BgQQwA/AQAuAAQKfycAAwsACAm2H34mAEYCAAsABwmcI34mAEYCAAoAAQlXCMxRACQAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECgcJBwAAAA==.Barrelrollin:BAAALgAECgYJDwAAAA==.Batrito:BAABLgAECn8tAAMHAAkJuxZtEAA/AgAHAAkJuxZtEAA/AgATAAcJuRRxJgBwAQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAABLgAECn8dAAIPAAcJBwpFagA/AQAPAAcJBwpFagA/AQAAAA==.Bearlylegál:BAAALgAFFAQJBAAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8hAAMSAAgJrhpzDwB7AgASAAgJrhpzDwB7AgANAAYJGAjrwADjAAAAAA==.Bethlahammer:BAAALgAECgQJCAABLgAECgcJEgAMAAAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQAAAA==.Billcosbrew:BAACLgAFFH8FAAIUAAMJnB80HwATAQAUAAMJnB80HwATAQAuAAQKfyMAAhQACAkHJhYEAEsDABQACAkHJhYEAEsDAAEuAAUUBAkEAAwAAAAA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgQJCwAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJIAACALQQAA==.Blizzcon:BAABLgAECn8/AAQHAAgJthbfEwASAgAHAAgJbhbfEwASAgATAAQJEQifSgC1AAAVAAIJZApkVgBVAAAAAA==.',
Bo='Borrgar:BAABLgAECn8lAAINAAgJsR7eJgBGAgANAAgJsR7eJgBGAgAAAA==.',
Br='Brackle:BAABLgAECn8tAAIPAAkJXSBeDwCuAgAPAAkJXSBeDwCuAgAAAA==.Bracori:BAACLgAFFH8RAAIJAAUJORcPFQBeAQAJAAUJORcPFQBeAQAuAAQKfywAAwkACQmnEA8oAHQBAAkACQmnEA8oAHQBABYABwnPE7IsAC8BAAAA.Brandywynne:BAABLgAECn8pAAIPAAkJvg0lPAC+AQAPAAkJvg0lPAC+AQAAAA==.Brick:BAABLgAECn86AAIDAAkJ6CMuAgAiAwADAAkJ6CMuAgAiAwAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAACLgAFFH8HAAMQAAIJAROxCACiAAAQAAIJAROxCACiAAAXAAEJgRcrGwBPAAAuAAQKfzoAAxcACQl+HaEFAOMBABAACAk9HiMFAAkCABcACAnQGaEFAOMBAAAA.Bronny:BAAALgADCgMJAwAAAA==.Brownpepperz:BAAALgADCgEJAQAAAA==.Bruticus:BAAALgADCggJCAAAAA==.',
Bu='Bubblebull:BAAALgAECgIJAwAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAECgYJDgAAAA==.Butterbllz:BAACLgAFFH8IAAINAAMJXBwuQQADAQANAAMJXBwuQQADAQAuAAQKfxsAAg0ACQnqGgJoAK8BAA0ACQnqGgJoAK8BAAAA.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn8pAAINAAgJbBMoVgCpAQANAAgJbBMoVgCpAQAAAA==.Camany:BAABLgAECn8cAAIPAAgJPhWKOwDGAQAPAAgJPhWKOwDGAQAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAUJDgATAJcNAA==.Caralath:BAAALgAECgQJBwAAAA==.Caramaulize:BAAALgAECgQJBAAAAA==.Caretakerz:BAABLgAECn8iAAIYAAcJzRwfDADlAQAYAAcJzRwfDADlAQAAAA==.Cartus:BAABLgAECn8oAAMZAAcJzgzoQwD0AAAZAAcJzgzoQwD0AAACAAUJRQXyhwCIAAAAAA==.',
Ce='Cedre:BAAALgADCgYJEgAAAA==.Celidoria:BAABLgAECn8eAAINAAgJhiBGKwB2AgANAAgJhiBGKwB2AgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Cheesepuff:BAABLgAECn8ZAAIRAAYJkwm+pwDaAAARAAYJkwm+pwDaAAAAAA==.Chikara:BAAALgAECgQJBgAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAUJFAAEAPQXAA==.Cinnibar:BAAALgADCgYJBgAAAA==.Cirï:BAAALgAECgYJDAAAAA==.Cisbick:BAABLgAECn8aAAIRAAYJxg3rngAbAQARAAYJxg3rngAbAQAAAA==.',
Cl='Clamshell:BAABLgAECn8zAAMLAAkJjyRrBABJAwALAAkJjyRrBABJAwAaAAEJAAAgMwAAAAAAAA==.Clayier:BAAALgAECgYJDwAAAA==.',
Cn='Cntendr:BAAALgAECgMJBQAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8dAAMWAAgJIh8vDQBLAgAWAAgJIh8vDQBLAgAJAAQJCg9RWQCvAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgADCgQJBAABLgAECggJJQANAKMiAA==.Corbanite:BAAALgAECgQJCQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDgAAAA==.Covertyqt:BAABLgAECn81AAIEAAkJwyJaCQAcAwAEAAkJwyJaCQAcAwAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn81AAILAAkJ0xqNHgBvAgALAAkJ0xqNHgBvAgAAAA==.',
Cr='Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgADCgEJAQAAAA==.',
['Cõ']='Cõrpses:BAEALgAECgQJBAABLgAECgkJCwAMAAAAAA==.',
Da='Daboof:BAAALgAECgEJAQAAAA==.Dabzz:BAAALgADCgMJAwAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgADCggJCwAAAA==.Daggere:BAAALgAECgEJBQAAAA==.Damaged:BAAALgAECgQJBAAAAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgAMAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAABLgAECn8aAAILAAYJugaX0wC1AAALAAYJugaX0wC1AAAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darckinz:BAABLgAECn8aAAITAAgJCwcGMQAvAQATAAgJCwcGMQAvAQAAAA==.Darkenmicky:BAABLgAECn8hAAIUAAcJoQ29MAAiAQAUAAcJoQ29MAAiAQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8TAAINAAUJWwlTPAARAQANAAUJWwlTPAARAQAuAAQKfywAAg0ACQlqH2oYANYCAA0ACQlqH2oYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAFFAEJAQAAAA==.Dayloc:BAABLgAECn81AAIRAAkJlA/uPgDIAQARAAkJlA/uPgDIAQAAAA==.',
De='Deataria:BAAALgAECgYJCwAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Deathwish:BAAALgAECgIJAgAAAA==.Delryth:BAAALgAECgUJCAAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demonatrix:BAAALgADCgEJAQAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8mAAIbAAkJYxz2AwBkAgAbAAkJYxz2AwBkAgABLgAECgkJCwAMAAAAAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAILAAkJfhBtQwDWAQALAAkJfhBtQwDWAQAAAA==.Divinetism:BAAALgAECgcJDgAAAA==.',
Dl='Dl:BAABLgAECn87AAITAAkJgx/kBwCyAgATAAkJgx/kBwCyAgAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQcAAgJGxWZFACfAQAdAAgJmBHmHwDCAQAcAAYJZBiZFACfAQAeAAEJwwdpSgAtAAAAAA==.Dragkohn:BAAALgAECgcJDQABLgAECgkJIQASABUmAA==.Dragonaged:BAAALgAECgEJAQAAAA==.Drakkarr:BAAALgAECgEJAQAAAA==.Drannek:BAAALgAECgEJAgAAAA==.Drimbirt:BAAALgAECgQJCAAAAA==.Drinkmormilk:BAABLgAECn8WAAINAAYJehSZhwBAAQANAAYJehSZhwBAAQAAAA==.Drogman:BAAALgAECgMJBAAAAA==.Droowin:BAAALgAECgIJAgABLgAECgYJDwAMAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgYJBwAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAABLgAECn8aAAIPAAgJPxdIOADSAQAPAAgJPxdIOADSAQAAAA==.',
Ed='Edensfury:BAAALgAECgcJEgAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAABLgAECn8XAAIPAAkJMBHpPgC7AQAPAAkJMBHpPgC7AQAAAA==.',
Ek='Ekthelion:BAABLgAECn8oAAIfAAcJshnKDgCpAQAfAAcJshnKDgCpAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIXAAYJaiA1CgAbAgAXAAYJaiA1CgAbAgAAAA==.Eleyert:BAABLgAECn8yAAIZAAkJqCQGAgBHAwAZAAkJqCQGAgBHAwAAAA==.Elwe:BAABLgAECn8XAAIVAAgJ2iCACQCsAgAVAAgJ2iCACQCsAgAAAA==.',
Em='Emmaga:BAABLgAECn8dAAIEAAcJZBipUwDEAQAEAAcJZBipUwDEAQAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn8oAAIPAAgJqh0mIAA8AgAPAAgJqh0mIAA8AgAAAA==.Enseth:BAABLgAECn8rAAQdAAkJXxOxGADxAQAdAAkJXxOxGADxAQAcAAQJNQfjLQCsAAAeAAMJlwYPQwBVAAAAAA==.',
Ep='Ephriam:BAAALgAECgUJBQABLgAFFAUJFAASAKMVAA==.',
Er='Erotikzombie:BAABLgAECn8YAAILAAcJgx/+OAD5AQALAAcJgx/+OAD5AQAAAA==.Errilyn:BAAALgADCgYJBgAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAABLgAECn8UAAILAAcJPxaFgwA3AQALAAcJPxaFgwA3AQABLgAECggJPwAHALYWAA==.',
Ex='Exene:BAABLgAECn8UAAMgAAkJ1wvRYgA9AQAgAAkJNAfRYgA9AQAbAAQJthFAGwC3AAAAAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAABLgAECn8yAAMDAAgJZR/JCwBEAgADAAgJHR/JCwBEAgAhAAcJcBAgCwBgAQAAAA==.Fangrell:BAAALgAECgcJBwABLgAECgkJKQAPAIEWAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAgJIgADAPkXAA==.Felcon:BAAALgAECgEJBAAAAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgYJBgABLgAECggJJQANALEeAA==.Fet:BAACLgAFFH8iAAMDAAgJ+RcZAgBeAgADAAgJ+RcZAgBeAgAiAAQJZw7YBAAjAQAuAAQKfzIAAwMACQl3JNwIAAMDAAMACQl3JNwIAAMDACIABgmjIf4GAK8BAAAA.Feyu:BAEALgAECgYJCQABLgAFFAMJBgACAKcSAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAFFAEJAQAMAAAAAA==.Fistsoiaaryn:BAAALgAECgYJEQAAAA==.',
Fl='Flatline:BAABLgAECn8YAAIHAAgJwRPyFwDnAQAHAAgJwRPyFwDnAQAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flöti:BAECLgAFFH8GAAICAAMJpxLeNgDRAAACAAMJpxLeNgDRAAAuAAQKfxgAAgIACAk+GSEdADECAAIACAk+GSEdADECAAAA.',
Fo='Four:BAABLgAECn8oAAINAAgJuRODYQCOAQANAAgJuRODYQCOAQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAABLgAECn8UAAIEAAcJ9R6ERgDsAQAEAAcJ9R6ERgDsAQAAAA==.Frysky:BAABLgAECn8UAAIYAAYJ+Q2AGQDkAAAYAAYJ+Q2AGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwAMAAAAAA==.Futz:BAABLgAECn8xAAISAAkJCCOEAgBqAwASAAkJCCOEAgBqAwAAAA==.Fuzzymage:BAAALgAECgEJAwAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAABLgAECn8hAAMPAAkJuBsWLAADAgAPAAkJuBsWLAADAgAjAAYJmQ9UQwBKAQAAAA==.Gangrell:BAAALgADCgIJAgABLgAECgkJKQAPAIEWAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.',
Go='Goobermanic:BAAALgAECgQJCAAAAA==.Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgAECgEJAgAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gp='Gpa:BAAALgADCgMJAwAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMiAAkJXxusAQCvAgAiAAkJXxusAQCvAgAhAAIJUxQFGACBAAAAAA==.Gravewin:BAAALgADCgMJBQABLgAECgYJDwAMAAAAAA==.Grendelheim:BAAALgAECgEJAQAAAA==.Grogar:BAAALgADCgMJAwAAAA==.Grumpycat:BAAALgADCgEJAQAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.Gutso:BAAALgADCgMJAwAAAA==.',
Gw='Gwynath:BAABLgAECn8gAAQVAAgJriMMBQAPAwAVAAgJriMMBQAPAwAHAAYJtxo2IQCKAQATAAEJShTiaAA9AAAAAA==.',
Ha='Hagrok:BAAALgAECgEJAQAAAA==.Haldael:BAAALgAECgUJBQAAAA==.Hammerfists:BAAALgAECgQJCQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgQJBQABLgAECggJFgAGAIcWAA==.Hantak:BAAALgAECgQJCgAAAA==.Hathaendron:BAAALgAECgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.',
He='Hemorrhagic:BAAALgADCgIJAgAAAA==.Heph:BAAALgADCgcJBwABLgADCggJGAAMAAAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIGAAgJjBNyGgA9AQAGAAgJjBNyGgA9AQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAIUAAgJ2RWFIwBwAQAUAAgJ2RWFIwBwAQABLgAECgkJCQAMAAAAAA==.Holyyballs:BAABLgAECn8aAAISAAgJRR2kEABuAgASAAgJRR2kEABuAgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgkJAwABLgAECgkJKQAPAIEWAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn84AAIWAAkJtSJaBQDbAgAWAAkJtSJaBQDbAgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.',
['Hì']='Hìroko:BAABLgAECn8eAAIRAAcJ9wT3owDhAAARAAcJ9wT3owDhAAAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.Ichigò:BAAALgAECgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQAMAAAAAA==.',
Im='Imananji:BAAALgAECgMJBAABLgAFFAUJEwAYAJEQAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8fAAIgAAkJxx1WHwA7AgAgAAkJxx1WHwA7AgAAAA==.Imperius:BAAALgAECgIJAgABLgAECgYJFwACAEUlAA==.',
In='Infernodruid:BAAALgAECgMJBQABLgAECgUJBwAMAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAABLgAECn8eAAIEAAcJzA5OhABSAQAEAAcJzA5OhABSAQAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAABLgAECn8iAAIPAAgJDRZCPQDAAQAPAAgJDRZCPQDAAQAAAA==.',
Ir='Iroh:BAABLgAECn8WAAIWAAgJYh45EAAiAgAWAAgJYh45EAAiAgAAAA==.Irondali:BAAALgADCgYJBgAAAA==.',
Is='Ismokeprot:BAAALgAECgQJCQAAAA==.',
Ja='Jainastraza:BAAALgAECgIJAgABLgAECgkJMwALAI8kAA==.Jakub:BAAALgAECgYJCQAAAA==.Jarinduva:BAAALgADCggJHAAAAA==.Jawnson:BAABLgAECn8sAAMDAAkJERcJEQD+AQADAAkJERcJEQD+AQAhAAIJ8RK8GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jekolyn:BAAALgAECgEJAgAAAA==.Jenefer:BAACLgAFFH8VAAMKAAUJmhlcEgAZAQAKAAUJmhlcEgAZAQALAAEJRgdRVgBNAAAuAAQKfzEAAgoACQnoIRsGAJ8CAAoACQnoIRsGAJ8CAAAA.Jerzak:BAAALgADCgYJDwAAAA==.',
Jo='Joemomo:BAABLgAECn8XAAIBAAgJ0Q7nLwBoAQABAAgJ0Q7nLwBoAQAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAAMAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.Joulecrafter:BAAALgAECggJCAAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kailback:BAABLgAECn8ZAAMLAAgJ/BkeQwDXAQALAAgJiBkeQwDXAQAaAAUJ1xjwCwBxAQAAAA==.Kait:BAABLgAECn83AAMCAAkJJR2wFAB5AgACAAkJJR2wFAB5AgAkAAMJ3gdBJACVAAAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECgYJCwAMAAAAAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgADCgcJCgAAAA==.Kalcifur:BAACLgAFFH8UAAISAAUJoxWsEQBrAQASAAUJoxWsEQBrAQAuAAQKfy0AAhIACQk9FwQaAA4CABIACQk9FwQaAA4CAAAA.Karper:BAAALgAECgEJAQAAAA==.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgAECgIJAgABLgAFFAUJFQAKAJoZAA==.Kasstigate:BAABLgAECn8XAAIBAAcJLBoxIgC7AQABAAcJLBoxIgC7AQABLgAFFAUJFQAKAJoZAA==.Kastiel:BAAALgAECgcJEgABLgAECggJGQAGAOYZAA==.Kathtel:BAABLgAECn8YAAIEAAgJJAsYgQBZAQAEAAgJJAsYgQBZAQAAAA==.Katstrider:BAABLgAECn8uAAIPAAkJJxrLHABPAgAPAAkJJxrLHABPAgAAAA==.Kattarea:BAAALgAECgYJCQABLgAECgkJLgAPACcaAA==.Kavica:BAAALgAECgYJDwABLgAFFAIJBQAIABQaAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8kAAIGAAgJaBueDAD6AQAGAAgJaBueDAD6AQAAAA==.Kelsier:BAAALgADCgYJBgAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8OAAILAAUJhBhiQgBAAQALAAUJhBhiQgBAAQAuAAQKfyoAAgsACQkIJUwHACADAAsACQkIJUwHACADAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgQJBAAAAA==.',
Ki='Kirigiri:BAACLgAFFH8FAAIIAAMJLgJ5QACOAAAIAAMJLgJ5QACOAAAuAAQKfx8AAwgABwnXDrRcAAABAAgABwnXDrRcAAABABgAAQkAAEA0ACUAAAEuAAUUBQkUABIAoxUA.Kirøs:BAAALgAECgUJBgAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgAECgIJAwAAAA==.',
Kn='Knom:BAAALgAECgcJEQAAAA==.',
Ko='Kohn:BAABLgAECn8hAAISAAkJFSYMCQDfAgASAAkJFSYMCQDfAgAAAA==.Kona:BAEALgAECgkJCwAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJJgANAOseAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8RAAIlAAUJGBrRAwBZAQAlAAUJGBrRAwBZAQAuAAQKfyEAAiUACQlTIusEAMYCACUACQlTIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAAALgAECgYJEAAAAA==.Lateo:BAABLgAECn9AAAIDAAkJ6hMKDgAjAgADAAkJ6hMKDgAjAgAAAA==.Lawz:BAABLgAECn8oAAQXAAgJwAfuFgDKAAAQAAcJ3AZvEgAHAQAXAAcJeAbuFgDKAAARAAcJuAOBxACmAAAAAA==.',
Le='Leafz:BAACLgAFFH8GAAIIAAMJKBIwMQDLAAAIAAMJKBIwMQDLAAAuAAQKfx8AAwgACAmRFV4pAOcBAAgACAmRFV4pAOcBAA4AAQmfDaZ3ADAAAAAA.Leaonissa:BAAALgAECgMJBAAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgEJAQAAAA==.Lemonruss:BAACLgAFFH8PAAINAAQJ3Q3RMwAnAQANAAQJ3Q3RMwAnAQAuAAQKfyEAAg0ACQkWGGksAHICAA0ACQkWGGksAHICAAAA.Leshafrierne:BAAALgAECgUJCQABLgAECgUJCwAMAAAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8hAAMXAAcJdgUUGwCtAAAXAAcJdgUUGwCtAAARAAUJhAMA0QCPAAAAAA==.',
Li='Lillika:BAAALgAECgIJAgAAAA==.Lilturtz:BAAALgAECgEJAQABLgAECggJKQAWAIUjAA==.Linnea:BAAALgAECgMJAwAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Longhorn:BAABLgAECn8iAAINAAcJ4A7EgQBLAQANAAcJ4A7EgQBLAQAAAA==.Loni:BAAALgAECgcJDwAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAAMAAAAAA==.Lortpegsalot:BAABLgAECn8mAAINAAkJ6x55IwBXAgANAAkJ6x55IwBXAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAAALgAECgQJBwAAAA==.',
Lu='Lucena:BAABLgAECn8oAAIVAAgJPB/RCwCCAgAVAAgJPB/RCwCCAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgcJDwAMAAAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Madamkluck:BAABLgAECn8oAAIIAAcJOB7xHQAzAgAIAAcJOB7xHQAzAgAAAA==.Maglubiyet:BAABLgAECn8jAAIkAAcJ1RXsDgCHAQAkAAcJ1RXsDgCHAQAAAA==.Magoz:BAAALgADCgcJDAAAAA==.Malar:BAAALgADCgUJBQAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Markyb:BAABLgAECn8uAAINAAkJwBOPOAD/AQANAAkJwBOPOAD/AQAAAA==.Masamura:BAACLgAFFH8aAAIEAAUJQR1pOABSAQAEAAUJQR1pOABSAQAuAAQKfzsAAgQACQlhIjEOAPICAAQACQlhIjEOAPICAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFgAGAIcWAA==.Maureanna:BAABLgAECn9DAAIIAAkJJxsiDwC8AgAIAAkJJxsiDwC8AgAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Mechahuntard:BAAALgADCgIJAgAAAA==.Medari:BAECLgAFFH8IAAIeAAMJoQuYGgC6AAAeAAMJoQuYGgC6AAAuAAQKfyQAAh4ACAnTF3UJACwCAB4ACAnTF3UJACwCAAAA.Medwyna:BAAALgAECgkJBQAAAA==.Melorm:BAAALgAECgMJBQAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgEJAQAAAA==.Mireille:BAAALgADCgkJFwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAABLgAECn8VAAINAAYJiRKGlgAmAQANAAYJiRKGlgAmAQAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgcJDQABLgAECggJGQANABkYAA==.Monachier:BAAALgAECgUJCwAAAA==.Moonkin:BAABLgAECn8UAAIIAAYJaxgQNgCeAQAIAAYJaxgQNgCeAQAAAA==.Moonlïght:BAABLgAECn8ZAAINAAgJGRhsWQChAQANAAgJGRhsWQChAQAAAA==.Moonrage:BAAALgADCgcJCwABLgAECggJGQANABkYAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8vAAIRAAgJiALpvAC0AAARAAgJiALpvAC0AAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8aAAIEAAgJPgyhgwBTAQAEAAgJPgyhgwBTAQAAAA==.Mosho:BAAALgAECgYJCAABLgAFFAgJIgADAPkXAA==.Mousemist:BAABLgAECn8yAAMWAAkJLRrpDgAzAgAWAAkJLRrpDgAzAgAJAAcJhAVvTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAAALgAECggJEQAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mí']='Míyágí:BAAALgAECgEJAQABLgAECgcJGwAZACEbAA==.',
['Mó']='Móldy:BAAALgAECgIJBgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJHQAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAQJBAAMAAAAAA==.Namor:BAAALgAECgEJBAAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgMJBQAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAFFAMJBwATAKwDAA==.Nedvox:BAECLgAFFH8HAAITAAMJrAPCIACtAAATAAMJrAPCIACtAAAuAAQKfyIAAhMACAmmEqQnAGgBABMACAmmEqQnAGgBAAAA.Nervous:BAAALgAECgQJCwABLgAFFAEJAQAMAAAAAA==.Nessà:BAAALgAECgUJCAAAAA==.Neveenn:BAABLgAECn8eAAMIAAgJcBakJwAXAgAIAAgJcBakJwAXAgAOAAEJfwWahAAjAAAAAA==.Neverbakdown:BAAALgAECgQJCwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Niandri:BAAALgADCgUJBgABLgAECgQJBwAMAAAAAA==.Nightpigas:BAAALgADCgkJCwABLgAECgUJEwAMAAAAAA==.',
No='Nohatcat:BAABLgAECn8pAAMWAAgJhSP5BQDOAgAWAAgJhSP5BQDOAgAJAAMJUQygfABGAAAAAA==.Notoom:BAAALgAECgYJEAAAAA==.Noxle:BAAALgADCgIJAgAAAA==.',
Ny='Nyxara:BAABLgAECn8gAAIRAAgJeRXIPwDFAQARAAgJeRXIPwDFAQAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8VAAIPAAgJ8xjFQAC0AQAPAAgJ8xjFQAC0AQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgADCgYJBQABLgAECgYJEAAMAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCggJFwAAAA==.',
Ob='Obata:BAAALgAECgYJBgAAAA==.',
Oc='Octavius:BAAALgAECgUJCwABLgAECgcJEgAMAAAAAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8XAAIaAAgJlQ5uDwAzAQAaAAgJlQ5uDwAzAQAAAA==.Ojoverde:BAACLgAFFH8QAAIRAAQJUwUaVQDwAAARAAQJUwUaVQDwAAAuAAQKfzIAAhEACQkSHB4cAGECABEACQkSHB4cAGECAAAA.',
On='Ontahli:BAAALgADCgUJBQABLgAECgkJLQAHALsWAA==.',
Op='Ophillã:BAAALgAECgEJAQABLgAECgUJCAAMAAAAAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.',
Ov='Overflare:BAAALgAECgEJAQAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugr:BAAALgAECgYJCgAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Painbreak:BAAALgADCgkJCQABLgAECgcJIgAYAM0cAA==.Pajamas:BAABLgAECn8ZAAIKAAgJrBlkFACdAQAKAAgJrBlkFACdAQAAAA==.Pallanquin:BAAALgAECgMJBQAAAA==.Pallywacker:BAABLgAECn8YAAINAAYJ4wdzwwDgAAANAAYJ4wdzwwDgAAAAAA==.Papichili:BAAALgADCgkJDQAAAA==.Pashnir:BAAALgAECgEJAQAAAA==.',
Pe='Peachey:BAABLgAECn8oAAICAAgJqBVjKQDpAQACAAgJqBVjKQDpAQAAAA==.Peaker:BAAALgAECgIJAwAAAA==.',
Ph='Phrantic:BAAALgAECgMJBQAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAAALgAECgUJEwAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAABLgAECn8hAAIIAAgJjAb3WQAJAQAIAAgJjAb3WQAJAQABLgAECgQJCAAMAAAAAA==.',
Ps='Psychosix:BAABLgAECn89AAIEAAkJNCXtAwBeAwAEAAkJNCXtAwBeAwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgAECgQJBgAAAA==.',
Qu='Quinberos:BAAALgADCgQJBAABLgAECgkJFQAfALEYAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgAECgEJAQABLgAECggJJQANALEeAA==.Raiola:BAABLgAECn8UAAQFAAYJpBHSMAD+AAAFAAYJpBHSMAD+AAAjAAMJ+AfzKwBOAAAPAAEJxgbaAwEyAAAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgAMAAAAAA==.Ramdel:BAAALgAECgcJDQABLgAECgkJKQAFABceAA==.Ramstryder:BAABLgAECn8pAAIFAAkJFx5OCAB+AgAFAAkJFx5OCAB+AgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8VAAIGAAYJ3CHAAQA2AgAGAAYJ3CHAAQA2AgAuAAQKfx8AAgYACAlrJdsCADYDAAYACAlrJdsCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgcJCAAAAA==.Rekmortal:BAABLgAFFH8LAAMmAAUJCBlVEgAJAQAmAAUJCRNVEgAJAQABAAQJ0hQkJwDfAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8pAAIPAAkJgRb1KQAMAgAPAAkJgRb1KQAMAgAAAA==.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgADCgUJBQAAAA==.Rheagall:BAABLgAECn8fAAIkAAkJZiDDAQD2AgAkAAkJZiDDAQD2AgAAAA==.Rheagnar:BAAALgADCgIJAgAAAA==.',
Ri='Rickets:BAAALgAECgEJAQAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Roaraxe:BAAALgAECgQJCAABLgAECgcJEgAMAAAAAA==.Rowena:BAABLgAECn8rAAIOAAkJiRo8FQBnAgAOAAkJiRo8FQBnAgAAAA==.Rowynna:BAABLgAECn8VAAMfAAkJsRgFDgC1AQAfAAcJihkFDgC1AQANAAIJJxawBwF8AAAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJEwAAAA==.',
Ru='Ruxspin:BAABLgAECn8bAAMWAAYJ8givQADQAAAWAAYJ8givQADQAAAJAAYJBAJGbABuAAAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIgAAYJhwmAlQDLAAAgAAYJhwmAlQDLAAAAAA==.Ryzinneko:BAACLgAFFH8LAAIIAAQJiBhBGwBIAQAIAAQJiBhBGwBIAQAuAAQKfyYAAggACQlRILsXAGYCAAgACQlRILsXAGYCAAAA.',
Sa='Sabend:BAACLgAFFH8eAAMRAAgJFA7NCACdAQARAAcJXRDNCACdAQAXAAEJYAAzHwBFAAAuAAQKfx8AAxEACAmgHWApAGsCABEACAmgHWApAGsCABcAAQkAAGRmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Safaria:BAABLgAECn8hAAIOAAgJDx7vDgBGAgAOAAgJDx7vDgBGAgAAAA==.Saloenus:BAAALgADCgYJBgAAAA==.Sarlyssa:BAAALgADCgkJEwAAAA==.Sathran:BAAALgAECgMJBAAAAA==.Saucymac:BAACLgAFFH8OAAITAAUJlw1WFQAgAQATAAUJlw1WFQAgAQAuAAQKfzMAAxMACQnAIZUEAPcCABMACQnAIZUEAPcCABUABQluHMsfAKEBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Senath:BAABLgAECn8oAAMDAAcJ8R0MHwByAQADAAYJgx0MHwByAQAhAAIJ8h6tFQCoAAAAAA==.Sephrenia:BAAALgADCgcJCwAAAA==.Seradorah:BAAALgADCgQJBAAAAA==.Serandipity:BAABLgAECn8aAAMHAAgJRhoDDwBSAgAHAAgJRhoDDwBSAgATAAQJSBDqQQDdAAABLgAFFAUJFQAKAJoZAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8fAAIEAAgJ+AtEdwBtAQAEAAgJ+AtEdwBtAQAAAA==.Shamanagans:BAAALgAECgYJEAAAAA==.Shamanigans:BAABLgAECn8gAAICAAgJtBDWMwCzAQACAAgJtBDWMwCzAQAAAA==.Shammygoat:BAABLgAECn8UAAIZAAgJPxpdHgDCAQAZAAgJPxpdHgDCAQAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwABLgAECgYJFwACAEUlAA==.Shaqattack:BAACLgAFFH8JAAIWAAQJixmxCwA/AQAWAAQJixmxCwA/AQAuAAQKfx8AAhYACAkVI0wGABwDABYACAkVI0wGABwDAAAA.Shaqattaq:BAABLgAECn8YAAQiAAcJZRcMBwCsAQAiAAcJZRcMBwCsAQAhAAUJvQtvEAAIAQADAAEJAAA4YAA1AAABLgAFFAQJCQAWAIsZAA==.Sharkmeat:BAABLgAECn8qAAITAAkJCxuvDABlAgATAAkJCxuvDABlAgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAAALgAECgcJDAAAAA==.Shawntelle:BAABLgAECn8nAAIFAAkJGSA3BQC8AgAFAAkJGSA3BQC8AgAAAA==.Shenlune:BAAALgAECgYJCgAAAA==.Sheutka:BAABLgAECn8XAAIHAAYJ8Q1kLgA4AQAHAAYJ8Q1kLgA4AQAAAA==.Shinaie:BAABLgAECn8mAAITAAgJOw7HJQB1AQATAAgJOw7HJQB1AQAAAA==.Shockanduwu:BAABLgAECn8WAAIZAAcJLxn5LQBdAQAZAAcJLxn5LQBdAQAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFgAGAIcWAA==.Shtylez:BAAALgAECgUJAgAAAA==.Shurshott:BAAALgAECgQJBAAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJLQAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwAMAAAAAA==.Sinariel:BAABLgAECn8mAAMJAAgJkhkFEwBNAgAJAAgJkhkFEwBNAgAWAAgJtRLVKgCHAQAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAABLgAECn8WAAINAAkJkgkddwBgAQANAAkJkgkddwBgAQAAAA==.',
Sm='Smitemachine:BAAALgADCgMJAwAAAA==.Smmoke:BAABLgAECn81AAIPAAkJ0x2KGQBkAgAPAAkJ0x2KGQBkAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAECgUJBwAAAA==.Sniperart:BAABLgAECn8hAAIPAAkJtxt8GQBlAgAPAAkJtxt8GQBlAgABLgAECgkJNAAKADciAA==.',
So='Sothh:BAAALgADCgYJBgABLgAECggJJQANALEeAA==.Soull:BAABLgAECn8lAAIIAAkJph0mCgD7AgAIAAkJph0mCgD7AgAAAA==.',
Sp='Spacemoo:BAABLgAECn8gAAQLAAcJUyBWOgD0AQALAAcJUyBWOgD0AQAaAAQJDBIfHAChAAAKAAEJhAFsVgAZAAAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.Squashfoot:BAAALgAECgEJAQABLgAECgcJEgAMAAAAAA==.',
St='Starface:BAACLgAFFH8TAAIYAAUJkRBSDADgAAAYAAUJkRBSDADgAAAuAAQKfzIAAxgACQknH6cDAMECABgACQknH6cDAMECAAgAAQk9AfDpABsAAAAA.Stargoose:BAAALgAECgcJBwABLgAFFAUJEwAYAJEQAA==.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgQJBQAAAA==.Stefane:BAAALgAECgcJCwAAAA==.Sterrling:BAAALgAECgMJAwAAAA==.Steverogers:BAAALgAECgUJCgABLgAFFAQJBAAMAAAAAA==.Stocktonrush:BAAALgAFFAIJAgABLgAFFAQJBAAMAAAAAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAAALgAECgYJEgAAAA==.Sturmx:BAABLgAECn81AAInAAkJsRtwBwCQAgAnAAkJsRtwBwCQAgAAAA==.',
Su='Subaaâ:BAABLgAECn8iAAMbAAgJliMGAQAzAwAbAAgJliMGAQAzAwAgAAUJIhQ9hgAaAQABLgAECgkJNQAGAHgfAA==.Subby:BAAALgADCgYJDwAAAA==.Subedei:BAACLgAFFH8JAAILAAMJUhYKcgDoAAALAAMJUhYKcgDoAAAuAAQKfy8AAwoACQlLIkUGANMCAAoACAk7IkUGANMCAAsABQmmIQxrAGoBAAAA.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAABLgAECn8XAAIYAAYJBxKNIQD+AAAYAAYJBxKNIQD+AAAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8nAAILAAgJMBNnYgCAAQALAAgJMBNnYgCAAQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCggJGAAMAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAABLgAECn8rAAInAAkJ3RekCwA2AgAnAAkJ3RekCwA2AgAAAA==.Syrony:BAAALgAECgQJBAAAAA==.',
['Sû']='Sûshealä:BAABLgAECn8WAAIVAAYJgRWAKwBJAQAVAAYJgRWAKwBJAQAAAA==.',
Ta='Tabby:BAAALgADCgkJEAAAAA==.Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn8wAAIYAAgJ9x3vBgBWAgAYAAgJ9x3vBgBWAgAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Tegen:BAAALgADCgEJAQAAAA==.Terrya:BAAALgADCgkJEQAAAA==.Teryail:BAAALgAECgcJEgAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Thaqknight:BAAALgAECgkJCQAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Therylnn:BAAALgADCgkJCQAAAA==.Theycomeforu:BAAALgAECggJCgAAAA==.Thiccklock:BAAALgAECgYJEQAAAA==.Thily:BAAALgAECgEJAQAAAA==.Thorwallen:BAAALgADCgYJDAABLgAECggJJQANALEeAA==.',
Ti='Tickle:BAABLgAECn8eAAIlAAcJOyGZBwAsAgAlAAcJOyGZBwAsAgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCwAMAAAAAA==.Tirithor:BAABLgAECn80AAINAAkJ1xUdPgDtAQANAAkJ1xUdPgDtAQAAAA==.',
To='Tockell:BAAALgAECgMJAwAAAA==.Tonakai:BAACLgAFFH8JAAIOAAUJuANZJgDIAAAOAAUJuANZJgDIAAAuAAQKfxUAAg4ACQn0F0sNAFwCAA4ACQn0F0sNAFwCAAAA.Tony:BAAALgAECgYJCgABLgAFFAMJBgADALEKAA==.Torbin:BAABLgAECn8XAAIPAAcJvghUdAApAQAPAAcJvghUdAApAQAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgAMAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trill:BAAALgAECgMJBAABLgAECgYJCwAMAAAAAA==.Trilleon:BAAALgAECgYJCwAAAA==.Trillis:BAAALgAECgIJAgABLgAECgYJCwAMAAAAAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAAMAAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.',
Tu='Turgà:BAAALgAECgEJAgABLgAECgUJCAAMAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgEJAQAAAA==.Tylîus:BAAALgAECgQJBAABLgAECgYJFgAfAKgbAA==.Tyredelsia:BAAALgADCgIJAgAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgADCgEJAQABLgAECgUJCAAMAAAAAA==.',
['Tú']='Túsk:BAAALgAECgcJCgAAAA==.',
['Tý']='Týlïus:BAABLgAECn8WAAIfAAYJqBvzEgCbAQAfAAYJqBvzEgCbAQAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCggJGAAAAA==.',
Ut='Uthilon:BAABLgAECn80AAIfAAkJSyLZAQACAwAfAAkJSyLZAQACAwAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn8pAAInAAgJvBNjFgCeAQAnAAgJvBNjFgCeAQAAAA==.',
Ve='Vedillian:BAABLgAECn8kAAIiAAgJyg02CQBuAQAiAAgJyg02CQBuAQAAAA==.Velanir:BAAALgAECgEJAgAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vendettuh:BAAALgAECgEJAQAAAA==.Vennaya:BAABLgAECn8oAAIVAAkJFgkcKwBLAQAVAAkJFgkcKwBLAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJCQAAAA==.Violentpanda:BAAALgAECgYJDgABLgAECggJLAAEALAkAA==.Vite:BAAALgADCggJIAAAAA==.Vixious:BAAALgADCgkJFQAAAA==.Vizigoth:BAABLgAECn8rAAMRAAgJ+g14WgB5AQARAAcJ+g14WgB5AQAXAAIJCxHzVwBnAAAAAA==.',
Vo='Voladon:BAABLgAECn8hAAIIAAcJcxh+KwDaAQAIAAcJcxh+KwDaAQAAAA==.Voyana:BAABLgAECn8hAAIVAAgJZxWnGADgAQAVAAgJZxWnGADgAQABLgAECggJIQAOAA8eAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAUJFAAEAPQXAA==.Vymage:BAACLgAFFH8UAAIEAAUJ9BfkQwA+AQAEAAUJ9BfkQwA+AQAuAAQKfzAAAwQACQmWItwNAPQCAAQACQmWItwNAPQCACgABAn9EHUHAOkAAAAA.',
['Vá']='Válidüs:BAACLgAFFH8dAAIVAAUJyRKTCgBmAQAVAAUJyRKTCgBmAQAuAAQKfygAAhUACQkJHsYLAJQCABUACQkJHsYLAJQCAAAA.',
['Vã']='Vãsh:BAABLgAECn8cAAQUAAcJgQdxPADrAAAUAAcJgQdxPADrAAAWAAUJZAIHbABRAAAJAAEJhgEOngAWAAAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAABLgAECn8YAAIhAAgJIw20CQB/AQAhAAgJIw20CQB/AQAAAA==.Waterlogged:BAAALgADCgMJAwAAAA==.Waterloo:BAAALgAECgEJAQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAAALgAECggJEQAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIEAAgJqAlthgBOAQAEAAgJqAlthgBOAQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.Wizpigas:BAAALgADCgUJBQABLgAECgUJEwAMAAAAAA==.',
Wr='Wrathidan:BAABLgAECn8UAAILAAgJAhClcwBXAQALAAgJAhClcwBXAQAAAA==.',
['Wì']='Wìccka:BAABLgAECn8aAAIIAAcJwBmDJAAFAgAIAAcJwBmDJAAFAgAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAAALgAECgQJBgABLgAFFAMJCAADAJcgAA==.',
Yi='Yingyang:BAAALgAECgEJAQAAAA==.',
Yo='Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAABLgAECn8cAAIJAAYJ7g6uNQAYAQAJAAYJ7g6uNQAYAQAAAA==.',
Yw='Ywontudie:BAAALgADCgYJDAAAAA==.',
Yz='Yz:BAACLgAFFH8IAAIDAAMJlyCZGQAWAQADAAMJlyCZGQAWAQAuAAQKfxwAAgMACQneIbkCAA4DAAMACQneIbkCAA4DAAAA.',
Za='Zalysi:BAABLgAECn8WAAMSAAgJHBLhJwDtAQASAAgJHBLhJwDtAQANAAIJkQdLHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAmAAMJ0himQQCKAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgAECgEJAQAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAUJEwAYAJEQAA==.',
Zh='Zhastr:BAABLgAECn8WAAImAAYJmRMgIwAfAQAmAAYJmRMgIwAfAQAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgQJBwABLgAFFAUJDQARAPgTAA==.Zlufernal:BAACLgAFFH8NAAIRAAUJ+BP/QwAcAQARAAUJ+BP/QwAcAQAuAAQKfy4AAhEACQl2IVMNAA8DABEACQl2IVMNAA8DAAAA.',
Zy='Zyn:BAABLgAECn8fAAIBAAcJig9xNgBIAQABAAcJig9xNgBIAQAAAA==.',
['Ðo']='Ðoom:BAAALgAECgQJAgAAAA==.',
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
