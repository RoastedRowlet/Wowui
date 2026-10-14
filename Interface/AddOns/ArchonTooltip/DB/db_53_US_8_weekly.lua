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

local lookup = {'Unknown-Unknown','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Arms','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Balance','Druid-Restoration','Druid-Feral','Mage-Arcane','DemonHunter-Havoc','Priest-Holy','Paladin-Retribution','Druid-Guardian','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','DemonHunter-Devourer','Hunter-Survival','Paladin-Protection','Priest-Shadow','Rogue-Assassination','Warlock-Affliction','Mage-Frost',}
local provider = {region='US',realm='AltarofStorms',name='US',type='weekly',zone=53,date='2026-10-13',data={Ad='Adiina:BAAANQADCgQIBQAAAA==.',
Ae='Aelera:BAAANQADCgMIAwAAAA==.',
Ah='Ahnkoh:BAAANQADCgYICQAAAA==.',
Ak='Ak:BAAANQADCgUIDQABNQABCgEIAQABAAAAAA==.',
Al='Alcool:BAAANQAECgMIAwAAAA==.Alindril:BAABNQAECn8mAAICAAgK/AsydwCvAQACAAgK/AsydwCvAQAAAA==.Alistarfall:BAAANQADCgcICQABNQAECgkJHwADAAgPAA==.Alledra:BAAANQABCggICwAAAA==.Alyriana:BAABNQAECn8pAAQEAAkKdRIjEQBVAgAEAAkKXBEjEQBVAgADAAQKBA8i4QDPAAAFAAQKxwXw4wCdAAAAAA==.',
Am='Amiyo:BAAANQAECgEIAQAAAA==.',
Ar='Arylis:BAAANQADCgMIAwAAAA==.',
As='Asalamalikum:BAAANQAECgEIAQABNQAFFAQICQAGAKwhAA==.Ashfallen:BAAANQAECgEIAgAAAA==.',
At='Atthegates:BAABNQAECn8hAAIHAAkKoBDLggARAgAHAAkKoBDLggARAgAAAA==.',
Az='Azrel:BAAANQAECgYIBgAAAA==.',
Ba='Bachira:BAAANQADCgMIAwAAAA==.Baddragon:BAACNQAFFH8QAAQIAAYKKhAYCAC6AQAIAAYKKhAYCAC6AQAJAAMKiBWACADsAAAKAAIKUBrJCACdAAA1AAQKfyMABAkACQqfJOEEAEcDAAkACQqfJOEEAEcDAAgABQrHDwYwABoBAAoAAwptHysVANoAAAAA.Balboo:BAAANQAECgYIBgABNQAFFAcIEwALAMIYAA==.Balto:BAACNQAFFH8TAAMLAAcKwhgeBwAXAgALAAYKXh4eBwAXAgAMAAMKgxFjCwAIAQA1AAQKfzUABAsACQoCJlADAMkDAAsACQoCJlADAMkDAA0AAwpmJZsbAEYBAAwABApsEutGAPUAAAAA.Bayleef:BAABNQAECn8mAAIMAAkKuxzPDgDkAgAMAAkKuxzPDgDkAgAAAA==.',
Bd='Bdragon:BAAANQADCgUIBQAAAA==.',
Be='Belac:BAABNQAECn8dAAIHAAkKwg/tiQD/AQAHAAkKwg/tiQD/AQAAAA==.Bemillion:BAAANQABCgIIAgAAAA==.Bettyboom:BAABNQAECn8lAAIOAAgKzhakpQA1AgAOAAgKzhakpQA1AgABNQABCgMIAwABAAAAAA==.',
Br='Brewlaw:BAAANQADCgMIAwAAAA==.Brujita:BAAANQADCgIIAgAAAA==.Brèè:BAABNQAECn8uAAIPAAkKfyAxDwAmAwAPAAkKfyAxDwAmAwAAAA==.',
Bu='Bunny:BAABNQAECn8YAAIQAAgKOQ0kdQC4AQAQAAgKOQ0kdQC4AQAAAA==.',
Ca='Caelith:BAABNQAECn8uAAIOAAgK1RCyvAAJAgAOAAgK1RCyvAAJAgAAAA==.Calrinara:BAAANQADCggIFgAAAA==.Cause:BAAANQAECgUIEQABNQAECgUIFQAOAP8XAA==.',
Cl='Cl:BAAANQAECgEJAQABNQAECgkJHQAHAMIPAA==.',
Co='Conall:BAACNQAFFH8GAAIRAAMKQgnqGgDLAAARAAMKQgnqGgDLAAA1AAQKfyAAAxEACQrtFydjAG0CABEACQrtFydjAG0CAAIAAQq/AbUsAScAAAAA.Confetti:BAAANQAECgcIEgAAAA==.',
Da='Daiquiri:BAAANQADCgUIBQABNQAECgcIEgABAAAAAA==.Dajova:BAAANQAECgcIBwAAAA==.Darling:BAAANQADCgIIAgAAAA==.',
Dd='Ddofpain:BAAANQADCgIIAgAAAA==.',
De='Deadmawheals:BAABNQAECn8VAAMLAAkKYg8PRADfAQALAAgKYg8PRADfAQASAAEKAAAlZwAkAAAAAA==.Deathblooms:BAABNQAFFH8HAAIGAAYKChLYCwCTAQAGAAYKChLYCwCTAQAAAA==.Dermo:BAAANQAECgEIAQAAAA==.',
Di='Dimfate:BAAANQABCgYIBgAAAA==.',
Dm='Dmaw:BAABNQAECn8XAAQTAAcKCg7xOwAwAQATAAYKCg7xOwAwAQAUAAUKOBCALAADAQAVAAUKdguFIADbAAAAAA==.',
Do='Doublmisting:BAAANQADCggICAAAAA==.',
Dr='Drarkbull:BAAANQAECgYICwAAAA==.Dreki:BAAANQADCgYIBgAAAA==.Drizzitt:BAAANQAECgEIAQAAAA==.',
Dy='Dyspeptic:BAAANQAECgIIAgABNQAFFAIICAARAK4KAA==.',
['Dó']='Dónkey:BAAANQADCggICAAAAA==.',
Eh='Ehunter:BAAANQADCgIIAgAAAA==.',
El='Electro:BAAANQAECgQIEAABNQAECgUIFQAOAP8XAA==.Elementtamer:BAAANQADCgMIAwAAAA==.',
Es='Esh:BAABNQAECn8YAAMWAAkKfSJrGAAkAwAWAAgKhCFrGAAkAwAXAAIKQCWzOADdAAAAAA==.',
Ev='Evildarkness:BAAANQADCggICAAAAA==.Evilemt:BAAANQADCggICwAAAA==.Evilmt:BAAANQADCgYIBwAAAA==.',
Fe='Fenlok:BAAANQADCgUIBQAAAA==.',
Fi='Firiana:BAAANQAECgUICQAAAA==.',
Fr='Frogsbreath:BAAANQADCgUIBQAAAA==.',
Ga='Galdrel:BAAANQADCgYIBwAAAA==.',
Gr='Grimoire:BAAANQAECgIIAgAAAA==.',
Gu='Gullar:BAAANQAECgEIAQAAAA==.Guzzug:BAAANQADCgUIBQABNQAECgcIEwABAAAAAA==.',
Ha='Hallsblack:BAAANQADCgIIAgAAAA==.Harami:BAAANQAECgEIAQABNQAECggIAwABAAAAAA==.Hartplate:BAAANQABCgUIBQAAAA==.Haymaker:BAAANQAECgcIEwAAAA==.',
He='Heide:BAAANQAECgcICwAAAA==.',
Hi='Hizø:BAAANQAECgQIBQAAAA==.',
Ho='Ho:BAAANQAECgMIAwAAAA==.Hordeelf:BAAANQAECgIJAgAAAA==.Hordeforsure:BAACNQAFFH8PAAMYAAcKMxW3CwB+AQAYAAUKkxW3CwB+AQAZAAIKoRSeIgCmAAA1AAQKfyQAAxgACQqKJaUGAGQDABgACQqKJaUGAGQDABkAAwrPIqESAdcAAAE1AAQKAgkCAAEAAAAA.',
Hu='Humanwolf:BAAANQADCgMIBQAAAA==.',
In='Inovar:BAACNQAFFH8JAAIWAAMKLB1iHgACAQAWAAMKLB1iHgACAQA1AAQKfy4AAxYACQryI1IVADMDABYACQryI1IVADMDABcAAQonI11hAGEAAAAA.',
Iz='Izugzug:BAACNQAFFH8JAAMGAAQKrCGUDgBlAQAGAAQKrCGUDgBlAQAaAAEKhwiWHwA9AAA1AAQKfycAAwYACQp1JCcIAHoDAAYACQp1JCcIAHoDABsABgoMEG99ACIBAAAA.',
Jo='Joolam:BAAANQADCgQIBAAAAA==.',
Ju='Julibean:BAAANQAECgQIBAAAAA==.',
Jx='Jxyy:BAAANQADCgUIBQABNQAFFAQKCwAZAGEbAA==.',
Ka='Kaminey:BAAANQAECggIAwAAAA==.Karizev:BAAANQADCggICAAAAA==.',
Ke='Kekson:BAAANQAECgUIBQAAAA==.Keyoshe:BAAANQADCgEIAQAAAA==.',
Kh='Kheliyah:BAAANQAECgYIDgAAAA==.',
Ki='Kickinugget:BAAANQAECggICwAAAA==.',
Ko='Korrkil:BAAANQADCgUIBQAAAA==.',
La='Lanthrastus:BAAANQAECgIIAgAAAA==.Largecaliber:BAAANQADCggICAAAAA==.',
Li='Liability:BAAANQADCgEIAQAAAA==.Lilac:BAAANQADCgIIAgAAAA==.Lirria:BAAANQABCgMIAwAAAA==.Lisanalgaib:BAABNQAECn8qAAIcAAkKxhBQDAD/AQAcAAkKxhBQDAD/AQAAAA==.',
Ly='Lynxxy:BAAANQAECgEIAQAAAA==.',
Ma='Magital:BAAANQAECgcIDgABNQAECgkJJAAdALEZAA==.Magnetic:BAAANQAECgIIAwABNQAECgUIFQAOAP8XAA==.Manalorian:BAAANQADCgQIBAAAAA==.',
Me='Medalea:BAAANQABCgIIAgAAAA==.Menethel:BAAANQAECgYICgAAAA==.Meowjin:BAAANQADCggICAAAAA==.Meudail:BAAANQADCgIIAgAAAA==.',
Mi='Miah:BAAANQADCgEIAQAAAA==.Miasmata:BAABNQAECn8hAAIaAAgKdRuxJgBcAgAaAAgKdRuxJgBcAgAAAA==.Mikeoxlongg:BAAANQAECgEIAQABNQAECgcIDQABAAAAAA==.',
Mo='Mordaut:BAABNQAECn8VAAIOAAYKIB9SxgD2AQAOAAYKIB9SxgD2AQAAAA==.Morts:BAABNQAECn8gAAIFAAgKgxrDRQBHAgAFAAgKgxrDRQBHAgAAAA==.',
Mu='Muzuki:BAAANQAECgEIAQAAAA==.',
My='Mylaw:BAAANQADCgQIBAAAAA==.',
Na='Nabi:BAAANQAECgYIEAABNQAECgUICgABAAAAAA==.Naianasha:BAABNQAECn8fAAIKAAgKzwgpDgBiAQAKAAgKzwgpDgBiAQAAAA==.',
Ne='Neris:BAABNQAECn8dAAMMAAkKzRGrIwAEAgAMAAkKzRGrIwAEAgALAAMKSwqAlACAAAABNQAFFAMICQAWACwdAA==.',
No='Noggenkarl:BAAANQAECgYIBgABNQAECgYICgABAAAAAA==.Nosfyrakktu:BAAANQAECgUICQABNQAECgkJHwADAAgPAA==.',
Nu='Nun:BAAANQAECgEIAQAAAA==.',
Ob='Obscur:BAAANQAECgcIDQAAAA==.',
On='Onepiece:BAAANQADCgEIAQABNQAFFAcIEwALAMIYAA==.',
Os='Osti:BAABNQAECn8sAAIeAAkKnyLvAACFAwAeAAkKnyLvAACFAwABNQAFFAIIBQATAPUaAA==.',
Pa='Pahine:BAAANQAECgcIEgABNQAECggIAwABAAAAAA==.Pallywackèr:BAAANQAECgEIAQAAAA==.',
Pe='Pepedin:BAABNQAECn8aAAMfAAgKQQ/JOAAiAQARAAcKVA5RywB+AQAfAAYKAw7JOAAiAQAAAA==.',
Ph='Phantoma:BAAANQADCgYIBgAAAA==.',
Pn='Pnkrweb:BAAANQAECgYIEQAAAA==.',
Po='Popshot:BAAANQAECgMIBAAAAA==.',
Pr='Profit:BAABNQAECn8qAAMQAAgKDx9zJQDTAgAQAAgKDx9zJQDTAgAgAAYKmRp9LAC+AQAAAA==.',
Pu='Punduh:BAABNQAECn8wAAIUAAkK1h80BwAfAwAUAAkK1h80BwAfAwAAAA==.',
Ra='Rabbidtotem:BAABNQAECn8XAAMDAAgKThkJTABDAgADAAgKThkJTABDAgAFAAEKnAV7GAE1AAAAAA==.Rainquis:BAAANQABCgIIAgAAAA==.Rajabra:BAABNQAECn8fAAIhAAgKUyC+FgDCAgAhAAgKUyC+FgDCAgAAAA==.Rasoon:BAAANQADCgYIBgAAAA==.Raveroller:BAAANQAECgYIBgAAAA==.',
Re='Redryder:BAAANQAECgQIBgAAAA==.Reevoke:BAABNQAFFH8KAAIJAAcKZxWaAQAtAgAJAAcKZxWaAQAtAgAAAA==.Reighven:BAAANQAECggIDwABNQAFFAQICQAGAKwhAA==.Rekson:BAAANQAECgcIDwAAAA==.',
Rh='Rhyderlight:BAAANQAECgIIAgAAAA==.Rhythm:BAABNQAECn8VAAIOAAUK/xd2FQFlAQAOAAUK/xd2FQFlAQAAAA==.',
Ro='Rola:BAAANQADCgQIBAAAAA==.Rolla:BAAANQADCggICAAAAA==.Romolus:BAAANQADCgYIBgAAAA==.',
Ru='Ruddertrim:BAABNQAECn8bAAMZAAkKkRcJXwBXAgAZAAgKNxkJXwBXAgAYAAcKaQ9zOACIAQAAAA==.',
Sa='Sadist:BAAANQABCgIIAgAAAA==.Salinedione:BAAANQAECgQICgAAAA==.Sargeruas:BAAANQAECgEIAQAAAA==.',
Sc='Scottiiee:BAAANQADCgcIDQAAAA==.Scratch:BAAANQADCgUIBQAAAA==.',
Se='Segen:BAAANQAECgcIEwAAAA==.Semip:BAAANQAECgIIAwAAAA==.Sen:BAABNQAECn8aAAMYAAkKgBYSIQBCAgAYAAkKExQSIQBCAgAZAAUKUBkM1ABTAQAAAA==.',
Sg='Sgttapeworm:BAAANQADCgEIAQAAAA==.',
Sh='Shacewoman:BAAANQAECgIIAgAAAA==.Shaitan:BAAANQADCgEIAQABNQAECggIAwABAAAAAA==.Sheeple:BAAANQADCgYIBgAAAA==.Shîver:BAAANQAECgcICwAAAA==.',
Si='Sidearm:BAAANQAECgQIBAAAAA==.Silvane:BAAANQAECgMIAwAAAA==.',
Sk='Skaadooshh:BAAANQADCgUJCQABNQAFFAQICQAGAKwhAA==.',
Sl='Slayèr:BAAANQADCgYIBgAAAA==.',
Sn='Snaptraphunt:BAAANQADCgIIAgAAAA==.Snipedyou:BAAANQADCggIEgAAAA==.',
So='Sophie:BAAANQADCgIIAgAAAA==.',
St='Staberella:BAAANQADCgMIAwAAAA==.Stache:BAAANQAECgYIDgAAAA==.Stevethuzad:BAAANQAECgIIAgABNQAECgcIEwABAAAAAA==.Stevo:BAAANQADCgYIDQAAAA==.Stormydaniel:BAAANQAECgcICQAAAA==.',
Sy='Synikal:BAABNQAECn8lAAIFAAgKTxDveACdAQAFAAgKTxDveACdAQAAAA==.',
['Sâ']='Sâuron:BAAANQABCgcJCQAAAA==.',
['Sæ']='Sæ:BAAANQAECgIIAwAAAA==.',
Ta='Taleiran:BAABNQAECn8kAAIdAAkKsRn2GACRAgAdAAkKsRn2GACRAgAAAA==.',
Th='Thdro:BAAANQADCgYIBgAAAA==.Threeofseven:BAAANQADCgcICAAAAA==.Thrøat:BAABNQAECn8hAAIGAAgKUSDkGgDVAgAGAAgKUSDkGgDVAgAAAA==.',
Ti='Tiberiius:BAABNQAECn8cAAMZAAkK7R3BRgCVAgAZAAgK7R3BRgCVAgAYAAUKIRY2QwA4AQAAAA==.Tilly:BAABNQAECn8YAAIPAAcKuRUyOgDeAQAPAAcKuRUyOgDeAQAAAA==.Titus:BAAANQAECgYICQAAAA==.',
To='Toes:BAAANQADCgIIAgAAAA==.',
Tr='Trigodun:BAAANQADCgYIBgAAAA==.',
Un='Undeadlysoul:BAABNQAECn8kAAQiAAgK3x1eCgDQAQAWAAgKHB3VUwBWAgAiAAYKnx1eCgDQAQAXAAEKbhv9aQBMAAAAAA==.Undedagaindk:BAACNQAFFH8bAAMbAAcKUCL4AQAyAgAbAAYKUCL4AQAyAgAGAAEKAADYOQAdAAA1AAQKfzEAAxsACQo9JmsJAHIDABsACQo9JmsJAHIDAAYAAQq+JZGuAGsAAAAA.',
Up='Uppercut:BAAANQAECgUIBgAAAA==.',
Us='Ussford:BAABNQAECn8gAAQUAAcK4g4hJQBNAQAUAAYK7hAhJQBNAQAVAAYKZAbbJACmAAATAAQKPwC2fwAEAAAAAA==.Ussorlando:BAABNQAECn8lAAIWAAkKLRbkLQDMAgAWAAkKLRbkLQDMAgAAAA==.',
Va='Valaw:BAAANQADCggIEQAAAA==.Valgprincess:BAAANQADCgUIBQAAAA==.',
Vi='Vincentius:BAAANQAECgcIEgAAAA==.',
Vo='Voidflame:BAAANQAECgQICAAAAA==.Volteil:BAAANQADCgYIBgAAAA==.',
Vu='Vuori:BAAANQAECgUIDgAAAA==.',
Wa='Warstomp:BAAANQAECgMIBAAAAA==.',
We='Wetdog:BAAANQADCgIIAgABNQAFFAcIEwALAMIYAA==.',
Wh='Whixx:BAAANQAECgUIEQABNQAECgcICwABAAAAAA==.',
Wi='Wikm:BAAANQAECgUIBgAAAA==.Will:BAAANQAECgQIBAABNQAFFAMICQAjALobAA==.',
Xn='Xnaisa:BAABNQAECn8aAAIFAAkKLR+cFAAnAwAFAAkKLR+cFAAnAwAAAA==.',
Xp='Xplosive:BAAANQADCgMIAwABNQAECgQIBgABAAAAAA==.',
Ys='Yshaarj:BAAANQADCgYICgABNQAECgcIEgABAAAAAA==.',
Za='Zale:BAAANQAECgEIAQAAAA==.Zapey:BAAANQAECgcICwAAAA==.',
Ze='Zerude:BAABNQAECn8mAAIIAAkKCxP7FwA6AgAIAAkKCxP7FwA6AgAAAA==.',
Zm='Zmr:BAABNQAECn8aAAMFAAgKhx0WOQB4AgAFAAgKhx0WOQB4AgADAAUKcx7aiACKAQAAAA==.Zmrr:BAAANQADCgIJAgABNQAECggIGgAFAIcdAA==.',
['Çh']='Çhris:BAAANQADCggIFQAAAA==.',
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
