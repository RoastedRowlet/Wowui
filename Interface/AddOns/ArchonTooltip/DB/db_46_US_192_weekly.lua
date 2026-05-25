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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Unknown-Unknown','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Mage-Arcane','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-05-23',data={Ak='Ako:BAAALgADCgQJBAAAAA==.',
Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECggJDAABLgAFFAUJHQABAN8kAA==.Alex:BAAALgAECggJEgABLgAFFAMJBQACAC4KAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8FAAMCAAMJLgqOagDAAAACAAMJkQeOagDAAAADAAEJKQnrFwBNAAAuAAQKfzQABAIACAmQIVsTAJwCAAIACAmQIVsTAJwCAAQABAkgGb0lADABAAMABAlfIUcQACkBAAAA.',
Ar='Archom:BAAALgADCgYJBgAAAA==.',
Au='Audrey:BAABLgAECn8kAAQFAAkJ2CM2CQDtAgAFAAcJeiQ2CQDtAgAGAAgJZxRnFADnAQAHAAgJDxkUCgCnAQABLgAFFAIJAgAIAAAAAA==.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8aAAIJAAYJrguIQwDQAAAJAAYJrguIQwDQAAABLgAFFAMJBwAKANMJAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAILAAgJKiIZGwDbAgALAAgJKiIZGwDbAgABLgAFFAMJBwAMAOscAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8qAAINAAgJ0w2hBAB7AQANAAgJ0w2hBAB7AQAAAA==.',
By='Byng:BAAALgAECgEJAQAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8LAAIOAAUJtQUVIwDcAAAOAAUJtQUVIwDcAAAuAAQKfyMAAg4ACQlMGaYbACUCAA4ACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAIAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Da='Dackosaur:BAABLgAECn8qAAIPAAgJUCOtAwDAAgAPAAgJUCOtAwDAAgAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgYJCAAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQUirwCZAAAQAAYJyQUirwCZAAAAAA==.Darkenedone:BAACLgAFFH8cAAIRAAUJJiHBCgB0AQARAAUJJiHBCgB0AQAuAAQKfyEAAxEACQlCIngDAOwCABEACQlCIngDAOwCAAsAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAIAAAAAA==.Demono:BAABLgAECn8WAAIQAAYJExdHXgCGAQAQAAYJExdHXgCGAQABLgAFFAYJFgASAKEjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAAALgAECgQJBQAAAA==.',
Dr='Drfrangelico:BAABLgAECn8aAAMBAAgJqBHJJgCtAQABAAgJqBHJJgCtAQATAAgJ6QbKkgAtAQAAAA==.Druido:BAACLgAFFH8WAAISAAYJoSNKAQARAgASAAYJoSNKAQARAgAuAAQKfzIAAxIACQnYJS0AAO8DABIACQnYJS0AAO8DAA4ABAnoIRksAEYBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8TAAIUAAQJACJjAQB/AQAUAAQJACJjAQB/AQAuAAQKfysAAhQACQl3IygBACcDABQACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8dAAIVAAgJZiF4CADgAgAVAAgJZiF4CADgAgAAAA==.',
Eo='Eocháid:BAAALgAECgEJAQABLgAFFAIJAgAIAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAACAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMFAAcJOQXrhwD9AAAFAAcJOQXrhwD9AAAHAAYJDQKrJABqAAAAAA==.Friarstrange:BAABLgAECn8UAAIVAAYJqAxDRgD5AAAVAAYJqAxDRgD5AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8fAAMSAAcJMx8AKgAKAgASAAYJHyEAKgAKAgAWAAEJvRQMOQA/AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJNgAXAFokAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQATAAgJfhDmUgDoAQAAAA==.Harakki:BAABLgAECn8qAAIYAAgJWhT+CQCcAQAYAAgJWhT+CQCcAQAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAIAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIBAAcJ/yH0DgCCAgABAAcJ/yH0DgCCAgAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAEJAQAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAIAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMTAAYJSRMdnwAXAQATAAYJsRAdnwAXAQAZAAIJRhafPgA+AAAAAA==.Icytouch:BAAALgAECgQJDAAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJLwAJAKMhAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8dAAITAAgJ4wfwkQAuAQATAAgJ4wfwkQAuAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgkJEwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8nAAIKAAkJjB7fFQC7AgAKAAkJjB7fFQC7AgAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAbAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECgUJCgAAAA==.',
La='Laine:BAABLgAECn8cAAIcAAYJMhyKHwDlAQAcAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8HAAIMAAMJ6xzqEgAEAQAMAAMJ6xzqEgAEAQAuAAQKfxoAAgwACQnxIOsEAOUCAAwACQnxIOsEAOUCAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQCAAcJXB6LDgDWAQACAAYJ7yOLDgDWAQADAAEJAABkBABbAAAEAAIJDgicFQBTAAAuAAQKfyQAAwIACQm3Is0EAG4DAAIACQm3Is0EAG4DAAQAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8ZAAIdAAgJEQ4JHwBFAQAdAAgJEQ4JHwBFAQAAAA==.Lunarheals:BAABLgAECn8iAAIcAAgJ7RiFEgAjAgAcAAgJ7RiFEgAjAgAAAA==.Lunasong:BAABLgAECn8XAAIFAAgJAAZhcQAvAQAFAAgJAAZhcQAvAQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyguard:BAAALgAECgUJBQABLgAECggJIgAVAEEUAA==.Martyulon:BAABLgAECn8iAAMVAAgJQRRSIwC9AQAVAAgJQRRSIwC9AQAMAAUJHQmBTACnAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyROaAQDvAAAeAAMJyROaAQDvAAAuAAQKfyoAAh4ACQnkHPQAAKgCAB4ACQnkHPQAAKgCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8vAAQJAAgJoyGjBwCdAgAJAAgJ7SCjBwCdAgAMAAUJ3B7qNQBIAQAVAAIJdAonXgBVAAAAAA==.Monko:BAAALgAECgEJAQABLgAFFAYJFgASAKEjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAbAFwbAA==.',
Od='Odinsknight:BAABLgAECn8fAAQYAAgJohJGCgCVAQAYAAgJ8xFGCgCVAQALAAMJsAE7DgFYAAARAAEJUhR/TAA0AAAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAECgEJAQAAAA==.',
Ph='Phreek:BAABLgAECn8dAAIKAAkJdxI6eQDfAQAKAAkJdxI6eQDfAQAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn8uAAISAAkJhhRXJgD6AQASAAkJhhRXJgD6AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn88AAQUAAkJ2BITCADPAQAUAAkJ2BITCADPAQAdAAQJZAwuPACMAAAQAAIJKQdG2ABOAAAAAA==.Racinette:BAACLgAFFH8dAAIBAAUJ3ySPBwD6AQABAAUJ3ySPBwD6AQAuAAQKfxoAAgEACQn7JL8FABADAAEACQn7JL8FABADAAAA.',
Re='Rebexha:BAAALgAECgUJDQAAAA==.Redia:BAAALgAECgEJAgAAAA==.Relvanas:BAABLgAECn8iAAMfAAgJ/gbMIwBIAQAfAAgJ/gbMIwBIAQAgAAMJKQM4HwBCAAAAAA==.',
Ri='Riverside:BAAALgAECgYJDgAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8jAAIFAAcJLwNflQDgAAAFAAcJLwNflQDgAAAAAA==.',
Sc='Scannedtron:BAAALgADCgQJBAAAAA==.Scantron:BAAALgAECgcJCgAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8GAAILAAUJCgTuaAD4AAALAAUJCgTuaAD4AAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBgALAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0BqLEQAwAgAhAAcJhR2LEQAwAgAiAAUJ4QRsSQC4AAABLgAFFAUJBgALAAoEAA==.',
Se='Sefyra:BAABLgAECn8ZAAIFAAYJJRVfaQBBAQAFAAYJJRVfaQBBAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgADCgEJAQAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgUJCQAAAA==.Snolo:BAABLgAECn8gAAIbAAgJWBAQKgB0AQAbAAgJWBAQKgB0AQAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAMJBwAMAOscAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAACAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8HAAIOAAMJtwQgKgCpAAAOAAMJtwQgKgCpAAAuAAQKfzoAAw4ACQlSDDIiAIoBAA4ACQlSDDIiAIoBABIABwkaF1JGAIgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRSNLABmAQAaAAgJVRSNLABmAQAAAA==.',
Tr='Trickydice:BAAALgAECgUJBgAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMCAAgJLBKFXACzAQACAAgJVhGFXACzAQADAAMJcQ/5GACzAAAAAA==.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8qAAITAAgJYSDCGwCAAgATAAgJYSDCGwCAAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9FAAMTAAkJESMuBgApAwATAAkJESMuBgApAwAZAAIJPxlRLgCDAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAIMAAgJPBBCJwBPAQAMAAgJPBBCJwBPAQABLgAFFAMJBQACAC4KAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAMJBQACAC4KAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8IAAIbAAMJ2g5tMgDJAAAbAAMJ2g5tMgDJAAAuAAQKfzEAAhsACAm9F90bANcBABsACAm9F90bANcBAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIOAAgJjQcRNQASAQAOAAgJjQcRNQASAQAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgUJDgAIAAAAAA==.',
['ßa']='ßandamonium:BAAALgAECgYJCQAAAA==.',
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
