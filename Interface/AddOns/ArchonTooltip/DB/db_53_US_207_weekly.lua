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

local lookup = {'Monk-Windwalker','Shaman-Restoration','Mage-Arcane','Unknown-Unknown','Druid-Guardian','Paladin-Retribution','Warlock-Demonology','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Holy','Priest-Discipline','Warrior-Arms','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Hunter-Survival','Monk-Mistweaver','Warrior-Protection','DeathKnight-Frost','Shaman-Elemental','DeathKnight-Blood','Warlock-Destruction','Druid-Feral','Evoker-Devastation','Evoker-Preservation','DemonHunter-Havoc','Druid-Restoration','Evoker-Augmentation','Warrior-Fury','DeathKnight-Unholy','DemonHunter-Devourer','Mage-Frost','Shaman-Enhancement','Warlock-Affliction',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaragondelta:BAAANQAFFAIIAgABNQAFFAgIGAABABAfAA==.Aaragonius:BAAANQADCggIEAABNQAFFAgIGAABABAfAA==.Aaragonneo:BAACNQAFFIEYAAIBAAgKEB+/AADFAgABAAgKEB+/AADFAgA1AAQKgTIAAgEACQpyJtMAAOMDAAEACQpyJtMAAOMDAAAA.Aaragontheta:BAAANQADCgIIAgABNQAFFAgIGAABABAfAA==.Aaragonxeta:BAAANQADCgEIAQABNQAFFAgIGAABABAfAA==.',
Ab='Ablé:BAABNQAECoEeAAICAAcKnhkwVQDlAQACAAcKnhkwVQDlAQAAAA==.',
Ac='Ackreseth:BAAANQAECgcICgAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQAECgIIBAAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aerae:BAAANQADCggIDwAAAA==.Aergoss:BAAANQAECgIJAgAAAA==.Aeristeia:BAABNQAECoEiAAIDAAgKdh73UQDMAgADAAgKdh73UQDMAgAAAA==.Aethyria:BAAANQADCgYIBgABNQAECgUIBwAEAAAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAYIHgAFAHElAA==.',
Ai='Aiee:BAABNQAECoEXAAIGAAgKfxh6ZgA7AgAGAAgKfxh6ZgA7AgAAAA==.Aizén:BAABNQAECoEfAAIHAAkK4hsdJQDXAgAHAAkK4hsdJQDXAgAAAA==.',
Al='Allaboutme:BAAANQADCgUJBgAAAA==.Aloha:BAAANQADCgYIBgAAAA==.',
Am='Amad:BAAANQAECgUIBQAAAA==.Amorha:BAAANQADCgQIBAAAAA==.Amourn:BAAANQAECgMIBAAAAA==.',
An='Analrek:BAAANQAECggIEgAAAA==.Antekhrestos:BAAANQADCgQIBAAAAA==.Antoinedruid:BAABNQAECoErAAIIAAkKsx8XFAARAwAIAAkKsx8XFAARAwABNQAFFAcIEgAJAGoVAA==.',
Ap='Apocalypsis:BAAANQAECgYIDwABNQAECgkJJAAKALAQAA==.Apodal:BAABNQAECoEYAAILAAkKXAvpEgCWAQALAAkKXAvpEgCWAQABNQAFFAgIFwAMAK0cAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arih:BAAANQADCgUIDAAAAA==.Arock:BAABNQAECoEeAAICAAkKwxszIgDAAgACAAkKwxszIgDAAgAAAA==.Arrithion:BAABNQAECoEZAAIDAAgKAxAIrgAEAgADAAgKAxAIrgAEAgAAAA==.Arthaz:BAACNQAFFIESAAMJAAcKahV1AgA5AgAJAAcKahV1AgA5AgANAAEKqx9MKABhAAA1AAQKgSwAAwkACQpvJZcCAKsDAAkACQpvJZcCAKsDAA4AAgrqDUkcAGcAAAAA.',
As='Asgorath:BAAANQAECgQIBQAAAA==.Astandra:BAAANQAECgMIBAAAAA==.Astro:BAAANQADCgIIAgABNQAECgkJJAADADggAA==.Aszúne:BAAANQAECgIIAgAAAA==.',
At='Atexnogaraa:BAABNQAECoEYAAIGAAkK6xoXVgBqAgAGAAkK6xoXVgBqAgABNQAFFAgIGAABABAfAA==.',
Av='Averelles:BAABNQAECoEqAAINAAgK0Qj/dQCAAQANAAgK0Qj/dQCAAQAAAA==.',
Aw='Awarlock:BAAANQADCgYIBgAAAA==.Awwik:BAABNQAECoEcAAIPAAgKAhrDXQBWAgAPAAgKAhrDXQBWAgAAAA==.',
Az='Azsharaa:BAAANQAECgcIBwAAAA==.',
Ba='Babyjojo:BAAANQAECgYICwAAAA==.Badaboomkin:BAAANQAECgcIEgABNQAFFAEIAQAEAAAAAA==.Baeldun:BAABNQAECoEfAAIDAAgKGhpMfQBsAgADAAgKGhpMfQBsAgAAAA==.Baethoven:BAABNQAECoEXAAIBAAcKOw2hLwBlAQABAAcKOw2hLwBlAQAAAA==.Bagagwa:BAAANQAECgYIBwAAAA==.Ballzac:BAAANQADCggICAAAAA==.Ballzout:BAAANQAECgcIDQABNQAFFAEIAQAEAAAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAABNQAECoEVAAIPAAYKMx6xegAGAgAPAAYKMx6xegAGAgABNQAECgkJIwAHAHYiAA==.',
Be='Beaconbilly:BAABNQAECoEcAAMQAAgKnR7UDgCKAgAQAAgKnR7UDgCKAgARAAgKERZqPwBJAgAAAA==.Bearmanpig:BAAANQAECgUICwAAAA==.Beelzemoan:BAAANQAECgUIEQAAAA==.Beens:BAACNQAFFIERAAMKAAcKhyJjBAACAgAKAAYKLSFjBAACAgASAAIKnSJDGAC+AAA1AAQKgS0AAgoACQpaJlkCALcDAAoACQpaJlkCALcDAAAA.Beewitched:BAAANQAECgQIDQAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAABNQAECoEYAAIRAAkKJw0BSwAdAgARAAkKJw0BSwAdAgABNQAFFAgIGAANAF0jAA==.Benkaz:BAAANQAECgYIDwABNQAFFAUIBgAPAGAJAA==.Bennszülött:BAAANQAECgUIBQABNQAECgYIDAAEAAAAAA==.',
Bi='Bierhops:BAAANQADCgcIBwAAAA==.Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Blacktacular:BAAANQADCgQIBAAAAA==.Bloodlust:BAABNQAECoEbAAIIAAkKIBMdMAA7AgAIAAkKIBMdMAA7AgABNQAECgkJMQARAGYaAA==.Bluedaemon:BAAANQAECgUIDgAAAA==.Bluenchi:BAAANQADCggICwABNQAFFAMIBwADAG4eAA==.Blunttruama:BAAANQAECgUIDwAAAA==.',
Br='Breadbowl:BAABNQAECoEYAAMRAAkK1RCwSAAlAgARAAkK1RCwSAAlAgAGAAEKkg4PaQE8AAAAAA==.Brontide:BAAANQAECgcICQABNQAECgYIDwAEAAAAAA==.Brrzerk:BAAANQAECgEIAQAAAA==.Brrzrrq:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesburst:BAAANQAECgMIAwABNQAECgQIDQAEAAAAAA==.Bubblëdin:BAAANQADCgYICgABNQAECgUIDgAEAAAAAA==.Buckee:BAABNQAECoEgAAMTAAgKYhVqGgDyAQATAAcK6RRqGgDyAQAUAAIKzRGgdQCBAAAAAA==.Buckets:BAAANQADCgcIGwAAAA==.Bucknutt:BAABNQAECoEUAAINAAcKeBjXTwAKAgANAAcKeBjXTwAKAgAAAA==.Buenonoches:BAAANQADCgcIBwAAAA==.Buffoutlaw:BAABNQAECoEbAAIVAAkKqiKQAgAWAwAVAAkKqiKQAgAWAwABNQAFFAgIGAAVAPMmAA==.Bullzzeye:BAABNQAECoEVAAMSAAkKcyD4NwCgAgASAAkK/R/4NwCgAgAWAAMKPhHKDQCYAAAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgcIBwAAAA==.',
Ca='Cabe:BAABNQAECoEWAAIFAAgKxwV0JwATAQAFAAgKxwV0JwATAQAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQAECgIIAgAAAA==.Cailber:BAAANQADCgUIBwABNQAECgUIBwAEAAAAAA==.Callipriest:BAAANQAECgQICgAAAA==.Callmetim:BAAANQAECggIBwAAAA==.Castermaster:BAABNQAECoEYAAIDAAcKhBoJlQA5AgADAAcKhBoJlQA5AgAAAA==.',
Ce='Celthrinor:BAAANQAFFAIIAgAAAA==.Cerevistra:BAAANQADCgEIAQAAAA==.',
Ch='Chaeni:BAAANQADCgcICQAAAA==.Chakkah:BAAANQADCgQIBAAAAA==.Chillyy:BAABNQAECoEjAAMXAAkKtRkrDAChAgAXAAkKtRkrDAChAgABAAEK9AThaAAhAAAAAA==.Chipss:BAAANQAECgQIBwAAAA==.Chispot:BAAANQAECgEJAgAAAA==.Chitorpedo:BAAANQAECgQIBgAAAA==.Chodester:BAAANQADCgUIBQAAAA==.Chokyo:BAAANQAECgYIEQAAAA==.Chronis:BAAANQABCgYICgAAAA==.',
Ci='Cidel:BAAANQAECgQIBwAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgYIDwAAAA==.Comeback:BAAANQADCggIEwAAAA==.Course:BAAANQADCgIIAgAAAA==.',
Cr='Crackalaks:BAAANQAECgUIEAAAAA==.Crazyb:BAABNQAECoEfAAITAAcKuA5hIAC2AQATAAcKuA5hIAC2AQAAAA==.Croith:BAABNQAECoElAAIYAAgKihdUDgAcAgAYAAgKihdUDgAcAgAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Crushbucket:BAAANQADCgQIBAAAAA==.Cryingorc:BAAANQAECgEIAQAAAA==.Crúz:BAAANQAECgMIBQABNQAECggIGAAZAOEWAA==.',
Cw='Cwap:BAAANQAECgIIAgAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYJBgAAAA==.',
Da='Daddywaumpus:BAAANQAECgMIAwAAAA==.Dageris:BAABNQAECoEYAAISAAgKHwtlcwD8AQASAAgKHwtlcwD8AQAAAA==.Damonic:BAAANQAECgMIAwABNQAFFAEIAQAEAAAAAA==.Danas:BAAANQADCggIDgAAAA==.Dargothous:BAAANQAECgMIAgAAAA==.Darksector:BAAANQADCgQIBAAAAA==.Darkwraith:BAAANQABCgUICAABNQAECgEIAQAEAAAAAA==.Datsyaass:BAAANQADCgcIBwAAAA==.Davicurn:BAAANQADCggIEAAAAA==.Dawtsfoevah:BAAANQABCgQIBQAAAA==.Daythyme:BAEANQAECgIIAgAAAA==.',
De='Deadornot:BAABNQAECoEdAAIaAAgK8x6FJwDEAgAaAAgK8x6FJwDEAgAAAA==.Deadywaumpus:BAABNQAECoEkAAIbAAkKYxpsHgClAgAbAAkKYxpsHgClAgAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDwAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQAECgUICwABNQAECgcIDAAEAAAAAA==.Deeztotemz:BAAANQAECgIIAwAAAA==.Demairis:BAAANQADCgcIBwAAAA==.Demonstyle:BAAANQAECgIIAgABNQAECgYIDwAEAAAAAA==.Desiiria:BAAANQAECgEIAQAAAA==.Deylicious:BAABNQAECoEVAAMNAAgKjCHqEQAlAwANAAgKjCHqEQAlAwAJAAIK/QzbVwB5AAABNQAFFAgIGAASALYeAA==.',
Dh='Dhani:BAAANQAECgUIEQAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIEQAAAA==.Diiemoar:BAABNQAECoEWAAMHAAcKSw8IjQCXAQAHAAcKSw8IjQCXAQAcAAEKLggcdgAxAAAAAA==.Dijoe:BAAANQAECgQIDQAAAA==.Dimmencius:BAAANQAECgQICQAAAA==.Dippndotz:BAABNQAECoEfAAMcAAkKmRmKGgCQAQAHAAcKUxklbQDvAQAcAAcKqxKKGgCQAQAAAA==.Discfunction:BAAANQAECgIIAgAAAA==.Disciple:BAAANQADCgYIBgAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAABNQAECoEnAAIdAAgKBRxqCACdAgAdAAgKBRxqCACdAgAAAA==.Dohvahkiin:BAAANQAECgUICAAAAA==.Dontlosmë:BAAANQAECgUIDgAAAA==.',
Dr='Draaragon:BAAANQADCggICwABNQAFFAgIGAABABAfAA==.Dracgutx:BAAANQADCggIGAAAAA==.Dragonboffa:BAAANQADCgYIEgAAAA==.Dragonlyfans:BAABNQAECoEoAAMeAAkKNRovDACKAgAeAAkKNRovDACKAgAfAAgKIw/xHADfAQABNQAFFAgIFgAIANMgAA==.Dripz:BAABNQAECoEbAAISAAgKFRzSMgCxAgASAAgKFRzSMgCxAgAAAA==.Drive:BAAANQAECggIEQAAAA==.Drumatic:BAAANQAECggICQAAAA==.Drunken:BAAANQADCggIFQAAAA==.Dryadwood:BAAANQADCgcIDQAAAA==.',
Du='Dubby:BAACNQAFFIEFAAIIAAIKsgxBGwCWAAAIAAIKsgxBGwCWAAA1AAQKgR4AAggACQo4HYAfALMCAAgACQo4HYAfALMCAAAA.Duelley:BAAANQABCgYICQAAAA==.Dumptruckdan:BAABNQAECoEdAAIGAAkK2BV5dAAWAgAGAAkK2BV5dAAWAgABNQAFFAgIGQADABQcAA==.Durgur:BAAANQAECgUIBwABNQAECgcJEAAEAAAAAA==.',
Ea='Eardi:BAAANQAECggIDQAAAA==.Earthpounder:BAABNQAECoEcAAISAAcKrRIrcQABAgASAAcKrRIrcQABAgAAAA==.',
Ec='Echoez:BAABNQAECoEhAAIXAAkK6wyLGADFAQAXAAkK6wyLGADFAQAAAA==.Eclipsa:BAAANQAECgUIDgAAAA==.Ecohez:BAAANQABCgcIBwABNQAECgkJIQAXAOsMAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAABNQAECggIHAAgAJghAA==.Elledramoc:BAAANQABCgEIAQAAAA==.Elunasolz:BAEANQADCggIJAABNQAECgQIBgAEAAAAAA==.',
Em='Emilil:BAAANQADCggIDAAAAA==.Eminence:BAAANQADCggIFgAAAA==.',
En='Enlight:BAAANQABCgMIAwAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECggIGwAGABYbAA==.',
Es='Escanor:BAAANQAECgIIAgAAAA==.Esu:BAAANQAECgIIBAAAAA==.',
Et='Etro:BAAANQADCgcIBwAAAA==.',
Eu='Eudaimonia:BAAANQADCgYIDwAAAA==.',
Ex='Exias:BAAANQADCggIGQAAAA==.',
Ey='Eyejuice:BAAANQAECgMIBAAAAA==.',
Fa='Facebeata:BAABNQAECoEkAAQKAAkKsBC9LgCvAQAKAAgKQgy9LgCvAQASAAUKPxO1swBoAQAWAAEKkgcNEgAuAAAAAA==.Fahlstad:BAAANQAECgQIBAAAAA==.Faize:BAAANQADCggIDgABNQAFFAUIDAAhALQHAA==.Falae:BAAANQAECgQICAABNQAFFAYICwARAHgNAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Fattfoot:BAAANQADCgQIBAAAAA==.Faunuis:BAACNQAFFIEWAAMIAAgK0yDMBgDwAQAIAAUKgiXMBgDwAQAhAAMKqhvXCAAaAQA1AAQKgSUAAwgACQrCJscBANsDAAgACQrCJscBANsDACEABgqKHespAJwBAAAA.Fawnbby:BAAANQAECgUIBQAAAA==.Faüst:BAAANQADCgQIBAABNQAECgkJKwANAD8iAA==.',
Fe='Fearthebeef:BAAANQABCgEIAQABNQAECggIHAAPAAIaAA==.Featherbrain:BAAANQAECgYIDwAAAA==.Felhell:BAAANQAECgQICAABNQAECgkJIwAXALUZAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAABNQAECoElAAIDAAgK9QrKxgDTAQADAAgK9QrKxgDTAQAAAA==.',
Fi='Fistflurry:BAAANQAECgUIBgABNQAFFAEIAQAEAAAAAA==.Fistlad:BAACNQAFFIEXAAMeAAgKvSUYAAAFAwAeAAcKsSYYAAAFAwAiAAEKEx+tCABlAAA1AAQKgSQAAh4ACQoHJy0AAP8DAB4ACQoHJy0AAP8DAAAA.Fizzybubbles:BAABNQAECoEkAAICAAgK0R5IJwCnAgACAAgK0R5IJwCnAgAAAA==.',
Fl='Flamehunter:BAAANQAECggIEwAAAA==.Flapple:BAACNQAFFIEMAAIeAAUK4hAuBACBAQAeAAUK4hAuBACBAQA1AAQKgS0AAh4ACQr5I8ACAHcDAB4ACQr5I8ACAHcDAAAA.Fleshgrind:BAAANQADCgQIBAAAAA==.Flexicution:BAAANQADCgYIBgABNQAECgQIBAAEAAAAAA==.Flexo:BAAANQADCgIIAgAAAA==.Floweret:BAAANQAECgcICQABNQAECgcIEQAEAAAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Fluffalicous:BAAANQAFFAIIAgAAAA==.Flûffy:BAAANQAECgUIDAAAAA==.',
Fr='Freaknikk:BAAANQAECgcIEwABNQAECgYIDgAEAAAAAA==.Freakuency:BAAANQABCgYICgAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECggIHgAEAAAAAQ==.Frozalth:BAAANQADCgUJBgAAAA==.',
Fu='Fudgemuffin:BAAANQAFFAIIAwAAAA==.Furyofgnomes:BAAANQADCgEIAQABNQADCgYIBgAEAAAAAA==.Fuzziewuzzie:BAAANQAECgEIAQAAAA==.',
Fx='Fxaweqzdpal:BAAANQAECgQIBQABNQAFFAcIIQAhABIjAA==.',
['Fë']='Fënrïr:BAAANQAECgMIBgABNQAECgkJLQAaAOwhAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Galice:BAAANQAECgQJBAAAAA==.Gardasil:BAAANQAECggIAgAAAA==.Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAABNQAECoEdAAIeAAkKjSHzAwBSAwAeAAkKjSHzAwBSAwABNQAFFAgIGQADABQcAA==.',
Ge='Gellysong:BAAANQABCgQJBgAAAA==.Genos:BAAANQAECgcICAAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gingersteve:BAAANQADCgcIBwAAAA==.Gix:BAAANQAECgEIAQAAAA==.',
Gl='Glolock:BAABNQAECoEcAAMHAAgKwR2IMQCoAgAHAAgKwR2IMQCoAgAcAAIKiwkgWwBmAAAAAA==.Glopanx:BAAANQAECgEIAQABNQAECggIHAAHAMEdAA==.',
Go='Goresnot:BAAANQAECgUIBgAAAA==.Gorgygrinds:BAAANQABCgUIBwAAAA==.',
Gr='Gravedarknes:BAACNQAFFIENAAMjAAUKIBg8AQAPAQAjAAMK3ho8AQAPAQAPAAIKAxSXJACbAAA1AAQKgRkAAyMACAoGIQ0SAFsBAA8ABgr8HfKIAOABACMABAqbIg0SAFsBAAAA.Greendog:BAAANQADCgIIAgABNQAECgcILQAGABEMAA==.Grievur:BAAANQAECgQICAABNQAECggIHAAPAP4WAA==.',
Gu='Guap:BAABNQAECoEYAAIDAAkKzBmZkgA+AgADAAkKzBmZkgA+AgABNQAFFAgIFwAeAL0lAA==.Guineasaurus:BAAANQADCgYIEAAAAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQAECgUICAAAAA==.Gutx:BAAANQAECgQICQAAAA==.',
Gy='Gyarrados:BAAANQADCgYIEAAAAA==.Gypsywolfe:BAAANQAECgUICwAAAA==.',
['Gí']='Gífted:BAABNQAECoEnAAIDAAkKxRe0cQCEAgADAAkKxRe0cQCEAgAAAA==.',
['Gü']='Günz:BAAANQABCgEIAQAAAA==.',
Ha='Hakasan:BAAANQAECgUIBQABNQAFFAEIAQAEAAAAAA==.Haleybeary:BAAANQAECgMIBgAAAA==.Hallowevez:BAAANQADCgYIBgAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQAECgUIBQAAAA==.Hastega:BAABNQAECoEdAAIHAAUKfhFwtQA0AQAHAAUKfhFwtQA0AQAAAA==.Haydonk:BAAANQADCgcIBwAAAA==.',
He='Herbage:BAABNQAECoEcAAINAAcKVhwtSAAnAgANAAcKVhwtSAAnAgAAAA==.Herrbjorn:BAAANQAECgMIBgAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQAECgUICgAAAA==.Hitaman:BAAANQAECgUICgAAAA==.',
Ho='Holik:BAAANQABCgEIAQAAAA==.Holybaguette:BAAANQAECgUICwAAAA==.Holycritbro:BAAANQAECgIIBQAAAA==.Horôn:BAAANQAECgcICAAAAA==.Hotgirlmegan:BAAANQAECggIDgAAAA==.Houndoomm:BAAANQADCggIHQAAAA==.',
Hr='Hriste:BAAANQAECgUIEgAAAA==.',
Hu='Hugepenances:BAAANQAECgQIBgAAAA==.Humptime:BAAANQADCgQIBAAAAA==.Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQAECgIIAgAAAA==.',
['Hô']='Hôrôn:BAAANQADCgYICgAAAA==.',
Il='Iloveturtle:BAAANQADCgIIAgAAAA==.',
Im='Imnosickmall:BAAANQAECgcIEQAAAA==.Impmafia:BAAANQAECgMIAgAAAA==.',
In='Incognetus:BAAANQAECggIHgAAAQ==.Insurrection:BAABNQAECoEVAAIRAAYK9BwJVQD6AQARAAYK9BwJVQD6AQABNQAECggIKQABAIkcAA==.',
Ir='Ironmaiiden:BAAANQAECgIIAwAAAA==.Ironpally:BAABNQAECoEeAAMGAAcKHRXMigDdAQAGAAcKHRXMigDdAQARAAMKkAUu4ACPAAAAAA==.',
Iw='Iwantmead:BAAANQABCgMIAwAAAA==.',
Ja='Jadziä:BAAANQAECgMIAwAAAA==.Jaes:BAAANQAECgQJBQABNQAFFAYICwARAHgNAA==.Jaesedar:BAABNQAFFIELAAIRAAYKeA3GBwC/AQARAAYKeA3GBwC/AQAAAA==.Jankizzle:BAAANQADCggIFgAAAA==.Jaycen:BAAANQAECgYIDwABNQAECggIHgAEAAAAAQ==.',
Je='Jellythug:BAABNQAECoEYAAMBAAgKpw/AJwCwAQABAAgK5A7AJwCwAQALAAEKyAdrMAAiAAAAAA==.Jenny:BAAANQAFFAEIAQAAAA==.Jerboa:BAAANQADCgQIBAAAAA==.Jerksnknight:BAABNQAECoEZAAIkAAgKuwpcWgB/AQAkAAgKuwpcWgB/AQAAAA==.Jethon:BAAANQADCgcIDwAAAA==.Jexro:BAABNQAECoEvAAIlAAkKGCXoAgCpAwAlAAkKGCXoAgCpAwAAAA==.Jezebaal:BAAANQAECgQIBQAAAA==.',
Jg='Jgremlin:BAAANQADCgUICAAAAA==.',
Ji='Jiun:BAAANQAECgMJAwAAAA==.',
Jo='Jobafett:BAAANQADCgIIAgAAAA==.Jobiwan:BAAANQADCgMIAwAAAA==.Joeroguein:BAAANQAECgEIAQAAAA==.Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAEANQAECgQICQAAAA==.Joshton:BAAANQADCgUIBgAAAA==.',
Jr='Jrrd:BAAANQAECgYICQAAAA==.',
Ju='Judgmentoe:BAAANQAECgQIBQAAAA==.Jusstice:BAABNQAECoEbAAISAAcKCArCmQChAQASAAcKCArCmQChAQAAAA==.',
Ka='Kack:BAAANQAECgYIDgAAAA==.Kadzageth:BAAANQAECgYICwAAAA==.Kalvosa:BAAANQADCgYIFwAAAA==.Kanglizard:BAAANQAECgEIAgAAAA==.Karlbarx:BAAANQAECgcIDAAAAA==.Kasaa:BAABNQAECoEeAAMUAAcKKQ90OQCuAQAUAAcKKQ90OQCuAQATAAMKrgJxQQB9AAAAAA==.Kasheira:BAAANQAECgYIEQAAAA==.Katti:BAAANQAECgYIDwAAAA==.Katzfiel:BAABNQAECoEcAAMhAAgKNwwhKgCbAQAhAAgKNwwhKgCbAQAIAAIKkQIhmQBFAAAAAA==.Kaytwo:BAACNQAFFIEXAAIPAAcKQCVyAQDaAgAPAAcKQCVyAQDaAgA1AAQKgR8AAg8ACQpsJhETAGcDAA8ACQpsJhETAGcDAAAA.',
Kb='Kblasti:BAAANQAECgQICAABNQAECgkJJgAIAJQjAA==.Kblastissimo:BAABNQAECoEmAAIIAAkKlCMNBgCbAwAIAAkKlCMNBgCbAwAAAA==.',
Kc='Kcommandr:BAAANQAECgQIBAABNQAECggIHgAaAHohAA==.',
Ke='Keltorik:BAAANQAECgIIAQAAAA==.Kendramp:BAAANQAECgYICwAAAA==.Kerrana:BAAANQADCgEIAQABNQAFFAYICwARAHgNAA==.Kersplode:BAAANQAECgUICgABNQAECggIIwASAMAcAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAABNQAECoEkAAMQAAcKogvsMQAoAQAQAAcKogvsMQAoAQAGAAEKCgF1rQEKAAAAAA==.Kieralyn:BAAANQAECgEIAgAAAA==.Kiltlifter:BAAANQAECgMIBgAAAA==.Kisol:BAAANQADCgYIBgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kojohunter:BAAANQAECgEIAQAAAA==.Kong:BAAANQAECgUIBgAAAA==.Kookta:BAABNQAECoEeAAIGAAkK8Rz9PwCwAgAGAAkK8Rz9PwCwAgAAAA==.Kozmo:BAAANQAECgYIDgAAAA==.',
Kr='Kreep:BAAANQAECgUIDQAAAA==.Kreepur:BAAANQAECgEIAQAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQAECgcIEAABNQAFFAUIDgABAFoRAA==.Kurai:BAABNQAECoEjAAILAAgKmg4yEwCRAQALAAgKmg4yEwCRAQAAAA==.Kutaki:BAAANQAECgMIBQABNQABCgMIAwAEAAAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECggIIwASAMAcAA==.',
['Kô']='Kôvu:BAAANQAFFAIIAgAAAA==.',
La='Lasrin:BAACNQAFFIEOAAIGAAUKkhUfCACgAQAGAAUKkhUfCACgAQA1AAQKgSMAAgYACQrWH0AuAPECAAYACQrWH0AuAPECAAAA.Lavenia:BAAANQADCggIDAAAAA==.',
Lc='Lcboss:BAAANQAECgUICwAAAA==.',
Ld='Ldawg:BAABNQAECoEiAAMDAAgKIAnD5wCUAQADAAgK+gjD5wCUAQAmAAEKzAK3RgAqAAAAAA==.',
Le='Leastzenmonk:BAAANQAECgYIDgABNQAFFAcIEAACAHoXAA==.Lelu:BAAANQADCgUIBQAAAA==.Leucetios:BAAANQAECgQIDAAAAA==.',
Li='Liello:BAAANQAECgIIAgAAAA==.Liethem:BAAANQADCgYIBgAAAA==.Lightchaos:BAAANQAECgYIBgABNQAECggICgAEAAAAAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAACNQAFFIEOAAMJAAUKtx6SBwBsAQAJAAQKsiCSBwBsAQANAAIKtAZOJgCJAAA1AAQKgSUAAgkACQqYH/MQAM8CAAkACQqYH/MQAM8CAAAA.Lilgaypunkk:BAAANQAFFAEIAQABNQAFFAUIDgAJALceAA==.Litestone:BAAANQADCgYIBgAAAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Lockfocks:BAAANQADCggICAABNQAECgEIAQAEAAAAAA==.Locoscar:BAACNQAFFIESAAISAAYKjharAwAEAgASAAYKjharAwAEAgA1AAQKgSwAAxIACQq9JRgHAJkDABIACQq9JRgHAJkDAAoABArcFBtRALsAAAAA.Logix:BAAANQADCgYIBAAAAA==.Loktark:BAACNQAFFIEYAAIVAAgK8yYDAAAgAwAVAAgK8yYDAAAgAwA1AAQKgSoAAhUACQrFJjsAAOQDABUACQrFJjsAAOQDAAAA.Lootini:BAAANQAECggIEAAAAA==.Lotei:BAABNQAECoEVAAMSAAYKOhh5gwDVAQASAAYKOhh5gwDVAQAKAAQK8Qg2TwDEAAAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgABNQAECgYICAAEAAAAAA==.Lucresh:BAAANQADCgYIBgAAAA==.Luhari:BAAANQAECgQIBAAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQAECgQIBQABNQAECgQIBgAEAAAAAA==.Lustíé:BAAANQAECgYIDwAAAA==.',
Ly='Lythinlock:BAAANQAECgQIBwAAAA==.Lythinmk:BAAANQAECgcICwAAAA==.',
['Là']='Lànthus:BAAANQAECggICgAAAA==.',
['Lê']='Lêêrøy:BAAANQADCgYIFAAAAA==.',
Ma='Magedood:BAAANQAECgUIEQAAAA==.Magev:BAABNQAECoEcAAMDAAcKkB+wyQDNAQADAAUKnCGwyQDNAQAmAAIKchoYKACPAAAAAA==.Maggerz:BAAANQADCgMJAwAAAA==.Magiccheif:BAAANQAECgUIEQAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Mailei:BAAANQADCggICAAAAA==.Maisharona:BAAANQADCgYIDAABNQAECggIHAADAMQiAA==.Makanir:BAAANQAECgcICwAAAA==.Maleficent:BAAANQAECgUIBwAAAA==.Manginah:BAAANQAFFAEIAQAAAA==.Manuelito:BAAANQADCgcIBwAAAA==.Mauringo:BAABNQAECoEYAAIaAAgKXA70YADPAQAaAAgKXA70YADPAQAAAA==.Mavanthis:BAABNQAECoEVAAIPAAYKNRmBlQC+AQAPAAYKNRmBlQC+AQAAAA==.Maxdizaster:BAABNQAECoEaAAIjAAcKTRIiDQDAAQAjAAcKTRIiDQDAAQAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAACNQAFFIEKAAMjAAIKPB6PAgChAAAjAAIKPB6PAgChAAAPAAIKNBVRJACcAAA1AAQKgR8AAw8ACQqRIvEtAPICAA8ACQpjIPEtAPICACMAAwoIJH4WABIBAAAA.Mckniferson:BAAANQADCgQIBgAAAA==.',
Me='Meddicineman:BAAANQABCggIEgAAAA==.Merlenoir:BAAANQADCggIFwAAAA==.Messybedhead:BAABNQAECoEoAAQhAAkKThZPFgBtAgAhAAkKThZPFgBtAgAFAAIKjAZMQwBXAAAIAAEKMwcangA4AAABNQADCgYIBgAEAAAAAA==.Methindour:BAAANQAECgMIBgAAAA==.',
Mi='Michãel:BAAANQADCgUIBQAAAA==.Mightydwarf:BAAANQADCggIGAAAAA==.Mintwiskers:BAAANQAECgQIBgAAAA==.Misiana:BAABNQAECoEfAAIbAAgKKRRzOAAFAgAbAAgKKRRzOAAFAgAAAA==.Mivix:BAAANQAECgUICAABNQAFFAcIHQANABIdAA==.',
Mo='Mom:BAAANQAECgUIDQABNQAECgkJJAAlAPUgAA==.Monkeyclaw:BAABNQAECoEkAAIYAAcKEBG/FwCCAQAYAAcKEBG/FwCCAQAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mootribution:BAAANQADCgMIAwAAAA==.Mordrak:BAABNQAECoEeAAIkAAgKmBUuQAD2AQAkAAgKmBUuQAD2AQAAAA==.Mordë:BAABNQAECoENAAMcAAcKjApdMgDxAAAcAAUKqghdMgDxAAAHAAQKHAyK7wC7AAAAAA==.Mormzie:BAAANQAECgMIBgABNQAECgkJLgAYAB4XAA==.Morwy:BAAANQAECggICwAAAA==.Moøbytoo:BAABNQAECoEcAAISAAcKWBvLUgBPAgASAAcKWBvLUgBPAgABNQAECggIHgAaAHohAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAABNQAECoEbAAInAAgKBhqCDACOAgAnAAgKBhqCDACOAgAAAA==.Muinogaraa:BAAANQAECgMIBgABNQAFFAgIGAABABAfAA==.Mum:BAABNQAECoEkAAIlAAkK9SBRCQA3AwAlAAkK9SBRCQA3AwAAAA==.Murked:BAAANQADCggIDQAAAA==.Mushmouth:BAABNQAECoEnAAMDAAkKWSFFKwAuAwADAAkKuyBFKwAuAwAmAAIKfx+tIwCvAAAAAA==.',
My='Myguy:BAAANQADCggIGQAAAA==.Mysiara:BAAANQADCggIEwAAAA==.',
['Mà']='Màjestic:BAAANQAECgIIAwAAAA==.',
['Mì']='Mìchael:BAABNQAECoEaAAMGAAgKiQn5wgBdAQAGAAcKhAn5wgBdAQARAAUKiQQaugDeAAAAAA==.',
['Mú']='Músu:BAAANQAECgYICwAAAA==.',
Na='Nagosho:BAAANQAECgIIAwAAAA==.Namaste:BAAANQAECgEIAQAAAA==.Nampur:BAAANQAECgEIAQAAAA==.Naril:BAABNQAECoEaAAIMAAgK1xieCAA6AgAMAAgK1xieCAA6AgAAAA==.Narvana:BAABNQAECoEtAAMGAAcKEQztuQBwAQAGAAcKEQztuQBwAQAQAAEK6APOcgAbAAAAAA==.Naughtyboy:BAAANQAECgEIAQABNQAECgkJGgADABEgAA==.Navicular:BAAANQAECgQIBgAAAA==.Nayalla:BAAANQAECgYIEAAAAA==.',
Ni='Nightbirdie:BAABNQAECoEUAAIhAAcKdAywLgBvAQAhAAcKdAywLgBvAQAAAA==.Nightshotz:BAAANQAECgUIEAAAAA==.Niobé:BAAANQAECgMIAwAAAA==.Nitezz:BAAANQADCggIDQAAAA==.Nityblast:BAAANQADCgYIDQAAAA==.',
No='Nodrus:BAAANQAECgIIAgAAAA==.Nogaraa:BAABNQAECoEXAAMcAAgKXh+IBADSAgAcAAgKXh+IBADSAgAoAAEKfwfaKAA8AAABNQAFFAgIGAABABAfAA==.Novath:BAACNQAFFIEYAAQRAAgKkR9bAADzAgARAAgKkR9bAADzAgAGAAEKzANPLgA9AAAQAAEKpQvqDgA7AAA1AAQKgSsABBEACQqTJdQBAM4DABEACQqTJdQBAM4DAAYABwohJLpKAI4CABAAAwoBIQM0ABkBAAAA.',
Ny='Nyssarissa:BAABNQAECoEkAAIoAAkKhxrdAgDDAgAoAAkKhxrdAgDDAgAAAA==.',
['Nè']='Nèliel:BAAANQAECgMJBgAAAA==.',
Oa='Oakenstream:BAAANQADCgIJAgAAAA==.',
Oe='Oennogaraa:BAAANQADCggICAABNQAFFAgIGAABABAfAA==.',
Op='Ophélia:BAAANQAECgQIBAAAAA==.',
Or='Orbz:BAAANQADCgcICgABNQAECggIEwAEAAAAAA==.Orusmar:BAAANQADCgYIEgAAAA==.',
Ot='Otterguy:BAAANQAECggIEQAAAA==.',
Ou='Oui:BAAANQAECgQIBgAAAA==.',
Ov='Overheated:BAAANQADCgYIDwAAAA==.',
Pa='Paalaz:BAACNQAFFIETAAIgAAUKFxs9BgC4AQAgAAUKFxs9BgC4AQA1AAQKgSMAAiAACQr9I6IPAA0DACAACQr9I6IPAA0DAAAA.Paarthurnax:BAAANQAECgQICgAAAA==.Pacifister:BAAANQADCgQIBAAAAA==.Paeldryth:BAABNQAECoEpAAMUAAkKbybUAgCfAwAUAAkKbybUAgCfAwATAAgKPRlUGAAIAgAAAA==.Paliesto:BAAANQAECgEIAQAAAA==.Paljin:BAAANQAECgIIBAAAAA==.Palkia:BAABNQAECoEZAAInAAkKhhDgDQB0AgAnAAkKhhDgDQB0AgAAAA==.Palmface:BAABNQAECoEaAAICAAgKlCF3GwDlAgACAAgKlCF3GwDlAgAAAA==.Panatepriest:BAAANQAECgIIAgAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgkJKAABAPUfAA==.Pandatunado:BAABNQAECoElAAISAAgKOR8KLwC+AgASAAgKOR8KLwC+AgAAAA==.Panky:BAAANQAECggIEgAAAA==.',
Pe='Pedrocerrano:BAABNQAECoEhAAICAAkK5hQmQQAxAgACAAkK5hQmQQAxAgAAAA==.Pelt:BAABNQAECoEjAAMSAAgKwBxmQQCCAgASAAgKwBxmQQCCAgAKAAUKxgllRgD0AAAAAA==.Pewbot:BAAANQAECgcIGQABNQAECggIHgAEAAAAAQ==.',
Ph='Phirefly:BAAANQAECgQIDwAAAA==.Phoebë:BAAANQADCgUIBwAAAA==.Phusiion:BAAANQAECgEJAQAAAA==.',
Pi='Pickledin:BAAANQAECgUICQAAAA==.Pinecones:BAABNQAECoEYAAIDAAgKYg/zsgD6AQADAAgKYg/zsgD6AQAAAA==.',
Pk='Pkmntrainer:BAAANQADCgYIFgABNQADCgcIEQAEAAAAAA==.',
Pl='Please:BAACNQAFFIEXAAICAAgK/QfwAgBKAgACAAgK/QfwAgBKAgA1AAQKgScAAgIACQr8IOMcAN0CAAIACQr8IOMcAN0CAAAA.Pleasetwo:BAABNQAECoEjAAICAAkKyRQRPQBCAgACAAkKyRQRPQBCAgABNQAFFAgIFwACAP0HAA==.Plumaril:BAABNQAECoEcAAIDAAcKshDM0QC9AQADAAcKshDM0QC9AQAAAA==.',
Po='Pondero:BAAANQAECgMIBAABNQAECgkJGAARANUQAA==.Pondos:BAAANQADCgIIAgABNQAECgkJGAARANUQAA==.',
Pp='Ppleakin:BAABNQAECoEdAAInAAgKdx6WCgC0AgAnAAgKdx6WCgC0AgAAAA==.',
Pr='Pranzar:BAABNQAECoEbAAIRAAkK2wnDWwDjAQARAAkK2wnDWwDjAQAAAA==.Prepdagoat:BAAANQAECgUICQABNQAECgEIAQAEAAAAAA==.',
Pt='Pticky:BAAANQAECgIIAgABNQAECgkJFQAlACEZAA==.',
Pu='Publichair:BAAANQAECgMIAwABNQAECggIGgACAJQhAA==.Pullo:BAABNQAECoEjAAMkAAkKgxkYPgABAgAkAAgK/xUYPgABAgAZAAgK+xXjLgDzAQAAAA==.Punctualpaul:BAABNQAECoEbAAIDAAkKjiNNGABsAwADAAkKjiNNGABsAwABNQAFFAgIGAARAJEfAA==.Purple:BAAANQAECggIEAAAAA==.',
Py='Pyrostreak:BAAANQAECgUIBwAAAA==.Pyrê:BAAANQAECgUICAAAAA==.',
Qu='Quidditch:BAABNQAECoEeAAIaAAgKeiGIGwAMAwAaAAgKeiGIGwAMAwAAAA==.',
Qw='Qwadsfwfgads:BAACNQAFFIEhAAIhAAcKEiNnAAC2AgAhAAcKEiNnAAC2AgA1AAQKgRoAAiEACQoII8cIACADACEACQoII8cIACADAAAA.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAcIIQAhABIjAA==.',
Ra='Rabbi:BAAANQAECgMIBAABNQAECggIHgAEAAAAAQ==.Raelavent:BAAANQAECgQICQAAAA==.Ragrappy:BAACNQAFFIEYAAINAAgKXSNHAAARAwANAAgKXSNHAAARAwA1AAQKgR4AAg0ACQq0Jt4CALMDAA0ACQq0Jt4CALMDAAAA.Raherius:BAAANQAECgcICwAAAA==.Raiju:BAABNQAECoEXAAIaAAcKUR3OQQBDAgAaAAcKUR3OQQBDAgAAAA==.Rakion:BAAANQAECgcIEwAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAACNQAFFIEGAAMHAAMKLRkDIQC+AAAHAAIKbB8DIQC+AAAcAAEKrgzWGQBPAAA1AAQKgSoAAwcACQroIEQhAOgCAAcACAqZHkQhAOgCABwAAgqjG/5GAKAAAAE1AAUUBAgOAA8AMCAA.Rayden:BAAANQADCgcIBwAAAA==.',
Re='Realm:BAAANQADCggICAAAAA==.Reavêr:BAABNQAECoEYAAIGAAgKxh35TACGAgAGAAgKxh35TACGAgAAAA==.Redreximus:BAAANQAECggIDwAAAA==.Regilock:BAAANQAECgQICwAAAA==.Retlec:BAAANQAECgYIEAAAAA==.Reïki:BAAANQAECgIIAwAAAA==.',
Ri='Rickaz:BAAANQAECgYIBAAAAA==.Rihn:BAAANQADCgEIAQABNQAECgYIEQAEAAAAAA==.Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Rochaca:BAAANQADCgcIGwAAAA==.Rocksham:BAAANQADCgUICQAAAA==.Roshana:BAABNQAECoEcAAISAAgK5xKrXAA1AgASAAgK5xKrXAA1AgAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgYIDwAEAAAAAA==.Rumham:BAAANQAECgYIBwAAAA==.',
Ry='Ryptup:BAAANQAECgQIBAAAAA==.',
['Rà']='Ràndle:BAAANQABCgIIAgAAAA==.',
['Rä']='Rävën:BAAANQADCggIDgAAAA==.',
['Rô']='Rôinujj:BAAANQAECgUIBgAAAA==.',
Sa='Safiyah:BAABNQAECoEcAAMlAAgKMRRrIQAiAgAlAAgKMRRrIQAiAgAgAAEKlQQQigAnAAAAAA==.Saltyevoker:BAAANQADCggIIQAAAA==.Same:BAABNQAECoEnAAMhAAkK7CL4BABlAwAhAAkK7CL4BABlAwAFAAUKkiAfFgDDAQABNQAFFAgIGAARAJEfAA==.Samophlangy:BAAANQADCgMIAwAAAA==.Sandorstus:BAABNQAECoEgAAIGAAkK9xoPRQCgAgAGAAkK9xoPRQCgAgAAAA==.Saothome:BAAANQAECgYICAAAAA==.Sathreal:BAABNQAECoEcAAIHAAkK8hFWSwBTAgAHAAkK8hFWSwBTAgAAAA==.Saywho:BAAANQADCgUJCQAAAA==.',
Sc='Scalywaumpus:BAAANQAECgQIBAAAAA==.Scienta:BAABNQAECoEZAAMBAAkKTR4EDgDiAgABAAkKTR4EDgDiAgALAAMKcRBMIwCVAAABNQAFFAIIAgAEAAAAAA==.Scope:BAAANQAECgQIBwAAAA==.Scrubdk:BAAANQADCgcIBwABNQAECggIDwAEAAAAAA==.Scúbasteve:BAABNQAECoEcAAQcAAcK5SMLJwAzAQAHAAQKVyLGlwB6AQAcAAMK5iMLJwAzAQAoAAIKESEZFgDBAAAAAA==.',
Se='Sefirot:BAAANQAECgMIBgAAAA==.Selinddra:BAAANQAECgMIBgAAAA==.Serrafin:BAAANQAECgcIAQAAAA==.Serrafindk:BAAANQAECggIBAAAAA==.',
Sh='Shadebringer:BAAANQADCggIIgAAAA==.Shadowboxin:BAAANQADCgUIBQABNQABCgQIBAAEAAAAAA==.Shadowscale:BAAANQADCggICAAAAA==.Shamairis:BAAANQADCggICAAAAA==.Shamdaddy:BAAANQAECgUICwAAAA==.Shamezee:BAABNQAECoEkAAInAAgK3hvHCQDFAgAnAAgK3hvHCQDFAgAAAA==.Shampoo:BAAANQAECgYICQAAAA==.Sharlotte:BAAANQAECgIIBAAAAA==.Shilas:BAABNQAECoEbAAIBAAkKohrdGgA7AgABAAkKohrdGgA7AgABNQAECggIGAADAGIPAA==.Shingyee:BAAANQABCgUIBQAAAA==.Shishkabug:BAAANQADCgIIAgAAAA==.Show:BAAANQADCggICAAAAA==.Shownuph:BAAANQADCgcIDgAAAA==.',
Si='Sicilianhero:BAAANQAECgUIBQAAAA==.Sinestroo:BAAANQAECggIDQAAAA==.Singelock:BAAANQAECgQIBAAAAA==.Sinsyn:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.Sinwarrior:BAABNQAECoEmAAIYAAkK1hyVBQD4AgAYAAkK1hyVBQD4AgABNQAFFAEIAQAEAAAAAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAACNQAFFIEYAAMSAAgKth4DAQBwAgASAAcK5B4DAQBwAgAKAAUK4BWOCACWAQA1AAQKgSYAAwoACQrdJrwAAO4DAAoACQraJrwAAO4DABIABwo1Hc1hACgCAAAA.Skorpco:BAABNQAECoEgAAIlAAkKXxtqEADcAgAlAAkKXxtqEADcAgAAAA==.',
Sl='Slickngrity:BAAANQABCgMIAwAAAA==.Sluggo:BAAANQADCggIEAAAAA==.',
Sm='Smulol:BAABNQAECoErAAIHAAkKZBhiLAC7AgAHAAkKZBhiLAC7AgAAAA==.Smutterli:BAAANQADCgQJBAAAAA==.',
Sn='Snoopfrogg:BAABNQAECoEgAAIHAAkK1iKcCQBuAwAHAAkK1iKcCQBuAwAAAA==.Snow:BAAANQAECggIDQAAAA==.',
So='Solfire:BAABNQAECoEVAAMRAAYKWhcwhQBiAQARAAUKfRcwhQBiAQAGAAUKnhXjzgBDAQAAAA==.Solstice:BAAANQAECgMIAwAAAA==.Sometingwong:BAAANQAECgYIBAAAAA==.',
Sp='Spamheal:BAAANQADCgcIDwAAAA==.Sparkle:BAAANQAECgIIBAAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.Spodermenpls:BAAANQADCgIIAgABNQAFFAcIEAACAHoXAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgcIBwAAAA==.Stormweaver:BAABNQAECoEZAAIIAAcKVgLocADcAAAIAAcKVgLocADcAAAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAgIGAABABAfAA==.Sunderwhere:BAACNQAFFIEOAAIPAAQKMCAVEACHAQAPAAQKMCAVEACHAQA1AAQKgRUAAg8ACQoRInoyAOECAA8ACQoRInoyAOECAAAA.Superhomie:BAAANQABCgIIAQAAAA==.',
Sw='Swann:BAABNQAECoEfAAIBAAkKcBxQEADFAgABAAkKcBxQEADFAgAAAA==.Swavor:BAAANQAECgcIDAAAAA==.Sweetbella:BAAANQADCgUIFQAAAA==.Sweetcheëks:BAAANQAECgQIBAAAAA==.Swurves:BAAANQAECgYICAAAAA==.',
Sy='Syela:BAAANQADCggIDQAAAA==.Symbio:BAAANQADCggIDQAAAA==.Syna:BAABNQAECoEZAAIlAAgK1gv9KgDJAQAlAAgK1gv9KgDJAQAAAA==.Syndct:BAAANQADCgIJAgAAAA==.',
Ta='Taearo:BAAANQAECgcIEQAAAA==.Taime:BAABNQAECoEYAAIRAAgKFQrsbgCkAQARAAgKFQrsbgCkAQAAAA==.Taimie:BAAANQABCgUICAAAAA==.Talirn:BAAANQADCggIFAAAAA==.Tallanvor:BAAANQAECgMIAwAAAA==.',
Te='Teax:BAAANQAECggICQAAAA==.Teddywaumpus:BAAANQADCgYJBgAAAA==.Tempestearth:BAAANQAECgIIAgAAAA==.Tendecay:BAABNQAECoEYAAIbAAYKmRkpUwCGAQAbAAYKmRkpUwCGAQAAAA==.Tentotem:BAAANQAECgYICAABNQAECgYIGAAbAJkZAA==.',
Th='Thanquiol:BAACNQAFFIEXAAIMAAgKrRwKAADjAgAMAAgKrRwKAADjAgA1AAQKgSEAAgwACQo/JekAAK8DAAwACQo/JekAAK8DAAAA.Thebaraj:BAABNQAECoEkAAMIAAgKPRWFNQAVAgAIAAgKPRWFNQAVAgAhAAYK8Qf7PQD9AAAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedrude:BAAANQAECgMIAwAAAA==.Thedruidd:BAAANQAECgEIAQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQAECgEIAwAAAA==.Theseglaives:BAAANQAECgEIAQAAAA==.Thrilled:BAAANQAECgUIDwAAAA==.Thyora:BAACNQAFFIEUAAQiAAYKXRYqAgD/AQAiAAYKXRYqAgD/AQAfAAQKVQTgDQDwAAAeAAIKegi+CwB8AAA1AAQKgSMABB8ACQomEUcbAPYBAB8ACQomEUcbAPYBAB4ABAoWD+AnANEAACIAAwoyGqYTAMoAAAAA.',
Ti='Tijdruid:BAAANQAECgIIAgAAAA==.Timouthy:BAAANQADCgEIAQAAAA==.Tinyblast:BAAANQADCgYIEAAAAA==.',
Tj='Tjomme:BAAANQADCggIDAAAAA==.',
To='Tommypickles:BAACNQAFFIEZAAMDAAgKFBypAwBpAgADAAcKGhmpAwBpAgAmAAIKLCJ5BACxAAA1AAQKgSsAAwMACQo+JhEHAL4DAAMACQo+JhEHAL4DACYAAgo+JmMgAMUAAAAA.Tomtrocity:BAAANQADCgUICQAAAA==.Toneclone:BAAANQAECgQIBQAAAA==.Tonestar:BAAANQAECgcIDQAAAA==.Tonyaharding:BAAANQABCgQJBAAAAA==.Toturaka:BAAANQAECgQIDAAAAA==.Touji:BAAANQADCgEIAQAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECggIHgAEAAAAAQ==.Tranquilitee:BAAANQABCggIDQAAAA==.Treerex:BAABNQAECoEcAAIIAAcKxhVxPwDUAQAIAAcKxhVxPwDUAQAAAA==.Troljin:BAABNQAECoEhAAIaAAgKsRS5SgAfAgAaAAgKsRS5SgAfAgAAAA==.Trollpaladin:BAAANQAECgcIDAAAAA==.',
Ts='Tsipayeoc:BAAANQAECgIIBAAAAA==.',
Tw='Twistedhavoc:BAAANQAECgYIDAAAAA==.Twk:BAAANQAECgMIAwAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgcIEwAAAA==.',
Ui='Uiazel:BAAANQADCgEIAQAAAA==.',
Um='Umalinn:BAABNQAECoEcAAIRAAgKDg4DYADUAQARAAgKDg4DYADUAQAAAA==.',
Un='Unholyrep:BAAANQAECgQIBAAAAA==.',
Ur='Urbellum:BAAANQADCgQIBAABNQAFFAcIFgAPAKMUAA==.Urukhaixd:BAAANQAECgMIAgAAAA==.',
Va='Vacca:BAABNQAECoEYAAIKAAgKmQ0JLADHAQAKAAgKmQ0JLADHAQAAAA==.Vaeyethror:BAAANQADCgQIBAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAABNQAECoEeAAIGAAgKQhYZcAAhAgAGAAgKQhYZcAAhAgAAAA==.Vapor:BAACNQAFFIERAAIVAAUKFCBzAAAFAgAVAAUKFCBzAAAFAgA1AAQKgTgAAhUACQrBI/EAAJMDABUACQrBI/EAAJMDAAAA.Varity:BAAANQABCgIIAgAAAA==.Varsity:BAABNQAECoEoAAIPAAkKniOLIAAnAwAPAAkKniOLIAAnAwABNQAECggIGAADAGIPAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Velaryn:BAAANQAECgIJAgAAAA==.Veleanna:BAAANQAECgEIAQAAAA==.Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vh='Vhega:BAAANQABCgIIAgAAAA==.',
Vi='Vinyasa:BAAANQAECggIDQAAAA==.',
Vo='Voodoobeast:BAABNQAECoEbAAIFAAcKJQsrIwA3AQAFAAcKJQsrIwA3AQAAAA==.',
Vu='Vulbahermosa:BAAANQAECgQIDwAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
We='Wenguo:BAAANQAECgQIBQAAAA==.',
Wh='Wheatiees:BAAANQADCgcIGgAAAA==.Whyp:BAACNQAFFIELAAIUAAQKvw2MCABBAQAUAAQKvw2MCABBAQA1AAQKgSYAAxQACQq5HasPAOQCABQACQq5HasPAOQCABMAAgonDb9BAHoAAAAA.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAFFAUICQAhAKoNAA==.',
Wo='Worgenzrdumb:BAAANQADCgcIBwAAAA==.',
Xa='Xavior:BAAANQAECgQIBAAAAA==.',
Xi='Xidara:BAAANQAECgIIBAAAAA==.Xiqualani:BAAANQADCgYIBgAAAA==.Xivei:BAACNQAFFIEdAAINAAcKEh0eAQC1AgANAAcKEh0eAQC1AgA1AAQKgSQAAw0ACQpiIbMnAK0CAA0ACQo2IbMnAK0CAA4ABwosENALAGoBAAAA.',
Xl='Xlegolas:BAAANQAECgIIBAAAAA==.',
Xo='Xorac:BAAANQAECggIDQAAAA==.',
Xz='Xzach:BAABNQAECoEYAAIlAAkKgg03JwDrAQAlAAkKgg03JwDrAQAAAA==.',
Yi='Yinlou:BAAANQAECgUIDAAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAFFAcIEgAiABgLAA==.',
Ys='Yshtolà:BAEANQAECgQIBgAAAA==.',
Yu='Yurmage:BAAANQAECgEIAQAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAACNQAFFIEYAAQcAAgKsiVzAACWAQAcAAQK7SVzAACWAQAoAAMKOyb4AABTAQAHAAMKJB+xFgAMAQA1AAQKgScABBwACQouJp4BAF8DABwACQquIp4BAF8DAAcABwqDIKRJAFgCACgAAwoiJrkNAFMBAAAA.Zaegorn:BAAANQAECggIEgAAAA==.Zamoarak:BAAANQADCgIIAgAAAA==.Zargar:BAACNQAFFIENAAInAAUKfBH5AQClAQAnAAUKfBH5AQClAQA1AAQKgS8AAicACQpCIyYDAGgDACcACQpCIyYDAGgDAAAA.Zarmakai:BAACNQAFFIESAAMkAAcK7yOqAABpAgAkAAcK7yOqAABpAgAbAAEKxAsULwApAAA1AAQKgScAAiQACQqkJjkFAJYDACQACQqkJjkFAJYDAAAA.',
Ze='Zenxo:BAAANQABCgYICQAAAA==.',
Zi='Zintalesh:BAAANQAECgIIAgAAAA==.Zionx:BAAANQADCgQIBAAAAA==.Zivie:BAABNQAECoEjAAMDAAgKSRVqnQAnAgADAAgKSRVqnQAnAgAmAAEKSRCbOwA+AAAAAA==.',
Zo='Zorrick:BAAANQAECgEIAQAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAACNQAFFIEGAAIRAAIKpCLBFQDOAAARAAIKpCLBFQDOAAA1AAQKgRgAAxEACQpTIJAQADgDABEACQpTIJAQADgDAAYAAQpXFcJlAT8AAAAA.',
['Ðr']='Ðrakie:BAABNQAECoEoAAIGAAkKQCMKDQCOAwAGAAkKQCMKDQCOAwAAAA==.',
['Ök']='Ökko:BAABNQAECoEYAAIDAAcK7RFcyQDOAQADAAcK7RFcyQDOAQAAAA==.',
['Öw']='Öwly:BAAANQAECgcICAAAAA==.',
['Øk']='Øktavïa:BAAANQADCgQIAgAAAA==.',
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
