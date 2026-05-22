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

local lookup = {'Monk-Mistweaver','Monk-Windwalker','Evoker-Augmentation','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','DeathKnight-Unholy','Mage-Frost','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','DemonHunter-Vengeance','DeathKnight-Frost','Hunter-Marksmanship','Warrior-Fury','DemonHunter-Devourer','Warlock-Demonology','Shaman-Elemental','Priest-Shadow','Druid-Restoration','DemonHunter-Havoc','Rogue-Outlaw','Druid-Balance','Druid-Guardian','Druid-Feral','Warrior-Protection','Shaman-Enhancement','Paladin-Holy',}
local provider = {region='US',realm='Nesingwary',name='US',type='weekly',zone=46,date='2026-05-16',data={Ae='Aegrond:BAAALgAECgYJBgAAAA==.',
Af='Afu:BAABLgAECn8lAAMBAAkJ6Rb+FwD/AQABAAkJ6Rb+FwD/AQACAAcJHA4rLQB4AQABLgAFFAYJEgADAJgcAA==.',
Ai='Airoh:BAAALgADCgYJDAAAAA==.',
Al='Allunnadora:BAAALgADCgcJCgAAAA==.',
Am='Ameliadark:BAAALgAECgUJCwAAAA==.Amellwind:BAAALgAECgQJBQAAAA==.',
An='Anga:BAAALgADCggJEQAAAA==.',
Ar='Arana:BAAALgAECgIJAgAAAA==.Argonaut:BAAALgADCgcJEQAAAA==.Ariosto:BAEBLgAECn8vAAIEAAkJLgpPFQAoAQAEAAkJLgpPFQAoAQAAAA==.Arkadias:BAAALgADCgEJAgAAAA==.Arthea:BAAALgAECgUJDAAAAA==.',
As='Asmmina:BAABLgAECn8ZAAIFAAcJgwoZXwAvAQAFAAcJgwoZXwAvAQAAAA==.',
Ay='Ayrwen:BAAALgAECgYJEgAAAA==.',
Az='Azarit:BAAALgAECgUJCQAAAA==.',
Ba='Baby:BAAALgAECgQJBAAAAA==.Badgerbadger:BAAALgADCgkJDwAAAA==.Bagelqt:BAABLgAECn8jAAIGAAkJ3BDvGQCzAQAGAAkJ3BDvGQCzAQAAAA==.Bahlsytotems:BAAALgAECgYJDAAAAA==.Bajablaster:BAABLgAECn8wAAIHAAkJcCJvBAA4AwAHAAkJcCJvBAA4AwABLgAFFAUJDQAIABsgAA==.Baldis:BAAALgADCgYJBQAAAA==.Baldr:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.',
Be='Benafflock:BAAALgADCgYJBgAAAA==.Bestbagel:BAAALgADCgYJDgAAAA==.',
Bl='Bllackout:BAACLgAFFH8GAAIKAAMJ5h0zMQAVAQAKAAMJ5h0zMQAVAQAuAAQKfxQAAgoACAkVIdwxAPMBAAoACAkVIdwxAPMBAAAA.Bllacktotem:BAAALgAECgEJAQAAAA==.Bloodchylde:BAAALgADCggJDwAAAA==.Bloodhardt:BAABLgAECn8VAAILAAgJ+RWaEgBuAQALAAgJ+RWaEgBuAQAAAA==.Bloodlor:BAAALgADCgYJBgAAAA==.Bluekoolaid:BAABLgAECn8jAAMCAAgJ8hn+DwD9AQACAAgJ8hn+DwD9AQAMAAMJuAz5bACOAAAAAA==.',
Bo='Boromer:BAAALgAECgcJCQABLgAFFAMJCQAHAIUcAA==.',
Br='Brisingrfire:BAAALgAECgYJBwAAAA==.',
['Bû']='Bûg:BAABLgAECn8jAAMNAAkJeRbgDwDgAQANAAkJeRbgDwDgAQAOAAIJdgupHQA/AAAAAA==.',
Ce='Celasha:BAAALgADCggJCQAAAA==.',
Ch='Cheba:BAAALgAFFAIJAgAAAA==.Cheese:BAAALgAECgUJCQAAAA==.Cheesemix:BAABLgAECn8UAAIPAAYJ+AssVQD5AAAPAAYJ+AssVQD5AAABLgAECgkJMwAPACAgAA==.Chesleigh:BAAALgAECgIJAwAAAA==.',
Ci='Cinderlight:BAABLgAECn8kAAIKAAgJDRElUQCOAQAKAAgJDRElUQCOAQAAAA==.',
Co='Colonicus:BAAALgADCgYJBgAAAA==.Corvell:BAAALgAECgYJDQAAAA==.Cozyfog:BAAALgAECgcJBwAAAA==.',
Cr='Crakdorn:BAAALgADCgYJDAAAAA==.Creatini:BAAALgADCgcJBwABLgAECgkJMgAIAL4YAA==.Crilynn:BAACLgAFFH8JAAIIAAQJOw4qRgAqAQAIAAQJOw4qRgAqAQAuAAQKfyQAAggACQlQGEgjAFICAAgACQlQGEgjAFICAAAA.Crispycrittr:BAABLgAECn8eAAMQAAgJiAdbJQBMAQAQAAgJiAdbJQBMAQARAAEJwwLxHwAkAAAAAA==.Cryhavoc:BAABLgAECn8bAAISAAYJ5BWUDAA4AQASAAYJ5BWUDAA4AQAAAA==.',
Cy='Cyssor:BAAALgAECgIJAwAAAA==.',
Da='Dagget:BAAALgADCgIJAgAAAA==.Dalex:BAAALgAECgEJBAAAAA==.Dancingfox:BAAALgAECgIJAwAAAA==.Dathdeath:BAABLgAECn8aAAITAAYJeA+4DwD7AAATAAYJeA+4DwD7AAAAAA==.Davlindhag:BAAALgADCgYJCQAAAA==.',
De='Deaviad:BAAALgADCgYJBgAAAA==.',
Di='Dillapuss:BAAALgADCgEJAQAAAA==.Dimitri:BAAALgADCgEJBAAAAA==.',
Dk='Dkpik:BAACLgAFFH8GAAIHAAMJ7g1bLADqAAAHAAMJ7g1bLADqAAAuAAQKfygAAgcACAm2IugYAOcCAAcACAm2IugYAOcCAAAA.',
Do='Docken:BAAALgAECgYJBwABLgAECgkJMgAIAL4YAA==.Donavis:BAAALgADCgYJBgAAAA==.Doroga:BAAALgADCgEJAwAAAA==.Dotsomahan:BAAALgAECggJEgAAAA==.',
Dr='Draggard:BAAALgADCgYJBgAAAA==.Dragonkiller:BAABLgAECn8kAAIUAAcJFhYFDAAkAQAUAAcJFhYFDAAkAQAAAA==.Dragulla:BAAALgADCgEJAQAAAA==.Drandzug:BAABLgAECn8aAAIVAAYJjAixQwDkAAAVAAYJjAixQwDkAAAAAA==.Druidfaime:BAAALgADCgkJKQAAAA==.Druprincess:BAAALgADCgYJCQAAAA==.',
Dy='Dylanah:BAAALgAECgEJAQAAAA==.',
Ec='Ecclesia:BAAALgADCgEJAQAAAA==.',
El='Elise:BAAALgAECgYJEAAAAA==.Ellzik:BAAALgAECgYJCgAAAA==.',
Es='Esthero:BAAALgADCgcJCAABLgAFFAEJAQAJAAAAAA==.',
Fa='Falorien:BAABLgAECn8bAAIIAAYJphLuhQAxAQAIAAYJphLuhQAxAQAAAA==.',
Fe='Fearne:BAAALgADCgMJAwAAAA==.Felray:BAABLgAECn8lAAIWAAgJWxToRwBiAQAWAAgJWxToRwBiAQAAAA==.',
Fl='Flamingpax:BAAALgADCgkJEwAAAA==.Flashindevil:BAAALgAECgEJAQAAAA==.Floinygos:BAAALgAECgUJBgABLgAECgkJLwAIAO4VAA==.Florecita:BAAALgADCgIJAgAAAA==.Fluffinbunz:BAABLgAECn8pAAIHAAgJGyAqGQBuAgAHAAgJGyAqGQBuAgAAAA==.Fluffinhigh:BAAALgAECgYJDwABLgAECggJKQAHABsgAA==.Fluffybúnny:BAAALgAECgIJAwAAAA==.',
Fo='Foxyh:BAAALgADCgcJBwAAAA==.',
Fr='Frankenberry:BAEALgAECgMJBQABLgAECgkJLwAEAC4KAA==.',
Ga='Gally:BAAALgADCgEJAgAAAA==.Gargorg:BAAALgAECgYJDQAAAA==.',
Gh='Ghostremedy:BAAALgADCgYJDAAAAA==.Ghpwarlock:BAABLgAECn8eAAIXAAcJ9Az6dwAPAQAXAAcJ9Az6dwAPAQAAAA==.',
Gi='Giorgina:BAABLgAECn8lAAIYAAgJdxUTIgCBAQAYAAgJdxUTIgCBAQAAAA==.',
Gl='Glasc:BAAALgAECgYJEgAAAA==.',
Gn='Gnowances:BAAALgADCgIJAgAAAA==.',
Go='Goobynuk:BAABLgAECn8XAAIIAAgJnhZISADBAQAIAAgJnhZISADBAQAAAA==.',
Gr='Grapes:BAAALgADCgYJDgABLgAECgkJIwANAHkWAA==.Grigorii:BAAALgADCgEJAgAAAA==.Grimstone:BAABLgAECn8ZAAMNAAcJ1x2XGQA3AgANAAcJ3RyXGQA3AgAOAAYJQhhNCwB3AQAAAA==.',
Hi='Highgreen:BAAALgADCgEJAQAAAA==.Himeno:BAAALgAECgEJAgAAAA==.',
Ho='Hoofstafa:BAAALgADCgYJCAAAAA==.',
Hu='Hurt:BAAALgAECgMJBAABLgAFFAQJDgAFANoMAA==.Huurs:BAAALgADCgEJAQAAAA==.',
If='Ifucmeurdead:BAAALgADCgcJBwAAAA==.',
In='Infernal:BAAALgADCgQJBAABLgADCgcJEgAJAAAAAA==.',
It='Itzli:BAABLgAECn8lAAIUAAkJ8yFcAgA8AgAUAAkJ8yFcAgA8AgABLgAFFAEJAQAJAAAAAA==.',
Iv='Ivee:BAAALgAECgcJBwABLgAFFAEJAQAJAAAAAA==.',
Ix='Ixtli:BAAALgAECgYJBwABLgAFFAEJAQAJAAAAAA==.',
Ja='Jaser:BAAALgAECgQJBAAAAA==.',
Je='Jedidave:BAAALgAECgMJAwAAAA==.Jellybeane:BAAALgAECgIJAwAAAA==.Jesdei:BAAALgAECgMJBgAAAA==.',
Jo='Jojen:BAABLgAECn8nAAMGAAgJrRewIwDJAQAGAAgJrRewIwDJAQAZAAQJ+AonRwCWAAAAAA==.Jonrai:BAAALgAECgEJAQAAAA==.',
Ju='Judgerrnut:BAAALgADCgMJAwAAAA==.',
Ka='Kaizer:BAAALgADCgEJAQAAAA==.Kalkri:BAAALgAECgIJAgAAAA==.Kasmin:BAAALgADCgEJAQAAAA==.Katrex:BAAALgAECgIJAwAAAA==.Kavix:BAABLgAECn8kAAIaAAgJmBb0JADgAQAaAAgJmBb0JADgAQAAAA==.Kayos:BAABLgAECn8oAAMWAAkJ+xR/KQDdAQAWAAkJLBR/KQDdAQAbAAcJUxNyHgDLAQAAAA==.',
Ke='Kefan:BAAALgADCgEJAQABLgAECgkJKAAWAPsUAA==.Kelzexx:BAABLgAECn8cAAIZAAcJtxMcJABUAQAZAAcJtxMcJABUAQAAAA==.',
Kh='Khalas:BAAALgADCgEJAwAAAA==.Khorne:BAABLgAECn8nAAILAAgJUAuEIADoAAALAAgJUAuEIADoAAAAAA==.',
Ki='Kiatus:BAAALgADCgEJAgAAAA==.Kimarah:BAAALgAFFAEJAQAAAA==.Kimed:BAAALgADCgkJCQAAAA==.Kissmyaxe:BAAALgADCgYJBgAAAA==.',
Km='Kmifeo:BAAALgADCgMJAwAAAA==.',
Ko='Koldor:BAAALgADCgEJAQAAAA==.Kortin:BAAALgADCgYJCwAAAA==.',
Kr='Krackdealer:BAAALgAECgEJAQAAAA==.Krelerokos:BAAALgADCgMJBAAAAA==.',
Ku='Kula:BAABLgAECn8XAAIFAAYJmgzwbgAIAQAFAAYJmgzwbgAIAQAAAA==.Kuroko:BAAALgADCgUJBgAAAA==.',
Kv='Kvnknight:BAAALgAECgIJAwAAAA==.',
Ky='Kylewithac:BAAALgAECgEJAQAAAA==.Kytes:BAAALgADCgUJBQABLgAECgkJMgAIAL4YAA==.',
La='Latro:BAACLgAFFH8OAAIFAAQJ2gwDJQAqAQAFAAQJ2gwDJQAqAQAuAAQKfyUAAwUACQkTHBEeAFECAAUACQkTHBEeAFECABQAAQkIBcqSACcAAAAA.',
Le='Leenex:BAAALgAECgYJCQAAAA==.Leginer:BAAALgAECgkJEgAAAA==.Legionflo:BAAALgAECgYJEAAAAA==.Lemiranas:BAAALgAECgEJAQAAAA==.Lepo:BAABLgAECn8fAAMNAAgJLQuDHABWAQANAAgJLQuDHABWAQAcAAEJWwSADwAqAAAAAA==.',
Lf='Lforeman:BAACLgAFFH8YAAIaAAQJ6xI9HQAXAQAaAAQJ6xI9HQAXAQAuAAQKfyYAAxoABwlwGeI3AMgBABoABwlwGeI3AMgBAB0AAQmNFepjADwAAAAA.',
Li='Liliith:BAAALgADCgYJDgAAAA==.Lilnative:BAAALgADCgYJCAAAAA==.',
Lo='Lochnessy:BAABLgAECn83AAMDAAkJ4hxsCQCCAgADAAkJ3hxsCQCCAgARAAgJmRIGDQAKAgAAAA==.',
Lu='Lunden:BAABLgAECn8kAAQdAAgJuBMZIwBXAQAeAAcJURTOEQBYAQAdAAgJRQ8ZIwBXAQAfAAUJzw+6GQDaAAAAAA==.Luvalee:BAAALgADCgcJCAAAAA==.',
['Lä']='Läzär:BAAALgADCgEJAQAAAA==.',
['Lë']='Lëësa:BAAALgADCgMJCQAAAA==.',
Ma='Mackob:BAAALgADCgQJBAAAAA==.Magdaz:BAAALgADCgEJAQAAAA==.Magnificence:BAABLgAECn8iAAIEAAgJ7QloFwARAQAEAAgJ7QloFwARAQAAAA==.Maldus:BAABLgAECn8qAAIZAAkJ8R4aBgC4AgAZAAkJ8R4aBgC4AgABLgAFFAEJAQAJAAAAAA==.Mallacath:BAABLgAECn8UAAIgAAgJhCG9BACUAgAgAAgJhCG9BACUAgAAAA==.Manapaw:BAAALgAECgcJCgAAAA==.Mandregosa:BAAALgAECgMJAwABLgAECgcJGQANANcdAA==.Marloak:BAAALgAECgQJBwAAAA==.Mazzkal:BAAALgAECgYJDAAAAA==.',
Mc='Mcbain:BAAALgADCgcJDAAAAA==.',
Me='Meekrob:BAAALgAECgEJAQABLgAFFAUJDQAIABsgAA==.Methot:BAAALgADCggJCQAAAA==.',
Mi='Mikeaevoevo:BAAALgADCgcJBwAAAA==.Milough:BAAALgAECgYJDAAAAA==.Mistii:BAAALgAECgYJBgAAAA==.Mizzbish:BAAALgADCgIJAgAAAA==.',
Mo='Moonchips:BAAALgADCgcJDAAAAA==.Morblodplez:BAAALgAECgcJDAAAAA==.Mortdavol:BAAALgAECgQJBAAAAA==.',
Mu='Mungus:BAAALgADCgYJBgAAAA==.Murtagh:BAAALgAECgEJAQABLgAECgIJAgAJAAAAAA==.',
My='Myhealsuck:BAAALgAECgEJAQAAAA==.',
Na='Nassaug:BAAALgADCgEJAgAAAA==.Nathali:BAAALgAECgEJAQAAAA==.Nattsu:BAAALgAECgQJBgAAAA==.',
Ne='Nex:BAAALgADCgkJCQAAAA==.',
Ni='Nicksamurai:BAABLgAECn8kAAIEAAgJlBNXDwB4AQAEAAgJlBNXDwB4AQAAAA==.Nightshadye:BAACLgAFFH8KAAILAAMJkQ2SGQCzAAALAAMJkQ2SGQCzAAAuAAQKfx4AAgsACAl0DR0dAGEBAAsACAl0DR0dAGEBAAAA.Nirazen:BAAALgADCgcJBwABLgAECggJJQAWAFsUAA==.',
No='Noches:BAAALgAECgIJAwAAAA==.Noi:BAABLgAECn8bAAIdAAYJIA5GOQDWAAAdAAYJIA5GOQDWAAAAAA==.',
Ny='Nymphoma:BAAALgAECgcJBwAAAA==.',
['Nì']='Nìghtblaze:BAAALgADCgUJBQAAAA==.',
Oc='Octobotic:BAACLgAFFH8QAAIIAAQJ1xfYLwBWAQAIAAQJ1xfYLwBWAQAuAAQKfyAAAggACAmxId0bAAcDAAgACAmxId0bAAcDAAAA.',
Om='Ombos:BAABLgAECn86AAMQAAkJQiEOAwDoAgAQAAkJQiEOAwDoAgADAAYJnBV5LQAvAQAAAA==.',
Or='Orenthal:BAAALgAECgYJEQAAAA==.Ortinchi:BAABLgAECn8ZAAICAAYJuwgiOADSAAACAAYJuwgiOADSAAAAAA==.',
Pa='Palapinga:BAAALgAECgEJAQAAAA==.Pandacakes:BAAALgAECgYJBwAAAA==.Pastureless:BAAALgADCgEJAQAAAA==.',
Ph='Phantom:BAAALgAECgcJDQAAAA==.Pheldor:BAAALgAECgYJCQABLgABCgMJAQAJAAAAAA==.Pheldorai:BAAALgAECggJDwABLgABCgMJAQAJAAAAAA==.Pheldrid:BAABLgAECn8cAAIGAAkJ+x81BgDTAgAGAAkJ+x81BgDTAgABLgABCgMJAQAJAAAAAA==.Phàntoms:BAABLgAECn8ZAAITAAYJoxeoDQAdAQATAAYJoxeoDQAdAQAAAA==.',
Pr='Protector:BAAALgAECgYJDgABLgAFFAQJDgAFANoMAA==.',
Pu='Puma:BAABLgAECn8bAAIeAAYJEA8sIgC8AAAeAAYJEA8sIgC8AAAAAA==.Puppyluv:BAAALgADCgEJAQAAAA==.Puregreen:BAAALgADCgQJBAAAAA==.Purpleme:BAAALgADCgEJAgAAAA==.',
Pv='Pve:BAAALgADCgcJBwAAAA==.',
['Pö']='Pöliwag:BAABLgAECn8VAAIfAAYJFg7rFgD6AAAfAAYJFg7rFgD6AAAAAA==.',
Qu='Quayle:BAAALgAECgQJBAABLgAECgYJEgAJAAAAAA==.',
Ra='Radiance:BAABLgAECn8nAAIDAAgJSyAOCwBmAgADAAgJSyAOCwBmAgAAAA==.Raevynn:BAACLgAFFH8HAAIGAAMJzgpkFgC6AAAGAAMJzgpkFgC6AAAuAAQKfxwAAgYACQk/DNk4AFgBAAYACQk/DNk4AFgBAAAA.Ragepioneer:BAAALgAECgQJBQAAAA==.Raiinzen:BAABLgAECn8iAAIBAAgJsR/4BwDBAgABAAgJsR/4BwDBAgAAAA==.Rajun:BAAALgAECgEJAwAAAA==.Rajvinder:BAAALgAECgQJBAAAAA==.Rascanthana:BAAALgAECgUJCAAAAA==.Rawrgrr:BAAALgAECgcJEwAAAA==.Razelda:BAAALgAECgYJCQAAAA==.Razelka:BAABLgAECn8eAAIVAAgJdBJ9IQCZAQAVAAgJdBJ9IQCZAQAAAA==.',
Re='Rekton:BAAALgAECgMJBAAAAA==.Remmulas:BAABLgAECn8kAAIIAAgJDhLoVACeAQAIAAgJDhLoVACeAQAAAA==.Repunzel:BAABLgAECn8ZAAIKAAYJlgZosgDPAAAKAAYJlgZosgDPAAAAAA==.',
Ri='Rippestrep:BAAALgADCgMJAwAAAA==.',
Ro='Rorky:BAABLgAECn8vAAIIAAkJ7hU3NgD/AQAIAAkJ7hU3NgD/AQAAAA==.Rozco:BAAALgAECgUJCwAAAA==.',
Ru='Rubmywolf:BAABLgAECn8bAAIFAAYJqxgVTgBfAQAFAAYJqxgVTgBfAQAAAA==.Rumtusk:BAAALgAECgYJCAABLgAECgkJLwAeACEgAA==.',
Sc='Scrapshot:BAAALgAFFAEJAQAAAA==.',
Se='Sephistia:BAAALgAECgYJBgAAAA==.Serina:BAABLgAECn8ZAAIFAAgJDQ20QwCAAQAFAAgJDQ20QwCAAQAAAA==.',
Sh='Shadefall:BAAALgADCgMJAwAAAA==.Shadowmisty:BAAALgADCgcJCQAAAA==.Shaelynn:BAAALgADCgEJAQAAAA==.Shammbulance:BAAALgAECgYJDAAAAA==.Shamrok:BAEALgAECgEJAgABLgAECgkJLwAEAC4KAA==.Shevah:BAABLgAECn8VAAIfAAgJjA/OEwAdAQAfAAgJjA/OEwAdAQAAAA==.Shivalry:BAAALgAECgQJBAAAAA==.Shyamalan:BAAALgAECgYJDgAAAA==.',
Si='Sid:BAACLgAFFH8NAAIIAAUJGyAcEwCAAQAIAAUJGyAcEwCAAQAuAAQKfygAAggACQm9I14VACgDAAgACQm9I14VACgDAAAA.Siege:BAAALgADCgcJBwAAAA==.Sinsation:BAAALgAECgYJEgAAAA==.',
Sk='Skagara:BAAALgADCgEJAQAAAA==.',
Sl='Slomo:BAAALgADCgEJAQAAAA==.',
Sn='Snaarf:BAAALgADCgMJAwAAAA==.Snowdrift:BAABLgAECn8yAAIIAAkJvhjlMQAQAgAIAAkJvhjlMQAQAgAAAA==.',
So='Sophié:BAAALgAECgYJCAABLgAFFAEJAQAJAAAAAA==.Souxie:BAAALgAECgIJAwAAAA==.',
St='Starlost:BAAALgADCgcJGwAAAA==.Starnova:BAAALgAECgUJBwAAAA==.Stãr:BAAALgAECgYJBgAAAA==.',
Su='Sud:BAAALgAFFAMJBAAAAA==.Suelock:BAABLgAECn8aAAIXAAYJuARnowC6AAAXAAYJuARnowC6AAAAAA==.Sugoikí:BAAALgADCggJCAAAAA==.',
Sy='Synapse:BAAALgAECgUJDAAAAA==.',
['Sô']='Sôulreaper:BAABLgAECn8aAAIHAAgJvRLvTACWAQAHAAgJvRLvTACWAQAAAA==.',
Ta='Taali:BAABLgAECn8bAAIKAAYJ4A2JjwAJAQAKAAYJ4A2JjwAJAQAAAA==.Tarrant:BAAALgAECgMJAwAAAA==.Tarv:BAABLgAECn8jAAIcAAgJogkwCQBDAQAcAAgJogkwCQBDAQAAAA==.',
Te='Teef:BAAALgAECgEJAQAAAA==.Teegobz:BAABLgAECn8sAAIUAAgJfhxJBgCjAQAUAAgJfhxJBgCjAQAAAA==.',
Th='Thankful:BAAALgADCgcJEgAAAA==.Thjazi:BAABLgAECn8lAAIYAAgJKBodFQDuAQAYAAgJKBodFQDuAQAAAA==.Thomasten:BAACLgAFFH8SAAMbAAUJ3yRXAgA8AQAbAAQJ3yRXAgA8AQAWAAUJhQlMOgDxAAAuAAQKfyUABBsACAk9Iz8TADwCABsACAmzID8TADwCABIABQnrIcsJAHgBABYAAQmDAYz2ABEAAAAA.Thomasthree:BAAALgAECgMJAwABLgAFFAUJEgAbAN8kAA==.Thormight:BAAALgADCgkJCwAAAA==.',
Ti='Tiaagra:BAAALgADCgYJBgAAAA==.',
To='Touching:BAAALgAECgUJBgABLgAECgYJDAAJAAAAAA==.',
Tr='Tranquil:BAAALgAECgYJCgABLgAFFAQJDgAFANoMAA==.Trazenser:BAAALgADCgUJBQAAAA==.Trent:BAABLgAECn8vAAIeAAkJISB8AgDRAgAeAAkJISB8AgDRAgAAAA==.Tricksibobby:BAABLgAECn8bAAMdAAYJTyAcFwDAAQAdAAYJTyAcFwDAAQAaAAYJDBd7OwBgAQAAAA==.',
Tu='Tuckinfank:BAAALgAECggJDwAAAA==.',
Ty='Tylèr:BAACLgAFFH8NAAIbAAQJORr7BAAIAQAbAAQJORr7BAAIAQAuAAQKfz8ABBsACQl+H+oDAMkCABsACQl+H+oDAMkCABIAAQmFFDojAD0AABYAAQk2DbvcADUAAAAA.',
Uj='Ujak:BAABLgAECn8fAAIhAAgJ2Q4hDQB1AQAhAAgJ2Q4hDQB1AQAAAA==.',
Um='Umami:BAABLgAECn8kAAIPAAgJkhUlKwC2AQAPAAgJkhUlKwC2AQAAAA==.',
Ur='Urielseptim:BAAALgADCgMJAwAAAA==.Urnothefathr:BAAALgADCgkJDwAAAA==.',
Va='Vanillacream:BAABLgAECn8kAAIFAAgJfRQYNQC3AQAFAAgJfRQYNQC3AQAAAA==.',
Vi='Viddar:BAABLgAECn8jAAISAAkJUx2bAgCIAgASAAkJUx2bAgCIAgAAAA==.Viroqua:BAACLgAFFH8PAAIZAAUJswv0EQAlAQAZAAUJswv0EQAlAQAuAAQKfzIAAhkACAkEGRAQAIUCABkACAkEGRAQAIUCAAAA.',
Vo='Volarious:BAAALgADCgYJBgAAAA==.Vorren:BAAALgADCgMJAwAAAA==.',
Wa='Wanderwho:BAAALgADCgQJBAAAAA==.Wavebringer:BAAALgADCgUJBgAAAA==.',
Wh='Whöever:BAAALgADCgMJAwAAAA==.',
Wi='Wildfire:BAAALgADCgcJBwAAAA==.Wileecyotie:BAAALgAECgQJAQABLgAECggJJQAWAFsUAA==.Winkelsmom:BAABLgAECn8dAAQdAAgJrhGyHgB5AQAdAAgJrhGyHgB5AQAaAAUJtwsIdwCPAAAfAAIJJQUJLwBPAAAAAA==.',
Wo='Woru:BAABLgAECn8aAAMPAAYJvRJtPwBQAQAPAAYJvRJtPwBQAQAhAAYJ7hdPEAA5AQAAAA==.',
Wr='Wrathofangus:BAAALgAECgYJCQAAAA==.',
Xa='Xarava:BAABLgAECn8kAAIPAAgJmRgTHQAOAgAPAAgJmRgTHQAOAgAAAA==.',
Yo='Yogisa:BAABLgAECn81AAMBAAkJOhXkEwAQAgABAAkJOhXkEwAQAgAMAAEJAAAojwAAAAAAAA==.',
Ys='Ysanova:BAABLgAECn8bAAIHAAYJEhdQaQBLAQAHAAYJEhdQaQBLAQAAAA==.',
Za='Zarkanna:BAAALgAECgUJCQAAAA==.',
Ze='Zenogias:BAABLgAECn8VAAIIAAYJSRIThAA1AQAIAAYJSRIThAA1AQAAAA==.',
Zy='Zymurg:BAAALgADCgIJAgAAAA==.',
['Æb']='Æbaddon:BAABLgAECn8nAAIiAAgJlCOSCQCuAgAiAAgJlCOSCQCuAgAAAA==.',
['Ðe']='Ðeimos:BAAALgADCgUJBQAAAA==.',
['ße']='ßenzyte:BAAALgAECgMJAwAAAA==.',
['ßu']='ßug:BAAALgAECgYJAwABLgAECgkJIwANAHkWAA==.',
['ßú']='ßúg:BAAALgAECgkJBwABLgAECgkJIwANAHkWAA==.',
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
