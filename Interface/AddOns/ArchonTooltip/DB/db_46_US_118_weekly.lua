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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Unknown-Unknown','Druid-Feral','Warlock-Destruction','Warrior-Protection','Paladin-Retribution','Hunter-Survival','Warrior-Arms','Evoker-Preservation','Mage-Frost','Evoker-Augmentation','Druid-Restoration','Druid-Balance','Priest-Discipline','Priest-Shadow','Priest-Holy','DeathKnight-Blood','Shaman-Restoration','Hunter-BeastMastery','Evoker-Devastation','Paladin-Holy','Paladin-Protection','Druid-Guardian','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-06-20',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Ae='Aethrion:BAAALgAECgMJBwAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAACLgAFFH8TAAIBAAUJZAlTKgALAQABAAUJZAlTKgALAQAuAAQKf0IAAgEACQkEG2kYACsCAAEACQkEG2kYACsCAAAA.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8TAAICAAkJAhigVgCeAQACAAkJAhigVgCeAQAAAA==.',
Ar='Aralaria:BAAALgAECgUJBQABLgAFFAMJCQADAIcdAA==.Aramis:BAAALgAECggJEwABLgAFFAMJCQADAIcdAA==.Aranumi:BAAALgAECgQJBAABLgAFFAMJCQADAIcdAA==.Arathrok:BAACLgAFFH8JAAIDAAMJhx22jADxAAADAAMJhx22jADxAAAuAAQKfx4AAgMACQmLIChTAMoBAAMACQmLIChTAMoBAAAA.',
As='Asha:BAACLgAFFH8YAAQEAAUJAA1IKgAeAQAEAAUJAA1IKgAeAQAFAAUJ/xY6FAAbAQAGAAUJ7QX2MgDcAAAuAAQKfxwABAUACAnLIKIdAMABAAUACAnLIKIdAMABAAQABAnQHBhKAEMBAAYABQnGGWc4ABsBAAAA.Asmoday:BAABLgAECn8pAAIDAAkJziI6EQDjAgADAAkJziI6EQDjAgAAAA==.Astra:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.Autoshift:BAABLgAECn8WAAIIAAgJ7woAHQAiAQAIAAgJ7woAHQAiAQAAAA==.Auun:BAAALgAECgYJBwABLgAECgkJKQADAM4iAA==.',
Ba='Bartre:BAAALgAFFAEJAQABLgAFFAQJFwAJAGgjAA==.Bat:BAABLgAECn8eAAIIAAkJZCUGAwDsAgAIAAkJZCUGAwDsAgAAAA==.',
Be='Benedictine:BAAALgAECgEJBQAAAA==.',
Bi='Bigcleavage:BAABLgAECn8hAAIKAAkJAxv1DgD7AQAKAAkJAxv1DgD7AQAAAA==.Bilbert:BAAALgAECgMJAwABLgAFFAMJCQALAKQgAA==.',
Bl='Blue:BAAALgAECgYJBgABLgAFFAgJGgAMAB0SAA==.Blueberrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Bo='Boomster:BAABLgAFFH8KAAIOAAYJ5h+5CAAlAgAOAAYJ5h+5CAAlAgABLgAFFAkJBAAHAAAAAA==.',
Br='Bri:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAACLgAFFH8JAAILAAMJpCAJUQANAQALAAMJpCAJUQANAQAuAAQKfyIAAgsACQnBI7oXALQCAAsACQnBI7oXALQCAAAA.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCwAAAA==.',
Ch='Cherrypie:BAAALgAFFAEJAQABLgAFFAMJBQANAGATAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cr='Cranberrypie:BAAALgAECgQJBQABLgAFFAMJBQANAGATAA==.Criscomaster:BAAALgAECgMJAwAAAA==.',
Cy='Cylla:BAACLgAFFH8WAAIPAAQJ7Qw2aQARAQAPAAQJ7Qw2aQARAQAuAAQKfzoAAg8ACQl8HGUyAE8CAA8ACQl8HGUyAE8CAAAA.',
De='Delacour:BAAALgAECgQJBAABLgAECgkJKQADAM4iAA==.',
Di='Dilfdormu:BAABLgAECn8gAAMOAAYJwBAHGQBEAQAOAAYJwBAHGQBEAQAQAAIJ1QInkwA0AAAAAA==.',
Dk='Dkvaluemenu:BAAALgAECgQJBAAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAACLgAFFH8OAAIRAAQJWRLoLwDyAAARAAQJWRLoLwDyAAAuAAQKfzkAAxEACQk+H58JACADABEACQk+H58JACADABIAAQnaJB9vAGoAAAAA.',
Dr='Dragonmabals:BAAALgAECgQJBAABLgAECgkJIQAKAAMbAA==.Dratak:BAACLgAFFH9NAAIKAAgJkSRFAQDDAgAKAAgJkSRFAQDDAgAuAAQKf3oAAgoACQnmJgsAAKIDAAoACQnmJgsAAKIDAAAA.Dread:BAABLgAECn8bAAIFAAgJjBrAEAB2AgAFAAgJjBrAEAB2AgAAAA==.Dreadfang:BAAALgAECgEJAgAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgAECgEJBgABLgAFFAgJTQAKAJEkAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAwAAAA==.Elunaraa:BAAALgAECgEJAQAAAA==.Elusivemonk:BAAALgAECgEJAQAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.Emeraldmay:BAAALgADCgQJBAAAAA==.',
Eu='Eugene:BAAALgAECgEJAQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAABLgAECn8lAAMBAAcJjxXmQABBAQABAAYJSxTmQABBAQAKAAcJXhCTIgAbAQAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAQJFwAKAKYlAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8yAAMTAAkJxiKNAQByAwATAAkJxiKNAQByAwAUAAEJSQDEQwAVAAAuAAQKf0EABBMACQmlJSABAMkDABMACQmlJSABAMkDABUABwkSEUAvAIYBABQAAgncIbpGAMkAAAAA.',
Ge='Geron:BAAALgAECgUJBQABLgAFFAMJCQALAKQgAA==.Geronimó:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Geronimô:BAAALgAECgYJEQAAAA==.Gerønimo:BAAALgAECgEJAgAAAA==.',
Go='Goo:BAAALgAECgcJDAABLgAFFAcJGAAWAC0VAA==.',
Gu='Gummies:BAAALgAECgEJAQAAAA==.Guy:BAAALgADCgcJBwABLgAFFAkJJAAXAHEXAA==.',
Ha='Hamhock:BAAALgAECgQJDgAAAA==.Haradali:BAAALgAFFAQJBAAAAA==.Hawa:BAAALgADCgEJAgAAAA==.',
Hi='Highpantsman:BAAALgAECgcJCAAAAA==.',
Ho='Holydiah:BAABLgAECn8pAAILAAcJeg/UlgBHAQALAAcJeg/UlgBHAQAAAA==.Holypriest:BAAALgAECgcJCgAAAA==.Hoofwinkled:BAAALgAECgcJBwAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAACLgAFFH8JAAMVAAMJXhaGIgCmAAAVAAMJBxKGIgCmAAATAAIJ7hFWPACKAAAuAAQKfy8ABBMACQliHLASAB0CABMACAnFHrASAB0CABQABwn/DCs5AC8BABUABAmOCedTAI0AAAAA.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECgkJKQADAM4iAA==.Kayla:BAAALgAECgEJAwAAAA==.',
Ko='Kode:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgcJJQABAI8VAA==.Kroth:BAABLgAECn9KAAIRAAkJpxO1KwD7AQARAAkJpxO1KwD7AQAAAA==.',
Ku='Kubfury:BAAALgAECgcJDgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8lAAIYAAkJ/yFqFACvAgAYAAkJ/yFqFACvAgAAAA==.Kíran:BAAALgAECgEJAwAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Li='Lily:BAAALgAECggJDgAAAA==.Limparrow:BAAALgAECgQJBgAAAA==.',
Lo='Loris:BAAALgAECgcJBgABLgAFFAkJBAAHAAAAAA==.',
Lu='Lunaci:BAABLgAECn8qAAMQAAkJDxxRDQCIAgAQAAkJDxxRDQCIAgAZAAYJmQ4LEgDqAAAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
['Lø']='Løop:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8uAAIKAAkJWR39BwB9AgAKAAkJWR39BwB9AgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8uAAIPAAkJvBwXHwCjAgAPAAkJvBwXHwCjAgAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgUJBgAAAA==.Maypah:BAAALgADCgIJAgAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Meowmfmeow:BAAALgADCgcJBwAAAA==.Metier:BAAALgAECgUJCgABLgAFFAQJFwAKAKYlAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAABLgAFFH8GAAIOAAUJbCU5CQAaAgAOAAUJbCU5CQAaAgABLgAFFAkJBAAHAAAAAA==.Misfortune:BAAALgAECggJDgABLgAFFAMJCQALAKQgAA==.Mitsy:BAABLgAECn8uAAIUAAgJIRbxHgDOAQAUAAgJIRbxHgDOAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMLAAgJGCGfIACpAgALAAcJFiGfIACpAgAaAAIJcAcCeQBbAAAAAA==.Montipython:BAABLgAECn8WAAMbAAkJ7RSlGwA6AQAbAAUJBh2lGwA6AQALAAYJZw2sywD5AAAAAA==.Moons:BAACLgAFFH8aAAMMAAgJHRIuAgAlAgAMAAgJHRIuAgAlAgAYAAEJ8QGQsAA7AAAuAAQKf1QAAgwACQmXI4sCACADAAwACQmXI4sCACADAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAACLgAFFH8RAAITAAgJpgw9AgBaAQATAAgJpgw9AgBaAQAuAAQKfxgAAhMABwmrH1UOAFUCABMABwmrH1UOAFUCAAAA.',
Mu='Mudpie:BAABLgAECn8aAAIcAAkJAx8gDAAfAgAcAAkJAx8gDAAfAgABLgAFFAMJBQANAGATAA==.Munco:BAACLgAFFH8FAAIdAAQJVhu9DwAlAQAdAAQJVhu9DwAlAQAuAAQKfz0AAx0ACQnjI6gDABoDAB0ACQnjI6gDABoDAAIAAQlMGPQDAUcAAAAA.Muncola:BAAALgAECgMJAwABLgAFFAQJBQAdAFYbAA==.Muncoli:BAAALgAECgMJBAABLgAFFAQJBQAdAFYbAA==.Muncolito:BAAALgADCgEJAQABLgAFFAQJBQAdAFYbAA==.Mungus:BAAALgAECgQJCQAAAA==.Mutakor:BAAALgAECgEJAQABLgAFFAgJTQAKAJEkAA==.',
My='Mylf:BAAALgAECgEJAQAAAA==.Mythhleremix:BAAALgADCgUJBgABLgAFFAQJFwAKAKYlAA==.',
Ne='Nedd:BAAALgADCggJCAABLgAECgkJKQADAM4iAA==.Nellie:BAABLgAECn8gAAMSAAkJJg7SJwCRAQASAAkJJg7SJwCRAQARAAQJlQHMsABkAAAAAA==.Newtree:BAAALgAFFAkJBAAAAA==.',
No='Notker:BAABLgAECn8uAAIVAAkJ7CP+AgBnAwAVAAkJ7CP+AgBnAwAAAA==.',
Ny='Nynaa:BAAALgAECgEJAQABLgAECgkJKQADAM4iAA==.',
On='Onieroxmysox:BAAALgAECgUJCAAAAA==.',
Or='Orcwarr:BAABLgAECn8uAAQKAAkJ1RzCCABsAgAKAAkJ1RzCCABsAgABAAMJlAl4jwCAAAANAAEJPQsKQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAILAAQJ+AV6YQDsAAALAAQJ+AV6YQDsAAAAAA==.Patadita:BAAALgAFFAQJBAAAAA==.',
Pe='Pecanpie:BAABLgAFFH8FAAQNAAMJYBNXMgCUAAANAAIJQBNXMgCUAAABAAIJIA0CRQCPAAAKAAEJoRNNLgAzAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAFFAcJBAABLgAFFAkJBAAHAAAAAA==.Pipsi:BAAALgAECgEJAQABLgAFFAQJBQAdAFYbAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJCAADAJUZAA==.',
Pr='Pryor:BAAALgAECgUJBQABLgAECgkJKQADAM4iAA==.',
Qu='Quiverinpalm:BAABLgAECn8WAAIGAAkJCxBXKgBjAQAGAAkJCxBXKgBjAQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8XAAQJAAQJaCOZCgDxAAAJAAMJaxyZCgDxAAAeAAIJkCP8fgDGAAAfAAEJ8COoGwBWAAAuAAQKfzoABAkACQkFJFkOAOMBAB4ABwmjHucoADgCAAkABQlKI1kOAOMBAB8AAwldJBIiALEAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwABLgAECgkJLQAFAH8WAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIgAAkJCiTeAQD1AgAgAAkJCiTeAQD1AgAAAA==.',
Se='Sennaria:BAAALgAECgEJAQAAAA==.Serenity:BAAALgAECgEJAwABLgAFFAUJCgACAGMaAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAcJHwAhAFEeAA==.Shioh:BAAALgADCgUJBQABLgAECgkJLQAFAH8WAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgAECgYJCwAAAA==.Sinappi:BAAALgAECgEJAwAAAA==.Siñ:BAABLgAECn8jAAIiAAkJTQgjCwCAAQAiAAkJTQgjCwCAAQAAAA==.',
Sk='Skaya:BAAALgADCgIJAgAAAA==.Skeetshootah:BAABLgAECn8tAAIYAAkJ2hesMQAVAgAYAAkJ2hesMQAVAgAAAA==.Skunkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.Skunkstömper:BAAALgAECgEJAQAAAA==.Skùnkstomper:BAAALgAECgcJCwAAAA==.Skúnkstomper:BAAALgAECgQJBAABLgAECgcJBwAHAAAAAA==.Skûnkstomper:BAAALgAECgEJAQABLgAECgcJBwAHAAAAAA==.',
Sl='Slowbadon:BAABLgAECn8YAAIaAAkJixOoNQB6AQAaAAkJixOoNQB6AQAAAA==.',
Sp='Spáceballs:BAAALgAECgYJCQABLgAECgcJBwAHAAAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgABLgAFFAkJBAAHAAAAAA==.Streetlight:BAABLgAECn8VAAIMAAkJYQ+iFQD2AQAMAAkJYQ+iFQD2AQABLgABCgEJAQAHAAAAAA==.Streetlights:BAAALgAECgYJDgABLgABCgEJAQAHAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAHAAAAAA==.',
Ta='Tank:BAACLgAFFH8XAAIKAAQJpiUGCQCjAQAKAAQJpiUGCQCjAQAuAAQKfzIAAgoACQnDJa8CADwDAAoACQnDJa8CADwDAAAA.',
Te='Teafayd:BAABLgAECn8eAAQfAAYJBw1zHwDFAAAfAAYJCAtzHwDFAAAJAAMJ4AwpJgCDAAAeAAEJpgpxCwA1AAAAAA==.',
Th='Thisboss:BAAALgAECgYJCQAAAA==.Thunderdot:BAABLgAECn8yAAIUAAkJbh4SDQCCAgAUAAkJbh4SDQCCAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAACLgAFFH8hAAIDAAYJdBaEAwB8AQADAAYJdBaEAwB8AQAuAAQKf1UAAgMACQkKI2gAALECAAMACQkKI2gAALECAAAA.',
To='Tomayter:BAABLgAECn8tAAIVAAkJzh9VCADmAgAVAAkJzh9VCADmAgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgABLgAFFAUJCgACAGMaAA==.Tree:BAABLgAFFH8OAAIRAAcJLiGKBQC4AgARAAcJLiGKBQC4AgABLgAFFAkJBAAHAAAAAA==.Trinitee:BAAALgAECgUJBQAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQALAG4aAA==.Trist:BAABLgAECn8dAAILAAkJbhpzPgArAgALAAkJbhpzPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8lAAIDAAgJuh4GLQCFAgADAAgJuh4GLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQAMAFMYAA==.',
Tw='Twaave:BAABLgAECn8yAAIPAAkJjSIUDwACAwAPAAkJjSIUDwACAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAHAAAAAA==.',
Ve='Vendmachin:BAAALgAECgMJAwAAAA==.Verdessa:BAAALgAECgQJCAAAAA==.',
Vn='Vnav:BAABLgAECn8VAAIjAAcJogn7LAAzAQAjAAcJogn7LAAzAQAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Xe='Xevic:BAAALgAECgIJAgABLgAECgkJKQADAM4iAA==.',
Xi='Xins:BAAALgAECgQJBAAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Za='Zapa:BAAALgAECgMJBQAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8uAAMJAAkJfhrkAwBOAgAJAAkJfhrkAwBOAgAeAAcJAAbinAAEAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8uAAIWAAkJUBfAFgCyAQAWAAkJUBfAFgCyAQAAAA==.',
['ßu']='ßunter:BAAALgADCgUJAgAAAA==.',
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
