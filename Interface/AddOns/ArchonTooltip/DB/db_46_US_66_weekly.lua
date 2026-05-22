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

local lookup = {'DemonHunter-Devourer','Warrior-Protection','Paladin-Protection','Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Assassination','Warrior-Fury','Paladin-Retribution','Hunter-Marksmanship','Warrior-Arms','Priest-Shadow','Priest-Discipline','Priest-Holy','Paladin-Holy','Monk-Mistweaver','Druid-Restoration','Druid-Feral','Druid-Guardian','Hunter-Survival','Monk-Brewmaster','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Rogue-Subtlety','Mage-Fire','DeathKnight-Frost',}
local provider = {region='US',realm='Dentarg',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abaddôn:BAAALgAECgYJCwAAAA==.Abelard:BAAALgAECgUJCwAAAA==.',
Ad='Adevourer:BAAALgADCgEJAQAAAA==.',
Ae='Aeeguariar:BAAALgADCgIJAgAAAA==.Aenlorie:BAAALgADCgMJAwABLgAFFAgJDgABAD4LAA==.Aezyndreth:BAAALgADCgQJBQAAAA==.',
Af='Aflickted:BAAALgAECggJDgAAAA==.',
Ag='Agesilaus:BAAALgAECgEJAQAAAA==.Agesipolis:BAAALgADCgYJEQAAAA==.Aggathon:BAEBLgAECn8jAAICAAgJpBA2EgB1AQACAAgJpBA2EgB1AQAAAA==.',
Ai='Aittuu:BAAALgADCgkJEAABLgAECgkJJwADAEkkAA==.',
Ak='Akusai:BAAALgAECgMJAwABLgAECgcJGQAEALQIAA==.',
Al='Aldebaran:BAAALgAECggJCAAAAA==.Aleksandar:BAAALgAECgMJAwAAAA==.',
Am='Amage:BAAALgADCgcJDgAAAA==.Amonk:BAAALgADCgIJAgAAAA==.',
An='Ansur:BAAALgAECgIJAgAAAA==.',
Ap='Apocâlypsè:BAAALgAECgkJBQAAAA==.',
Ar='Aradoria:BAAALgAECgMJAwAAAA==.Arlonar:BAAALgADCgIJAgABLgADCgQJBQAFAAAAAA==.Arohgue:BAAALgADCgIJAgAAAA==.',
As='Asenturius:BAAALgADCgUJBQAAAA==.Ashke:BAABLgAECn8gAAIGAAgJdRZ0KwDeAQAGAAgJdRZ0KwDeAQAAAA==.',
Av='Avarice:BAAALgAECgEJAQABLgAECgkJKQAHAI8WAA==.',
Ax='Axetoface:BAAALgADCgYJCAAAAA==.Axetomouth:BAAALgAECgEJAQAAAA==.',
Az='Azraeon:BAAALgAECgYJEwAAAA==.Azurehorn:BAAALgADCgYJBgABLgAECggJDgAFAAAAAA==.',
Ba='Badlucklouie:BAAALgAECgYJEAAAAA==.Badpenny:BAAALgADCgYJCwAAAA==.Bajenkas:BAAALgAECgUJCwAAAA==.Balfas:BAAALgADCgcJDAAAAA==.',
Be='Beaupeep:BAABLgAECn8ZAAIEAAcJtAiCEwAEAQAEAAcJtAiCEwAEAQAAAA==.Beepbop:BAAALgAECgEJBAAAAA==.Benedictine:BAABLgAECn8aAAIIAAkJ0hmeDAAuAgAIAAkJ0hmeDAAuAgAAAA==.',
Bi='Bigrick:BAAALgADCgYJBgAAAA==.',
Bl='Bloodstyx:BAAALgAECgQJBAABLgAECggJJwAJADweAA==.',
Bo='Boogieman:BAAALgADCgIJBAAAAA==.Boyacky:BAAALgADCgMJAwAAAA==.',
Br='Braiglock:BAAALgAECgYJCwAAAA==.Brambletime:BAAALgADCgQJBAAAAA==.Brigit:BAAALgAECgIJAgAAAA==.',
Bu='Buudha:BAAALgADCgEJAQAAAA==.',
By='Bygz:BAAALgAFFAIJBAABLgAFFAcJFwAKAMMiAA==.',
['Bä']='Bärnowl:BAAALgAECgQJBAAAAA==.',
Ca='Caarjack:BAACLgAFFH8OAAQLAAQJ2g+eBADkAAAMAAQJJgtcIAAOAQALAAMJkQyeBADkAAANAAEJrBNYHwBKAAAuAAQKfygABA0ACAl5FpkUAP4BAA0ACAl5FpkUAP4BAAwABAk2HGYtACwBAAsAAgn0DtkUAHMAAAAA.Caicedo:BAAALgAECgcJCQAAAA==.Callmehoney:BAAALgAECgEJAQAAAA==.Callmemeg:BAAALgAECgYJCQAAAA==.Catadelic:BAABLgAECn8rAAIGAAgJ5AqBTQBfAQAGAAgJ5AqBTQBfAQAAAA==.',
Ce='Celektra:BAAALgAECgYJCgAAAA==.Celestial:BAABLgAECn8dAAQOAAkJGBC/HwBUAQAOAAgJLQ6/HwBUAQAPAAUJog6wEADgAAAQAAEJWwRaEAEoAAAAAA==.',
Ch='Chewmatter:BAABLgAECn8nAAMBAAkJiSEqCADaAgABAAkJiSEqCADaAgARAAEJAADhWgAAAAAAAA==.Chewwbacca:BAAALgAECgUJBQAAAA==.Chronoclear:BAAALgADCgYJBgAAAA==.Chud:BAAALgADCggJCAAAAA==.Chuwy:BAAALgAECgcJBwAAAA==.Chyse:BAAALgAECgEJAQAAAA==.',
Ci='Cindroz:BAAALgAECgYJCgAAAA==.',
Cl='Claus:BAAALgADCgQJBQAAAA==.Cleanname:BAABLgAECn8bAAMSAAkJ8hsWAwBsAgASAAkJ8hsWAwBsAgABAAUJTA9rgwDFAAAAAA==.Clurichaun:BAABLgAECn8lAAITAAcJawfEDAAbAQATAAcJawfEDAAbAQAAAA==.',
Cr='Crak:BAAALgADCgUJCgAAAA==.Crusade:BAAALgADCggJCAAAAA==.Crùros:BAAALgAECgYJCwAAAA==.',
Cu='Cucuchara:BAABLgAECn8UAAMUAAYJzBT+TwCzAAAUAAQJQBP+TwCzAAACAAIJ+xovOACIAAAAAA==.',
Da='Daemonna:BAAALgAECgYJBgAAAA==.Darkestdude:BAAALgADCgMJAwAAAA==.',
De='Deathdab:BAAALgADCgEJAQAAAA==.Deathphish:BAABLgAECn8kAAIJAAgJ+xYrEACyAQAJAAgJ+xYrEACyAQAAAA==.Demonish:BAAALgAECgIJBAAAAA==.Denntarg:BAAALgAECgQJBwABLgAECgkJKwAVAPYgAA==.Desdemona:BAABLgAECn8ZAAIWAAYJbhAkEgD0AAAWAAYJbhAkEgD0AAAAAA==.Deshler:BAABLgAECn8XAAMCAAcJcQuxHgDvAAACAAYJhQ2xHgDvAAAUAAcJVwSlVAChAAAAAA==.',
Di='Dice:BAAALgADCgIJAgAAAA==.Dirtyblonde:BAAALgAECgYJDgAAAA==.Ditlutz:BAABLgAECn8nAAIDAAkJSSTTAAAuAwADAAkJSSTTAAAuAwAAAA==.',
Dj='Djskyfallx:BAABLgAECn8UAAIHAAcJoxy9dADpAQAHAAcJoxy9dADpAQAAAA==.',
Do='Dom:BAACLgAFFH8SAAMUAAUJcxdBEwAyAQAUAAUJcxdBEwAyAQAXAAIJaQQMDQBMAAAuAAQKfyAAAhQACAnwH/EYAIQCABQACAnwH/EYAIQCAAAA.Doraf:BAAALgADCgcJDQAAAA==.Dormammu:BAAALgAECgEJAgAAAA==.',
Dr='Druken:BAAALgAECgQJCwAAAA==.Drûid:BAAALgADCgEJAQAAAA==.',
Du='Dumbledore:BAAALgAECgEJAQAAAA==.',
Dw='Dwarfussy:BAABLgAECn8XAAICAAcJshQBFgCuAQACAAcJshQBFgCuAQAAAA==.',
Dy='Dybby:BAABLgAECn8UAAIHAAgJURZ7QwDPAQAHAAgJURZ7QwDPAQAAAA==.',
El='Elderoth:BAAALgAECgUJCwAAAA==.Eledork:BAAALgADCgMJAwAAAA==.Elrondus:BAAALgAECggJDAAAAA==.',
Em='Emridion:BAAALgAECgYJDwAAAA==.',
En='Endlessnight:BAABLgAECn8nAAIJAAgJPB5rCABEAgAJAAgJPB5rCABEAgAAAA==.',
Ey='Eyeinfection:BAAALgADCgIJBAAAAA==.',
['Eä']='Eärendil:BAAALgADCgUJBQAAAA==.',
Fa='Faearia:BAACLgAFFH8HAAIYAAUJBw3QEAAyAQAYAAUJBw3QEAAyAQAuAAQKfyAAAhgACQmnG+gMALUCABgACQmnG+gMALUCAAAA.Faebryn:BAABLgAECn8nAAIUAAkJsSNcAwACAwAUAAkJsSNcAwACAwAAAA==.Faenza:BAAALgADCgkJEAAAAA==.',
Fe='Felbourne:BAAALgAECgUJDAAAAA==.Felmaiden:BAAALgADCgQJBQAAAA==.Fenirean:BAAALgAECgYJCgAAAA==.Fettylock:BAAALgAECgEJBAAAAA==.',
Fi='Fintaylor:BAAALgAECgcJBwAAAA==.',
Fl='Flirts:BAAALgAECgMJBAAAAA==.',
Fo='Foodstamp:BAAALgAECgMJAwAAAA==.Forcas:BAABLgAECn8mAAMRAAcJTBsPEQCyAQARAAcJBRoPEQCyAQASAAMJPx2SFwDmAAAAAA==.Fox:BAAALgADCgcJBwABLgAECggJDgAFAAAAAA==.',
Fr='Frijõle:BAAALgAECgQJBAAAAA==.',
Fu='Furysmite:BAAALgADCgYJCgAAAA==.Fuzebox:BAAALgAECgcJEQAAAA==.',
Ga='Gallifrey:BAABLgAECn8pAAIHAAkJjxa2LAAkAgAHAAkJjxa2LAAkAgAAAA==.Gamarrick:BAABLgAECn8oAAIYAAgJKRGIHwB0AQAYAAgJKRGIHwB0AQAAAA==.Ganyin:BAAALgAECgUJBQAAAA==.Gaul:BAAALgAECgEJAgAAAA==.',
Ge='Germain:BAAALgAECgcJDwAAAA==.',
Gi='Gimick:BAAALgAECgEJAQAAAA==.',
Gn='Gneissbark:BAAALgADCgYJBgAAAA==.Gnomeminator:BAAALgADCgYJBgABLgAECgYJFgADAL8aAA==.Gnometzu:BAABLgAECn8vAAIIAAkJ8xakCwA9AgAIAAkJ8xakCwA9AgAAAA==.',
Go='Golddicmove:BAAALgAECgQJCwAAAA==.Goth:BAAALgAECggJDQAAAA==.Gothicc:BAAALgAECgMJAwAAAA==.',
Gr='Greeva:BAAALgADCgcJCAAAAA==.Griever:BAEBLgAECn8YAAQOAAYJMRvbGQCcAAAQAAUJgxmQdQASAQAOAAMJMhzbGQCcAAAPAAEJRhV8IwA9AAAAAA==.Grimdrood:BAAALgADCgYJBgAAAA==.',
Gu='Guilladot:BAABLgAECn8bAAIQAAcJkBRQcAAeAQAQAAcJkBRQcAAeAQAAAA==.Guillak:BAABLgAECn8mAAMQAAcJqhIiZQA2AQAQAAUJBRQiZQA2AQAOAAUJ5g9pMgDuAAAAAA==.Gurdbi:BAAALgAECgEJAgAAAA==.',
Gw='Gwonam:BAAALgADCgUJBQABLgAECgEJAQAFAAAAAA==.',
Ha='Harafar:BAAALgAECgcJEAAAAA==.Harmonic:BAAALgADCgkJEQABLgADCgkJEAAFAAAAAA==.Harxx:BAAALgADCgMJAwAAAA==.Hatka:BAAALgAECgYJCQAAAA==.',
He='Healingtide:BAAALgADCgEJAQABLgAECgYJCwAFAAAAAA==.Healtards:BAABLgAECn8aAAMZAAkJagppGAC2AQAZAAkJagppGAC2AQAaAAYJLgLbVwDWAAAAAA==.Hematose:BAAALgADCgQJBAABLgAECgUJCwAFAAAAAA==.Hetdtyaiqing:BAAALgAECgEJAQAAAA==.',
Hi='Hitmonleë:BAAALgAECgIJAgABLgAECgYJDgAFAAAAAA==.',
Ho='Holyfyer:BAAALgAECgMJAwAAAA==.Holyshift:BAABLgAECn8bAAIbAAgJ8RpzGABPAgAbAAgJ8RpzGABPAgAAAA==.Homgal:BAAALgAECgYJDAAAAA==.Hoofingit:BAAALgAECgQJBAAAAA==.',
Hu='Hullstorm:BAAALgADCgcJCgAAAA==.Hume:BAAALgAECgMJAgAAAA==.',
Ib='Ibull:BAAALgADCgEJAQAAAA==.',
Ic='Icyifu:BAABLgAECn8VAAIcAAgJIx4VCgCVAgAcAAgJIx4VCgCVAgAAAA==.',
If='Iffy:BAAALgAECggJDgAAAA==.',
Ih='Ihys:BAAALgADCgEJAQAAAA==.',
Il='Ilian:BAABLgAECn8WAAIIAAkJpRrMCQBeAgAIAAkJpRrMCQBeAgAAAA==.',
In='Ingward:BAAALgAECgEJAQAAAA==.Iniquity:BAABLgAECn8qAAMaAAkJvxZeFwDKAQAaAAkJvxZeFwDKAQAYAAUJExmMNgDmAAAAAA==.',
Ja='Jabiso:BAAALgAECgEJAgAAAA==.Jackthebeast:BAABLgAFFH8OAAMGAAMJdCFRJwAgAQAGAAMJdCFRJwAgAQAWAAEJKAXGKwBDAAAAAA==.Jaida:BAABLgAECn8fAAIBAAkJpw0OcQBRAQABAAkJpw0OcQBRAQAAAA==.Jamesxd:BAAALgAECgMJAwABLgAECggJHAAdAKogAA==.Jang:BAAALgADCgcJBwAAAA==.',
Jd='Jdmagisdruid:BAABLgAECn8nAAMeAAkJ2iVYAABsAwAeAAkJ2iVYAABsAwAfAAEJ5yOQKQBUAAAAAA==.Jdmagisrogue:BAAALgADCgMJAwABLgAECgkJJwAeANolAA==.',
Je='Jeanne:BAABLgAECn8dAAMYAAcJ5AYWNgDoAAAYAAcJ5AYWNgDoAAAaAAYJ7wUdPQCxAAAAAA==.Jedoniah:BAABLgAECn8nAAIVAAkJ6yTJAwA4AwAVAAkJ6yTJAwA4AwAAAA==.Jeffrey:BAAALgAECgMJBgAAAA==.Jenkers:BAAALgAECgUJBQAAAA==.',
Jo='Jorhmont:BAAALgAECggJDgAAAA==.Jowyy:BAAALgADCgEJAQAAAA==.',
Ju='Juan:BAABLgAECn8dAAIdAAYJkxTBOgBiAQAdAAYJkxTBOgBiAQAAAA==.Jumbo:BAABLgAECn8lAAIUAAgJsRxsEgAWAgAUAAgJsRxsEgAWAgAAAA==.Jumpeor:BAACLgAFFH8WAAIVAAYJQCGkBQDeAQAVAAYJQCGkBQDeAQAuAAQKfyAAAhUACQmmJugDAJADABUACQmmJugDAJADAAAA.',
Ka='Kael:BAAALgAECgQJBAAAAA==.Kalorlan:BAAALgAECgEJAQAAAA==.Kassey:BAAALgADCgYJCwAAAA==.Katacola:BAACLgAFFH8oAAIdAAgJXR0zAQDIAgAdAAgJXR0zAQDIAgAuAAQKfy0AAh0ACQlvJssCAGoDAB0ACQlvJssCAGoDAAAA.Kathloken:BAAALgADCgYJCQAAAA==.',
Ke='Kenaf:BAAALgADCgEJAwAAAA==.Kevesebal:BAABLgAECn8eAAMQAAkJWyJcBQBmAwAQAAkJWyJcBQBmAwAOAAEJAABIcAA2AAABLgAECgkJHQAEAG0kAA==.',
Kh='Khronic:BAABLgAECn8YAAQNAAYJzRpSDQCxAQANAAYJzRpSDQCxAQALAAMJuQc0FAB8AAAMAAIJeQmhYQBUAAAAAA==.',
Ki='Kikiliki:BAAALgAECggJEwAAAA==.Kilthgar:BAABLgAECn8mAAIDAAkJZhlABgA0AgADAAkJZhlABgA0AgAAAA==.Kirkinius:BAAALgADCgEJAQAAAA==.',
Ko='Koa:BAABLgAECn8ZAAIdAAgJwhTKOwBdAQAdAAgJwhTKOwBdAQAAAA==.Kobeni:BAAALgAECgYJEAAAAA==.Kodiak:BAAALgAECgYJDAAAAA==.Kolar:BAAALgAECgcJEgAAAA==.Koravellia:BAAALgAECgEJBQAAAA==.Kord:BAAALgADCgcJDgAAAA==.',
Kr='Kraph:BAAALgAECgIJAwAAAA==.Krillin:BAAALgAECgcJEgAAAA==.',
Ku='Kurau:BAABLgAECn8ZAAIgAAcJbAz7HwBMAQAgAAcJbAz7HwBMAQAAAA==.',
Ky='Kyrinra:BAAALgAECgQJBAAAAA==.',
La='Lacie:BAABLgAECn8WAAIGAAYJrA3PawANAQAGAAYJrA3PawANAQAAAA==.Lamarvelous:BAAALgAECgQJBwAAAA==.',
Le='Leela:BAAALgADCgMJAwABLgAECggJHgAHADINAA==.',
Li='Littletoot:BAAALgADCgUJBwAAAA==.',
Lo='Lockybleier:BAAALgADCgYJDAAAAA==.Logìc:BAAALgADCgIJAgAAAA==.Lokiel:BAABLgAECn8mAAIbAAgJxxYPGAD6AQAbAAgJxxYPGAD6AQAAAA==.Lonescyther:BAAALgADCgMJAwAAAA==.Lorithen:BAAALgAECgQJBAABLgAFFAQJBQAhAPAgAA==.',
Lu='Lunula:BAABLgAECn8yAAIfAAkJjhmUBQBVAgAfAAkJjhmUBQBVAgAAAA==.Luxörd:BAABLgAECn8oAAIbAAgJmySHBAAUAwAbAAgJmySHBAAUAwAAAA==.',
Ly='Lyaenna:BAABLgAECn8bAAMaAAgJ8RQeFwDMAQAaAAgJ8RQeFwDMAQAYAAcJYQSSOgDTAAAAAA==.Lydius:BAABLgAECn8rAAIdAAgJsRBvNQB9AQAdAAgJsRBvNQB9AQAAAA==.Lymn:BAAALgADCgQJBAAAAA==.',
Ma='Macguffins:BAAALgAECgQJBAAAAA==.Maddex:BAAALgAECgMJBAAAAA==.Madeng:BAAALgAECgUJCwABLgAECgYJDAAFAAAAAA==.Mageshir:BAABLgAECn8bAAMHAAgJmQ/+WgCMAQAHAAgJUw/+WgCMAQAiAAEJ8wplDwA5AAAAAA==.Maletherion:BAABLgAECn8dAAIWAAcJlyDPBgDcAQAWAAcJlyDPBgDcAQAAAA==.Malhoon:BAAALgADCgQJBAAAAA==.Maltherion:BAABLgAECn8hAAIRAAgJvR5ADQDvAQARAAgJvR5ADQDvAQAAAA==.Maolestromz:BAAALgAECgcJAwAAAA==.Margareetah:BAAALgAECgQJCAAAAA==.Marisal:BAAALgAECgQJBAAAAA==.Mayaeyes:BAAALgAFFAIJAwABLgAFFAcJFwAKAMMiAA==.',
Me='Merily:BAAALgADCgIJAgAAAA==.',
Mi='Mikokahuna:BAAALgAECgUJCQAAAA==.Minglo:BAAALgAECgUJCAAAAA==.Minireaper:BAAALgAFFAIJAgAAAA==.Mistaeko:BAAALgADCgMJAwAAAA==.',
Mj='Mjolnir:BAABLgAECn8nAAIVAAkJsSADDADQAgAVAAkJsSADDADQAgAAAA==.',
Mo='Moggren:BAAALgAECggJDgAAAA==.Moirbidia:BAAALgADCgcJCgAAAA==.Mongke:BAAALgADCgYJBwAAAA==.',
['Mî']='Mîsh:BAAALgAECgQJBAAAAA==.',
Na='Namôr:BAAALgADCgYJCwAAAA==.Narzel:BAAALgAECgUJEgAAAA==.Nazgul:BAAALgAFFAIJAgAAAA==.',
Ne='Necronias:BAAALgAECgYJEAAAAA==.Nehen:BAAALgAECgIJAgABLgAECggJHgAHACMXAA==.Nelelish:BAAALgAECgEJAQAAAA==.Nequins:BAABLgAECn8mAAIdAAgJ1h5ADwCYAgAdAAgJ1h5ADwCYAgAAAA==.Nequinss:BAABLgAECn8kAAIjAAgJmiPwBAAeAwAjAAgJmiPwBAAeAwABLgAECggJJgAdANYeAA==.Nesteä:BAAALgAECgEJAQABLgAECgYJDgAFAAAAAA==.Nevermore:BAAALgAECgUJBwAAAA==.',
Ni='Nicabar:BAABLgAECn8zAAIQAAkJGwxvPgCjAQAQAAkJGwxvPgCjAQAAAA==.Nitemare:BAAALgADCgcJCAAAAA==.',
No='Noaman:BAAALgAECgEJAwAAAA==.Noapandman:BAAALgAECgEJAQAAAA==.Noie:BAAALgAECgMJBgAAAA==.Nooamann:BAAALgADCgEJAQAAAA==.Noodles:BAAALgAECgYJDAAAAA==.Normademon:BAAALgAECgEJAQAAAA==.Noztalgia:BAAALgAECggJEgAAAA==.',
Nt='Nthx:BAAALgADCgMJAwAAAA==.',
Nu='Nullbringer:BAAALgADCgYJBgAAAA==.',
Nx='Nxttuesday:BAAALgADCgUJBQAAAA==.',
['Nå']='Nåndo:BAAALgAECgEJAQAAAA==.',
['Në']='Nëklaüs:BAABLgAECn8XAAMJAAYJihKnHgAKAQAJAAYJihKnHgAKAQAKAAEJpQj7HQE5AAAAAA==.',
Oa='Oakily:BAABLgAECn8WAAIdAAYJ9Qk1cgD/AAAdAAYJ9Qk1cgD/AAAAAA==.',
Od='Oditte:BAAALgADCgYJBgAAAA==.',
Oi='Oilliphéist:BAAALgAECgQJCgAAAA==.',
Om='Omegatanker:BAACLgAFFH8FAAIhAAQJ8CD4CgB4AQAhAAQJ8CD4CgB4AQAuAAQKfzAAAyEACQkTJqYAAGUDACEACQkTJqYAAGUDAAgAAQmiBip6ACsAAAAA.',
Or='Ornot:BAACLgAFFH8FAAIjAAMJUQOZNwCjAAAjAAMJUQOZNwCjAAAuAAQKfxkAAiMACAlNDh8/AIQBACMACAlNDh8/AIQBAAAA.',
Os='Oshdruid:BAABLgAECn8cAAMdAAgJqiAJFgBQAgAdAAgJqiAJFgBQAgAfAAMJkSKQIADFAAAAAA==.',
Ow='Owo:BAAALgADCgYJDAAAAA==.',
Pa='Pacfritanda:BAAALgADCgQJBAAAAA==.Pandurbear:BAAALgADCgYJCwAAAA==.Paws:BAAALgAECgEJAQAAAA==.',
Pe='Pequin:BAAALgAECgYJBgABLgAECggJJgAdANYeAA==.Pergatory:BAABLgAECn8gAAIYAAYJnQsIMwD5AAAYAAYJnQsIMwD5AAAAAA==.',
Ph='Phanie:BAAALgADCgYJCAAAAA==.Pho:BAAALgAFFAIJAgAAAA==.Phuule:BAAALgADCgQJCQAAAA==.Phuulmojo:BAAALgADCgIJAgAAAA==.',
Pi='Piruletras:BAABLgAECn8WAAIGAAcJ5QyUWAA+AQAGAAcJ5QyUWAA+AQAAAA==.',
Pr='Priechwhirl:BAABLgAECn8sAAIXAAkJnR2IAgDRAgAXAAkJnR2IAgDRAgAAAA==.Provost:BAABLgAECn8jAAIVAAgJFiPWEwCQAgAVAAgJFiPWEwCQAgAAAA==.',
Pu='Pumpkinpîe:BAAALgAECgUJCAAAAA==.',
Qu='Quanx:BAACLgAFFH8FAAIkAAMJdASDJAC2AAAkAAMJdASDJAC2AAAuAAQKfxcAAyQACQknF9IUAO8BACQACQm1FdIUAO8BAAQABglnFicSAJQBAAAA.',
Ra='Radiantmist:BAAALgADCgMJAwABLgAECgYJCwAFAAAAAA==.Rakiko:BAAALgAFFAIJAwABLgAFFAcJFwAKAMMiAA==.Ratacola:BAAALgAECgEJAQAAAA==.Raydora:BAAALgADCgQJBwAAAA==.',
Re='Rednecklock:BAAALgADCgEJAQAAAA==.Remulüs:BAABLgAECn8lAAQBAAgJVh/RFABbAgABAAgJVh/RFABbAgASAAMJ3AMXHQBgAAARAAEJAADEbwA1AAAAAA==.',
Ri='Riah:BAAALgADCgkJCQAAAA==.Rickyböbby:BAAALgADCgQJBQAAAA==.Riilyn:BAABLgAECn8vAAIlAAgJoxzxDgDsAQAlAAgJoxzxDgDsAQAAAA==.Riolu:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.',
Ru='Ruith:BAAALgAECgUJCQAAAA==.',
['Rø']='Røean:BAAALgAECgYJCAAAAA==.',
Sa='Saina:BAAALgAECgEJAQAAAA==.Satanshelpa:BAAALgADCgUJBQAAAA==.',
Sb='Sb:BAAALgADCgUJBQAAAA==.',
Sc='Scalebeard:BAABLgAECn8cAAQNAAkJ4wlmFQAoAQANAAkJ4wlmFQAoAQALAAUJvxlDDwDQAAAMAAEJ7AxNYwAwAAAAAA==.Scecretzs:BAAALgAECgYJCQAAAA==.Screnry:BAAALgAECgEJAQAAAA==.',
Se='Secretz:BAAALgADCgYJCgAAAA==.Sedrelari:BAABLgAECn8bAAIgAAYJih8LDQD7AQAgAAYJih8LDQD7AQAAAA==.Seizethesol:BAAALgADCgIJAgAAAA==.Sepsis:BAAALgAECgYJEAAAAA==.Sesamo:BAACLgAFFH8VAAIVAAYJpBMWEACAAQAVAAYJpBMWEACAAQAuAAQKfzAAAhUACQluJOAEACMDABUACQluJOAEACMDAAAA.',
Sh='Shocks:BAAALgAECgEJAgAAAA==.Shroomin:BAABLgAECn8bAAIkAAcJtyGFGwCwAQAkAAcJtyGFGwCwAQAAAA==.',
Si='Sixseven:BAAALgADCgkJGQAAAA==.',
Sk='Skass:BAAALgADCgcJEAAAAA==.',
Sl='Slok:BAAALgADCgcJCwAAAA==.Slyndara:BAABLgAECn8UAAMSAAcJ+QWiFQCtAAASAAYJggaiFQCtAAABAAEJTQNU7AAfAAAAAA==.',
Sm='Smarthen:BAABLgAECn8eAAQHAAgJIxe6QwDOAQAHAAgJIxe6QwDOAQAmAAIJJwFaEAAzAAAiAAEJPgERIwANAAAAAA==.Smolhatka:BAAALgAECgEJAQABLgAECgYJCQAFAAAAAA==.',
Sn='Sniffums:BAABLgAECn8aAAIgAAkJEhBeEADpAQAgAAkJEhBeEADpAQAAAA==.',
So='Sokto:BAAALgAECgUJCAAAAA==.Solarian:BAABLgAECn8mAAIBAAcJ5xE6VQA1AQABAAcJ5xE6VQA1AQAAAA==.Soule:BAAALgADCgkJKwAAAA==.',
Sp='Spacewalrus:BAAALgADCgIJAgABLgAECggJKAAbAJskAA==.',
Sq='Squirtlë:BAAALgADCgcJBwABLgAECgYJDgAFAAAAAA==.',
St='Startle:BAAALgADCggJIgAAAA==.Steelbreeze:BAAALgAECgQJCwAAAA==.Stoutbringer:BAAALgAECgIJAgAAAA==.Størmzkurse:BAAALgAECgEJAQAAAA==.',
Sy='Sylvaedir:BAAALgADCgcJBgAAAA==.Systran:BAAALgADCgYJBwAAAA==.',
Ta='Tailrazen:BAAALgAECgYJDQAAAA==.Talyn:BAABLgAECn8eAAIHAAgJMg2vYwB2AQAHAAgJMg2vYwB2AQAAAA==.Taomi:BAABLgAECn8nAAIjAAkJKhZdFwA7AgAjAAkJKhZdFwA7AgAAAA==.Taylorswift:BAAALgAECgkJDgAAAA==.',
Te='Tengri:BAAALgAECgIJBgAAAA==.Tenspeed:BAABLgAECn8iAAIBAAgJHhb8MQC0AQABAAgJHhb8MQC0AQAAAA==.',
Th='Thanâtos:BAAALgADCgkJCQABLgAECgYJFgADAL8aAA==.Thire:BAAALgAECgYJEAAAAA==.Thisrogue:BAAALgAECgEJAQAAAA==.Throwglaive:BAAALgAECgQJBAABLgAFFAcJFwAKAMMiAA==.',
Ti='Tidereign:BAAALgAECgcJEAAAAA==.Timka:BAABLgAECn8ZAAIdAAYJrgtZWgDjAAAdAAYJrgtZWgDjAAAAAA==.Tiriell:BAABLgAECn8rAAIVAAkJ9iAlDgC8AgAVAAkJ9iAlDgC8AgAAAA==.',
Tr='Tracixs:BAAALgAECgEJAQAAAA==.Trenity:BAAALgADCgIJAgAAAA==.Trinanah:BAACLgAFFH8NAAIYAAQJ3AV8EwARAQAYAAQJ3AV8EwARAQAuAAQKfygAAhgACAnmEs8bAP4BABgACAnmEs8bAP4BAAAA.',
['Tô']='Tôrunn:BAABLgAECn8rAAIDAAgJlhTYDACfAQADAAgJlhTYDACfAQAAAA==.',
Un='Undeadots:BAAALgAECgEJAQAAAA==.',
Ut='Uthandric:BAAALgADCgIJAgABLgAECgkJJwADAEkkAA==.',
Va='Valeriux:BAAALgAECgMJAwAAAA==.Vallock:BAABLgAECn8dAAIOAAYJ2wZ5FgC4AAAOAAYJ2wZ5FgC4AAAAAA==.Valmyr:BAAALgAECgMJAwAAAA==.Valor:BAAALgADCggJCAABLgAECggJIwAVABYjAA==.Vanarn:BAAALgADCgQJBQAAAA==.',
Ve='Velamun:BAAALgADCgcJBwAAAA==.Velidori:BAAALgAECgEJAgAAAA==.Velrez:BAAALgAECgQJBwAAAA==.Vengence:BAAALgADCgYJBwAAAA==.Venusäur:BAAALgAECgYJDgAAAA==.',
Vi='Viital:BAAALgAECgMJBQAAAA==.',
Vo='Voidblade:BAAALgAECgIJBQAAAA==.',
Wa='Wammus:BAAALgAECgYJCgAAAA==.Warglaive:BAAALgADCgMJBQAAAA==.Wayden:BAAALgAECggJEwAAAA==.Waz:BAAALgAECgQJCAAAAA==.',
We='Wef:BAABLgAECn8hAAIGAAgJgQuXSABuAQAGAAgJgQuXSABuAQAAAA==.Welath:BAAALgAECggJCAAAAA==.',
Wh='Whobit:BAAALgADCgUJBQAAAA==.',
Wi='Wimbly:BAAALgAECgMJAwAAAA==.Windwalker:BAABLgAECn8mAAIIAAcJTCK8CwA7AgAIAAcJTCK8CwA7AgAAAA==.Wings:BAAALgAECggJDgAAAA==.Wintel:BAAALgADCgQJBQAAAA==.Wizzinmapant:BAAALgAECgUJCgAAAA==.',
Xa='Xanza:BAAALgADCgYJCAAAAA==.',
Yl='Ylva:BAAALgADCgcJCAAAAA==.',
Yo='Yo:BAABLgAECn8ZAAIVAAUJzBXrigAPAQAVAAUJzBXrigAPAQAAAA==.Yozomiria:BAAALgAECgMJAwAAAA==.',
Ys='Yste:BAAALgADCgYJBQABLgAECgMJAwAFAAAAAA==.',
Yu='Yummybuttons:BAAALgAECgQJBAAAAA==.',
Za='Zandk:BAAALgADCgkJEAABLgAFFAUJCwAMAOkHAA==.Zanju:BAAALgAECgQJDAAAAA==.Zanvoker:BAACLgAFFH8LAAIMAAUJ6QeoJAD1AAAMAAUJ6QeoJAD1AAAuAAQKfxsAAgwABwm5GKkWACICAAwABwm5GKkWACICAAAA.',
Ze='Zerc:BAABLgAECn88AAInAAkJCyFRAQDWAgAnAAkJCyFRAQDWAgAAAA==.',
Zi='Zinkie:BAABLgAECn8WAAIOAAYJCBZEDQAcAQAOAAYJCBZEDQAcAQAAAA==.',
Zo='Zorttok:BAAALgAECgQJBwAAAA==.',
Zu='Zukkario:BAAALgAFFAMJBAABLgAFFAcJFwAKAMMiAA==.',
Zy='Zyp:BAAALgADCgMJAwAAAA==.',
['Æn']='Ænlora:BAACLgAFFH8OAAMBAAcJPgueCwB5AQABAAcJPgueCwB5AQARAAEJngcEGQBHAAAuAAQKfxcAAgEACQmPIkUUAN4CAAEACQmPIkUUAN4CAAAA.',
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
