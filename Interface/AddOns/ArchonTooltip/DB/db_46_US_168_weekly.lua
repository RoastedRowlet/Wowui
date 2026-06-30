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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Mage-Frost','Mage-Arcane','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','DemonHunter-Havoc','Hunter-Survival','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-06-27',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AnWOADDAAABAAQJ+AnWOADDAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Alerra:BAAALgAECgEJAQAAAA==.Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8XAAIEAAgJBxtMQgDbAQAEAAgJBxtMQgDbAQAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgUJCAAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQq7HQAnAQAFAAkJlQq7HQAnAQAAAA==.Arkadias:BAAALgAECgEJAgAAAA==.Arthea:BAABLgAECn8YAAMGAAkJiweFxAADAQAGAAkJmwaFxAADAQAHAAUJ0QWdEQCpAAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgthUACxAQAEAAkJDgthUACxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8oAAIIAAkJyw9kCQARAQAIAAkJyw9kCQARAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIJAAkJghJPIADAAQAJAAkJghJPIADAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIKAAkJcSJrCQAkAwAKAAkJcSJrCQAkAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDQALAIkcAA==.Bastiecats:BAAALgADCgcJBwAAAA==.',
Be='Beatrixx:BAAALgAECggJDQAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8LAAIIAAMJNR+SYQDsAAAIAAMJNR+SYQDsAAAuAAQKfxcAAggACQluIWouAEcCAAgACQluIWouAEcCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8nAAIMAAkJvR7/BgCtAgAMAAkJvR7/BgCtAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoREABLAgACAAkJsRoREABLAgANAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAKAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMOAAkJeRY+GADYAQAOAAkJeRY+GADYAQAPAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAABLgAECn8XAAIQAAkJMAqkVgBcAQAQAAkJMAqkVgBcAQAAAA==.Cheese:BAABLgAECn8dAAMCAAcJvxtTGgDeAQACAAcJvxtTGgDeAQABAAQJPxI+agDYAAAAAA==.Cheesemix:BAABLgAECn8bAAIQAAYJXg1SbgARAQAQAAYJXg1SbgARAQABLgAECgkJRgAQAMYhAA==.Chesleigh:BAABLgAECn8UAAIGAAQJMgpGFACTAAAGAAQJMgpGFACTAAAAAA==.Chickenchokr:BAAALgAECgEJAQAAAA==.',
Ci='Cinderlight:BAABLgAECn8wAAIIAAkJ8BElWADDAQAIAAkJ8BElWADDAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJEAAGAD8SAA==.Crilynn:BAACLgAFFH8TAAIGAAUJERL4YAAfAQAGAAUJERL4YAAfAQAuAAQKfyQAAgYACQlOGKA2AD4CAAYACQlOGKA2AD4CAAAA.Crispycrittr:BAABLgAECn8eAAMRAAgJiAdbJQBMAQARAAgJiAdbJQBMAQASAAEJwwL6KgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8lAAITAAgJLBOMDACMAQATAAgJLBOMDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJCQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAAALgAECgQJEgAAAA==.Dathdeath:BAABLgAECn8jAAIUAAgJXA0nFwAeAQAUAAgJXA0nFwAeAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgAECgYJDAAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAgAAAA==.Dirtnappzz:BAAALgAECgUJBQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIKAAMJ7g1bLADqAAAKAAMJ7g1bLADqAAAuAAQKfygAAgoACAm8IugYAOcCAAoACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAFFAEJAQABLgAFFAQJEAAGAD8SAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJBAAAAA==.Dotdotded:BAAALgAECgkJCwAAAA==.Dotsomahan:BAABLgAECn8YAAIVAAkJWA/IXgCDAQAVAAkJWA/IXgCDAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIWAAkJSRbmCQDVAQAWAAkJSRbmCQDVAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Draik:BAAALgADCggJCAABLgAECgcJDgAXAAAAAA==.Drandzug:BAABLgAECn8hAAIYAAcJwggGUQAFAQAYAAcJwggGUQAFAQAAAA==.Druidfaime:BAAALgAECgYJEwAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAgAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elementalhro:BAAALgAECgEJAQAAAA==.Elise:BAABLgAECn8YAAIZAAcJGB83FwATAgAZAAcJGB83FwATAgAAAA==.Ellzik:BAABLgAECn8UAAMaAAcJ5wt/MwDbAAAaAAcJ5wt/MwDbAAAZAAQJxAOUawBzAAAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDQALAIkcAA==.',
Fa='Falorien:BAABLgAECn8lAAIGAAgJwBI7cACZAQAGAAgJwBI7cACZAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAACLgAFFH8GAAIbAAIJYQxQgAB+AAAbAAIJYQxQgAB+AAAuAAQKfycAAhsACQnoFNpIAKwBABsACQnoFNpIAKwBAAAA.',
Fl='Flamingpax:BAAALgAECgcJDgAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAUJFAAGAH8PAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAACLgAFFH8GAAIKAAMJ8xwXgQAFAQAKAAMJ8xwXgQAFAQAuAAQKfzEAAgoACQkLIfsPAOwCAAoACQkLIfsPAOwCAAAA.Fluffinhigh:BAABLgAECn8rAAUaAAkJ8xo1CQBYAgAaAAkJNho1CQBYAgAZAAYJqRd1NABHAQAcAAMJ9RXBggCzAAAdAAQJZxJyMACfAAABLgAFFAMJBgAKAPMcAA==.Fluffinkai:BAAALgAECgQJCgABLgAFFAMJBgAKAPMcAA==.Fluffybúnny:BAABLgAECn8UAAITAAQJfw4HAwCAAAATAAQJfw4HAwCAAAAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJNwAFAJUKAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Fu='Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIVAAgJJg1pgQA2AQAVAAgJJg1pgQA2AQAAAA==.',
Gi='Gillneddra:BAAALgAECgIJAgAAAA==.Giorgina:BAACLgAFFH8KAAIeAAMJ5Q8SNQC6AAAeAAMJ5Q8SNQC6AAAuAAQKfycAAh4ACAnXF5knALABAB4ACAnXF5knALABAAAA.',
Gl='Glasc:BAABLgAECn8eAAMfAAcJDQ7zNABCAQAfAAcJDQ7zNABCAQALAAYJ7Q2tRAD8AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJEgAAAA==.',
Go='Goobynuk:BAACLgAFFH8JAAIGAAIJ9g83LACXAAAGAAIJ9g83LACXAAAuAAQKfyAAAgYACQkqGcc2AD0CAAYACQkqGcc2AD0CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAUJFAAaAHsTAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMOAAcJ1x2XGQA3AgAOAAcJ3RyXGQA3AgAPAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAFFAEJAQABLgAFFAUJJQAEAFcSAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAXAAAAAA==.',
It='Itzli:BAACLgAFFH8MAAIWAAQJmCCmDgB0AQAWAAQJmCCmDgB0AQAuAAQKfykAAhYACQnzIb8DAIoCABYACQnzIb8DAIoCAAEuAAUUBAkNAAsAiRwA.',
Iv='Ivee:BAABLgAFFH8FAAIKAAMJWgiqJQDNAAAKAAMJWgiqJQDNAAABLgAFFAQJDQALAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDQALAIkcAA==.',
Ja='Janner:BAAALgAECgUJDAAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgMJDAAAAA==.Jesdei:BAABLgAECn8VAAIVAAcJAAKEJQFDAAAVAAcJAAKEJQFDAAAAAA==.',
Jg='Jgwentworth:BAAALgAECgcJBwABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMJAAkJuhivHQDXAQAJAAkJuhivHQDXAQALAAQJ+AreZACIAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJDAAAAA==.Kavix:BAABLgAECn8mAAIcAAkJSxbdIwAsAgAcAAkJSxbdIwAsAgAAAA==.Kayos:BAACLgAFFH8UAAIbAAUJ3A+LTAAFAQAbAAUJ3A+LTAAFAQAuAAQKfygAAxsACQn8FJ88ANUBABsACQktFJ88ANUBACAABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAUJFAAbANwPAA==.Kelz:BAAALgAECgIJAgAAAA==.Kelzexx:BAABLgAECn8qAAILAAkJ4hFEIADEAQALAAkJ4hFEIADEAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIMAAkJrwpJJgAhAQAMAAkJrwpJJgAhAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAABLgAFFH8FAAIGAAMJ8QqKiQDGAAAGAAMJ8QqKiQDGAAABLgAFFAQJDQALAIkcAA==.Kimed:BAAALgAECggJCwAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Kolcon:BAAALgAECgEJAQABLgAECggJDwAXAAAAAA==.Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8iAAIEAAgJRw+cYgCBAQAEAAgJRw+cYgCBAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJEAAGAD8SAA==.',
La='Largetha:BAAALgAECgQJBQABLgAFFAQJDQALAIkcAA==.Latro:BAACLgAFFH8lAAMEAAUJVxKjFwDlAAAEAAUJVxKjFwDlAAAhAAIJOgS3CQB7AAAuAAQKfysAAwQACQlrHHEpADgCAAQACQlrHHEpADgCABYAAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8WAAIVAAYJpgVFyQC+AAAVAAYJpgVFyQC+AAAAAA==.Leginer:BAABLgAECn8YAAIbAAYJXBGCkwD5AAAbAAYJXBGCkwD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECgYJCAAAAA==.Lepo:BAABLgAECn8hAAMOAAkJ4AspHwCdAQAOAAkJ4AspHwCdAQAiAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIcAAUJ1hV5IQBMAQAcAAUJ1hV5IQBMAQAuAAQKfykAAxwABwn/GqQ8AKEBABwABwn/GqQ8AKEBABkAAQmNFb6HADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8SAAIDAAQJkQzwDQDbAAADAAQJkQzwDQDbAAAuAAQKf0UAAwMACQn6HMMNAIMCAAMACQn1HMMNAIMCABIACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn86AAQZAAkJWByKDwBnAgAZAAkJWxuKDwBnAgAaAAgJ7BExKAAWAQAdAAUJzw+WKADLAAAAAA==.Luvalee:BAAALgAECgQJBAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCggJFQAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgUJBQABLgAFFAQJDQALAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn82AAMFAAkJkgsUHAA2AQAFAAkJRQkUHAA2AQAIAAIJmwtPGQBrAAAAAA==.Maladroit:BAAALgAECgUJBQABLgAFFAQJDQALAIkcAA==.Maldus:BAACLgAFFH8NAAILAAQJiRyNEgBTAQALAAQJiRyNEgBTAQAuAAQKfyoAAgsACQnyHk8LAJsCAAsACQnyHk8LAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8QAAIjAAQJRx2dBQDvAAAjAAQJRx2dBQDvAAAuAAQKfyEAAiMACQngILoEANQCACMACQngILoEANQCAAAA.Mam:BAAALgADCgcJBwAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAOANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAIJCQANACQKAA==.Marloak:BAABLgAECn8bAAMcAAcJ8hDOTwBPAQAcAAcJ8hDOTwBPAQAZAAIJhwbChQA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIeAAYJpQQ+bQChAAAeAAYJpQQ+bQChAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJEwAAAA==.Mccormick:BAAALgAECgQJBAABLgAFFAQJDQALAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAGABESAA==.Metaocalypse:BAABLgAECn8WAAMKAAkJARZHBwAiAQAKAAcJiRlHBwAiAQAMAAIJawv9BgBlAAAAAA==.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mirrah:BAAALgAECgEJAQAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mistyfisty:BAAALgAECgEJAQAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgAECgEJAwAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAXAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nessy:BAAALgAFFAIJAgABLgAFFAQJEgADAJEMAA==.Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBNXEgChAQAFAAkJIBNXEgChAQAAAA==.Nightshadye:BAACLgAFFH8hAAIMAAUJ/RBEIQDfAAAMAAUJ/RBEIQDfAAAuAAQKfyMAAgwACQl7Dx0dAGEBAAwACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAFFAIJBgAbAGEMAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIZAAYJIA5bUADMAAAZAAYJIA5bUADMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xFaOgC8AAABAAMJ9xFaOgC8AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8dAAIGAAYJwRwHLgC2AQAGAAYJwRwHLgC2AQAuAAQKfyAAAgYACAmxId0bAAcDAAYACAmxId0bAAcDAAAA.',
Om='Ombos:BAACLgAFFH8RAAMRAAQJxx9aBAAiAQARAAQJxx9aBAAiAQADAAQJ5QSeTgCUAAAuAAQKf0QAAxEACQl7IV8DABMDABEACQl7IV8DABMDAAMABwm5FiktAIcBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8vAAICAAkJfAorAwD8AAACAAkJfAorAwD8AAAAAA==.',
Oz='Ozrog:BAAALgAECgIJAwABLgAFFAUJFAAbANwPAA==.',
Pa='Palapinga:BAAALgAECgEJAgABLgAECgcJDAAXAAAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAFFAEJAQAAAA==.Pandahalf:BAAALgAECgQJDAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8aAAIZAAcJtA+7NgA7AQAZAAcJtA+7NgA7AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAXAAAAAA==.Pheldorai:BAABLgAECn8hAAMVAAkJXBR4AwB1AQAVAAkJXBR4AwB1AQAkAAEJdQQJNgAtAAABLgABCgMJAQAXAAAAAA==.Pheldrid:BAABLgAECn8eAAMJAAkJiCBUBwD6AgAJAAkJiCBUBwD6AgALAAEJfweOjQAtAAABLgABCgMJAQAXAAAAAA==.Phàntoms:BAABLgAECn8ZAAIUAAYJoxfCGAAOAQAUAAYJoxfCGAAOAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAUJJQAEAFcSAA==.',
Pu='Puma:BAABLgAECn8mAAIaAAgJZQ+LJwAbAQAaAAgJZQ+LJwAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIdAAcJrw1SHwANAQAdAAcJrw1SHwANAQAAAA==.',
Qu='Quayle:BAAALgAECgUJBQABLgAECgcJHgAfAA0OAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGFBwDgAgADAAkJxSGFBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIJAAUJOgtOFQAXAQAJAAUJOgtOFQAXAQAuAAQKfx0AAgkACQmEDdk4AFgBAAkACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn83AAIBAAkJ2B+DCAATAwABAAkJ2B+DCAATAwAAAA==.Rajun:BAAALgAECgEJBAAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAACLgAFFH8GAAIcAAIJ6QxgEwBiAAAcAAIJ6QxgEwBiAAAuAAQKfx4AAxwACQl4Hi4eAFQCABwACAlMHi4eAFQCAB0AAglrFHMIAEIAAAAA.Razelda:BAAALgAECgYJEwAAAA==.Razelka:BAABLgAECn8gAAIYAAkJmhF2JADRAQAYAAkJmhF2JADRAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIGAAkJQRPyVADeAQAGAAkJQRPyVADeAQAAAA==.Repunzel:BAABLgAECn8vAAIIAAkJBgt+CAAkAQAIAAkJBgt+CAAkAQAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8UAAIGAAUJfw9mYgAdAQAGAAUJfw9mYgAdAQAuAAQKfy8AAgYACQnuFU9PAO4BAAYACQnuFU9PAO4BAAAA.Rozco:BAAALgAECgcJEgAAAA==.',
Ru='Rubmywolf:BAABLgAECn8lAAIEAAgJjxnWOwDwAQAEAAgJjxnWOwDwAQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAUJFAAaAHsTAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8uAAIEAAkJsBdzJgBHAgAEAAkJsBdzJgBHAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwABLgAECgMJAwAXAAAAAA==.Shadowmisty:BAAALgAECgEJAQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJDQAXAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgkJNwAFAJUKAA==.Shaure:BAAALgAECgEJAQAAAA==.Shevah:BAABLgAECn8XAAIdAAkJghGlFgBiAQAdAAkJghGlFgBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgUJDQAXAAAAAA==.',
Si='Sid:BAACLgAFFH8YAAIGAAcJkB8cEwCAAQAGAAcJkB8cEwCAAQAuAAQKfzAAAgYACQm9JG8NAA4DAAYACQm9JG8NAA4DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8QAAIGAAQJPxL5FQAfAQAGAAQJPxL5FQAfAQAuAAQKfzoAAgYACQmHHcAoAHcCAAYACQmHHcAoAHcCAAAA.',
So='Sophié:BAAALgAECgYJEgABLgAFFAQJDQALAIkcAA==.Souxie:BAAALgAECgQJEQAAAA==.',
Sp='Sprout:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgAECgkJBgAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Stonetotem:BAAALgAECgMJAwAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQPTjgB8AAABAAYJLQPTjgB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8jAAIVAAgJygTNsgDgAAAVAAgJygTNsgDgAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQAAAA==.Synapse:BAABLgAECn8eAAICAAcJ5hBDPQALAQACAAcJ5hBDPQALAQAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIKAAkJ8xYqLQBLAgAKAAkJ8xYqLQBLAgAAAA==.',
Ta='Taali:BAABLgAECn8mAAIIAAgJZgyrmABEAQAIAAgJZgyrmABEAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn85AAIiAAkJOQ3qCQCHAQAiAAkJOQ3qCQCHAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIWAAgJax1XCAD5AQAWAAgJax1XCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIeAAkJDBurFQA6AgAeAAkJDBurFQA6AgAAAA==.Thomasten:BAACLgAFFH8XAAMgAAUJ3ySqCQBuAQAgAAQJ3ySqCQBuAQAbAAUJphh/UAD7AAAuAAQKfyUABCAACAk+Iz8TADwCACAACAm0ID8TADwCABMABQnrIV0OAGsBABsAAQmDARpCAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAcJFwAgAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECggJDQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAUJJQAEAFcSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8UAAIaAAUJexPyBgDAAAAaAAUJexPyBgDAAAAuAAQKfy8AAhoACQkfIKMEAMwCABoACQkfIKMEAMwCAAAA.Tricksibobby:BAABLgAECn8lAAQZAAgJ3SHPFQAhAgAZAAcJGSHPFQAhAgAcAAgJihjJOQCuAQAdAAIJOBuhMACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAXAAAAAA==.Tylèr:BAACLgAFFH8XAAMgAAUJmRujDABGAQAgAAUJDRujDABGAQATAAEJ+AjjEgAzAAAuAAQKf0YABCAACQmhH9MHALICACAACQmhH9MHALICABMAAQl4FFUyADoAABsAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAACLgAFFH8FAAIlAAMJlgjiBwBZAAAlAAMJlgjiBwBZAAAuAAQKfzAAAiUACQkeFWAKABMCACUACQkeFWAKABMCAAAA.',
Um='Umami:BAABLgAECn8mAAIQAAkJgRVeMgDqAQAQAAkJgRVeMgDqAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn83AAIEAAkJqhbhNAAJAgAEAAkJqhbhNAAJAgAAAA==.',
Ve='Vermithrax:BAAALgAECgYJCgABLgAFFAIJBgAbAGEMAA==.',
Vi='Viddar:BAABLgAECn8jAAITAAkJYx3CBABsAgATAAkJYx3CBABsAgAAAA==.Viroqua:BAACLgAFFH8WAAILAAcJjBC+EABkAQALAAcJjBC+EABkAQAuAAQKfzIAAgsACAkDGRAQAIUCAAsACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAIJAwABLgAECgkJGQAmAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAFFAIJBgAbAGEMAA==.Winkelsmom:BAABLgAECn8vAAUZAAkJkhPlHgDRAQAZAAkJwxLlHgDRAQAcAAYJ3QpodADYAAAaAAIJ3hNuBwB3AAAdAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8gAAMlAAcJJBoBEQCjAQAlAAcJJBoBEQCjAQAQAAYJvRLNWwBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn86AAIQAAkJtBlcHQBiAgAQAAkJtBlcHQBiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RW7HgAkAgABAAkJ4RW7HgAkAgANAAEJAACqsAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAIKAAcJ+RhrWAC8AQAKAAcJ+RhrWAC8AQAAAA==.',
Za='Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zendiesel:BAAALgAECgYJBwABLgAECggJMwAWAGsdAA==.Zenogias:BAABLgAECn8jAAIGAAgJxxUFfACAAQAGAAgJxxUFfACAAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAUJFAAaAHsTAA==.Zote:BAAALgADCgkJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAACLgAFFH8GAAImAAIJihd0OACKAAAmAAIJihd0OACKAAAuAAQKf0AAAiYACQlzIfgGABwDACYACQlzIfgGABwDAAAA.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAEAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMEAAMJ4Q7jaQDRAAAEAAMJ1gzjaQDRAAAhAAEJOxdOMABSAAAAAA==.',
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
