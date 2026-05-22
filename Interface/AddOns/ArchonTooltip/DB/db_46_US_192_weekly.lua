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

local lookup = {'Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','Mage-Arcane','Druid-Balance','Unknown-Unknown','Druid-Guardian','DemonHunter-Devourer','DeathKnight-Blood','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-05-16',data={Al='Alannaria:BAAALgADCgQJBwAAAA==.Alaris:BAAALgAECggJDAABLgAFFAUJGAABALYjAA==.Alex:BAAALgAECggJEAABLgAECggJJAACAOgfAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAABLgAECn8kAAQCAAgJ6B/UGwBCAgACAAgJsB3UGwBCAgADAAQJIBm9JQAwAQAEAAQJXyFHEAApAQAAAA==.',
Ar='Archom:BAAALgADCgUJBQAAAA==.',
Au='Audrey:BAABLgAECn8bAAQFAAkJax33BwB4AQAFAAgJDxn3BwB4AQAGAAYJNw8JJQAlAQAHAAMJ7R14iADKAAAAAA==.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8ZAAIIAAYJrgvyOwDRAAAIAAYJrgvyOwDRAAABLgAECgkJKAAJAH8WAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAIKAAgJKiIZGwDbAgAKAAgJKiIZGwDbAgABLgAECgkJFwALADMgAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn8iAAIMAAgJKgrSBABbAQAMAAgJKgrSBABbAQAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8KAAINAAUJtQU6HQDhAAANAAUJtQU6HQDhAAAuAAQKfyEAAg0ACAnkGqYbACUCAA0ACAnkGqYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCgAOAAAAAA==.Codum:BAAALgAECgUJCgAAAA==.',
Da='Dackosaur:BAABLgAECn8iAAIPAAgJ7iFZAwCpAgAPAAgJ7iFZAwCpAgAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgQJBgAAAA==.Danekriste:BAABLgAECn8SAAIQAAYJyQUOnACTAAAQAAYJyQUOnACTAAAAAA==.Darkenedone:BAACLgAFFH8XAAIRAAUJVhydDQAoAQARAAUJVhydDQAoAQAuAAQKfyEAAxEACQlCIkUCAKICABEACQlCIkUCAKICAAoAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECgUJBgAAAA==.',
De='Deathaura:BAAALgADCgMJAwAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIQAAYJExdHXgCGAQAQAAYJExdHXgCGAQABLgAFFAUJFAASAHckAA==.Denton:BAAALgAECgQJBAAAAA==.',
Do='Doggx:BAAALgADCgkJDgAAAA==.',
Dr='Drfrangelico:BAABLgAECn8ZAAMBAAgJqBGlIAC0AQABAAgJqBGlIAC0AQATAAgJ6Ab5fgAnAQAAAA==.Druido:BAACLgAFFH8UAAISAAUJdyRKAQARAgASAAUJdyRKAQARAgAuAAQKfy8AAxIACQnYJS0AAO8DABIACQnYJS0AAO8DAA0ABAnoIX0kAE0BAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8PAAIUAAQJmyCxAQBRAQAUAAQJmyCxAQBRAQAuAAQKfysAAhQACQl3IygBACcDABQACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8bAAIVAAYJ1yJWEAA7AgAVAAYJ1yJWEAA7AgAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAACAFoeAA==.',
Fr='Frankßuck:BAABLgAECn8dAAMHAAYJ5wL3lgCoAAAHAAYJ2AL3lgCoAAAFAAYJDQJPIABgAAAAAA==.Friarstrange:BAABLgAECn8UAAIVAAYJqAxiOQD1AAAVAAYJqAxiOQD1AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Ga='Gaebora:BAABLgAECn8eAAISAAYJHyEAKgAKAgASAAYJHyEAKgAKAgAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECggJLQAWAL0hAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQATAAgJfhDmUgDoAQAAAA==.Harakki:BAABLgAECn8iAAIXAAgJLhNuCACMAQAXAAgJLhNuCACMAQAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgIJAgAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCgAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8dAAIBAAYJkiL3EgAxAgABAAYJkiL3EgAxAgAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgADCgYJBgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8YAAMTAAYJUBEZjAAPAQATAAYJuA4ZjAAPAQAYAAIJRhaRNgBAAAAAAA==.Icytouch:BAAALgAECgQJCwAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECggJJwAIAC4eAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8aAAITAAYJTgfxqQDcAAATAAYJTgfxqQDcAAAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECggJEAAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8hAAIJAAkJ/x2GEwCvAgAJAAkJ/x2GEwCvAgAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAZAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAaAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECgUJCgAAAA==.',
La='Laine:BAABLgAECn8cAAIbAAYJMhyKHwDlAQAbAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAABLgAECn8XAAILAAkJMyBLBADcAgALAAkJMyBLBADcAgAAAA==.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQCAAcJWh6nBwDoAQACAAYJ7yOnBwDoAQAEAAEJAABkBABbAAADAAIJCAj6FgBRAAAuAAQKfyQAAwIACQm3Is0EAG4DAAIACQm3Is0EAG4DAAMAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8ZAAIcAAgJEA41GQBRAQAcAAgJEA41GQBRAQAAAA==.Lunarheals:BAABLgAECn8gAAIbAAYJmBoXGwCnAQAbAAYJmBoXGwCnAQAAAA==.Lunasong:BAABLgAECn8WAAIHAAcJFgYjcgAAAQAHAAcJFgYjcgAAAQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyulon:BAABLgAECn8aAAMVAAYJHxgXJQB1AQAVAAYJHxgXJQB1AQALAAUJHQmEQACxAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAABLgAECn8nAAIdAAkJ4ByvAACtAgAdAAkJ4ByvAACtAgAAAA==.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn8nAAQIAAgJLh6rDQAgAgAIAAgJ7xurDQAgAgALAAUJ3B7qNQBIAQAVAAIJdAonXgBVAAAAAA==.Monko:BAAALgAECgEJAQABLgAFFAUJFAASAHckAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
['Mí']='Míku:BAAALgAECgMJAwAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAaAFwbAA==.',
Od='Odinsknight:BAABLgAECn8ZAAQXAAgJSBF2CQByAQAXAAgJUw92CQByAQAKAAMJsAE7DgFYAAARAAEJUhR9QQA2AAAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.',
Ph='Phreek:BAABLgAECn8XAAIJAAkJdxI6eQDfAQAJAAkJdxI6eQDfAQAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDAAAAA==.Pouyan:BAABLgAECn8uAAISAAkJhhRIIQD5AQASAAkJhhRIIQD5AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn88AAQUAAkJ2RJwBgDZAQAUAAkJ2RJwBgDZAQAcAAQJZAxUMwCSAAAQAAIJKQdxvwBQAAAAAA==.Racinette:BAACLgAFFH8YAAIBAAUJtiOmBgDmAQABAAUJtiOmBgDmAQAuAAQKfxoAAgEACQn7JL8FABADAAEACQn7JL8FABADAAAA.',
Re='Rebexha:BAAALgAECgQJDAAAAA==.Redia:BAAALgAECgEJAQAAAA==.Relvanas:BAABLgAECn8YAAMeAAYJZQcuKgDqAAAeAAYJZQcuKgDqAAAfAAMJKQMDHABEAAAAAA==.',
Ri='Riverside:BAAALgAECgYJDAAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8hAAIHAAcJGANffwDgAAAHAAcJGANffwDgAAAAAA==.',
Sc='Scantron:BAAALgAECgYJCAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAAALgAFFAEJAQABLgAFFAUJBQANAFMDAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBQANAFMDAA==.Scuffedfaith:BAABLgAECn8bAAMgAAgJ0BowDgA1AgAgAAcJhR0wDgA1AgAhAAUJ4QRsSQC4AAABLgAFFAUJBQANAFMDAA==.',
Se='Sefyra:BAABLgAECn8YAAIHAAYJihPFXwAtAQAHAAYJihPFXwAtAQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgcJCAAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgQJBwAAAA==.Snolo:BAABLgAECn8YAAIaAAYJkRIVNAAMAQAaAAYJkRIVNAAMAQAAAA==.Snowyrose:BAAALgAECgMJAwABLgAECgkJFwALADMgAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAACAFoeAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAABLgAECn82AAMNAAkJTwzLHACJAQANAAkJTwzLHACJAQASAAcJGxRSRgCIAQAAAA==.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIZAAgJVRTYJABtAQAZAAgJVRTYJABtAQAAAA==.',
Tr='Trickydice:BAAALgAECgQJBAAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMCAAgJLBKFXACzAQACAAgJVhGFXACzAQAEAAMJcQ/5GACzAAAAAA==.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8iAAITAAgJVh/yGwBdAgATAAgJVh/yGwBdAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn88AAMTAAkJNiI+BgAQAwATAAkJNiI+BgAQAwAYAAIJPxkuKACGAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAILAAgJPBBfIQBSAQALAAgJPBBfIQBSAQABLgAECggJJAACAOgfAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAECggJJAACAOgfAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8FAAIaAAMJwQuWKwDRAAAaAAMJwQuWKwDRAAAuAAQKfzEAAhoACAnEF0QYAMgBABoACAnEF0QYAMgBAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAINAAgJjQc+LgAQAQANAAgJjQc+LgAQAQAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgAAAA==.',
['ßa']='ßandamonium:BAAALgAECgYJBgAAAA==.',
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
