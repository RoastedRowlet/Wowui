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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Feral','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Evoker-Augmentation','Druid-Restoration','Druid-Guardian','Druid-Balance','Priest-Discipline','Priest-Holy','Priest-Shadow','Paladin-Protection','DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-08-18',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgQJCAAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8TAAIBAAUJZAlPKgALAQABAAUJZAlPKgALAQAuAAQKf0IAAgEACQkEG2kYACsCAAEACQkEG2kYACsCAAAA.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQACAAkJAhigVgCeAQAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCgADAIcdAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCgADAIcdAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCgADAIcdAA==.Arathrok:BAACLgAFFH8KAAIDAAMJhx2xjADxAAADAAMJhx2xjADxAAAuAAQKfx4AAgMACQmLIC9TAMoBAAMACQmLIC9TAMoBAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJAA1KKgAeAQAEAAUJAA1KKgAeAQAFAAUJ/xY4FAAbAQAGAAUJ7QXtMgDcAAAuAAQKfxwABAUACAnLIKEdAMABAAUACAnLIKEdAMABAAQABAnQHBZKAEMBAAYABQnGGWo4ABsBAAAA.Asmoday:BAABLgAECn8pAAIDAAkJziI8EQDjAgADAAkJziI8EQDjAgAAAA==.Astra:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7woCHQAiAQAIAAgJ7woCHQAiAQAAAA==.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAFFAEJAQABLgAFFAQJFwAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCUGAwDsAgAIAAkJZCUGAwDsAgAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxvzDgD7AQAKAAkJAxvzDgD7AQAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCgALAKQgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAgJGgAMAB0SAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h+xCAAlAgAOAAYJ5h+xCAAlAgABLgAFFAkJBgAOAGwlAA==.',
Br='Bri:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8KAAILAAMJpCD6UAANAQALAAMJpCD6UAANAQAuAAQKfyIAAgsACQnBI7sXALQCAAsACQnBI7sXALQCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cp='Cptbarnacles:BAABLgAECn8lAAQPAAcJhBKiIQC1AAAQAAQJGhHxqQDuAAAPAAQJshCiIQC1AAAJAAMJzwwjKgBsAAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgAECggJDQAAAA==.',
Cy='Cylla:BAACLgAFFH8fAAIRAAcJyAkCKQAwAQARAAcJyAkCKQAwAQAuAAQKfzoAAhEACQl8HGMyAE8CABEACQl8HGMyAE8CAAAA.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8iAAMOAAYJwBAHGQBEAQAOAAYJwBAHGQBEAQASAAMJLwkbFwBPAAAAAA==.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8OAAITAAQJWRLhLwDyAAATAAQJWRLhLwDyAAAuAAQKfzwABBMACQk+H58JACADABMACQk+H58JACADABQAAwlgCRkSAG8AABUAAQnaJCBvAGoAAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAABLgAECgkJIQAKAAMbAA==.Dratak:BAACLgAFFH+EAAIKAAkJbSRcAABDAwAKAAkJbSRcAABDAwAuAAQKf3oAAgoACQnmJgsAAKIDAAoACQnmJgsAAKIDAAAA.Dratalt:BAABLgAFFH8NAAIKAAYJWRqYBgCKAQAKAAYJWRqYBgCKAQABLgAFFAkJhAAKAG0kAA==.Dread:BAABLgAECn8bAAIFAAgJjBrAEAB2AgAFAAgJjBrAEAB2AgAAAA==.Dreadfang:BAAALgAECgEJAgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJCQABLgAFFAkJhAAKAG0kAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgUJBQAAAA==.Elunaraa:BAAALgAECgEJAQAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgAECgcJEgAAAA==.Emeraldmay:BAAALgAECgQJBAAAAA==.',
Eu='Eugene:BAAALgAECgEJAQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frockit:BAAALgAECgQJBAABLgAFFAMJBgABAAwRAA==.Frocknor:BAACLgAFFH8GAAIBAAMJDBHEFwDgAAABAAMJDBHEFwDgAAAuAAQKfzIAAwoACQnZFhgFAEcBAAoACQkiExgFAEcBAAEABglUFXgOAOYAAAAA.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFwAKAKYlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH9IAAQWAAkJriOLAQByAwAWAAkJriOLAQByAwAXAAMJxh3+CgABAQAYAAEJMxcdJQBEAAAuAAQKf0EABBYACQmlJR8BAMkDABYACQmlJR8BAMkDABcABwkSEUAvAIYBABgAAgncIbpGAMkAAAAA.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCgALAKQgAA==.Geronimó:BAAALgAECgYJCwABLgAECgcJDAAHAAAAAA==.Geronimô:BAABLgAECn8YAAMLAAYJRRCtIwDOAAALAAYJRRCtIwDOAAAZAAIJ3gKHUQAuAAAAAA==.Gerønimo:BAAALgAECgEJAgAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAcJGAAaAC0VAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Gumz:BAAALgAECgEJAwAAAA==.Guy:BAAALgADCgcJCAABLgAFFAkJPwAbAEUZAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAgAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8sAAILAAkJcg/SlgBHAQALAAkJcg/SlgBHAQAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hoofwinkled:BAAALgAECgcJDAAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.Hornstar:BAAALgAECgkJCQAAAA==.',
Ik='Iktomi:BAAALgAECgUJBQAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8PAAMXAAUJvxVFDQDTAAAXAAUJJBNFDQDTAAAWAAMJgw77JwBfAAAuAAQKfzAABBYACQlvHLASAB0CABYACAnFHrASAB0CABgABwn/DC45AC8BABcABQn8DuMUAGUAAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ki='Kittybutt:BAABLgAFFH8FAAISAAMJswnTJQCRAAASAAMJswnTJQCRAAAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgQJCAABLgAFFAMJBgABAAwRAA==.Kroth:BAABLgAECn9KAAITAAkJpxOzKwD7AQATAAkJpxOzKwD7AQAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIcAAkJ/yFnFACvAgAcAAkJ/yFnFACvAgAAAA==.Kíran:BAAALgAECgEJAwABLgAECgQJCAAHAAAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Le='Lediah:BAAALgAECgUJBwAAAA==.',
Li='Liilith:BAAALgAECgUJBwAAAA==.Lily:BAABLgAECn8gAAQKAAkJSh+MAQByAgAKAAkJIxuMAQByAgABAAgJ1R5aBgCKAQANAAEJMB85FABbAAAAAA==.Limparrow:BAAALgAECgYJCAAAAA==.',
Ln='Lnav:BAAALgAECgIJAgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJBgAOAGwlAA==.',
Lu='Lunaci:BAACLgAFFH8MAAISAAMJjRdRHADHAAASAAMJjRdRHADHAAAuAAQKfyoAAxIACQkPHE8NAIgCABIACQkPHE8NAIgCAB0ABgmZDgsSAOoAAAAA.Lunylu:BAAALgADCgUJBQAAAA==.',
['Lø']='Løop:BAAALgAECgEJAQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR38BwB9AgAKAAkJWR38BwB9AgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIRAAkJvBwWHwCjAgARAAkJvBwWHwCjAgAAAA==.Maven:BAAALgAECgYJDAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Meowmfmeow:BAAALgADCgcJBwAAAA==.Metier:BAAALgAECgUJCwABLgAFFAQJFwAKAKYlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mimetismo:BAAALgADCgQJBAAAAA==.Mirror:BAABLgAFFH8GAAIOAAUJbCUwCQAaAgAOAAUJbCUwCQAaAgAAAA==.Misfortune:BAAALgAECggJDgABLgAFFAMJCgALAKQgAA==.Mitsy:BAABLgAECn8uAAIYAAgJIRbxHgDOAQAYAAgJIRbxHgDOAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAgALAAcJFiGfIACpAgAeAAIJcAf+eABbAAAAAA==.Montipython:BAABLgAECn8WAAMZAAkJ7RSlGwA6AQAZAAUJBh2lGwA6AQALAAYJZw2uywD5AAAAAA==.Moons:BAACLgAFFH8aAAMMAAgJHRIuAgAlAgAMAAgJHRIuAgAlAgAcAAEJ8QGRsAA7AAAuAAQKf1QAAgwACQmXI4oCACADAAwACQmXI4oCACADAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8TAAIWAAgJFg/sDwBHAQAWAAgJFg/sDwBHAQAuAAQKfxgAAhYABwmrH1UOAFUCABYABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIUAAkJAx8gDAAfAgAUAAkJAx8gDAAfAgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8GAAIfAAQJVhu/DwAlAQAfAAQJVhu/DwAlAQAuAAQKfz0AAx8ACQnjI6YDABoDAB8ACQnjI6YDABoDAAIAAQlMGPsDAUcAAAAA.Muncola:BAAALgAECgMJAwABLgAFFAQJBgAfAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBgAfAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBgAfAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAgABLgAFFAkJhAAKAG0kAA==.',
My='Mylf:BAAALgAECgEJAQAAAA==.Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFwAKAKYlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMVAAkJJg7VJwCRAQAVAAkJJg7VJwCRAQATAAQJlQHMsABkAAAAAA==.Newtree:BAABLgAFFH8FAAIOAAMJyxxYHgC+AAAOAAMJyxxYHgC+AAABLgAFFAkJBgAOAGwlAA==.',
No='Notker:BAABLgAECn8uAAIXAAkJ7CP9AgBnAwAXAAkJ7CP9AgBnAwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
On='Onieroxmysox:BAAALgAECgUJCQAAAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RzBCABsAgAKAAkJ1RzBCABsAgABAAMJlAl4jwCAAAANAAEJPQsKQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AVxYQDsAAALAAQJ+AVxYQDsAAAAAA==.Patadita:BAABLgAFFH8NAAIEAAYJTRcnDgClAQAEAAYJTRcnDgClAQAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBNUMgCUAAANAAIJQBNUMgCUAAABAAIJIA3+RACPAAAKAAEJoRNHLgAzAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAcJBAABLgAFFAkJBgAOAGwlAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBgAfAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8hAAIGAAkJ+RbYAgCdAQAGAAkJ+RbYAgCdAQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8XAAQJAAQJaCOWCgDxAAAJAAMJaxyWCgDxAAAQAAIJkCPhfgDGAAAPAAEJ8COqGwBWAAAuAAQKfzoABAkACQkFJFkOAOMBABAABwmjHucoADgCAAkABQlKI1kOAOMBAA8AAwldJBAiALEAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwABLgAECgkJLQAFAH8WAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.Sanise:BAAALgAECgYJBgAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIgAAkJCiTeAQD1AgAgAAkJCiTeAQD1AgAAAA==.',
Se='Sennaria:BAAALgAECgEJAQAAAA==.Serenity:BAAALgAFFAEJAQABLgAFFAUJDgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAkJLQAhAGsgAA==.Shankdela:BAAALgAECgEJAQAAAA==.Shaule:BAAALgAECgEJAgAAAA==.Shioh:BAAALgADCgUJBQABLgAECgkJLQAFAH8WAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgYJCwAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIiAAkJTQgjCwCAAQAiAAkJTQgjCwCAAQAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIcAAkJ2heqMQAVAgAcAAkJ2heqMQAVAgAAAA==.Skunkstomper:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.Skunkstömper:BAAALgAECgQJBAAAAA==.Skùnkstomper:BAAALgAECgcJDgAAAA==.Skúnkstomper:BAAALgAECgQJBAABLgAECgcJDAAHAAAAAA==.Skûnkstomper:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.Skünkstomper:BAAALgAECgEJAQABLgAECgcJDAAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIeAAkJixOpNQB6AQAeAAkJixOpNQB6AQAAAA==.',
Sp='Spáceballs:BAAALgAECgYJCQABLgAECgcJDAAHAAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stakkzy:BAAALgAECgUJBQABLgAFFAQJCQAMAAoRAA==.Stampede:BAAALgAFFAEJAgABLgAFFAUJDgACAGMaAA==.Stay:BAAALgAECgcJBgABLgAFFAkJBgAOAGwlAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ+fFQD2AQAMAAkJYQ+fFQD2AQABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8XAAIKAAQJpiUDCQCjAQAKAAQJpiUDCQCjAQAuAAQKfzIAAgoACQnDJa8CADwDAAoACQnDJa8CADwDAAAA.',
Te='Teafayd:BAABLgAECn8jAAQPAAYJSg5yHwDFAAAPAAYJyAtyHwDFAAAJAAQJdw4qJgCDAAAQAAEJpgr/PgAoAAAAAA==.',
Th='Thisboss:BAAALgAECgYJCQAAAA==.Thunderdot:BAACLgAFFH8NAAIYAAUJpRFwEADwAAAYAAUJpRFwEADwAAAuAAQKfzIAAhgACQluHhENAIICABgACQluHhENAIICAAAA.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8pAAIDAAcJHBSKGQCZAQADAAcJHBSKGQCZAQAuAAQKf1UAAgMACQkKIwsQAOwCAAMACQkKIwsQAOwCAAAA.',
To='Tomayter:BAABLgAECn8tAAIXAAkJzh9VCADmAgAXAAkJzh9VCADmAgAAAA==.',
Tr='Tree:BAABLgAFFH8OAAITAAcJLiGIBQC4AgATAAcJLiGIBQC4AgABLgAFFAkJBgAOAGwlAA==.Trinitee:BAAALgAECgUJCwAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgALAAkJbhpzPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAgADAAgJuh4GLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJCAAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIRAAkJjSIPDwACAwARAAkJjSIPDwACAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgAECgMJAwAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAABLgAECn8XAAIjAAcJJAr7LAAzAQAjAAcJJAr7LAAzAQAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Xz='Xz:BAAALgAECgMJAwAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zaki:BAAALgADCgEJAQAAAA==.Zapa:BAAALgAECgMJBQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhrkAwBOAgAJAAkJfhrkAwBOAgAQAAcJAAbknAAEAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8uAAIaAAkJUBfBFgCyAQAaAAkJUBfBFgCyAQAAAA==.',
['Ôx']='Ôx:BAAALgAECgUJBQABLgAECgcJDAAHAAAAAA==.',
['ßu']='ßunter:BAAALgADCgUJBQAAAA==.',
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
