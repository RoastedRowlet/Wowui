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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Mage-Frost','Hunter-Survival','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Rogue-Outlaw','Druid-Guardian','Shaman-Elemental','Monk-Windwalker','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Mage-Fire','DeathKnight-Frost','Warrior-Protection','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','DeathKnight-Blood','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-05-16',data={Ab='Abeblinkin:BAAALgAECgQJBAAAAA==.Aborlight:BAAALgAECgQJBwAAAA==.',
Ad='Adit:BAAALgAECgYJCAAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLhjINQClAQABAAYJrRnINQClAQACAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgQJCQAAAA==.',
Ai='Aiwass:BAABLgAECn8wAAIDAAkJbQ2BCAB1AQADAAkJbQ2BCAB1AQAAAA==.Aiyo:BAAALgAECgQJBgABLgAECgcJCwAEAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.',
Am='Amathricus:BAABLgAECn8mAAICAAgJzwubbABMAQACAAgJzwubbABMAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAAALgAECgYJCAAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8HAAMFAAQJ1Q+GEAAqAQAFAAQJ1Q+GEAAqAQAGAAMJcw3hKgDVAAAuAAQKfx0AAwYABwmfHs4VAOEBAAYABwmfHs4VAOEBAAUAAgm2EVMkAH0AAAEuAAUUBAkHAAUA1Q8A.Auitou:BAAALgAECgcJCAAAAA==.Auralei:BAABLgAECn8UAAIHAAYJBgbbsQDkAAAHAAYJBgbbsQDkAAAAAA==.',
Az='Azelia:BAAALgAECgUJDAABLgAECggJIAABAPcWAA==.Azzy:BAABLgAECn8gAAMBAAgJ9xb2IACxAQABAAcJ+hn2IACxAQACAAEJPwGZWwERAAAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAECgIJBAABLgAFFAIJAgAEAAAAAA==.',
Bi='Bigb:BAABLgAECn8mAAIIAAcJKSYEBQDEAgAIAAcJKSYEBQDEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgADCgcJFwAAAA==.Brochese:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAQJEQAJALEPAA==.Buwumkin:BAAALgAECgEJAQAAAA==.',
Ca='Cadaverous:BAAALgAECgUJCQAAAA==.Canadianguy:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.',
Ch='Cheyeon:BAAALgAECgYJBgAAAA==.Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAAALgAECgEJAgAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAcJGQAKAKUgAA==.Claybigsby:BAACLgAFFH8PAAILAAQJ2RgiLAA5AQALAAQJ2RgiLAA5AQAuAAQKfxwAAwMACAm5HRADAMoCAAMACAm5HRADAMoCAAsABQmWGq5xAHwBAAAA.Clif:BAACLgAFFH8JAAMMAAQJhAv0DgD9AAAMAAQJhAv0DgD9AAANAAIJxAf/LgCJAAAuAAQKfxkAAw0ACAmqHNwWAJYCAA0ACAmqHNwWAJYCAAwAAQl+HUVEAFAAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJBwAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Da='Dargon:BAABLgAECn8XAAMGAAgJ3yNnBgAZAwAGAAgJ3yNnBgAZAwAOAAYJ7hzSGwBSAQABLgAECggJGgACAGomAA==.',
De='Deaf:BAAALgAFFAEJAQABLgAFFAMJBQAPAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demonifrita:BAAALgADCgkJCQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAEAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAAALgAECgcJEwAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAcJGQAKAKUgAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiemage:BAAALgAECgEJAgAAAA==.Dorenis:BAAALgAECgEJAgAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Droopox:BAABLgAECn8eAAIQAAkJBQnsGQACAQAQAAkJBQnsGQACAQAAAA==.Druchese:BAAALgAECgYJCwABLgAECgYJDgAEAAAAAA==.',
Ea='Eagleeye:BAABLgAECn8VAAICAAYJXRFCnADzAAACAAYJXRFCnADzAAAAAA==.',
Em='Emsley:BAACLgAFFH8IAAIRAAMJzwZfIwDAAAARAAMJzwZfIwDAAAAuAAQKf0UAAhEACQnaFtEPACcCABEACQnaFtEPACcCAAAA.',
Er='Erised:BAAALgADCgYJDwAAAA==.',
Ex='Exo:BAACLgAFFH8RAAIHAAQJzhrYKwBdAQAHAAQJzhrYKwBdAQAuAAQKfx4AAgcACAkzITYgAPMCAAcACAkzITYgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAECggJGgACAGomAA==.',
Fl='Floudruid:BAAALgADCgMJAwAAAA==.',
Fo='Focalors:BAAALgAFFAIJAgAAAA==.Foobear:BAACLgAFFH8RAAIQAAQJTxWNBQAiAQAQAAQJTxWNBQAiAQAuAAQKfygAAhAACAnXHpsEAKQCABAACAnXHpsEAKQCAAAA.Fozzy:BAABLgAECn8YAAIGAAgJpQekOwDpAAAGAAgJpQekOwDpAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8gAAIKAAkJLhyWIABDAgAKAAkJLhyWIABDAgAAAA==.Franfran:BAABLgAECn8fAAIHAAkJcw8RSADBAQAHAAkJcw8RSADBAQAAAA==.Freasey:BAABLgAECn8UAAICAAYJiw/qkAAHAQACAAYJiw/qkAAHAQAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgUJDwABLgAFFAQJEQAQAE8VAA==.Furlock:BAAALgAECgYJEgAAAA==.',
Ga='Gabriel:BAAALgAECgcJCAAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgYJCQAAAA==.',
Ge='Gengiskaan:BAAALgADCggJEAAAAA==.',
Gi='Gir:BAAALgAECgYJBwAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgAECgYJDgAAAA==.',
Gr='Gramid:BAABLgAECn8aAAICAAgJaiYFEgCdAgACAAgJaiYFEgCdAgAAAA==.Greenseer:BAABLgAECn8kAAILAAYJPRVuZwAzAQALAAYJPRVuZwAzAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAABLgAECn8xAAINAAkJJSDxBwChAgANAAkJJSDxBwChAgAAAA==.',
Ha='Haagen:BAAALgAECgMJAwAAAA==.Haagoon:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAIPAAMJwiEaBAAbAQAPAAMJwiEaBAAbAQAuAAQKfx0AAg8ABwmCJR0BAPMCAA8ABwmCJR0BAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECggJHQASAP8OAA==.',
Hi='Hightones:BAACLgAFFH8JAAITAAQJDAixNAAHAQATAAQJDAixNAAHAQAuAAQKfyAAAhMACAk2IEoWANECABMACAk2IEoWANECAAAA.',
Ho='Holdêm:BAABLgAECn8dAAISAAgJ/w4oIABbAQASAAgJ/w4oIABbAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAQJEQARAK4eAA==.Hollee:BAAALgADCgQJBAABLgAFFAQJEQAUAIUTAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgYJCwAAAA==.',
Ic='Icylady:BAAALgAECgYJCQAAAA==.',
If='Ifrita:BAACLgAFFH8GAAMHAAMJDgneYgDXAAAHAAMJEAbeYgDXAAAVAAEJ4Qo+AwBCAAAuAAQKfzcABBUACAk7FaoHAIYBAAcACAnkEy1NALMBABUABgkjE6oHAIYBABYAAQm1CdwNAC8AAAAA.Ifrite:BAABLgAECn8dAAMKAAkJFw7FfgCGAQAKAAcJtAzFfgCGAQAXAAgJiArQEQDbAAAAAA==.',
Ik='Ikur:BAAALgAECgYJDgABLgAFFAMJBwABANAWAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8KAAICAAMJuwKLSgDDAAACAAMJuwKLSgDDAAAuAAQKfyUAAgIACQnjEJRHAKkBAAIACQnjEJRHAKkBAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAgAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAEAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn8uAAMMAAgJ8iGABACGAgAMAAgJ8iGABACGAgAYAAMJlyFkGgAXAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgAECgMJAwAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8sAAMZAAkJTBt0BgAhAgAZAAgJAh10BgAhAgAaAAcJdA68gwDQAAAAAA==.Katakuri:BAAALgAECgEJAQAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIbAAcJIheEJABaAQAbAAcJIheEJABaAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.',
Kr='Krayt:BAAALgAECgEJAgAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAgJHAALAEclAA==.',
La='Lambo:BAABLgAECn8eAAIRAAgJDSACCgB5AgARAAgJDSACCgB5AgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDQAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAAALgAFFAMJAwAAAA==.Loveyuling:BAAALgAECgEJAwABLgAECgQJBwAEAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8jAAIHAAgJYhpcAwB3AgAHAAgJYhpcAwB3AgAuAAQKfyoAAwcACQleI6oPAEoDAAcACQleI6oPAEoDABYABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8OAAIcAAUJZyLIAQB7AQAcAAUJZyLIAQB7AQAuAAQKfxgAAhwACAnqH7MCAMECABwACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAgAAAA==.Melitha:BAAALgADCggJCAABLgAECggJLgAMAPIhAA==.Mero:BAACLgAFFH8HAAITAAQJtBAtLAAiAQATAAQJtBAtLAAiAQAuAAQKfyAAAx0ACAkNGlsJANkBAB0ABgmOH1sJANkBABMABwnkEvpmAG0BAAAA.Metal:BAABLgAECn8eAAIeAAcJqxcdHQCLAQAeAAcJqxcdHQCLAQAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAFFAIJAgAEAAAAAA==.Mistbehavin:BAACLgAFFH8RAAIJAAQJsQ+6GgATAQAJAAQJsQ+6GgATAQAuAAQKfyIAAgkACAm5FvgcABsCAAkACAm5FvgcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyXtGgA9AgABAAcJMyXtGgA9AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgYJDgAEAAAAAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgADCgIJAwAAAA==.',
Ne='Nemisai:BAAALgAECgYJDAAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Nu='Nutinerbutt:BAAALgAECgEJAQAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAAALgAECgQJDQAAAA==.',
Ok='Ok:BAABLgAECn8WAAIIAAgJ5ROhFgCmAQAIAAgJ5ROhFgCmAQAAAA==.',
Or='Orionbtch:BAABLgAECn8VAAIfAAcJMQcHJAAXAQAfAAcJMQcHJAAXAQAAAA==.',
Ov='Overheat:BAABLgAECn8aAAIHAAgJkh2zNAAFAgAHAAgJkh2zNAAFAgAAAA==.',
Po='Poppy:BAABLgAECn8YAAIHAAYJhAfQrQDrAAAHAAYJhAfQrQDrAAAAAA==.Portinglol:BAAALgAECgEJAQABLgAFFAcJGQAKAKUgAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECggJEAAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn8oAAITAAgJDRXwNwCdAQATAAgJDRXwNwCdAQAAAA==.Ravenstorm:BAAALgAECgYJDAAAAA==.',
Re='Remmîngton:BAABLgAECn8uAAMBAAgJNx/xDAB5AgABAAgJNx/xDAB5AgACAAEJdwdcQgEzAAAAAA==.Retbulls:BAAALgAECgUJBQAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAABLgAECn8qAAIUAAkJYB2dEwB4AgAUAAkJYB2dEwB4AgAAAA==.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAAALgAECgYJDgAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8uAAIKAAkJdhY9NQDlAQAKAAkJdhY9NQDlAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8RAAIHAAQJOhtcMQBTAQAHAAQJOhtcMQBTAQAuAAQKfyIAAgcACAmGI0kXAB4DAAcACAmGI0kXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAECggJGgACAGomAA==.',
Sh='Shel:BAABLgAECn8oAAITAAkJHgvwSABeAQATAAkJHgvwSABeAQAAAA==.Sheppy:BAAALgAFFAQJBAAAAA==.Shimakaze:BAACLgAFFH8YAAMKAAUJYCUzFwA5AQAKAAQJYCUzFwA5AQAgAAEJAABjNQAAAAAuAAQKfyIAAgoABwljJNcrAIkCAAoABwljJNcrAIkCAAAA.Shizaam:BAACLgAFFH8RAAIRAAQJrh78CwBkAQARAAQJrh78CwBkAQAuAAQKfyIAAxEACAkHJYgFAD4DABEACAkHJYgFAD4DABQAAQkrCXSdADQAAAAA.Shlommy:BAAALgAECggJEQAAAA==.',
Si='Siinns:BAACLgAFFH8FAAISAAQJlwyKDgAQAQASAAQJlwyKDgAQAQAuAAQKfyEAAxIACQmOHcELADwCABIACQmOHcELADwCAAkAAgnOE0J6AFsAAAAA.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullmages:BAACLgAFFH8QAAICAAQJABgACQBnAQACAAQJABgACQBnAQAuAAQKfxkAAgIABwk3I6QgAKkCAAIABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8YAAINAAYJOhBvRQDeAAANAAYJOhBvRQDeAAAAAA==.Slinkeril:BAABLgAECn8VAAIcAAYJIxDuCwAtAQAcAAYJIxDuCwAtAQAAAA==.Sloppydro:BAAALgAECgMJBgAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAEAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAEAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Sploosh:BAAALgADCgcJBwAAAA==.',
St='Stabberz:BAACLgAFFH8JAAIcAAMJshavBAABAQAcAAMJshavBAABAQAuAAQKf0gAAxwACQmhIckAAAYDABwACQmhIckAAAYDAB8ABAk4EqhLAM0AAAAA.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAcJGQAKAKUgAA==.',
Sw='Sweetsourrex:BAAALgAECgYJCQABLgAECgcJCwAEAAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAEAAAAAA==.',
Ta='Tatisjr:BAAALgAECgQJBAAAAA==.',
Te='Tempprance:BAAALgADCgcJEQAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBwAAAA==.Thrass:BAABLgAECn8gAAIHAAkJ+hH6OgDuAQAHAAkJ+hH6OgDuAQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Tohru:BAAALgAECgIJAgABLgAFFAIJAgAEAAAAAA==.Toobrunner:BAACLgAFFH8aAAITAAYJhSIxBwADAgATAAYJhSIxBwADAgAuAAQKfx4AAhMACAlSImUbAK4CABMACAlSImUbAK4CAAAA.Tool:BAACLgAFFH8RAAITAAUJ4CK2EACcAQATAAUJ4CK2EACcAQAuAAQKfyEAAhMACQnqIwQMACEDABMACQnqIwQMACEDAAEuAAUUCAkZAAcAHBsA.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Va='Vampress:BAAALgAECgEJAgAAAA==.Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAABLgAECn8qAAMPAAkJ5SH0AADYAgAPAAkJlyH0AADYAgAcAAcJWh3lBQDJAQAAAA==.',
Vi='Virikas:BAABLgAECn8cAAMUAAcJYx16GwAaAgAUAAcJYx16GwAaAgARAAQJKAxJVwCHAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAITAAgJThXCWwCOAQATAAgJThXCWwCOAQAAAA==.Voodooki:BAABLgAECn8uAAIhAAgJwhFxHgB8AQAhAAgJwhFxHgB8AQAAAA==.',
Vu='Vuo:BAABLgAECn8tAAIiAAgJyhOjOACpAQAiAAgJyhOjOACpAQAAAA==.',
Wa='Wayside:BAAALgAECgEJBwAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAAALgAFFAQJBAAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAEAAAAAA==.',
Wi='Wickedshaman:BAAALgADCgkJCQABLgAECggJLQAiAMoTAA==.Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAABLgAFFH8IAAILAAQJnBKvMQAtAQALAAQJnBKvMQAtAQAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgAHAK4WAA==.Yamå:BAACLgAFFH8GAAIHAAMJrhZpVQD6AAAHAAMJrhZpVQD6AAAuAAQKfxkAAgcABglrIktfAB0CAAcABglrIktfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn8pAAIUAAgJZh5fDQCeAgAUAAgJZh5fDQCeAgAAAA==.',
Ze='Zerosh:BAABLgAECn8gAAIcAAgJ1gxzCAB8AQAcAAgJ1gxzCAB8AQAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8hAAIRAAkJchMjGwC1AQARAAkJchMjGwC1AQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAwAAAA==.',
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
