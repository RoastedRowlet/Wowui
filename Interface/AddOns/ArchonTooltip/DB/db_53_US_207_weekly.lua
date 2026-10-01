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

local lookup = {'Monk-Windwalker','Shaman-Restoration','Mage-Arcane','Unknown-Unknown','Druid-Guardian','Warlock-Demonology','Druid-Balance','Priest-Shadow','Hunter-Marksmanship','Monk-Brewmaster','DemonHunter-Vengeance','Priest-Discipline','Paladin-Retribution','Priest-Holy','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Warrior-Protection','DeathKnight-Blood','Warlock-Destruction','Druid-Feral','Evoker-Devastation','Evoker-Preservation','Hunter-Survival','Druid-Restoration','Evoker-Augmentation','Shaman-Elemental','Warrior-Fury','Warrior-Arms','DeathKnight-Unholy','DemonHunter-Devourer','Mage-Frost','Shaman-Enhancement','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Frost',}
local provider = {region='US',realm='Stormreaver',name='US',type='weekly',zone=53,date='2026-09-29',data={Aa='Aaragondelta:BAAANQAECgcIBwABNQAFFAgIFwABABAfAA==.Aaragonius:BAAANQADCggIEAABNQAFFAgIFwABABAfAA==.Aaragonneo:BAACNQAFFIEXAAIBAAgKEB9hAADzAgABAAgKEB9hAADzAgA1AAQKgS4AAgEACQpyJsAAAOEDAAEACQpyJsAAAOEDAAAA.Aaragontheta:BAAANQADCgIIAgABNQAFFAgIFwABABAfAA==.Aaragonxeta:BAAANQADCgEIAQABNQAFFAgIFwABABAfAA==.',
Ab='Ablé:BAABNQAECoEXAAICAAcKCRh+SgDpAQACAAcKCRh+SgDpAQAAAA==.',
Ac='Ackreseth:BAAANQAECgYICQAAAA==.',
Ad='Adriön:BAAANQADCgYIBgAAAA==.',
Ae='Aeko:BAAANQAECgIIBAAAAA==.Aemeath:BAAANQADCgIIAgAAAA==.Aerae:BAAANQADCggIDwAAAA==.Aergoss:BAAANQAECgIJAgAAAA==.Aeristeia:BAABNQAECoEbAAIDAAgKPxvnZgCAAgADAAgKPxvnZgCAAgAAAA==.Aethyria:BAAANQADCgYIBgABNQAECgIJAgAEAAAAAA==.',
Ah='Ahriena:BAAANQADCgEIAQABNQAFFAYIGAAFAN4kAA==.',
Ai='Aiee:BAAANQAECgcIDwAAAA==.Aizén:BAABNQAECoEXAAIGAAgKvhzuLACaAgAGAAgKvhzuLACaAgAAAA==.',
Al='Allaboutme:BAAANQADCgUJBgAAAA==.',
Am='Amad:BAAANQAECgUIBQAAAA==.Amorha:BAAANQADCgQIBAAAAA==.Amourn:BAAANQAECgIIAgAAAA==.',
An='Analrek:BAAANQAECgcIEQAAAA==.Antekhrestos:BAAANQADCgQIBAAAAA==.Antoinedruid:BAABNQAECoEoAAIHAAkKJh9EEwAIAwAHAAkKJh9EEwAIAwABNQAFFAcIEQAIAGoVAA==.',
Ap='Apocalypsis:BAAANQAECgUICQABNQAECgkJIQAJAN4OAA==.Apodal:BAABNQAECoEYAAIKAAkKXAtsEACeAQAKAAkKXAtsEACeAQABNQAFFAgIFwALAK0cAA==.Apoluss:BAAANQADCgYICwAAAA==.',
Ar='Arih:BAAANQADCgUIDAAAAA==.Arock:BAABNQAECoEYAAICAAkKQxtfHQDDAgACAAkKQxtfHQDDAgAAAA==.Arrithion:BAAANQAECgYIEAAAAA==.Arthaz:BAACNQAFFIERAAIIAAcKahVqAQBWAgAIAAcKahVqAQBWAgA1AAQKgSYAAwgACQr+JBkDAJkDAAgACQr+JBkDAJkDAAwAAgrqDVsZAGcAAAAA.',
As='Asgorath:BAAANQAECgEIAQAAAA==.Astandra:BAAANQAECgIIAgAAAA==.Astro:BAAANQADCgIIAgABNQAECggIHAADAPAeAA==.',
At='Atexnogaraa:BAABNQAECoEYAAINAAkK6xo7QACKAgANAAkK6xo7QACKAgABNQAFFAgIFwABABAfAA==.',
Av='Averelles:BAABNQAECoEdAAIOAAcKwAhZdgBJAQAOAAcKwAhZdgBJAQAAAA==.',
Aw='Awwik:BAAANQAECgcIEwAAAA==.',
Az='Azsharaa:BAAANQAECgcIBwAAAA==.',
Ba='Babyjojo:BAAANQAECgYICwAAAA==.Badaboomkin:BAAANQAECgcIDAABNQAFFAEIAQAEAAAAAA==.Baeldun:BAAANQAECgcIEwAAAA==.Baethoven:BAAANQAECgUIDgAAAA==.Bagagwa:BAAANQAECgUIBgAAAA==.Ballzac:BAAANQADCggICAAAAA==.Ballzout:BAAANQAECgcIDQABNQAFFAEIAQAEAAAAAA==.Bamix:BAAANQADCgYIBgAAAA==.Bashm:BAAANQAECgYIEQABNQAECgkJIAAGAHYiAA==.',
Be='Beaconbilly:BAABNQAECoEZAAMPAAgKlR6zCwCdAgAPAAgKlR6zCwCdAgAQAAgKERZ7NABXAgAAAA==.Bearmanpig:BAAANQAECgUIBgAAAA==.Beelzemoan:BAAANQAECgQIDQAAAA==.Beens:BAACNQAFFIERAAMJAAcKhyL/AgAdAgAJAAYKLSH/AgAdAgARAAIKnSJ2EQDHAAA1AAQKgSoAAgkACQpJJvIBALsDAAkACQpJJvIBALsDAAAA.Beewitched:BAAANQAECgEIBAAAAA==.Beloved:BAAANQAECgEIAQAAAA==.Belowzerolol:BAABNQAECoEYAAIQAAkKJw3DPwAlAgAQAAkKJw3DPwAlAgABNQAFFAgIGAAOAF0jAA==.Benkaz:BAAANQAECgYICwABNQAFFAEIAQAEAAAAAA==.Bennszülött:BAAANQAECgUIBQAAAA==.',
Bi='Bierhops:BAAANQADCgcIBwAAAA==.Bigchimpin:BAAANQADCgcIBwAAAA==.',
Bl='Blacktacular:BAAANQADCgQIBAAAAA==.Bloodlust:BAABNQAECoEaAAIHAAkKIBNwKQBMAgAHAAkKIBNwKQBMAgABNQAECgkJLAAQAEIZAA==.Bluedaemon:BAAANQAECgUICQAAAA==.Bluenchi:BAAANQADCggICwABNQAFFAMIBQADAHcbAA==.Blunttruama:BAAANQAECgUICgAAAA==.',
Bo='Boomboompow:BAAANQADCggIEgAAAA==.',
Br='Breadbowl:BAAANQAECggIEwAAAA==.Brontide:BAAANQAECgcICQABNQAECgYIDwAEAAAAAA==.Brrzerk:BAAANQADCggICwAAAA==.Brrzrrq:BAAANQADCgEIAQAAAA==.',
Bu='Bubblesburst:BAAANQADCgYIDQABNQAECgEIBAAEAAAAAA==.Bubblëdin:BAAANQADCgYICgABNQAECgIIAgAEAAAAAA==.Buckee:BAABNQAECoEZAAMSAAgK+xRkGAD1AQASAAcK1hRkGAD1AQATAAIKcRDzYwCAAAAAAA==.Buckets:BAAANQADCgcIGwAAAA==.Bucknutt:BAAANQAECgYIEgAAAA==.Buffoutlaw:BAABNQAECoEYAAIUAAkK6iBgAgAUAwAUAAkK6iBgAgAUAwABNQAFFAgIGAAUAPMmAA==.Bullzzeye:BAAANQAFFAMIAwAAAA==.Butternipz:BAAANQADCgcIBwAAAA==.',
By='Byshop:BAAANQAECgcIBwAAAA==.',
Ca='Cabe:BAAANQAECgcIEwAAAA==.Caerra:BAAANQADCgIIAgAAAA==.Caggarm:BAAANQAECgIIAgAAAA==.Cailber:BAAANQADCgUIBwABNQAECgIIAgAEAAAAAA==.Callipriest:BAAANQAECgQICgAAAA==.Callmetim:BAAANQAECggIBgAAAA==.Castermaster:BAAANQAECgYIEQAAAA==.',
Ce='Celthrinor:BAAANQAECgcJDAAAAA==.Cerevistra:BAAANQADCgEIAQAAAA==.',
Ch='Chaeni:BAAANQADCgQIAwAAAA==.Chakkah:BAAANQADCgQIBAAAAA==.Chillyy:BAABNQAECoEgAAMVAAkKHBjDCgCkAgAVAAkKHBjDCgCkAgABAAEK9AQjXAAhAAAAAA==.Chipss:BAAANQAECgQIBwAAAA==.Chispot:BAAANQAECgEJAgAAAA==.Chitorpedo:BAAANQAECgQIBgAAAA==.Chodester:BAAANQADCgUIBQAAAA==.Chokyo:BAAANQAECgUICwAAAA==.Chronis:BAAANQABCgYICgAAAA==.',
Ci='Cidel:BAAANQAECgQIBgAAAA==.Cifer:BAAANQADCgYIBgAAAA==.',
Co='Comatoast:BAAANQAECgYIDwAAAA==.Comeback:BAAANQADCggIDgAAAA==.Course:BAAANQADCgIIAgAAAA==.',
Cr='Crackalaks:BAAANQAECgUICwAAAA==.Crazyb:BAABNQAECoEYAAISAAcK1w2HHgC1AQASAAcK1w2HHgC1AQAAAA==.Croith:BAABNQAECoEeAAIWAAgKDxa2DQD8AQAWAAgKDxa2DQD8AQAAAA==.Crotch:BAAANQABCgEIAgAAAA==.Crushbucket:BAAANQADCgQIBAAAAA==.Cryingorc:BAAANQAECgEIAQAAAA==.Crúz:BAAANQAECgIJBAAAAA==.',
Cw='Cwap:BAAANQAECgIIAgAAAA==.',
Cy='Cyndraylitha:BAAANQADCgYJBgAAAA==.',
Da='Daddywaumpus:BAAANQAECgMIAwAAAA==.Dageris:BAAANQAECgcIEAAAAA==.Damonic:BAAANQADCggIDgABNQAFFAEIAQAEAAAAAA==.Danas:BAAANQADCggIDgAAAA==.Dargothous:BAAANQAECgIIAgAAAA==.Darksector:BAAANQADCgQIBAAAAA==.Darkwraith:BAAANQABCgUIBgABNQAECgEIAQAEAAAAAA==.Davicurn:BAAANQADCggIEAAAAA==.Daythyme:BAEANQAECgIIAgAAAA==.',
De='Deadornot:BAAANQAECgcIEwAAAA==.Deadywaumpus:BAABNQAECoEhAAIXAAkKBBnBHQCOAgAXAAkKBBnBHQCOAgAAAA==.Deathbubbles:BAAANQADCgYIBwAAAA==.Deathkong:BAAANQAECgcIDwAAAA==.Deathofdager:BAAANQADCggICAAAAA==.Deetwenty:BAAANQAECgUICwAAAA==.Deeztotemz:BAAANQAECgIIAwAAAA==.Demairis:BAAANQADCgcIBwAAAA==.Demonstyle:BAAANQAECgIIAgABNQAECgUJDgAEAAAAAA==.Desiiria:BAAANQAECgEIAQAAAA==.Deylicious:BAAANQAECggIEQABNQAFFAgIGAARALYeAA==.',
Dh='Dhani:BAAANQAECgUIEQAAAA==.',
Di='Dietdrpibb:BAAANQADCgcIEQAAAA==.Diiemoar:BAAANQAECggIEAAAAA==.Dijoe:BAAANQAECgQIDQAAAA==.Dimmencius:BAAANQAECgQICAAAAA==.Dippndotz:BAABNQAECoEdAAMYAAkKmRnkGACYAQAGAAcKUxlhWQD9AQAYAAcKqxLkGACYAQAAAA==.Discfunction:BAAANQADCgcIGgAAAA==.Disciple:BAAANQADCgYIBgAAAA==.',
Do='Doafliploser:BAAANQADCgYIBgAAAA==.Dogwalterll:BAABNQAECoEfAAIZAAgKPBpNBwCJAgAZAAgKPBpNBwCJAgAAAA==.Dohvahkiin:BAAANQAECgMIAwAAAA==.Dontlosmë:BAAANQAECgIIAgAAAA==.',
Dr='Draaragon:BAAANQADCggICwABNQAFFAgIFwABABAfAA==.Dracgutx:BAAANQADCgcIEAAAAA==.Dragonboffa:BAAANQADCgYIEgAAAA==.Dragonlyfans:BAABNQAECoEoAAMaAAkKNRpnCgCbAgAaAAkKNRpnCgCbAgAbAAgKIw8CGgDlAQABNQAFFAgIFgAHANMgAA==.Dripz:BAAANQAECggIEwAAAA==.Drive:BAAANQAECgcIEAAAAA==.Drumatic:BAAANQAECggICQAAAA==.Drunken:BAAANQADCgcIDQAAAA==.Dryadwood:BAAANQADCgcIDQAAAA==.',
Du='Dubby:BAABNQAECoEbAAIHAAkKOB0aGgDIAgAHAAkKOB0aGgDIAgAAAA==.Duelley:BAAANQABCgYICQAAAA==.Dumptruckdan:BAABNQAECoEdAAINAAkK2BXuXAAsAgANAAkK2BXuXAAsAgABNQAFFAgIGAADABQcAA==.Durgur:BAAANQAECgUIBQABNQAECgcJEAAEAAAAAA==.',
Ea='Eardi:BAAANQAECggIDQAAAA==.Earthpounder:BAAANQAECgUIEQAAAA==.',
Ec='Echoez:BAABNQAECoEhAAIVAAkK6wzHFADaAQAVAAkK6wzHFADaAQAAAA==.Eclipsa:BAAANQAECgUIDgAAAA==.',
Ee='Eebo:BAAANQADCgMIAwAAAA==.',
El='Elbram:BAAANQADCggICAABNQAECgYIEgAEAAAAAA==.Elledramoc:BAAANQABCgEIAQAAAA==.Elunasolz:BAEANQADCggIIQABNQAECgQJBgAEAAAAAA==.',
Em='Emilil:BAAANQADCggIDAAAAA==.Eminence:BAAANQADCggIFgAAAA==.',
En='Enlight:BAAANQABCgMIAwAAAA==.',
Er='Erdorco:BAAANQADCggICwABNQAECggIGgANACEaAA==.',
Es='Escanor:BAAANQAECgIIAgAAAA==.Esu:BAAANQAECgIIAgAAAA==.',
Eu='Eudaimonia:BAAANQADCgYIDwAAAA==.',
Ex='Exias:BAAANQADCggIGQAAAA==.',
Ey='Eyejuice:BAAANQAECgIIAgAAAA==.',
Fa='Facebeata:BAABNQAECoEhAAQJAAkK3g5gKAC7AQAJAAgKQgxgKAC7AQARAAQKSxA8wAAVAQAcAAEKkgeBEAAuAAAAAA==.Fahlstad:BAAANQAECgQIBAAAAA==.Faize:BAAANQADCggIDgABNQAFFAUIDAAdALQHAA==.Falae:BAAANQAECgMJBgABNQAFFAUICAAQABkQAA==.Fathêrhêlp:BAAANQADCgEIAQAAAA==.Faunuis:BAACNQAFFIEWAAMHAAgK0yC7BAD7AQAHAAUKgiW7BAD7AQAdAAMKqht3BgAlAQA1AAQKgSUAAwcACQrCJggBAOgDAAcACQrCJggBAOgDAB0ABgqKHXEjAKgBAAAA.Fawnbby:BAAANQAECgUIBQAAAA==.Faüst:BAAANQADCgQIBAABNQAECgkJIwAOAD8iAA==.',
Fe='Fearthebeef:BAAANQABCgEIAQABNQAECgcIEwAEAAAAAA==.Featherbrain:BAAANQAECgUIDgAAAA==.Felhell:BAAANQAECgQICAABNQAECgkJIAAVABwYAA==.Ferenyet:BAAANQADCgYIBgAAAA==.Fermagus:BAABNQAECoEeAAIDAAcKNgZG6gBiAQADAAcKNgZG6gBiAQAAAA==.',
Fi='Fistflurry:BAAANQAECgUIBgABNQAFFAEIAQAEAAAAAA==.Fistlad:BAACNQAFFIEXAAMaAAgKvSUSAAASAwAaAAcKsSYSAAASAwAeAAEKEx+6BgBlAAA1AAQKgSEAAhoACQoHJxYAAAkEABoACQoHJxYAAAkEAAAA.Fizzybubbles:BAABNQAECoEcAAICAAgKNR6KJACaAgACAAgKNR6KJACaAgAAAA==.',
Fl='Flamehunter:BAAANQAECggIEgAAAA==.Flapple:BAACNQAFFIEHAAIaAAQKthDjBAA7AQAaAAQKthDjBAA7AQA1AAQKgSoAAhoACQreI0cCAH4DABoACQreI0cCAH4DAAAA.Fleshgrind:BAAANQADCgQIBAAAAA==.Flexicution:BAAANQADCgYIBgABNQAECgQIBAAEAAAAAA==.Floweret:BAAANQAECgIIAgABNQAECgcIEQAEAAAAAA==.Flu:BAAANQADCgEIAQABNQAECgIIAgAEAAAAAA==.Flûffy:BAAANQAECgUIDAAAAA==.',
Fr='Freaknikk:BAAANQAECgcIEwABNQAECgYIDgAEAAAAAA==.Freakuency:BAAANQABCgYICgAAAA==.Freightraìn:BAAANQADCgIIAgABNQAECggIHAAEAAAAAQ==.Frozalth:BAAANQADCgUJBgAAAA==.',
Fu='Fudgemuffin:BAAANQAFFAIIAwAAAA==.Furyofgnomes:BAAANQADCgEIAQABNQAECgEIAQAEAAAAAA==.',
Fx='Fxaweqzdpal:BAAANQAECgEIAQABNQAFFAcIIAAdABIjAA==.',
['Fë']='Fënrïr:BAAANQAECgMIBgABNQAECgkJKgAfACwhAA==.',
['Fú']='Fúzzybútt:BAAANQADCgMIAwAAAA==.',
Ga='Galice:BAAANQAECgQJBAAAAA==.Gardasil:BAAANQAECggIAgAAAA==.Garlim:BAAANQADCgUIBQAAAA==.Gazebogary:BAABNQAECoEdAAIaAAkKjSHtAgBnAwAaAAkKjSHtAgBnAwABNQAFFAgIGAADABQcAA==.',
Ge='Gellysong:BAAANQABCgQJBgAAAA==.Genos:BAAANQAECgcICAAAAA==.Gerlim:BAAANQADCgEIAQAAAA==.',
Gi='Gix:BAAANQAECgEIAQAAAA==.',
Gl='Glolock:BAAANQAECgcIEwAAAA==.Glopanx:BAAANQAECgEIAQABNQAECgcIEwAEAAAAAA==.',
Go='Goresnot:BAAANQADCggIKgAAAA==.Gorgygrinds:BAAANQABCgUIBgAAAA==.',
Gr='Gravedarknes:BAACNQAFFIEIAAMgAAQKvBOwAQCsAAAgAAIKthawAQCsAAAhAAIKwxAzHwCVAAA1AAQKgRcAAyAACAoGIRoPAGYBACEABgr8HfxyAO0BACAABAqbIhoPAGYBAAAA.Greendog:BAAANQADCgIIAgABNQAECgYIIwANAPsJAA==.Grievur:BAAANQAECgMIBAABNQAECggIFwAhAO8TAA==.',
Gu='Guap:BAABNQAECoEYAAIDAAkKzBm5fQBJAgADAAkKzBm5fQBJAgABNQAFFAgIFwAaAL0lAA==.Guineasaurus:BAAANQADCgUIBgAAAA==.Gunray:BAAANQADCgUIBQAAAA==.Guttamane:BAAANQAECgQIBwAAAA==.Gutx:BAAANQAECgMIBQAAAA==.',
Gy='Gyarrados:BAAANQADCgYIEAAAAA==.Gypsywolfe:BAAANQAECgQIBgAAAA==.',
['Gí']='Gífted:BAABNQAECoEkAAIDAAkKAheVYwCIAgADAAkKAheVYwCIAgAAAA==.',
['Gü']='Günz:BAAANQABCgEIAQAAAA==.',
Ha='Hakasan:BAAANQAECgEIAQABNQAFFAEIAQAEAAAAAA==.Haleybeary:BAAANQAECgMIBAAAAA==.Harawing:BAAANQADCgUIBQAAAA==.Hargrim:BAAANQADCggIDwAAAA==.Hastega:BAABNQAECoEZAAIGAAUKdA8eqwAXAQAGAAUKdA8eqwAXAQAAAA==.Haydonk:BAAANQADCgcIBwAAAA==.',
He='Herbage:BAAANQAECgUIEQAAAA==.Herrbjorn:BAAANQAECgMIBQAAAA==.',
Hi='Hinata:BAAANQADCgQIBAAAAA==.Hippopotamus:BAAANQAECgUICgAAAA==.Hitaman:BAAANQAECgUICgAAAA==.',
Hl='Hlzmybuttoff:BAAANQAECgUIBQABNQAECgkJIAAaAO8bAA==.',
Ho='Holik:BAAANQABCgEIAQAAAA==.Holybaguette:BAAANQAECgUICwAAAA==.Holycritbro:BAAANQAECgIIAwAAAA==.Horôn:BAAANQAECgcIBgAAAA==.Hotgirlmegan:BAAANQAECggIBAAAAA==.Houndoomm:BAAANQADCggIHQAAAA==.',
Hr='Hriste:BAAANQAECgUIDQAAAA==.',
Hu='Hugepenances:BAAANQAECgQIBAAAAA==.Humptime:BAAANQADCgQIBAAAAA==.Hunteress:BAAANQADCgQIBAAAAA==.Huntyhunt:BAAANQAECgIIAgAAAA==.',
['Hô']='Hôrôn:BAAANQADCgYICgAAAA==.',
Im='Imnosickmall:BAAANQAECgcIDAAAAA==.',
In='Incognetus:BAAANQAECggIHAAAAQ==.Insurrection:BAAANQAECgUIDgABNQAECggIIQABAKoZAA==.',
Ir='Ironmaiiden:BAAANQAECgEIAQAAAA==.Ironpally:BAABNQAECoEXAAMNAAcKZhZUjwCcAQANAAYKNhRUjwCcAQAQAAMKkAXByACUAAAAAA==.',
Iw='Iwantmead:BAAANQABCgMIAwAAAA==.',
Ja='Jaduen:BAAANQADCggIHQAAAA==.Jadziä:BAAANQADCgYICgAAAA==.Jaes:BAAANQAECgQJBQABNQAFFAUICAAQABkQAA==.Jaesedar:BAABNQAFFIEIAAIQAAUKGRA3CACOAQAQAAUKGRA3CACOAQAAAA==.Jankizzle:BAAANQADCggIEAAAAA==.Jaycen:BAAANQAECgQJCwABNQAECggIHAAEAAAAAQ==.',
Je='Jellythug:BAAANQAECgYIEQAAAA==.Jenny:BAAANQAECggIDAAAAA==.Jerboa:BAAANQADCgQIBAAAAA==.Jerksnknight:BAABNQAECoEZAAIiAAgKuwqFSQCKAQAiAAgKuwqFSQCKAQAAAA==.Jethon:BAAANQADCgcIDwAAAA==.Jexro:BAABNQAECoEtAAIjAAkKpyTZAgCgAwAjAAkKpyTZAgCgAwAAAA==.Jezebaal:BAAANQAECgIIAgAAAA==.',
Jg='Jgremlin:BAAANQADCgUICAAAAA==.',
Ji='Jiun:BAAANQAECgMJAwAAAA==.',
Jo='Johnseenah:BAAANQADCgYIDAAAAA==.Jonnybravo:BAEANQAECgQICQAAAA==.Joshton:BAAANQADCgUIBgAAAA==.',
Jr='Jrrd:BAAANQAECgYICQAAAA==.',
Ju='Judgmentoe:BAAANQAECgMIBAAAAA==.Jusstice:BAAANQAECgUIEAAAAA==.',
Ka='Kack:BAAANQAECgYICgAAAA==.Kadzageth:BAAANQAECgUICgAAAA==.Kalvosa:BAAANQADCgYIFAAAAA==.Kanglizard:BAAANQAECgEIAQAAAA==.Karlbarx:BAAANQAECgcIDAAAAA==.Kasaa:BAABNQAECoEYAAMTAAYKuBDGNQCDAQATAAYKuBDGNQCDAQASAAMKrgIXPQCAAAAAAA==.Kasheira:BAAANQAECgUIDAAAAA==.Katti:BAAANQAECgYIDQAAAA==.Katzfiel:BAAANQAECgcIEwAAAA==.Kaytwo:BAACNQAFFIEXAAIhAAcKQCXHAADvAgAhAAcKQCXHAADvAgA1AAQKgRwAAiEACQplJuMNAHgDACEACQplJuMNAHgDAAAA.',
Kb='Kblasti:BAAANQAECgQICAABNQAECgkJIwAHAJQjAA==.Kblastissimo:BAABNQAECoEjAAIHAAkKlCNNBACrAwAHAAkKlCNNBACrAwAAAA==.',
Kc='Kcommandr:BAAANQAECgQIBAABNQAECggIGgAfAHIfAA==.',
Ke='Kendramp:BAAANQAECgUICgAAAA==.Kersplode:BAAANQAECgMIBQABNQAECggIHgARAJQbAA==.',
Kh='Khariia:BAAANQADCgQIBAAAAA==.',
Ki='Kieloran:BAABNQAECoEkAAMPAAcKogshKgAzAQAPAAcKogshKgAzAQANAAEKCgHyfAEKAAAAAA==.Kieralyn:BAAANQAECgEIAgAAAA==.Kiltlifter:BAAANQAECgMIBAAAAA==.Kisol:BAAANQADCgYIBgAAAA==.',
Ko='Koaladashian:BAAANQAECggIDwAAAA==.Koalaficent:BAAANQAECggIDgAAAA==.Kojodruid:BAAANQADCgYICgAAAA==.Kojohunter:BAAANQAECgEIAQAAAA==.Kong:BAAANQAECgUIBgAAAA==.Kookta:BAABNQAECoEYAAINAAkKtxpaQACKAgANAAkKtxpaQACKAgAAAA==.Kozmo:BAAANQAECgUJCgAAAA==.',
Kr='Kreep:BAAANQAECgUICAAAAA==.Kreepur:BAAANQAECgEIAQAAAA==.Kresnik:BAAANQADCgUIBQAAAA==.',
Ku='Kundin:BAAANQAECgcIEAABNQAFFAMICQABAO4UAA==.Kurai:BAABNQAECoEfAAIKAAgKhQ68EACYAQAKAAgKhQ68EACYAQAAAA==.Kutaki:BAAANQAECgMIAwABNQABCgEIAQAEAAAAAA==.',
['Kí']='Kíngbradley:BAAANQADCgQIBAABNQAECggIHgARAJQbAA==.',
['Kô']='Kôvu:BAAANQAECgYICwAAAA==.',
La='Lasrin:BAACNQAFFIEKAAINAAQKRxdxCABdAQANAAQKRxdxCABdAQA1AAQKgSIAAg0ACQrWHyohAA8DAA0ACQrWHyohAA8DAAAA.Lavenia:BAAANQADCggIDAAAAA==.',
Lc='Lcboss:BAAANQAECgQIBAAAAA==.',
Ld='Ldawg:BAABNQAECoEgAAMDAAgKIAk6zwCWAQADAAgK+gg6zwCWAQAkAAEKzALmPQAtAAAAAA==.',
Le='Leastzenmonk:BAAANQAECgYIDgABNQAFFAcIEAACAHoXAA==.Lelu:BAAANQADCgUIBQAAAA==.Leucetios:BAAANQAECgQICQAAAA==.',
Li='Liello:BAAANQAECgIJAgAAAA==.Liethem:BAAANQADCgYIBgAAAA==.Lightchaos:BAAANQAECgYIBgABNQAFFAYIEgACAPweAA==.Lightice:BAAANQADCgMIAwAAAA==.Lilgaypunk:BAACNQAFFIELAAMIAAUKgh20BQB+AQAIAAQKsiC0BQB+AQAOAAIKtAYmHwCSAAA1AAQKgSUAAggACQqYHwENAO0CAAgACQqYHwENAO0CAAAA.Lilgaypunkk:BAAANQAECgcIDAABNQAFFAUICwAIAIIdAA==.Littlecyka:BAAANQADCggICAAAAA==.',
Lo='Lockfocks:BAAANQADCggICAABNQAECgEIAQAEAAAAAA==.Locoscar:BAACNQAFFIEMAAIRAAUK7RnjBACvAQARAAUK7RnjBACvAQA1AAQKgSkAAxEACQq9JdYEAKYDABEACQq9JdYEAKYDAAkABArcFDFHAL4AAAAA.Logix:BAAANQADCgYIBAAAAA==.Loktark:BAACNQAFFIEYAAIUAAgK8yYBAAA4AwAUAAgK8yYBAAA4AwA1AAQKgSQAAhQACQrFJiIAAO8DABQACQrFJiIAAO8DAAAA.Lootini:BAAANQAECggIEAAAAA==.Lotei:BAAANQAECgYIDwAAAA==.',
Lu='Luckylock:BAAANQADCgYIBgABNQAECgcICwAEAAAAAA==.Lucresh:BAAANQADCgYIBgAAAA==.Luhari:BAAANQAECgQIBAAAAA==.Lula:BAAANQADCgIIAgAAAA==.Lunasolz:BAEANQAECgMIAwABNQAECgQJBgAEAAAAAA==.Lustíé:BAAANQAECgQICQAAAA==.',
Ly='Lythinlock:BAAANQAECgQIBwAAAA==.Lythinmk:BAAANQAECgYICQAAAA==.',
['Là']='Lànthus:BAAANQAECggICgAAAA==.',
['Lê']='Lêêrøy:BAAANQADCgYIFAAAAA==.',
Ma='Magedood:BAAANQAECgUIDAAAAA==.Magev:BAAANQAECgUIEQAAAA==.Maggerz:BAAANQADCgMJAwAAAA==.Magiccheif:BAAANQAECgUIEQAAAA==.Magnuz:BAAANQADCgQIBwAAAA==.Mailei:BAAANQADCggICAAAAA==.Maisharona:BAAANQADCgYIDAABNQAECggIHAADAMQiAA==.Makanir:BAAANQAECgcIBwAAAA==.Maleficent:BAAANQAECgIIAgAAAA==.Manginah:BAAANQAFFAEIAQAAAA==.Manuelito:BAAANQADCgcIBwAAAA==.Mauringo:BAAANQAECgcIEQAAAA==.Mavanthis:BAAANQAECgUIEAAAAA==.Maxdizaster:BAAANQAECgUIEAAAAA==.Mazkaz:BAAANQADCgUIBQAAAA==.',
Mc='Mcbonk:BAACNQAFFIEKAAMgAAIKPB7jAQChAAAgAAIKPB7jAQChAAAhAAIKNBVoHQCeAAA1AAQKgR8AAyEACQqRIl4kAAEDACEACQpjIF4kAAEDACAAAwoIJDkTABgBAAAA.Mckniferson:BAAANQADCgQIBgAAAA==.',
Me='Meddicineman:BAAANQABCggIEgAAAA==.Merlenoir:BAAANQADCggIEgAAAA==.Messybedhead:BAABNQAECoEkAAQdAAkKThZBEgB7AgAdAAkKThZBEgB7AgAFAAIKjAavNgBXAAAHAAEKMwesjgA7AAABNQADCgYIBgAEAAAAAA==.Methindour:BAAANQAECgMIBAAAAA==.',
Mi='Mightydwarf:BAAANQADCggIGAAAAA==.Mintwiskers:BAAANQAECgQIBgAAAA==.Misiana:BAABNQAECoEZAAIXAAgK5BDQPQDIAQAXAAgK5BDQPQDIAQAAAA==.Mivix:BAAANQAECgUICAABNQAFFAYIHAAOAAYfAA==.',
Mo='Mom:BAAANQAECgQICAABNQAECgkJIQAjAPUgAA==.Monkeyclaw:BAABNQAECoEdAAIWAAcKEBHyEwCKAQAWAAcKEBHyEwCKAQAAAA==.Moonfist:BAAANQADCgQIBAAAAA==.Mordrak:BAAANQAECgYIEwAAAA==.Mordë:BAABNQAECoENAAMYAAcKjAppLwD3AAAYAAUKqghpLwD3AAAGAAQKHAwa0gDAAAAAAA==.Mormzie:BAAANQAECgMIBAABNQAECgkJJAAWAJsWAA==.Morwy:BAAANQAECggICwAAAA==.Moøbytoo:BAABNQAECoEYAAIRAAcK9xrkRwBJAgARAAcK9xrkRwBJAgABNQAECggIGgAfAHIfAA==.',
Ms='Msedd:BAAANQADCgMIAwAAAA==.',
Mu='Mugged:BAABNQAECoEVAAIlAAgKehUeDgBKAgAlAAgKehUeDgBKAgAAAA==.Muinogaraa:BAAANQAECgMIBgABNQAFFAgIFwABABAfAA==.Mum:BAABNQAECoEhAAIjAAkK9SAdBwBNAwAjAAkK9SAdBwBNAwAAAA==.Murked:BAAANQADCggJDQAAAA==.Mushmouth:BAABNQAECoEfAAMDAAgKVCLXPADtAgADAAgKoiHXPADtAgAkAAEK/B8LLABcAAAAAA==.',
My='Myguy:BAAANQADCgYIFAAAAA==.Mysiara:BAAANQADCggIEwAAAA==.',
['Mà']='Màjestic:BAAANQAECgEIAQAAAA==.',
['Mì']='Mìchael:BAAANQAECgYIEgAAAA==.',
['Mú']='Músu:BAAANQAECgYICwAAAA==.',
Na='Nagosho:BAAANQAECgEIAQAAAA==.Namaste:BAAANQAECgEIAQAAAA==.Nampur:BAAANQAECgEIAQAAAA==.Naril:BAAANQAECgcIEQAAAA==.Narvana:BAABNQAECoEjAAMNAAYK+wlSzgAKAQANAAUKMgtSzgAKAQAPAAEK6AMrZQAdAAAAAA==.Naughtyboy:BAAANQAECgEIAQABNQAECgkJFQADAPAfAA==.Navicular:BAAANQAECgIIAgAAAA==.Nayalla:BAAANQAECgUICgAAAA==.',
Ni='Nightbirdie:BAAANQAECgcIDwAAAA==.Nightshotz:BAAANQAECgUICwAAAA==.Niobé:BAAANQADCgYICgAAAA==.Nitezz:BAAANQADCgUIBQAAAA==.Nityblast:BAAANQADCgYIDQAAAA==.',
No='Nodrus:BAAANQAECgIIAgAAAA==.Nogaraa:BAABNQAECoEXAAMYAAgKXh/4AwDgAgAYAAgKXh/4AwDgAgAmAAEKfwfQJAA8AAABNQAFFAgIFwABABAfAA==.Novath:BAACNQAFFIEYAAQQAAgKkR8nAAAFAwAQAAgKkR8nAAAFAwANAAEKzANZIgBGAAAPAAEKpQtsDAA7AAA1AAQKgSgABBAACQqTJVwBANQDABAACQqTJVwBANQDAA0ABwohJJw4AKgCAA8AAgrYHiw9ALEAAAAA.',
Ny='Nyssarissa:BAABNQAECoEhAAImAAkKnhmRAgC7AgAmAAkKnhmRAgC7AgAAAA==.',
['Nè']='Nèliel:BAAANQAECgMJBgAAAA==.',
Oa='Oakenstream:BAAANQADCgIJAgAAAA==.',
Oe='Oennogaraa:BAAANQADCggICAABNQAFFAgIFwABABAfAA==.',
Op='Ophélia:BAAANQAECgQIBAAAAA==.',
Or='Orbz:BAAANQADCgcICgABNQAECgcIEQAEAAAAAA==.Orusmar:BAAANQADCgYIEgAAAA==.',
Ot='Otterguy:BAAANQAECgcIEAAAAA==.',
Ou='Oui:BAAANQAECgQIBgAAAA==.',
Ov='Overheated:BAAANQADCgYIDwAAAA==.',
Pa='Paalaz:BAACNQAFFIEPAAInAAUKYhpqBADEAQAnAAUKYhpqBADEAQA1AAQKgSAAAicACQr9I/wMABMDACcACQr9I/wMABMDAAAA.Paarthurnax:BAAANQAECgQIBAAAAA==.Pacifister:BAAANQADCgQJBAAAAA==.Paeldryth:BAABNQAECoElAAMTAAkKWSazAgCUAwATAAkKWSazAgCUAwASAAgKPRmJFQAUAgAAAA==.Paliesto:BAAANQAECgEIAQAAAA==.Paljin:BAAANQAECgIIAgAAAA==.Palkia:BAAANQAECgUIDgAAAA==.Palmface:BAAANQAECgcIEQAAAA==.Panatepriest:BAAANQAECgIIAgAAAA==.Pandadante:BAAANQAECgEIAQABNQAECgkJIAABAC0cAA==.Pandatunado:BAABNQAECoElAAIRAAgKOR+fIQDZAgARAAgKOR+fIQDZAgAAAA==.Panky:BAAANQAECgcIEQAAAA==.',
Pe='Pedrocerrano:BAABNQAECoEaAAICAAkKgRTLNQBDAgACAAkKgRTLNQBDAgAAAA==.Pelt:BAABNQAECoEeAAMRAAgKlBv4NgCCAgARAAgKlBv4NgCCAgAJAAUKxgnYPQD7AAAAAA==.Pewbot:BAAANQAECgcIEwABNQAECggIHAAEAAAAAQ==.',
Ph='Phirefly:BAAANQAECgQICAAAAA==.Phoebë:BAAANQADCgUIBwAAAA==.Phusiion:BAAANQAECgEJAQAAAA==.',
Pi='Pickledin:BAAANQAECgUICQAAAA==.Pinecones:BAABNQAECoEVAAIDAAcKshAdrgDbAQADAAcKshAdrgDbAQABNQAECgkJJQAhAJ4jAA==.',
Pk='Pkmntrainer:BAAANQADCgYIFgABNQADCgcIEQAEAAAAAA==.',
Pl='Please:BAACNQAFFIEXAAICAAgK/QfSAQBdAgACAAgK/QfSAQBdAgA1AAQKgSQAAgIACQr8IH4WAO0CAAIACQr8IH4WAO0CAAAA.Pleasetwo:BAABNQAECoEgAAICAAkKwg3YWACyAQACAAkKwg3YWACyAQABNQAFFAgIFwACAP0HAA==.Plumaril:BAAANQAECgYIEQAAAA==.',
Po='Pondero:BAAANQAECgMIAwABNQAECggIEwAEAAAAAA==.Pondos:BAAANQADCgIIAgABNQAECggIEwAEAAAAAA==.',
Pp='Ppleakin:BAABNQAECoEVAAIlAAcKwB8uDgBIAgAlAAcKwB8uDgBIAgAAAA==.',
Pr='Pranzar:BAAANQAECgcIEgAAAA==.Prepdagoat:BAAANQAECgQIBAABNQADCgQJBAAEAAAAAA==.',
Pt='Pticky:BAAANQAECgIIAgABNQAECgkJFQAjACEZAA==.',
Pu='Publichair:BAAANQAECgMIAwABNQAECgcIEQAEAAAAAA==.Pullo:BAABNQAECoEjAAMiAAkKgxkGLgAgAgAiAAgK/xUGLgAgAgAoAAgK+xUEJgAIAgAAAA==.Punctualpaul:BAABNQAECoEaAAIDAAkKNCPBEgB5AwADAAkKNCPBEgB5AwABNQAFFAgIGAAQAJEfAA==.Purple:BAAANQAECggIDQAAAA==.',
Py='Pyrostreak:BAAANQAECgIIAgAAAA==.Pyrê:BAAANQAECgMIAwAAAA==.',
Qu='Quidditch:BAABNQAECoEaAAIfAAgKch/6HgDeAgAfAAgKch/6HgDeAgAAAA==.',
Qw='Qwadsfwfgads:BAACNQAFFIEgAAIdAAcKEiMtAADMAgAdAAcKEiMtAADMAgA1AAQKgRoAAh0ACQoII8IGAC8DAB0ACQoII8IGAC8DAAAA.Qwamsfwfgads:BAAANQAECgIIAgABNQAFFAcIIAAdABIjAA==.',
Ra='Rabbi:BAAANQAECgIIAgABNQAECggIHAAEAAAAAQ==.Raelavent:BAAANQAECgMIBQAAAA==.Ragrappy:BAACNQAFFIEYAAIOAAgKXSMSAAAnAwAOAAgKXSMSAAAnAwA1AAQKgR4AAg4ACQq0JvgBALwDAA4ACQq0JvgBALwDAAAA.Raherius:BAAANQAECgQIBAAAAA==.Raiju:BAAANQAECgYIEAAAAA==.Rakion:BAAANQAECgcIEwAAAA==.Ramped:BAAANQADCgUIBQAAAA==.Raszahk:BAABNQAECoEnAAMGAAkKdCDvHQDbAgAGAAgKFh7vHQDbAgAYAAIKoxu1QgCkAAABNQAFFAQICgAhAEUeAA==.Rayden:BAAANQADCgcIBwAAAA==.',
Re='Realm:BAAANQADCggICAAAAA==.Reavêr:BAAANQAECgcIEQAAAA==.Redreximus:BAAANQAECggIDAAAAA==.Regilock:BAAANQAECgQICwAAAA==.Retlec:BAAANQAECgYIEAAAAA==.Reïki:BAAANQAECgEIAQAAAA==.',
Ri='Rickaz:BAAANQAECgYIBAAAAA==.Ripto:BAAANQAECgEIAQAAAA==.',
Ro='Rochaca:BAAANQADCgcIFgAAAA==.Rocksham:BAAANQADCgQIBAAAAA==.Roshana:BAAANQAECgcIEwAAAA==.Rothoof:BAAANQAECgMIAwAAAA==.',
Ru='Rudnos:BAAANQADCgMIAgABNQAECgUJDgAEAAAAAA==.Rumham:BAAANQAECgYIBwAAAA==.',
Ry='Ryptup:BAAANQAECgQIBAAAAA==.',
['Rà']='Ràndle:BAAANQABCgIIAgAAAA==.',
['Rä']='Rävën:BAAANQADCgUIBgAAAA==.',
['Rô']='Rôinujj:BAAANQAECgMIBAAAAA==.',
Sa='Safiyah:BAABNQAECoEXAAMjAAgKvBP+HQAoAgAjAAgKvBP+HQAoAgAnAAEKlQRYeQAoAAAAAA==.Saltyevoker:BAAANQADCggJHgAAAA==.Same:BAABNQAECoEhAAMdAAkKbyI+BABlAwAdAAkKbyI+BABlAwAFAAEKWx0jNwBVAAABNQAFFAgIGAAQAJEfAA==.Samophlangy:BAAANQADCgMIAwAAAA==.Sandorstus:BAABNQAECoEYAAINAAcKXRv1YQAcAgANAAcKXRv1YQAcAgAAAA==.Saothome:BAAANQAECgQIBgAAAA==.Sathreal:BAAANQAECggIEwAAAA==.Saywho:BAAANQADCgUJCQAAAA==.',
Sc='Scalywaumpus:BAAANQAECgQIBAAAAA==.Scienta:BAABNQAECoEVAAMBAAkKmh02DADkAgABAAkKmh02DADkAgAKAAMKcRAbHwCbAAABNQAFFAIIAgAEAAAAAA==.Scope:BAAANQAECgMIAwAAAA==.Scrubdk:BAAANQADCgcIBwABNQAECggIDAAEAAAAAA==.Scúbasteve:BAAANQAECgUIEQAAAA==.',
Se='Sefirot:BAAANQAECgMIBAAAAA==.Selinddra:BAAANQAECgMIBAAAAA==.Serrafin:BAAANQAECgcIAQAAAA==.Serrafindk:BAAANQAECgcIBAAAAA==.',
Sh='Shadebringer:BAAANQADCggIIgAAAA==.Shadowboxin:BAAANQADCgUIBQAAAA==.Shadowscale:BAAANQADCgUIBQAAAA==.Shamdaddy:BAAANQAECgUICwAAAA==.Shamezee:BAABNQAECoEXAAIlAAgKyxQSDAB0AgAlAAgKyxQSDAB0AgAAAA==.Shampoo:BAAANQAECgYICQAAAA==.Sharlotte:BAAANQAECgIIBAAAAA==.Shilas:BAABNQAECoEbAAIBAAkKohrjFQBTAgABAAkKohrjFQBTAgABNQAECgkJJQAhAJ4jAA==.Shishkabug:BAAANQADCgIIAgAAAA==.Show:BAAANQADCggICAAAAA==.Shownuph:BAAANQADCgYJBwAAAA==.',
Si='Sicilianhero:BAAANQADCggIEgAAAA==.Sinestroo:BAAANQAECggIBgAAAA==.Singelock:BAAANQAECgQIBAAAAA==.Sinsyn:BAAANQADCggICAABNQAECgQIBAAEAAAAAA==.Sinwarrior:BAABNQAECoEdAAIWAAkKPRkkBwClAgAWAAkKPRkkBwClAgABNQAECggICAAEAAAAAA==.Sizz:BAAANQADCgQIBAAAAA==.',
Sk='Skipcawk:BAACNQAFFIEYAAMRAAgKth6MAAB6AgARAAcK5B6MAAB6AgAJAAUK4BVNBgCkAQA1AAQKgSYAAwkACQrdJl4AAPoDAAkACQraJl4AAPoDABEABwo1HaVRACwCAAAA.Skorpco:BAABNQAECoEgAAIjAAkKXxuTDQDtAgAjAAkKXxuTDQDtAgAAAA==.',
Sl='Slickngrity:BAAANQABCgMIAwAAAA==.Sluggo:BAAANQADCggIEAAAAA==.',
Sm='Smulol:BAABNQAECoEiAAIGAAkK5xHYPgBWAgAGAAkK5xHYPgBWAgAAAA==.Smutterli:BAAANQADCgQJBAAAAA==.',
Sn='Snoopfrogg:BAABNQAECoEYAAIGAAgKlSJ+FAAOAwAGAAgKlSJ+FAAOAwAAAA==.Snow:BAAANQAECgcIDAAAAA==.',
So='Solfire:BAAANQAECgUIEAAAAA==.Solstice:BAAANQAECgMIAwAAAA==.Sometingwong:BAAANQAECgQIBAAAAA==.',
Sp='Spamheal:BAAANQADCgcIDwAAAA==.Sparkle:BAAANQAECgIIAgAAAA==.Spliffy:BAAANQABCgEIAQAAAA==.Spodermenpls:BAAANQADCgIIAgABNQAFFAcIEAACAHoXAA==.',
St='Stabber:BAAANQADCgQIBAAAAA==.Stoc:BAAANQAECgcIBwAAAA==.Stormweaver:BAAANQAECgYIEAAAAA==.',
Su='Suinogaraa:BAAANQADCgYIBgABNQAFFAgIFwABABAfAA==.Sunderwhere:BAACNQAFFIEKAAIhAAQKRR4PDgBkAQAhAAQKRR4PDgBkAQA1AAQKgRIAAiEACQoRIuUnAPECACEACQoRIuUnAPECAAAA.Superhomie:BAAANQABCgIIAQAAAA==.',
Sw='Swann:BAABNQAECoEcAAIBAAkKNBsqDwC1AgABAAkKNBsqDwC1AgAAAA==.Swavor:BAAANQAECgYICwAAAA==.Sweetbella:BAAANQADCgUIFQAAAA==.Swurves:BAAANQAECgYICAAAAA==.',
Sy='Syela:BAAANQADCgYIBgAAAA==.Symbio:BAAANQADCggIDQAAAA==.Syna:BAAANQAECgYIEQAAAA==.Syndct:BAAANQADCgIJAgAAAA==.',
Ta='Taearo:BAAANQAECgcIEQAAAA==.Taime:BAAANQAECgYIDgAAAA==.Taimie:BAAANQABCgUICAAAAA==.Talirn:BAAANQADCggIFAAAAA==.Tallanvor:BAAANQADCggIGwAAAA==.',
Te='Teax:BAAANQAECggICQAAAA==.Teddywaumpus:BAAANQADCgYJBgAAAA==.Tendecay:BAAANQAECgUIEQAAAA==.Tentotem:BAAANQAECgIIAgABNQAECgUIEQAEAAAAAA==.',
Th='Thanquiol:BAACNQAFFIEXAAILAAgKrRwFAAADAwALAAgKrRwFAAADAwA1AAQKgSEAAgsACQo/JZ4AAMADAAsACQo/JZ4AAMADAAAA.Thebaraj:BAABNQAECoEdAAMHAAcKGRerNQDxAQAHAAcKGRerNQDxAQAdAAUKAwmVOwDaAAAAAA==.Thebigdawg:BAAANQADCgUICAAAAA==.Thedrude:BAAANQADCgYICgAAAA==.Thedruidd:BAAANQAECgEIAQAAAA==.Theeassassin:BAAANQADCgIIAQAAAA==.Thelance:BAAANQAECgEIAwAAAA==.Theseglaives:BAAANQAECgEIAQAAAA==.Thrilled:BAAANQAECgQICgAAAA==.Thyora:BAACNQAFFIEOAAQeAAUKHRJiAwBGAQAeAAQKZBViAwBGAQAbAAQKVQQrCwACAQAaAAIKegg2CgCAAAA1AAQKgSEABBsACQomEVcYAP4BABsACQomEVcYAP4BABoABAoWD4okANQAAB4AAgr2F8AWAHQAAAAA.',
Ti='Tijdruid:BAAANQAECgIIAgAAAA==.Timouthy:BAAANQADCgEIAQAAAA==.Tinyblast:BAAANQADCgYICgAAAA==.',
Tj='Tjomme:BAAANQADCggIDAAAAA==.',
To='Tommypickles:BAACNQAFFIEYAAMDAAgKFBwFAgCEAgADAAcKGhkFAgCEAgAkAAIKLCLIAgC+AAA1AAQKgSgAAwMACQo+JiMFAMUDAAMACQo+JiMFAMUDACQAAgo+JuEbAM0AAAAA.Tomtrocity:BAAANQADCgUICQAAAA==.Toneclone:BAAANQAECgQIBQAAAA==.Tonestar:BAAANQAECgcIDQAAAA==.Tonyaharding:BAAANQABCgQJBAAAAA==.Toturaka:BAAANQAECgQICgAAAA==.',
Tr='Trackerjoe:BAAANQADCgMIBAAAAA==.Train:BAAANQADCgIIAgABNQAECggIHAAEAAAAAQ==.Treerex:BAAANQAECgUIEQAAAA==.Troljin:BAABNQAECoEbAAIfAAcKqhQ1VwDNAQAfAAcKqhQ1VwDNAQAAAA==.Trollpaladin:BAAANQAECgcIDAAAAA==.',
Ts='Tsipayeoc:BAAANQAECgIIAgAAAA==.',
Tw='Twistedhavoc:BAAANQAECgUIBgAAAA==.Twk:BAAANQADCggIGwAAAA==.',
Ty='Tyrgann:BAAANQADCgUIBQAAAA==.Tytoflamina:BAAANQAECgYIDAAAAA==.',
Ui='Uiazel:BAAANQADCgEIAQAAAA==.',
Um='Umalinn:BAAANQAECgcIEwAAAA==.',
Un='Unholyrep:BAAANQAECgQIBAAAAA==.',
Ur='Urbellum:BAAANQADCgQIBAAAAA==.Urukhaixd:BAAANQAECgMIAgAAAA==.',
Va='Vacca:BAAANQAECgcIEwAAAA==.Vaeyethror:BAAANQADCgQJBAAAAA==.Vahvadon:BAAANQADCgQIBAAAAA==.Valucia:BAAANQADCgEIAQAAAA==.Vandagar:BAAANQAECgcIEgAAAA==.Vapor:BAACNQAFFIELAAIUAAUK0x1ZAADwAQAUAAUK0x1ZAADwAQA1AAQKgTUAAhQACQqPI9MAAJUDABQACQqPI9MAAJUDAAAA.Varity:BAAANQABCgIIAgAAAA==.Varsity:BAABNQAECoElAAIhAAkKniPiFgBDAwAhAAkKniPiFgBDAwAAAA==.Vason:BAAANQADCgMIAwAAAA==.',
Ve='Velaryn:BAAANQAECgIJAgAAAA==.Veleanna:BAAANQADCgMIAwAAAA==.Ventumceleri:BAAANQADCgUIBQAAAA==.',
Vh='Vhega:BAAANQABCgIIAgAAAA==.',
Vi='Vinyasa:BAAANQAECgcIDAAAAA==.',
Vo='Voodoobeast:BAAANQAECgUIEQAAAA==.',
Vu='Vulbahermosa:BAAANQAECgMICwAAAA==.',
Wa='Waremtae:BAAANQADCgEIAQAAAA==.',
We='Wenguo:BAAANQAECgQIBQAAAA==.',
Wh='Wheatiees:BAAANQADCgcIGAAAAA==.Whyp:BAACNQAFFIEHAAITAAQKpgvjBQA+AQATAAQKpgvjBQA+AQA1AAQKgSMAAxMACQoMHF4QALsCABMACQoMHF4QALsCABIAAgonDYQ9AHwAAAAA.',
Wi='Wickle:BAAANQADCgcIBwAAAA==.Wingdaz:BAEANQADCggICQABNQAFFAMIBAAEAAAAAA==.',
Wo='Worgenzrdumb:BAAANQADCgcIBwAAAA==.',
Xa='Xavior:BAAANQADCgUIBQAAAA==.',
Xi='Xidara:BAAANQAECgIIAgAAAA==.Xiqualani:BAAANQADCgYIBgAAAA==.Xivei:BAACNQAFFIEcAAIOAAYKBh9hAgBhAgAOAAYKBh9hAgBhAgA1AAQKgSQAAw4ACQpiIWQfALwCAA4ACQo2IWQfALwCAAwABwosEE0KAHQBAAAA.',
Xl='Xlegolas:BAAANQAECgIIAgAAAA==.',
Xo='Xorac:BAAANQAECggIDQAAAA==.',
Xz='Xzach:BAABNQAECoEYAAIjAAkKgg3zIgD2AQAjAAkKgg3zIgD2AQAAAA==.',
Yi='Yinlou:BAAANQAECgQICAAAAA==.',
Yo='Yorha:BAAANQADCgEIAQABNQAFFAYIDwAeAJsKAA==.',
Ys='Yshtolà:BAEANQAECgQJBgAAAA==.',
Yu='Yurmage:BAAANQAECgEIAQAAAA==.',
['Yì']='Yìffist:BAAANQADCgYIDAAAAA==.',
Za='Zachx:BAACNQAFFIEYAAQYAAgKsiVaAACfAQAYAAQK7SVaAACfAQAmAAMKOyaYAABcAQAGAAMKJB/eDwAVAQA1AAQKgSQABBgACQosJk8BAGwDABgACQquIk8BAGwDAAYABwqDIAs5AGsCACYAAwodJhYMAFEBAAAA.Zaegorn:BAAANQAECggIEgAAAA==.Zamoarak:BAAANQADCgIIAgAAAA==.Zargar:BAACNQAFFIEIAAIlAAQK8hH7AQBWAQAlAAQK8hH7AQBWAQA1AAQKgSwAAiUACQo5Ix8CAIADACUACQo5Ix8CAIADAAAA.Zarmakai:BAACNQAFFIESAAMiAAcK7yMiAACUAgAiAAcK7yMiAACUAgAXAAEKxAsaKAApAAA1AAQKgSQAAiIACQqkJogCALwDACIACQqkJogCALwDAAAA.',
Ze='Zenxo:BAAANQABCgYICQAAAA==.',
Zi='Zintalesh:BAAANQAECgIIAgAAAA==.Zionx:BAAANQADCgQIBAAAAA==.Zivie:BAABNQAECoEcAAMDAAcKTxWqqgDiAQADAAcKTxWqqgDiAQAkAAEKSRCWMwBCAAAAAA==.',
Zo='Zorrick:BAAANQAECgEIAQAAAA==.',
Zu='Zurry:BAAANQABCgEIAQAAAA==.',
Zy='Zygon:BAAANQAFFAIIBAAAAA==.',
['Ðr']='Ðrakie:BAABNQAECoEZAAINAAkKrRw+KQDoAgANAAkKrRw+KQDoAgAAAA==.',
['Ök']='Ökko:BAAANQAECgUIDgAAAA==.',
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
