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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Warlock-Demonology','Warrior-Fury','Druid-Balance','DemonHunter-Devourer','Druid-Guardian','Druid-Restoration','Druid-Feral','Shaman-Elemental','Priest-Discipline','Priest-Shadow','DemonHunter-Havoc','Rogue-Outlaw','Warrior-Protection','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-05-23',data={Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAABLgAECn8lAAMBAAkJ6Rb+FwD/AQABAAkJ6Rb+FwD/AQACAAcJHA4rLQB4AQABLgAFFAYJFgADABghAA==.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAFFAEJAQAAAA==.Amellwind:BAAALgAECgQJCAAAAA==.',
An='Anga:BAAALgADCggJFAAAAA==.',
Ar='Arana:BAAALgAECgIJAgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn8vAAIEAAkJLgq4GAApAQAEAAkJLgq4GAApAQAAAA==.Arkadias:BAAALgADCgEJAgAAAA==.Arthea:BAAALgAECgYJDQAAAA==.',
As='Asmmina:BAABLgAECn8jAAIFAAgJdQpHVQB1AQAFAAgJdQpHVQB1AQAAAA==.',
Au='Auren:BAAALgAECgEJAgAAAA==.',
Ay='Ayrwen:BAABLgAECn8ZAAIGAAcJyAqHkwArAQAGAAcJyAqHkwArAQAAAA==.',
Az='Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgAECgMJAwAAAA==.Bagelqt:BAABLgAECn8rAAIHAAkJghKGGQDXAQAHAAkJghKGGQDXAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIIAAkJcSIZBgAwAwAIAAkJcSIZBgAwAwABLgAFFAYJEAAJAD0hAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJAgABLgAECgkJJQAKAPMhAA==.',
Be='Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8JAAIGAAMJNR/rPgAKAQAGAAMJNR/rPgAKAQAuAAQKfxQAAgYACAkWIVI/AOkBAAYACAkWIVI/AOkBAAAA.Bllacktotem:BAAALgAECgEJAQAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8XAAILAAgJRBY1EwCuAQALAAgJRBY1EwCuAQAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8lAAMCAAkJsRoKDABcAgACAAkJsRoKDABcAgAMAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAIAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMNAAkJeRbUEgDpAQANAAkJeRbUEgDpAQAOAAIJdQupHQA/AAABLgAFFAIJAgAPAAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAAALgAFFAIJAwAAAA==.Cheese:BAAALgAECgYJEQAAAA==.Cheesemix:BAABLgAECn8WAAIQAAYJMw36WwARAQAQAAYJMw36WwARAQABLgAECgkJRQAQAMYhAA==.Chesleigh:BAAALgAECgIJBQAAAA==.',
Ci='Cinderlight:BAABLgAECn8nAAIGAAgJURLdXQCWAQAGAAgJURLdXQCWAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECggJCAAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECgkJMwAJAL0YAA==.Crilynn:BAACLgAFFH8NAAIJAAQJSQ7mUwAfAQAJAAQJSQ7mUwAfAQAuAAQKfyQAAgkACQlOGKwrAE0CAAkACQlOGKwrAE0CAAAA.Crispycrittr:BAABLgAECn8eAAMRAAgJiAdbJQBMAQARAAgJiAdbJQBMAQASAAEJwwI5JAAjAAAAAA==.Cryhavoc:BAABLgAECn8hAAITAAcJWRUuDABpAQATAAcJWRUuDABpAQAAAA==.',
Cy='Cyssor:BAAALgAECgIJBQAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBAAAAA==.Dancingfox:BAAALgAECgIJBQAAAA==.Dathdeath:BAABLgAECn8gAAIUAAcJPg9+EAAlAQAUAAcJPg9+EAAlAQAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgADCgEJBAAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIIAAMJ7g1bLADqAAAIAAMJ7g1bLADqAAAuAAQKfygAAggACAm8IugYAOcCAAgACAm8IugYAOcCAAAA.',
Do='Docken:BAAALgAECgcJCQABLgAECgkJMwAJAL0YAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgADCgEJAwAAAA==.Dotdotded:BAAALgAECgQJAwAAAA==.Dotsomahan:BAABLgAECn8WAAIVAAgJgw6ObQBJAQAVAAgJgw6ObQBJAQAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8mAAIKAAkJSRaoBwDmAQAKAAkJSRaoBwDmAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8dAAIWAAYJJwnETQDmAAAWAAYJJwnETQDmAAAAAA==.Druidfaime:BAAALgAECgMJBQAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Du='Dunce:BAAALgAECgEJAQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgADCgEJAQAAAA==.',
El='Elise:BAABLgAECn8VAAIXAAYJUB+gGwC+AQAXAAYJUB+gGwC+AQAAAA==.Ellzik:BAAALgAECgcJEQAAAA==.',
En='Enfuego:BAAALgADCgkJCQAAAA==.',
Es='Esthero:BAAALgAECgEJAQABLgAECgkJJQAKAPMhAA==.',
Fa='Falorien:BAABLgAECn8hAAIJAAcJHBNldgBvAQAJAAcJHBNldgBvAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8lAAIYAAgJXBQYUwBqAQAYAAgJXBQYUwBqAQAAAA==.',
Fl='Flamingpax:BAAALgAECgIJAwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAFFAMJBgAJABQPAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8pAAIIAAgJHCD5IABiAgAIAAgJHCD5IABiAgAAAA==.Fluffinhigh:BAABLgAECn8ZAAUZAAcJ2Rn+DgC4AQAZAAcJaBn+DgC4AQAXAAYJqReZKwBJAQAaAAMJ9RWFdgCyAAAbAAIJZQu3NwBDAAABLgAECggJKQAIABwgAA==.Fluffybúnny:BAAALgAECgIJBQAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJLwAEAC4KAA==.Freakadeek:BAAALgAECgUJBQAAAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8gAAIVAAgJJg01bQBKAQAVAAgJJg01bQBKAQAAAA==.',
Gi='Giorgina:BAABLgAECn8mAAIcAAgJYBb/JACTAQAcAAgJYBb/JACTAQAAAA==.',
Gl='Glasc:BAABLgAECn8XAAMdAAYJRQ7RMgAeAQAdAAYJRQ7RMgAeAQAeAAYJ7Q2KNwAOAQAAAA==.',
Gn='Gnowances:BAAALgADCgkJCwAAAA==.',
Go='Goobynuk:BAABLgAECn8YAAIJAAgJ7xcZUwDGAQAJAAgJ7xcZUwDGAQAAAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAFFAIJAgAPAAAAAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMNAAcJ1x2XGQA3AgANAAcJ3RyXGQA3AgAOAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.Hornet:BAAALgADCgkJCQAAAA==.',
Hu='Hurt:BAAALgAECgYJCAABLgAFFAQJEgAFAA0OAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgAECgEJAQAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAPAAAAAA==.',
It='Itzli:BAABLgAECn8lAAIKAAkJ8yHTAgCVAgAKAAkJ8yHTAgCVAgAAAA==.',
Iv='Ivee:BAAALgAECgcJCAABLgAECgkJJQAKAPMhAA==.',
Ix='Ixtli:BAAALgAECgYJBwABLgAECgkJJQAKAPMhAA==.',
Ja='Janner:BAAALgADCgkJEQAAAA==.Jaser:BAAALgAECgUJCQAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgIJBQAAAA==.Jesdei:BAAALgAECgMJBgAAAA==.',
Jo='Jojen:BAABLgAECn8pAAMHAAkJuhiUFwDqAQAHAAkJuhiUFwDqAQAeAAQJ+AryUQCUAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgADCgEJAQAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgIJAwAAAA==.Kavix:BAABLgAECn8mAAIaAAkJSxbKHgAtAgAaAAkJSxbKHgAtAgAAAA==.Kayos:BAACLgAFFH8GAAIYAAMJRAsdTwDMAAAYAAMJRAsdTwDMAAAuAAQKfygAAxgACQn8FJsxAOABABgACQktFJsxAOABAB8ABwlTE3IeAMsBAAAA.',
Ke='Kefan:BAAALgADCgEJAQABLgAFFAMJBgAYAEQLAA==.Kelzexx:BAABLgAECn8cAAIeAAcJtxPJKgBUAQAeAAcJtxPJKgBUAQAAAA==.',
Kh='Khalas:BAAALgADCgEJAwAAAA==.Khorne:BAABLgAECn8pAAILAAkJrwqDHgAwAQALAAkJrwqDHgAwAQAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAEJAQABLgAECgkJJQAKAPMhAA==.Kimed:BAAALgADCgkJCQAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.Krillian:BAAALgAECgEJAQAAAA==.',
Ku='Kula:BAABLgAECn8dAAIFAAcJQQ2qZwBGAQAFAAcJQQ2qZwBGAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgIJBQAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAECgkJMwAJAL0YAA==.',
La='Latro:BAACLgAFFH8SAAIFAAQJDQ4PMAAhAQAFAAQJDQ4PMAAhAQAuAAQKfysAAwUACQlrHJAeAEUCAAUACQlrHJAeAEUCAAoAAQkIBcqSACcAAAAA.',
Le='Leenex:BAAALgAECgYJCQAAAA==.Leginer:BAABLgAECn8YAAIYAAYJXA5YfwD5AAAYAAYJXA5YfwD5AAAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAABLgAECn8hAAMNAAkJ4AunGACtAQANAAkJ4AunGACtAQAgAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8ZAAIaAAUJdRRPFwBmAQAaAAUJdRRPFwBmAQAuAAQKfykAAxoABwn/Gnk1AKIBABoABwn/Gnk1AKIBABcAAQmNFZFxADsAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAACLgAFFH8FAAIDAAMJggydMwDFAAADAAMJggydMwDFAAAuAAQKfz8AAwMACQn6HJgLAIMCAAMACQn1HJgLAIMCABIACAmZEgYNAAoCAAAA.',
Lu='Lunden:BAABLgAECn8qAAQXAAgJuBPaKABaAQAXAAgJRQ/aKABaAQAZAAgJ7BG6HQAcAQAbAAUJzw8kHwDSAAAAAA==.Luvalee:BAAALgADCgcJCAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgMJDAAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdalena:BAAALgAECgEJAQABLgAECgkJJQAKAPMhAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8mAAIEAAgJ7QnSGgAUAQAEAAgJ7QnSGgAUAQAAAA==.Maldus:BAABLgAECn8qAAIeAAkJ8h5aCACqAgAeAAkJ8h5aCACqAgABLgAECgkJJQAKAPMhAA==.Mallacath:BAABLgAECn8cAAIhAAgJ9yGUBQCcAgAhAAgJ9yGUBQCcAgAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQANANcdAA==.Marloak:BAAALgAECgUJCAAAAA==.Mazzkal:BAAALgAECgYJEAAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Meekrob:BAAALgAECgEJAQABLgAFFAYJEAAJAD0hAA==.Methot:BAAALgAECgMJAwAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Morrok:BAAALgADCgEJAQAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgAECgEJAQAAAA==.Nathali:BAAALgAECgYJBwAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8mAAIEAAkJIBPYDgCoAQAEAAkJIBPYDgCoAQAAAA==.Nightshadye:BAACLgAFFH8OAAILAAQJJBC9FQD6AAALAAQJJBC9FQD6AAAuAAQKfyEAAgsACQl7Dx0dAGEBAAsACQl7Dx0dAGEBAAAA.Nirazen:BAAALgADCgcJBwABLgAECggJJQAYAFwUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIXAAYJIA4zQwDOAAAXAAYJIA4zQwDOAAAAAA==.',
Ny='Nymphoma:BAAALgAECggJCAAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8UAAIJAAQJvRiBPABKAQAJAAQJvRiBPABKAQAuAAQKfyAAAgkACAmxId0bAAcDAAkACAmxId0bAAcDAAAA.',
Om='Ombos:BAABLgAECn9CAAMRAAkJeyGyAgAXAwARAAkJeyGyAgAXAwADAAYJmxWqNAA2AQAAAA==.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Ortinchi:BAABLgAECn8dAAICAAcJRwknNwD5AAACAAcJRwknNwD5AAAAAA==.',
Pa='Palapinga:BAAALgAECgEJAgAAAA==.Pallypocket:BAAALgAECgYJBwAAAA==.Pandacakes:BAAALgAECgYJCAAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAAALgAECgcJEQAAAA==.Pheldor:BAAALgAECgcJCgABLgABCgMJAQAPAAAAAA==.Pheldorai:BAAALgAECggJEgABLgABCgMJAQAPAAAAAA==.Pheldrid:BAABLgAECn8eAAMHAAkJiCAWBQAOAwAHAAkJiCAWBQAOAwAeAAEJfwdIcwAvAAABLgABCgMJAQAPAAAAAA==.Phàntoms:BAABLgAECn8ZAAIUAAYJoxdrEgAMAQAUAAYJoxdrEgAMAQAAAA==.',
Pr='Protector:BAAALgAECgYJDgABLgAFFAQJEgAFAA0OAA==.',
Pu='Puma:BAABLgAECn8hAAIZAAcJdA/pIgDzAAAZAAcJdA/pIgDzAAAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8WAAIbAAcJrw32FgAkAQAbAAcJrw32FgAkAQAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgYJFwAdAEUOAA==.',
Ra='Radiance:BAABLgAECn8pAAIDAAkJxSH+BQDmAgADAAkJxSH+BQDmAgAAAA==.Raerias:BAAALgADCgYJBgAAAA==.Raevynn:BAACLgAFFH8LAAIHAAQJDQmeFADxAAAHAAQJDQmeFADxAAAuAAQKfx0AAgcACQmEDdk4AFgBAAcACQmEDdk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8nAAIBAAgJsB+DCgC9AgABAAgJsB+DCgC9AgAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECggJDwAAAA==.Rawrgrr:BAABLgAECn8YAAIaAAcJcB1sHgAvAgAaAAcJcB1sHgAvAgAAAA==.Razelda:BAAALgAECgYJDAAAAA==.Razelka:BAABLgAECn8eAAIWAAgJcxIDKACWAQAWAAgJcxIDKACWAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8lAAIJAAkJQROiQwD1AQAJAAkJQROiQwD1AQAAAA==.Repunzel:BAABLgAECn8dAAIGAAcJRAgFrwD+AAAGAAcJRAgFrwD+AAAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAACLgAFFH8GAAIJAAMJFA9RZQDrAAAJAAMJFA9RZQDrAAAuAAQKfy8AAgkACQnuFSxAAAACAAkACQnuFSxAAAACAAAA.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAABLgAECn8hAAIFAAcJ6xoMOwDIAQAFAAcJ6xoMOwDIAQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAFFAMJBgAZAJgRAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8fAAIFAAgJGBGJRACoAQAFAAgJGBGJRACoAQAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAAAAA==.Shamrok:BAEALgAECgEJBAABLgAECgkJLwAEAC4KAA==.Shevah:BAABLgAECn8XAAIbAAkJghEAEQBxAQAbAAkJghEAEQBxAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgYJDgAAAA==.Shyneeshay:BAAALgAECgMJAwABLgAECgQJBgAPAAAAAA==.',
Si='Sid:BAACLgAFFH8QAAIJAAYJPSEcEwCAAQAJAAYJPSEcEwCAAQAuAAQKfy4AAgkACQm9JF4VACgDAAkACQm9JF4VACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.',
Sk='Skagara:BAAALgADCgEJAQAAAA==.',
Sl='Slomo:BAAALgAECgMJAwAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn8zAAIJAAkJvRhYPAANAgAJAAkJvRhYPAANAgAAAA==.',
So='Sophié:BAAALgAECgYJCAABLgAECgkJJQAKAPMhAA==.Souxie:BAAALgAECgIJBQAAAA==.',
St='Starnova:BAAALgAECgYJCgAAAA==.Stãr:BAAALgAECgYJCwAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8gAAIVAAcJFgUbnQDtAAAVAAcJFgUbnQDtAAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAAALgAECgYJDQAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8jAAIIAAkJ8xZDIwBWAgAIAAkJ8xZDIwBWAgAAAA==.',
Ta='Taali:BAABLgAECn8hAAIGAAcJzgwakgAuAQAGAAcJzgwakgAuAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn8pAAIgAAgJPwrVCgBDAQAgAAgJPwrVCgBDAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8sAAIKAAgJjRwfCADaAQAKAAgJjRwfCADaAQAAAA==.Tellera:BAAALgAECgEJAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8nAAIcAAkJDBvDEABDAgAcAAkJDBvDEABDAgAAAA==.Thomasten:BAACLgAFFH8WAAMfAAUJ3yRVAwCeAQAfAAQJ3yRVAwCeAQAYAAUJUxOtNQAcAQAuAAQKfyUABB8ACAk+Iz8TADwCAB8ACAm0ID8TADwCABMABQnrIcwLAHIBABgAAQmDAR0RAREAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAUJFgAfAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgUJBgABLgAECgYJDAAPAAAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAQJEgAFAA0OAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAACLgAFFH8GAAIZAAMJmBE1EQCyAAAZAAMJmBE1EQCyAAAuAAQKfy8AAhkACQkfIDwDANMCABkACQkfIDwDANMCAAAA.Tricksibobby:BAABLgAECn8hAAQXAAcJVSF4HAC3AQAXAAYJTyB4HAC3AQAaAAcJdRcmMwCtAQAbAAIJOBu7JQCjAAAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tyledor:BAAALgAECgUJBAABLgAECgYJDAAPAAAAAA==.Tylèr:BAACLgAFFH8PAAMfAAQJ9BpEBgBkAQAfAAQJaRpEBgBkAQATAAEJ+AjHDAA2AAAuAAQKf0EABB8ACQl+H7MFALgCAB8ACQl+H7MFALgCABMAAQl4FOUoADwAABgAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8nAAIiAAgJ4RHGDQCdAQAiAAgJ4RHGDQCdAQAAAA==.',
Um='Umami:BAABLgAECn8mAAIQAAkJgRWcKADtAQAQAAkJgRWcKADtAQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgAECgUJBQAAAA==.',
Va='Vaelion:BAAALgAECgYJEgAAAA==.Vanillacream:BAABLgAECn8pAAIFAAgJjhWuQAC0AQAFAAgJjhWuQAC0AQAAAA==.',
Vi='Viddar:BAABLgAECn8jAAITAAkJYx11AwB7AgATAAkJYx11AwB7AgAAAA==.Viroqua:BAACLgAFFH8UAAIeAAUJrBKGEQA9AQAeAAUJrBKGEQA9AQAuAAQKfzIAAh4ACAkDGRAQAIUCAB4ACAkDGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vondah:BAAALgAECgIJAgAAAA==.Vorren:BAAALgADCgMJAwAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whiskylilith:BAAALgAECgEJAQABLgAECgkJGQAjAHoIAA==.Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgQJAQABLgAECggJJQAYAFwUAA==.Winkelsmom:BAABLgAECn8fAAQXAAgJrRF+JAB5AQAXAAgJrRF+JAB5AQAaAAUJtwvjgwCQAAAbAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8dAAMiAAYJYxk/EgBRAQAiAAYJYxk/EgBRAQAQAAYJvRKQSwBNAQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCQAAAA==.',
Xa='Xarava:BAABLgAECn8qAAIQAAgJtxiUIwALAgAQAAgJtxiUIwALAgAAAA==.',
Yo='Yogisa:BAABLgAECn86AAMBAAkJOhX5GAARAgABAAkJOhX5GAARAgAMAAEJAAA2nAAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8hAAIIAAcJ+RgTSgDBAQAIAAcJ+RgTSgDBAQAAAA==.',
Za='Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zenogias:BAABLgAECn8ZAAIJAAYJSRKjmAAtAQAJAAYJSRKjmAAtAQAAAA==.Zerokool:BAAALgAECgEJAgAAAA==.',
Zo='Zote:BAAALgADCgkJCQAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn8vAAIjAAgJlCPUCwCrAgAjAAgJlCPUCwCrAgAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAFFAIJAgAPAAAAAA==.',
['ßú']='ßúg:BAAALgAFFAIJAgAAAA==.',
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
