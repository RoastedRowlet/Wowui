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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Hunter-BeastMastery','Paladin-Protection','Mage-Frost','Mage-Arcane','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','Druid-Guardian','DemonHunter-Devourer','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','Unknown-Unknown','DemonHunter-Havoc','Hunter-Survival','Rogue-Outlaw','Warrior-Protection','Warlock-Affliction','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-06-20',data={Aa='Aatra:BAAALgAECgIJAgAAAA==.',
Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAACLgAFFH8FAAIBAAQJ+AnVOADDAAABAAQJ+AnVOADDAAAuAAQKfyUAAwEACQnpFv4XAP8BAAEACQnpFv4XAP8BAAIABwkcDistAHgBAAEuAAUUBgkaAAMAIiEA.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAABLgAECn8VAAIEAAcJKBtOQgDbAQAEAAcJKBtOQgDbAQAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgUJBwAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn83AAIFAAkJlQq6HQAnAQAFAAkJlQq6HQAnAQAAAA==.Arkadias:BAAALgAECgEJAQAAAA==.Arthea:BAABLgAECn8WAAMGAAcJCAh+xAADAQAGAAcJyQZ+xAADAQAHAAUJ0QWdEQCpAAAAAA==.',
As='Asmmina:BAABLgAECn8lAAIEAAkJDgtjUACxAQAEAAkJDgtjUACxAQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8kAAIIAAgJMQxemgBBAQAIAAgJMQxemgBBAQAAAA==.',
Az='Azalan:BAAALgAECgEJAQAAAA==.Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgQJBAAAAA==.Badgerbadgur:BAAALgAECgEJAQAAAA==.Bagelqt:BAABLgAECn8rAAIJAAkJghJMIADAAQAJAAkJghJMIADAAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIKAAkJcSJsCQAkAwAKAAkJcSJsCQAkAwAAAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJBAABLgAFFAQJDQALAIkcAA==.Bastiecats:BAAALgADCgcJBwAAAA==.',
Be='Beatrixx:BAAALgAECggJDQAAAA==.Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8LAAIIAAMJNR+hYQDsAAAIAAMJNR+hYQDsAAAuAAQKfxcAAggACQluIWouAEcCAAgACQluIWouAEcCAAAA.Bllacktotem:BAAALgAFFAIJAgAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8lAAIMAAkJvR4CBwCtAgAMAAkJvR4CBwCtAgAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoREABLAgACAAkJsRoREABLAgANAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAKAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.Brubuus:BAAALgAECgMJBQAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMOAAkJeRY+GADYAQAOAAkJeRY+GADYAQAPAAIJdQupHQA/AAABLgAFFAMJBQAEAOEOAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAABLgAECn8XAAIQAAkJMAqfVgBcAQAQAAkJMAqfVgBcAQAAAA==.Cheese:BAABLgAECn8cAAMCAAcJLRtSGgDeAQACAAcJLRtSGgDeAQABAAQJPxI7agDYAAAAAA==.Cheesemix:BAABLgAECn8bAAIQAAYJXg1LbgARAQAQAAYJXg1LbgARAQABLgAECgkJRgAQAMYhAA==.Chesleigh:BAAALgAECgQJEQAAAA==.',
Ci='Cinderlight:BAABLgAECn8uAAIIAAkJ8BEmWADDAQAIAAkJ8BEmWADDAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCQAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAFFAQJCQAGAKIRAA==.Crilynn:BAACLgAFFH8TAAIGAAUJERIRYQAfAQAGAAUJERIRYQAfAQAuAAQKfyQAAgYACQlOGKI2AD4CAAYACQlOGKI2AD4CAAAA.Crispycrittr:BAABLgAECn8eAAMRAAgJiAdbJQBMAQARAAgJiAdbJQBMAQASAAEJwwL6KgAiAAAAAA==.Crotchcriter:BAAALgAECgEJAgAAAA==.Cryhavoc:BAABLgAECn8lAAITAAgJLBOMDACMAQATAAgJLBOMDACMAQAAAA==.',
Cy='Cyssor:BAAALgAECgQJCQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBQAAAA==.Dancingfox:BAAALgAECgQJDwAAAA==.Dathdeath:BAABLgAECn8jAAIUAAgJXA0nFwAeAQAUAAgJXA0nFwAeAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.Dezzii:BAAALgAECgYJBgAAAA==.',
Di='Diddel:BAAALgADCgEJAQAAAA==.Dillapuss:BAAALgADCgMJBAAAAA==.Dimitri:BAAALgAECgEJAgAAAA==.Dirtnappzz:BAAALgAECgUJBQAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIKAAMJ7g1bLADqAAAKAAMJ7g1bLADqAAAuAAQKfygAAgoACAm8IugYAOcCAAoACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAECgcJCwABLgAFFAQJCQAGAKIRAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgAECgEJBAAAAA==.Dotdotded:BAAALgAECgkJCwAAAA==.Dotsomahan:BAABLgAECn8YAAIVAAkJWA/IXgCDAQAVAAkJWA/IXgCDAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIWAAkJSRbmCQDVAQAWAAkJSRbmCQDVAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8hAAIXAAcJwggCUQAFAQAXAAcJwggCUQAFAQAAAA==.Druidfaime:BAAALgAECgYJEAAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgAECgEJAQAAAA==.',
El='Elementalhro:BAAALgAECgEJAQAAAA==.Elise:BAABLgAECn8XAAIYAAcJGB81FwATAgAYAAcJGB81FwATAgAAAA==.Ellzik:BAABLgAECn8UAAMZAAcJ5wt8MwDbAAAZAAcJ5wt8MwDbAAAYAAQJxAORawBzAAAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgUJCgABLgAFFAQJDQALAIkcAA==.',
Fa='Falorien:BAABLgAECn8lAAIGAAgJwBI7cACZAQAGAAgJwBI7cACZAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAACLgAFFH8FAAIaAAIJYQxZgAB+AAAaAAIJYQxZgAB+AAAuAAQKfycAAhoACQnoFNVIAKwBABoACQnoFNVIAKwBAAAA.',
Fl='Flamingpax:BAAALgAECgcJCwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAQJEwAGAH8PAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAACLgAFFH8FAAIKAAMJ8xwhgQAFAQAKAAMJ8xwhgQAFAQAuAAQKfzAAAgoACQkLIfkPAOwCAAoACQkLIfkPAOwCAAAA.Fluffinhigh:BAABLgAECn8pAAUZAAkJ8xo1CQBYAgAZAAkJNho1CQBYAgAYAAYJqRdyNABHAQAbAAMJ9RXEggCzAAAcAAQJZxJzMACfAAABLgAFFAMJBQAKAPMcAA==.Fluffinkai:BAAALgAECgQJBwABLgAFFAMJBQAKAPMcAA==.Fluffybúnny:BAAALgAECgQJEQAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJNwAFAJUKAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Fu='Furrious:BAAALgAECgQJBAAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIVAAgJJg1lgQA2AQAVAAgJJg1lgQA2AQAAAA==.',
Gi='Gillneddra:BAAALgAECgIJAgAAAA==.Giorgina:BAACLgAFFH8KAAIdAAMJ5Q8SNQC6AAAdAAMJ5Q8SNQC6AAAuAAQKfycAAh0ACAnXF5onALABAB0ACAnXF5onALABAAAA.',
Gl='Glasc:BAABLgAECn8eAAMeAAcJDQ7zNABCAQAeAAcJDQ7zNABCAQALAAYJ7Q2nRAD8AAAAAA==.',
Gn='Gnowances:BAAALgADCgkJEgAAAA==.',
Go='Goobynuk:BAACLgAFFH8FAAIGAAIJ3AospgCFAAAGAAIJ3AospgCFAAAuAAQKfyAAAgYACQkqGck2AD0CAAYACQkqGck2AD0CAAAA.Gornade:BAAALgAECgEJAQABLgAFFAQJEwAZAHsTAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAMJBQAEAOEOAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMOAAcJ1x2XGQA3AgAOAAcJ3RyXGQA3AgAPAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAECgcJCQABLgAFFAUJIgAEAFcSAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAfAAAAAA==.',
It='Itzli:BAACLgAFFH8LAAIWAAQJmCC9DgB0AQAWAAQJmCC9DgB0AQAuAAQKfykAAhYACQnzIb8DAIoCABYACQnzIb8DAIoCAAEuAAUUBAkNAAsAiRwA.',
Iv='Ivee:BAAALgAECgcJCAABLgAFFAQJDQALAIkcAA==.',
Ix='Ixtli:BAAALgAECgYJCAABLgAFFAQJDQALAIkcAA==.',
Ja='Janner:BAAALgAECgUJDAAAAA==.Jaser:BAAALgAECgUJDQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgMJDAAAAA==.Jesdei:BAAALgAECgYJEgAAAA==.',
Jg='Jgwentworth:BAAALgAECgcJBwABLgAFFAUJDQACAAAJAA==.',
Jo='Jojen:BAABLgAECn8pAAMJAAkJuhiuHQDXAQAJAAkJuhiuHQDXAQALAAQJ+ArTZACIAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgAECgEJAgAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgQJCQAAAA==.Kavix:BAABLgAECn8mAAIbAAkJSxbeIwAsAgAbAAkJSxbeIwAsAgAAAA==.Kayos:BAACLgAFFH8TAAIaAAQJ3A9/CQC1AAAaAAQJ3A9/CQC1AAAuAAQKfygAAxoACQn8FJ08ANUBABoACQktFJ08ANUBACAABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAQJEwAaANwPAA==.Kelzexx:BAABLgAECn8qAAILAAkJ4hFEIADEAQALAAkJ4hFEIADEAQAAAA==.',
Kh='Khalas:BAAALgAECgEJAQAAAA==.Khorne:BAABLgAECn8pAAIMAAkJrwpIJgAhAQAMAAkJrwpIJgAhAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAMJBAABLgAFFAQJDQALAIkcAA==.Kimed:BAAALgAECgcJCQAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Kolcon:BAAALgAECgEJAQABLgAECggJDwAfAAAAAA==.Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krackle:BAAALgADCgUJBQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJBAAAAA==.',
Ku='Kula:BAABLgAECn8iAAIEAAgJRw+iYgCBAQAEAAgJRw+iYgCBAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgQJDwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAFFAQJCQAGAKIRAA==.',
La='Largetha:BAAALgAECgQJBAABLgAFFAQJDQALAIkcAA==.Latro:BAACLgAFFH8iAAMEAAUJVxI6QAAtAQAEAAUJVxI6QAAtAQAhAAIJOgQOAwB/AAAuAAQKfysAAwQACQlrHHMpADgCAAQACQlrHHMpADgCABYAAQkIBcqSACcAAAAA.',
Le='Leenex:BAABLgAECn8VAAIVAAYJhgVHyQC+AAAVAAYJhgVHyQC+AAAAAA==.Leginer:BAABLgAECn8XAAIaAAYJXA6AkwD5AAAaAAYJXA6AkwD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Leguku:BAAALgAECgEJAQAAAA==.Lemiranas:BAAALgAECgYJCAAAAA==.Lepo:BAABLgAECn8hAAMOAAkJ4AsoHwCdAQAOAAkJ4AsoHwCdAQAiAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8dAAIbAAUJ1hV/IQBMAQAbAAUJ1hV/IQBMAQAuAAQKfykAAxsABwn/Gqc8AKEBABsABwn/Gqc8AKEBABgAAQmNFbyHADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8OAAIDAAQJkQwHNwDoAAADAAQJkQwHNwDoAAAuAAQKf0UAAwMACQn6HMUNAIMCAAMACQn1HMUNAIMCABIACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn84AAQYAAkJWByIDwBnAgAYAAkJWxuIDwBnAgAZAAgJ7BEyKAAWAQAcAAUJzw+UKADLAAAAAA==.Luvalee:BAAALgAECgQJBAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCggJFAAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgUJBQABLgAFFAQJDQALAIkcAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn80AAMFAAkJagkUHAA2AQAFAAkJRQkUHAA2AQAIAAIJ6AKiDQBQAAAAAA==.Maladroit:BAAALgAECgUJBQABLgAFFAQJDQALAIkcAA==.Maldus:BAACLgAFFH8NAAILAAQJiRyMEgBTAQALAAQJiRyMEgBTAQAuAAQKfyoAAgsACQnyHlALAJsCAAsACQnyHlALAJsCAAAA.Malinore:BAAALgADCgUJBQAAAA==.Mallacath:BAACLgAFFH8NAAIjAAQJRx3xDgBBAQAjAAQJRx3xDgBBAQAuAAQKfyEAAiMACQngILwEANQCACMACQngILwEANQCAAAA.Mam:BAAALgADCgcJBwAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQAOANcdAA==.Mantequilla:BAAALgADCgIJAgABLgAFFAIJBQANACQKAA==.Marloak:BAABLgAECn8ZAAMbAAYJvxHRTwBPAQAbAAYJvxHRTwBPAQAYAAIJhwa/hQA+AAAAAA==.Mathilak:BAAALgAECgEJAQAAAA==.Mazzkal:BAABLgAECn8UAAIdAAYJpQQ8bQChAAAdAAYJpQQ8bQChAAAAAA==.',
Mc='Mcbain:BAAALgADCgcJEwAAAA==.Mccormick:BAAALgAECgMJAwABLgAFFAQJDQALAIkcAA==.',
Me='Merethyl:BAAALgAECgMJAwABLgAFFAUJEwAGABESAA==.Metaocalypse:BAABLgAECn8VAAMKAAkJIxRVBADPAAAKAAcJCxdVBADPAAAMAAIJawsDAwBnAAAAAA==.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Missuswor:BAAALgAECgEJAQAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgAECgEJAwAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAfAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAwAAAA==.Nathali:BAAALgAECgYJCQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIFAAkJIBNXEgChAQAFAAkJIBNXEgChAQAAAA==.Nightshadye:BAACLgAFFH8dAAIMAAQJJBBKIQDfAAAMAAQJJBBKIQDfAAAuAAQKfyMAAgwACQl7Dx0dAGEBAAwACQl7Dx0dAGEBAAAA.Nirazen:BAAALgAECgcJBwABLgAFFAIJBQAaAGEMAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIYAAYJIA5UUADMAAAYAAYJIA5UUADMAAAAAA==.Notmonk:BAABLgAFFH8FAAIBAAMJ9xFYOgC8AAABAAMJ9xFYOgC8AAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCQAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8cAAIGAAYJwRwlLgC2AQAGAAYJwRwlLgC2AQAuAAQKfyAAAgYACAmxId0bAAcDAAYACAmxId0bAAcDAAAA.',
Om='Ombos:BAACLgAFFH8LAAMRAAQJThlNGgDyAAARAAMJfhtNGgDyAAADAAMJHQWcTgCUAAAuAAQKf0QAAxEACQl7IV8DABMDABEACQl7IV8DABMDAAMABwm5FigtAIcBAAAA.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Orticia:BAAALgADCgUJBQAAAA==.Ortinchi:BAABLgAECn8oAAICAAkJVQpIAQDnAAACAAkJVQpIAQDnAAAAAA==.',
Oz='Ozrog:BAAALgAECgIJAwABLgAFFAQJEwAaANwPAA==.',
Pa='Palapinga:BAAALgAECgEJAgABLgAECgcJDAAfAAAAAA==.Pallypocket:BAAALgAFFAMJAwAAAA==.Pandacakes:BAAALgAECgYJCQAAAA==.Pandahalf:BAAALgAECgQJCQAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAABLgAECn8aAAIYAAcJtA+4NgA7AQAYAAcJtA+4NgA7AQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAfAAAAAA==.Pheldorai:BAABLgAECn8bAAMVAAkJBBG8PgDhAQAVAAkJBBG8PgDhAQAkAAEJdQQJNgAtAAABLgABCgMJAQAfAAAAAA==.Pheldrid:BAABLgAECn8eAAMJAAkJiCBUBwD6AgAJAAkJiCBUBwD6AgALAAEJfweHjQAtAAABLgABCgMJAQAfAAAAAA==.Phàntoms:BAABLgAECn8ZAAIUAAYJoxfCGAAOAQAUAAYJoxfCGAAOAQAAAA==.',
Pr='Protector:BAAALgAECgYJEwABLgAFFAUJIgAEAFcSAA==.',
Pu='Puma:BAABLgAECn8mAAIZAAgJZQ+OJwAbAQAZAAgJZQ+OJwAbAQAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIcAAcJrw1RHwANAQAcAAcJrw1RHwANAQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgcJHgAeAA0OAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSGGBwDgAgADAAkJxSGGBwDgAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8RAAIJAAUJOgtOFQAXAQAJAAUJOgtOFQAXAQAuAAQKfx0AAgkACQmEDdk4AFgBAAkACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn81AAIBAAkJ2B+FCAATAwABAAkJ2B+FCAATAwAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAACLgAFFH8FAAIbAAIJ6QyzbQA8AAAbAAIJ6QyzbQA8AAAuAAQKfxsAAxsACAnMHjAeAFQCABsABwmnHjAeAFQCABwAAQk8EhFLAEMAAAAA.Razelda:BAAALgAECgYJEwAAAA==.Razelka:BAABLgAECn8gAAIXAAkJmhF3JADRAQAXAAkJmhF3JADRAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIGAAkJQRPyVADeAQAGAAkJQRPyVADeAQAAAA==.Repunzel:BAABLgAECn8oAAIIAAkJ6whUBADoAAAIAAkJ6whUBADoAAAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8TAAIGAAQJfw/5DACrAAAGAAQJfw/5DACrAAAuAAQKfy8AAgYACQnuFVBPAO4BAAYACQnuFVBPAO4BAAAA.Rozco:BAAALgAECgYJEQAAAA==.',
Ru='Rubmywolf:BAABLgAECn8lAAIEAAgJjxnWOwDwAQAEAAgJjxnWOwDwAQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAQJEwAZAHsTAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8sAAIEAAkJ+RZ0JgBHAgAEAAkJ+RZ0JgBHAgAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAABLgAECggJDQAfAAAAAA==.Shamrok:BAEALgAECgEJBQABLgAECgkJNwAFAJUKAA==.Shevah:BAABLgAECn8XAAIcAAkJghGjFgBiAQAcAAkJghGjFgBiAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgcJDwAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgQJCQAfAAAAAA==.',
Si='Sid:BAACLgAFFH8YAAIGAAcJkB8cEwCAAQAGAAcJkB8cEwCAAQAuAAQKfzAAAgYACQm9JHMNAA4DAAYACQm9JHMNAA4DAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgAECgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgQJBAAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAACLgAFFH8JAAIGAAQJohGjXgAjAQAGAAQJohGjXgAjAQAuAAQKfzoAAgYACQmHHcMoAHcCAAYACQmHHcMoAHcCAAAA.',
So='Sophié:BAAALgAECgYJDgABLgAFFAQJDQALAIkcAA==.Souxie:BAAALgAECgQJEQAAAA==.',
Sp='Sprout:BAAALgAECgEJAQAAAA==.',
St='Starlost:BAAALgAECgkJBgAAAA==.Starnova:BAAALgAECgYJEQAAAA==.Stãr:BAABLgAECn8XAAIBAAYJLQPNjgB8AAABAAYJLQPNjgB8AAAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8jAAIVAAgJygTOsgDgAAAVAAgJygTOsgDgAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Sylvas:BAAALgAECgEJAQAAAA==.Synapse:BAABLgAECn8cAAICAAYJ9w9DPQALAQACAAYJ9w9DPQALAQAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIKAAkJ8xYqLQBLAgAKAAkJ8xYqLQBLAgAAAA==.',
Ta='Taali:BAABLgAECn8mAAIIAAgJZgytmABEAQAIAAgJZgytmABEAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn83AAIiAAkJMwzqCQCHAQAiAAkJMwzqCQCHAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8zAAIWAAgJax1XCAD5AQAWAAgJax1XCAD5AQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIdAAkJDBusFQA6AgAdAAkJDBusFQA6AgAAAA==.Thomasten:BAACLgAFFH8WAAMgAAUJ3ySpCQBuAQAgAAQJ3ySpCQBuAQAaAAUJUxOOUAD7AAAuAAQKfyUABCAACAk+Iz8TADwCACAACAm0ID8TADwCABMABQnrIV0OAGsBABoAAQmDARVCAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAcJFgAgAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECggJDQAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAUJIgAEAFcSAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8TAAIZAAQJexMwAgCzAAAZAAQJexMwAgCzAAAuAAQKfy8AAhkACQkfIKMEAMwCABkACQkfIKMEAMwCAAAA.Tricksibobby:BAABLgAECn8lAAQYAAgJ3SHOFQAhAgAYAAcJGSHOFQAhAgAbAAgJihjMOQCuAQAcAAIJOBuiMACfAAAAAA==.Tricksï:BAAALgAECgEJAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAfAAAAAA==.Tylèr:BAACLgAFFH8XAAMgAAUJmRuiDABGAQAgAAUJDRuiDABGAQATAAEJ+AjiEgAzAAAuAAQKf0YABCAACQmhH9MHALICACAACQmhH9MHALICABMAAQl4FFMyADoAABoAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8wAAIlAAkJHhVfCgATAgAlAAkJHhVfCgATAgAAAA==.',
Um='Umami:BAABLgAECn8mAAIQAAkJgRVbMgDqAQAQAAkJgRVbMgDqAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgYJDQAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn83AAIEAAkJqhbiNAAJAgAEAAkJqhbiNAAJAgAAAA==.',
Ve='Vermithrax:BAAALgAECgYJCgABLgAFFAIJBQAaAGEMAA==.',
Vi='Viddar:BAABLgAECn8jAAITAAkJYx3CBABsAgATAAkJYx3CBABsAgAAAA==.Viroqua:BAACLgAFFH8VAAILAAYJ9BC/EABkAQALAAYJ9BC/EABkAQAuAAQKfzIAAgsACAkDGRAQAIUCAAsACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECggJAgAAAA==.Vorren:BAAALgAECgUJBQAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAFFAIJAwABLgAECgkJGQAmAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgYJBgABLgAFFAIJBQAaAGEMAA==.Winkelsmom:BAABLgAECn8tAAUYAAkJCRPjHgDRAQAYAAkJwxLjHgDRAQAbAAYJ3QppdADYAAAZAAIJdQxIBABaAAAcAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8gAAMlAAcJJBoAEQCkAQAlAAcJJBoAEQCkAQAQAAYJvRLHWwBKAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCgAAAA==.',
Xa='Xarava:BAABLgAECn84AAIQAAkJbBlaHQBiAgAQAAkJbBlaHQBiAgAAAA==.',
Yo='Yogisa:BAABLgAECn9HAAMBAAkJ4RW7HgAkAgABAAkJ4RW7HgAkAgANAAEJAACmsAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8iAAIKAAcJ+RhoWAC8AQAKAAcJ+RhoWAC8AQAAAA==.',
Za='Zariganja:BAAALgADCgIJAgAAAA==.Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zendiesel:BAAALgAECgYJBwABLgAECggJMwAWAGsdAA==.Zenogias:BAABLgAECn8hAAIGAAcJrBUHfACAAQAGAAcJrBUHfACAAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zombieshaman:BAAALgAECgEJAQABLgAFFAQJEwAZAHsTAA==.Zote:BAAALgADCgkJDwAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAACLgAFFH8FAAImAAIJihdzOACKAAAmAAIJihdzOACKAAAuAAQKf0AAAiYACQlzIfgGABwDACYACQlzIfgGABwDAAAA.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAMJBQAEAOEOAA==.',
['ßú']='ßúg:BAABLgAFFH8FAAMEAAMJ4Q7jaQDRAAAEAAMJ1gzjaQDRAAAhAAEJOxdMMABSAAAAAA==.',
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
