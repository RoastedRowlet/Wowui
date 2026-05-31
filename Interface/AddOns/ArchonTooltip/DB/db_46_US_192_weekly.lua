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

local lookup = {'Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Mage-Frost','Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Druid-Feral','Warrior-Arms','DeathKnight-Frost','Paladin-Protection','Shaman-Elemental','Evoker-Augmentation','Priest-Holy','DemonHunter-Havoc','Mage-Fire','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Priest-Shadow',}
local provider = {region='US',realm='ShatteredHalls',name='US',type='weekly',zone=46,date='2026-05-30',data={Ab='Abs:BAAALgADCgEJAQAAAA==.',
Ak='Ako:BAAALgAECgkJDgAAAA==.',
Al='Alannaria:BAAALgAECgEJAQAAAA==.Alaris:BAAALgAFFAEJAQABLgAFFAUJIgABAN8kAA==.Alex:BAABLgAECn8ZAAMCAAkJgBekYgCPAQACAAgJKBSkYgCPAQADAAUJ7xciJQAQAQABLgAFFAQJBwAEAC4KAA==.Allmight:BAAALgADCgIJAgAAAA==.Alx:BAACLgAFFH8HAAQEAAQJLgqSdQC+AAAEAAMJkQeSdQC+AAAFAAEJKQmjHgBLAAAGAAEJAACuJwAAAAAuAAQKfzUABAQACAmQIcMVAJYCAAQACAmQIcMVAJYCAAYABAkgGb0lADABAAUABQlzG0cQACkBAAAA.',
Ar='Archom:BAAALgADCgYJBgAAAA==.Ares:BAAALgAECgYJBgAAAA==.',
Au='Audrey:BAACLgAFFH8HAAMHAAMJUBU8JgCJAAAHAAIJeg08JgCJAAAIAAEJ/STOeABtAAAuAAQKfyUABAgACQnYI00LAOcCAAgABwl6JE0LAOcCAAcACAlnFGEWAOIBAAkACAkPGegKAKQBAAAA.',
Av='Avoe:BAAALgADCgYJBgAAAA==.',
Ba='Banakafalata:BAABLgAECn8bAAIKAAcJ8QnCPgDuAAAKAAcJ8QnCPgDuAAABLgAFFAMJCgALANMJAA==.Bat:BAAALgAECgUJDAAAAA==.',
Be='Beautieful:BAAALgADCgcJEQAAAA==.Bevo:BAAALgAECgYJBgAAAA==.',
Bi='Bigsha:BAAALgADCgYJCwAAAA==.',
Bl='Blux:BAAALgADCgUJBQAAAA==.',
Bo='Bondagestyle:BAAALgADCgIJAgAAAA==.Borgor:BAABLgAECn8pAAICAAgJKiIZGwDbAgACAAgJKiIZGwDbAgABLgAFFAMJCgAMAPQfAA==.',
Br='Braindead:BAAALgAECgUJBQAAAA==.',
Bt='Btterbean:BAAALgAECgMJBQAAAA==.',
Bu='Burdên:BAABLgAECn82AAINAAkJ7Q95AwDTAQANAAkJ7Q95AwDTAQAAAA==.',
By='Byng:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ch='Chamber:BAAALgAECgQJBAAAAA==.Chambr:BAAALgAECgEJAQAAAA==.Chamchi:BAAALgAECgQJBAAAAA==.Cheri:BAACLgAFFH8MAAIPAAYJGweCGwAVAQAPAAYJGweCGwAVAQAuAAQKfyMAAg8ACQlMGaYbACUCAA8ACQlMGaYbACUCAAAA.',
Co='Codh:BAAALgAECgEJAgABLgAECgUJCwAOAAAAAA==.Codum:BAAALgAECgUJCwAAAA==.',
Cu='Cubenzi:BAAALgADCgkJBAAAAA==.',
Da='Dackosaur:BAABLgAECn8vAAIQAAkJGiPLAQAiAwAQAAkJGiPLAQAiAwAAAA==.Daedalos:BAAALgAECgkJCQAAAA==.Dageek:BAAALgAECgEJAQAAAA==.Daneikus:BAAALgAECgYJCQAAAA==.Danekriste:BAABLgAECn8SAAIRAAYJyQXMvQCMAAARAAYJyQXMvQCMAAAAAA==.Darkenedone:BAACLgAFFH8iAAIDAAYJ2h4LCADAAQADAAYJ2h4LCADAAQAuAAQKfyEAAwMACQlCIjEEAOQCAAMACQlCIjEEAOQCAAIAAgkPEsoUAUsAAAAA.',
Db='Dblackfalcon:BAAALgAECggJCQAAAA==.',
De='Deathaura:BAAALgAECgIJAgAAAA==.Deathbyarrow:BAAALgADCgUJBQAAAA==.Demonex:BAAALgADCgMJAwABLgAECgQJBAAOAAAAAA==.Demono:BAABLgAECn8WAAIRAAYJExdHXgCGAQARAAYJExdHXgCGAQABLgAFFAcJHAASAAkjAA==.Denton:BAAALgAECgQJBQAAAA==.',
Do='Doggx:BAAALgAECgcJDgAAAA==.',
Dr='Drfrangelico:BAABLgAECn8aAAMBAAgJqBGOKQCrAQABAAgJqBGOKQCrAQATAAgJ6QZEpgASAQAAAA==.Druido:BAACLgAFFH8cAAISAAcJCSMGAwDIAgASAAcJCSMGAwDIAgAuAAQKfzIAAxIACQnYJS0AAO8DABIACQnYJS0AAO8DAA8ABAnoIcgvAEQBAAAA.Drunkmonk:BAAALgAECggJEAAAAA==.',
Ds='Ds:BAACLgAFFH8VAAIUAAUJACLnAQB5AQAUAAUJACLnAQB5AQAuAAQKfysAAhQACQl3IygBACcDABQACQl3IygBACcDAAAA.',
Du='Dumdum:BAAALgAECgQJBgAAAA==.',
En='Enjoyby:BAABLgAECn8eAAIVAAgJ4iEdCQDpAgAVAAgJ4iEdCQDpAgAAAA==.',
Eo='Eocháid:BAAALgAECgEJAQABLgAFFAIJAgAOAAAAAA==.',
Er='Erzascarlet:BAAALgADCgIJAgAAAA==.',
Ex='Exayah:BAAALgAECgQJBAAAAA==.',
Fi='Fistwarior:BAAALgAECgYJDAABLgAFFAcJIAAEAFweAA==.',
Fr='Frankßuck:BAABLgAECn8kAAMIAAcJOQVskgD/AAAIAAcJOQVskgD/AAAJAAYJDQIeJwBpAAAAAA==.Friarstrange:BAABLgAECn8UAAIVAAYJqAyfTwD5AAAVAAYJqAyfTwD5AAAAAA==.Frosticle:BAAALgADCgEJAQAAAA==.',
Fu='Fuwawá:BAAALgAECgMJAwAAAA==.',
Ga='Gaebora:BAABLgAECn8hAAMSAAkJwR0AKgAKAgASAAYJHyEAKgAKAgAWAAMJQhJcJQC6AAAAAA==.',
Gn='Gnomekabobs:BAAALgADCgEJAQABLgAECgkJQAAXAGglAA==.',
Gy='Gyllene:BAAALgADCgMJAwAAAA==.',
Ha='Hadory:BAABLgAECn8WAAITAAgJfhDmUgDoAQATAAgJfhDmUgDoAQAAAA==.Harakki:BAABLgAECn8vAAMYAAkJihNaCgCrAQAYAAgJ3xRaCgCrAQADAAEJOwo9UQA5AAAAAA==.Hardscope:BAAALgAECgYJEAAAAA==.Havilove:BAAALgADCgQJBAAAAA==.',
He='Herbie:BAAALgADCgMJBAABLgAECgUJCwAOAAAAAA==.',
Ho='Holyroran:BAABLgAECn8eAAIBAAcJ/yGsEAB9AgABAAcJ/yGsEAB9AgAAAA==.Hopseng:BAAALgADCgQJBAAAAA==.Hotsrock:BAAALgAECgEJAQAAAA==.',
['Hé']='Hécâté:BAAALgAFFAIJAgAAAA==.',
Ia='Iamundeadian:BAEALgAECgYJAwABLgAECgkJAgAOAAAAAA==.',
Ic='Icdeadpeeple:BAABLgAECn8ZAAMTAAYJSRMcrAAJAQATAAYJsRAcrAAJAQAZAAIJRhbfQwA+AAAAAA==.Icytouch:BAAALgAECgYJEgAAAA==.',
Il='Illijim:BAAALgAECgMJAwABLgAECgkJNAAKAEkhAA==.',
Im='Immortal:BAAALgAECgkJCgAAAA==.',
Ip='Ipwnprince:BAAALgAECgEJAQAAAA==.',
Is='Isityummy:BAAALgAECgIJAQAAAA==.',
Ja='Jarakk:BAAALgADCgUJCAAAAA==.',
Je='Jedrek:BAAALgAECgEJAQAAAA==.Jellybeanrez:BAABLgAECn8mAAITAAgJ4weLpQATAQATAAgJ4weLpQATAQAAAA==.',
Jo='Jojolion:BAAALgAECgQJCAAAAA==.Jorrdan:BAAALgAECgkJEwAAAA==.',
Ka='Kaidapixi:BAAALgADCgYJBgAAAA==.Kalacia:BAABLgAECn8nAAILAAkJjB7XGACuAgALAAkJjB7XGACuAgAAAA==.',
Ke='Keysbricked:BAAALgAECgQJBgABLgAECgkJGAAaAFUUAA==.',
Ki='Kickflip:BAAALgAECgYJBgABLgAFFAYJFQAbAFwbAA==.Kikthebucket:BAAALgADCgEJAQAAAA==.',
Kr='Kraytoes:BAAALgADCgEJAQAAAA==.Kritz:BAAALgAECggJDwAAAA==.',
Kw='Kwaichang:BAAALgAECgEJAQAAAA==.',
La='Laine:BAABLgAECn8cAAIcAAYJMhyKHwDlAQAcAAYJMhyKHwDlAQAAAA==.Lastexile:BAAALgAECgEJAQAAAA==.',
Li='Linglinda:BAACLgAFFH8KAAIMAAMJ9B/oEQAbAQAMAAMJ9B/oEQAbAQAuAAQKfxsAAgwACQnxIKkFAOMCAAwACQnxIKkFAOMCAAAA.',
Lo='Lockstar:BAEALgAECgkJAgAAAA==.Lockwarior:BAACLgAFFH8gAAQEAAcJXB77FQDGAQAEAAYJ7yP7FQDGAQAFAAEJAABkBABbAAAGAAIJDgicFQBTAAAuAAQKfyQAAwQACQm3Is0EAG4DAAQACQm3Is0EAG4DAAYAAQkAAM6AAA0AAAAA.Loricarvonri:BAAALgAECgUJCAAAAA==.Lottiedottie:BAAALgAECgQJBAAAAA==.Love:BAAALgAECgQJBAAAAA==.',
Lu='Luciena:BAABLgAECn8eAAIdAAgJuw/dHQBoAQAdAAgJuw/dHQBoAQAAAA==.Lunarheals:BAABLgAECn8jAAIcAAgJ7RiSFAAaAgAcAAgJ7RiSFAAaAgAAAA==.Lunasong:BAABLgAECn8aAAIIAAkJ8wbXXAB2AQAIAAkJ8wbXXAB2AQAAAA==.Luxury:BAAALgAECgMJBgAAAA==.',
Ma='Marcagi:BAAALgADCgEJAQAAAA==.Martyguard:BAAALgAECgUJBQABLgAECgkJJwAVAPATAA==.Martyulon:BAABLgAECn8nAAMVAAkJ8BOgHwD1AQAVAAkJ8BOgHwD1AQAMAAUJHQlFUwCmAAAAAA==.Maxlink:BAAALgAECgMJAwAAAA==.',
Me='Melikefire:BAACLgAFFH8HAAIeAAMJyRM+AgDRAAAeAAMJyRM+AgDRAAAuAAQKfyoAAh4ACQnkHDoBAJoCAB4ACQnkHDoBAJoCAAAA.Melikesword:BAAALgAECgQJBAAAAA==.',
Mo='Molda:BAAALgAECgcJEwAAAA==.Monkjimothy:BAABLgAECn80AAQKAAkJSSGLCACZAgAKAAgJ7SCLCACZAgAMAAYJ2x7qNQBIAQAVAAIJdAonXgBVAAAAAA==.Monko:BAAALgAECgEJAQABLgAFFAcJHAASAAkjAA==.Moomie:BAAALgADCgMJAwAAAA==.Moonstrike:BAAALgAECggJEAAAAA==.Mortius:BAAALgADCgcJDAAAAA==.',
Na='Navier:BAAALgADCgMJAwAAAA==.',
Ne='Nero:BAAALgADCgEJAQAAAA==.',
No='Noice:BAAALgAECgIJAgABLgAFFAYJFQAbAFwbAA==.',
Od='Odinsknight:BAABLgAECn8lAAQYAAgJMxNFCwCZAQAYAAgJhRJFCwCZAQACAAMJsAE7DgFYAAADAAEJUhTZUgA0AAAAAA==.',
Pa='Pandáam:BAAALgAECgEJAQAAAA==.Parkeidand:BAAALgAECggJEQAAAA==.Patodeez:BAAALgAFFAIJAgAAAA==.',
Ph='Phreek:BAABLgAECn8dAAILAAkJdxI6eQDfAQALAAkJdxI6eQDfAQAAAA==.',
Po='Pookie:BAAALgAECgEJAQAAAA==.Portius:BAAALgADCggJDQAAAA==.Pouyan:BAABLgAECn81AAISAAkJhhTpKAD5AQASAAkJhhTpKAD5AQAAAA==.',
Pr='Prfctpullout:BAAALgADCgIJAgAAAA==.',
Ra='Ra:BAABLgAECn9KAAQUAAkJDhXqCADJAQAUAAkJ2BLqCADJAQAdAAcJ9hR/GwCAAQARAAIJKQfi4wBOAAAAAA==.Racinette:BAACLgAFFH8iAAIBAAUJ3yTzCQDyAQABAAUJ3yTzCQDyAQAuAAQKfxoAAgEACQn7JL8FABADAAEACQn7JL8FABADAAAA.',
Re='Rebexha:BAAALgAECgcJEwAAAA==.Redia:BAAALgAECgEJAgAAAA==.Relvanas:BAABLgAECn8jAAMfAAgJ/gY1JwBBAQAfAAgJ/gY1JwBBAQAgAAMJKQOXIQBAAAAAAA==.',
Ri='Riverside:BAAALgAECgYJDwAAAA==.',
Sa='Saelesth:BAAALgAECggJEAAAAA==.Sambie:BAABLgAECn8oAAIIAAkJGwN4iQASAQAIAAkJGwN4iQASAQAAAA==.',
Sc='Scannedtron:BAAALgAECgcJBwAAAA==.Scantron:BAAALgAECgcJDAAAAA==.Scrappycocco:BAAALgAECgUJDAAAAA==.Scuffedbones:BAABLgAFFH8HAAICAAUJCgSKdwDvAAACAAUJCgSKdwDvAAAAAA==.Scuffedbop:BAAALgADCgcJDQABLgAFFAUJBwACAAoEAA==.Scuffedfaith:BAABLgAECn8bAAMhAAgJ0BpdEwAmAgAhAAcJhR1dEwAmAgAiAAUJ4QRsSQC4AAABLgAFFAUJBwACAAoEAA==.',
Se='Sefyra:BAABLgAECn8aAAIIAAcJyBM0XAB4AQAIAAcJyBM0XAB4AQAAAA==.Setelai:BAAALgADCgUJBQAAAA==.',
Sh='Shamroran:BAAALgAECgEJAQAAAA==.Shankz:BAAALgADCgEJAQAAAA==.Shishi:BAAALgADCgkJCgAAAA==.',
Si='Sinful:BAAALgAECgIJAgAAAA==.',
Sn='Sneakycress:BAAALgAECgUJCQAAAA==.Snolo:BAABLgAECn8gAAIbAAgJWBDNLABsAQAbAAgJWBDNLABsAQAAAA==.Snowyrose:BAAALgAECgMJAwABLgAFFAMJCgAMAPQfAA==.',
So='Sorakaa:BAAALgADCgUJBQAAAA==.Soulstoned:BAAALgADCgYJCQAAAA==.',
Sp='Spiritwarior:BAAALgAFFAIJAwABLgAFFAcJIAAEAFweAA==.Splux:BAAALgAECgUJBQAAAA==.',
St='Starsky:BAAALgADCgUJBgAAAA==.Strangedraco:BAAALgADCgYJBgAAAA==.Strangewood:BAACLgAFFH8KAAIPAAMJXQXYLwCVAAAPAAMJXQXYLwCVAAAuAAQKfzsAAxIACQk9GlJGAIgBABIABwl5F1JGAIgBAA8ACQlSDEIlAIgBAAAA.',
Su='Sugarhzopurp:BAAALgAECgcJCAAAAA==.Summerss:BAAALgADCggJCAAAAA==.',
Sw='Swiftlee:BAAALgAECgYJBwAAAA==.',
Th='Thunderfnk:BAABLgAECn8YAAIaAAgJVRSVMABjAQAaAAgJVRSVMABjAQAAAA==.',
Tr='Trickydice:BAAALgAECgcJDAAAAA==.',
Tw='Twentyfour:BAAALgAECgEJAQABLgAECgYJDwAOAAAAAA==.',
Ty='Tysreaper:BAABLgAECn8YAAMEAAgJLBKFXACzAQAEAAgJVhGFXACzAQAFAAMJcQ/5GACzAAAAAA==.',
Ur='Urickea:BAAALgAECgEJAQAAAA==.',
Va='Valdyr:BAABLgAECn8vAAITAAkJqx/ZEQDEAgATAAkJqx/ZEQDEAgAAAA==.Vannishstrik:BAAALgAECgQJBAAAAA==.Varri:BAAALgADCgMJAwAAAA==.',
Vo='Vodouism:BAAALgAECgUJBQABLgAECgYJFQASACAjAA==.Vonbane:BAAALgADCgYJCAAAAA==.',
Vu='Vu:BAAALgAECgYJBgAAAA==.',
Wa='Warcawk:BAAALgAECgYJEgAAAA==.Wardsky:BAAALgAECgYJCgAAAA==.',
We='Webbington:BAAALgAECgEJAQAAAA==.',
Wr='Wreckthar:BAABLgAECn9OAAMTAAkJtCQGBABNAwATAAkJtCQGBABNAwAZAAIJPxkHMgCCAAAAAA==.',
Wu='Wu:BAABLgAECn8WAAIMAAgJPBDdKgBMAQAMAAgJPBDdKgBMAQABLgAFFAQJBwAEAC4KAA==.',
Xe='Xelagos:BAAALgAECgcJBwABLgAFFAQJBwAEAC4KAA==.',
Xy='Xyla:BAAALgADCgEJAQAAAA==.',
Ze='Zenetrawr:BAACLgAFFH8MAAIbAAQJOQ5BKgD9AAAbAAQJOQ5BKgD9AAAuAAQKfzIAAhsACAmDGOsbAN4BABsACAmDGOsbAN4BAAAA.',
Zi='Zingispingus:BAABLgAECn8fAAIPAAgJjQd6OQARAQAPAAgJjQd6OQARAQAAAA==.',
['Ær']='Ærìs:BAAALgADCgcJBwAAAA==.',
['Ða']='Ðaora:BAAALgADCgkJCgABLgAECgcJFAAXAHEbAA==.',
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
