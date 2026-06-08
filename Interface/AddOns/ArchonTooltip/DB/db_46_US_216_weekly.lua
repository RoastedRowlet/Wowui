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

local lookup = {'Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Monk-Brewmaster','Monk-Windwalker','Warlock-Affliction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Druid-Guardian','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Druid-Balance','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=46,date='2026-06-07',data={Ab='Abeteon:BAAALgAECgEJAQAAAA==.',
Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8vAAIBAAgJ6B9sCQBNAgABAAgJ6B9sCQBNAgAAAA==.',
Ae='Aelvoker:BAACLgAFFH8ZAAQCAAcJuhpBEwC5AQACAAcJsBVBEwC5AQADAAQJPhUNBAAJAQAEAAQJ7gaBEwCQAAAuAAQKfxcABAMACQlFH1EHAHcCAAMABgkkI1EHAHcCAAQABwmdEYkaALcBAAIAAgndGtFKAKkAAAAA.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgUJCwAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR50BQCfAgAFAAgJOR50BQCfAgAGAAgJ1xPGcgB+AQAAAA==.',
Ap='Apachaler:BAABLgAECn8nAAQHAAkJ+xrDDwCYAgAHAAkJ+xrDDwCYAgAIAAEJNhm5gABCAAAJAAEJIgnXmgAsAAAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8VAAMKAAQJSB+1AgBsAQAKAAQJSB+1AgBsAQALAAIJ5x5lMgCuAAAuAAQKfzQAAwoACQkgJVoAAFYDAAoACQkgJVoAAFYDAAsABQm6H+5QAKMBAAAA.',
Az='Azriel:BAAALgADCgEJAQAAAA==.Azshan:BAAALgADCgQJBAABLgAECgQJBwAMAAAAAA==.',
Ba='Babymager:BAABLgAECn8iAAINAAcJ5QsVsQAdAQANAAcJ5QsVsQAdAQAAAA==.Babyshamz:BAAALgAECgYJBgAAAA==.Barranphalnx:BAAALgAECgEJAQAAAA==.',
Bb='Bbldrizzy:BAAALgADCgEJAQAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgAECgYJCwABLgAECgcJGwAOAEQQAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bh='Bhal:BAAALgAECgEJAQAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8WAAIPAAQJxR0CDABXAQAPAAQJxR0CDABXAQAuAAQKfzwAAg8ACQnRJd4AAGYDAA8ACQnRJd4AAGYDAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgYJDQAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgcJEAAMAAAAAA==.Bluchu:BAEALgAECgEJAQABLgAECgcJEAAMAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECgkJDwAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8cAAINAAcJ2h0UFgAjAgANAAcJ2h0UFgAjAgAuAAQKfysAAg0ACQk/JU0KAHEDAA0ACQk/JU0KAHEDAAAA.Buddiez:BAAALgADCgEJAQAAAA==.Built:BAABLgAECn8eAAQPAAkJ9CBYDAAJAgAPAAgJASFYDAAJAgAQAAMJTBi+fwDoAAARAAEJ2hhogQBBAAAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.Carrot:BAAALgAECgIJAgAAAA==.',
Ce='Cenwen:BAACLgAFFH8TAAINAAQJYBohQwBYAQANAAQJYBohQwBYAQAuAAQKfycAAg0ACQmVHoI/ABgCAA0ACQmVHoI/ABgCAAAA.',
Ch='Chaos:BAABLgAECn9KAAIPAAkJbiW4AABuAwAPAAkJbiW4AABuAwAAAA==.Chonk:BAAALgAECgYJBgAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAcJIAASAFEVAA==.',
Cl='Clawreece:BAAALgAECgQJCQAAAA==.',
Co='Conta:BAAALgAECgYJCQAAAA==.',
Cr='Cryingtears:BAABLgAECn8pAAQTAAgJ9A8UOABjAQATAAgJ9A8UOABjAQAGAAcJqQbS3QDVAAAFAAEJAAEEVwAYAAAAAA==.',
Cu='Cuchicu:BAABLgAECn9CAAMUAAkJ1xu+DgDYAgAUAAkJ1xu+DgDYAgAVAAUJEhK9NwApAQAAAA==.',
Da='Dakkonix:BAEALgAECgcJEAAAAA==.Dakkonixx:BAEALgAECgUJBgABLgAECgcJEAAMAAAAAA==.Damagexx:BAAALgAECgIJBQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.Darklords:BAAALgADCgEJAQAAAA==.Daviid:BAAALgADCgYJBgAAAA==.',
De='Demigodd:BAAALgADCgIJAgAAAA==.Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAISAAcJsx6EMwBoAgASAAcJsx6EMwBoAgAAAA==.Dextt:BAABLgAECn8dAAIWAAcJLCIrDgCpAgAWAAcJLCIrDgCpAgAAAA==.Dez:BAABLgAECn8mAAITAAkJyRWAGAA6AgATAAkJyRWAGAA6AgAAAA==.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgAECgUJBQAAAA==.',
Dr='Dragnaballs:BAEALgAECgcJEgABLgAFFAkJNQANALseAA==.Drdot:BAAALgAECgEJAgABLgAECggJHwASALsaAA==.Drehd:BAACLgAFFH8KAAIWAAMJvCQQKwAiAQAWAAMJvCQQKwAiAQAuAAQKfy0AAhYACAnVJHwIACADABYACAnVJHwIACADAAAA.Drewcifer:BAACLgAFFH8JAAIXAAQJDBSYXgDDAAAXAAQJDBSYXgDDAAAuAAQKfy0AAhcACQlFIhALAOgCABcACQlFIhALAOgCAAEuAAUUBAkJABcADBQA.Drewwar:BAAALgAECgEJAQABLgAFFAQJCQAXAAwUAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumalshadows:BAAALgAECgUJBQAAAA==.Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQABLgAFFAMJAwAMAAAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgMJCgAMAAAAAA==.',
Eg='Egoon:BAAALgAECgQJBgAAAA==.',
El='Elarial:BAAALgADCgEJAQAAAA==.Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8jAAISAAYJ0yACGgD0AQASAAYJ0yACGgD0AQAuAAQKfygAAhIACQlOIuwSAAoDABIACQlOIuwSAAoDAAAA.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fl='Flop:BAAALgADCgIJAgAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgcJFwANAA8MAA==.Fotmtrash:BAACLgAFFH8XAAQYAAQJYR79EwATAQAZAAQJTBc6IgAdAQAYAAMJbCD9EwATAQAaAAIJ4gSjLwBzAAAuAAQKfy8ABBkACQk4I34FACgDABkACQn+H34FACgDABgACAkZIu8HAMwCABoAAgknCWFaAE4AAAAA.Foxxydots:BAABLgAECn82AAILAAkJ5RjLLgAXAgALAAkJ5RjLLgAXAgAAAA==.',
Fr='Frostitoot:BAABLgAECn8XAAINAAcJDwzqrgAgAQANAAcJDwzqrgAgAQAAAA==.',
Fu='Fupa:BAAALgAECgEJAQAAAA==.',
Ga='Galbsadi:BAABLgAECn8nAAMbAAgJJBOZEQAgAQALAAgJYw9EbQBbAQAbAAcJtQ+ZEQAgAQAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Genie:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgUJDAAAAA==.Getsuga:BAAALgAECgIJAwAAAA==.',
Gh='Ghostmonk:BAAALgAFFAIJAgABLgAFFAUJIQASAAUlAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8kAAQcAAkJviDcHABnAgAcAAcJOiHcHABnAgABAAYJPRgFGwAZAQAdAAYJshqyLgC8AAAAAA==.Graflock:BAAALgAECgUJBQAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIcAAYJmg+qTgBsAQAcAAYJmg+qTgBsAQAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECggJEAAAAA==.Hamtaro:BAAALgAECgYJDAAAAA==.Hawthorne:BAACLgAFFH8FAAIHAAMJ6wnlEgCCAAAHAAMJ6wnlEgCCAAAuAAQKfxoAAgcABwnvHdwUACACAAcABwnvHdwUACACAAAA.',
Hi='Hiyabusa:BAABLgAECn8UAAIeAAcJ4BBDLQCWAQAeAAcJ4BBDLQCWAQAAAA==.',
Ho='Hollowboi:BAABLgAECn88AAIIAAkJMiK4AwAMAwAIAAkJMiK4AwAMAwAAAA==.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Il='Illgaz:BAAALgAECgEJAQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8gAAMSAAcJURXcHwDSAQASAAYJURXcHwDSAQAfAAEJAAA4FQBGAAAuAAQKfx8AAhIACQm9IK0RABIDABIACQm9IK0RABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8KAAITAAQJmhldIQAKAQATAAQJmhldIQAKAQAuAAQKfxwAAhMACAloJtwJANQCABMACAloJtwJANQCAAAA.',
Jy='Jyggles:BAABLgAECn8aAAIfAAgJrAHqOwCXAAAfAAgJrAHqOwCXAAAAAA==.',
Ka='Kavdh:BAACLgAFFH8GAAIXAAMJvQ8iXQDHAAAXAAMJvQ8iXQDHAAAuAAQKfxwAAhcABwlrIsEcAF8CABcABwlrIsEcAF8CAAAA.',
Ke='Kenpachip:BAAALgAECgUJBQAAAA==.Keyaesh:BAAALgADCgcJCgAAAA==.',
Ki='Kirax:BAAALgAECgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgAWALwkAA==.',
Ks='Kshot:BAABLgAECn89AAIPAAkJmR8BBgC/AgAPAAkJmR8BBgC/AgAAAA==.',
La='Lagdalen:BAABLgAECn8aAAIYAAYJExxjHQDOAQAYAAYJExxjHQDOAQAAAA==.Lanachan:BAABLgAECn9EAAIcAAkJ+xeEEQBjAgAcAAkJ+xeEEQBjAgAAAA==.',
Ld='Ldn:BAABLgAECn9AAAINAAkJtRI7RwAAAgANAAkJtRI7RwAAAgAAAA==.',
Le='Lep:BAAALgAECgUJBQAAAA==.',
Li='Lightofdawn:BAAALgAECgEJAQAAAA==.Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8wAAIQAAkJQAlwWgCLAQAQAAkJQAlwWgCLAQAAAA==.',
Ly='Lylieth:BAABLgAECn87AAILAAkJyBOxOwDmAQALAAkJyBOxOwDmAQAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.Miriko:BAAALgADCgkJCQAAAA==.',
Mo='Mock:BAACLgAFFH8GAAICAAMJ9AADVABtAAACAAMJ9AADVABtAAAuAAQKfxgAAgIACAl+CuY6ADQBAAIACAl+CuY6ADQBAAEuAAQKBwkhABkALQ0A.Mogera:BAAALgADCgMJBQAAAA==.Mouthyhusky:BAAALgAFFAIJAgAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCwAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.Omey:BAAALgAECgEJAwAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Or='Oraine:BAAALgAECgUJBQAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn81AAMTAAkJWiFHDwCaAgATAAkJWiFHDwCaAgAGAAUJHRtYngAvAQAAAA==.',
Po='Poppachàdson:BAABLgAECn8dAAIgAAcJ+CDTCABPAgAgAAcJ+CDTCABPAgABLgAFFAMJBgAgABoVAA==.Poppadadson:BAACLgAFFH8GAAIgAAMJGhWSDQDTAAAgAAMJGhWSDQDTAAAuAAQKfxwAAiAABwmBH4kGAI0CACAABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAgABoVAA==.',
Pr='Priceless:BAAALgADCgYJBgAAAA==.',
Pu='Puscifer:BAAALgAECgkJCQAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.Quincar:BAAALgADCgEJAQABLgAECgMJCgAMAAAAAA==.',
Ra='Rafayel:BAAALgADCgMJAwAAAA==.Raizel:BAAALgADCgUJCAABLgAECgkJQgAUANcbAA==.Ravister:BAAALgAECgUJBQABLgAFFAcJHgAaAIIiAA==.',
Re='Relic:BAACLgAFFH8dAAQhAAYJHBScBQB7AQAhAAUJ0BOcBQB7AQASAAEJnBHW/ABDAAAfAAIJxQsBPQAqAAAuAAQKfykAAyEACQmEHZMCAIwCACEACQmEHZMCAIwCABIABgmbF8V9AGABAAAA.Renk:BAABLgAECn8vAAISAAkJACZpBABZAwASAAkJACZpBABZAwAAAA==.Renka:BAAALgAECgUJBQABLgAECgkJLwASAAAmAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrhlgBPAQAGAAYJZRrhlgBPAQAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJIAAZAB0KAA==.Saihu:BAAALgADCgEJAQAAAA==.Sammie:BAEALgAECgUJCAABLgAECgcJEAAMAAAAAA==.Sarromand:BAAALgAECgUJBQABLgAECgkJPAAIADIiAA==.Savant:BAAALgAECgMJAwAAAA==.Sayl:BAABLgAECn8gAAMZAAkJHQqnMwA+AQAZAAgJjAmnMwA+AQAaAAUJMwi9VAC1AAAAAA==.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMLAAkJ4hqLPgATAgALAAgJcBqLPgATAgAbAAQJeRTgKwAQAQAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAABLgAECn8WAAIaAAgJbwoLMwBGAQAaAAgJbwoLMwBGAQAAAA==.Shadowydern:BAABLgAECn8oAAMaAAkJlSAtCQC3AgAaAAkJlSAtCQC3AgAYAAEJ/RBpfwAzAAAAAA==.Shamewow:BAACLgAFFH8ZAAIWAAYJJRkoFwCTAQAWAAYJJRkoFwCTAQAuAAQKfzMAAhYACQlIHGkVAJQCABYACQlIHGkVAJQCAAAA.Sharkbite:BAAALgAECgQJBwAAAA==.Shrimpboat:BAAALgAECgYJBQAAAA==.',
Si='Sicknnasty:BAACLgAFFH8aAAIfAAYJbRVwDwBvAQAfAAYJbRVwDwBvAQAuAAQKf0gAAx8ACQnOITEHAKECAB8ACQnOITEHAKECABIACAlRFv1UAL8BAAAA.Sicsickly:BAAALgAFFAEJAQAAAA==.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAABLgAECn8hAAMZAAcJLQ3aLABmAQAZAAcJLQ3aLABmAQAaAAcJXwcBQgAAAQAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAABLgAECn8fAAISAAgJuxqeLQBCAgASAAgJuxqeLQBCAgAAAA==.',
Sp='Sparkyboo:BAAALgAECgEJAQAAAA==.Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQABLgAECgYJBQAMAAAAAA==.',
St='Starshopping:BAABLgAECn8UAAIXAAgJmiFlFQDWAgAXAAgJmiFlFQDWAgABLgAECgkJSgAPAG4lAA==.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgAFFAQJBAABLgAFFAgJKwAIABYiAA==.Talrip:BAABLgAECn8eAAIiAAkJVR3YBgAgAgAiAAkJVR3YBgAgAgAAAA==.Taxiplease:BAAALgAECggJBwAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thornhub:BAAALgAECgUJBQAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgYJCwAAAA==.Toro:BAACLgAFFH8fAAIcAAcJbh38BAABAgAcAAcJbh38BAABAgAuAAQKfysAAhwACQl3JGUFAFADABwACQl3JGUFAFADAAAA.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgAFFAIJAgAAAA==.Tree:BAACLgAFFH8PAAIUAAQJBiQrFgCiAQAUAAQJBiQrFgCiAQAuAAQKfxYAAhQABgmZI1geAEwCABQABgmZI1geAEwCAAAA.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIIAAYJWSANIAABAgAIAAYJWSANIAABAgAAAA==.',
Tz='Tzungxie:BAABLgAECn8tAAIeAAkJWR3dDABNAgAeAAkJWR3dDABNAgAAAA==.',
Un='Unholylord:BAACLgAFFH8eAAIaAAcJgiJkAwBJAgAaAAcJgiJkAwBJAgAuAAQKfyIAAhoACQmtI8oEAEcDABoACQmtI8oEAEcDAAAA.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgAECgkJEgABLgAFFAcJHgAaAIIiAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn83AAIBAAgJMgtIKAAkAQABAAgJMgtIKAAkAQAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAgAMAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAACLgAFFH8LAAMDAAQJ0BP1BAAVAQADAAQJkQ/1BAAVAQACAAMJIA0mQAC4AAAuAAQKf0YABAMACQmbHkwCAJkCAAMACQmbHkwCAJkCAAIACAmMFRwdAN4BAAQAAQkbAfNOACAAAAAA.',
Za='Zaptik:BAAALgAECgEJAgAAAA==.',
['Ël']='Ëlëmëntary:BAAALgAECgcJBgAAAA==.',
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
